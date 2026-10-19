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
    /// When Snaptic stopped (a quit: `clean`) or was last seen running (a heartbeat while a session, a `--pid` hold or
    /// a rule session is in it). History ends what wasn't carried on here at the latest, so time Snaptic wasn't
    /// running is never counted (awake-correctness F1). Same clock domain as `bootSession`.
    package var stop: AwakeStopStamp?
    /// The rule session running at the last heartbeat (review6 N2). Rule sessions never resume, and a quit records
    /// them, so only a snapshot left by a crash (a stamp that isn't `clean`) carries one; restore records it then.
    package var rule: AwakeRuleRecord?
    /// Wall start of the current history segment of the manual session or a hold, when it was resumed after a gap
    /// (the part before the gap is its own history entry).
    package var segmentStarts: LossyMap<StableID, Double>
    /// The reminders already shown for `manual` (N1: the 8-hour one stays once per session across relaunches).
    package var reminders: AwakeReminders
    /// History only (0.3.1 B1, r1 A5): `manual`'s id when lid-closed mode was on at some point in it, so its entry
    /// keeps "Lid closed" across a quit or crash. Never read by the lid gate (N19): the mode itself is never restored.
    package var lidSession: StableID?

    package init() {
        bootSession = ""
        manual = nil
        holds = []
        suppressions = LossyMap()
        pausedUntil = nil
        guardMemory = GuardMemory()
        stop = nil
        rule = nil
        segmentStarts = LossyMap()
        reminders = AwakeReminders()
        lidSession = nil
    }

    private enum CodingKeys: String, CodingKey {
        case bootSession, manual, holds, suppressions, pausedUntil, guardMemory, stop, rule, segmentStarts, reminders,
             lidSession
    }

    /// R5-3: a bad `manual` decodes as nil and the rest is kept; holds element-wise, duplicate ids keep the first.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bootSession = c.lossy(.bootSession, "")
        manual = (try? c.decodeIfPresent(AwakeSession.self, forKey: .manual)) ?? nil
        holds = c.lossyUniqueArray(.holds, [])
        suppressions = c.lossy(.suppressions, LossyMap())
        pausedUntil = c.lossy(.pausedUntil, nil)
        guardMemory = c.lossy(.guardMemory, GuardMemory())
        stop = c.lossy(.stop, nil)
        rule = c.lossy(.rule, nil)
        segmentStarts = c.lossy(.segmentStarts, LossyMap())
        reminders = c.lossy(.reminders, AwakeReminders())
        lidSession = c.lossy(.lidSession, nil)
    }

    /// The snapshot SessionController writes from its runtime state: connection holds are left out (N17).
    package init(bootSession: String, manual: AwakeSession?, holds: [AwakeHold],
                 suppressions: [StableID: TriggerSuppression], pausedUntil: Double?, guardMemory: GuardMemory,
                 stop: AwakeStopStamp? = nil, rule: AwakeRuleRecord? = nil, segmentStarts: [StableID: Double] = [:],
                 reminders: AwakeReminders = AwakeReminders(), lidSession: StableID? = nil) {
        self.bootSession = bootSession
        var m = manual
        m?.overrideGuards = false
        self.manual = m
        self.holds = holds.filter(\.binding.isProcess)
        self.suppressions = LossyMap(suppressions)
        self.pausedUntil = pausedUntil
        self.guardMemory = guardMemory
        self.stop = stop
        self.rule = rule
        self.segmentStarts = LossyMap(segmentStarts)
        self.reminders = reminders
        self.lidSession = lidSession
        self = sanitized()
    }

    /// Everything but the stop stamp (SessionController writes on a change of this, or when the heartbeat is due).
    package var content: AwakeRuntimeSnapshot {
        var c = self
        c.stop = nil
        return c
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
        if let st = stop, !st.isValid { c.stop = nil }
        if let r = rule, !r.isValid { c.rule = nil }
        let ids = Set([c.manual?.id].compactMap { $0 } + c.holds.map(\.id))
        c.segmentStarts = LossyMap(segmentStarts.values.filter { ids.contains($0.key) && $0.value.isFinite && $0.value >= 0 })
        c.reminders = reminders.keeping(session: c.manual?.id)
        if lidSession != c.manual?.id { c.lidSession = nil }
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
        let carried = Set([c.manual?.id].compactMap { $0 } + c.holds.map(\.id))
        c.segmentStarts = LossyMap(base.segmentStarts.values.filter { carried.contains($0.key) })
        c.reminders = base.reminders.keeping(session: c.manual?.id)
        c.lidSession = c.manual != nil && base.lidSession == c.manual?.id ? base.lidSession : nil
        // The stamp and the rule record are read once by restore (`awayEnds`, `restoreEnd`, `resumedSegment`,
        // `ruleEnd`) from the stored snapshot.
        c.stop = nil
        c.rule = nil
        return c
    }

    /// A resume after a gap shorter than this keeps one history segment (an update's relaunch).
    package static let splitGapSeconds: Double = 60

    /// History for what `sanitized(now:)` drops although it ran under Snaptic (awake-correctness F1, F5b): another
    /// boot's session or `--pid` hold ends `.reboot` when Snaptic stopped (the stamp; without one, from a build
    /// before stamps, the end is unknown and nothing is reported), a same-boot one that ran out ends `.timeUp`. An
    /// end is never after the item's own end, after Snaptic stopped (or `now` without a stamp, same boot), or
    /// before its start; the entry starts at the item's segment start. With `resume` off, a manual session in a
    /// snapshot without a stamp (written by a quit of a build before stamps) was recorded at that quit: skipped.
    package func awayEnds(now: ClockNow, resume: Bool = true) -> [AwakeAwayEnd] {
        let base = sanitized()
        guard now.wall.isFinite, now.continuous.isFinite else { return [] }
        var out: [AwakeAwayEnd] = []
        if let m = base.manual, resume || base.stop != nil, m.sanitized(now: now) == nil,
           let e = base.awayEnd(.session(m), boot: m.bootSession, startedAt: m.startedAt, ownEnd: Self.end(of: m),
                                now: now, valid: { m.sanitized(now: $0) != nil }) {
            out.append(e)
        }
        for h in base.holds where h.sanitized(now: now) == nil && !out.contains(where: { $0.item.id == h.id }) {
            let span = h.deadline - h.startedContinuous
            if let e = base.awayEnd(.hold(h), boot: h.bootSession, startedAt: h.startedAt,
                                    ownEnd: (wall: h.startedAt + span, continuous: h.deadline), now: now,
                                    valid: { h.sanitized(now: $0) != nil }) {
                out.append(e)
            }
        }
        return out
    }

    /// Everything the snapshot owes History when it is discarded unread (a launch with `Modules.disable.awake`):
    /// the away ends, every item that would have been carried on, ended `.moduleStopped` when Snaptic stopped, and a
    /// crashed rule session. With `resume` off, a manual session in a snapshot without a stamp was recorded by the
    /// quit that wrote it (a build before stamps).
    package func discardedEnds(now: ClockNow, resume: Bool) -> [AwakeAwayEnd] {
        var out = awayEnds(now: now, resume: resume)
        let kept = sanitized(now: now)
        let stamped = sanitized().stop != nil
        if let m = kept.manual, resume || stamped, !out.contains(where: { $0.item.id == m.id }) {
            out.append(restoreEnd(.session(m), reason: .moduleStopped, now: now))
        }
        for h in kept.holds where !out.contains(where: { $0.item.id == h.id }) {
            out.append(restoreEnd(.hold(h), reason: .moduleStopped, now: now))
        }
        if let r = ruleEnd(now: now) { out.append(r) }
        return out
    }

    /// The history entries a launch that discards this snapshot unread owes; none when History isn't effective
    /// (the user's switch, or `Awake.disable.history` through the feature graph, security S3-1).
    package func discardedHistory(now: ClockNow, config: AwakeConfig,
                                  killSwitches: Set<AwakeFeature>) -> [AwakeHistoryEntry] {
        let effective = AwakeFeatureGraph.resolve(raw: config.rawFeatures, killSwitches: killSwitches, safeMode: false,
                                                  unavailable: [])
        guard effective.contains(.history) else { return [] }
        return discardedEnds(now: now, resume: config.sessions.behavior.resumeAfterRestart).map { AwakeHistoryEntry($0) }
    }

    /// A rule session cut short by a crash (review6 N2): it ran from its start until the last heartbeat, and ends
    /// `.moduleStopped` (same boot) or `.reboot` (the Mac restarted since). nil without a stamp, after a clean quit
    /// (which recorded it), or when the record is unusable.
    package func ruleEnd(now: ClockNow) -> AwakeAwayEnd? {
        let base = sanitized()
        guard let r = base.rule, let st = base.stop, !st.clean, !base.bootSession.isEmpty, now.wall.isFinite else {
            return nil
        }
        // Same boot: never after now either; another boot's wall clock is no bound (as for `awayEnds`).
        let sameBoot = base.bootSession == now.bootSession
        let end = max(r.startWall, sameBoot ? min(st.wall, now.wall) : st.wall)
        return AwakeAwayEnd(item: .rule(r), startWall: min(r.startWall, end), endWall: end,
                            reason: sameBoot ? .moduleStopped : .reboot)
    }

    /// The wall instant Snaptic last kept this snapshot's items: the stop stamp (never after `now`), else `now`.
    package func stoppedWall(now: ClockNow) -> Double {
        guard let st = sanitized().stop else { return now.wall }
        return min(st.wall, now.wall)
    }

    /// The start of an item's current history segment (its start, or where a resume after a gap began).
    package func segmentStart(_ id: StableID, startedAt: Double) -> Double {
        Self.segmentStart(stored: segmentStarts[id], startedAt: startedAt)
    }

    /// The same for a running item (SessionController's history start): a stored segment start counts only when it
    /// is finite and not before the item's own start.
    package static func segmentStart(stored: Double?, startedAt: Double) -> Double {
        guard let s = stored, s.isFinite, s >= startedAt else { return startedAt }
        return s
    }

    /// A carried item that restore doesn't resume after all (resume off after a crash, a guard, the app quit, the
    /// process exited, command-line control off): it ended when Snaptic stopped.
    package func restoreEnd(_ item: AwakeAwayEnd.Item, reason: AwakeEndReason, now: ClockNow) -> AwakeAwayEnd {
        let start = segmentStart(item.id, startedAt: item.startedAt)
        return AwakeAwayEnd(item: item, startWall: start, endWall: max(start, stoppedWall(now: now)), reason: reason,
                            lidClosed: hadLidMode(item))
    }

    /// A resumed item's segment before the gap (Snaptic not running) as its own entry, ending `.moduleStopped` when
    /// Snaptic stopped; nil when the gap is shorter than `splitGapSeconds` or nothing ran before it. The resumed
    /// part then starts at `now.wall`.
    package func resumedSegment(_ item: AwakeAwayEnd.Item, now: ClockNow) -> AwakeAwayEnd? {
        guard sanitized().stop != nil, now.wall.isFinite else { return nil }
        let stopped = stoppedWall(now: now)
        let start = segmentStart(item.id, startedAt: item.startedAt)
        guard now.wall - stopped >= Self.splitGapSeconds, stopped > start else { return nil }
        return AwakeAwayEnd(item: item, startWall: start, endWall: stopped, reason: .moduleStopped,
                            lidClosed: hadLidMode(item))
    }

    /// The item is the manual session that had lid-closed mode (`lidSession`).
    package func hadLidMode(_ item: AwakeAwayEnd.Item) -> Bool {
        if case .session(let s) = item { return lidSession != nil && lidSession == s.id }
        return false
    }

    /// One item's away end: limited by the stop stamp when it was written in the item's boot, else (same boot) by
    /// `now`; `.timeUp` when its own end came first, else `.reboot` (another boot) or `.timeUp` (same boot: it
    /// ran out while Snaptic wasn't running).
    private func awayEnd(_ item: AwakeAwayEnd.Item, boot: String, startedAt: Double,
                         ownEnd: (wall: Double, continuous: Double)?, now: ClockNow,
                         valid: (ClockNow) -> Bool) -> AwakeAwayEnd? {
        guard !boot.isEmpty, startedAt.isFinite else { return nil }
        let sameBoot = boot == now.bootSession
        var limit: (wall: Double, continuous: Double)
        if let st = stop, st.isValid, bootSession == boot {
            limit = (st.wall, st.continuous)
            if sameBoot { limit = (min(limit.wall, now.wall), min(limit.continuous, now.continuous)) }
        } else if sameBoot {
            limit = (now.wall, now.continuous)
        } else {
            return nil
        }
        let start = segmentStart(item.id, startedAt: startedAt)
        if let e = ownEnd, e.wall.isFinite, e.continuous.isFinite,
           e.continuous <= limit.continuous || e.wall <= limit.wall {
            guard valid(ClockNow(wall: e.wall - 1, continuous: e.continuous - 1, bootSession: boot)) else { return nil }
            let endWall = max(min(e.wall, limit.wall), startedAt)
            return AwakeAwayEnd(item: item, startWall: min(start, endWall), endWall: endWall, reason: .timeUp,
                                lidClosed: hadLidMode(item))
        }
        guard valid(ClockNow(wall: limit.wall, continuous: limit.continuous, bootSession: boot)) else { return nil }
        let endWall = max(limit.wall, startedAt)
        return AwakeAwayEnd(item: item, startWall: min(start, endWall), endWall: endWall,
                            reason: sameBoot ? .timeUp : .reboot, lidClosed: hadLidMode(item))
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

/// The rule session that governed at the last heartbeat (`AwakeRuntimeSnapshot.rule`): which rule, and its wall start.
package struct AwakeRuleRecord: Codable, Equatable, Sendable {
    package var triggerID: StableID
    package var startWall: Double

    package init(triggerID: StableID, startWall: Double) {
        self.triggerID = triggerID
        self.startWall = startWall
    }

    package var isValid: Bool { startWall.isFinite && startWall >= 0 }
}

/// When Snaptic stopped or was last seen running (`AwakeRuntimeSnapshot.stop`).
package struct AwakeStopStamp: Codable, Equatable, Sendable {
    package var wall: Double
    /// CLOCK_MONOTONIC_RAW of the snapshot's boot.
    package var continuous: Double
    /// true: Snaptic quit at this instant (it recorded what ran then); false: the last heartbeat (a crash ends
    /// somewhere after it, and a rule session in the snapshot is still owed, `ruleEnd`).
    package var clean: Bool

    package init(wall: Double, continuous: Double, clean: Bool) {
        self.wall = wall
        self.continuous = continuous
        self.clean = clean
    }

    private enum CodingKeys: String, CodingKey { case wall, continuous, clean }

    /// Lossy per field; an unreadable time makes the stamp invalid (dropped by `sanitized()`).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wall = c.lossy(.wall, -1)
        continuous = c.lossy(.continuous, -1)
        clean = c.lossy(.clean, false)
    }

    package var isValid: Bool { wall.isFinite && continuous.isFinite && wall >= 0 && continuous >= 0 }
}

