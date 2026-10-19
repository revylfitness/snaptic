import Foundation

// Assertions and arbitration (owner: G; PLAN 0.3 §2.4, N3, N17). The plan holds absolute continuous instants only,
// so it is stable while nothing changes; AssertionManager derives TimeoutSeconds at create.

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
    /// GuardMemory holds trigger starts (a battery, thermal or assertion hold): a rule session gets no assertion.
    package var guardsHold: Bool
    /// AwakeClock.continuousEnd of the governing manual session, or the latest deadline of the hold stack.
    package var sessionEnd: Double?
    /// 0.3.1 B3.3: lid-closed mode is on, the lid is shut and no external display is attached, so the session's
    /// display policy counts as `maySleep` (Snaptic's own assertion never keeps the closed panel lit).
    package var lidShut: Bool

    package init(governing: AwakeGoverning, screenLocked: Bool, consoleActive: Bool, realIdleSeconds: Double?,
                 keepDisplayOnWhileLocked: Bool, driveAliveWriting: Bool, guardsHold: Bool, sessionEnd: Double?,
                 lidShut: Bool = false) {
        self.governing = governing
        self.screenLocked = screenLocked
        self.consoleActive = consoleActive
        self.realIdleSeconds = realIdleSeconds
        self.keepDisplayOnWhileLocked = keepDisplayOnWhileLocked
        self.driveAliveWriting = driveAliveWriting
        self.guardsHold = guardsHold
        self.sessionEnd = sessionEnd
        self.lidShut = lidShut
    }
}

package enum AwakeArbiter {
    package static let timeoutGraceSeconds: Double = 15
    package static let rearmThresholdSeconds: Double = 5

    /// Plan rules (§2.4): inactive → off; keepOn → display, downgraded to system while locked (unless
    /// keepDisplayOnWhileLocked) or off console; maySleep → system; holds → system; keepOnWhileActive → display while
    /// real idle < displayIdleMinutes (unknown idle counts as active), else system. Manual sessions with an end and the
    /// hold stack get `deadline = sessionEnd + grace`; rule sessions have no backstop and none while guards hold.
    /// 0.3.1 B3.3: while `lidShut` (lid-closed mode on, the lid closed, no external display) every display policy
    /// counts as `maySleep`, so Snaptic's own assertion never keeps the closed panel lit.
    package static func plan(_ input: AwakeArbiterInput) -> AwakeAssertionPlan {
        let disk = input.driveAliveWriting
        let end = input.sessionEnd.flatMap { $0.isFinite ? $0 + timeoutGraceSeconds : nil }
        switch input.governing {
        case .inactive:
            return AwakeAssertionPlan(type: .off, details: .manual, deadline: nil, preventDiskIdle: disk)
        case .manual(let s):
            let hasEnd = s.kind.isTimed || s.kind.cap != nil
            return AwakeAssertionPlan(type: type(for: s.options, input), details: .manual,
                                      deadline: hasEnd ? end : nil, preventDiskIdle: disk)
        case .trigger(let top):
            guard !input.guardsHold else {
                return AwakeAssertionPlan(type: .off, details: .automatic, deadline: nil, preventDiskIdle: disk)
            }
            return AwakeAssertionPlan(type: type(for: top.options, input), details: .automatic, deadline: nil,
                                      preventDiskIdle: disk)
        case .holds(let holds):
            guard !holds.isEmpty else {
                return AwakeAssertionPlan(type: .off, details: .manual, deadline: nil, preventDiskIdle: disk)
            }
            let latest = holds.map(\.deadline).filter(\.isFinite).max().map { $0 + timeoutGraceSeconds }
            return AwakeAssertionPlan(type: .system, details: .manual, deadline: end ?? latest, preventDiskIdle: disk)
        }
    }

    private static func type(for options: AwakeSessionOptions, _ input: AwakeArbiterInput) -> AwakeAssertionType {
        if input.lidShut { return .system }
        let displayAllowed = input.consoleActive && (!input.screenLocked || input.keepDisplayOnWhileLocked)
        switch options.display {
        case .maySleep:
            return .system
        case .keepOn:
            return displayAllowed ? .display : .system
        case .keepOnWhileActive:
            let limit = Double(options.sanitized().displayIdleMinutes) * 60
            let active = input.realIdleSeconds.map { !$0.isFinite || $0 < limit } ?? true
            return active && displayAllowed ? .display : .system
        }
    }

    /// manual > highest-priority active trigger > hold stack > inactive (N3, N17).
    package static func governing(manual: AwakeSession?, top: TriggerTop?, holds: [AwakeHold]) -> AwakeGoverning {
        if let m = manual { return .manual(m) }
        if let t = top { return .trigger(t) }
        if !holds.isEmpty { return .holds(holds) }
        return .inactive
    }

    /// The sessionEnd input: the manual session's continuous end, or the latest hold deadline when holds govern.
    package static func sessionEnd(_ governing: AwakeGoverning, now: ClockNow) -> Double? {
        switch governing {
        case .manual(let s): return AwakeClock.continuousEnd(s, now: now)
        case .holds(let holds): return holds.map(\.deadline).filter(\.isFinite).max()
        case .inactive, .trigger: return nil
        }
    }

    /// true when the live assertion must be swapped: type or details changed, or the deadline appeared,
    /// disappeared or moved by more than rearmThresholdSeconds. `preventDiskIdle` is a separate assertion.
    package static func needsSwap(current: AwakeAssertionPlan, next: AwakeAssertionPlan) -> Bool {
        if current.type == .off && next.type == .off { return false }
        if current.type != next.type || current.details != next.details { return true }
        switch (current.deadline, next.deadline) {
        case (nil, nil): return false
        case (.some(let a), .some(let b)): return !(abs(a - b) <= rearmThresholdSeconds)
        default: return true
        }
    }
}
