import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §3.6 (kind S). A closed enum: no case carries a
// name, pid or payload; EventLog's Awake overload (A) is the only writer of the `.awake` category (lint L9).

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

    /// Fixed text per case (the counter key for counted cases). Stub: a generic text.
    package var text: String { "awake event" }
}
