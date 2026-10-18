import Foundation

// Parent ↔ guard messages, JSON lines (owner: B). R2C §4.4 + PLAN §4.5 + R5.2.
// Times are relative seconds (no clock domain crosses the pipe).

package enum GuardMessage: Codable, Equatable, Sendable {
    /// Answered with `ready`.
    case hello(protocolVersion: Int, build: String)
    /// Acknowledged with `ack(seq)`. `id` names the trial, `seq` this request (FIXES-R2 N1:
    /// the two are never the same counter, so no other message's reply can answer it).
    case armTrial(id: UInt64, seq: UInt64, undo: [UndoOp], deadlineSeconds: Double)
    /// The trial's deadline becomes at least now + `seconds` (never shortened; capped at
    /// now + `maxDeadlineSeconds`). Sent after each apply stage and right before the confirm
    /// panel shows (FIXES-R1 B4, FIXES-R2 N8). No reply.
    case extend(id: UInt64, seconds: Double)
    /// Acknowledged with `ack(seq)`: from then on the guard no longer reverts the trial by
    /// its deadline or a hang (the user chose Keep).
    case commitIntent(id: UInt64, seq: UInt64)
    /// The trial is over (kept, or the app undid it itself). No reply.
    case commit(id: UInt64)
    case disarm(id: UInt64)
    /// Replaces the whole long-armed set; acknowledged with `ack(seq)`.
    case long(seq: UInt64, undo: [UndoOp], restoreColorSync: Bool)
    /// Dim states that justify killing a hung parent after 30 s (dim to black, overlay < 30%).
    case impairment(dimToBlack: Bool, overlayBelowFloor: Bool)
    case busy(seconds: Double)
    case classification([GuardDisplayClass])
    case heartbeat(mainAgeMillis: UInt64)
    /// Exit without undoing anything (only sent while nothing is armed). No reply.
    case shutdown
}

package enum GuardReply: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int, canMonitorPanel: Bool)
    /// Echoes the `seq` of the request it answers.
    case ack(seq: UInt64)
    case reverted(trial: UInt64?, applied: Int, skipped: Int)
    case failed(String)
}

package enum GuardProtocol {
    /// 2: acks echo a per-request `seq` (FIXES-R2 N1).
    package static let version = 2
    /// Bounds enforced on both sides (a message outside them is a protocol error).
    package static let maxUndoOps = 256
    package static let maxDisplays = 64
    package static let maxDeadlineSeconds = 120.0
    /// Panel (≤ 60 s) + 10 s, with room to spare.
    package static let maxExtendSeconds = 90.0
    package static let maxBusySeconds = 10.0
    package static let maxFailureLength = 256

    /// Guard timing (PLAN §4.5, R5.2, R5.3).
    package static let hangSeconds = 10.0
    package static let killParentAfterSeconds = 30.0
    package static let staleHeartbeatSeconds = 3.0
    package static let noVisiblePersistSeconds = 2.0
    package static let wakeGraceSeconds = 15.0
    package static let quiescenceQuietSeconds = 1.5
    package static let quiescenceCapSeconds = 8.0
    package static let ackTimeoutSeconds = 1.0
    /// Trial deadline = panel + settle (≤ 5 s) + 10 s (R5.2).
    package static func trialDeadline(panelSeconds: Double) -> Double { panelSeconds + 5 + 10 }
    /// What the app extends a trial by right before the panel shows: panel + 10 s (FIXES-R1 B4).
    package static func panelExtension(panelSeconds: Double) -> Double {
        min(max(panelSeconds, 0) + 10, maxExtendSeconds)
    }
    /// The guard's `extend` rule: at least now + seconds, never earlier than before, capped.
    package static func extendedDeadline(current: Double, now: Double, seconds: Double) -> Double {
        let s = min(max(seconds.isFinite ? seconds : 0, 0), maxExtendSeconds)
        return max(current, min(now + s, now + maxDeadlineSeconds))
    }

    // MARK: Coding (one JSON object per line; JSONEncoder never emits a raw newline)

    package static func encode(_ message: GuardMessage) -> Data? { try? JSONEncoder().encode(message) }
    package static func encode(_ reply: GuardReply) -> Data? { try? JSONEncoder().encode(reply) }

    /// Nil for malformed or out-of-bounds messages.
    package static func decodeMessage(_ line: Data) -> GuardMessage? {
        guard line.count <= LineSplitter.maxLine,
              let m = try? JSONDecoder().decode(GuardMessage.self, from: line), isValid(m) else { return nil }
        return m
    }

    package static func decodeReply(_ line: Data) -> GuardReply? {
        guard line.count <= LineSplitter.maxLine, let r = try? JSONDecoder().decode(GuardReply.self, from: line) else { return nil }
        if case .failed(let s) = r, s.count > maxFailureLength { return .failed(String(s.prefix(maxFailureLength))) }
        return r
    }

    package static func isValid(_ m: GuardMessage) -> Bool {
        func ok(_ d: Double, _ maxValue: Double) -> Bool { d.isFinite && d >= 0 && d <= maxValue }
        switch m {
        case .hello(let v, let build): return v > 0 && build.utf8.count <= 128
        case .armTrial(_, let seq, let undo, let deadline):
            return seq != 0 && undo.count <= maxUndoOps && ok(deadline, maxDeadlineSeconds)
        case .extend(_, let s): return ok(s, maxExtendSeconds)
        case .commitIntent(_, let seq): return seq != 0
        case .long(let seq, let undo, _): return seq != 0 && undo.count <= maxUndoOps
        case .busy(let s): return s.isFinite && s >= 0
        case .classification(let c): return c.count <= maxDisplays
        case .commit, .disarm, .impairment, .heartbeat, .shutdown: return true
        }
    }

    /// The `seq` the guard's `ack` must echo, for the messages that are acknowledged; nil for
    /// the others (both sides use this, so they can't disagree about which messages get one).
    package static func ackSeq(_ m: GuardMessage) -> UInt64? {
        switch m {
        case .armTrial(_, let seq, _, _), .commitIntent(_, let seq), .long(let seq, _, _): return seq
        case .hello, .extend, .commit, .disarm, .impairment, .busy, .classification, .heartbeat, .shutdown: return nil
        }
    }

    /// `busy` windows are capped at 10 s (R3C §5.2).
    package static func clampedBusy(_ seconds: Double) -> Double { min(max(seconds.isFinite ? seconds : 0, 0), maxBusySeconds) }
}

