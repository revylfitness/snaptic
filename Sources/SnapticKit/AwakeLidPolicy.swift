import Foundation

// Lid-closed mode's states and rules (owner: T-lid-kit; PLAN 0.3.1 B3.0, B3.4, B5): the state machine's published
// state, how it ends and fails, the recovery journal and its classification, start refusals, the battery floor, the
// cap and the lid-shut rule.
//
// Step 0 stub: the types are the contract; the rules return fail-safe values (the highest floor, a cap that has
// already passed, "ends the session", nothing to recover) until T-lid-kit lands.

/// The state machine's published state (B3.0; `AwakeRuntimeState.lidMode`, assigned only by LidClosedController, lint
/// L16). Tokens are 32 lowercase hex characters; `until` is a continuous-clock instant.
package enum AwakeLidMode: Equatable, Sendable {
    case off
    case authorizing(token: String)
    case verifying(token: String, pid: Int32)
    case on(token: String, pid: Int32, until: Double)
    case stopping(token: String)
    /// Shows one toast, then returns to `off`.
    case failed(AwakeLidFailStage)

    package var isOn: Bool {
        if case .on = self { return true }
        return false
    }

    /// Every lid entry point is disabled and shows the B0 pending text.
    package var isPending: Bool {
        switch self {
        case .authorizing, .verifying, .stopping: return true
        case .off, .on, .failed: return false
        }
    }

    package var token: String? {
        switch self {
        case .authorizing(let t), .verifying(let t, _), .on(let t, _, _), .stopping(let t): return t
        case .off, .failed: return nil
        }
    }
}

/// Why lid-closed mode ended (B5; History, logs and the "Lid-closed mode ended at …" line).
package enum AwakeLidEnd: String, Codable, CaseIterable, Sendable {
    case user, sessionEnded, replaced, cap, battery, heat, otherApp, watchdogLost, quit, safeMode, featureOff,
         moduleStopped
}

/// Where turning lid-closed mode on failed (B5; logged, never shown).
package enum AwakeLidFailStage: String, Codable, CaseIterable, Sendable {
    case beacon, spawn, args, verify, timeout
}

/// `~/Library/Application Support/Snaptic/awake/lid.json` (B3.1 step 2): one slot, 0600, written atomically. No field
/// ever reaches root.
package struct AwakeLidJournal: Codable, Equatable, Sendable {
    package var token: String
    package var bootSessionUUID: String
    package var startedAtWall: Double
    package var startedAtContinuous: Double
    package var pid: Int32?
    package var instanceID: UInt64?
    package var floor: Int

    package init(token: String, bootSessionUUID: String, startedAtWall: Double, startedAtContinuous: Double,
                 pid: Int32? = nil, instanceID: UInt64? = nil, floor: Int) {
        self.token = token
        self.bootSessionUUID = bootSessionUUID
        self.startedAtWall = startedAtWall
        self.startedAtContinuous = startedAtContinuous
        self.pid = pid
        self.instanceID = instanceID
        self.floor = floor
    }
}

/// The B3.4 classification of a journal and the kernel's `SleepDisabled`.
package enum AwakeLidRecovery: String, Equatable, Sendable {
    /// No journal: someone else's setting (reported, never changed).
    case nothing
    /// Journal and SleepDisabled 0: clear the journal.
    case clear
    /// Same boot, SleepDisabled 1: re-check after 30 s, then `leftover`. Turning the mode on is refused meanwhile.
    case pending
    /// Another boot (or still 1 after the re-check): the leftover rows show.
    case leftover
}

/// Why turning lid-closed mode on is refused (B2): each is one toast; the mode never offers Start Anyway.
package enum AwakeLidRefusal: Equatable, Sendable {
    /// Discharging below `floor + 5`: the percentage needed.
    case lowBattery(needed: Int)
    case tooHot
    case startAnywaySession
    case translocated
    case journalPending
    case leftover

    /// Stub: empty (T-lid-kit writes the B2 texts).
    package var text: String { "" }
}

package enum AwakeLidPolicy {
    /// The battery limit: `max(10, Awake's floor)`, or 20% while Awake's floor is off (B1). Stub: 50, the highest.
    package static func floor(awakeGuards: AwakeGuardsConfig) -> Int { 50 }

    /// The mode's end: the earlier of the session's end and `capStart + 24 h` (B2 "keep"). Stub: `capStart`.
    package static func until(sessionEnd: Double?, capStart: Double) -> Double { capStart }

    /// The 5-minute cap warning is due now (B1). Stub: false.
    package static func capWarningDue(until: Double, sessionEnd: Double?, now: Double) -> Bool { false }

    /// The mode ended for `reason` while the lid is shut and closing it would sleep the Mac: the session ends too,
    /// with `.lidEnded` (B3.3). Stub: true.
    package static func endsSession(lidShut: Bool, lidWillSleep: Bool?, reason: AwakeLidEnd) -> Bool { true }

    /// B3.4's table. `sleepDisabled` is the kernel's value (nil = unreadable). Stub: `.nothing`.
    package static func classify(journal: AwakeLidJournal?, bootUUID: String, sleepDisabled: Bool?, now: ClockNow,
                                 ownPID: Int32) -> AwakeLidRecovery {
        .nothing
    }

    /// The first B2 refusal that applies, or nil. `batteryPercent` is nil when unknown or on power. Stub: nil (the
    /// step-0 spawner refuses everything anyway).
    package static func startRefusal(batteryPercent: Int?, discharging: Bool, floor: Int, thermalSerious: Bool,
                                     overrideGuards: Bool, translocated: Bool,
                                     recovery: AwakeLidRecovery) -> AwakeLidRefusal? {
        nil
    }
}
