import Foundation

// Awake session model (owner: G; PLAN 0.3 §2.3, R5-4, R5-14). Pure values: the app's SessionController owns the
// runtime, Kit owns every rule that can be stated without the system.

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
    package static let displayIdleMinutesRange: ClosedRange<Int> = 1...240

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

    package func sanitized() -> AwakeSessionOptions {
        var o = self
        o.displayIdleMinutes = AwakeMath.clamp(displayIdleMinutes, Self.displayIdleMinutesRange)
        return o
    }

    /// Rules never move the pointer (N10): `.nudge` becomes `.declare`.
    package func withoutNudge() -> AwakeSessionOptions {
        var o = self
        if o.activity == .nudge { o.activity = .declare }
        return o
    }
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

    package static let topProcessRange: ClosedRange<Int> = 10...800
    package static let newProcessesRange: ClosedRange<Int> = 1...50
    package static let totalCPURange: ClosedRange<Int> = 1...90
    package static let diskRange: ClosedRange<Int> = 64...1_000_000
    package static let networkRange: ClosedRange<Int> = 1...100_000
    package static let quietRange: ClosedRange<Int> = 60...3_600
    package static let minimumHoldRange: ClosedRange<Int> = 0...3_600

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

    package func sanitized() -> UntilIdleSpec {
        UntilIdleSpec(topProcessPercent: AwakeMath.clamp(topProcessPercent, Self.topProcessRange),
                      newProcesses: AwakeMath.clamp(newProcesses, Self.newProcessesRange),
                      totalCPUPercent: AwakeMath.clamp(totalCPUPercent, Self.totalCPURange),
                      diskKBps: AwakeMath.clamp(diskKBps, Self.diskRange),
                      networkKBps: AwakeMath.clamp(networkKBps, Self.networkRange),
                      quietSeconds: AwakeMath.clamp(quietSeconds, Self.quietRange),
                      minimumHoldSeconds: AwakeMath.clamp(minimumHoldSeconds, Self.minimumHoldRange))
    }
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

    /// A sample with every signal unknown (a missing sample, or the first one after a wake).
    package static let unknown = TaskActivitySample(topProcessPercent: nil, newProcesses: nil, totalCPUPercent: nil,
                                                    diskKBps: nil, networkKBps: nil)
}

package enum TaskQuiet {
    /// Busy when any signal is unknown, not finite, or at or above its threshold (an unknown never ends a session).
    package static func isBusy(_ s: TaskActivitySample, spec: UntilIdleSpec) -> Bool {
        let spec = spec.sanitized()
        guard let top = s.topProcessPercent, let fresh = s.newProcesses, let total = s.totalCPUPercent,
              let disk = s.diskKBps, let net = s.networkKBps else { return true }
        guard top.isFinite, total.isFinite, disk.isFinite, net.isFinite else { return true }
        if top >= Double(spec.topProcessPercent) { return true }
        if fresh >= spec.newProcesses { return true }
        if total >= Double(spec.totalCPUPercent) { return true }
        if disk >= Double(spec.diskKBps) { return true }
        return net >= Double(spec.networkKBps)
    }

    /// quietSince: continuous instant of the first quiet sample in the current run (nil while busy). `started`: R5-4.
    /// Finished once the quiet run has lasted `quietSeconds` and `minimumHoldSeconds` have passed since `started`.
    package static func step(quietSince: Double?, sample: TaskActivitySample, now: Double, started: Double,
                             spec: UntilIdleSpec) -> (quietSince: Double?, finished: Bool) {
        let spec = spec.sanitized()
        guard now.isFinite, !isBusy(sample, spec: spec) else { return (nil, false) }
        var since = now
        if let q = quietSince, q.isFinite, q <= now { since = q }
        let quietLongEnough = now - since >= Double(spec.quietSeconds)
        let heldLongEnough = !started.isFinite || now - started >= Double(spec.minimumHoldSeconds)
        return (since, quietLongEnough && heldLongEnough && started.isFinite)
    }

    /// Seconds of the current quiet run; nil while busy.
    package static func quietFor(quietSince: Double?, now: Double) -> Double? {
        guard let q = quietSince, q.isFinite, now.isFinite else { return nil }
        return max(0, now - q)
    }
}

