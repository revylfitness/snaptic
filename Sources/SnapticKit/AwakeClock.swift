import Foundation

// Awake time (owner: G; PLAN 0.3 §2.3 "Time", N2, N12, R5-14). Continuous time is CLOCK_MONOTONIC_RAW seconds (counts
// sleep, safe to persist with kern.bootsessionuuid); wall time is Unix seconds. Text is hand-formatted (N12).

package struct ClockNow: Equatable, Sendable {
    package var wall: Double
    package var continuous: Double
    package var bootSession: String

    package init(wall: Double, continuous: Double, bootSession: String) {
        self.wall = wall
        self.continuous = continuous
        self.bootSession = bootSession
    }
}

package enum AwakeClock {
    /// Insomnia's cap; extensions included.
    package static let maxSessionSeconds = 30 * 86_400
    /// `awake start` with no argument (C10).
    package static let cliDefaultSeconds = 3_600
    /// `awake hold` without --max; also CLI untilIdle caps.
    package static let holdDefaultCapSeconds = 12 * 3_600
    /// `awake hold --max` upper bound.
    package static let holdMaxCapSeconds = 24 * 3_600
    /// Shortest duration or cap a session takes.
    package static let minimumSessionSeconds = 60
    package static var durationRange: ClosedRange<Int> { minimumSessionSeconds...maxSessionSeconds }
    /// Slack when comparing stored instants (floating error, a sub-second clock read gap).
    package static let toleranceSeconds: Double = 1

    package static func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                              source: AwakeSessionSource, now: ClockNow, id: StableID) -> AwakeSession {
        var kind = kind
        var deadline: Double?
        switch kind {
        case .indefinite, .until:
            deadline = nil
        case .duration(let seconds):
            let s = AwakeMath.clamp(seconds, durationRange)
            kind = .duration(seconds: s)
            deadline = now.continuous + Double(s)
        case .whileApp(let bundleID, let cap):
            let c = cap.map { AwakeMath.clamp($0, durationRange) }
            kind = .whileApp(bundleID: bundleID, maxSeconds: c)
            deadline = c.map { now.continuous + Double($0) }
        case .untilIdle(let spec, let cap):
            let c = cap.map { AwakeMath.clamp($0, durationRange) }
            kind = .untilIdle(spec.sanitized(), maxSeconds: c)
            deadline = c.map { now.continuous + Double($0) }
        }
        return AwakeSession(id: id, kind: kind, options: options.sanitized(), presetID: presetID, source: source,
                            startedAt: now.wall, startedContinuous: now.continuous, deadline: deadline,
                            bootSession: now.bootSession)
    }

    /// The cap is clamped to 60 s ... holdMaxCapSeconds.
    package static func hold(_ binding: HoldBinding, capSeconds: Int, now: ClockNow, id: StableID) -> AwakeHold {
        let cap = AwakeMath.clamp(capSeconds, minimumSessionSeconds...holdMaxCapSeconds)
        return AwakeHold(id: id, binding: binding, startedAt: now.wall, startedContinuous: now.continuous,
                         deadline: now.continuous + Double(cap), bootSession: now.bootSession)
    }

    /// nil = no limit; ≤ 0 = expired. Duration and caps use the continuous deadline; until uses wall time. A session
    /// from another boot has 0 left.
    package static func remaining(_ s: AwakeSession, now: ClockNow) -> Double? {
        guard s.bootSession == now.bootSession else { return 0 }
        switch s.kind {
        case .indefinite:
            return nil
        case .until(let t):
            guard t.isFinite, now.wall.isFinite else { return 0 }
            return t - now.wall
        case .duration, .whileApp, .untilIdle:
            guard let d = s.deadline else { return s.kind.isTaskBound ? nil : 0 }
            guard d.isFinite, now.continuous.isFinite else { return 0 }
            return d - now.continuous
        }
    }

    /// wall + remaining: the end time to show, correct after a clock change.
    package static func endWall(_ s: AwakeSession, now: ClockNow) -> Double? {
        remaining(s, now: now).map { now.wall + max(0, $0) }
    }

    /// Also true when bootSession differs.
    package static func isExpired(_ s: AwakeSession, now: ClockNow) -> Bool {
        guard s.bootSession == now.bootSession else { return true }
        guard let r = remaining(s, now: now) else { return false }
        return r <= 0
    }

    /// The session's end as a continuous instant: `deadline`, or for until-kinds continuous + (unixTime − wall).
    package static func continuousEnd(_ s: AwakeSession, now: ClockNow) -> Double? {
        switch s.kind {
        case .indefinite:
            return nil
        case .until(let t):
            guard t.isFinite, now.wall.isFinite, now.continuous.isFinite else { return nil }
            return now.continuous + (t - now.wall)
        case .duration, .whileApp, .untilIdle:
            guard let d = s.deadline, d.isFinite else { return nil }
            return d
        }
    }

    /// Timed kinds and capped task kinds.
    package static func canExtend(_ s: AwakeSession) -> Bool {
        switch s.kind {
        case .duration, .until: return true
        case .whileApp(_, let cap), .untilIdle(_, let cap): return cap != nil
        case .indefinite: return false
        }
    }

    /// nil when !canExtend, `seconds` ≤ 0 or the session already expired; the result never exceeds maxSessionSeconds
    /// from start (a session already at the limit comes back unchanged).
    package static func extended(_ s: AwakeSession, by seconds: Int, now: ClockNow) -> AwakeSession? {
        guard canExtend(s), seconds > 0, !isExpired(s, now: now) else { return nil }
        let add = min(seconds, maxSessionSeconds)
        var out = s
        switch s.kind {
        case .duration(let total):
            let newTotal = min(AwakeMath.adding(total, add), maxSessionSeconds)
            out.kind = .duration(seconds: max(newTotal, total))
            out.deadline = s.startedContinuous + Double(max(newTotal, total))
        case .until(let t):
            // The 30-day limit counts on the continuous clock from the start, converted to the current wall clock.
            let limitWall = now.wall + (s.startedContinuous + Double(maxSessionSeconds) - now.continuous)
            out.kind = .until(unixTime: max(t, min(t + Double(add), limitWall)))
        case .whileApp(let bundleID, .some(let cap)):
            let c = max(cap, min(AwakeMath.adding(cap, add), maxSessionSeconds))
            out.kind = .whileApp(bundleID: bundleID, maxSeconds: c)
            out.deadline = s.startedContinuous + Double(c)
        case .untilIdle(let spec, .some(let cap)):
            let c = max(cap, min(AwakeMath.adding(cap, add), maxSessionSeconds))
            out.kind = .untilIdle(spec, maxSeconds: c)
            out.deadline = s.startedContinuous + Double(c)
        case .indefinite, .whileApp(_, .none), .untilIdle(_, .none):
            return nil
        }
        return out
    }
}

