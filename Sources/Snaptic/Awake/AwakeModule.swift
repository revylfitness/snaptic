import AppKit
import Combine
import SwiftUI
import SnapticKit

/// The Awake module (lead; PLAN 0.3 §2.1, §2.11): resolves the effective features, activates the services they
/// need in dependency order, and starts one controller per AwakeControllerID that has effective features. Mirrors
/// DisplaysModule; the three stores are ModuleHost's (one owner, R5-14).
@MainActor final class AwakeModule: SnapticModule, StatusItemProvider {
    let id: ModuleID = .awake
    let title = L("Awake")
    let symbolName = "cup.and.saucer"
    let summary = L("Keeps your Mac awake for a while, while an app runs, or while rules apply.")
    private(set) var state: ModuleState = .stopped

    var requiredPermissions: Set<Permission> {
        let set = context == nil ? resolveEffective(config.value) : effective
        return set.reduce(into: Set<Permission>()) { $0.formUnion(AwakeFeatureGraph.permissions($1)) }
    }

    let config: ConfigStore<AwakeConfig>
    let stateStore: ConfigStore<AwakeRuntimeSnapshot>
    let historyStore: ConfigStore<AwakeHistory>
    let runtime = AwakeRuntimeState()

    /// Every controller class; the order is the start order (stop runs in reverse). `sessions` and `triggers` are
    /// the context's own instances (other controllers call them).
    static let controllerTypes: [any AwakeFeatureController.Type] = [
        SessionController.self, GuardsController.self, TriggerController.self, ActivityController.self,
        DriveAliveController.self, IndicatorController.self, HistoryController.self, AwakeAutomation.self,
    ]

    private var context: AwakeContext?
    private var moduleContext: ModuleContext?
    private var controllers: [AwakeControllerID: any AwakeFeatureController] = [:]
    private var controllerLifetimes: [AwakeControllerID: Lifetime] = [:]
    private var controllerFeatures: [AwakeControllerID: Set<AwakeFeature>] = [:]
    private var serviceLifetimes: [AwakeServiceID: Lifetime] = [:]
    private var effective: Set<AwakeFeature> = []
    private var killSwitches: Set<AwakeFeature> = []
    private var dynamicNeeds: AwakeDynamicNeeds = []
    private var lastConfig: AwakeConfig
    private var sinks: [AnyCancellable] = []
    /// Kept across starts so the item (G's) can stay while its own menu is open.
    private var indicator: IndicatorController?
    /// G's Settings pages read the stores and runtime, and the context while the module runs (one per app run).
    private(set) lazy var pageEnvironment = AwakePageEnvironment(config: config, history: historyStore, runtime: runtime,
                                                                 context: { [weak self] in self?.context })

    /// The host owns the stores for the app's lifetime.
    init(config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>, history: ConfigStore<AwakeHistory>) {
        self.config = config
        stateStore = state
        historyStore = history
        lastConfig = config.value
    }

    // MARK: SnapticModule

