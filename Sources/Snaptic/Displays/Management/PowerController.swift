import AppKit
import Combine
import IOKit
import IOKit.pwr_mgt
import SnapticKit

/// Soft disconnect, auto-disconnect of the built-in display and sleep prevention
/// (PLAN §9.6, R5.7, R5.8). Disconnects are `.forSession` trials, long-armed by the queue;
/// re-enabling is a visibility restore. Panic and stop reconnect everything Snaptic disabled.
@MainActor final class PowerController: DisplayFeatureController, PanicParticipant, DiagnosticsContributor {
    static var id: DisplayControllerID { .power }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Per-display management (sleep prevention, the auto-disconnect exclusion) and the auto-disconnect setting.
    static var observedSections: Set<DisplaysConfigSection> { [.management, .perDisplayManagement] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []

    /// Displays Snaptic disconnected, with the id they had (they stay online).
    private var disabled: [DisplayKey: UInt32] = [:]
    private var autoDisconnected: Set<DisplayKey> = []
    private var externalPower: ExternalPowerReading = .notReadable
    private var externalApple = false
    private var assertion: IOPMAssertionID = 0
    private var sinks: [AnyCancellable] = []
    private var lastAutoDecision: String = ""
    /// Panic released the sleep assertion; it isn't re-taken until the latch clears (R5.4).
    private var heldByPanic = false
    /// Held here: the menu registry keeps contributors weakly.
    private var menu: ManagementMenuItems?

    var disabledKeys: Set<DisplayKey> { Set(disabled.keys) }
    var isPreventingSleep: Bool { assertion != 0 }

    /// Soft disconnect uses CGS on Intel Macs, where it is less tested: labeled Experimental
    /// there (menus, the Arrangement page; F's Features page can show `disconnectNote`).
    static var disconnectIsExperimental: Bool { !ManagedHardware.isAppleSilicon }
    static var disconnectNote: String? {
        disconnectIsExperimental ? L("Experimental on Intel Macs: a disconnected display may need a replug if macOS doesn't bring it back.") : nil
    }
    static var disconnectTitle: String { disconnectIsExperimental ? L("Disconnect (Experimental)") : L("Disconnect") }

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        switch feature {
        case .autoDisconnectBuiltin:
            switch BuiltinDisconnectPolicy.autoDisconnectAvailability(modelIdentifier: ManagedHardware.modelIdentifier,
                                                                      isAppleSilicon: ManagedHardware.isAppleSilicon) {
            case .allowed: return .available
            case .refused(let why): return .unavailable(why)
            }
        default:
            return .available
        }
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        let items = ManagementMenuItems(context: context)
        items.power = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.registerPanic(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Disconnect and sleep"), lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in MainActor.assumeIsolated { self?.displaysChanged(displays) } }
            .store(in: &sinks)
        // Resume after a panic: sleep prevention may come back (only then).
        context.runtime.$isPanicLatched
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latched in
                MainActor.assumeIsolated {
                    guard let self, !latched, self.heldByPanic else { return }
                    self.heldByPanic = false
                    self.updateSleepAssertion()
                }
            }
            .store(in: &sinks)
        updateSleepAssertion()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        let lostDisconnect = self.effective.contains(.disconnect) && !effective.contains(.disconnect)
        self.effective = effective
        if lostDisconnect { reconnectAllBestEffort() }
        updateSleepAssertion()
        changed()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.perDisplay != new.perDisplay { updateSleepAssertion() }
        if old.management != new.management || old.perDisplay != new.perDisplay { changed() }
    }

    /// Page-visible state changed (what Snaptic disconnected, sleep prevention): one revision bump and a menu rebuild.
    private func changed() {
        context?.runtime.revision(Self.id).bump()
        context?.requestMenuRebuild()
    }

    /// Reverts session state: reconnect what Snaptic disconnected, release the assertion.
    func stop() {
        reconnectAllBestEffort()
        releaseAssertion()
        heldByPanic = false
        sinks.removeAll()
        menu = nil
        lifetime = nil
        context = nil
        effective = []
    }

    /// R5.4 row: reconnect what Snaptic disconnected and release sleep prevention, which
    /// stays released while the panic latch is set.
    func panicRestore() {
        reconnectAllBestEffort()
        heldByPanic = true
        releaseAssertion()
    }

    // MARK: Disconnect

