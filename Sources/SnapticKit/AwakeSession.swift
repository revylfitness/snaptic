import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.3 + R5 (kind S): safe returns; the lossy
// decoders R5-3 declares are real. G replaces the bodies in step 1.

package enum AwakeDisplayPolicy: String, Codable, CaseIterable, Sendable {
    /// PreventUserIdleDisplaySleep. UI "Keep on".
    case keepOn
    /// PreventUserIdleSystemSleep; the display follows System Settings. UI "Can turn off".
    case maySleep
    /// keepOn until real idle ≥ displayIdleMinutes, then maySleep. UI "Keep on until idle for [n min]".
    case keepOnWhileActive
}

package enum AwakeActivityMode: String, Codable, CaseIterable, Sendable { case off, declare, nudge }

package struct AwakeSessionOptions: Codable, Equatable, Sendable {
    package var display: AwakeDisplayPolicy
    /// 1...240, default 30.
    package var displayIdleMinutes: Int
    /// `.nudge` acts only per N10 (else it degrades to `.declare`).
    package var activity: AwakeActivityMode

    package init(display: AwakeDisplayPolicy = .keepOn, displayIdleMinutes: Int = 30, activity: AwakeActivityMode = .off) {
        self.display = display
        self.displayIdleMinutes = displayIdleMinutes
        self.activity = activity
    }

    private enum CodingKeys: String, CodingKey { case display, displayIdleMinutes, activity }

    /// Lossy per field.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        display = c.lossy(.display, .keepOn)
        displayIdleMinutes = c.lossy(.displayIdleMinutes, 30)
        activity = c.lossy(.activity, .off)
    }

    package func sanitized() -> AwakeSessionOptions { self }
}

/// "Until Downloads and Tasks Finish" (N9). Busy = any signal at or above its threshold in a 5 s sample; the
/// session ends after `quietSeconds` with no busy sample, never before `minimumHoldSeconds` from start (R5-4).
package struct UntilIdleSpec: Codable, Equatable, Sendable {
    /// 50 = half of one core; 10...800.
    package var topProcessPercent: Int
    /// 3; 1...50 same-user pids first seen in one 5 s sample.
    package var newProcesses: Int
    /// 15; 1...90.
    package var totalCPUPercent: Int
    /// 1_024; 64...1_000_000.
    package var diskKBps: Int
    /// 50; 1...100_000.
    package var networkKBps: Int
    /// 300; 60...3_600.
    package var quietSeconds: Int
    /// 600; 0...3_600 (R5-4; replaces graceSeconds, never shipped; not in the UI).
    package var minimumHoldSeconds: Int

    package init(topProcessPercent: Int = 50, newProcesses: Int = 3, totalCPUPercent: Int = 15, diskKBps: Int = 1_024,
                 networkKBps: Int = 50, quietSeconds: Int = 300, minimumHoldSeconds: Int = 600) {
        self.topProcessPercent = topProcessPercent
        self.newProcesses = newProcesses
        self.totalCPUPercent = totalCPUPercent
        self.diskKBps = diskKBps
        self.networkKBps = networkKBps
        self.quietSeconds = quietSeconds
        self.minimumHoldSeconds = minimumHoldSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case topProcessPercent, newProcesses, totalCPUPercent, diskKBps, networkKBps, quietSeconds, minimumHoldSeconds
    }

    /// Lossy per field.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UntilIdleSpec()
        topProcessPercent = c.lossy(.topProcessPercent, d.topProcessPercent)
        newProcesses = c.lossy(.newProcesses, d.newProcesses)
        totalCPUPercent = c.lossy(.totalCPUPercent, d.totalCPUPercent)
        diskKBps = c.lossy(.diskKBps, d.diskKBps)
        networkKBps = c.lossy(.networkKBps, d.networkKBps)
        quietSeconds = c.lossy(.quietSeconds, d.quietSeconds)
        minimumHoldSeconds = c.lossy(.minimumHoldSeconds, d.minimumHoldSeconds)
    }

    package func sanitized() -> UntilIdleSpec { self }
}

/// One untilIdle sample (G declares it; J's samplers fill it). nil = unknown, which counts as busy.
package struct TaskActivitySample: Equatable, Sendable {
    package var topProcessPercent: Double?
    package var newProcesses: Int?
    package var totalCPUPercent: Double?
    package var diskKBps: Double?
    package var networkKBps: Double?

    package init(topProcessPercent: Double?, newProcesses: Int?, totalCPUPercent: Double?, diskKBps: Double?,
                 networkKBps: Double?) {
        self.topProcessPercent = topProcessPercent
        self.newProcesses = newProcesses
        self.totalCPUPercent = totalCPUPercent
        self.diskKBps = diskKBps
        self.networkKBps = networkKBps
    }
}

