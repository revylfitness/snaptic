import AppKit
import Combine
import CoreGraphics
import SnapticKit

// User idle time (owner: J; PLAN 0.3 §2.8, §2.9, security L1/M2). A `.common` timer: 10 s, or 5 s while a fast
// request lives (keepOnWhileActive, activity) or an enabled rule uses the idle criterion. Per-type `.hidSystemState`
// seconds (key down, flags changed, left/right/other mouse down, scroll wheel, mouse moved; never "any input"), turned
// into the last REAL input by IdleMath so Snaptic's own nudges and declarations never count. No TCC.

@MainActor final class IdleSampler: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.idle] }
    static let slowSeconds: TimeInterval = 10
    static let fastSeconds: TimeInterval = 5

    /// Event types that count as the user working (keys, clicks, scrolls): what ActivityPolicy waits on.
    private static let workTypes: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                                   .scrollWheel]

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private let timer = SourceTimer()
    private let fastRequests = NeedCounter()
    private var configSink: AnyCancellable?
    private var ruleNeedsFast = false

    /// Continuous instants of the last real input of any kind (mouse moves included) and of the last key, click or
    /// scroll. -infinity before the first read.
    private var lastRealInput = -Double.infinity
    private var lastWorkInput = -Double.infinity
    private var hasRead = false

    init() {}

    /// 5 s sampling while `lifetime` lives (keepOnWhileActive governs; ActivityController runs).
    func requestFastSampling(_ lifetime: Lifetime) { fastRequests.add(lifetime) }

    /// Seconds since the last real input (mouse moves included), re-read now; nil while inactive.
    func realIdleSeconds() -> Double? {
        guard active else { return nil }
        read(fire: false)
        return max(0, AwakeSourceClock.now() - lastRealInput)
    }

    /// Seconds since the last key, click or scroll that wasn't ours, re-read now (ActivityInputs.secondsSinceUserInput).
    func secondsSinceUserInput() -> Double? {
        guard active else { return nil }
        read(fire: false)
        return max(0, AwakeSourceClock.now() - lastWorkInput)
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        fastRequests.onChange = { [weak self] in self?.reschedule() }
        configSink = context.config.$value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.configChanged(value) }
            }
        configChanged(context.config.value)
        read(fire: false)
        reschedule()
    }

    func deactivate() {
        guard active else { return }
        active = false
        timer.cancel()
        fastRequests.onChange = nil
        configSink = nil
        ruleNeedsFast = false
        lastRealInput = -Double.infinity
        lastWorkInput = -Double.infinity
        hasRead = false
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active, hasRead else { return }
        facts.realIdleSeconds = max(0, AwakeSourceClock.now() - lastRealInput)
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Sampling

    private func configChanged(_ config: AwakeConfig) {
        let needs = AwakeFeatureGraph.rawState(.triggers, in: config.rawFeatures)
            && TriggerEngine.requiredKinds(config.triggers.triggers).contains(.idle)
        guard needs != ruleNeedsFast else { return }
        ruleNeedsFast = needs
        reschedule()
    }

    private func reschedule() {
        guard active else { return }
        let interval = fastRequests.isNeeded || ruleNeedsFast ? Self.fastSeconds : Self.slowSeconds
        guard !timer.isRunning || timer.interval != interval else { return }
        timer.start(every: interval, tolerance: interval / 10) { [weak self] in self?.read(fire: true) }
    }

    private func read(fire: Bool) {
        guard active else { return }
        let now = AwakeSourceClock.now()
        let nudges = context?.activity.recentNudges ?? []
        let declarations = context?.activity.recentDeclarations ?? []
        var work = lastWorkInput
        for type in Self.workTypes {
            let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
            work = IdleMath.lastRealInput(previous: work, now: now, hidIdleSeconds: idle, nudgeTimes: [],
                                          declareTimes: declarations)
        }
        let moved = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let real = IdleMath.lastRealInput(previous: max(lastRealInput, work), now: now, hidIdleSeconds: moved,
                                          nudgeTimes: nudges, declareTimes: declarations)
        lastWorkInput = work
        lastRealInput = real
        hasRead = true
        // Idle time grows every tick, so every timed read is a change.
        if fire { changes.fire() }
    }
}