/// Reverse-DNS bundle identifiers as Awake stores them (app sessions, rules, recent apps).
package enum AwakeBundleID {
    package static let maxBytes = 255

    /// ASCII letters, digits, "-", "_" and ".", at least two non-empty components, ≤ 255 bytes.
    package static func isValid(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        guard !bytes.isEmpty, bytes.count <= maxBytes else { return false }
        var components = 1
        var componentLength = 0
        for b in bytes {
            switch b {
            case 0x2E:
                guard componentLength > 0 else { return false }
                components += 1
                componentLength = 0
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F:
                componentLength += 1
            default:
                return false
            }
        }
        return components >= 2 && componentLength > 0
    }
}

/// Small numeric helpers shared by the Awake Kit files.
package enum AwakeMath {
    package static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }

    package static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        guard v.isFinite else { return lo }
        return min(max(v, lo), hi)
    }

    /// Saturating Int addition (never traps).
    package static func adding(_ a: Int, _ b: Int) -> Int {
        let (r, overflow) = a.addingReportingOverflow(b)
        if overflow { return b > 0 ? Int.max : Int.min }
        return r
    }
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

    package var isProcess: Bool {
        if case .process = self { return true }
        return false
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
    package var isTimed: Bool {
        switch self {
        case .duration, .until: return true
        case .indefinite, .whileApp, .untilIdle: return false
        }
    }

    /// whileApp/untilIdle cap.
    package var cap: Int? {
        switch self {
        case .whileApp(_, let m), .untilIdle(_, let m): return m
        case .indefinite, .duration, .until: return nil
        }
    }

    /// whileApp, untilIdle.
    package var isTaskBound: Bool {
        switch self {
        case .whileApp, .untilIdle: return true
        case .indefinite, .duration, .until: return false
        }
    }

    /// The history kind this session records.
    package var historyKind: AwakeHistoryKind {
        switch self {
        case .indefinite: return .indefinite
        case .duration: return .duration
        case .until: return .until
        case .whileApp: return .app
        case .untilIdle: return .idle
        }
    }
}

private enum SessionKindKey: String, CodingKey { case type, seconds, unixTime, bundleID, maxSeconds, spec, pid, startTime }

extension AwakeSessionKind: Codable {
    /// Type-tagged: {"type":"duration","seconds":5400}. An unknown type (incl. r3 drafts' "hold") or a missing
    /// required field throws, so the stored session is dropped.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SessionKindKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "indefinite":
            self = .indefinite
        case "duration":
            self = .duration(seconds: try c.decode(Int.self, forKey: .seconds))
        case "until":
            let t = try c.decode(Double.self, forKey: .unixTime)
            guard t.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .unixTime, in: c, debugDescription: "Not finite")
            }
            self = .until(unixTime: t)
        case "whileApp":
            self = .whileApp(bundleID: try c.decode(String.self, forKey: .bundleID),
                             maxSeconds: c.lossy(.maxSeconds, nil))
        case "untilIdle":
            self = .untilIdle(c.lossy(.spec, UntilIdleSpec()), maxSeconds: c.lossy(.maxSeconds, nil))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown session kind")
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SessionKindKey.self)
        switch self {
        case .indefinite:
            try c.encode("indefinite", forKey: .type)
        case .duration(let seconds):
            try c.encode("duration", forKey: .type)
            try c.encode(seconds, forKey: .seconds)
        case .until(let t):
            try c.encode("until", forKey: .type)
            try c.encode(t, forKey: .unixTime)
        case .whileApp(let bundleID, let maxSeconds):
            try c.encode("whileApp", forKey: .type)
            try c.encode(bundleID, forKey: .bundleID)
            try c.encodeIfPresent(maxSeconds, forKey: .maxSeconds)
        case .untilIdle(let spec, let maxSeconds):
            try c.encode("untilIdle", forKey: .type)
            try c.encode(spec, forKey: .spec)
            try c.encodeIfPresent(maxSeconds, forKey: .maxSeconds)
        }
    }
}

