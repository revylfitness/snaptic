import Foundation

// Awake runtime snapshot (owner: G; PLAN 0.3 §2.5 "Persistence", §2.14, R5-3, R5-14). Key SnapticAwakeStateV1. Read
// once at start through `sanitized(now:)` (bounds from Snaptic's clock, not the snapshot's own fields); afterwards
// SessionController only writes whole snapshots built from memory.

package struct AwakeRuntimeSnapshot: ConfigModel {
    package static let key = "SnapticAwakeStateV1"
    /// "Pause Rules" never reaches further than this (Until Tomorrow, 24 h from the CLI).
    package static let maxPauseSeconds: Double = 2 * 86_400
    /// A suppression's `until` never lies further ahead than the longest resume delay.
    package static var maxSuppressionSeconds: Double { Double(AwakeTrigger.resumeRange.upperBound) * 60 }
    package static let maxSuppressions = 64

    /// kern.bootsessionuuid when written.
    package var bootSession: String
    package var manual: AwakeSession?
    /// `.process` holds only, ≤ 8, lossyUniqueArray (N17, N18, R5-3).
    package var holds: [AwakeHold]
    package var suppressions: LossyMap<StableID, TriggerSuppression>
    /// Wall time; "Pause Rules".
    package var pausedUntil: Double?
    package var guardMemory: GuardMemory

    package init() {
        bootSession = ""
        manual = nil
        holds = []
        suppressions = LossyMap()
        pausedUntil = nil
        guardMemory = GuardMemory()
    }

    private enum CodingKeys: String, CodingKey { case bootSession, manual, holds, suppressions, pausedUntil, guardMemory }

    /// R5-3: a bad `manual` decodes as nil and the rest is kept; holds element-wise, duplicate ids keep the first.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bootSession = c.lossy(.bootSession, "")
        manual = (try? c.decodeIfPresent(AwakeSession.self, forKey: .manual)) ?? nil
        holds = c.lossyUniqueArray(.holds, [])
        suppressions = c.lossy(.suppressions, LossyMap())
        pausedUntil = c.lossy(.pausedUntil, nil)
        guardMemory = c.lossy(.guardMemory, GuardMemory())
    }

    /// The snapshot SessionController writes from its runtime state: connection holds are left out (N17).
    package init(bootSession: String, manual: AwakeSession?, holds: [AwakeHold],
                 suppressions: [StableID: TriggerSuppression], pausedUntil: Double?, guardMemory: GuardMemory) {
        self.bootSession = bootSession
        var m = manual
        m?.overrideGuards = false
        self.manual = m
        self.holds = holds.filter(\.binding.isProcess)
        self.suppressions = LossyMap(suppressions)
        self.pausedUntil = pausedUntil
        self.guardMemory = guardMemory
        self = sanitized()
    }

    /// Shape clamp without a clock: `.rule` manual sessions and connection holds dropped, holds de-duplicated and
    /// capped, non-finite values dropped, unknown suppression keys dropped.
    package func sanitized() -> AwakeRuntimeSnapshot {
        var c = self
        if let m = manual, m.source == .rule || !m.startedContinuous.isFinite { c.manual = nil }
        c.manual?.overrideGuards = false
        c.holds = Array(holds.filter { $0.binding.isProcess && $0.deadline.isFinite && $0.startedContinuous.isFinite }
            .uniquedByID().prefix(AwakeHold.maxHolds))
        var kept: [StableID: TriggerSuppression] = [:]
        for (id, s) in suppressions.values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard kept.count < Self.maxSuppressions else { break }
            var s = s
            if let u = s.until, !u.isFinite { s.until = nil }
            if s.until != nil || s.untilFalse { kept[id] = s }
        }
        c.suppressions = LossyMap(kept)
        if let p = pausedUntil, !p.isFinite { c.pausedUntil = nil }
        c.guardMemory = guardMemory.sanitized()
        return c
    }

    /// Load-time clamp (Kit half of code R2-M8). Drops a manual session or hold from another boot or out of range
    /// (`AwakeSession.sanitized(now:)`, `AwakeHold.sanitized(now:)`); on a boot mismatch drops `until` suppressions
    /// (keeps `untilFalse`) and resets guard memory except `warnedSerious`; keeps `source` (security L1). Pid checks
    /// and guards run in SessionController.restore.
    package func sanitized(now: ClockNow) -> AwakeRuntimeSnapshot {
        let base = sanitized()
        let sameBoot = !base.bootSession.isEmpty && base.bootSession == now.bootSession
        var c = AwakeRuntimeSnapshot()
        c.bootSession = now.bootSession
        if sameBoot {
            c.manual = base.manual.flatMap { $0.sanitized(now: now) }
            c.holds = Array(base.holds.compactMap { $0.sanitized(now: now) }.uniquedByID().prefix(AwakeHold.maxHolds))
        }
        var kept: [StableID: TriggerSuppression] = [:]
        for (id, s) in base.suppressions.values {
            var s = s
            if !sameBoot {
                s.until = nil
            } else if let u = s.until {
                if u <= now.continuous || u - now.continuous > Self.maxSuppressionSeconds { s.until = nil }
            }
            if s.until != nil || s.untilFalse { kept[id] = s }
        }
        c.suppressions = LossyMap(kept)
        if let p = base.pausedUntil, now.wall.isFinite, p > now.wall, p - now.wall <= Self.maxPauseSeconds {
            c.pausedUntil = p
        }
        c.guardMemory = base.guardMemory.reloaded(sameBoot: sameBoot)
        return c
    }

    /// What `sanitized(now:)` dropped only because it ran out while Snaptic wasn't running (same boot, otherwise
    /// valid, with a known end): history records it at its end instant (wall, never after `now.wall`). A session
    /// without an end (Until Turned Off, uncapped app or task sessions) never expires; another boot's items have no
    /// known end and are not reported.
    package func expiredWhileAway(now: ClockNow) -> (manual: (session: AwakeSession, endWall: Double)?,
                                                      holds: [(hold: AwakeHold, endWall: Double)]) {
        let base = sanitized()
        guard !base.bootSession.isEmpty, base.bootSession == now.bootSession,
              now.wall.isFinite, now.continuous.isFinite else { return (manual: nil, holds: []) }
        var manualEnd: (session: AwakeSession, endWall: Double)?
        if let m = base.manual, m.sanitized(now: now) == nil, let end = Self.end(of: m),
           end.continuous <= now.continuous || end.wall <= now.wall {
            let probe = ClockNow(wall: end.wall - 1, continuous: end.continuous - 1, bootSession: now.bootSession)
            if let valid = m.sanitized(now: probe) {
                manualEnd = (session: valid, endWall: min(max(end.wall, valid.startedAt), now.wall))
            }
        }
        var holdEnds: [(hold: AwakeHold, endWall: Double)] = []
        for h in base.holds where h.sanitized(now: now) == nil && h.deadline <= now.continuous {
            let span = h.deadline - h.startedContinuous
            let probe = ClockNow(wall: h.startedAt + span - 1, continuous: h.deadline - 1, bootSession: now.bootSession)
            guard let valid = h.sanitized(now: probe), !holdEnds.contains(where: { $0.hold.id == valid.id }) else { continue }
            holdEnds.append((hold: valid, endWall: min(max(valid.startedAt + span, valid.startedAt), now.wall)))
        }
        return (manual: manualEnd, holds: holdEnds)
    }

    /// A session's end on both clocks; nil when it has none.
    private static func end(of s: AwakeSession) -> (wall: Double, continuous: Double)? {
        if case .until(let t) = s.kind {
            guard t.isFinite else { return nil }
            return (wall: t, continuous: s.startedContinuous + (t - s.startedAt))
        }
        guard let d = s.deadline, d.isFinite else { return nil }
        return (wall: s.startedAt + (d - s.startedContinuous), continuous: d)
    }

    /// Services the restored state needs before restore runs (§2.1 start order).
    package var dynamicNeeds: AwakeDynamicNeeds {
        var needs: AwakeDynamicNeeds = []
        if let m = manual {
            switch m.kind {
            case .untilIdle: needs.insert(.taskQuiet)
            case .whileApp: needs.insert(.apps)
            case .indefinite, .duration, .until: break
            }
            if m.options.display == .keepOnWhileActive { needs.insert(.idle) }
        }
        if !holds.isEmpty { needs.insert(.process) }
        return needs
    }
}
