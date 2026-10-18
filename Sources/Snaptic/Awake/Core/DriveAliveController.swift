import AppKit
import Combine
import SnapticKit

// Drive Alive policy driver (owner: J; PLAN 0.3 §2.9, §2.12, C9, N1, R5-14, security M1/M3). Decides which turned-on
// volumes DriveAliveService writes to, re-deciding whenever what governs, the power facts, the guard memory, the
// settings or system sleep change: never for command-line sessions or holds, never while guards forbid background
// work (hard floor, user floor, unreadable battery, critical heat), never around system sleep, and never before the
// UI-confirmed first write of a volume (`firstWriteDone`). Mirrors the service's per-volume state into the runtime.
// The guard memory is SessionController's in-memory copy, never the outside-writable snapshot store (security S-1).
// The PreventDiskIdle assertion follows the service's `isWriting` (awake-correctness F1): this controller
// re-arbitrates whenever it flips, so the assertion exists only while a permitted target is mounted and eligible.

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
        // SessionController sets `runtime.power` after every guard evaluation (its guard memory is current by then),
        // so the main-queue hop re-decides with the evaluated memory.
        context.runtime.$power
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
            .store(in: &sinks)
        context.driveAlive.$isWriting
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.writingChanged() } }
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
        let wasWriting = context?.driveAlive.isWriting == true
        context?.driveAlive.setTargets([], interval: TimeInterval(DriveAliveConfig().intervalSeconds))
        context?.driveAlive.track([:])
        if context?.runtime.drives.isEmpty == false { context?.runtime.drives = [] }
        if wasWriting, let sessions = context?.sessions {
            // Drive Alive turned off while Awake keeps running: drop PreventDiskIdle. After the current pass, so a
            // module stop (sessions stop right after this) arbitrates nothing.
            let box = CallbackTarget(sessions)
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.arbitrate() } }
        }
        lifetime = nil
        sleeping = false
        context = nil
    }

    // MARK: Deciding

    /// The arbiter's `driveAliveWriting` input changed (awake-correctness F1).
    private func writingChanged() {
        guard let context, lifetime != nil else { return }
        context.sessions.arbitrate()
    }

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
                                                memory: context.sessions.guardMemory)
    }
}