    /// §2.1 start order: snapshot read once and sanitized → dynamic needs seeded → services → controllers (the
    /// session controller restores) → re-apply if the needs changed.
    func start(_ moduleContext: ModuleContext) {
        guard context == nil else { return }
        self.moduleContext = moduleContext
        killSwitches = Self.readKillSwitches()
        let ctx = AwakeContext(host: AwakeHost(moduleContext), config: config, state: stateStore,
                               history: historyStore, runtime: runtime)
        context = ctx
        let snapshot = stateStore.value.sanitized(now: Self.clockNow())
        dynamicNeeds = snapshot.dynamicNeeds
        controllers = [:]
        for type in Self.controllerTypes {
            switch type.id {
            case .sessions: controllers[.sessions] = ctx.sessions
            case .triggers: controllers[.triggers] = ctx.triggers
            default: controllers[type.id] = type.init()
            }
        }
        if let indicator = controllers[.indicator] as? IndicatorController { self.indicator = indicator }
        runtime.availability = availabilityTable(ctx)
        lastConfig = config.value
        apply(resolveEffective(config.value))
        ctx.sessions.restore(snapshot)
        // §2.1 step 5: re-apply once if restore changed the needs; afterwards follow every change.
        if ctx.sessions.dynamicNeeds != dynamicNeeds {
            dynamicNeeds = ctx.sessions.dynamicNeeds
            apply(effective)
        }
        ctx.sessions.onDynamicNeedsChange = { [weak self] needs in
            guard let self, self.context != nil, needs != self.dynamicNeeds else { return }
            self.dynamicNeeds = needs
            self.apply(self.effective)
        }
        state = .running
        runtime.moduleState = .running
        config.$value
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.configChanged() } }
            .store(in: &sinks)
        moduleContext.requestStatusPlan()
    }

    /// Synchronous and idempotent: controllers in reverse, services in reverse, every assertion released.
    func stop() {
        guard let ctx = context else { return }
        sinks.removeAll()
        for type in Self.controllerTypes.reversed() {
            guard let life = controllerLifetimes[type.id] else { continue }
            controllers[type.id]?.stop()
            life.end()
        }
        controllerLifetimes = [:]
        controllerFeatures = [:]
        for id in AwakeFeatureGraph.activationOrder.reversed() {
            guard let life = serviceLifetimes[id] else { continue }
            ctx.service(id).deactivate()
            life.end()
        }
        serviceLifetimes = [:]
        ctx.assertions.releaseAll()
        // Quit keeps the snapshot so a relaunch resumes; a disable or Safe Mode clears it (§2.5).
        if !ctx.host.signals.isTerminating { stateStore.value = AwakeRuntimeSnapshot() }
        stateStore.flush()
        historyStore.flush()
        config.flush()
        effective = []
        dynamicNeeds = []
        context = nil
        controllers = [:]
        state = .stopped
        runtime.reset()
        moduleContext?.requestStatusPlan()
        moduleContext = nil
    }

    /// §5.4: the compact section (G's AwakeMenuRows through the indicator).
    func menuSection() -> [NSMenuItem] { context == nil ? [] : (indicator?.compactSection() ?? []) }

    /// 0.3.1 A1, N11: lid-closed mode is on (", even with the lid closed" on the shared glyph's label). What the plan
    /// calls `AwakeHost.lidModeOn`: StatusMenu reaches Awake through the module, not through AwakeHost.
    var lidModeOn: Bool { runtime.lidMode.isOn }

    /// Awake's sub-pages (§4.3). G's routes join this switch when its page lands.
    func settingsDestination(_ route: SettingsRoute) -> AnyView? {
        switch route.id {
        case DrivesPageControls.surface:   // "awake.drives"
            return AnyView(DrivesPage(config: config, runtime: runtime, live: { [weak self] in self?.context }))
        case AwakeHistoryPageControls.surface:   // "awake.history"
            return AwakePage.historyPage(env: pageEnvironment)
        default:
            return nil
        }
    }

    /// The Awake section of the shared diagnostics report (G's AwakeDiagnostics; §3.6: no names or identifiers).
    func diagnosticsLines() -> [String] { AwakeDiagnostics().lines(context) }

    var tint: SettingsTint { .orange }
    var highlights: [FeatureHighlight] { AwakePage.highlights }
    func settingsRoot() -> SettingsRoot { AwakePage.settingsRoot(env: pageEnvironment) }
    func settingsIndex() -> [SettingsSearchEntry] { AwakePage.searchEntries() }

    // MARK: StatusItemProvider (G's IndicatorController owns the item)

    var statusItem: NSStatusItem? { indicator?.statusItem }

    func applyStatusItem(_ row: CustomItemRow) {
        indicator?.applyStatusItem(row)
    }

    // MARK: Resolution

    private func resolveEffective(_ value: AwakeConfig) -> Set<AwakeFeature> {
        let unavailable = Set(runtime.availability.compactMap { $0.value.isAvailable ? nil : $0.key })
        return AwakeFeatureGraph.resolve(raw: value.rawFeatures, killSwitches: killSwitches,
                                         safeMode: moduleContext?.safeMode.isActive ?? false, unavailable: unavailable)
    }

    private func availabilityTable(_ ctx: AwakeContext) -> [AwakeFeature: FeatureAvailability] {
        var table: [AwakeFeature: FeatureAvailability] = [:]
        for feature in AwakeFeature.allCases {
            let controller = AwakeFeatureGraph.controller(of: feature)
            table[feature] = controllers[controller]?.availability(of: feature, context: ctx) ?? .available
        }
        return table
    }

    private func configChanged() {
        guard context != nil else { return }
        let new = config.value
        let old = lastConfig
        guard new != old else { return }
        lastConfig = new
        let before = controllerLifetimes
        if new.rawFeatures != old.rawFeatures || new.triggers != old.triggers { apply(resolveEffective(new)) }
        for type in Self.controllerTypes where before[type.id] != nil && controllerLifetimes[type.id] != nil {
            controllers[type.id]?.configDidChange(from: old, to: new)
        }
    }

    /// The apply order of §2.1 (same as Displays §3.6).
    private func apply(_ newEffective: Set<AwakeFeature>) {
        guard let ctx = context else { return }
        effective = newEffective
        runtime.effectiveFeatures = newEffective

        var sets: [AwakeControllerID: Set<AwakeFeature>] = [:]
        for feature in newEffective { sets[AwakeFeatureGraph.controller(of: feature), default: []].insert(feature) }

        // 0. Controllers that lose some (not all) features let go of them first.
        for type in Self.controllerTypes.reversed() {
            guard let new = sets[type.id], let current = controllerFeatures[type.id], !new.isSuperset(of: current) else { continue }
            let kept = new.intersection(current)
            controllerFeatures[type.id] = kept
            controllers[type.id]?.effectiveFeaturesDidChange(kept)
        }
        // 1. Stop controllers whose effective set became empty.
        for type in Self.controllerTypes.reversed() where sets[type.id] == nil {
            guard let life = controllerLifetimes[type.id] else { continue }
            controllers[type.id]?.stop()
            life.end()
            controllerLifetimes[type.id] = nil
            controllerFeatures[type.id] = nil
        }
        // 2. Services: deactivate the unneeded (reverse), activate the needed (in order).
        let criteria = TriggerEngine.requiredKinds(config.value.triggers.triggers)
        let needed = AwakeFeatureGraph.requiredServices(effective: newEffective, criteria: criteria, dynamic: dynamicNeeds)
        for id in AwakeFeatureGraph.activationOrder.reversed() where !needed.contains(id) {
            guard let life = serviceLifetimes[id] else { continue }
            ctx.service(id).deactivate()
            life.end()
            serviceLifetimes[id] = nil
        }
        for id in AwakeFeatureGraph.activationOrder where needed.contains(id) && serviceLifetimes[id] == nil {
            let life = ctx.host.lifetime.child()
            serviceLifetimes[id] = life
            ctx.service(id).activate(ctx, lifetime: life)
        }
        // 3. Start new controllers; tell the rest about gained features.
        for type in Self.controllerTypes {
            guard let set = sets[type.id] else { continue }
            if controllerLifetimes[type.id] == nil {
                let life = ctx.host.lifetime.child()
                controllerLifetimes[type.id] = life
                controllerFeatures[type.id] = set
                controllers[type.id]?.start(ctx, lifetime: life, effective: set)
            } else if controllerFeatures[type.id] != set {
                controllerFeatures[type.id] = set
                controllers[type.id]?.effectiveFeaturesDidChange(set)
            }
        }
    }

    // MARK: Host facts

    /// `Awake.disable.<feature>` from Snaptic's persistent domain only (N14); unkillable features ignore them. Also
    /// read by HistoryController for a launch with `Modules.disable.awake` (security S3-1).
    static func readKillSwitches() -> Set<AwakeFeature> {
        KillSwitches.read(UserDefaults.standard.persistentDomain(forName: ConfigStore<AwakeConfig>.persistentDomainName),
                          prefix: "Awake")
    }

    /// Wall, continuous (CLOCK_MONOTONIC_RAW, counts sleep) and boot session (N2).
    static func clockNow() -> ClockNow {
        let continuous = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9
        return ClockNow(wall: Date().timeIntervalSince1970, continuous: continuous, bootSession: bootSession())
    }

    /// The boot session can't change within a process: read once (review code F7), retried only while unreadable.
    private static var cachedBootSession: String?

    private static func bootSession() -> String {
        if let cached = cachedBootSession { return cached }
        var size = 0
        sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0)
        var boot = ""
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 { boot = String(cString: buffer) }
        }
        if !boot.isEmpty { cachedBootSession = boot }
        return boot
    }
}
