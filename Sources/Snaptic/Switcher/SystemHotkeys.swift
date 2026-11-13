import Foundation
import SnapticKit

/// The app side of Kit `SystemHotkeyLedger` (PLAN 0.5 §4.12; X2-3, X3-2): the two defaults lists, the take under the
/// full contract, and the give-back under its own marker. Used from `SystemHotkeys` on main only.
private final class DefaultsHotkeyPort: SystemHotkeyPort {
    private var giveBackMarked = false

    func savedIDs() -> [Int]? { UserDefaults.standard.array(forKey: CrashGuard.savedListKey) as? [Int] }
    func setSavedIDs(_ ids: [Int]) { UserDefaults.standard.set(ids, forKey: CrashGuard.savedListKey) }
    func removeSavedIDs() { UserDefaults.standard.removeObject(forKey: CrashGuard.savedListKey) }
    func pendingIDs() -> [Int]? { UserDefaults.standard.array(forKey: CrashGuard.pendingGiveBackKey) as? [Int] }
    func setPendingIDs(_ ids: [Int]) { UserDefaults.standard.set(ids, forKey: CrashGuard.pendingGiveBackKey) }
    func removePendingIDs() { UserDefaults.standard.removeObject(forKey: CrashGuard.pendingGiveBackKey) }
    func isEnabled(_ id: Int32) -> Bool? { PrivateWindowAPI.isSymbolicHotKeyEnabled(id) }
    func take(_ id: Int32) -> Bool { PrivateWindowAPI.takeSymbolicHotKey(id) }
    func beginGiveBack() { giveBackMarked = PrivateWindowAPI.beginGiveBack() }
    func giveBack(_ id: Int32) { PrivateWindowAPI.giveBackSymbolicHotKey(id) }

    func endGiveBack() {
        PrivateWindowAPI.endGiveBack(giveBackMarked)
        giveBackMarked = false
    }

    func guardHolds(_ ids: Set<Int32>) { HotkeyGuard.shared.setDisabled(ids) }
}

/// Disables macOS's own ⌘⇥ / ⌘` while a Snaptic shortcut uses them and gives
/// them back afterwards. Which ones Snaptic disabled is saved to disk first, so
/// a crash or force-quit is repaired on the next launch, and shortcuts the
/// user turned off themselves are never touched. The rules are Kit's `SystemHotkeyLedger`.
@MainActor
enum SystemHotkeys {
    private static let ledger = SystemHotkeyLedger(port: DefaultsHotkeyPort())
    /// The kill switch is read every fourth beat (2 s) while Snaptic holds an id.
    private static var beats = 0

    /// Whether the take's kill switch, crash guard, poison or availability says no. Reads the kill switches.
    private static var takeBlocked: Bool {
        PrivateWindowAPI.readKillSwitches()
        return !PrivateWindowAPI.canTakeSymbolicHotKeys()
    }

    /// Launch step 4, after step 3b: gives back what a previous run left off, or, when the give-back's crash guard
    /// tripped on this build, moves that list to `Windows.pendingGiveBack`.
    static func atLaunch() {
        let result = ledger.atLaunch(giveBackDisabled: InflightMarkers.isDisabled(CrashGuard.giveBackMarker))
        if case .movedToPending = result {
            EventLog.shared.record(.safety, "windows.giveBack pending until Try Again or the next macOS build")
        }
    }

    static func apply(_ shortcuts: [Shortcut]) {
        let wanted = SystemHotkeyLedger.wanted(
            commandTab: shortcuts.contains { $0.modifier == .command && $0.keyCode == KeyCode.tab },
            commandBacktick: shortcuts.contains { $0.modifier == .command && $0.keyCode == KeyCode.backtick })
        ledger.apply(wanted, takeBlocked: takeBlocked)
    }

    /// Takes the shortcuts back after the hang guard released them.
    static func reassert() {
        ledger.reassert(takeBlocked: takeBlocked)
    }

    /// Hands the shortcuts back to macOS while Snaptic can't see key presses.
    static func setSuspended(_ value: Bool) {
        guard value != ledger.suspended else { return }
        ledger.setSuspended(value, takeBlocked: value ? false : takeBlocked)
    }

    /// Gives every shortcut back (quit, or the switcher module stopping). Idempotent.
    static func restore() {
        ledger.restore()
    }

    /// Each host heartbeat: the take's kill switch turning on while Snaptic holds an id gives every id back (H6).
    static func heartbeat() {
        guard !ledger.owned.isEmpty else {
            beats = 0
            return
        }
        beats += 1
        guard beats % 4 == 0 else { return }
        if PrivateWindowAPI.readKillSwitches().contains(.symbolicHotKeys) { ledger.restore() }
    }

    /// The "⌘⇥ not given back" row's Try Again (G3-2): clears the give-back's disabled build and gives the pending
    /// list back now.
    static func tryAgainGiveBack() {
        UserDefaults.standard.removeObject(forKey: CrashGuard.giveBackTryAgainKey)
        _ = ledger.giveBackPendingNow()
    }
}

/// A thread-safe safety net for ⌘⇥. The main thread checks in regularly; if it
/// stops (a hang), a background timer gives the built-in shortcuts back to
/// macOS so the user is never left without ⌘⇥. Also used from signal handlers.
final class HotkeyGuard: @unchecked Sendable {
    static let shared = HotkeyGuard()

    private let lock = NSLock()
    private var disabled = Set<Int32>()
    private var lastBeat = DispatchTime.now().uptimeNanoseconds
    private var tripped = false
    private var timer: DispatchSourceTimer?

    /// The shortcuts Snaptic currently has switched off.
    func setDisabled(_ ids: Set<Int32>) {
        lock.lock()
        disabled = ids
        lock.unlock()
    }

    /// Called from the main thread. Returns true if the guard had to step in
    /// since the last beat, so the caller can take the shortcuts back over.
    func beat() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        lastBeat = DispatchTime.now().uptimeNanoseconds
        let wasTripped = tripped
        tripped = false
        return wasTripped
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 2, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    private func check() {
        lock.lock()
        let stale = Double(DispatchTime.now().uptimeNanoseconds &- lastBeat) / 1_000_000_000 > 1.5
        let ids = disabled
        let trip = stale && !tripped && !ids.isEmpty
        if trip { tripped = true }
        lock.unlock()
        if trip { giveBack(ids) }
    }

    /// Gives every shortcut back right away, from any thread, under the give-back marker.
    func releaseAll() {
        lock.lock()
        let ids = disabled
        disabled = []
        lock.unlock()
        giveBack(ids)
    }

    /// The signal handler's give-back: pre-resolved pointers, no marker, no defaults (D2-11).
    func releaseAllFromSignal() {
        lock.lock()
        let ids = disabled
        disabled = []
        lock.unlock()
        for id in ids.sorted() { PrivateWindowAPI.giveBackFromSignal(id) }
    }

    private func giveBack(_ ids: Set<Int32>) {
        guard !ids.isEmpty else { return }
        let marked = PrivateWindowAPI.beginGiveBack()
        for id in ids.sorted() { PrivateWindowAPI.giveBackSymbolicHotKey(id) }
        PrivateWindowAPI.endGiveBack(marked)
    }
}
