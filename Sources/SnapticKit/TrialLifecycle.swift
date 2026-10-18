import Foundation

// The confirm-trial state machine (owner: B). PLAN §4.3/§4.4, R5.2, FIXES-R1 B1. The queue's
// trial task drives it through its phases and asks it at every checkpoint (after each await)
// what to do; everything else (Revert button, timeout, sleep/lock, a new request, panic, the
// guard, Displays stopping) only *requests*. Rules:
//
// - A trial resolves exactly once: as kept, or as reverted with the first reason that won.
// - A revert requested at any point before the change is final wins, including while the
//   panel isn't up yet (arming, applying, settling) and while a Keep is being written.
// - Once the user chose Keep, only panic or the guard's own revert still override it; sleep,
//   lock or a new request arriving during the short Keep write don't undo the user's choice.
// - `stop()` (Displays stopping, synchronous) resolves on the spot: a trial whose Keep is
//   underway is committed, any other is undone by the caller. The task then sees `.abandon`.
//   FIXES-R2 N6: "committed" means the Keep is finished properly (Keep batches written if
//   they hadn't gone out yet, kept modes remembered and persisted), never half-kept.

package enum TrialRevertReason: String, Codable, Equatable, Sendable, CaseIterable {
    /// The Revert button, Esc.
    case user
    /// The countdown ran out.
    case timeout
    /// Sleep, screen sleep, lock, fast user switch.
    case session
    /// A newer user request (it must not wait for this trial's countdown).
    case newRequest
    /// Restore All Displays.
    case panic
    /// The guard reverted the trial itself (deadline or hang).
    case guardReverted
    /// The guard died or became unreachable.
    case guardLost
    /// A staged apply step failed.
    case applyFailed
    /// Displays stopped (only reported; `stop()` handles it).
    case stopped

    /// Reasons that still win after the user chose Keep.
    package var overridesKeep: Bool { self == .panic || self == .guardReverted }
}

package enum TrialPhase: Equatable, Sendable {
    /// Journal + guard arm; nothing applied yet.
    case arming
    /// Staged apply (HDR, rotation, CG batches).
    case applying
    /// Waiting for the displays to come back before the countdown.
    case settling
    /// The panel is up.
    case confirming
    /// The user chose Keep: commit intent, final-scope re-apply, afterKeep.
    case keeping
    /// The staged undo is running.
    case reverting
    case resolved
}

package enum TrialEnd: Equatable, Sendable {
    case kept
    case reverted(TrialRevertReason)
}

package enum TrialPanelChoice: Equatable, Sendable {
    case keep, revert, timeout
}

/// What the trial task does at a checkpoint.
package enum TrialStep: Equatable, Sendable {
    /// Carry on.
    case proceed
    /// Stop and run the revert path (staged undo, disarm, journals) for this reason.
    case revert(TrialRevertReason)
    /// The trial was already resolved elsewhere (Displays stopped): touch nothing.
    case abandon
}

/// What a synchronous `stop()` must do right away.
package enum TrialStopAction: Equatable, Sendable {
    /// Already resolved.
    case none
    /// Undo the trial now (synchronously, CAS).
    case undo
    /// The user's Keep was underway: finish it as kept (commit, clear journals).
    case commit
}

