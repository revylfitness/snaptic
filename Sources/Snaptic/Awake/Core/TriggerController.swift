import AppKit
import SnapticKit

// Rules (owner: G; PLAN 0.3 §2.7, §2.12, R5-10, R5-11): criterion facts from J's sources → TriggerEngine.step →
// the cached top rule → SessionController.arbitrate(), synchronously. Steps are coalesced to one per main-queue turn
// (arbitration never is); a wake steps only after a 5 s settle so displays, power and network re-read. Suppressions
// (a manual end) and Pause Rules live in the snapshot SessionController writes; hysteresis is memory only.
// Works as a holder of restored suppressions and the pause even while the `triggers` feature is off.

/// A rule session that stopped governing (HistoryController records it as an automatic session).
struct AwakeRuleEnd: Equatable {
    let triggerID: StableID
    let startWall: Double
    let endWall: Double
    let reason: AwakeEndReason
}

@MainActor final class TriggerController: AwakeFeatureController {
    static var id: AwakeControllerID { .triggers }
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    /// The governing candidate after the last step (nil while the feature is off).
    private(set) var top: TriggerTop?
    private(set) var suppressions: [StableID: TriggerSuppression] = [:]
    /// Wall time; "Pause Rules".
    private(set) var pausedUntil: Double?

    static let settleSeconds: Double = 5
    static let pauseLimit: Double = 24 * 3_600

    private var lifetime: Lifetime?
    private var sourcesLifetime: Lifetime?
    private var hysteresis: [StableID: TriggerHysteresis] = [:]
    private var displayOverride: (id: StableID, display: AwakeDisplayPolicy)?
    private var stepQueued = false
    private var settleUntil: Double?
    private var pendingEndReason: AwakeEndReason?
    private let ticker = Ticker()
    private let ruleEnds = EventFanout<AwakeRuleEnd>()
    private var observedKinds: Set<AwakeCriterionKind> = []

    init() {}

    var isRunning: Bool { lifetime != nil }
    var isPaused: Bool { pausedUntil.map { $0 > Date().timeIntervalSince1970 } ?? false }

    // MARK: Snapshot (SessionController)

    func restore(suppressions: [StableID: TriggerSuppression], pausedUntil: Double?) {
        self.suppressions = suppressions
        self.pausedUntil = pausedUntil
        publishPause()
        requestStep()
    }

    // MARK: Actions

    /// The user ended this rule's session: suppressed per its "After I turn it off" (never disables it).
    func manualEnd(_ id: StableID) {
        guard let ctx = context, let t = ctx.config.value.triggers.triggers.first(where: { $0.id == id }) else { return }
        let now = AwakeModule.clockNow()
        suppressions[id] = TriggerEngine.manualEnd(t, now: now.continuous)
        if top?.id == id { pendingEndReason = .user }
        step()
    }

    /// Pause Rules for `seconds` (1 hour from the menu, ≤ 24 h from the CLI).
    func pause(seconds: Double) {
        let s = min(max(seconds, 60), Self.pauseLimit)
        pausedUntil = Date().timeIntervalSince1970 + s
        afterPauseChange()
    }

    /// Pause Rules Until Tomorrow: until the start of the next local day.
    func pauseUntilTomorrow() {
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.startOfDay(for: Date()).addingTimeInterval(36 * 3_600)
        pausedUntil = calendar.startOfDay(for: tomorrow).timeIntervalSince1970
        afterPauseChange()
    }

    func resume() {
        pausedUntil = nil
        afterPauseChange()
    }

    /// Keep Display On for the governing rule session (lasts until that session ends).
    func setDisplayOverride(_ display: AwakeDisplayPolicy) {
        guard let t = top else { return }
        displayOverride = (t.id, display)
        top?.options.display = display
    }

