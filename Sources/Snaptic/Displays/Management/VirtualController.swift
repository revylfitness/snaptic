import AppKit
import SnapticKit
import SnapticShims

/// Virtual screens: specs, connect/disconnect, bulk actions, associations through the
/// ConnectPlanner, recipes, disconnect on lock (PLAN §9.2–§9.4, R5.6).
@MainActor final class VirtualController: DisplayFeatureController, PanicParticipant, SessionParticipant, DiagnosticsContributor {
    static var id: DisplayControllerID { .virtual }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var menu: VirtualMenuItems?
    /// Screens whose HiDPI check failed: recreated with backing for the initial mode only.
    private var limited: Set<StableID> = []
    /// Screens shut down for a locked/switched-out session, recreated on resume.
    private var pausedScreens: Set<StableID> = []
    private var stoppedAfterFailures = false
    private(set) var lastError: String?
    private var busy: Set<StableID> = []

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        guard VirtualHostsService.isAvailable else { return .unavailable(L("Virtual displays aren't available on this Mac")) }
        if feature == .hdrVirtual && !SNVirtualDisplayHDR.supported {
            return .unavailable(L("HDR virtual modes aren't supported on this macOS version"))
        }
        return .available
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        stoppedAfterFailures = false
        let items = VirtualMenuItems(context: context)
        items.controller = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.registerPanic(self, lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Virtual screens"), lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        context.virtualHosts.addExitListener(lifetime: lifetime) { [weak self] id, unexpected in
            self?.hostExited(id, unexpected: unexpected)
        }
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        context?.requestMenuRebuild()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        guard old.virtualScreens != new.virtualScreens, let ctx = context else { return }
        // Removed screens go away.
        let ids = Set(new.virtualScreens.screens.map(\.id))
        for s in old.virtualScreens.screens where !ids.contains(s.id) { ctx.virtualHosts.destroyNow(specID: s.id) }
        ctx.requestMenuRebuild()
    }

    /// Shuts down this controller's hosts (Smart HiDPI hosts belong to their own controller).
    func stop() {
        if let ctx = context {
            for s in ctx.config.value.virtualScreens.screens { ctx.virtualHosts.destroyNow(specID: s.id) }
        }
        menu = nil
        lifetime = nil
        context = nil
        effective = []
        busy = []
    }

    // MARK: Model

    var screens: [VirtualScreenSpec] { context?.config.value.virtualScreens.screens ?? [] }

    func screen(_ id: StableID) -> VirtualScreenSpec? { context?.config.value.virtualScreens.screen(id) }

    func isLive(_ id: StableID) -> Bool { context?.virtualHosts.isLive(id) ?? false }

    func displayID(_ id: StableID) -> UInt32? { context?.virtualHosts.liveDisplays[id] }

    func isBusy(_ id: StableID) -> Bool { busy.contains(id) }

    @discardableResult
    func add(_ spec: VirtualScreenSpec) -> Bool {
        guard let ctx = context else { return false }
        guard ctx.config.value.virtualScreens.screens.count < VirtualConfig.maxScreens else {
            ctx.toasts.show(L("You can create up to 8 virtual screens"), lifetime: lifetime)
            return false
        }
        var s = spec.sanitized(soc: ManagedHardware.soc)
        if !effective.contains(.hdrVirtual) { s.hdr = false }
        ctx.config.value.virtualScreens.screens.append(s)
        return true
    }

    func addRecipe(_ kind: RecipeKind, target: DisplayKey? = nil) {
        guard let ctx = context else { return }
        var aspect: (width: Int, height: Int)?
        if let target, let d = ManagedDisplays.info(ctx, key: target), let m = d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref {
            aspect = (m.pixelWidth, m.pixelHeight)
        }
        if add(Recipes.spec(for: kind, soc: ManagedHardware.soc, target: target, targetAspect: aspect)), kind == .recording {
            ctx.toasts.show(L("Recording screen created. Set up its picture-in-picture view on the PIP page."), lifetime: lifetime)
        }
    }

    /// Edits keep the id; a live screen whose identity or size changed reconnects.
    func update(_ spec: VirtualScreenSpec) {
        guard let ctx = context, let i = ctx.config.value.virtualScreens.screens.firstIndex(where: { $0.id == spec.id }) else { return }
        var s = spec.sanitized(soc: ManagedHardware.soc)
        if !effective.contains(.hdrVirtual) { s.hdr = false }
        let old = ctx.config.value.virtualScreens.screens[i]
        ctx.config.value.virtualScreens.screens[i] = s
        if isLive(s.id) && (old.modes != s.modes || old.hiDPI != s.hiDPI || old.sizeInches != s.sizeInches || old.name != s.name
                            || old.aspectWidth != s.aspectWidth || old.aspectHeight != s.aspectHeight || old.hdr != s.hdr) {
            let id = s.id
            lifetime?.spawn { [weak self] in
                await self?.disconnect(id)
                await self?.connect(id)
            }
        }
    }

    func remove(_ id: StableID) {
        guard let ctx = context else { return }
        ctx.virtualHosts.destroyNow(specID: id)
        ctx.config.value.virtualScreens.screens.removeAll { $0.id == id }
        ctx.config.value.virtualScreens.connected[id] = nil
    }

    // MARK: Connect / disconnect

    /// User connect (or a layout). Remembers the choice for recreate-on-launch.
    func connect(_ id: StableID) async {
        guard let ctx = context else { return }
        ctx.config.value.virtualScreens.connected[id] = true
        stoppedAfterFailures = false
        await create(id, automatic: false)
    }

    /// The planner's step 2 (associations, recreate on launch, after resume).
    func connectAutomatically(_ id: StableID) async {
        guard let ctx = context, !stoppedAfterFailures, !managementAutomationPaused(ctx) else { return }
        if ctx.virtualHosts.recentFailures >= 3 {
            stoppedAfterFailures = true
            ctx.toasts.show(L("Virtual display failed to start"), lifetime: lifetime)
            return
        }
        await create(id, automatic: true)
    }

    private func create(_ id: StableID, automatic: Bool) async {
        guard let ctx = context, effective.contains(.virtualScreens), let spec = screen(id), !isLive(id), !busy.contains(id),
              let initial = spec.initialMode else { return }
        busy.insert(id)
        defer { busy.remove(id); context?.requestMenuRebuild() }
        ctx.virtualHosts.setHeadless(id, spec.headlessPrimary)
        do {
            var displayID = try await ctx.virtualHosts.create(spec: spec, initialMode: initial, limitToInitial: limited.contains(id))
            _ = await ctx.virtualHosts.waitUntilOnline(displayID)
            // R5.6: a HiDPI screen must be backed 2×; otherwise recreate with the initial mode's backing.
            if spec.hiDPI && initial.hiDPI && !limited.contains(id), let m = ManagedModes.current(for: displayID),
               !VirtualHostProtocol.hiDPIVerified(requested: initial, pixelWidth: m.ref.pixelWidth, pointWidth: m.ref.pointWidth) {
                limited.insert(id)
                await ctx.virtualHosts.destroy(specID: id)
                displayID = try await ctx.virtualHosts.create(spec: spec, initialMode: initial, limitToInitial: true)
                _ = await ctx.virtualHosts.waitUntilOnline(displayID)
            }
            let extra = spec.modesLimited(toInitial: limited.contains(id))
            if extra.count > 1 { try? await ctx.virtualHosts.setModes(extra, for: id) }
            lastError = nil
            await place(spec, displayID: displayID, ctx: ctx)
            EventLog.shared.record(.virtualDisplay, automatic ? "Virtual screen connected automatically" : "Virtual screen connected")
        } catch {
            let message = (error as? VirtualHostsService.HostError)?.message ?? L("Virtual display failed to start")
            lastError = message
            if !automatic { ctx.toasts.show(message, lifetime: lifetime) }
        }
    }

    private func place(_ spec: VirtualScreenSpec, displayID: UInt32, ctx: DisplaysContext) async {
        guard spec.placement == .belowRightOfMain,
              let main = ctx.registry.displays.first(where: \.isMain), main.desktopID != displayID else { return }
        let b = CGDisplayBounds(displayID)
        let o = ArrangementMath.belowRightOfMain(width: Int(b.width), height: Int(b.height), main: ManagedDisplays.rect(main))
        _ = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Place virtual screen"), risk: .low,
                                                                  changes: [.origin(displayID, x: o.x, y: o.y)], finalScope: .forSession,
                                                                  automatic: true))
    }

    func disconnect(_ id: StableID) async {
        guard let ctx = context else { return }
        ctx.config.value.virtualScreens.connected[id] = false
        // Un-mirror first if a physical display mirrors it.
        if let vid = displayID(id) {
            let mirrors = ctx.registry.displays.filter { $0.hardwareID.mirrorSource == vid || $0.mirrorOf == vid }
            if !mirrors.isEmpty {
                _ = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Stop mirroring"), risk: .low,
                                                                          changes: mirrors.map { DisplayChange.mirror($0.hardwareID, of: nil) },
                                                                          finalScope: .forSession))
            }
        }
        await ctx.virtualHosts.destroy(specID: id)
        ctx.requestMenuRebuild()
    }

    func toggle(_ id: StableID) {
        let live = isLive(id)
        lifetime?.spawn { [weak self] in
            if live { await self?.disconnect(id) } else { await self?.connect(id) }
        }
    }

    // MARK: Bulk

    func connectAll() { lifetime?.spawn { [weak self] in for s in self?.screens ?? [] { await self?.connect(s.id) } } }
    func disconnectAll() { lifetime?.spawn { [weak self] in for s in self?.screens ?? [] { await self?.disconnect(s.id) } } }

    func reconnectAll() {
        let live = screens.filter { isLive($0.id) }.map(\.id)
        lifetime?.spawn { [weak self] in
            for id in live { await self?.disconnect(id) }
            for id in live { await self?.connect(id) }
        }
    }

    func discardAll() {
        for s in screens { remove(s.id) }
    }

    func disassociateAll() {
        guard let ctx = context else { return }
        for i in ctx.config.value.virtualScreens.screens.indices {
            ctx.config.value.virtualScreens.screens[i].associations = []
        }
    }

    // MARK: Prompts (never unattended, R5.2)

    func promptMirror(_ id: StableID, onto target: DisplayKey) {
        guard let ctx = context, let spec = screen(id), let t = ManagedDisplays.info(ctx, key: target) else { return }
        ctx.toasts.show(L("Mirror '\(spec.name)' onto \(t.name)?"), action: ToastAction(title: L("Mirror")) { [weak self] in
            guard let self, let ctx = self.context, let lifetime = self.lifetime, let vid = self.displayID(id),
                  let t = ManagedDisplays.info(ctx, key: target) else { return }
            ManagedTransactions.submit(ctx, TransactionRequest(label: L("Mirror virtual screen"), risk: .trial,
                                                               changes: [.mirror(t.hardwareID, of: vid)], finalScope: .forSession),
                                       lifetime: lifetime)
        }, lifetime: lifetime)
    }

    func promptStream(_ id: StableID, onto target: DisplayKey, flipped: Bool) {
        guard let ctx = context, let spec = screen(id), let t = ManagedDisplays.info(ctx, key: target) else { return }
        let text = flipped ? L("Stream '\(spec.name)' flipped onto \(t.name)?") : L("Stream '\(spec.name)' onto \(t.name)?")
        ctx.toasts.show(text, action: ToastAction(title: L("Set Up…")) { [weak self] in
            self?.context?.openSettings("displays.pip")
        }, lifetime: lifetime)
    }

    // MARK: ConnectPlanner (step 2)

    func contribute(to inputs: inout ConnectInputs) {
        guard let ctx = context, effective.contains(.virtualScreens) else { return }
        let config = ctx.config.value.virtualScreens
        for s in config.screens {
            var wants = config.connected[s.id] ?? false
            if inputs.trigger == .launch && !s.recreateOnLaunch { wants = false }
            if pausedScreens.contains(s.id) { wants = true }
            inputs.virtualScreens.append(PlanVirtualScreen(specID: s.id, associations: s.associations, wantsConnected: wants))
            guard let vid = displayID(s.id) else { continue }
            let presented = ctx.registry.displays.first { $0.desktopID == vid }
            let bound = ctx.registry.displays.first { $0.hardwareID != vid && $0.hardwareID.mirrorSource == vid }?.key
            inputs.hosts.append(PlanHost(specID: s.id, purpose: .virtualScreen, isLive: true, isMain: presented?.isMain ?? false,
                                         boundTo: bound, identityMatches: true, physicalMissingSeconds: nil))
        }
    }

    // MARK: Session / panic / host exits

    /// Non-headless hosts shut down when the session resigns (un-mirror first; §4.9).
    func sessionDidPause() {
        for s in screens where isLive(s.id) && !s.headlessPrimary {
            pausedScreens.insert(s.id)
            let id = s.id
            lifetime?.spawn { [weak self] in await self?.shutdownForSession(id) }
        }
    }

    private func shutdownForSession(_ id: StableID) async {
        guard let ctx = context else { return }
        if let vid = displayID(id) {
            let mirrors = ctx.registry.displays.filter { $0.hardwareID.mirrorSource == vid }
            if !mirrors.isEmpty {
                _ = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Stop mirroring"), risk: .low,
                                                                          changes: mirrors.map { DisplayChange.mirror($0.hardwareID, of: nil) },
                                                                          finalScope: .forSession, automatic: true))
            }
        }
        await ctx.virtualHosts.destroy(specID: id)
    }

    /// The planner recreates paused screens on resume (DisplaysModule triggers it).
    func sessionDidResume() {
        let ids = pausedScreens
        pausedScreens = []
        guard let ctx = context, !ids.isEmpty else { return }
        for id in ids { ctx.config.value.virtualScreens.connected[id] = true }
    }

    /// Virtual mirrors shut down; others stay (a headless screen may be all the user has).
    func panicRestore() {
        guard let ctx = context else { return }
        for s in screens {
            guard let vid = displayID(s.id), ctx.registry.displays.contains(where: { $0.hardwareID != vid && $0.hardwareID.mirrorSource == vid }) else { continue }
            ctx.virtualHosts.destroyNow(specID: s.id)
        }
    }

    private func hostExited(_ id: StableID, unexpected: Bool) {
        guard let ctx = context, screen(id) != nil, unexpected else { return }
        if ctx.virtualHosts.recentFailures >= 3 {
            stoppedAfterFailures = true
            ctx.toasts.show(L("Virtual display failed to start"), lifetime: lifetime)
        } else {
            ctx.connectPlanner.trigger(.reconfigure)
        }
        ctx.requestMenuRebuild()
    }

    // MARK: Actions / CLI

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        for n in 1...VirtualConfig.maxScreens {
            ctx.actions.register(Action(id: .dVirtualToggle(n), title: L("Toggle Virtual Screen \(n)"), feature: .virtualScreens,
                                        cliAllowed: true) { [weak self] _ in
                guard let self, self.screens.indices.contains(n - 1) else { return }
                self.toggle(self.screens[n - 1].id)
            }, lifetime: lifetime)
        }
    }

    private func find(_ selector: String) -> VirtualScreenSpec? {
        if let n = Int(selector), screens.indices.contains(n - 1) { return screens[n - 1] }
        if let id = StableID(rawValue: selector) { return screen(id) }
        let lower = selector.lowercased()
        return screens.first { $0.name.lowercased() == lower } ?? screens.first { $0.name.lowercased().hasPrefix(lower) }
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("virtual", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("virtual list | connect <name> | disconnect <name>"), lifetime: lifetime) { [weak self] req in
            guard let self, self.effective.contains(.virtualScreens) else {
                return .failure(ManagementExit.unavailable, L("Virtual screens are off"))
            }
            let a = req.arguments
            switch a.first?.lowercased() {
            case "list", nil:
                return .ok(self.screens.enumerated().map { pair -> String in
                    let s = pair.element
                    return "\(pair.offset + 1). \(s.name) \(s.aspectWidth):\(s.aspectHeight)" + (self.isLive(s.id) ? " [connected]" : "")
                }.joined(separator: "\n"))
            case "connect", "disconnect":
                guard a.count > 1, let s = self.find(a.dropFirst().joined(separator: " ")) else {
                    return .failure(ManagementExit.notFound, L("No such virtual screen"))
                }
                if a[0].lowercased() == "connect" {
                    await self.connect(s.id)
                    return self.isLive(s.id) ? .ok(s.name) : .failure(ManagementExit.refused, self.lastError ?? "")
                }
                await self.disconnect(s.id)
                return .ok(s.name)
            default:
                return .failure(ManagementExit.usage, L("Usage: virtual list | connect <name> | disconnect <name>"))
            }
        }
    }

    func diagnostics() -> [(String, String)] {
        [(L("Virtual screens"), String(screens.count)),
         (L("Connected"), String(screens.filter { isLive($0.id) }.count)),
         (L("HiDPI fallbacks"), String(limited.count)),
         (L("Stopped after failures"), stoppedAfterFailures ? L("Yes") : L("No")),
         (L("Last error"), lastError ?? L("none"))]
    }
}

/// HDR support probe (static fact for availability).
enum SNVirtualDisplayHDR {
    static var supported: Bool { SNVirtualDisplay.supportsHDRModes() }
}
