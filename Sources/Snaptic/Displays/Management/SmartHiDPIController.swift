import AppKit
import SnapticKit
import SnapticShims

/// Smart HiDPI (PLAN §9.5, R5.6): a 2× virtual display per physical panel, mirrored onto
/// it. First enable is a trial; kept pairs are re-established by the ConnectPlanner
/// (`restore`), rebinding the mirror instead of recreating when the panel returns.
@MainActor final class SmartHiDPIController: DisplayFeatureController, PanicParticipant, SessionParticipant,
    DiagnosticsContributor {
    static var id: DisplayControllerID { .smartHiDPI }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Pairs live in `virtualScreens.smartHiDPI` (0.3 §4.5).
    static var observedSections: Set<DisplaysConfigSection> { [.virtualScreens] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var missingSince: [StableID: Double] = [:]
    private var busy: Set<DisplayKey> = []
    private var sessionPaused = false
    private(set) var lastError: String? {
        didSet { if lastError != oldValue { context?.runtime.revision(Self.id).bump() } }
    }
    /// Held here: the menu registry keeps contributors weakly.
    private var menu: ManagementMenuItems?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        VirtualHostsService.isAvailable ? .available : .unavailable(L("Virtual displays aren’t available on this Mac"))
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        let items = ManagementMenuItems(context: context)
        items.smartHiDPI = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.registerPanic(self, lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        context.diagnostics.register(self, section: ManagementText.sharperTextSection, lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        context.virtualHosts.addExitListener(lifetime: lifetime) { [weak self] id, unexpected in
            guard let self, self.owns(id) else { return }
            self.changed()
            guard unexpected else { return }
            // FIXES-R3 5: no respawn once the hosts speak another protocol (restart needed).
            guard self.context?.virtualHosts.restartRequired != true else { return }
            self.context?.connectPlanner.trigger(.reconfigure)
        }
        // Only a session resign (fast user switching) shuts pairs down; lock and sleep keep them.
        context.sessionGate.observeEvents(lifetime: lifetime) { [weak self] event in
            if event == .resignedActive { self?.shutdownForSession() }
        }
        context.actions.register(Action(id: .dSmartHiDPIToggle, title: ManagementText.sharperTextOnOff, feature: .smartHiDPI,
                                        cliAllowed: true) { [weak self] t in
            guard let self, let ctx = self.context else { return }
            for d in ManagedDisplays.resolve(ctx, t) { self.toggle(d.key) }
        }, lifetime: lifetime)
        // Off-only from the CLI (R5.4).
        context.commands.register("smart-hidpi", policy: .low, offOnly: true, cliAllowed: true, summary: L("smart-hidpi off <display>|all"),
                                  lifetime: lifetime) { [weak self] req, _ in
            guard let self else { return .failure(ControlExit.unavailable, "") }
            let a = req.arguments
            guard a.first?.lowercased() == "off" else { return .failure(ControlExit.refused, L("Only “off” is allowed")) }
            return await self.turnOffCommand(a.count > 1 ? a[1] : "all", requireOn: false)
        }
        // R5.4 exposure name `toggle smartHiDPI` (verbs match case-insensitively), plus the
        // dashed spelling; off-only: turns Smart HiDPI off on the given (or every) display.
        for verb in ["toggle smarthidpi", "toggle smart-hidpi"] {
            context.commands.register(verb, policy: .low, offOnly: true, cliAllowed: true,
                                      summary: L("toggle smartHiDPI [<display>|all]: turn sharper text off"),
                                      lifetime: lifetime) { [weak self] req, _ in
                guard let self else { return .failure(ControlExit.unavailable, "") }
                let sel = req.arguments.first.map { $0.lowercased() == "off" ? (req.arguments.dropFirst().first ?? "all") : $0 } ?? "all"
                return await self.turnOffCommand(sel, requireOn: true)
            }
        }
    }

    /// Turns Smart HiDPI off on the selected displays (CLI; never on).
    private func turnOffCommand(_ selector: String, requireOn: Bool) async -> ControlResponse {
        guard let ctx = context else { return .failure(ControlExit.unavailable, "") }
        let keys: [DisplayKey]
        if selector.lowercased() == "all" {
            keys = Array(pairs.keys)
        } else {
            let r = ManagedDisplays.cliKeys(ctx, selector)
            if let error = r.error { return error }
            keys = r.keys
        }
        let on = keys.filter { pairs[$0] != nil }
        if on.isEmpty {
            return requireOn ? .failure(ControlExit.refused, ManagementText.sharperTextOnlyOff)
                             : .ok(ManagementText.sharperTextAlreadyOff)
        }
        for k in on { await disable(k) }
        return .ok()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        changed()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.virtualScreens.smartHiDPI != new.virtualScreens.smartHiDPI { changed() }
    }

    /// Page-visible state changed (pairs live or busy, errors): one revision bump and a menu rebuild.
    private func changed() {
        context?.runtime.revision(Self.id).bump()
        context?.requestMenuRebuild()
    }

    private func setBusy(_ key: DisplayKey, _ on: Bool) {
        let changedState = on ? busy.insert(key).inserted : busy.remove(key) != nil
        if changedState { changed() }
    }

    func stop() {
        if let ctx = context { for p in pairs.values { ctx.virtualHosts.destroyNow(specID: p.specID) } }
        missingSince = [:]
        busy = []
        menu = nil
        lifetime = nil
        context = nil
        effective = []
    }

    // MARK: Model

    var pairs: [DisplayKey: SmartHiDPIPair] { context?.config.value.virtualScreens.smartHiDPI.values ?? [:] }

    func owns(_ specID: StableID) -> Bool { pairs.values.contains { $0.specID == specID } }

    func isActive(_ key: DisplayKey) -> Bool {
        guard let p = pairs[key] else { return false }
        return context?.virtualHosts.isLive(p.specID) ?? false
    }

    func isBusy(_ key: DisplayKey) -> Bool { busy.contains(key) }

    private func setPair(_ key: DisplayKey, _ pair: SmartHiDPIPair?) {
        guard let ctx = context else { return }
        ctx.config.value.virtualScreens.smartHiDPI[key] = pair
    }

    /// The physical panel as the registry presents it (with or without the pair).
    private func physical(_ key: DisplayKey) -> DisplayInfo? {
        guard let ctx = context else { return nil }
        let vid = pairs[key].flatMap { ctx.virtualHosts.liveDisplays[$0.specID] }
        return ctx.registry.displays.first { $0.key == key && $0.hardwareID != vid }
    }

    /// Native pixel size of the panel (from its own mode list).
    private func nativePixels(_ d: DisplayInfo) -> (width: Int, height: Int, refresh: Int)? {
        guard let n = ManagedModes.native(in: ManagedModes.modes(for: d.hardwareID)) else { return nil }
        return (n.ref.pixelWidth, n.ref.pixelHeight, n.ref.refreshMilliHz)
    }

    /// 50–150 % of the native size, as HiDPI points within the chip limits (§9.5).
    func modeOptions(_ key: DisplayKey) -> [VirtualMode] {
        guard let d = physical(key) ?? context.flatMap({ ManagedDisplays.info($0, key: key) }), let n = nativePixels(d) else { return [] }
        let limit = SoCCaps.maxHiDPIPointDimension(ManagedHardware.soc)
        // Panels at 75 Hz and above are offered their native rate (GPU cost shown in Settings).
        let hz = n.refresh >= 75_000 ? Int((Double(n.refresh) / 1000).rounded()) * 1000 : 60_000
        var result: [VirtualMode] = []
        for percent in stride(from: 50, through: 150, by: 10) {
            var w = n.width * percent / 100
            var h = n.height * percent / 100
            w -= w % 2
            h -= h % 2
            guard w >= VirtualScreenSpec.minModeDimension, h >= VirtualScreenSpec.minModeDimension, w <= limit, h <= limit else { continue }
            let m = VirtualMode(width: w, height: h, hiDPI: true, refreshMilliHz: hz)
            if !result.contains(m) { result.append(m) }
        }
        return result
    }

    /// The option closest to the panel's current UI size.
    private func initialMode(_ key: DisplayKey, options: [VirtualMode]) -> VirtualMode? {
        guard let d = physical(key), let current = d.currentMode?.ref ?? ManagedModes.current(for: d.hardwareID)?.ref else { return options.first }
        return options.min { abs($0.width - current.pointWidth) < abs($1.width - current.pointWidth) }
    }

    private func spec(_ key: DisplayKey, pair: SmartHiDPIPair, options: [VirtualMode]) -> VirtualScreenSpec? {
        guard let d = physical(key), let n = nativePixels(d) else { return nil }
        let aspect = Recipes.reduced((n.width, n.height))
        let wmm = Double(d.physicalSizeMM.width), hmm = Double(d.physicalSizeMM.height)
        let inches = wmm > 10 && hmm > 10 ? (wmm * wmm + hmm * hmm).squareRoot() / 25.4 : 27
        var modes = options
        if let i = modes.firstIndex(of: pair.mode) { modes.swapAt(0, i) } else { modes.insert(pair.mode, at: 0) }
        let hdr = pair.hdr && effective.contains(.smartHiDPI) && (context?.runtime.effectiveFeatures.contains(.hdrVirtual) ?? false)
        return VirtualScreenSpec(id: pair.specID, name: ManagementText.sharperTextDisplayName(d.name), aspectWidth: aspect.width,
                                 aspectHeight: aspect.height, sizeInches: inches, hiDPI: true, modes: modes,
                                 primaries: primaries(d), hdr: hdr)
    }

    /// The panel's primaries, so wide-gamut content isn't clamped to sRGB (§9.5). EDID
    /// chromaticity first (R5.6); without it the virtual keeps macOS's default. The physical
    /// display's ICC profile is deliberately not copied onto the virtual (R5.6).
    private func primaries(_ d: DisplayInfo) -> VirtualPrimaries? {
        guard let ctx = context else { return nil }
        let info = ctx.privateAPI.function(.coreDisplayInfo, as: IORegistryDisplays.InfoDictionaryFn.self)
        guard let edid = IORegistryDisplays.facts(for: d.hardwareID, coreDisplayInfo: info).edid,
              let chroma = EDIDInfo.parse(edid)?.chromaticity else { return nil }
        return VirtualPrimaries(edid: chroma)
    }

    private func serialSeed(_ d: DisplayInfo) -> String {
        let id = ManagedIdentity.identity(hardwareID: d.hardwareID)
        return id.tier1 ?? id.tier2 ?? d.key.rawValue
    }

    /// Creates the host and its display, with the R5.6 HiDPI check and fallback.
    private func createHost(_ key: DisplayKey, pair: SmartHiDPIPair) async throws -> UInt32 {
        guard let ctx = context, let d = physical(key) else { throw VirtualHostsService.HostError.notRunning }
        let options = modeOptions(key)
        guard let spec = spec(key, pair: pair, options: options) else { throw VirtualHostsService.HostError.failed(.invalidRequest) }
        var limited = pair.limitToInitial
        var vid = try await ctx.virtualHosts.create(spec: spec, initialMode: pair.mode, limitToInitial: limited, serialSeed: serialSeed(d))
        _ = await ctx.virtualHosts.waitUntilOnline(vid)
        if !limited, let m = ManagedModes.current(for: vid),
           !VirtualHostProtocol.hiDPIVerified(requested: pair.mode, pixelWidth: m.ref.pixelWidth, pointWidth: m.ref.pointWidth) {
            limited = true
            var updated = pair
            updated.limitToInitial = true
            setPair(key, updated)
            await ctx.virtualHosts.destroy(specID: pair.specID)
            vid = try await ctx.virtualHosts.create(spec: spec, initialMode: pair.mode, limitToInitial: true, serialSeed: serialSeed(d))
            _ = await ctx.virtualHosts.waitUntilOnline(vid)
        }
        let extra = spec.modesLimited(toInitial: limited)
        if extra.count > 1 { try? await ctx.virtualHosts.setModes(extra, for: pair.specID) }
        return vid
    }

    /// The physical panel's own origin and main status (not the presented pair's).
    private func bindChanges(_ key: DisplayKey, virtualID: UInt32) -> [DisplayChange]? {
        guard let d = physical(key) else { return nil }
        let b = CGDisplayBounds(d.hardwareID)
        var changes: [DisplayChange] = [.mirror(d.hardwareID, of: virtualID),
                                        .origin(virtualID, x: Int32(b.origin.x.rounded()), y: Int32(b.origin.y.rounded()))]
        if d.hardwareID.isMain { changes.append(.main(virtualID)) }
        return changes
    }

    /// Tells the registry the pair exists, so it presents one display (B: `virtualFacts`).
    private func markBound(_ key: DisplayKey, specID: StableID) {
        guard let ctx = context, let d = physical(key) else { return }
        ctx.virtualHosts.setPairPhysical(specID, d.hardwareID)
    }

    // MARK: User actions

    func toggle(_ key: DisplayKey) {
        if isActive(key) {
            lifetime?.spawn { [weak self] in await self?.disable(key) }
        } else {
            enable(key)
        }
    }

    /// First enable is a trial; Keep makes the pair "kept" (re-established automatically).
    func enable(_ key: DisplayKey, mode: VirtualMode? = nil) {
        guard let ctx = context, let lifetime, effective.contains(.smartHiDPI), !busy.contains(key) else { return }
        guard let d = physical(key), d.isActive, d.transport == .builtin || d.transport == .wired, d.mirrorOf == nil else {
            ctx.toasts.show(ManagementText.sharperTextNeedsDisplay, lifetime: lifetime)
            return
        }
        let options = modeOptions(key)
        guard let initial = mode ?? initialMode(key, options: options) else {
            ctx.toasts.show(ManagementText.noSharpSize, lifetime: lifetime)
            return
        }
        var pair = pairs[key] ?? SmartHiDPIPair(mode: initial)
        pair.mode = initial
        pair.kept = false
        setPair(key, pair)
        setBusy(key, true)
        ctx.connectPlanner.beginUserChange()
        let specID = pair.specID
        lifetime.spawn { [weak self] in
            guard let self, let ctx = self.context else { return }
            defer { self.setBusy(key, false) }
            do {
                let vid = try await self.createHost(key, pair: pair)
                guard let changes = self.bindChanges(key, virtualID: vid) else {
                    await ctx.virtualHosts.destroy(specID: specID)
                    ctx.connectPlanner.endUserChange(changed: false)
                    return
                }
                let request = TransactionRequest(label: ManagementText.turnOnSharperText, risk: .trial, changes: changes, finalScope: .forSession,
                                                 afterRevert: { [weak self] in await self?.context?.virtualHosts.destroy(specID: specID) })
                let outcome = await ManagedTransactions.run(ctx, request)
                let ok = outcome == .applied || outcome == .kept
                if ok { self.markBound(key, specID: specID) }
                ctx.connectPlanner.endUserChange(changed: ok)
                if ok {
                    if var p = self.pairs[key] {
                        p.kept = true
                        self.setPair(key, p)
                    }
                    self.lastError = nil
                } else {
                    await ctx.virtualHosts.destroy(specID: specID)
                    if let text = ManagedTransactions.message(outcome) { ctx.toasts.show(text, lifetime: self.lifetime) }
                }
            } catch {
                ctx.connectPlanner.endUserChange(changed: false)
                let text = (error as? VirtualHostsService.HostError)?.message ?? L("Virtual display failed to start")
                self.lastError = text
                ctx.toasts.show(text, lifetime: self.lifetime)
            }
        }
    }

    /// Un-mirror, then shut the host down; the pair is forgotten.
    func disable(_ key: DisplayKey) async {
        guard let ctx = context, let pair = pairs[key] else { return }
        setPair(key, nil)
        ctx.virtualHosts.setPairPhysical(pair.specID, nil)
        if let vid = ctx.virtualHosts.liveDisplays[pair.specID] {
            let mirrors = ctx.registry.displays.filter { $0.hardwareID != vid && $0.hardwareID.mirrorSource == vid }
            if !mirrors.isEmpty {
                _ = await ManagedTransactions.run(ctx, TransactionRequest(label: ManagementText.turnOffSharperText, risk: .low,
                                                                          changes: mirrors.map { DisplayChange.mirror($0.hardwareID, of: nil) },
                                                                          finalScope: .forSession))
            }
        }
        await ctx.virtualHosts.destroy(specID: pair.specID)
        changed()
    }

    /// Slider: the virtual's own mode change (low risk when known-good).
    func setMode(_ key: DisplayKey, _ mode: VirtualMode) {
        guard let ctx = context, let lifetime, var pair = pairs[key] else { return }
        pair.mode = mode
        setPair(key, pair)
        guard let vid = ctx.virtualHosts.liveDisplays[pair.specID] else { return }
        guard let ref = ManagedModes.modes(for: vid).map(\.ref).first(where: { $0.pointWidth == mode.width && $0.pointHeight == mode.height && $0.isHiDPI })
        else {
            ctx.toasts.show(ManagementText.sizeNeedsReconnect, action: ToastAction(title: L("Reconnect")) { [weak self] in
                guard let self else { return }
                self.lifetime?.spawn { [weak self] in
                    await self?.disable(key)
                    self?.enable(key, mode: mode)
                }
            }, lifetime: lifetime)
            return
        }
        ctx.connectPlanner.beginUserChange()
        ManagedTransactions.submit(ctx, TransactionRequest(label: ManagementText.changeSharperTextSize, risk: .low, changes: [.mode(vid, ref)]),
                                   lifetime: lifetime) { [weak self] outcome in
            self?.context?.connectPlanner.endUserChange(changed: outcome == .applied || outcome == .kept)
        }
    }

    // MARK: ConnectPlanner (step 2)

    func contribute(to inputs: inout ConnectInputs) {
        guard let ctx = context, effective.contains(.smartHiDPI) else { return }
        let now = managementUptime()
        for (key, pair) in pairs {
            let vid = ctx.virtualHosts.liveDisplays[pair.specID]
            let phys = ctx.registry.displays.first { $0.key == key && $0.hardwareID != vid }
            let present = phys != nil
            if pair.kept {
                let tier1 = phys.map { ManagedIdentity.identity(hardwareID: $0.hardwareID).tier1 != nil } ?? false
                inputs.pairs.append(PlanPair(physical: key, specID: pair.specID, physicalPresent: present, tier1Verified: tier1))
            }
            guard let vid else { missingSince[pair.specID] = nil; continue }
            if present { missingSince[pair.specID] = nil } else if missingSince[pair.specID] == nil { missingSince[pair.specID] = now }
            let presented = ctx.registry.displays.first { $0.desktopID == vid }
            let bound: DisplayKey? = (phys.map { $0.hardwareID.mirrorSource == vid } ?? false) ? key : nil
            inputs.hosts.append(PlanHost(specID: pair.specID, purpose: .smartHiDPI(physical: key), isLive: true,
                                         isMain: presented?.isMain ?? false, boundTo: bound, identityMatches: true,
                                         physicalMissingSeconds: missingSince[pair.specID].map { now - $0 }))
        }
    }

    /// Planner restore: recreate the host; phase 2 rebinds the mirror.
    func reestablish(specID: StableID, physical key: DisplayKey) async {
        guard let ctx = context, !managementAutomationPaused(ctx), !sessionPaused, let pair = pairs[key], pair.specID == specID,
              pair.kept, !busy.contains(key) else { return }
        setBusy(key, true)
        defer { setBusy(key, false) }
        do {
            _ = try await createHost(key, pair: pair)
        } catch {
            lastError = (error as? VirtualHostsService.HostError)?.message
        }
    }

    /// Planner restore: mirror the returning panel onto its live virtual (tier-1 verified).
    func rebind(specID: StableID, physical key: DisplayKey) async {
        guard let ctx = context, let pair = pairs[key], pair.specID == specID, let vid = ctx.virtualHosts.liveDisplays[specID],
              let changes = bindChanges(key, virtualID: vid) else { return }
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: ManagementText.restoreSharperText, risk: .restore,
                                                                           changes: changes, finalScope: .forSession, automatic: true))
        if outcome == .applied || outcome == .kept { markBound(key, specID: specID) }
        changed()
    }

    /// No serial number to verify the panel: ask (trial).
    func promptRebind(specID: StableID, physical key: DisplayKey) {
        guard let ctx = context, let d = physical(key) else { return }
        ctx.toasts.show(ManagementText.turnSharperTextBackOn(d.name), action: ToastAction(title: L("Turn On")) { [weak self] in
            guard let self, let ctx = self.context, let lifetime = self.lifetime, let vid = ctx.virtualHosts.liveDisplays[specID],
                  let changes = self.bindChanges(key, virtualID: vid) else { return }
            ManagedTransactions.submit(ctx, TransactionRequest(label: ManagementText.restoreSharperText, risk: .trial, changes: changes,
                                                               finalScope: .forSession), lifetime: lifetime) { [weak self] outcome in
                if outcome == .applied || outcome == .kept { self?.markBound(key, specID: specID) }
            }
        }, lifetime: lifetime)
    }

    // MARK: Session / panic

    /// The gate also closes for lock and sleep, where pairs stay; see `shutdownForSession`.
    func sessionDidPause() {}

    /// Session resign: un-mirror, then shut every pair's host down (§4.9). Kept pairs are
    /// re-established through the planner when the session resumes.
    private func shutdownForSession() {
        guard let ctx = context, !sessionPaused else { return }
        sessionPaused = true
        for p in pairs.values where ctx.virtualHosts.isLive(p.specID) {
            let id = p.specID
            lifetime?.spawn { [weak self] in
                guard let self, let ctx = self.context else { return }
                ctx.virtualHosts.setPairPhysical(id, nil)
                if let vid = ctx.virtualHosts.liveDisplays[id] {
                    let mirrors = ctx.registry.displays.filter { $0.hardwareID != vid && $0.hardwareID.mirrorSource == vid }
                    if !mirrors.isEmpty {
                        _ = await ManagedTransactions.run(ctx, TransactionRequest(
                            label: ManagementText.turnOffSharperText, risk: .low, changes: mirrors.map { DisplayChange.mirror($0.hardwareID, of: nil) },
                            finalScope: .forSession, automatic: true))
                    }
                }
                await ctx.virtualHosts.destroy(specID: id)
                EventLog.shared.record(.virtualDisplay, "Sharper text pair paused for a user switch")
            }
        }
    }

    func sessionDidResume() { sessionPaused = false }

    /// Hosts shut down; macOS breaks the mirrors and the panels return (R5.4).
    func panicRestore() {
        guard let ctx = context else { return }
        for p in pairs.values { ctx.virtualHosts.destroyNow(specID: p.specID) }
    }

    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [] }
        return [(L("Pairs"), String(pairs.count)),
                (L("Kept"), String(pairs.values.filter(\.kept).count)),
                (L("Live"), String(pairs.values.filter { ctx.virtualHosts.isLive($0.specID) }.count)),
                (L("In grace (panel missing)"), String(missingSince.count)),
                (L("Last error"), lastError ?? L("none"))]
    }
}
