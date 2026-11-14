import Foundation

// The window symbols' crash guard (lead; PLAN 0.5 §4.12 step 6, H3, H6; X2-3, X2-4, X3-2, X3-8; B1b): the marker and
// defaults names, the launch rule, when a call writes its marker, the in-flight ledger, and the ⌘⇥ take and
// give-back ledger. `Windows/InflightMarkers.swift` writes the files; `Switcher/SystemHotkeys.swift` is the port.

package enum CrashGuard {
    /// Read-only symbols stop writing markers after this many successes on a verified OS build (X2-4).
    package static let verifyAfterSuccesses = 20
    /// The ⌘⇥ give-back's own marker and disabled build, apart from the take's (X2-3).
    package static let giveBackMarker = "symbolicHotKeys.giveBack"
    /// The list a disabled give-back leaves for Try Again or the next OS build (X3-2).
    package static let pendingGiveBackKey = "Windows.pendingGiveBack"
    /// 0.4's saved list of the ⌘⇥ ids Snaptic turned off.
    package static let savedListKey = "SnapticDisabledSystemHotkeys"

    package static func disabledKey(_ marker: String) -> String { "Windows.disabledBuild." + marker }
    package static func verifiedKey(_ marker: String) -> String { "Windows.verifiedBuild." + marker }
    package static func probedKey(_ marker: String) -> String { "Windows.probedBuild." + marker }

    /// Every marker name: one per symbol, then the give-back.
    package static var markerNames: [String] { WindowSymbolID.allCases.map(\.rawValue) + [giveBackMarker] }

    package struct LaunchDecision: Equatable, Sendable {
        /// Markers whose disabled build is now this build (sorted).
        package var disable: [String]
        /// Every file found, known or not: all are removed either way (sorted).
        package var remove: [String]

        package init(disable: [String], remove: [String]) {
            self.disable = disable
            self.remove = remove
        }
    }

    /// Launch step 3b (X2-3, X3-8). A marker counts only when it names a known symbol, holds this OS build, and the
    /// previous run didn't quit cleanly. `markers` maps each file name to its content (nil: unreadable).
    package static func atLaunch(markers: [String: String?], currentBuild: String,
                                 previousRunCleanQuit: Bool) -> LaunchDecision {
        let known = Set(markerNames)
        var disable: [String] = []
        if !previousRunCleanQuit && !currentBuild.isEmpty {
            for (name, content) in markers where known.contains(name) {
                if let content, content.trimmingCharacters(in: .whitespacesAndNewlines) == currentBuild {
                    disable.append(name)
                }
            }
        }
        return LaunchDecision(disable: disable.sorted(), remove: markers.keys.sorted())
    }

    /// The previous run's clean quit, from `SnapticLaunchHistoryV1` read before this launch is recorded. No history
    /// means no previous run, so nothing it left can count.
    package static func previousRunCleanQuit(_ history: LaunchHistory) -> Bool {
        history.records.last?.cleanQuit ?? true
    }

    package static func isDisabled(disabledBuild: String?, currentBuild: String) -> Bool {
        !currentBuild.isEmpty && disabledBuild == currentBuild
    }

    /// Whether this call writes its marker: always, except a read-only symbol verified on this build (X2-4).
    package static func needsMarker(_ id: WindowSymbolID, verifiedBuild: String?, currentBuild: String) -> Bool {
        !(id.readOnly && !currentBuild.isEmpty && verifiedBuild == currentBuild)
    }

    /// Write `verifiedBuild` once: a read-only symbol, 20 successes, on a verified major (never elsewhere, X3-1).
    package static func shouldMarkVerified(_ id: WindowSymbolID, successes: Int, major: Int,
                                           alreadyVerified: Bool) -> Bool {
        id.readOnly && !alreadyVerified && successes >= verifyAfterSuccesses && WindowOSGate.isVerified(major: major)
    }

    /// A feature row's Try Again clears that feature's disabled builds only; the give-back's stays (G3-2).
    package static func tryAgainKeys(_ feature: WindowFeature) -> [String] {
        WindowSymbolID.symbols(for: feature).map { disabledKey($0.rawValue) }
    }

    /// The "⌘⇥ not given back" row's Try Again clears this one only.
    package static var giveBackTryAgainKey: String { disabledKey(giveBackMarker) }
}

// MARK: In-flight markers

/// A lock the app backs with `os_unfair_lock` and the tests with `NSLock`.
package protocol InflightLock: Sendable {
    func lock()
    func unlock()
}

package final class KitInflightLock: InflightLock, @unchecked Sendable {
    private let base = NSLock()
    package init() {}
    package func lock() { base.lock() }
    package func unlock() { base.unlock() }
}

/// The marker files: `inflight/<name>` holding the OS build.
package protocol InflightMarkerFiles: Sendable {
    /// Creates or truncates the file and writes the build; false when that failed.
    func write(_ name: String) -> Bool
    func remove(_ name: String)
}