/// The guard's hang rule (PLAN §4.5, R3C §5.2) as a pure function, so it is tested on Linux.
package struct HangDetector: Equatable, Sendable {
    /// Uptime seconds of the last heartbeat received, and the age it reported.
    package var lastHeartbeatAt: Double?
    package var lastMainAgeMillis: UInt64 = 0
    /// End of the current `busy` window (uptime seconds).
    package var busyUntil: Double = 0
    /// mainAgeMillis when the current busy window opened (a busy that would extend an open
    /// window while the age keeps growing is ignored).
    private var busyOpenedAtAge: UInt64?
    /// End of the post-wake grace (uptime seconds).
    package var wakeGraceUntil: Double = 0

    package init() {}

    package mutating func heartbeat(mainAgeMillis: UInt64, at now: Double) {
        lastHeartbeatAt = now
        lastMainAgeMillis = mainAgeMillis
        if now >= busyUntil { busyOpenedAtAge = nil }
    }

    /// Returns false when the request was ignored.
    @discardableResult
    package mutating func busy(seconds: Double, at now: Double) -> Bool {
        let s = GuardProtocol.clampedBusy(seconds)
        guard s > 0 else { return false }
        if now < busyUntil, let opened = busyOpenedAtAge, lastMainAgeMillis > opened { return false }
        busyUntil = max(busyUntil, now + s)
        if busyOpenedAtAge == nil { busyOpenedAtAge = lastMainAgeMillis }
        return true
    }

    package mutating func didWake(at now: Double) { wakeGraceUntil = now + GuardProtocol.wakeGraceSeconds }

    /// Seconds since the parent last looked alive, or nil when it looks alive now.
    package func hangSeconds(at now: Double) -> Double? {
        guard now >= wakeGraceUntil else { return nil }
        guard let last = lastHeartbeatAt else { return nil }
        let silence = now - last
        let reportedAge = Double(lastMainAgeMillis) / 1000 + silence
        let inBusy = now < busyUntil
        if silence > GuardProtocol.hangSeconds { return silence }
        if !inBusy && reportedAge > GuardProtocol.hangSeconds { return reportedAge }
        return nil
    }

    package func isHeartbeatStale(at now: Double) -> Bool {
        guard let last = lastHeartbeatAt else { return true }
        return now - last > GuardProtocol.staleHeartbeatSeconds
    }
}
