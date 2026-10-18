import AppKit
import SnapticKit

// History (owner: G; PLAN 0.3 §2.14, §3.6): every manual-session, hold and rule-session end becomes one local entry
// in SnapticAwakeHistoryV1 (≤ 500, 90 days, short `.replaced` runs merged by Kit). It never reaches logs,
// diagnostics, the CLI or exports. Controllers stop in reverse start order, so this one records what still runs when
// the module stops — except what a relaunch will resume (quit with "Resume after restart", `--pid` holds), which is
// recorded when it really ends: at its end after the relaunch, or by restore when it isn't carried on (ran out, the
// Mac restarted, a guard...), never counting the time Snaptic wasn't running (round-2 F1). A resume after a gap
// records the part before it as its own entry.

@MainActor final class HistoryController: AwakeFeatureController {
    static var id: AwakeControllerID { .history }
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    private var lifetime: Lifetime?

    init() {}

    /// Today's and this week's totals (local calendar; seconds).
    func totals(now: Date = Date()) -> (today: Double, week: Double) {
        guard let ctx = context else { return (0, 0) }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        return ctx.history.value.totals(todayStart: today.timeIntervalSince1970, weekStart: week.timeIntervalSince1970,
                                        now: now.timeIntervalSince1970)
    }

    private func record(_ item: AwakeEndedItem, _ reason: AwakeEndReason) {
        guard let ctx = context else { return }
        let now = Date().timeIntervalSince1970
        let entry: AwakeHistoryEntry
        switch item {
        case .session(let s):
            if skipsForResume(reason) && ctx.config.value.sessions.behavior.resumeAfterRestart { return }
            var bundleID: String?
            if case .whileApp(let b, _) = s.kind { bundleID = b }
            let start = ctx.sessions.historyStart(s.id, startedAt: s.startedAt)
            entry = AwakeHistoryEntry(start: min(start, now), end: now, kind: s.kind.historyKind, source: s.source,
                                      presetID: s.presetID, triggerID: nil, bundleID: bundleID, endReason: reason)
        case .hold(let h):
            if h.binding.isProcess && skipsForResume(reason) { return }
            let start = ctx.sessions.historyStart(h.id, startedAt: h.startedAt)
            entry = AwakeHistoryEntry(start: min(start, now), end: now, kind: .process, source: .commandLine,
                                      presetID: nil, triggerID: nil, bundleID: nil, endReason: reason)
        }
        append(entry)
    }

    /// Rule sessions never resume after a relaunch (the rule starts a new one), so every end is recorded, quitting
    /// included; one a crash cut short arrives through the away ends (the snapshot's rule record, review6 N2).
    private func recordRule(_ end: AwakeRuleEnd) {
        append(AwakeHistoryEntry(start: min(end.startWall, end.endWall), end: end.endWall, kind: .automatic,
                                 source: .rule, presetID: nil, triggerID: end.triggerID, bundleID: nil,
                                 endReason: end.reason))
    }

    /// What restore owes for the snapshot (F1, F5b): recorded with the end it computed.
    private func recordAway(_ end: AwakeAwayEnd) {
        append(AwakeHistoryEntry(end))
    }

    /// A launch that discards the snapshot unread (`Modules.disable.awake`, ModuleHost): what it held still gets its
    /// history entries, ending when Snaptic stopped (F1). Nothing when History isn't effective: its switch off or
    /// `Awake.disable.history` set (security S3-1, read like AwakeModule reads it).
    static func recordDiscardedSnapshot(_ state: ConfigStore<AwakeRuntimeSnapshot>, history: ConfigStore<AwakeHistory>,
                                        config: AwakeConfig) {
        let now = AwakeModule.clockNow()
        let entries = state.value.discardedHistory(now: now, config: config, killSwitches: AwakeModule.readKillSwitches())
        append(entries, to: history, now: now.wall)
    }

    /// Quitting: what resumes after the relaunch is recorded when it really ends.
    private func skipsForResume(_ reason: AwakeEndReason) -> Bool {
        reason == .moduleStopped && (context?.host.signals.isTerminating ?? false)
    }

    private func append(_ entry: AwakeHistoryEntry) {
        guard let ctx = context else { return }
        Self.append([entry], to: ctx.history, now: Date().timeIntervalSince1970)
    }

    /// The one write path: each entry sanitized (an unusable one is dropped), capped at 500, then pruned to 90 days;
    /// nothing is written when no entry is usable.
    private static func append(_ entries: [AwakeHistoryEntry], to store: ConfigStore<AwakeHistory>, now: Double) {
        let usable = entries.compactMap { $0.sanitized() }
        guard !usable.isEmpty else { return }
        var h = store.value
        for e in usable { h = h.appending(e, cap: AwakeHistory.maxEntries) }
        store.value = h.pruned(now: now, keepDays: AwakeHistory.keepDays)
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard self.lifetime == nil else { return }   // idempotent
        self.context = context
        self.lifetime = lifetime
        context.sessions.observeEnds(lifetime) { [weak self] item, reason in self?.record(item, reason) }
        context.triggers.observeRuleEnds(lifetime) { [weak self] end in self?.recordRule(end) }
        context.sessions.observeAwayEnds(lifetime) { [weak self] end in self?.recordAway(end) }
        let pruned = context.history.value.pruned(now: Date().timeIntervalSince1970, keepDays: AwakeHistory.keepDays)
        if pruned != context.history.value { context.history.value = pruned }
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {}

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {}

    /// Module stop: records what still runs (the session controller stops after this one). The module publishes the
    /// new effective set before it stops a controller whose features went away, so `history` still being effective
    /// here means the whole module is stopping; a history feature turned off records nothing more.
    func stop() {
        guard let ctx = context else { return }
        if ctx.runtime.isEffective(.history) {
            if let s = ctx.sessions.manual { record(.session(s), .moduleStopped) }
            for h in ctx.sessions.holds { record(.hold(h), .moduleStopped) }
            // TriggerController stops after this one; its end of the governing rule would go unheard (F5a).
            if let end = ctx.triggers.currentRuleEnd(.moduleStopped) { recordRule(end) }
        }
        lifetime = nil
        context = nil
    }
}