package struct TrialLifecycle: Equatable, Sendable {
    package private(set) var phase: TrialPhase = .arming
    /// The first revert request that counted (nil while none did).
    package private(set) var revertReason: TrialRevertReason?
    /// The guard already reverted (the staged undo is still run: CAS makes it a no-op).
    package private(set) var guardReverted = false
    package private(set) var end: TrialEnd?

    package init() {}

    package var isResolved: Bool { end != nil }
    /// A revert has been requested and the task hasn't acted on it yet.
    package var isRevertRequested: Bool { end == nil && revertReason != nil }
    /// Before the panel is up: ConnectPlanner etc. still see this as a pending trial.
    package var isPending: Bool { end == nil }

    /// A revert request from outside the task. Returns whether it counted.
    @discardableResult
    package mutating func requestRevert(_ reason: TrialRevertReason) -> Bool {
        guard end == nil, phase != .reverting else { return false }
        if phase == .keeping && !reason.overridesKeep { return false }
        if revertReason == nil { revertReason = reason }
        return true
    }

    /// The guard reported that it reverted this trial.
    package mutating func guardDidRevert() {
        guard end == nil else { return }
        guardReverted = true
        requestRevert(.guardReverted)
    }

    /// A checkpoint after an await, staying in the current phase.
    package mutating func checkpoint() -> TrialStep {
        guard end == nil else { return .abandon }
        if phase == .reverting { return .proceed }
        if let r = revertReason {
            phase = .reverting
            return .revert(r)
        }
        return .proceed
    }

    /// A checkpoint that moves on to `next` when nothing asked for a revert.
    package mutating func advance(to next: TrialPhase) -> TrialStep {
        let step = checkpoint()
        guard step == .proceed, phase != .reverting else { return step }
        switch next {
        case .arming, .applying, .settling, .confirming:
            phase = next
        case .keeping, .reverting, .resolved:
            // Keep goes through panelClosed; revert/resolve through the dedicated calls.
            return .proceed
        }
        return .proceed
    }

    /// The panel closed. Keep counts only if nothing asked for a revert meanwhile.
    package mutating func panelClosed(_ choice: TrialPanelChoice) -> TrialStep {
        guard end == nil else { return .abandon }
        if phase != .reverting {
            switch choice {
            case .keep:
                if revertReason == nil {
                    phase = .keeping
                    return .proceed
                }
            case .revert: requestRevert(.user)
            case .timeout: requestRevert(.timeout)
            }
        }
        phase = .reverting
        return .revert(revertReason ?? .user)
    }

    /// An apply step failed: revert (unless already resolved).
    package mutating func applyFailed() -> TrialStep {
        guard end == nil else { return .abandon }
        requestRevert(.applyFailed)
        phase = .reverting
        return .revert(revertReason ?? .applyFailed)
    }

    /// The Keep path finished writing. `.proceed` = resolved as kept; `.revert` = a panic or
    /// guard revert arrived during the Keep: run the revert path; `.abandon` = stopped meanwhile.
    package mutating func finishKeep() -> TrialStep {
        guard end == nil else { return .abandon }
        guard phase == .keeping, revertReason == nil else {
            phase = .reverting
            return .revert(revertReason ?? .user)
        }
        end = .kept
        phase = .resolved
        return .proceed
    }

    /// The revert path finished. False when the trial was already resolved (stop()).
    @discardableResult
    package mutating func finishRevert() -> Bool {
        guard end == nil else { return false }
        end = .reverted(revertReason ?? .user)
        phase = .resolved
        return true
    }

    /// Displays stop (synchronous). Resolves now; the caller performs the returned action.
    package mutating func stop() -> TrialStopAction {
        guard end == nil else { return .none }
        if phase == .keeping && revertReason == nil {
            end = .kept
            phase = .resolved
            return .commit
        }
        end = .reverted(revertReason ?? .stopped)
        phase = .resolved
        return .undo
    }
}

/// Which queued request a newer user request supersedes (FIXES-R1 B1: a new request never
/// waits out an older trial's countdown). Every submit takes a ticket; a trial whose ticket
/// is older than the latest user request is reverted or, if not applied yet, skipped.
package struct TrialSupersession: Equatable, Sendable {
    package private(set) var latestUser: UInt64 = 0
    private var serial: UInt64 = 0

    package init() {}

    /// A ticket for a new request; user requests also become the latest.
    package mutating func ticket(user: Bool) -> UInt64 {
        serial &+= 1
        if user { latestUser = serial }
        return serial
    }

    /// True when a user request newer than `ticket` exists.
    package func isSuperseded(_ ticket: UInt64) -> Bool { latestUser > ticket }
}
