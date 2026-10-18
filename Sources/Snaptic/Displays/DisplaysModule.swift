import AppKit
import Combine
import SwiftUI
import SnapticKit

/// The Displays module (lead): resolves the effective feature set, activates the
/// services it needs in dependency order, and starts one controller per
/// DisplayControllerID that has effective features (PLAN §3.6, R5).
@MainActor final class DisplaysModule: SnapticModule {
    let id: ModuleID = .displays
    let title = L("Displays")
    let symbolName = "display.2"
    let summary = L("Brightness, resolution, DDC, virtual screens and more, for every display.")
    private(set) var state: ModuleState = .stopped

    /// Before start(), what the saved settings would turn on (for the host's launch request).
    var requiredPermissions: Set<Permission> {
        let set = context == nil ? resolveEffective(config.value) : effective
        return set.reduce(into: Set<Permission>()) { $0.formUnion(FeatureGraph.permissions($1)) }
    }

    let config: ConfigStore<DisplaysConfig>
    let runtime = DisplaysRuntimeState()
    private(set) lazy var pageEnvironment = DisplaysPageEnvironment(
        config: config, runtime: runtime, enableFeature: { [weak self] in self?.enable($0) })

    /// Every menu contributor type (lead-owned list; `--selftest-controls` checks the union of their
    /// `menuItemIDs` covers every frozen 0.2 menu id, R5-13). Add a type here when you add a contributor.
    static let menuContributorTypes: [any DisplayMenuContributor.Type] = [
        PanicCoordinator.self, AutomationMenuItems.self, OverviewMenuItems.self, VirtualMenuItems.self,
        LayoutsMenuItems.self, ManagementMenuItems.self, ResolutionMenuItems.self, DDCMenuItems.self,
        BrightnessMenuItems.self, ColorMenuItems.self, PIPMenuItems.self,
    ]

    /// Every controller class; the order is the start order (stop runs in reverse).
    static let controllerTypes: [any DisplayFeatureController.Type] = [
        OverviewController.self, DiagnosticsController.self,
        ResolutionController.self,
        BrightnessController.self, XDRController.self, SyncController.self,
        ColorController.self, SystemColorsController.self,
        DDCController.self, KeysController.self, OSDController.self,
        ArrangementController.self, PanelPropsController.self, PowerController.self,
        ProtectionController.self, LayoutsController.self,
        VirtualController.self, SmartHiDPIController.self,
        PIPController.self, MenuBarOverlaysController.self, AutomationController.self,
    ]

    private let controllers: [DisplayControllerID: any DisplayFeatureController]
    /// Owned here so private symbols are registered once, before any availability check.
    private let privateAPI = PrivateDisplayAPI()
    private var serviceLifetimes: [DisplayServiceID: Lifetime] = [:]
    private var paused: Set<DisplayFeature> = []
    private var context: DisplaysContext?
    private var moduleContext: ModuleContext?
    private var controllerLifetimes: [DisplayControllerID: Lifetime] = [:]
    private var controllerFeatures: [DisplayControllerID: Set<DisplayFeature>] = [:]
    private var activeServices: Set<DisplayServiceID> = []
    private var effective: Set<DisplayFeature> = []
    private var killSwitches: Set<DisplayFeature> = []
    private var unavailable: Set<DisplayFeature> = []
    private var lastConfig: DisplaysConfig
    private var sinks: [AnyCancellable] = []
    private var observers: [NSObjectProtocol] = []

    /// The host owns the store for the app's lifetime (R5.1).
    init(config: ConfigStore<DisplaysConfig>) {
        self.config = config
        lastConfig = config.value
        var map: [DisplayControllerID: any DisplayFeatureController] = [:]
        for type in Self.controllerTypes {
            precondition(map[type.id] == nil, "Two controllers claim \(type.id.rawValue)")
            map[type.id] = type.init()
        }
        precondition(map.count == DisplayControllerID.allCases.count, "Every DisplayControllerID needs a controller")
        controllers = map
        var symbols = Self.controllerTypes.flatMap { $0.privateSymbols }
        symbols += Self.serviceTypes.flatMap { $0.privateSymbols }
        privateAPI.register(symbols)
    }

    private static let serviceTypes: [any DisplayServiceLifecycle.Type] = [
        DisplayRegistry.self, SessionGate.self, DisplayGuardClient.self, DisplayTransactionQueue.self,
        AppleBrightnessIO.self, DDCService.self, GammaService.self, OverlayService.self, EDRBoost.self,
        BrightnessService.self, OSDPresenter.self, ColorSyncService.self, MonitorPanelService.self,
        MediaKeyService.self, VirtualHostsService.self, CaptureService.self, SpawnerService.self,
    ]

    // MARK: SnapticModule

