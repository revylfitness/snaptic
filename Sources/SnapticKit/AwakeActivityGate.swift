import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.3 + R5-7 (kind S). G implements the truth
// table in step 1. Runtime only: nothing here is Codable (r3 security M2); lint L16 allows `activityGate =` only in
// SessionController.swift.

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

    /// The §2.3 truth table (normative). Stub: unchanged.
    package func applying(_ event: Event) -> AwakeActivityGate { self }
}
