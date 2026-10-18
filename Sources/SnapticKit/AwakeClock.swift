import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.3 + R5-14 (kind S): safe returns.

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

    package static func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions, presetID: StableID?,
                              source: AwakeSessionSource, now: ClockNow, id: StableID) -> AwakeSession {
        AwakeSession(id: id, kind: kind, options: options, presetID: presetID, source: source, startedAt: now.wall,
                     startedContinuous: now.continuous, deadline: nil, bootSession: now.bootSession)
    }

    package static func hold(_ binding: HoldBinding, capSeconds: Int, now: ClockNow, id: StableID) -> AwakeHold {
        AwakeHold(id: id, binding: binding, startedAt: now.wall, startedContinuous: now.continuous,
                  deadline: now.continuous, bootSession: now.bootSession)
    }

    /// nil = no limit; ≤ 0 = expired. Stub: 0.
    package static func remaining(_ s: AwakeSession, now: ClockNow) -> Double? { 0 }
    /// wall + remaining. Stub: nil.
    package static func endWall(_ s: AwakeSession, now: ClockNow) -> Double? { nil }
    /// Also true when bootSession differs. Stub: true.
    package static func isExpired(_ s: AwakeSession, now: ClockNow) -> Bool { true }
    /// The session's end as a continuous instant. Stub: nil.
    package static func continuousEnd(_ s: AwakeSession, now: ClockNow) -> Double? { nil }
    /// Timed kinds and capped task kinds. Stub: false.
    package static func canExtend(_ s: AwakeSession) -> Bool { false }
    /// nil when !canExtend. Stub: nil.
    package static func extended(_ s: AwakeSession, by seconds: Int, now: ClockNow) -> AwakeSession? { nil }
}

/// Hand-formatted text (N12).
package enum AwakeCountdown {
    /// ≥ 1 h "1h 42m" ("2h" on the hour), 1–59 min "42m" (rounded up), < 1 min "42s". Stub: "".
    package static func short(_ remaining: Double) -> String { "" }
    /// "1 hour 42 minutes remaining". Stub: "".
    package static func spoken(_ remaining: Double) -> String { "" }
    /// "5:00 PM" or "17:00". Stub: "".
    package static func clock(hour: Int, minute: Int, uses24Hour: Bool) -> String { "" }
    /// Seconds until `short` changes; never 0. Stub: 60.
    package static func nextChange(_ remaining: Double) -> Double { 60 }
}

/// CLI and the "Custom…" panel.
package enum AwakeDurationRequest: Equatable, Sendable {
    case indefinite, untilIdle
    case duration(seconds: Int)
    case untilClock(hour: Int, minute: Int)
}

package enum AwakeDurationGrammar {
    package static let maxDigits = 7, maxDecimals = 2
    /// "90", "90m", "1h30m", "2h", "1.5h", "until 17:30", … Never traps. Stub: nil.
    package static func parse(_ words: [String]) -> AwakeDurationRequest? { nil }
}

/// R5-14 (consistency m6): read from the system locale once (N12).
package struct AwakeTextContext: Equatable, Sendable {
    package var uses24Hour: Bool
    package var decimalSeparator: String

    package init(uses24Hour: Bool, decimalSeparator: String) {
        self.uses24Hour = uses24Hour
        self.decimalSeparator = decimalSeparator
    }
}