    func start(_ moduleContext: ModuleContext) {
        guard context == nil else { return }
        self.moduleContext = moduleContext
        killSwitches = Self.readKillSwitches()
        let lifetime = moduleContext.lifetime.child()
        let ctx = DisplaysContext(module: moduleContext, privateAPI: privateAPI, config: config, runtime: runtime,
                                  lifetime: lifetime)
        context = ctx
        state = .running
        runtime.moduleState = .running
        computeAvailability(ctx)

        ctx.panic.onLatchChanged = { [weak self] in
            guard let self, let ctx = self.context else { return }
            self.runtime.isPanicLatched = ctx.panic.isLatched
            self.reresolve()
            // Internally gated work (layouts, virtual recreation…) catches up on Resume.
            if !ctx.panic.isLatched { ctx.connectPlanner.trigger(.reconfigure) }
        }
        ctx.menus.onChange = { [weak self] in self?.moduleContext?.requestMenuRebuild() }
        // A permission granted or revoked while running can change what's available.
        ctx.permissions.observe(lifetime: lifetime) { [weak self] _, _ in
            guard let self, let ctx = self.context else { return }
            self.computeAvailability(ctx)
            self.reresolve()
        }
        ctx.actions.isEffective = { [weak self] feature in self?.effective.contains(feature) ?? false }
        ctx.actions.onRefused = { [weak ctx] action in
            ctx?.toasts.show(L("“\(action.title)” isn't available right now: its feature is off."))
        }
        paused = ctx.otherApps.pausedDisplayFeatures
        ctx.otherApps.onChange = { [weak self] in
            guard let self, let ctx = self.context else { return }
            self.paused = ctx.otherApps.pausedDisplayFeatures
            self.reresolve()
        }
        ctx.panic.start(ctx, lifetime: lifetime)
        ctx.sessionGate.onStateChange = { [weak self] isOpen in self?.sessionChanged(isOpen: isOpen) }

        lastConfig = config.value
        apply(resolveEffective(lastConfig))

        ctx.connectPlanner.start(ctx, lifetime: lifetime)
        ctx.connectPlanner.trigger(.launch)
        observeSystem(ctx)
        pageEnvironment.setContext(ctx)

        // @Published fires in willSet: hop once so `config.value` is the new value.
        config.$value
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.configChanged() } }
            .store(in: &sinks)
        EventLog.shared.record(.modules, "Displays started with \(effective.count) features")
    }

    func stop() {
        guard let ctx = context else { return }
        sinks.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        pageEnvironment.setContext(nil)

        ctx.connectPlanner.stop()
        for type in Self.controllerTypes.reversed() {
            guard let life = controllerLifetimes[type.id] else { continue }
            controllers[type.id]?.stop()
            life.end()
        }
        controllerLifetimes = [:]
        controllerFeatures = [:]
        ctx.panic.stop()
        ctx.sessionGate.onStateChange = nil
        ctx.panic.onLatchChanged = nil
        ctx.otherApps.onChange = nil
        ctx.menus.onChange = nil
        for service in FeatureGraph.activationOrder.reversed() where activeServices.contains(service) {
            ctx.service(service).deactivate()
            serviceLifetimes[service]?.end()
        }
        activeServices = []
        serviceLifetimes = [:]
        ctx.lifetime.end()
        config.flush()

        context = nil
        effective = []
        runtime.reset()
        runtime.moduleState = .stopped
        state = .stopped
        EventLog.shared.record(.modules, "Displays stopped")
    }

    func menuSection() -> [NSMenuItem] {
        guard let ctx = context else { return [] }
        return DisplaysMenuBuilder(context: ctx).build()
    }

    // Settings root and sub-pages (F's DisplaysPage, §4.3).
    var tint: SettingsTint { DisplaysPage.tint }
    var highlights: [FeatureHighlight] { DisplaysPage.highlights }
    func settingsRoot() -> SettingsRoot { DisplaysPage.settingsRoot(env: pageEnvironment) }
    func settingsDestination(_ route: SettingsRoute) -> AnyView? { DisplaysPage.destination(route, env: pageEnvironment) }

    /// Runs a registered action (quick menu, floating panel, CLI). False if unknown.
    @discardableResult
    func perform(_ id: DisplayActionID, on target: DisplayTarget = .pointer) -> Bool {
        context?.actions.perform(id, on: target) ?? false
    }

    // MARK: Features

    /// Turns a feature on together with everything it requires.
    func enable(_ feature: DisplayFeature) {
        let available = Set(DisplayFeature.allCases).subtracting(unavailable).subtracting(killSwitches)
        var value = config.value
        for (f, on) in FeatureGraph.enabling(feature, raw: value.rawFeatures, available: available) {
            value.features[f] = on
        }
        config.value = value
    }

    func disable(_ feature: DisplayFeature) {
        guard FeatureGraph.spec(feature).defaultState != .always else { return }
        config.value.features[feature] = false
    }

    private func resolveEffective(_ value: DisplaysConfig) -> Set<DisplayFeature> {
        FeatureGraph.resolve(raw: value.rawFeatures, killSwitches: killSwitches,
                             safeMode: context?.safeMode.isActive ?? false,
                             unavailable: unavailable, panicLatch: context?.panic.isLatched ?? false,
                             paused: paused)
    }

    private func computeAvailability(_ ctx: DisplaysContext) {
        var table: [DisplayFeature: FeatureAvailability] = [:]
        var missing: Set<DisplayFeature> = []
        let privateMissing = ctx.privateAPI.unavailableFeatures()
        for feature in DisplayFeature.allCases {
            var a = controllers[FeatureGraph.controller(of: feature)]?.availability(of: feature, context: ctx)
                ?? .unavailable(L("Not available on this Mac"))
            if a.isAvailable, let reason = privateMissing[feature] { a = .unavailable(reason) }
            if killSwitches.contains(feature) { a = .unavailable(L("Turned off by a defaults setting")) }
            table[feature] = a
            if !a.isAvailable { missing.insert(feature) }
        }
        unavailable = missing
        runtime.availability = table
    }

    private func reresolve() {
        guard context != nil else { return }
        apply(resolveEffective(config.value))
    }

    private func configChanged() {
        guard context != nil else { return }
        let new = config.value
        let old = lastConfig
        guard new != old else { return }
        lastConfig = new
        let before = controllerLifetimes
        if new.rawFeatures != old.rawFeatures { apply(resolveEffective(new)) }
        // Step 5: controllers that were already running hear about the change; newly
        // started ones read the new value in start(). 0.3 §4.5: only those observing a changed section.
        let changed = DisplaysConfig.changedSections(old: old, new: new)
        for type in Self.controllerTypes where before[type.id] != nil && controllerLifetimes[type.id] != nil {
            guard !type.observedSections.isDisjoint(with: changed) else { continue }
            controllers[type.id]?.configDidChange(from: old, to: new)
        }
    }

    /// PLAN §3.6 module apply order.
    private func apply(_ newEffective: Set<DisplayFeature>) {
        guard let ctx = context else { return }
        let old = effective
        effective = newEffective
        runtime.effectiveFeatures = newEffective

        var sets: [DisplayControllerID: Set<DisplayFeature>] = [:]
        for feature in newEffective { sets[FeatureGraph.controller(of: feature), default: []].insert(feature) }

        // 0. Controllers that lose some (not all) features let go of them before any
        //    service they used is deactivated.
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
        // 2. Deactivate services no longer required, in reverse order.
        let required = FeatureGraph.requiredServices(effective: newEffective)
        for service in FeatureGraph.activationOrder.reversed()
        where activeServices.contains(service) && !required.contains(service) {
            ctx.service(service).deactivate()
            serviceLifetimes[service]?.end()
            serviceLifetimes[service] = nil
            activeServices.remove(service)
        }
        // 3. Activate newly required services, in order.
        for service in FeatureGraph.activationOrder where required.contains(service) && !activeServices.contains(service) {
            let life = ctx.lifetime.child()
            serviceLifetimes[service] = life
            ctx.service(service).activate(ctx, lifetime: life)
            activeServices.insert(service)
        }
        // 4. Start new controllers; 5. notify the rest.
        for type in Self.controllerTypes {
            guard let set = sets[type.id], let controller = controllers[type.id] else { continue }
            if controllerLifetimes[type.id] == nil {
                let life = ctx.lifetime.child()
                controllerLifetimes[type.id] = life
                controllerFeatures[type.id] = set
                controller.start(ctx, lifetime: life, effective: set)
            } else if controllerFeatures[type.id] != set {
                controllerFeatures[type.id] = set
                controller.effectiveFeaturesDidChange(set)
            }
        }
        if old != newEffective {
            EventLog.shared.record(.modules, "Displays features: \(newEffective.count) effective")
            moduleContext?.requestMenuRebuild()
            if Set(old.map { FeatureGraph.spec($0).page }) != Set(newEffective.map { FeatureGraph.spec($0).page }) {
                moduleContext?.requestSettingsRefresh()
            }
        }
    }

    // MARK: System events

    private func observeSystem(_ ctx: DisplaysContext) {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.context?.connectPlanner.trigger(.wake) }
        })
        runtime.displays = ctx.registry.displays
        ctx.registry.changes
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in
                MainActor.assumeIsolated {
                    guard let self, let ctx = self.context else { return }
                    self.runtime.displays = displays
                    self.runtime.prune(keeping: Set(displays.map(\.key)))
                    ctx.connectPlanner.trigger(.reconfigure)
                    self.moduleContext?.requestMenuRebuild()
                }
            }
            .store(in: &sinks)
    }

    private func sessionChanged(isOpen: Bool) {
        guard let ctx = context else { return }
        for participant in ctx.sessionParticipants {
            if isOpen { participant.sessionDidResume() } else { participant.sessionDidPause() }
        }
        if isOpen { ctx.connectPlanner.trigger(.sessionResume) }
    }

    /// Persistent-domain Bool keys `Displays.disable.<feature>`, read once per start.
    private static func readKillSwitches() -> Set<DisplayFeature> {
        KillSwitches.read(UserDefaults.standard.persistentDomain(forName: ConfigStore<DisplaysConfig>.persistentDomainName),
                          prefix: "Displays")
    }
}
