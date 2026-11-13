import Foundation

/// Disables macOS's own ⌘⇥ / ⌘` while a Snaptic shortcut uses them and gives
/// them back afterwards. Which ones Snaptic disabled is saved to disk first, so
/// a crash or force-quit is repaired on the next launch, and shortcuts the
/// user turned off themselves are never touched.
@MainActor
enum SystemHotkeys {
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2
    private static let commandKeyAboveTab: Int32 = 6
    private static let defaultsKey = "SnapticDisabledSystemHotkeys"
    private static let managed: Set<Int32> = [1, 2, 6]

    private static var disabledBySnaptic = Set<Int32>()
    private static var suspended = false

    /// Re-enables anything a previous run disabled but never restored.
    static func recoverFromPreviousRun() {
        let leftover = (UserDefaults.standard.array(forKey: defaultsKey) as? [Int]) ?? []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        // Only ever touch the three shortcuts Snaptic manages, whatever the file says.
        for value in leftover {
            guard let id = Int32(exactly: value), managed.contains(id) else { continue }
            PrivateWindowAPI.setSymbolicHotKey(id, enabled: true)
        }
    }

    static func apply(_ shortcuts: [Shortcut]) {
        var wanted = Set<Int32>()
        if shortcuts.contains(where: { $0.modifier == .command && $0.keyCode == KeyCode.tab }) {
            wanted.formUnion([commandTab, commandShiftTab])
        }
        if shortcuts.contains(where: { $0.modifier == .command && $0.keyCode == KeyCode.backtick }) {
            wanted.insert(commandKeyAboveTab)
        }
        // A shortcut the user already switched off in System Settings is left
        // alone, so Snaptic never turns it back on later.
        wanted = wanted.filter { disabledBySnaptic.contains($0) || PrivateWindowAPI.isSymbolicHotKeyEnabled($0) != false }

        // Persist before touching the system so a crash mid-way is recoverable.
        let everDisabled = disabledBySnaptic.union(wanted)
        UserDefaults.standard.set(everDisabled.map { Int($0) }, forKey: defaultsKey)

        for id in disabledBySnaptic.subtracting(wanted) {
            PrivateWindowAPI.setSymbolicHotKey(id, enabled: true)
        }
        if !suspended {
            for id in wanted {
                PrivateWindowAPI.setSymbolicHotKey(id, enabled: false)
            }
        }
        disabledBySnaptic = wanted
        UserDefaults.standard.set(wanted.map { Int($0) }, forKey: defaultsKey)
        HotkeyGuard.shared.setDisabled(suspended ? [] : wanted)
    }

    /// Takes the shortcuts back after the hang guard released them.
    static func reassert() {
        guard !suspended else { return }
        for id in disabledBySnaptic {
            PrivateWindowAPI.setSymbolicHotKey(id, enabled: false)
        }
        HotkeyGuard.shared.setDisabled(disabledBySnaptic)
    }

    /// Hands the shortcuts back to macOS while Snaptic can't see key presses.
    static func setSuspended(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value
        for id in disabledBySnaptic {
            PrivateWindowAPI.setSymbolicHotKey(id, enabled: value)
        }
        HotkeyGuard.shared.setDisabled(value ? [] : disabledBySnaptic)
    }

    /// Gives every shortcut back (quit, or the switcher module stopping). Idempotent.
    static func restore() {
        suspended = false
        guard !disabledBySnaptic.isEmpty else { return }
        for id in disabledBySnaptic {
            PrivateWindowAPI.setSymbolicHotKey(id, enabled: true)
        }
        disabledBySnaptic = []
        HotkeyGuard.shared.setDisabled([])
        UserDefaults.standard.removeObject(forKey: defaultsKey)
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
        if trip {
            for id in ids { PrivateWindowAPI.setSymbolicHotKey(id, enabled: true) }
        }
    }

    /// Gives every shortcut back right away, from any thread.
    func releaseAll() {
        lock.lock()
        let ids = disabled
        disabled = []
        lock.unlock()
        for id in ids { PrivateWindowAPI.setSymbolicHotKey(id, enabled: true) }
    }
}