/// Hand-formatted text (N12).
package enum AwakeCountdown {
    /// Remaining seconds as whole seconds, rounded up; 0 for non-finite or negative values, bounded so Int never traps.
    private static func wholeSeconds(_ remaining: Double) -> Int {
        guard remaining.isFinite, remaining > 0 else { return 0 }
        return Int(min(remaining, 1e12).rounded(.up))
    }

    /// Whole minutes, rounded up.
    private static func wholeMinutes(_ remaining: Double) -> Int {
        guard remaining.isFinite, remaining > 0 else { return 0 }
        return Int((min(remaining, 1e12) / 60).rounded(.up))
    }

    /// ≥ 1 h "1h 42m" ("2h" on the hour), 1–59 min "42m" (rounded up), < 1 min "42s".
    package static func short(_ remaining: Double) -> String {
        let secs = wholeSeconds(remaining)
        if secs < 60 { return "\(secs)s" }
        let m = wholeMinutes(remaining)
        if m < 60 { return "\(m)m" }
        let h = m / 60, mm = m % 60
        return mm == 0 ? "\(h)h" : "\(h)h \(mm)m"
    }

    /// "1 hour 42 minutes remaining", "42 seconds remaining" (VoiceOver, tooltip).
    package static func spoken(_ remaining: Double) -> String {
        let secs = wholeSeconds(remaining)
        if secs < 60 { return L("\(unit(secs, "second", "seconds")) remaining") }
        let m = wholeMinutes(remaining)
        if m < 60 { return L("\(unit(m, "minute", "minutes")) remaining") }
        let h = m / 60, mm = m % 60
        if mm == 0 { return L("\(unit(h, "hour", "hours")) remaining") }
        return L("\(unit(h, "hour", "hours")) \(unit(mm, "minute", "minutes")) remaining")
    }

    /// "5:00 PM" or "17:00" from local hour and minute (the app converts the instant with Calendar).
    package static func clock(hour: Int, minute: Int, uses24Hour: Bool) -> String {
        let h = ((hour % 24) + 24) % 24
        let m = ((minute % 60) + 60) % 60
        let mm = m < 10 ? "0\(m)" : "\(m)"
        if uses24Hour { return (h < 10 ? "0\(h)" : "\(h)") + ":" + mm }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(mm) " + (h < 12 ? "AM" : "PM")
    }

    /// Seconds until `short` changes (minute boundary, or 1 s steps in the last minute); never 0.
    package static func nextChange(_ remaining: Double) -> Double {
        guard remaining.isFinite else { return 60 }
        guard remaining > 0 else { return 1 }
        let r = min(remaining, 1e12)
        let secs = wholeSeconds(r)
        let threshold: Double
        if secs < 60 {
            threshold = Double(secs - 1)
        } else {
            let m = wholeMinutes(r)
            threshold = m == 1 ? 59 : Double(m - 1) * 60
        }
        let delta = r - threshold
        return delta > 0 ? delta : 1
    }

    /// "1 hour", "2 minutes".
    package static func unit(_ n: Int, _ one: String, _ many: String) -> String { "\(n) " + (n == 1 ? one : many) }
}

