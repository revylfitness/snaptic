import Foundation

// Awake log vocabulary (owner: G; PLAN 0.3 §3.6). A closed enum: no case carries a name, pid or payload beyond fixed
// enums and a bounded rule number; EventLog's Awake overload (A) is the only writer of the `.awake` category (lint L9).

package enum AwakeLogEvent: Equatable, Sendable {
    // Counted only (EventLog.shared.awakeCounts; never in the ring).
    case sessionStarted(AwakeHistoryKind)
    case sessionEnded(AwakeEndReason)
    case holdStarted
    case triggerActive(index: Int)
    case activityCapped
    // Ring (errors only).
    case assertionFailed
    case driveAliveError(DriveAliveError)
    case holdRefused
    case restoreDropped

    /// Counted-only cases never enter the ring.
    package var isCounted: Bool {
        switch self {
        case .sessionStarted, .sessionEnded, .holdStarted, .triggerActive, .activityCapped: return true
        case .assertionFailed, .driveAliveError, .holdRefused, .restoreDropped: return false
        }
    }

    /// Fixed text per case: the counter key for counted cases ("awake.session.started.duration"), a sentence for ring
    /// cases. Rule numbers are 1-based and bounded by AwakeTrigger.maxTriggers.
    package var text: String {
        switch self {
        case .sessionStarted(let kind): return "awake.session.started." + kind.rawValue
        case .sessionEnded(let reason): return "awake.session.ended." + reason.rawValue
        case .holdStarted: return "awake.hold.started"
        case .triggerActive(let index):
            return "awake.rule.active.\(AwakeMath.clamp(index + 1, 1...AwakeTrigger.maxTriggers))"
        case .activityCapped: return "awake.activity.capped"
        case .assertionFailed: return "Awake couldn't create its power assertion."
        case .driveAliveError(let e): return "Drive Alive skipped a write (" + e.rawValue + ")."
        case .holdRefused: return "A command-line hold was refused."
        case .restoreDropped: return "A saved Awake session couldn't be restored."
        }
    }
}
