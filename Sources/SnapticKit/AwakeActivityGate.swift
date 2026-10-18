import Foundation

// Runtime-only gate for activity simulation (owner: G; PLAN 0.3 §2.3, R5-1, R5-7). Nothing here is Codable (r3
// security M2); lint L16 allows `activityGate =` only in SessionController.swift.

package struct AwakeActivityGate: Equatable, Sendable {
    package enum Pointer: Equatable, Sendable {
        /// CLI, launch, restored, resumed, trigger or hold governs.
        case notAllowed
        /// Hotkey start: the confirmation toast appears the first time pointer movement would act.
        case askOnFirstUse
        /// Toast shown; declare meanwhile.
        case asking
        /// Menu/Settings start, or Allow clicked.
        case allowed
        /// Not Now / toast dismissed / Stop on the first-nudge toast: declare for this session.
        case declined
    }

    /// Nothing governing for this long resets the activity cap (R5-7, r3 security L5).
    package static let capResetSeconds: Double = 900

    /// True only after a menu-click or Settings-button start handler, or the hotkey toast's Allow handler, in this
    /// process (N10). Never decoded, never derived from `source`.
    package private(set) var uiStartedInProcess: Bool = false
    package private(set) var pointer: Pointer = .notAllowed
    /// Continuous instant activity first acted; the cap counts from here (carried across back-to-back sessions).
    package private(set) var activitySince: Double? = nil
    /// Continuous; for `nothingGoverned` (R5-7).
    package private(set) var lastEnded: Double? = nil

    package init() {}

    package enum Event: Equatable, Sendable {
        case uiStart
        case hotkeyStart
        case confirmAsked, confirmAllowed, confirmDeclined
        case otherStart
        case restore, resume
        case takeover
        case replaced
        /// R5-7: the manual session ended (pointer reset; activitySince and lastEnded kept).
        case ended
        /// R5-7: any active → inactive transition of governing: lastEnded = now.
        case governingEnded(now: Double)
        case moduleStop
        /// Activity acted: sets activitySince when nil.
        case acted(now: Double)
        /// R5-7: every arbitration with nothing governing.
        case nothingGoverned(now: Double)
        case unchanged
    }

    /// Pointer movement may act (the rest of N10 is ActivityPolicy.nudgeAllowed).
    package var pointerAllowed: Bool { uiStartedInProcess && pointer == .allowed }

    /// Seconds activity has acted on Snaptic's continuous clock (0 before the first action).
    package func activityElapsed(now: Double) -> Double {
        guard let since = activitySince, since.isFinite, now.isFinite else { return 0 }
        return max(0, now - since)
    }

    /// The §2.3 truth table (normative):
    /// uiStart → (true, allowed, activitySince nil); hotkeyStart → (false, askOnFirstUse, kept);
    /// confirmAsked → asking (only from askOnFirstUse); confirmAllowed → (true, allowed, nil) only from asking;
    /// confirmDeclined → declined (from askOnFirstUse, asking or allowed; notAllowed stays);
    /// otherStart, restore, resume, takeover, replaced, ended → (false, notAllowed, kept);
    /// governingEnded → lastEnded = now; nothingGoverned → lastEnded = now when nil, else activitySince = nil when
    /// now − lastEnded ≥ 900 (R5-7); moduleStop → init(); acted → activitySince ?? now; unchanged → self.
    package func applying(_ event: Event) -> AwakeActivityGate {
        var g = self
        switch event {
        case .uiStart:
            g.uiStartedInProcess = true
            g.pointer = .allowed
            g.activitySince = nil
        case .hotkeyStart:
            g.uiStartedInProcess = false
            g.pointer = .askOnFirstUse
        case .confirmAsked:
            if pointer == .askOnFirstUse { g.pointer = .asking }
        case .confirmAllowed:
            guard pointer == .asking else { return self }
            g.uiStartedInProcess = true
            g.pointer = .allowed
            g.activitySince = nil
        case .confirmDeclined:
            switch pointer {
            case .askOnFirstUse, .asking, .allowed, .declined: g.pointer = .declined
            case .notAllowed: break
            }
        case .otherStart, .restore, .resume, .takeover, .replaced, .ended:
            g.uiStartedInProcess = false
            g.pointer = .notAllowed
        case .governingEnded(let now):
            if now.isFinite { g.lastEnded = now }
        case .moduleStop:
            return AwakeActivityGate()
        case .acted(let now):
            if g.activitySince == nil, now.isFinite { g.activitySince = now }
        case .nothingGoverned(let now):
            guard now.isFinite else { return self }
            if let last = lastEnded {
                if now - last >= Self.capResetSeconds { g.activitySince = nil }
            } else {
                g.lastEnded = now
            }
        case .unchanged:
            return self
        }
        return g
    }
}