extension HoldBinding: Codable {
    /// `.connection` never decodes (that hold is dropped); `.process` needs pid and startTime.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SessionKindKey.self)
        switch try c.decode(String.self, forKey: .type) {
        case "process":
            self = .process(pid: try c.decode(Int32.self, forKey: .pid), startTime: try c.decode(UInt64.self, forKey: .startTime))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Hold binding not restorable")
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SessionKindKey.self)
        switch self {
        case .connection(let pid, let t):
            try c.encode("connection", forKey: .type)
            try c.encode(pid, forKey: .pid)
            try c.encode(t, forKey: .startTime)
        case .process(let pid, let t):
            try c.encode("process", forKey: .type)
            try c.encode(pid, forKey: .pid)
            try c.encode(t, forKey: .startTime)
        }
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

    /// Seconds left on the cap (≤ 0 = expired, or 0 from another boot).
    package func remaining(now: ClockNow) -> Double {
        guard bootSession == now.bootSession, deadline.isFinite, now.continuous.isFinite else { return 0 }
        return deadline - now.continuous
    }

    /// nil when expired, from another boot, started after now, deadline − start > holdMaxCap, or pid ≤ 1.
    package func sanitized(now: ClockNow) -> AwakeHold? {
        guard !bootSession.isEmpty, bootSession == now.bootSession else { return nil }
        guard startedAt.isFinite, startedContinuous.isFinite, deadline.isFinite, now.continuous.isFinite else { return nil }
        guard binding.pid > 1, startedContinuous >= 0, startedContinuous <= now.continuous else { return nil }
        guard deadline > startedContinuous,
              deadline - startedContinuous <= Double(AwakeClock.holdMaxCapSeconds) + AwakeClock.toleranceSeconds
        else { return nil }
        guard deadline > now.continuous else { return nil }
        return self
    }
}

/// Persisted and kept through restore (security L1: a restored CLI session stays `.commandLine`).
package enum AwakeSessionSource: String, Codable, Sendable {
    case menu, hotkey, settings, commandLine, launch
    /// R5-14: history and policy only (trigger sessions); sanitized(now:) drops a manual session with it.
    case rule

    /// menu, hotkey, settings: a direct user action in Snaptic's own UI (N10).
    package var isDirectUserAction: Bool {
        switch self {
        case .menu, .hotkey, .settings: return true
        case .commandLine, .launch, .rule: return false
        }
    }
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
    /// mismatch (r3 security L3); also for a `.rule` source (R5-14). Options are clamped; the source is kept.
    package func sanitized(now: ClockNow) -> AwakeSession? {
        guard source != .rule, !bootSession.isEmpty, bootSession == now.bootSession else { return nil }
        guard startedAt.isFinite, startedContinuous.isFinite, now.continuous.isFinite, now.wall.isFinite else { return nil }
        guard startedContinuous >= 0, startedContinuous <= now.continuous else { return nil }
        let tolerance = AwakeClock.toleranceSeconds
        let maxSpan = Double(AwakeClock.maxSessionSeconds)
        var s = self
        s.overrideGuards = false
        s.options = options.sanitized()
        switch kind {
        case .indefinite:
            guard deadline == nil else { return nil }
        case .duration(let seconds):
            guard AwakeClock.durationRange.contains(seconds), let d = deadline, d.isFinite,
                  abs(d - (startedContinuous + Double(seconds))) <= tolerance else { return nil }
        case .until(let t):
            // Wall based: the end must lie within the 30-day cap of the wall start and after it.
            guard deadline == nil, t.isFinite, t > startedAt, t - startedAt <= maxSpan + tolerance else { return nil }
        case .whileApp(let bundleID, let maxSeconds):
            guard AwakeBundleID.isValid(bundleID), Self.capMatches(maxSeconds, deadline, start: startedContinuous)
            else { return nil }
        case .untilIdle(let spec, let maxSeconds):
            guard Self.capMatches(maxSeconds, deadline, start: startedContinuous) else { return nil }
            s.kind = .untilIdle(spec.sanitized(), maxSeconds: maxSeconds)
        }
        guard !AwakeClock.isExpired(s, now: now) else { return nil }
        return s
    }

    /// Both nil, or the cap is in range and the deadline is start + cap (r3 security L3).
    private static func capMatches(_ cap: Int?, _ deadline: Double?, start: Double) -> Bool {
        switch (cap, deadline) {
        case (nil, nil):
            return true
        case (let cap?, let d?):
            return AwakeClock.durationRange.contains(cap) && d.isFinite
                && abs(d - (start + Double(cap))) <= AwakeClock.toleranceSeconds
        default:
            return false
        }
    }
}