/// CLI and the "Custom…" panel. "until 17:30" stays a clock request; the app resolves it with Calendar (DST-correct).
package enum AwakeDurationRequest: Equatable, Sendable {
    case indefinite, untilIdle
    case duration(seconds: Int)
    case untilClock(hour: Int, minute: Int)
}

package enum AwakeDurationGrammar {
    package static let maxDigits = 7, maxDecimals = 2

    /// "90", "90m", "1h30m", "2h", "1.5h", "1h 30m", "until 17:30", "until 5:30pm", "until 5:30 pm", "indefinite",
    /// "forever", "idle". A bare number is minutes. Numbers: ASCII digits only, ≤ 7 digits, ≤ 2 decimals, no sign or
    /// exponent; durations are 60 s ... 30 days, computed in hundredths with overflow checks. Never traps.
    package static func parse(_ words: [String]) -> AwakeDurationRequest? {
        guard !words.isEmpty, words.count <= 8 else { return nil }
        let lowered = words.map(asciiLowercased)
        guard lowered.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32 }) else { return nil }
        if lowered.count == 1 {
            switch lowered[0] {
            case "indefinite", "forever": return .indefinite
            case "idle": return .untilIdle
            default: break
            }
        }
        if lowered[0] == "until" {
            guard lowered.count >= 2, lowered.count <= 3 else { return nil }
            return clock(lowered.dropFirst().joined())
        }
        return duration(lowered.joined(separator: " ")).map { .duration(seconds: $0) }
    }

    /// Seconds for one duration word sequence already joined, or nil.
    package static func durationSeconds(_ words: [String]) -> Int? {
        guard case .duration(let s)? = parse(words) else { return nil }
        return s
    }

    private static func asciiLowercased(_ s: String) -> String {
        String(decoding: s.utf8.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }, as: UTF8.self)
    }

    /// A number in hundredths ("1.5" → 150), or nil.
    private static func hundredths(_ bytes: ArraySlice<UInt8>) -> Int? {
        var intPart = 0, intDigits = 0, frac = 0, fracDigits = 0, seenDot = false
        for b in bytes {
            if b == 0x2E {
                guard !seenDot, intDigits > 0 else { return nil }
                seenDot = true
            } else if (0x30...0x39).contains(b) {
                let d = Int(b - 0x30)
                if seenDot {
                    fracDigits += 1
                    guard fracDigits <= maxDecimals else { return nil }
                    frac = frac * 10 + d
                } else {
                    intDigits += 1
                    guard intDigits <= maxDigits else { return nil }
                    intPart = intPart * 10 + d
                }
            } else {
                return nil
            }
        }
        guard intDigits > 0, !(seenDot && fracDigits == 0) else { return nil }
        if fracDigits == 1 { frac *= 10 }
        return intPart * 100 + frac
    }

    private static let units: [(names: [String], seconds: Int)] = [
        (["d", "day", "days"], 86_400),
        (["h", "hr", "hrs", "hour", "hours"], 3_600),
        (["m", "min", "mins", "minute", "minutes"], 60),
    ]

    private static func duration(_ text: String) -> Int? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return nil }
        var i = 0
        var total = 0
        var lastUnit = Int.max
        var terms = 0
        while i < bytes.count {
            while i < bytes.count, bytes[i] == 0x20 { i += 1 }
            guard i < bytes.count else { break }
            let numberStart = i
            while i < bytes.count, (0x30...0x39).contains(bytes[i]) || bytes[i] == 0x2E { i += 1 }
            guard i > numberStart, let value = hundredths(bytes[numberStart..<i]) else { return nil }
            let unitStart = i
            while i < bytes.count, (0x61...0x7A).contains(bytes[i]) { i += 1 }
            let unitText = String(decoding: bytes[unitStart..<i], as: UTF8.self)
            let unitSeconds: Int
            if unitText.isEmpty {
                // A bare number is minutes, and only on its own.
                guard terms == 0, i == bytes.count else { return nil }
                unitSeconds = 60
            } else {
                guard let u = units.first(where: { $0.names.contains(unitText) }) else { return nil }
                unitSeconds = u.seconds
            }
            // Units only descend (1h30m, not 30m1h) and appear once.
            guard unitSeconds < lastUnit else { return nil }
            lastUnit = unitSeconds
            let (product, overflow) = value.multipliedReportingOverflow(by: unitSeconds)
            guard !overflow else { return nil }
            let (sum, overflow2) = total.addingReportingOverflow(product)
            guard !overflow2, sum <= AwakeClock.maxSessionSeconds * 100 else { return nil }
            total = sum
            terms += 1
        }
        let seconds = (total + 99) / 100
        guard AwakeClock.durationRange.contains(seconds) else { return nil }
        return seconds
    }

    /// "17:30", "5:30pm", "5pm", "12am". 24-hour without a suffix; 1...12 with am/pm.
    private static func clock(_ text: String) -> AwakeDurationRequest? {
        var bytes = Array(text.utf8)
        var meridiem: Int?   // 0 am, 12 pm
        if bytes.count >= 2, bytes[bytes.count - 1] == 0x6D {
            let m = bytes[bytes.count - 2]
            if m == 0x61 { meridiem = 0 } else if m == 0x70 { meridiem = 12 } else { return nil }
            bytes.removeLast(2)
        }
        guard !bytes.isEmpty, bytes.allSatisfy({ (0x30...0x39).contains($0) || $0 == 0x3A }) else { return nil }
        let parts = bytes.split(separator: 0x3A, omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, (1...2).contains(parts[0].count) else { return nil }
        let hour = parts[0].reduce(0) { $0 * 10 + Int($1 - 0x30) }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2 else { return nil }
            minute = parts[1].reduce(0) { $0 * 10 + Int($1 - 0x30) }
        } else if meridiem == nil {
            return nil   // a bare "17" is not a clock time
        }
        guard (0...59).contains(minute) else { return nil }
        if let mer = meridiem {
            guard (1...12).contains(hour) else { return nil }
            return .untilClock(hour: hour % 12 + mer, minute: minute)
        }
        guard (0...23).contains(hour) else { return nil }
        return .untilClock(hour: hour, minute: minute)
    }
}

/// R5-14 (consistency m6): read from the system locale once (N12).
package struct AwakeTextContext: Equatable, Sendable {
    package var uses24Hour: Bool
    package var decimalSeparator: String

    package init(uses24Hour: Bool, decimalSeparator: String) {
        self.uses24Hour = uses24Hour
        self.decimalSeparator = decimalSeparator
    }

    /// Kit's fallback where a caller has no locale facts (tests, logs): 12-hour, ".".
    package static let standard = AwakeTextContext(uses24Hour: false, decimalSeparator: ".")
}