/// One counter per marker (X2-4, X3-8, P3-6). The file is written on 0→1 and unlinked on 1→0, each under that
/// marker's lock together with the count, never around the private call, so a write and an unlink on one symbol
/// can't interleave and the marker stays while any call is in flight.
package final class InflightLedger: @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        let lock: any InflightLock
        var count = 0
        var successes = 0
        init(lock: any InflightLock) { self.lock = lock }
    }

    private let slots: [String: Slot]
    private let files: any InflightMarkerFiles

    package init(names: [String], files: any InflightMarkerFiles, makeLock: (String) -> any InflightLock) {
        var slots: [String: Slot] = [:]
        for name in names where slots[name] == nil { slots[name] = Slot(lock: makeLock(name)) }
        self.slots = slots
        self.files = files
    }

    /// Marks one call in flight. False when the 0→1 write failed (or the name is unknown): the caller takes the
    /// fallback and counts `markerWriteFailed`, and nothing is in flight.
    package func begin(_ name: String) -> Bool {
        guard let slot = slots[name] else { return false }
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if slot.count == 0 {
            guard files.write(name) else { return false }
        }
        slot.count += 1
        return true
    }

    /// Ends one call; `succeeded` adds to the in-memory success count. Returns that count.
    @discardableResult
    package func end(_ name: String, succeeded: Bool = true) -> Int {
        guard let slot = slots[name] else { return 0 }
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if slot.count > 0 {
            slot.count -= 1
            if slot.count == 0 { files.remove(name) }
        }
        if succeeded { slot.successes += 1 }
        return slot.successes
    }

    /// A success for a call that wrote no marker (a verified read-only symbol). Returns the count.
    @discardableResult
    package func noteSuccess(_ name: String) -> Int {
        guard let slot = slots[name] else { return 0 }
        slot.lock.lock()
        defer { slot.lock.unlock() }
        slot.successes += 1
        return slot.successes
    }

    package func inFlight(_ name: String) -> Int {
        guard let slot = slots[name] else { return 0 }
        slot.lock.lock()
        defer { slot.lock.unlock() }
        return slot.count
    }
}

// MARK: ⌘⇥ take and give-back

/// What `SystemHotkeyLedger` needs from the app: the two defaults lists, the take under the full contract, and the
/// give-back under its own guard.
package protocol SystemHotkeyPort: AnyObject {
    /// `SnapticDisabledSystemHotkeys`.
    func savedIDs() -> [Int]?
    func setSavedIDs(_ ids: [Int])
    func removeSavedIDs()
    /// `Windows.pendingGiveBack`. Only the launch move writes it.
    func pendingIDs() -> [Int]?
    func setPendingIDs(_ ids: [Int])
    func removePendingIDs()
    /// The take's `IsSymbolicHotKeyEnabled`; nil when it can't say.
    func isEnabled(_ id: Int32) -> Bool?
    /// Turns one id off under the full contract (crash guard, poison, kill switch). False: not taken.
    func take(_ id: Int32) -> Bool
    /// The give-back marker, then each id, then the marker's end. No gate, image check or poison applies.
    func beginGiveBack()
    func giveBack(_ id: Int32)
    func endGiveBack()
    /// `HotkeyGuard.setDisabled`.
    func guardHolds(_ ids: Set<Int32>)
}

