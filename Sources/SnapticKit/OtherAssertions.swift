import Foundation

// Other processes keeping the Mac awake, and the system-wide "SleepDisabled" setting (owner: J; PLAN 0.3 §1.1, §1.3,
// §2.8, §3.6). Pure parsing of what the app reads: `IOPMCopyAssertionsByProcess` (pid → assertion dictionaries) and
// the "SystemPowerSettings" dictionary of the `com.apple.PowerManagement` preferences (what `pmset disablesleep`,
// Amphetamine Power Protect and Insomnia leave behind). Read-only here: the only writer of SleepDisabled in Snaptic is
// lid-closed mode's root watchdog (0.3.1 B3.2, LidWatchdog.swift), while that mode is on or during recovery. Local UI
// only: nothing here is logged, stored, exported or sent over the CLI.

/// What another process's assertion keeps from happening, strongest last.
package enum OtherAssertionKind: Int, CaseIterable, Comparable, Sendable {
    /// PreventUserIdleSystemSleep, NoIdleSleepAssertion, SystemIsActive: no idle sleep; the display may sleep.
    case idleSleep
    /// PreventUserIdleDisplaySleep, NoDisplaySleepAssertion: the display (and so the Mac) stays on.
    case display
    /// PreventSystemSleep: no sleep at all while on AC power.
    case systemSleep

    package static func < (a: OtherAssertionKind, b: OtherAssertionKind) -> Bool { a.rawValue < b.rawValue }
}

/// One process holding at least one assertion that keeps the Mac awake.
package struct OtherAssertionHolder: Equatable, Sendable {
    /// The process the assertion is attributed to: the "on behalf of" process when powerd names one (coreaudiod
    /// playing for Music), else the owner.
    package var pid: Int32
    /// powerd's "AssertProcess" name of the owner, cleaned (≤ 64 scalars); a fallback when the pid can't be named.
    package var reportedName: String?
    package var kinds: Set<OtherAssertionKind>
    /// Active assertions attributed to this pid.
    package var count: Int

    package init(pid: Int32, reportedName: String?, kinds: Set<OtherAssertionKind>, count: Int) {
        self.pid = pid
        self.reportedName = reportedName
        self.kinds = kinds
        self.count = count
    }
}

/// One line of the "Other apps keeping your Mac awake" section: every holder with the same display name merged.
package struct OtherAssertionRow: Equatable, Sendable {
    package var name: String
    /// Strongest first.
    package var kinds: [OtherAssertionKind]
    /// Processes merged into this row.
    package var processes: Int

    package init(name: String, kinds: [OtherAssertionKind], processes: Int) {
        self.name = name
        self.kinds = kinds
        self.processes = processes
    }
}

