import Foundation

// Activity simulation policy (owner: J; PLAN 0.3 §2.9, N10). Pure truth tables; ActivityController feeds them and
// ActivitySimulator acts on the result. Every non-finite input reads as "don't act".

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
    /// The cap never exceeds 8 h, whatever the caller passes (AwakeActivityConfig.stopAfterHours is 1...8).
    package static let maxStopAfterSeconds: Double = 8 * 3600
    /// Session sources that are direct actions in Snaptic's own UI (N10); spelled out here rather than read from
    /// `AwakeSessionSource.isDirectUserAction` so the rule is local and tested.
    package static let directSources: Set<AwakeSessionSource> = [.menu, .hotkey, .settings]

    /// skip unless: mode ≠ off, unlocked, on console, no screensaver, displays awake, switcher hidden,
    /// secondsSinceUserInput ≥ interval, activityElapsed < stopAfter (≤ 8 h). nudge additionally needs nudgeAllowed
    /// and an edge distance > margin; otherwise a nudge request degrades to declare.
    package static func decide(_ i: ActivityInputs) -> ActivityDecision {
        guard i.mode != .off, !i.screenLocked, i.onConsole, !i.screensaverRunning, !i.displaysAsleep,
              !i.switcherVisible else { return .skip }
        guard i.secondsSinceUserInput.isFinite, i.secondsSinceUserInput >= intervalSeconds else { return .skip }
        guard i.activityElapsedSeconds.isFinite, i.stopAfterSeconds.isFinite, i.activityElapsedSeconds >= 0,
              i.activityElapsedSeconds < min(i.stopAfterSeconds, maxStopAfterSeconds) else { return .skip }
        guard i.mode == .nudge, i.nudgeAllowed, let edge = i.pointerEdgeDistance, edge.isFinite,
              edge > edgeMarginPoints else { return .declare }
        return .nudge
    }

    /// The N10 rule in one place: true only when pointerNudge is effective, Accessibility preflight passes, the
    /// governing source is a manual session started by a direct UI action, and the gate says
    /// `uiStartedInProcess && pointer == .allowed`. False for trigger, hold, CLI, launch, restored and resumed
    /// sessions (the gate is `.notAllowed` for those) and for an unconfirmed hotkey start.
    package static func nudgeAllowed(governing: AwakeGoverning, gate: AwakeActivityGate, pointerNudgeEffective: Bool,
                                     accessibility: Bool) -> Bool {
        guard pointerNudgeEffective, accessibility, case .manual(let session) = governing,
              directSources.contains(session.source) else { return false }
        return gate.uiStartedInProcess && gate.pointer == .allowed
    }

    /// True when a nudge would act except for the hotkey confirmation (gate `.askOnFirstUse`): ActivityController
    /// then calls `SessionController.requestPointerConfirmation()`. The caller has already checked that pointer
    /// movement is effective and Accessibility passes.
    package static func needsPointerConfirmation(_ i: ActivityInputs, gate: AwakeActivityGate) -> Bool {
        guard i.mode == .nudge, gate.pointer == .askOnFirstUse else { return false }
        var asIfAllowed = i
        asIfAllowed.nudgeAllowed = true
        return decide(asIfAllowed) == .nudge
    }
}

package enum IdleMath {
    package static let echoSeconds: Double = 1
    /// Remembered nudge and declaration instants (ActivitySimulator keeps the last 10 of each).
    package static let rememberedActions = 10

    /// The continuous instant of the last real input. `hidIdleSeconds` is one HID event type's idle time read at
    /// `now`, so its reset happened at `now − hidIdleSeconds`. A reset within `echoSeconds` of one of our nudges
    /// (callers pass `nudgeTimes` only for the mouse-moved type) or after one of our declarations (all types) is our
    /// own echo, not real input (security L1/M2, code M8): `previous` is kept. A reset older than `previous` changes
    /// nothing; a non-finite reading changes nothing; a negative idle reads as input `now`.
    package static func lastRealInput(previous: Double, now: Double, hidIdleSeconds: Double,
                                      nudgeTimes: [Double], declareTimes: [Double]) -> Double {
        guard now.isFinite, hidIdleSeconds.isFinite else { return previous }
        let reset = now - max(0, hidIdleSeconds)
        if previous.isFinite, reset <= previous { return previous }
        // ± echoSeconds: the HID clock and ours are read at slightly different moments.
        let isEcho = (nudgeTimes + declareTimes).contains { t in t.isFinite && abs(reset - t) <= echoSeconds }
        return isEcho ? previous : reset
    }

    /// Appends `t` to a remembered list, keeping the newest `rememberedActions`.
    package static func remembering(_ t: Double, in list: [Double]) -> [Double] {
        var out = list
        out.append(t)
        if out.count > rememberedActions { out.removeFirst(out.count - rememberedActions) }
        return out
    }
}
