import Foundation

// SessionController's pure decisions (owner: G; PLAN 0.3 §2.5, §2.10, R5-1, R5-10): start admission, the CLI rate
// limit, Turn Off targets and their notices, reminders, the tick schedule and the pointer-confirmation prompt. The app
// controller only performs the side effects these return, so every rule here is tested on Linux.

/// Start admission (§2.5 rules, §2.10 CLI table).
package enum AwakeStartRules {
    /// nil = the start may proceed. CLI starts may not be indefinite (`.notAllowedFromCLI`) and never replace a
    /// session started in Snaptic's own UI (`.uiSessionRunning`, security L4). A rule never starts a manual session.
    /// Kinds out of range are `.invalid` (a duration outside 60 s … 30 days, an until-instant not in the future or
    /// more than 30 days away, an invalid bundle id, a cap out of range).
    package static func refusal(kind: AwakeSessionKind, source: AwakeSessionSource, current: AwakeSession?,
                                now: ClockNow) -> AwakeRefusal? {
        if source == .rule { return .invalid }
        if source == .commandLine {
            if case .indefinite = kind { return .notAllowedFromCLI }
            if let c = current, c.source.isDirectUserAction { return .uiSessionRunning }
        }
        func capOK(_ cap: Int?) -> Bool { cap.map { AwakeClock.durationRange.contains($0) } ?? true }
        switch kind {
        case .indefinite:
            return nil
        case .duration(let s):
            return AwakeClock.durationRange.contains(s) ? nil : .invalid
        case .until(let t):
            guard t.isFinite, now.wall.isFinite else { return .invalid }
            let ahead = t - now.wall
            return ahead >= 1 && ahead <= Double(AwakeClock.maxSessionSeconds) ? nil : .invalid
        case .whileApp(let bundleID, let cap):
            return AwakeBundleID.isValid(bundleID) && capOK(cap) ? nil : .invalid
        case .untilIdle(_, let cap):
            return capOK(cap) ? nil : .invalid
        }
    }

    /// CLI untilIdle starts and CLI presets of an uncapped untilIdle preset get the 12 h cap (parity minor 7).
    package static func cliCapped(_ kind: AwakeSessionKind) -> AwakeSessionKind {
        if case .untilIdle(let spec, nil) = kind { return .untilIdle(spec, maxSeconds: AwakeClock.holdDefaultCapSeconds) }
        return kind
    }

    /// The CLI session kind for a parsed `awake start` request. `untilClock` needs the app's Calendar resolution
    /// (`untilUnix`); nil = no argument (1 h, C10).
    package static func cliKind(_ request: AwakeDurationRequest?, untilUnix: Double?) -> AwakeSessionKind? {
        switch request {
        case nil: return .duration(seconds: AwakeClock.cliDefaultSeconds)
        case .indefinite?: return .indefinite
        case .untilIdle?: return cliCapped(.untilIdle(UntilIdleSpec(), maxSeconds: nil))
        case .duration(let s)?: return .duration(seconds: s)
        case .untilClock?: return untilUnix.flatMap { $0.isFinite ? .until(unixTime: $0) : nil }
        }
    }
}

/// `start`, `hold`, `stop` and `extend` share one request per second (security L3), on Snaptic's continuous clock.
package struct AwakeRateLimiter: Equatable, Sendable {
    package static let intervalSeconds: Double = 1
    package private(set) var last: Double?

    package init() {}

    /// true (and remembers `now`) when at least a second passed since the last allowed request.
    package mutating func allow(now: Double) -> Bool {
        guard now.isFinite else { return false }
        if let l = last, now >= l, now - l < Self.intervalSeconds { return false }
        last = now
        return true
    }
}

