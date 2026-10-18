import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.4 (kind S): safe returns.

package enum AwakeAssertionType: String, Sendable { case off, system, display }
/// The only Details values (security M6).
package enum AwakeAssertionDetails: String, Sendable { case manual, automatic }

package struct AwakeAssertionPlan: Equatable, Sendable {
    /// Fixed vocabulary.
    package static let name = "Snaptic: keeping your Mac awake"
    package static let inactive = AwakeAssertionPlan(type: .off, details: .manual, deadline: nil, preventDiskIdle: false)
    package var type: AwakeAssertionType
    package var details: AwakeAssertionDetails
    /// Continuous instant; TimeoutSeconds is derived only at create.
    package var deadline: Double?
    /// Drive Alive writing.
    package var preventDiskIdle: Bool

    package init(type: AwakeAssertionType, details: AwakeAssertionDetails, deadline: Double?, preventDiskIdle: Bool) {
        self.type = type
        self.details = details
        self.deadline = deadline
        self.preventDiskIdle = preventDiskIdle
    }
}

package struct AwakeArbiterInput: Equatable, Sendable {
    package var governing: AwakeGoverning
    package var screenLocked: Bool
    package var consoleActive: Bool
    package var realIdleSeconds: Double?
    package var keepDisplayOnWhileLocked: Bool
    package var driveAliveWriting: Bool
    package var guardsHold: Bool
    package var sessionEnd: Double?

    package init(governing: AwakeGoverning, screenLocked: Bool, consoleActive: Bool, realIdleSeconds: Double?,
                 keepDisplayOnWhileLocked: Bool, driveAliveWriting: Bool, guardsHold: Bool, sessionEnd: Double?) {
        self.governing = governing
        self.screenLocked = screenLocked
        self.consoleActive = consoleActive
        self.realIdleSeconds = realIdleSeconds
        self.keepDisplayOnWhileLocked = keepDisplayOnWhileLocked
        self.driveAliveWriting = driveAliveWriting
        self.guardsHold = guardsHold
        self.sessionEnd = sessionEnd
    }
}

package enum AwakeArbiter {
    package static let timeoutGraceSeconds: Double = 15
    package static let rearmThresholdSeconds: Double = 5
    /// Stub: inactive.
    package static func plan(_ input: AwakeArbiterInput) -> AwakeAssertionPlan { .inactive }
    /// manual > highest-priority active trigger > hold stack > inactive (N3, N17). Stub: inactive.
    package static func governing(manual: AwakeSession?, top: TriggerTop?, holds: [AwakeHold]) -> AwakeGoverning {
        .inactive
    }
    /// Stub: false.
    package static func needsSwap(current: AwakeAssertionPlan, next: AwakeAssertionPlan) -> Bool { false }
}
