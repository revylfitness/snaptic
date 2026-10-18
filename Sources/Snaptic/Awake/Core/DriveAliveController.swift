import AppKit
import Combine
import SnapticKit

// Drive Alive policy driver (owner: J; PLAN 0.3 §2.9, §2.12, C9, N1, R5-14, security M1/M3). Decides which turned-on
// volumes DriveAliveService writes to, re-deciding whenever what governs, the power facts, the guard memory, the
// settings or system sleep change: never for command-line sessions or holds, never while guards forbid background
// work (hard floor, user floor, unreadable battery, critical heat), never around system sleep, and never before the
// UI-confirmed first write of a volume (`firstWriteDone`). Mirrors the service's per-volume state into the runtime.

@MainActor final class DriveAliveController: AwakeFeatureController {
    static var id: AwakeControllerID { .driveAlive }
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    private var lifetime: Lifetime?
    private var sinks: [AnyCancellable] = []
    private var sleeping = false

    init() {}

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard self.lifetime == nil else { return }
        self.context = context
        self.lifetime = lifetime
        sleeping = context.system.isSleeping
        context.power.observe(lifetime) { [weak self] in self?.apply() }
        context.system.observeEvents(lifetime) { [weak self] event in self?.systemEvent(event) }
        context.runtime.$governing
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
            .store(in: &sinks)
        context.state.$value
            .map(\.guardMemory)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
            .store(in: &sinks)
        context.driveAlive.$volumes
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volumes in
                MainActor.assumeIsolated {
                    guard let runtime = self?.context?.runtime, runtime.drives != volumes else { return }
                    runtime.drives = volumes
                }
            }
            .store(in: &sinks)
        apply()
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) { apply() }

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {
        if old.drives != new.drives { apply() }
    }

    func stop() {
        guard lifetime != nil else { return }
        sinks.removeAll()
        context?.driveAlive.setTargets([], interval: TimeInterval(DriveAliveConfig().intervalSeconds))
        context?.driveAlive.track([:])
        if context?.runtime.drives.isEmpty == false { context?.runtime.drives = [] }
        lifetime = nil
        sleeping = false
        context = nil
    }

    // MARK: Deciding

    private func systemEvent(_ event: SystemEvent) {
        switch event {
        case .willSleep:
            // §2.12: writes stop before sleep and resume after the wake.
            sleeping = true
            apply()
        case .didWake:
            sleeping = false
            apply()
        default:
            break
        }
    }

    private func apply() {
        guard let context, lifetime != nil else { return }
        let drives = context.config.value.drives.sanitized()
        var names: [VolumeUUIDKey: String] = [:]
        for (uuid, volume) in drives.volumes.values where volume.enabled { names[uuid] = volume.name }
        context.driveAlive.track(names)

        let governing = context.runtime.governing
        let allowed = !sleeping && backgroundWorkAllowed(context)
        var targets = Set<VolumeUUIDKey>()
        for (uuid, volume) in drives.volumes.values where volume.enabled {
            if DriveAlivePolicy.shouldWrite(sessionActive: governing.isActive, sessionSource: governing.source,
                                            evenWithoutSession: drives.evenWithoutSession,
                                            backgroundWorkAllowed: allowed,
                                            uiConfirmedFirstWrite: volume.firstWriteDone) {
                targets.insert(uuid)
            }
        }
        context.driveAlive.setTargets(targets, interval: TimeInterval(drives.intervalSeconds))
    }

    /// Security M1 (fail-safe: no power facts yet reads as "not allowed").
    private func backgroundWorkAllowed(_ context: AwakeContext) -> Bool {
        guard let facts = context.power.facts else { return false }
        return AwakeGuards.allowsBackgroundWork(facts, config: context.config.value.guards,
                                                memory: context.state.value.guardMemory)
    }
}