/// Disables macOS's own ⌘⇥ / ⌘⇧⇥ / ⌘` while a Snaptic shortcut uses them and gives them back afterwards (0.4's
/// `SystemHotkeys`, now with the give-back guard; X3-2). The ids Snaptic turned off are saved before the calls, so a
/// crash is repaired at the next launch, and a saved list is removed only after its give-back returns. Shortcuts the
/// user turned off themselves are never touched.
package final class SystemHotkeyLedger {
    package static let commandTab: Int32 = 1
    package static let commandShiftTab: Int32 = 2
    package static let commandKeyAboveTab: Int32 = 6
    package static let managed: Set<Int32> = [commandTab, commandShiftTab, commandKeyAboveTab]

    package enum LaunchResult: Equatable, Sendable {
        case nothing
        /// The saved and pending lists were given back and both keys removed.
        case gaveBack(Int)
        /// The give-back is disabled on this build: the saved list now waits in `Windows.pendingGiveBack`.
        case movedToPending(Int)
    }

    private let port: SystemHotkeyPort
    package private(set) var owned = Set<Int32>()
    package private(set) var suspended = false
    /// The give-back's crash guard tripped on this build: no take until Try Again or the next OS build.
    package private(set) var giveBackDisabled = false

    package init(port: SystemHotkeyPort) { self.port = port }

    private static func managedIDs(_ list: [Int]?) -> Set<Int32> {
        Set((list ?? []).compactMap { Int32(exactly: $0) }.filter { managed.contains($0) })
    }

    private static func encode(_ ids: Set<Int32>) -> [Int] { ids.map { Int($0) }.sorted() }

    private func giveBack(_ ids: Set<Int32>) {
        guard !ids.isEmpty else { return }
        port.beginGiveBack()
        for id in ids.sorted() { port.giveBack(id) }
        port.endGiveBack()
    }

    /// Launch step 4 (H3, X3-2), after step 3b. A disabled give-back moves the saved list (union) to
    /// `Windows.pendingGiveBack` and removes the old key; otherwise the saved and pending lists are given back,
    /// marker first, and both keys removed after it returns.
    package func atLaunch(giveBackDisabled: Bool) -> LaunchResult {
        self.giveBackDisabled = giveBackDisabled
        if giveBackDisabled {
            let saved = Self.managedIDs(port.savedIDs())
            guard !saved.isEmpty else {
                if port.savedIDs() != nil { port.removeSavedIDs() }
                return .nothing
            }
            let pending = Self.managedIDs(port.pendingIDs()).union(saved)
            port.setPendingIDs(Self.encode(pending))
            port.removeSavedIDs()
            return .movedToPending(pending.count)
        }
        return recoverFromPreviousRun()
    }

    /// Gives back anything a previous run turned off and never gave back. Never writes the pending list.
    package func recoverFromPreviousRun() -> LaunchResult {
        let hadSaved = port.savedIDs() != nil, hadPending = port.pendingIDs() != nil
        let ids = Self.managedIDs(port.savedIDs()).union(Self.managedIDs(port.pendingIDs()))
        giveBack(ids)
        if hadSaved { port.removeSavedIDs() }
        if hadPending { port.removePendingIDs() }
        return ids.isEmpty ? .nothing : .gaveBack(ids.count)
    }

    /// The give-back row's Try Again (G3-2): its disabled build is already cleared; give the pending list back now.
    package func giveBackPendingNow() -> Int {
        giveBackDisabled = false
        let ids = Self.managedIDs(port.pendingIDs())
        let had = port.pendingIDs() != nil
        giveBack(ids)
        if had { port.removePendingIDs() }
        return ids.count
    }

    /// The ids a shortcut set wants: `⌘⇥` takes 1 and 2, `⌘\`` takes 6.
    package static func wanted(commandTab: Bool, commandBacktick: Bool) -> Set<Int32> {
        var ids = Set<Int32>()
        if commandTab { ids.formUnion([Self.commandTab, Self.commandShiftTab]) }
        if commandBacktick { ids.insert(commandKeyAboveTab) }
        return ids
    }

    /// Takes what `requested` wants and gives back the rest. `takeBlocked` covers the take's kill switch, poison,
    /// crash guard and availability; a disabled give-back blocks the take too. Ids in the pending list count as
    /// Snaptic's own, never as ones the user turned off. Never writes the pending list.
    package func apply(_ requested: Set<Int32>, takeBlocked: Bool) {
        let pending = Self.managedIDs(port.pendingIDs())
        var wanted = requested.intersection(Self.managed)
        if takeBlocked || giveBackDisabled { wanted = [] }
        wanted = wanted.filter { owned.contains($0) || pending.contains($0) || port.isEnabled($0) != false }

        // Saved before the system is touched, so a crash midway is recoverable.
        let everOff = owned.union(wanted)
        if !everOff.isEmpty { port.setSavedIDs(Self.encode(everOff)) }

        giveBack(owned.subtracting(wanted))
        var held = wanted
        if !suspended {
            for id in wanted.sorted() where !port.take(id) { held.remove(id) }
        }
        owned = held
        if owned.isEmpty {
            if port.savedIDs() != nil { port.removeSavedIDs() }
        } else {
            port.setSavedIDs(Self.encode(owned))
        }
        port.guardHolds(suspended ? [] : owned)
    }

    /// Takes the ids back after the hang guard released them.
    package func reassert(takeBlocked: Bool) {
        guard !suspended, !takeBlocked, !giveBackDisabled, !owned.isEmpty else { return }
        for id in owned.sorted() where !port.take(id) { owned.remove(id) }
        port.guardHolds(owned)
    }

    /// Hands the ids back while Snaptic can't see key presses, and takes them again after.
    package func setSuspended(_ value: Bool, takeBlocked: Bool) {
        guard value != suspended else { return }
        suspended = value
        if value {
            giveBack(owned)
            port.guardHolds([])
        } else if takeBlocked || giveBackDisabled {
            // Nothing is off; the ids stay Snaptic's so the next apply or restore handles them.
            port.guardHolds([])
        } else {
            for id in owned.sorted() where !port.take(id) { owned.remove(id) }
            port.guardHolds(owned)
        }
    }

    /// Gives every id back (quit, the module stopping, or the kill switch turning on). Idempotent.
    package func restore() {
        suspended = false
        guard !owned.isEmpty else { return }
        giveBack(owned)
        owned = []
        port.guardHolds([])
        port.removeSavedIDs()
    }
}