    /// Why a display can't be disconnected, or nil.
    func disconnectRefusal(_ d: DisplayInfo) -> String? {
        guard let ctx = context else { return L("Displays is off") }
        guard effective.contains(.disconnect) else { return L("Disconnect is off") }
        if d.isBuiltin, case .refused(let why) = BuiltinDisconnectPolicy.builtinAvailability(modelIdentifier: ManagedHardware.modelIdentifier) {
            return why
        }
        guard d.isActive else { return L("Already disconnected") }
        let others = ctx.registry.displays.filter { $0.key != d.key && $0.isActive }
        if d.isStronglyVisible && !others.contains(where: \.isStronglyVisible) {
            return L("Another visible display must stay connected")
        }
        if !d.isStronglyVisible && !others.contains(where: { $0.isStronglyVisible || $0.isWeaklyVisible }) {
            return L("Another visible display must stay connected")
        }
        return nil
    }

    func disconnect(_ key: DisplayKey) {
        guard let ctx = context, let lifetime, let d = ManagedDisplays.info(ctx, key: key) else { return }
        if let why = disconnectRefusal(d) {
            ctx.toasts.show(why, lifetime: lifetime)
            return
        }
        let id = d.hardwareID
        ctx.connectPlanner.beginUserChange()
        ManagedTransactions.submit(ctx, TransactionRequest(label: L("Disconnect display"), risk: .trial,
                                                           changes: [.enabled(id, false)], finalScope: .forSession),
                                   lifetime: lifetime) { [weak self] outcome in
            let ok = outcome == .applied || outcome == .kept
            if ok { self?.disabled[key] = id }
            self?.context?.connectPlanner.endUserChange(changed: ok)
            self?.changed()
        }
    }

