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
    /// 0.3.1 B5: lid-closed mode turned on, and how it ended.
    case lidOn
    case lidOff(AwakeLidEnd)
    // Ring (errors only).
    case assertionFailed
    case driveAliveError(DriveAliveError)
    case holdRefused
    case restoreDropped
    /// 0.3.1 B5: lid-closed mode couldn't turn on (the stage), or sleep was found left off by an earlier session.
    case lidFailed(AwakeLidFailStage)
    case lidLeftover

    /// Counted-only cases never enter the ring.
    package var isCounted: Bool {
        switch self {
        case .sessionStarted, .sessionEnded, .holdStarted, .triggerActive, .activityCapped, .lidOn, .lidOff: return true
        case .assertionFailed, .driveAliveError, .holdRefused, .restoreDropped, .lidFailed, .lidLeftover: return false
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
        case .lidOn: return "awake.lid.on"
        case .lidOff(let end): return "awake.lid.off." + end.rawValue
        case .assertionFailed: return "Awake couldn't create its power assertion."
        case .driveAliveError(let e): return "Drive Alive skipped a write (" + e.rawValue + ")."
        case .holdRefused: return "A command-line hold was refused."
        case .restoreDropped: return "A saved Awake session couldn't be restored."
        case .lidFailed(let stage): return "Lid-closed mode couldn't turn on (" + stage.rawValue + ")."
        case .lidLeftover: return "Sleep was found turned off after an earlier lid-closed session."
        }
    }
}