/// What a user Turn Off ends (R5-10), and what is still keeping the Mac awake afterwards.
package enum AwakeTurnOffTarget: Equatable, Sendable { case manual, trigger(StableID), holds, nothing }
package enum AwakeTurnOffNotice: Equatable, Sendable {
    /// "Rules can still keep your Mac awake." [Turn Off “<rule>”] [Pause Rules]
    case rules(StableID)
    /// "Terminal is still keeping your Mac awake." [End Command-Line Holds]
    case holds
}

package enum AwakeTurnOff {
    /// Turn Off ends what governs: the manual session, the governing rule's session, or the hold stack.
    package static func target(_ governing: AwakeGoverning) -> AwakeTurnOffTarget {
        switch governing {
        case .inactive: return .nothing
        case .manual: return .manual
        case .trigger(let top): return .trigger(top.id)
        case .holds: return .holds
        }
    }

    /// The governing state after a Turn Off: a rule → its notice; only holds → the holds notice; nothing → none.
    package static func notice(after governing: AwakeGoverning) -> AwakeTurnOffNotice? {
        switch governing {
        case .trigger(let top): return .rules(top.id)
        case .holds: return .holds
        case .inactive, .manual: return nil
        }
    }
}

/// The 5-minute and 8-hour reminders (§2.5): each fires once per session (the 5-minute one again after the end
/// moved, e.g. Add 1 Hour).
package struct AwakeReminders: Equatable, Sendable {
    package static let fiveMinuteSeconds: Double = 300
    package static let minimumRunSeconds: Double = 900
    package static let longSessionSeconds: Double = 8 * 3_600

    package enum Reminder: Equatable, Sendable { case fiveMinutes, eightHours }

    package private(set) var fiveFor: StableID?
    package private(set) var fiveEnd: Double?
    package private(set) var eightFor: StableID?

    package init() {}

    /// The reminder due now, recorded as shown. Timed sessions (duration, until) that ran ≥ 15 min remind once
    /// with ≤ 5 min (and > 0) left; an indefinite session reminds once after 8 hours.
    package mutating func due(_ session: AwakeSession?, now: ClockNow) -> Reminder? {
        guard let s = session, s.bootSession == now.bootSession else { return nil }
        let ran = now.continuous - s.startedContinuous
        if s.kind.isTimed, let left = AwakeClock.remaining(s, now: now), let end = AwakeClock.continuousEnd(s, now: now),
           left > 0, left <= Self.fiveMinuteSeconds, ran >= Self.minimumRunSeconds {
            let already = fiveFor == s.id && fiveEnd.map { abs($0 - end) <= AwakeArbiter.rearmThresholdSeconds } == true
            if !already {
                fiveFor = s.id
                fiveEnd = end
                return .fiveMinutes
            }
        }
        if case .indefinite = s.kind, ran >= Self.longSessionSeconds, eightFor != s.id {
            eightFor = s.id
            return .eightHours
        }
        return nil
    }

    /// Seconds until the next reminder could fire (for the tick); nil when none is pending.
    package func nextDue(_ session: AwakeSession?, now: ClockNow) -> Double? {
        guard let s = session, s.bootSession == now.bootSession else { return nil }
        let ran = now.continuous - s.startedContinuous
        if s.kind.isTimed, let left = AwakeClock.remaining(s, now: now), let end = AwakeClock.continuousEnd(s, now: now),
           left > 0 {
            let done = fiveFor == s.id && fiveEnd.map { abs($0 - end) <= AwakeArbiter.rearmThresholdSeconds } == true
            if !done {
                let atLeft = left - Self.fiveMinuteSeconds
                let atRun = Self.minimumRunSeconds - ran
                let wait = max(atLeft, atRun, 0)
                if wait < left { return wait }
            }
            return nil
        }
        if case .indefinite = s.kind, eightFor != s.id { return max(0, Self.longSessionSeconds - ran) }
        return nil
    }
}

