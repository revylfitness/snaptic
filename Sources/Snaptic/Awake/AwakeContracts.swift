import AppKit
import SnapticKit

// Awake protocols and the one fan-out implementation (lead; PLAN 0.3 §2.8, §2.11).

/// An Awake service, activated by need in `AwakeFeatureGraph.activationOrder`.
@MainActor protocol AwakeServiceLifecycle: AnyObject {
    /// Idempotent.
    func activate(_ context: AwakeContext, lifetime: Lifetime)
    /// Idempotent; releases ports, listeners, timers.
    func deactivate()
}

/// A service that produces trigger facts.
@MainActor protocol CriterionSource: AwakeServiceLifecycle {
    static var kinds: Set<AwakeCriterionKind> { get }
    /// Writes this source's fields into the facts (nil while not ready).
    func contribute(to facts: inout CriterionFacts)
    /// Multicast (code M7). The handler is dropped when `lifetime` ends.
    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void)
}

/// One controller per AwakeControllerID, constructed with init() per module start.
@MainActor protocol AwakeFeatureController: AnyObject {
    static var id: AwakeControllerID { get }
    init()
    /// Static facts only: services may not be active yet.
    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability
    /// `lifetime` ends right after stop().
    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>)
    /// The effective subset changed but is still non-empty. Never a restart.
    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>)
    func configDidChange(from old: AwakeConfig, to new: AwakeConfig)
    /// Synchronous, idempotent, never shows UI.
    func stop()
}

/// The fan-out every source uses: handlers run in registration order, on main, until their lifetime ends.
@MainActor final class ChangeFanout {
    private var handlers: [(id: UInt64, run: @MainActor () -> Void)] = []
    private var next: UInt64 = 0

    init() {}

    func add(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) {
        guard !lifetime.isEnded else { return }
        next &+= 1
        let id = next
        handlers.append((id, handler))
        lifetime.onEnd { [weak self] in self?.handlers.removeAll { $0.id == id } }
    }

    func fire() {
        for handler in handlers { handler.run() }
    }

    var count: Int { handlers.count }
}