package enum OtherAssertions {
    // Keys of one assertion dictionary (IOPMLib.h / IOPMLibPrivate.h).
    package static let typeKey = "AssertType"
    package static let levelKey = "AssertLevel"
    package static let processKey = "AssertProcess"
    package static let onBehalfOfPIDKey = "AssertionOnBehalfOfPID"
    package static let suspendedKey = "AssertionIsStateSuspended"

    /// `CFPreferencesCopyValue(settingsKey, preferencesDomain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)` is
    /// exactly what the private `IOPMCopySystemPowerSettings()` returns; `sleepDisabledKey` is kIOPMSleepDisabledKey.
    package static let preferencesDomain = "com.apple.PowerManagement"
    package static let settingsKey = "SystemPowerSettings"
    package static let sleepDisabledKey = "SleepDisabled"

    /// Bounds: a hostile or broken reply never grows the UI without limit.
    package static let maxHolders = 64
    package static let maxAssertionsPerProcess = 256
    package static let maxNameScalars = 64

    /// The kinds that keep the Mac awake; everything else (UserIsActive input echoes, BackgroundTask, PreventDiskIdle,
    /// push and internal assertions) is not "keeping your Mac awake" and is ignored.
    package static func kind(ofType type: String) -> OtherAssertionKind? {
        switch type {
        case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "SystemIsActive": return .idleSleep
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion": return .display
        case "PreventSystemSleep": return .systemSleep
        default: return nil
        }
    }

    /// Holders from `IOPMCopyAssertionsByProcess` (keys are owner pids). Skipped: pids ≤ 0 (the kernel), `ownPID`
    /// (attributed either way, so Snaptic never lists itself), assertions at level 0 or suspended, unknown or
    /// non-keeping types. Sorted by pid; at most `maxHolders`.
    package static func holders(_ byProcess: [Int32: [[String: Any]]], ownPID: Int32) -> [OtherAssertionHolder] {
        var out: [Int32: OtherAssertionHolder] = [:]
        for owner in byProcess.keys.sorted() where owner > 0 && owner != ownPID {
            for assertion in (byProcess[owner] ?? []).prefix(maxAssertionsPerProcess) {
                guard isActive(assertion), let type = assertion[typeKey] as? String, let kind = kind(ofType: type) else {
                    continue
                }
                var pid = owner
                if let behalf = int(assertion[onBehalfOfPIDKey]), behalf > 0, behalf <= Int(Int32.max) {
                    pid = Int32(behalf)
                }
                guard pid != ownPID else { continue }
                var holder = out[pid] ?? OtherAssertionHolder(pid: pid, reportedName: nil, kinds: [], count: 0)
                if pid == owner, holder.reportedName == nil, let name = assertion[processKey] as? String {
                    let cleaned = TextSanitizer.clean(name, maxScalars: maxNameScalars).trimmingCharacters(in: .whitespaces)
                    if !cleaned.isEmpty { holder.reportedName = cleaned }
                }
                holder.kinds.insert(kind)
                holder.count += 1
                out[pid] = holder
            }
        }
        return Array(out.keys.sorted().prefix(maxHolders).compactMap { out[$0] })
    }

    /// Level present and 0 = released; suspended = not in effect. A missing level reads as on (older replies).
    package static func isActive(_ assertion: [String: Any]) -> Bool {
        if let level = int(assertion[levelKey]), level == 0 { return false }
        if let suspended = flag(assertion[suspendedKey]), suspended { return false }
        return true
    }

    /// Rows for display: holders named by `name(holder)` (the app resolves running apps and process names), empty
    /// names dropped, equal names (case-insensitive) merged, sorted by name. Kinds strongest first.
    package static func rows(_ holders: [OtherAssertionHolder], name: (OtherAssertionHolder) -> String?) -> [OtherAssertionRow] {
        var merged: [String: OtherAssertionRow] = [:]
        var kinds: [String: Set<OtherAssertionKind>] = [:]
        for holder in holders {
            guard let raw = name(holder) else { continue }
            let display = TextSanitizer.clean(raw, maxScalars: maxNameScalars).trimmingCharacters(in: .whitespaces)
            guard !display.isEmpty, !holder.kinds.isEmpty else { continue }
            let key = display.lowercased()
            var row = merged[key] ?? OtherAssertionRow(name: display, kinds: [], processes: 0)
            row.processes += 1
            merged[key] = row
            kinds[key, default: []].formUnion(holder.kinds)
        }
        return merged.keys.sorted().compactMap { key in
            guard var row = merged[key] else { return nil }
            row.kinds = (kinds[key] ?? []).sorted(by: >)
            return row
        }
    }

    /// Advanced › Other Apps while SleepDisabled is on and no Snaptic journal explains it (0.3.1 B3.4; it replaces
    /// 0.3's "Snaptic can’t change this."). With a journal, the leftover row (`AwakeLidText.leftover`) shows instead.
    package static let sleepDisabledByOther = L("Sleep is turned off for this Mac by another app or command. Snaptic leaves it as it is.")

    /// The SleepDisabled flag from the "SystemPowerSettings" dictionary. An absent dictionary or key (no custom
    /// settings) is false; a present key is true for `true`, any non-zero number or "1"/"true"/"yes"; anything else
    /// is false.
    package static func sleepDisabled(_ settings: [String: Any]?) -> Bool {
        guard let settings, let value = settings[sleepDisabledKey] else { return false }
        return flag(value) ?? false
    }

    // MARK: Value parsing (CF values arrive bridged on macOS, as Swift values in tests)

    package static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Int32: return Int(v)
        case let v as Int64: return Int(exactly: v)
        case let v as UInt32: return Int(v)
        case let v as UInt64: return Int(exactly: v)
        case let v as Double: return v.isFinite && v.rounded() == v && abs(v) < 1e15 ? Int(v) : nil
        case let v as NSNumber: return Int(exactly: v.int64Value)
        default: return nil
        }
    }

    package static func flag(_ value: Any?) -> Bool? {
        switch value {
        case let v as Bool: return v
        case let v as String:
            switch v.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        default: return int(value).map { $0 != 0 }
        }
    }
}
