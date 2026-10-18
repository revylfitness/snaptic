import Foundation

// Both ends of the parent ↔ guard conversation as pure state (owner: B). FIXES-R2 N1: the
// parent waited for acks under one counter while the guard echoed another, so no trial ever
// armed. The request/ack correlation (parent) and the message handling (guard) live here so
// the whole conversation is tested on Linux with a fake transport; DisplayGuardClient and
// GuardCore only add the pipe, timers and side effects.

/// The parent's outstanding requests, keyed by the `seq` each one carries (GuardProtocol.ackSeq).
///
/// - `seq`s are never reused, not even across guard processes, so a late ack can only ever
///   name its own request.
/// - Each request belongs to the guard process (generation) it was sent to; an ack read
///   from another process's pipe is ignored.
/// - A request resolves exactly once: acknowledged, timed out, or failed (guard gone).
package struct GuardAckTracker<Waiter> {
    private struct Entry {
        let generation: UInt64
        let deadline: Double
        let waiter: Waiter
    }

    /// The guard process requests go to now (0 = none started yet).
    package private(set) var generation: UInt64 = 0
    private var lastSeq: UInt64 = 0
    private var entries: [UInt64: Entry] = [:]

    package init() {}

    package var pendingCount: Int { entries.count }

    package func isPending(_ seq: UInt64) -> Bool { entries[seq] != nil }

    /// A new guard process: every request still waiting on the old one fails (returned).
    package mutating func startGeneration() -> [Waiter] {
        generation &+= 1
        return failAll()
    }

    /// A seq for a request nobody waits for (its ack, if any, is ignored). Never 0.
    package mutating func nextSeq() -> UInt64 {
        lastSeq &+= 1
        if lastSeq == 0 { lastSeq = 1 }
        return lastSeq
    }

    /// Registers a request about to be sent to the current guard; returns its seq.
    package mutating func begin(_ waiter: Waiter, at now: Double, timeout: Double) -> UInt64 {
        let seq = nextSeq()
        entries[seq] = Entry(generation: generation, deadline: now + max(timeout, 0), waiter: waiter)
        return seq
    }

    /// An `ack(seq)` read from guard process `generation`. Returns the waiter to resolve as
    /// acknowledged; nil for an unknown, late (timed out), duplicate or stale ack.
    package mutating func acknowledge(_ seq: UInt64, from generation: UInt64) -> Waiter? {
        guard let e = entries[seq], e.generation == generation, generation == self.generation else { return nil }
        entries[seq] = nil
        return e.waiter
    }

    /// One request's own timer fired. Returns the waiter to resolve as failed, nil when the
    /// request was already resolved.
    package mutating func timeOut(_ seq: UInt64) -> Waiter? {
        entries.removeValue(forKey: seq)?.waiter
    }

    /// Every request whose deadline passed (oldest first).
    package mutating func expire(at now: Double) -> [Waiter] {
        let due = entries.filter { now >= $0.value.deadline }.keys.sorted()
        return due.compactMap { entries.removeValue(forKey: $0)?.waiter }
    }

    /// The guard died or was stopped: everything still waiting fails (oldest first).
    package mutating func failAll() -> [Waiter] {
        let all = entries.keys.sorted().compactMap { entries[$0]?.waiter }
        entries = [:]
        return all
    }
}

/// The guard's bookkeeping for what the parent tells it. `handle` returns exactly the replies
/// the protocol promises: `ready` for `hello`, one `ack(seq)` for each message that
/// `GuardProtocol.ackSeq` names, nothing for the rest.
package struct GuardSession: Equatable, Sendable {
    package struct Trial: Equatable, Sendable {
        package var undo: [UndoOp]
        /// Uptime seconds.
        package var deadline: Double
        /// The user chose Keep: never reverted by deadline or hang any more.
        package var committing: Bool
    }

    package private(set) var trials: [UInt64: Trial] = [:]
    package private(set) var longUndo: [UndoOp] = []
    package private(set) var longColorSync = false
    package private(set) var dimImpairing = false
    package private(set) var classes: [GuardDisplayClass] = []
    package var hang = HangDetector()
    /// `shutdown` arrived: the guard exits without undoing anything.
    package private(set) var shutdownRequested = false

    /// A committing trial the parent never finished is forgotten this long after its deadline.
    package static let committingGraceSeconds = 60.0

    package init() {}

    package mutating func handle(_ message: GuardMessage, at now: Double, canMonitorPanel: Bool) -> [GuardReply] {
        switch message {
        case .hello:
            return [.ready(protocolVersion: GuardProtocol.version, canMonitorPanel: canMonitorPanel)]
        case .armTrial(let id, let seq, let undo, let deadline):
            trials[id] = Trial(undo: undo, deadline: now + deadline, committing: false)
            return [.ack(seq: seq)]
        case .extend(let id, let seconds):
            if var t = trials[id], !t.committing {
                t.deadline = GuardProtocol.extendedDeadline(current: t.deadline, now: now, seconds: seconds)
                trials[id] = t
            }
            return []
        case .commitIntent(let id, let seq):
            // Acked even for a trial the guard already reverted: that `reverted` reply went
            // out first, so the parent learns of it before this ack.
            trials[id]?.committing = true
            return [.ack(seq: seq)]
        case .commit(let id), .disarm(let id):
            trials[id] = nil
            return []
        case .long(let seq, let undo, let colorSync):
            longUndo = undo
            longColorSync = colorSync
            return [.ack(seq: seq)]
        case .impairment(let dim, let overlay):
            dimImpairing = dim || overlay
            return []
        case .busy(let seconds):
            hang.busy(seconds: seconds, at: now)
            return []
        case .classification(let list):
            classes = list
            return []
        case .heartbeat(let age):
            hang.heartbeat(mainAgeMillis: age, at: now)
            return []
        case .shutdown:
            shutdownRequested = true
            return []
        }
    }

    /// Trials the guard reverts now: past their deadline and not committing (by id).
    package func dueTrials(at now: Double) -> [UInt64] {
        trials.filter { !$0.value.committing && now >= $0.value.deadline }.keys.sorted()
    }

    /// Trials a hang or the parent's death reverts: every one not committing, newest first.
    package var revertibleTrials: [UInt64] {
        trials.filter { !$0.value.committing }.keys.sorted(by: >)
    }

    /// Removes a trial the guard is about to revert.
    package mutating func takeTrial(_ id: UInt64) -> Trial? { trials.removeValue(forKey: id) }

    /// Forgets committing trials whose parent never sent `commit` (long past the deadline).
    package mutating func pruneCommitting(at now: Double) {
        for (id, t) in trials where t.committing && now >= t.deadline + Self.committingGraceSeconds { trials[id] = nil }
    }

    /// Something the guard must protect (keeps App Nap away).
    package var hasArmedState: Bool { !trials.isEmpty || !longUndo.isEmpty || longColorSync }

    /// Long-armed states that impair visibility (the hang rule acts on these, R5.2).
    package var isImpairing: Bool { longUndo.contains { $0.stage == .enable } || longColorSync || dimImpairing }
}
