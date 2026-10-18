import AppKit
import SnapticKit

// History (owner: G; PLAN 0.3 §2.14, §3.6): every manual-session, hold and rule-session end becomes one local entry
// in SnapticAwakeHistoryV1 (≤ 500, 90 days, short `.replaced` runs merged by Kit). It never reaches logs,
// diagnostics, the CLI or exports. Controllers stop in reverse start order, so this one records what still runs when
// the module stops — except what a relaunch will resume (quit with "Resume after restart", `--pid` holds), which is
// recorded when it really ends.

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
            entry = AwakeHistoryEntry(start: min(s.startedAt, now), end: now, kind: s.kind.historyKind, source: s.source,
                                      presetID: s.presetID, triggerID: nil, bundleID: bundleID, endReason: reason)
        case .hold(let h):
            if h.binding.isProcess && skipsForResume(reason) { return }
            entry = AwakeHistoryEntry(start: min(h.startedAt, now), end: now, kind: .process, source: .commandLine,
                                      presetID: nil, triggerID: nil, bundleID: nil, endReason: reason)
        }
        append(entry)
    }

    private func recordRule(_ end: AwakeRuleEnd) {
        if skipsForResume(end.reason) { return }
        append(AwakeHistoryEntry(start: min(end.startWall, end.endWall), end: end.endWall, kind: .automatic,
                                 source: .rule, presetID: nil, triggerID: end.triggerID, bundleID: nil,
                                 endReason: end.reason))
    }

    /// Quitting: what resumes after the relaunch is recorded when it really ends.
    private func skipsForResume(_ reason: AwakeEndReason) -> Bool {
        reason == .moduleStopped && (context?.host.signals.isTerminating ?? false)
    }

    private func append(_ entry: AwakeHistoryEntry) {
        guard let ctx = context, let e = entry.sanitized() else { return }
        let now = Date().timeIntervalSince1970
        ctx.history.value = ctx.history.value.appending(e, cap: AwakeHistory.maxEntries)
            .pruned(now: now, keepDays: AwakeHistory.keepDays)
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard self.lifetime == nil else { return }   // idempotent
        self.context = context
        self.lifetime = lifetime
        context.sessions.observeEnds(lifetime) { [weak self] item, reason in self?.record(item, reason) }
        context.triggers.observeRuleEnds(lifetime) { [weak self] end in self?.recordRule(end) }
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
        }
        lifetime = nil
        context = nil
    }
}