package enum AwakeEndReason: String, Codable, CaseIterable, Sendable {
    case user, timeUp, appQuit, processExited, tasksFinished, replaced, triggerEnded, batteryLow,
         adapterDisconnected, lowPowerMode, thermal, systemSleep, userSwitch, lockedTooLong, moduleStopped, safeMode,
         reboot, assertionFailed, commandLineOff

    /// Ends the user chose (no end toast, no "Last end" line).
    package var isUserEnd: Bool {
        switch self {
        case .user, .replaced: return true
        default: return false
        }
    }
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

    package var isActive: Bool {
        if case .inactive = self { return false }
        return true
    }

    /// The source a policy sees (R5-14): `.rule` for a trigger session, `.commandLine` for the holds-only state.
    package var source: AwakeSessionSource? {
        switch self {
        case .inactive: return nil
        case .manual(let s): return s.source
        case .trigger: return .rule
        case .holds: return .commandLine
        }
    }

    /// The governing display policy (holds have no options: the display may sleep).
    package var options: AwakeSessionOptions? {
        switch self {
        case .inactive: return nil
        case .manual(let s): return s.options
        case .trigger(let t): return t.options
        case .holds: return AwakeSessionOptions(display: .maySleep)
        }
    }
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
    /// The session started but its own first arbitration ended it (off console longer than allowed, locked too
    /// long, the assertion couldn't be created): the reply names that end (awake-correctness N2).
    case endedAtStart(AwakeEndReason)

    /// 4 for every refusal (0.2 CLI table).
    package var exitCode: Int32 { 4 }

    package var text: String {
        switch self {
        case .guardActive(let reason):
            switch reason {
            case .batteryLow: return L("The battery is too low to keep your Mac awake.")
            case .lowPowerMode: return L("Low Power Mode is on.")
            case .thermal: return L("Your Mac is too hot to keep awake right now.")
            case .adapterDisconnected: return L("The power adapter is disconnected.")
            default: return L("Awake can't start right now.")
            }
        case .unavailable(let reason):
            switch reason {
            case .featureOff: return L("Awake is turned off.")
            case .safeMode: return L("This isn't available in Safe Mode.")
            case .turnedOffByDefaults: return DefaultsLock.text
            }
        case .invalid:
            return L("That session can't start. Check the duration, the app or the process.")
        case .notAllowedFromCLI:
            return L("Sessions without an end can't start from the command line. Use the menu or “snaptic awake hold”.")
        case .uiSessionRunning:
            return L("A session started in Snaptic is running. Stop it first with “snaptic awake stop”, or use “snaptic awake hold”.")
        case .holdLimit:
            return L("Snaptic is already holding for 8 commands.")
        case .rateLimited:
            return L("Too many requests. Try again in a second.")
        case .endedAtStart(let reason):
            switch reason {
            case .userSwitch: return L("Awake ended at once: another user is using this Mac.")
            case .lockedTooLong: return L("Awake ended at once: the screen has been locked too long.")
            case .assertionFailed: return L("Snaptic couldn't keep your Mac awake. Try again, or restart Snaptic.")
            default:
                return L("Awake ended at once: ") + AwakeEndText.phrase(reason, floor: AwakeGuards.hardFloorPercent,
                                                                       appName: nil, lockedHours: nil) + "."
            }
        }
    }
}