/// The SessionController tick (§2.5): the countdown's next change, the earliest expiry of the manual session or a
/// hold, and the next reminder; never sooner than 0.25 s, never later than an hour (wake and clock checks cover the
/// rest).
package enum AwakeTick {
    package static let minimum: Double = 0.25
    package static let maximum: Double = 3_600

    package static func next(manual: AwakeSession?, holds: [AwakeHold], reminders: AwakeReminders,
                             now: ClockNow) -> Double? {
        var candidates: [Double] = []
        if let m = manual {
            if let r = AwakeClock.remaining(m, now: now) {
                candidates.append(max(0, r))
                if r > 0 { candidates.append(AwakeCountdown.nextChange(r)) }
            }
            if let d = reminders.nextDue(m, now: now) { candidates.append(d) }
        }
        for h in holds { candidates.append(max(0, h.remaining(now: now))) }
        guard let soonest = candidates.filter(\.isFinite).min() else { return nil }
        return min(max(soonest, minimum), maximum)
    }
}

/// The hotkey pointer-movement confirmation (R5-1): bound to the session it was shown for. `confirmAsked` only when
/// the toast was actually shown; Allow, Not Now and dismissal apply only while that session still governs as the
/// manual session.
package struct AwakePointerPrompt: Equatable, Sendable {
    package private(set) var sessionID: StableID?

    package init() {}

    package var isShowing: Bool { sessionID != nil }

    /// The toast was offered for `session`; `shown` is ToastPresenter.show's result.
    package mutating func offered(session: StableID, shown: Bool) -> AwakeActivityGate.Event? {
        guard shown else { return nil }
        sessionID = session
        return .confirmAsked
    }

    /// Allow: `.confirmAllowed` only if the toast's session is still the governing manual session.
    package mutating func allowed(governingManual: StableID?) -> AwakeActivityGate.Event? {
        defer { sessionID = nil }
        guard let s = sessionID, s == governingManual else { return nil }
        return .confirmAllowed
    }

    /// Not Now or any dismissal: `.confirmDeclined` for the toast's session only.
    package mutating func declined(governingManual: StableID?) -> AwakeActivityGate.Event? {
        defer { sessionID = nil }
        guard let s = sessionID, s == governingManual else { return nil }
        return .confirmDeclined
    }

    /// The session ended or was replaced: forget the prompt.
    package mutating func reset() { sessionID = nil }
}

/// Session-ending policies that depend on system events (§2.12).
package enum AwakeSystemPolicy {
    /// Off console this long ends `.userSwitch` with `.afterHour`.
    package static let userSwitchGraceSeconds: Double = 3_600

    /// The end reason for the current session facts, or nil. `offConsoleSince`/`lockedSince` are continuous instants.
    package static func end(behavior: AwakeBehavior, onConsole: Bool, offConsoleSince: Double?, locked: Bool,
                            lockedSince: Double?, now: Double) -> AwakeEndReason? {
        if !onConsole {
            switch behavior.userSwitchEnd {
            case .immediately: return .userSwitch
            case .afterHour:
                if let since = offConsoleSince, now - since >= userSwitchGraceSeconds { return .userSwitch }
            case .never: break
            }
        }
        if locked, let hours = behavior.endAfterLockedHours, let since = lockedSince,
           now - since >= Double(hours) * 3_600 {
            return .lockedTooLong
        }
        return nil
    }

    /// Seconds until `end` could first return a reason (for a one-shot timer); nil when nothing is pending.
    package static func nextCheck(behavior: AwakeBehavior, onConsole: Bool, offConsoleSince: Double?, locked: Bool,
                                  lockedSince: Double?, now: Double) -> Double? {
        var out: [Double] = []
        if !onConsole, behavior.userSwitchEnd == .afterHour, let since = offConsoleSince {
            out.append(max(0, since + userSwitchGraceSeconds - now))
        }
        if locked, let hours = behavior.endAfterLockedHours, let since = lockedSince {
            out.append(max(0, since + Double(hours) * 3_600 - now))
        }
        return out.min()
    }
}
