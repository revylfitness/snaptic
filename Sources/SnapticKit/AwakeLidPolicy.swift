import Foundation

// Lid-closed mode's states and rules (owner: T-lid-kit; PLAN 0.3.1 B2, B3.0–B3.4, B5): the state machine's published
// state, how it ends and fails, the recovery journal and its classification, start refusals, the battery floor, the
// cap, the liveness checks and the lid-shut rule. LidClosedController and LidRecovery only perform what these return.

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

    /// The menu row's state (B0): on, one of the three pending texts, or off (`off` and `failed` alike).
    package var rowState: LidRowState {
        switch self {
        case .on: return .on
        case .authorizing: return .authorizing
        case .verifying: return .verifying
        case .stopping: return .stopping
        case .off, .failed: return .off
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
/// ever reaches root, and a journal alone never prompts: it only decides what a `SleepDisabled` of 1 means (B3.4).
package struct AwakeLidJournal: Codable, Equatable, Sendable {
    /// A journal file is read at most this far (it holds a few short fields).
    package static let maxBytes = 4_096

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

    /// A journal file that exists but can't be read as one: it still counts as Snaptic's (B3.4), so a
    /// `SleepDisabled` of 1 shows the leftover rows instead of being taken for another app's setting.
    package static let unreadable = AwakeLidJournal(token: "", bootSessionUUID: "", startedAtWall: 0,
                                                     startedAtContinuous: 0, floor: 0)

    /// The file's contents → a journal, or `unreadable` (too long, not JSON, missing fields).
    package static func parse(_ data: Data) -> AwakeLidJournal {
        guard data.count <= maxBytes, let j = try? JSONDecoder().decode(AwakeLidJournal.self, from: data) else {
            return unreadable
        }
        return j
    }

    /// The file's contents (sorted keys); nil if encoding fails.
    package func encoded() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try? e.encode(self)
    }

    /// Every field as LidClosedController writes it: a token, a boot session, finite times, a floor in range and,
    /// once verified, a watchdog pid that is a real process other than `ownPID`.
    package func isSane(ownPID: Int32) -> Bool {
        guard LidWatchdog.isToken(token), !bootSessionUUID.isEmpty, bootSessionUUID.utf8.count <= 64,
              startedAtWall.isFinite, startedAtContinuous.isFinite, LidWatchdog.floorRange.contains(floor) else {
            return false
        }
        if let p = pid { return p > 1 && p < 100_000 && p != ownPID }
        return true
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

    /// The toast (B2 table).
    package var text: String {
        switch self {
        case .lowBattery(let needed):
            return L("Lid-closed mode needs at least \(needed)% battery, or connect power.")
        case .tooHot: return L("Your Mac is too hot for lid-closed mode right now.")
        case .startAnywaySession: return L("Lid-closed mode isn’t available in a Start Anyway session.")
        case .translocated: return AwakeLidText.translocated
        case .journalPending: return L("Snaptic is finishing an earlier lid-closed session. Try again in a minute.")
        case .leftover: return L("Turn sleep back on first. It may have been left off by an earlier lid-closed session.")
        }
    }

    /// The leftover toast carries Turn Sleep Back On… and Open Awake Settings… (B2); the others carry none.
    package var buttons: [String] {
        self == .leftover ? [AwakeLidText.turnSleepBackOn, AwakeLidText.openAwakeSettings] : []
    }
}

/// What osascript's answer means for the state machine (B3.1 step 5).
package enum AwakeLidLaunchStep: Equatable, Sendable {
    /// Verify this pid (B3.1 step 6).
    case verify(pid: Int32)
    /// Cancel: silent.
    case canceled
    /// `check` exited 3: the "Sleep is already turned off…" toast; the session starts or continues without the mode.
    case alreadyOff
    /// "Snaptic couldn’t turn on lid-closed mode. Try again." (`args` for the script's 64, else `spawn`).
    case failed(AwakeLidFailStage)
}

/// The heartbeat's liveness rule (B3.1 step 7, B3.3): the watchdog gone ends the mode at once; `SleepDisabled` read as
/// 0 twice in a row ends it as another app's doing. An unreadable value changes nothing (the watchdog itself restores
/// after two).
package struct AwakeLidLiveness: Equatable, Sendable {
    package private(set) var zeroReads = 0

    package init() {}

    /// One tick: `watchdogAlive` is `kill(pid, 0)` answering and the same `instanceID` as at verify.
    package mutating func tick(watchdogAlive: Bool, sleepDisabled: Bool?) -> AwakeLidEnd? {
        guard watchdogAlive else { return .watchdogLost }
        switch sleepDisabled {
        case true?: zeroReads = 0
        case false?: zeroReads += 1
        case nil: break
        }
        return zeroReads >= 2 ? .otherApp : nil
    }
}

package enum AwakeLidPolicy {
    // Timings (B3.0–B3.4), in seconds unless named otherwise.
    /// osascript gets this long for the password before SIGTERM (a timeout).
    package static let osascriptTimeoutSeconds: Double = 120
    /// The "Turning on lid-closed mode…" toast shows once verifying takes longer than this.
    package static let verifyToastSeconds: Double = 2
    /// Verify polls `SleepDisabled` this often, for at most this long.
    package static let verifyPollSeconds: Double = 0.5
    package static let verifyLimitSeconds: Double = 10
    /// The second look after turning on (B3.1 step 7).
    package static let recheckAfterOnSeconds: Double = 5
    /// Heartbeat period and leeway; a tick touches the beacon only while the main thread answered within the limit.
    package static let heartbeatSeconds: Double = 5
    package static let heartbeatLeewaySeconds: Double = 0.5
    package static let mainAgeLimitMillis = 10_000
    /// Turning off polls `SleepDisabled` for this long before the leftover rows show.
    package static let stopPollSeconds: Double = 15
    /// A failed or superseded request keeps its journal until `SleepDisabled` reads 0, at most this long.
    package static let failedExitPollSeconds: Double = 30
    /// A pending journal is classified again after this long (B3.4).
    package static let pendingRecheckSeconds: Double = 30
    /// `pmset displaysleepnow` at most this often (powerd defers it ~30 s after a wake).
    package static let displaySleepIntervalSeconds: Double = 10
    /// The cap warning shows this long before the cap.
    package static let capWarningSeconds: Double = 300
    /// The "Lid-closed mode ended at …" line is kept this long.
    package static let lastEndKeepSeconds: Double = 12 * 3_600
    /// Turning on needs `floor + startMarginPercent` while discharging (B2).
    package static let startMarginPercent = 5
    /// The limit while Awake's battery floor is turned off (B1).
    package static let floorWhenAwakeFloorOff = 20

    /// The battery limit: `max(10, Awake's floor)`, or 20% while Awake's floor is off (B1); always 10–50.
    package static func floor(awakeGuards: AwakeGuardsConfig) -> Int {
        let g = awakeGuards.sanitized()
        let f = g.batteryFloorEnabled ? max(LidWatchdog.floorRange.lowerBound, g.batteryFloor) : floorWhenAwakeFloorOff
        return AwakeMath.clamp(f, LidWatchdog.floorRange)
    }

    /// The mode's end: the earlier of the session's end and `capStart + 24 h` (B2 "keep"). `capStart` is the first
    /// turn-on and never resets, so the app and the watchdog agree on the cap. A `capStart` that isn't finite gives
    /// `-infinity` (already passed: the mode ends).
    package static func until(sessionEnd: Double?, capStart: Double) -> Double {
        guard capStart.isFinite else { return -.infinity }
        let cap = capStart + Double(LidWatchdog.capSeconds)
        guard let end = sessionEnd, end.isFinite else { return cap }
        return min(end, cap)
    }

    /// The 5-minute cap warning is due now (B1): the cap ends before the session, and `now` is within the last five
    /// minutes before it. The app shows it once per turn-on.
    package static func capWarningDue(until: Double, sessionEnd: Double?, now: Double) -> Bool {
        guard until.isFinite, now.isFinite else { return false }
        if let end = sessionEnd, end.isFinite, end <= until { return false }
        return now >= until - capWarningSeconds && now < until
    }

    /// The mode ended for `reason` while the lid is closed (`lidShut`: `AwakeRuntimeState.lidClosed == true`, whatever
    /// displays are attached) and closing it sleeps the Mac (`lidWillSleep == true`): the session ends too, with
    /// `.lidEnded` (B3.3). Not when the session's own end, a replacement, quitting, Safe Mode or the module stopping
    /// ended the mode: the session is ending already.
    package static func endsSession(lidShut: Bool, lidWillSleep: Bool?, reason: AwakeLidEnd) -> Bool {
        guard lidShut, lidWillSleep == true else { return false }
        switch reason {
        case .user, .cap, .battery, .heat, .otherApp, .watchdogLost, .featureOff: return true
        case .sessionEnded, .replaced, .quit, .safeMode, .moduleStopped: return false
        }
    }

    /// Why the mode ends when its session ends for `reason` (the gate already said `.end`). Quitting stops the module,
    /// so `terminating` names that `.quit`.
    package static func lidEnd(sessionEnded reason: AwakeEndReason, terminating: Bool) -> AwakeLidEnd {
        switch reason {
        case .replaced: return .replaced
        case .moduleStopped: return terminating ? .quit : .moduleStopped
        case .safeMode: return .safeMode
        case .appQuit, .user, .timeUp, .processExited, .tasksFinished, .triggerEnded, .batteryLow,
             .adapterDisconnected, .lowPowerMode, .thermal, .systemSleep, .userSwitch, .lockedTooLong, .reboot,
             .assertionFailed, .commandLineOff, .lidEnded:
            return .sessionEnded
        }
    }

    /// The app's own battery and heat cutoff, ahead of the session's guards (B3.3); the watchdog enforces the same
    /// floor and heat limit on its own. Heat first. An unknown percentage ends nothing here: the session's guards and
    /// the watchdog (after two unreadable reads) handle it.
    package static func guardEnd(batteryPercent: Int?, discharging: Bool, floor: Int,
                                 thermalSerious: Bool) -> AwakeLidEnd? {
        if thermalSerious { return .heat }
        if discharging, let p = batteryPercent, p <= floor { return .battery }
        return nil
    }

    /// B3.4's table. `sleepDisabled` is the kernel's value (nil = unreadable); `bootUUID` this boot's session UUID
    /// ("" when unreadable). An unreadable value keeps the journal and refuses turning on (`pending`); a journal that
    /// isn't sane (`AwakeLidJournal.isSane`), or a same-boot one older than any watchdog can live, is `leftover` at
    /// once.
    package static func classify(journal: AwakeLidJournal?, bootUUID: String, sleepDisabled: Bool?, now: ClockNow,
                                 ownPID: Int32) -> AwakeLidRecovery {
        guard let j = journal else { return .nothing }
        guard let on = sleepDisabled else { return .pending }
        guard on else { return .clear }
        guard j.isSane(ownPID: ownPID) else { return .leftover }
        guard !bootUUID.isEmpty else { return .pending }
        guard j.bootSessionUUID == bootUUID else { return .leftover }
        // Same boot: a watchdog may still be restoring (its beacon goes stale within 20 s), but none outlives its cap.
        let age = now.continuous - j.startedAtContinuous
        let longest = Double(LidWatchdog.capSeconds + 60) + pendingRecheckSeconds
        guard age.isFinite, age >= 0, age <= longest else { return .leftover }
        return .pending
    }

    /// The look 30 s after `pending` (B3.4): 0 clears, 1 is a leftover, unreadable stays pending.
    package static func recheck(sleepDisabled: Bool?) -> AwakeLidRecovery {
        switch sleepDisabled {
        case false?: return .clear
        case true?: return .leftover
        case nil: return .pending
        }
    }

    /// The first B2 refusal that applies, or nil, most fundamental first: translocated, a leftover, a pending
    /// journal, a Start Anyway session, heat, then the battery (discharging below `floor + 5`, or discharging at an
    /// unknown level). `batteryPercent` is nil when unknown or on power.
    package static func startRefusal(batteryPercent: Int?, discharging: Bool, floor: Int, thermalSerious: Bool,
                                     overrideGuards: Bool, translocated: Bool,
                                     recovery: AwakeLidRecovery) -> AwakeLidRefusal? {
        if translocated { return .translocated }
        switch recovery {
        case .leftover: return .leftover
        case .pending: return .journalPending
        case .nothing, .clear: break
        }
        if overrideGuards { return .startAnywaySession }
        if thermalSerious { return .tooHot }
        let needed = AwakeMath.clamp(floor, LidWatchdog.floorRange) + startMarginPercent
        if discharging && (batteryPercent.map { $0 < needed } ?? true) { return .lowBattery(needed: needed) }
        return nil
    }

    /// osascript's outcome → the next step (B3.1 step 5).
    package static func launchStep(_ outcome: LidWatchdog.Outcome) -> AwakeLidLaunchStep {
        switch outcome {
        case .launched(let pid): return .verify(pid: pid)
        case .canceled: return .canceled
        case .failed(3): return .alreadyOff
        case .failed(64): return .failed(.args)
        case .failed: return .failed(.spawn)
        }
    }

    /// The watchdog's identity at verify (B3.1 step 6): real uid 0 and started after the spawn (both from
    /// `sysctl(KERN_PROC_PID)`; nil when unreadable; `spawnedAt` is the wall time taken just before the spawn, and
    /// the kernel keeps start times to the microsecond, so one second of slack covers rounding only). Anything else
    /// fails with stage `verify`.
    package static func watchdogVerified(realUID: UInt32?, startTime: Double?, spawnedAt: Double) -> Bool {
        guard realUID == 0, let t = startTime, t.isFinite, spawnedAt.isFinite else { return false }
        return t >= spawnedAt - 1
    }
}