    /// Re-enables displays; visibility restores use `.restore` (no panel).
    func reenable(_ keys: [DisplayKey], automatic: Bool) async {
        guard let ctx = context else { return }
        var changes: [DisplayChange] = []
        for k in keys {
            if let id = disabled[k] ?? ManagedDisplays.info(ctx, key: k)?.hardwareID { changes.append(.enabled(id, true)) }
        }
        guard !changes.isEmpty else { return }
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(
            label: L("Reconnect displays"), risk: automatic ? .restore : .low, changes: changes, finalScope: .forSession,
            automatic: automatic))
        if outcome == .applied || outcome == .kept {
            for k in keys {
                disabled[k] = nil
                autoDisconnected.remove(k)
            }
        }
        changed()
    }

    func connectAll() {
        guard let lifetime else { return }
        let keys = Array(disabled.keys)
        lifetime.spawn { [weak self] in await self?.reenable(keys, automatic: false) }
    }

    /// Reconnects one display (menus, the Arrangement page).
    func connect(_ key: DisplayKey) {
        lifetime?.spawn { [weak self] in await self?.reenable([key], automatic: false) }
    }

    /// Best effort from synchronous paths (stop, panic, feature off).
    private func reconnectAllBestEffort() {
        guard let ctx = context, !disabled.isEmpty else { return }
        let changes = disabled.values.map { DisplayChange.enabled($0, true) }
        disabled = [:]
        autoDisconnected = []
        ctx.runtime.revision(Self.id).bump()
        let queue = ctx.transactions
        Task { @MainActor in
            _ = await queue.submit(TransactionRequest(label: L("Reconnect displays"), risk: .restore, changes: changes,
                                                      finalScope: .forSession, automatic: true))
        }
    }

    func disconnectAllButMain() {
        guard let ctx = context, let lifetime else { return }
        let targets = ctx.registry.displays.filter { !$0.isMain && $0.isActive && disconnectRefusal($0) == nil }
        guard !targets.isEmpty else { return }
        let ids = Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0.hardwareID) })
        ctx.connectPlanner.beginUserChange()
        ManagedTransactions.submit(ctx, TransactionRequest(label: L("Disconnect all but main"), risk: .trial,
                                                           changes: ids.values.map { DisplayChange.enabled($0, false) }, finalScope: .forSession),
                                   lifetime: lifetime) { [weak self] outcome in
            let ok = outcome == .applied || outcome == .kept
            if ok { ids.forEach { self?.disabled[$0.key] = $0.value } }
            self?.context?.connectPlanner.endUserChange(changed: ok)
            self?.changed()
        }
    }

    func toggleBuiltin() {
        guard let ctx = context else { return }
        if let key = disabled.keys.first(where: { k in ctx.registry.displays.first { $0.key == k }?.isBuiltin == true }) {
            lifetime?.spawn { [weak self] in await self?.reenable([key], automatic: false) }
        } else if let b = ctx.registry.displays.first(where: { $0.isBuiltin && $0.isActive }) {
            disconnect(b.key)
        }
    }

    private func displaysChanged(_ displays: [DisplayInfo]) {
        // Forget records of displays that came back on their own or left.
        let before = disabled.count
        for (k, _) in disabled {
            guard let d = displays.first(where: { $0.key == k }) else { disabled[k] = nil; continue }
            if d.isActive { disabled[k] = nil; autoDisconnected.remove(k) }
        }
        if disabled.count != before { context?.runtime.revision(Self.id).bump() }
        updateSleepAssertion()
    }

    // MARK: Auto-disconnect (ConnectPlanner step 5)

    /// Lid state from IOPMrootDomain's AppleClamshellState; nil when unknown (desktops).
    static func lidOpen() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool else { return nil }
        return !value
    }

    /// Reads the remaining external display's power over DDC before planning (async, off the plan).
    func refreshExternalPower() async {
        guard let ctx = context, effective.contains(.autoDisconnectBuiltin) else { return }
        guard let external = ctx.registry.displays.first(where: { !$0.isBuiltin && $0.isStronglyVisible }) else {
            externalPower = .notReadable
            return
        }
        externalApple = CGDisplayVendorNumber(external.hardwareID) == 0x610
        guard ctx.ddc.isAvailable(external.key) else {
            externalPower = .notReadable
            return
        }
        if let reading = await ctx.ddc.read(0xD6, from: external.key) {
            externalPower = reading.current == 1 ? .on : .off
        } else {
            externalPower = .unknown
        }
    }

    func contribute(to inputs: inout ConnectInputs) {
        guard let ctx = context, effective.contains(.autoDisconnectBuiltin),
              let builtin = ctx.registry.displays.first(where: \.isBuiltin) else { return }
        let ignored = ctx.config.value.perDisplay[builtin.key]?.management.ignoreForAutoDisconnect ?? false
        inputs.autoDisconnect = PlanAutoDisconnect(
            builtin: builtin.key, modelIdentifier: ManagedHardware.modelIdentifier, isAppleSilicon: ManagedHardware.isAppleSilicon,
            lidOpen: Self.lidOpen(), externalPower: externalPower, externalIsAppleNative: externalApple,
            userSaysNoDDC: ctx.config.value.management.autoDisconnectWithoutDDC, builtinIgnored: ignored)
    }

    func autoDisconnect(_ key: DisplayKey) async {
        guard let ctx = context, let d = ManagedDisplays.info(ctx, key: key), d.isBuiltin, d.isActive else { return }
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(
            label: L("Disconnect the built-in display"), risk: .restore, changes: [.enabled(d.hardwareID, false)],
            finalScope: .forSession, automatic: true))
        lastAutoDecision = ManagedTransactions.outcomeName(outcome)
        if outcome == .applied || outcome == .kept {
            disabled[key] = d.hardwareID
            autoDisconnected.insert(key)
            changed()
            ctx.toasts.show(L("Built-in display disconnected"), action: ToastAction(title: L("Reconnect")) { [weak self] in
                self?.lifetime?.spawn { [weak self] in await self?.reenable([key], automatic: false) }
            }, lifetime: lifetime)
        }
    }

    // MARK: Sleep prevention

    private func updateSleepAssertion() {
        guard let ctx = context, effective.contains(.sleepPrevention), !heldByPanic, !ctx.panic.isLatched else {
            return releaseAssertion()
        }
        let wanted = ctx.registry.displays.contains { d in
            d.isOnline && (ctx.config.value.perDisplay[d.key]?.management.preventSleep ?? false)
        }
        if wanted && assertion == 0 {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Snaptic: prevent display sleep while a display is connected" as CFString, &id)
            if r == kIOReturnSuccess { assertion = id }
            ctx.runtime.sleepPreventionActive = assertion != 0
            changed()
        } else if !wanted {
            releaseAssertion()
        }
    }

    private func releaseAssertion() {
        if context?.runtime.sleepPreventionActive == true { context?.runtime.sleepPreventionActive = false }
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        changed()
    }

    func setPreventSleep(_ on: Bool, for key: DisplayKey) {
        guard let ctx = context else { return }
        var value = ctx.config.value
        var pd = value.perDisplay[key] ?? PerDisplayConfig()
        pd.management.preventSleep = on
        value.perDisplay[key] = pd
        ctx.config.value = value
    }

    // MARK: Actions / CLI

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: .dConnectAll, title: L("Connect All Displays"), feature: .disconnect, cliAllowed: true) { [weak self] _ in
            self?.connectAll()
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .dDisconnect, title: L("Disconnect Display"), feature: .disconnect, cliAllowed: true) { [weak self] t in
            guard let self, let ctx = self.context else { return }
            ManagedDisplays.resolve(ctx, t).forEach { self.disconnect($0.key) }
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .dDisconnectAllButMain, title: L("Disconnect All But Main"), feature: .disconnect,
                                    cliAllowed: true) { [weak self] _ in self?.disconnectAllButMain() }, lifetime: lifetime)
        ctx.actions.register(Action(id: .dToggleBuiltin, title: L("Toggle Built-in Display"), feature: .disconnect, cliAllowed: true) { [weak self] _ in
            self?.toggleBuiltin()
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .dSleepPreventionToggle, title: L("Toggle Display Sleep Prevention"), feature: .sleepPrevention,
                                    cliAllowed: false) { [weak self] t in
            guard let self, let ctx = self.context else { return }
            for d in ManagedDisplays.resolve(ctx, t) {
                self.setPreventSleep(!(ctx.config.value.perDisplay[d.key]?.management.preventSleep ?? false), for: d.key)
            }
        }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("connect", policy: .low, offOnly: false, cliAllowed: true, summary: L("connect all|<display>"),
                              lifetime: lifetime) { [weak self] req in
            guard let self else { return .failure(ControlExit.unavailable, L("Disconnect is off")) }
            return await self.connectCommand(req.arguments.first ?? "all")
        }
        // §11 verb list: the same as `connect all`.
        ctx.commands.register("reconnect-all", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("reconnect-all: reconnect every display Snaptic disconnected"), lifetime: lifetime) { [weak self] _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Disconnect is off")) }
            return await self.connectCommand("all")
        }
        ctx.commands.register("disconnect", policy: .trial, offOnly: false, cliAllowed: true, summary: L("disconnect <display>"),
                              lifetime: lifetime) { [weak self] req in
            guard let self, let ctx = self.context, self.effective.contains(.disconnect) else {
                return .failure(ControlExit.unavailable, L("Disconnect is off"))
            }
            guard let sel = req.arguments.first else { return .failure(ControlExit.usage, L("Usage: disconnect <display>")) }
            let pick = ManagedDisplays.cliSelectOne(ctx, sel)
            if let error = pick.error { return error }
            guard let d = pick.display else { return .failure(ControlExit.notFound, "") }
            if let why = self.disconnectRefusal(d) { return .failure(ControlExit.refused, why) }
            let id = d.hardwareID
            ctx.connectPlanner.beginUserChange()
            let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Disconnect display"), risk: .trial,
                                                                               changes: [.enabled(id, false)], finalScope: .forSession,
                                                                               skipConfirmation: req.skipConfirmation))
            let ok = outcome == .applied || outcome == .kept
            if ok { self.disabled[d.key] = id }
            ctx.connectPlanner.endUserChange(changed: ok)
            self.changed()
            return ManagedTransactions.response(outcome)
        }
        // Off-only from the CLI (R5.4): sleep prevention can be released, never started.
        ctx.commands.register("prevent-sleep", policy: .low, offOnly: true, cliAllowed: true, summary: L("prevent-sleep off"),
                              lifetime: lifetime) { [weak self] req in
            guard let self, let ctx = self.context else { return .failure(ControlExit.unavailable, "") }
            guard req.arguments.first?.lowercased() == "off" else { return .failure(ControlExit.refused, L("Only 'off' is allowed")) }
            for d in ctx.registry.displays { self.setPreventSleep(false, for: d.key) }
            return .ok()
        }
    }

    /// `connect all` / `reconnect-all` / `connect <display>`.
    private func connectCommand(_ selector: String) async -> ControlResponse {
        guard let ctx = context, effective.contains(.disconnect) else {
            return .failure(ControlExit.unavailable, L("Disconnect is off"))
        }
        let keys: [DisplayKey]
        if selector.lowercased() == "all" {
            keys = Array(disabled.keys)
        } else {
            let r = ManagedDisplays.cliKeys(ctx, selector)
            if let error = r.error { return error }
            keys = r.keys.filter { k in disabled[k] != nil || ManagedDisplays.info(ctx, key: k)?.isActive == false }
        }
        guard !keys.isEmpty else { return .ok(L("Nothing to reconnect")) }
        await reenable(keys, automatic: false)
        let still = keys.filter { disabled[$0] != nil }
        return still.isEmpty ? .ok() : .failure(ControlExit.unavailable, L("Some displays couldn't be reconnected"))
    }

    func diagnostics() -> [(String, String)] {
        [(L("Disconnected by Snaptic"), String(disabled.count)),
         (L("Auto-disconnected"), String(autoDisconnected.count)),
         (L("Lid"), Self.lidOpen().map { $0 ? L("open") : L("closed") } ?? L("unknown")),
         (L("External power reading"), externalPower.rawValue),
         (L("Last auto-disconnect"), lastAutoDecision.isEmpty ? L("none") : lastAutoDecision),
         (L("Preventing display sleep"), isPreventingSleep ? L("Yes") : (heldByPanic ? L("No (released by Restore All Displays)") : L("No"))),
         (L("Disconnect"), Self.disconnectIsExperimental ? L("Experimental (Intel)") : L("Standard"))]
    }
}