package enum TaskQuiet {
    /// Stub: always busy (an unknown never ends a session).
    package static func isBusy(_ s: TaskActivitySample, spec: UntilIdleSpec) -> Bool { true }

    /// quietSince: continuous instant of the first quiet sample in the current run (nil while busy). `started`: R5-4.
    package static func step(quietSince: Double?, sample: TaskActivitySample, now: Double, started: Double,
                             spec: UntilIdleSpec) -> (quietSince: Double?, finished: Bool) {
        (nil, false)
    }

    /// Seconds of the current quiet run; nil while busy.
    package static func quietFor(quietSince: Double?, now: Double) -> Double? { nil }
}

/// What a command-line hold is bound to. The server resolves both; neither comes from the request.
package enum HoldBinding: Equatable, Sendable {
    /// The `snaptic` client's own connection and process (peer pid: best effort, not identity). Never persisted.
    case connection(pid: Int32, startTime: UInt64)
    /// `--pid N`: a same-user process the caller names. Persisted; re-verified at restore.
    case process(pid: Int32, startTime: UInt64)

    package var pid: Int32 {
        switch self {
        case .connection(let pid, _), .process(let pid, _): return pid
        }
    }

    /// Process start in µs (pbi_start_tvsec·10⁶ + pbi_start_tvusec).
    package var startTime: UInt64 {
        switch self {
        case .connection(_, let t), .process(_, let t): return t
        }
    }
}

package enum AwakeSessionKind: Equatable, Sendable {
    case indefinite
    /// 60 ... AwakeClock.maxSessionSeconds.
    case duration(seconds: Int)
    /// Absolute wall instant.
    case until(unixTime: Double)
    /// Validated reverse-DNS, ≤ 255 bytes; optional cap.
    case whileApp(bundleID: String, maxSeconds: Int?)
    /// Ends after quietSeconds with no busy sample.
    case untilIdle(UntilIdleSpec, maxSeconds: Int?)

    /// duration, until.
    package var isTimed: Bool { false }
    /// whileApp/untilIdle cap.
    package var cap: Int? { nil }
    /// whileApp, untilIdle.
    package var isTaskBound: Bool { false }
}

private enum StubTypeKey: String, CodingKey { case type }

extension AwakeSessionKind: Codable {
    /// Hand-written, type-tagged (G). Stub: throws, so a stored session is dropped.
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: StubTypeKey.self)
        try c.encode("notBuilt", forKey: .type)
    }
}

extension HoldBinding: Codable {
    /// `.connection` never decodes (that hold is dropped). Stub: nothing decodes.
    package init(from decoder: Decoder) throws { throw StubError.notBuilt }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: StubTypeKey.self)
        try c.encode("notBuilt", forKey: .type)
    }
}

/// One command-line holder (N17). SessionController keeps ≤ maxHolds; `.process` holds persist.
package struct AwakeHold: Codable, Equatable, Sendable, Identifiable {
    package static let maxHolds = 8
    package var id: StableID
    package var binding: HoldBinding
    /// Wall, display and history only.
    package var startedAt: Double
    package var startedContinuous: Double
    /// Continuous: start + cap (cap ≤ AwakeClock.holdMaxCapSeconds).
    package var deadline: Double
    package var bootSession: String

    package init(id: StableID, binding: HoldBinding, startedAt: Double, startedContinuous: Double, deadline: Double,
                 bootSession: String) {
        self.id = id
        self.binding = binding
        self.startedAt = startedAt
        self.startedContinuous = startedContinuous
        self.deadline = deadline
        self.bootSession = bootSession
    }

    private enum CodingKeys: String, CodingKey { case id, binding, startedAt, startedContinuous, deadline, bootSession }

    /// Lossy per field; an id or binding that doesn't decode throws (the hold is dropped).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        binding = try c.decode(HoldBinding.self, forKey: .binding)
        startedAt = c.lossy(.startedAt, 0)
        startedContinuous = c.lossy(.startedContinuous, 0)
        deadline = c.lossy(.deadline, 0)
        bootSession = c.lossy(.bootSession, "")
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(binding, forKey: .binding)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(startedContinuous, forKey: .startedContinuous)
        try c.encode(deadline, forKey: .deadline)
        try c.encode(bootSession, forKey: .bootSession)
    }

    /// nil when expired, from another boot, started after now, or deadline − start > holdMaxCap. Stub: nil.
    package func sanitized(now: ClockNow) -> AwakeHold? { nil }
}

