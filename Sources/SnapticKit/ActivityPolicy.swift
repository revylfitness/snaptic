import Foundation

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.9 (kind S): safe returns (never acts).

/// `.skip`, not `.none` (code sig).
package enum ActivityDecision: Equatable, Sendable { case skip, declare, nudge }

package struct ActivityInputs: Equatable, Sendable {
    package var mode: AwakeActivityMode
    package var nudgeAllowed: Bool
    package var screenLocked: Bool
    package var onConsole: Bool
    package var screensaverRunning: Bool
    package var displaysAsleep: Bool
    package var switcherVisible: Bool
    package var secondsSinceUserInput: Double
    /// Snaptic's continuous clock: now − gate.activitySince.
    package var activityElapsedSeconds: Double
    package var stopAfterSeconds: Double
    package var pointerEdgeDistance: Double?

    package init(mode: AwakeActivityMode, nudgeAllowed: Bool, screenLocked: Bool, onConsole: Bool,
                 screensaverRunning: Bool, displaysAsleep: Bool, switcherVisible: Bool, secondsSinceUserInput: Double,
                 activityElapsedSeconds: Double, stopAfterSeconds: Double, pointerEdgeDistance: Double?) {
        self.mode = mode
        self.nudgeAllowed = nudgeAllowed
        self.screenLocked = screenLocked
        self.onConsole = onConsole
        self.screensaverRunning = screensaverRunning
        self.displaysAsleep = displaysAsleep
        self.switcherVisible = switcherVisible
        self.secondsSinceUserInput = secondsSinceUserInput
        self.activityElapsedSeconds = activityElapsedSeconds
        self.stopAfterSeconds = stopAfterSeconds
        self.pointerEdgeDistance = pointerEdgeDistance
    }
}

package enum ActivityPolicy {
    package static let intervalSeconds: Double = 60
    package static let edgeMarginPoints: Double = 2
    /// Stub: skip.
    package static func decide(_ i: ActivityInputs) -> ActivityDecision { .skip }
    /// The N10 rule in one place. Stub: false.
    package static func nudgeAllowed(governing: AwakeGoverning, gate: AwakeActivityGate, pointerNudgeEffective: Bool,
                                     accessibility: Bool) -> Bool { false }
    /// Stub: false.
    package static func needsPointerConfirmation(_ i: ActivityInputs, gate: AwakeActivityGate) -> Bool { false }
}

package enum IdleMath {
    package static let echoSeconds: Double = 1
    /// Stub: the previous value.
    package static func lastRealInput(previous: Double, now: Double, hidIdleSeconds: Double,
                                      nudgeTimes: [Double], declareTimes: [Double]) -> Double { previous }
}
