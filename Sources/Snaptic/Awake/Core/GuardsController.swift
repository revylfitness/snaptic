import AppKit
import Combine
import SnapticKit

// Guards (owner: G; PLAN 0.3 §2.6, §2.12, R5-6). SessionController evaluates AwakeGuards on every power change itself
// (critical heat and the 5% hard floor never depend on a feature state); this controller shows the notices that end
// nothing — serious heat (once per episode), Low Power Mode turning on, an unreadable battery — and re-evaluates when a
// thermal hold's 10-minute cool-down can clear, since no power event arrives then.

@MainActor final class GuardsController: AwakeFeatureController {
    static var id: AwakeControllerID { .guards }
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    private var lifetime: Lifetime?
    private var sinks: [AnyCancellable] = []
    private var recheck: Timer?

    init() {}

    private func notice(_ n: AwakeGuardNotice) {
        guard let ctx = context, let lifetime else { return }
        switch n {
        case .warn(.thermal):
            ctx.host.toasts.show(L("Your Mac is running hot. Awake ends if it gets too hot."), action: nil, lifetime: lifetime)
        case .warn(.lowPowerMode):
            ctx.host.toasts.show(L("Low Power Mode is on. Awake keeps running."), action: nil, lifetime: lifetime)
        case .warn:
            break
        case .batteryUnreadable:
            ctx.host.toasts.show(L("Snaptic can't read the battery level, so it stopped appearing active and keeping drives awake."),
                                 action: nil, lifetime: lifetime)
        }
    }

    /// A thermal hold clears 10 minutes after the heat dropped to fair or below: evaluate again then.
    private func scheduleRecheck() {
        recheck?.invalidate()
        recheck = nil
        guard let ctx = context, let at = AwakeGuards.holdClearsAt(ctx.sessions.guardMemory) else { return }
        let delay = max(1, at - AwakeModule.clockNow().continuous + 1)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.context?.sessions.evaluateGuards() }
        }
        timer.tolerance = min(delay * 0.1, 30)
        RunLoop.main.add(timer, forMode: .common)
        recheck = timer
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        self.context = context
        self.lifetime = lifetime
        context.sessions.observeGuardNotices(lifetime) { [weak self] n in self?.notice(n) }
        context.runtime.$power
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleRecheck() } }
            .store(in: &sinks)
        context.sessions.evaluateGuards()
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {}

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {}

    func stop() {
        sinks.removeAll()
        recheck?.invalidate()
        recheck = nil
        lifetime = nil
        context = nil
    }
}