/// Persisted and kept through restore (security L1: a restored CLI session stays `.commandLine`).
package enum AwakeSessionSource: String, Codable, Sendable {
    case menu, hotkey, settings, commandLine, launch
    /// R5-14: history and policy only (trigger sessions); sanitized(now:) drops a manual session with it.
    case rule

    /// menu, hotkey, settings: a direct user action in Snaptic's own UI (N10). Stub: false.
    package var isDirectUserAction: Bool { false }
}

package struct AwakeSession: Codable, Equatable, Sendable, Identifiable {
    package var id: StableID
    package var kind: AwakeSessionKind
    /// Resolved at start: preset ?? defaultOptions (§2.14, R5-11).
    package var options: AwakeSessionOptions
    package var presetID: StableID?
    package var source: AwakeSessionSource
    /// Wall, display and history only.
    package var startedAt: Double
    /// Continuous clock at start.
    package var startedContinuous: Double
    /// Continuous-clock instant: duration end or task cap; nil = none.
    package var deadline: Double?
    /// kern.bootsessionuuid at start; mismatch = expired.
    package var bootSession: String
    /// One-shot "Start Anyway"; not in CodingKeys, never persisted (security H2).
    package var overrideGuards: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, kind, options, presetID, source, startedAt, startedContinuous, deadline, bootSession
    }

    package init(id: StableID, kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                 source: AwakeSessionSource, startedAt: Double, startedContinuous: Double, deadline: Double?,
                 bootSession: String, overrideGuards: Bool = false) {
        self.id = id
        self.kind = kind
        self.options = options
        self.presetID = presetID
        self.source = source
        self.startedAt = startedAt
        self.startedContinuous = startedContinuous
        self.deadline = deadline
        self.bootSession = bootSession
        self.overrideGuards = overrideGuards
    }

    /// Lossy per field; an id, kind or source failure throws (the session is dropped).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        kind = try c.decode(AwakeSessionKind.self, forKey: .kind)
        source = try c.decode(AwakeSessionSource.self, forKey: .source)
        options = c.lossy(.options, AwakeSessionOptions())
        presetID = c.lossy(.presetID, nil)
        startedAt = c.lossy(.startedAt, 0)
        startedContinuous = c.lossy(.startedContinuous, 0)
        deadline = c.lossy(.deadline, nil)
        bootSession = c.lossy(.bootSession, "")
        overrideGuards = false
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(options, forKey: .options)
        try c.encodeIfPresent(presetID, forKey: .presetID)
        try c.encode(source, forKey: .source)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(startedContinuous, forKey: .startedContinuous)
        try c.encodeIfPresent(deadline, forKey: .deadline)
        try c.encode(bootSession, forKey: .bootSession)
    }

    /// nil if expired, other boot, out of range, started after now, deadline beyond the cap, or cap/deadline
    /// mismatch (r3 security L3). Stub: nil.
    package func sanitized(now: ClockNow) -> AwakeSession? { nil }
}

package enum AwakeEndReason: String, Codable, CaseIterable, Sendable {
    case user, timeUp, appQuit, processExited, tasksFinished, replaced, triggerEnded, batteryLow,
         adapterDisconnected, lowPowerMode, thermal, systemSleep, userSwitch, lockedTooLong, moduleStopped, safeMode,
         reboot, assertionFailed, commandLineOff
}

package struct TriggerTop: Equatable, Sendable {
    package var id: StableID
    package var index: Int
    package var options: AwakeSessionOptions
    package var since: Double

    package init(id: StableID, index: Int, options: AwakeSessionOptions, since: Double) {
        self.id = id
        self.index = index
        self.options = options
        self.since = since
    }
}

/// What the indicator, menu, Settings status row and CLI show.
package enum AwakeGoverning: Equatable, Sendable {
    case inactive
    case manual(AwakeSession)
    case trigger(TriggerTop)
    /// Non-empty; only when no manual session and no active trigger (N3, N17).
    case holds([AwakeHold])
}

package enum AwakeUnavailableReason: String, Codable, Sendable { case featureOff, safeMode, turnedOffByDefaults }

/// Kit (code M13), so CLI exit mapping and UI copy are tested.
package enum AwakeRefusal: Error, Equatable, Sendable {
    case guardActive(AwakeEndReason)
    case unavailable(AwakeUnavailableReason)
    case invalid
    case notAllowedFromCLI
    case uiSessionRunning
    case holdLimit
    case rateLimited

    /// 4 for every refusal (0.2 CLI table).
    package var exitCode: Int32 { 4 }
    /// Stub: one generic text.
    package var text: String { L("Not built yet") }
}