    func observeRuleEnds(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeRuleEnd) -> Void) {
        ruleEnds.add(lifetime, handler)
    }

    /// Coalesced: one step per main-queue turn.
    func requestStep() {
        guard isRunning, !stepQueued else { return }
        stepQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.stepQueued = false
                self?.step()
            }
        }
    }

    private func afterPauseChange() {
        publishPause()
        if isRunning {
            step()
        } else {
            context?.sessions.arbitrate()
        }
    }

    private func publishPause() {
        let date = pausedUntil.map { Date(timeIntervalSince1970: $0) }
        if context?.runtime.pausedUntil != date { context?.runtime.pausedUntil = date }
    }

    // MARK: Stepping

    private func step() {
        guard let ctx = context, isRunning else { return }
        let now = AwakeModule.clockNow()
        if let settle = settleUntil {
            if now.continuous < settle {
                ticker.schedule(after: settle - now.continuous) { [weak self] in self?.step() }
                return
            }
            settleUntil = nil
        }
        let triggers = ctx.config.value.triggers.triggers
        var facts = CriterionFacts()
        for kind in TriggerEngine.requiredKinds(triggers) { ctx.source(for: kind)?.contribute(to: &facts) }
        facts.minuteOfWeek = AwakeFormat.minuteOfWeek()
        if facts.power == nil { facts.power = ctx.power.facts }
        if let p = pausedUntil, p <= now.wall { pausedUntil = nil }
        let paused = pausedUntil != nil
        let guardsHold = ctx.sessions.guardMemory.blocksTriggers(at: now.continuous)
        let result = TriggerEngine.step(triggers, facts: facts, now: now.continuous, hysteresis: hysteresis,
                                        suppressions: suppressions, paused: paused, guardsHold: guardsHold)
        hysteresis = result.hysteresis
        suppressions = result.suppressions

        var next = result.top
        if let o = displayOverride {
            if next?.id == o.id { next?.options.display = o.display } else { displayOverride = nil }
        }
        if let old = top, old.id != next?.id {
            let reason = pendingEndReason ?? .triggerEnded
            let startWall = now.wall - max(0, now.continuous - old.since)
            ruleEnds.fire(AwakeRuleEnd(triggerID: old.id, startWall: startWall, endWall: now.wall, reason: reason))
            EventLog.shared.record(AwakeLogEvent.sessionEnded(reason))
        }
        if let n = next, n.id != top?.id { EventLog.shared.record(AwakeLogEvent.triggerActive(index: n.index)) }
        pendingEndReason = nil
        top = next
        publish(triggers)
        scheduleTick(result.nextDeadline, triggers: triggers, now: now)
        ctx.sessions.arbitrate()
    }

    private func publish(_ triggers: [AwakeTrigger]) {
        guard let rt = context?.runtime else { return }
        let active = triggers.filter { $0.enabled && hysteresis[$0.id]?.active == true }.map(\.id)
        let waiting = triggers.filter { $0.enabled && hysteresis[$0.id]?.active != true && hysteresis[$0.id]?.trueSince != nil }
            .map(\.id)
        if rt.activeTriggerIDs != active { rt.activeTriggerIDs = active }
        if rt.waitingTriggerIDs != waiting { rt.waitingTriggerIDs = waiting }
        publishPause()
    }

    private func scheduleTick(_ deadline: Double?, triggers: [AwakeTrigger], now: ClockNow) {
        var waits: [Double] = []
        if let d = deadline { waits.append(d - now.continuous) }
        if let b = Ticker.secondsToNextBoundary(TriggerEngine.scheduleBoundaries(triggers)) { waits.append(b + 1) }
        if let p = pausedUntil { waits.append(p - now.wall) }
        guard let wait = waits.min() else {
            ticker.cancel()
            return
        }
        ticker.schedule(after: wait) { [weak self] in self?.step() }
    }

    // MARK: Sources

    /// Observes the sources of every criterion kind the enabled rules use (the module activated them).
    private func observeSources() {
        guard let ctx = context, let lifetime else { return }
        let kinds = TriggerEngine.requiredKinds(ctx.config.value.triggers.triggers)
        guard kinds != observedKinds || sourcesLifetime == nil else { return }
        sourcesLifetime?.end()
        let life = lifetime.child()
        sourcesLifetime = life
        observedKinds = kinds
        var seen: [ObjectIdentifier] = []
        for kind in kinds {
            guard let source = ctx.source(for: kind) else { continue }
            let key = ObjectIdentifier(source)
            guard !seen.contains(key) else { continue }
            seen.append(key)
            source.observe(life) { [weak self] in self?.requestStep() }
        }
    }

    private func systemEvent(_ event: SystemEvent) {
        switch event {
        case .didWake:
            settleUntil = AwakeModule.clockNow().continuous + Self.settleSeconds
            requestStep()
        case .clockChanged, .timeZoneChanged, .dayChanged:
            requestStep()
        default:
            break
        }
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard self.lifetime == nil else { return }   // idempotent
        self.context = context
        self.lifetime = lifetime
        context.power.observe(lifetime) { [weak self] in self?.requestStep() }
        context.system.observeEvents(lifetime) { [weak self] event in self?.systemEvent(event) }
        observeSources()
        publishPause()
        requestStep()
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {}

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {
        guard old.triggers != new.triggers else { return }
        let ids = Set(new.triggers.triggers.map(\.id))
        hysteresis = hysteresis.filter { ids.contains($0.key) }
        observeSources()
        requestStep()
    }

    /// The feature turned off or the module stops: no rule governs any more; suppressions and the pause stay (they
    /// are snapshot state).
    func stop() {
        ticker.cancel()
        sourcesLifetime?.end()
        sourcesLifetime = nil
        observedKinds = []
        lifetime = nil
        hysteresis = [:]
        displayOverride = nil
        settleUntil = nil
        let hadTop = top != nil
        if let old = top {
            let now = AwakeModule.clockNow()
            let startWall = now.wall - max(0, now.continuous - old.since)
            ruleEnds.fire(AwakeRuleEnd(triggerID: old.id, startWall: startWall, endWall: now.wall,
                                       reason: context?.host.signals.isTerminating == true ? .moduleStopped : .triggerEnded))
        }
        top = nil
        if let rt = context?.runtime {
            rt.activeTriggerIDs = []
            rt.waitingTriggerIDs = []
        }
        if hadTop { context?.sessions.arbitrate() }
    }
}