extension AwakeHistoryEntry {
    /// The entry for an away end (kind, source and bundle from the item, as a live end records them).
    package init(_ e: AwakeAwayEnd) {
        switch e.item {
        case .session(let s):
            var bundleID: String?
            if case .whileApp(let b, _) = s.kind { bundleID = b }
            self.init(start: min(e.startWall, e.endWall), end: e.endWall, kind: s.kind.historyKind, source: s.source,
                      presetID: s.presetID, triggerID: nil, bundleID: bundleID, endReason: e.reason,
                      lidClosed: e.lidClosed)
        case .hold:
            self.init(start: min(e.startWall, e.endWall), end: e.endWall, kind: .process, source: .commandLine,
                      presetID: nil, triggerID: nil, bundleID: nil, endReason: e.reason)
        case .rule(let r):
            self.init(start: min(e.startWall, e.endWall), end: e.endWall, kind: .automatic, source: .rule,
                      presetID: nil, triggerID: r.triggerID, bundleID: nil, endReason: e.reason)
        }
    }
}

/// One history entry restore owes for an item it doesn't carry on, or for the part of a resumed item before the gap.
package struct AwakeAwayEnd: Equatable, Sendable {
    package enum Item: Equatable, Sendable {
        case session(AwakeSession), hold(AwakeHold), rule(AwakeRuleRecord)

        package var id: StableID {
            switch self {
            case .session(let s): return s.id
            case .hold(let h): return h.id
            case .rule(let r): return r.triggerID
            }
        }

        package var startedAt: Double {
            switch self {
            case .session(let s): return s.startedAt
            case .hold(let h): return h.startedAt
            case .rule(let r): return r.startWall
            }
        }
    }

    package var item: Item
    package var startWall: Double
    package var endWall: Double
    package var reason: AwakeEndReason
    /// The manual session had lid-closed mode (0.3.1 B1: the History entry's `lidClosed`).
    package var lidClosed: Bool

    package init(item: Item, startWall: Double, endWall: Double, reason: AwakeEndReason, lidClosed: Bool = false) {
        self.item = item
        self.startWall = startWall
        self.endWall = endWall
        self.reason = reason
        self.lidClosed = lidClosed
    }
}
