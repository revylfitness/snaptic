import AppKit
import SnapticKit

// Stub (owner: C). Hand-written by the lead in step 0 from PLAN 0.3 §4.5 (kind S): drops every value. C implements
// the latest-wins mailbox (DDC ≤ 20 Hz, `.ended` always delivered) in step 2.

@MainActor final class DisplayLiveController: DisplayLiveControlling {
    weak var context: DisplaysContext?

    init() {}

    func set(_ control: LiveControl, _ value: Double, for display: DisplayKey, phase: DragPhase) {}
}
