import AppKit
import Combine
import SnapticKit

// Activity simulation driver (owner: J; PLAN 0.3 §2.9, §2.12, N10, R5-7, security M1/M2). Once per
// ActivityPolicy.intervalSeconds (60 s, a `.common` timer) and whenever what governs changes, it gathers the inputs
// at the moment of use (session dictionary, screensaver, display sleep, switcher, last real input, Snaptic's own
// clock for the cap), lets the Kit policy decide and has ActivitySimulator act. Never acts while guards forbid
// background work, while locked, off console, during a screensaver, with the displays asleep or around system sleep.
// Pointer movement follows N10 (ActivityPolicy.nudgeAllowed) and asks first for a hotkey start
// (SessionController.requestPointerConfirmation). The cap counts on the gate's continuous clock across back-to-back
// sessions (R5-7); only a new UI start clears it. The first nudge of a manual session shows "Awake is moving the
// pointer slightly." [Stop] (§3.2); Stop declines pointer movement for that session (declare only).

@MainActor final class ActivityController: AwakeFeatureController {
    static var id: AwakeControllerID { .activity }
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    private var effective: Set<AwakeFeature> = []
    private var lifetime: Lifetime?
    private let timer = SourceTimer()
    private var sinks: [AnyCancellable] = []
    private var sleeping = false
    private var cappedLogged = false
    private var notice = NudgeNotice()
    /// The first-nudge notice's lifetime: ends with its session (or the controller), which removes the toast.
    private var noticeLifetime: Lifetime?
    private var noticeSession: StableID?

    init() {}

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard self.lifetime == nil else { return }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        sleeping = context.system.isSleeping
        // 5 s idle sampling while activity runs, so "60 s since the last input" is measured to within 5 s.
        context.idle.requestFastSampling(lifetime)
        context.system.observeEvents(lifetime) { [weak self] event in self?.systemEvent(event) }
        context.runtime.$governing
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.evaluate() } }
            .store(in: &sinks)
        context.host.signals.$switcherVisible
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in MainActor.assumeIsolated { if visible { self?.evaluate() } } }
            .store(in: &sinks)
        timer.start(every: ActivityPolicy.intervalSeconds, tolerance: 2) { [weak self] in self?.evaluate() }
        evaluate()
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {
        self.effective = effective
        evaluate()
    }

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {
        if old.activity != new.activity { evaluate() }
    }

    func stop() {
        guard lifetime != nil else { return }
        timer.cancel()
        sinks.removeAll()
        context?.activity.stop()
        context?.runtime.activity = .off
        context?.runtime.activityCapped = false
        endNotice()
        notice = NudgeNotice()
        lifetime = nil
        effective = []
        sleeping = false
        cappedLogged = false
        context = nil
    }

    // MARK: Deciding

    private func systemEvent(_ event: SystemEvent) {
        switch event {
        case .willSleep:
            // §2.12: activity stops before sleep; nothing acts until the wake.
            sleeping = true
            idle()
        case .didWake:
            sleeping = false
            evaluate()
        case .lockHint, .unlockHint, .screensaverStarted, .screensaverStopped, .screensDidSleep, .screensDidWake,
             .sessionResigned, .sessionBecameActive:
            evaluate()
        default:
            break
        }
    }

    /// Stop acting now (the session continues).
    private func idle() {
        guard let context else { return }
        context.activity.stop()
        if context.runtime.activity != .off { context.runtime.activity = .off }
    }

    private func evaluate() {
        guard let context, lifetime != nil else { return }
        let governing = context.runtime.governing
        let manualID: StableID?
        if case .manual(let session) = governing { manualID = session.id } else { manualID = nil }
        if noticeSession != nil, noticeSession != manualID { endNotice() }
        // Rules never move the pointer (N10); holds have no activity.
        var mode = governing.options?.activity ?? .off
        if case .trigger = governing, mode == .nudge { mode = .declare }
        guard effective.contains(.activity), governing.isActive, mode != .off, !sleeping else {
            setCapped(false)
            idle()
            return
        }
        guard backgroundWorkAllowed(context) else {
            idle()
            return
        }
        let now = AwakeSourceClock.now()
        let gate = context.sessions.activityGate
        let config = context.config.value.activity.sanitized()
        let session = context.system.sessionFacts()
        let accessibility = effective.contains(.pointerNudge) && context.activity.canPostEvents
        let inputs = ActivityInputs(
            mode: mode,
            nudgeAllowed: ActivityPolicy.nudgeAllowed(governing: governing, gate: gate,
                                                      pointerNudgeEffective: effective.contains(.pointerNudge),
                                                      accessibility: accessibility),
            screenLocked: session.locked,
            onConsole: session.onConsole,
            screensaverRunning: context.system.screensaverRunning,
            displaysAsleep: context.system.displaysAsleep,
            switcherVisible: context.host.signals.switcherVisible,
            // Unknown reads as "the user is working" (0 s): nothing acts.
            secondsSinceUserInput: context.idle.secondsSinceUserInput() ?? 0,
            activityElapsedSeconds: gate.activityElapsed(now: now),
            stopAfterSeconds: Double(config.stopAfterHours) * 3600,
            pointerEdgeDistance: mode == .nudge ? context.activity.pointerEdgeDistance() : nil)
        let capped = gate.activitySince != nil && inputs.activityElapsedSeconds >= inputs.stopAfterSeconds
        setCapped(capped)
        if accessibility, ActivityPolicy.needsPointerConfirmation(inputs, gate: gate) {
            context.sessions.requestPointerConfirmation()
        }
        let decision = ActivityPolicy.decide(inputs)
        context.activity.perform(decision)
        let acted = context.activity.lastAction
        if acted != .skip { context.sessions.noteActivityActed(now: now) }
        if notice.noteAction(acted, session: manualID), let manualID { showNotice(for: manualID) }
        let shown: AwakeActivityMode = acted == .nudge ? .nudge : acted == .declare ? .declare : .off
        if context.runtime.activity != shown { context.runtime.activity = shown }
    }

    /// Security M1: hard floor, user floor, unreadable battery and critical heat stop activity (fail-safe: no power
    /// facts yet reads as "not allowed"). The guard memory is SessionController's in-memory copy, never the
    /// outside-writable snapshot store (security S-1).
    private func backgroundWorkAllowed(_ context: AwakeContext) -> Bool {
        guard let facts = context.power.facts else { return false }
        return AwakeGuards.allowsBackgroundWork(facts, config: context.config.value.guards,
                                                memory: context.sessions.guardMemory)
    }

    // MARK: First-nudge notice

    private func showNotice(for session: StableID) {
        guard let context, let parent = lifetime else { return }
        endNotice()
        let life = parent.child()
        noticeLifetime = life
        noticeSession = session
        context.host.toasts.show(L("Awake is moving the pointer slightly."), actions: [
            ToastAction(title: L("Stop")) { [weak self] in self?.stopPointer() },
        ], lifetime: life)
    }

    private func endNotice() {
        noticeLifetime?.end()
        noticeLifetime = nil
        noticeSession = nil
    }

    /// Stop on the notice: no more pointer movement in this session (it still appears active by declaring).
    private func stopPointer() {
        guard let context, lifetime != nil else { return }
        context.sessions.declinePointer()
        endNotice()
        evaluate()
    }

    private func setCapped(_ capped: Bool) {
        guard let context else { return }
        if context.runtime.activityCapped != capped { context.runtime.activityCapped = capped }
        if capped, !cappedLogged {
            cappedLogged = true
            EventLog.shared.record(.activityCapped)
        } else if !capped {
            cappedLogged = false
        }
    }
}
