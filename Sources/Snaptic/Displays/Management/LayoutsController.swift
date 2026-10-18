import AppKit
import SnapticKit

/// Saved display layouts ("Layouts"): capture, manual apply, trust and auto-apply
/// (PLAN §9.7, §4.11 step 3, R5.7).
@MainActor final class LayoutsController: DisplayFeatureController, DiagnosticsContributor {
    static var id: DisplayControllerID { .layouts }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Saved layouts and their settings (0.3 §4.5).
    static var observedSections: Set<DisplaysConfigSection> { [.layouts] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var menu: LayoutsMenuItems?
    /// A matching layout whose toast may have been missed (R5.7).
    private(set) var pendingMatch: StableID? {
        didSet { if pendingMatch != oldValue { changed() } }
    }
    private var autoApplies = 0

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        let items = LayoutsMenuItems(context: context)
        items.controller = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Layouts"), lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        changed()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.layouts != new.layouts {
            if let p = pendingMatch, new.layouts.layout(p) == nil { pendingMatch = nil }
            changed()
        }
    }

    /// Page-visible state changed (the missed-prompt match, trust): one revision bump and a menu rebuild.
    private func changed() {
        context?.runtime.revision(Self.id).bump()
        context?.requestMenuRebuild()
    }

    func stop() {
        pendingMatch = nil
        menu = nil
        lifetime = nil
        context = nil
        effective = []
    }

    // MARK: Model

    var layouts: [SavedLayout] { context?.config.value.layouts.layouts ?? [] }

    func layout(_ id: StableID) -> SavedLayout? { context?.config.value.layouts.layout(id) }

    func liveIdentities() -> [LiveLayoutDisplay] {
        guard let ctx = context else { return [] }
        return ctx.registry.displays.filter { $0.isActive || $0.isOnline }
            .filter { $0.transport != .snapticVirtual || $0.isSmartHiDPIPair }
            .map { LiveLayoutDisplay(key: $0.key, identity: ManagedIdentity.identity(hardwareID: $0.hardwareID)) }
    }

    func isTrusted(_ l: SavedLayout) -> Bool {
        LayoutPresetModel.isTrusted(l, osMajor: ManagedIdentity.osMajor, digest: ManagedIdentity.sha256Hex)
    }

    func matches(_ l: SavedLayout) -> LayoutMatch? { LayoutPresetModel.match(l, live: liveIdentities()) }

    /// The menu's "Apply Matching Layout": the layout a missed prompt offered while it still matches, else the
    /// most specific matching layout.
    func matchingLayout() -> SavedLayout? {
        if let p = pendingMatch, let l = layout(p), matches(l) != nil { return l }
        return LayoutPresetModel.bestMatch(layouts, live: liveIdentities())
    }

    /// How the presented displays are arranged now (the menu's checkmarks; read once per menu build).
    func liveStates() -> [DisplayKey: LayoutLiveState] {
        guard let ctx = context else { return [:] }
        let all = ctx.registry.displays.filter { $0.isActive && ($0.transport != .snapticVirtual || $0.isSmartHiDPIPair) }
        var states: [DisplayKey: LayoutLiveState] = [:]
        for d in all {
            let r = ManagedDisplays.rect(d)
            let mirror = d.mirrorOf.flatMap { src in all.first { $0.desktopID == src || $0.hardwareID == src }?.key }
            states[d.key] = LayoutLiveState(mode: d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref,
                                            x: r.x, y: r.y, isMain: d.isMain, rotation: d.rotation, mirrorOf: mirror)
        }
        return states
    }

    private func update(_ id: StableID, _ change: (inout SavedLayout) -> Void) {
        guard let ctx = context, let i = ctx.config.value.layouts.layouts.firstIndex(where: { $0.id == id }) else { return }
        var value = ctx.config.value
        change(&value.layouts.layouts[i])
        value.layouts.layouts[i] = value.layouts.layouts[i].sanitized()
        ctx.config.value = value
    }

    /// Any edit clears trust (R5.7).
    func edit(_ id: StableID, _ change: (inout SavedLayout) -> Void) {
        update(id) { l in
            let before = l
            change(&l)
            if l.displays != before.displays || l.virtualScreens != before.virtualScreens || l.nightShift != before.nightShift {
                l.trust = nil
            }
        }
    }

    func delete(_ id: StableID) {
        guard let ctx = context else { return }
        ctx.config.value.layouts.layouts.removeAll { $0.id == id }
    }

    func move(_ id: StableID, by delta: Int) {
        guard let ctx = context, let i = ctx.config.value.layouts.layouts.firstIndex(where: { $0.id == id }) else { return }
        let j = min(ctx.config.value.layouts.layouts.count - 1, max(0, i + delta))
        guard i != j else { return }
        var list = ctx.config.value.layouts.layouts
        list.swapAt(i, j)
        ctx.config.value.layouts.layouts = list
    }

    /// "Capture current": the presented displays' current state.
    @discardableResult
    func captureCurrent(name: String? = nil) -> SavedLayout? {
        guard let ctx = context else { return nil }
        guard ctx.config.value.layouts.layouts.count < LayoutPresetModel.maxLayouts else {
            ctx.toasts.show(L("You can save up to 32 layouts"), lifetime: lifetime)
            return nil
        }
        var displays: [DisplayKey: SavedDisplaySettings] = [:]
        let all = ctx.registry.displays.filter { $0.isActive && ($0.transport != .snapticVirtual || $0.isSmartHiDPIPair) }
        for d in all {
            let mirror = d.mirrorOf.flatMap { src in all.first { $0.desktopID == src || $0.hardwareID == src }?.key }
            let r = ManagedDisplays.rect(d)
            let ddc = capturedDDC(ctx, d.key)
            displays[d.key] = SavedDisplaySettings(
                mode: d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref, x: r.x, y: r.y, isMain: d.isMain,
                rotation: d.rotation, mirrorOf: mirror, mirrorSet: true, brightness: ctx.brightness.value(for: d.key),
                ddcInput: ddc.input, volume: ddc.volume, identity: ManagedIdentity.identity(hardwareID: d.hardwareID))
        }
        guard !displays.isEmpty else { return nil }
        var virtuals: [StableID: Bool] = [:]
        for s in ctx.config.value.virtualScreens.screens { virtuals[s.id] = ctx.virtualHosts.isLive(s.id) }
        let n = ctx.config.value.layouts.layouts.count + 1
        let layout = SavedLayout(name: name ?? L("Layout \(n)"), displays: displays, virtualScreens: virtuals).sanitized()
        ctx.config.value.layouts.layouts.append(layout)
        if displays.values.contains(where: { $0.identity.tier1 == nil }) {
            ctx.toasts.show(L("Some displays have no serial number; '\(layout.name)' matches them by UUID only"), lifetime: lifetime)
        }
        return layout
    }

    /// DDC volume and input as C's controller last read or set them (live values; nothing is
    /// read from the monitor here). Only when the feature is on and the control is enabled.
    private func capturedDDC(_ ctx: DisplaysContext, _ key: DisplayKey) -> (volume: Double?, input: UInt16?) {
        guard ctx.ddc.isAvailable(key), let ddc = ctx.ddc.controller else { return (nil, nil) }
        let eff = ctx.runtime.effectiveFeatures
        let live = ctx.runtime.runtime(for: key)
        var volume: Double?
        if eff.contains(.ddcControls), ddc.isControlEnabled(VCPPolicy.volume, for: key), let v = live.volume, v.isFinite {
            volume = min(1, max(0, v))
        }
        let input = eff.contains(.ddcInput) ? live.input : nil
        return (volume, input)
    }

    // MARK: Apply

    private struct Plan {
        var changes: [DisplayChange] = []
        var skipped: [String] = []
    }

    private func plan(_ l: SavedLayout, ctx: DisplaysContext) -> Plan {
        var p = Plan()
        let eff = ctx.runtime.effectiveFeatures
        for (key, s) in l.displays.values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let d = ManagedDisplays.info(ctx, key: key) else { continue }
            if let m = s.mode {
                if eff.contains(.resolution), let live = ProtectionDiff.resolve(m, in: ManagedModes.modes(for: d.desktopID).map(\.ref)) {
                    if live != (d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref) { p.changes.append(.mode(d.desktopID, live)) }
                } else { p.skipped.append(L("resolution")) }
            }
            if let x = s.x, let y = s.y, s.mirrorOf == nil {
                if eff.contains(.arrangement) {
                    let r = ManagedDisplays.rect(d)
                    if r.x != x || r.y != y { p.changes.append(.origin(d.desktopID, x: x, y: y)) }
                } else { p.skipped.append(L("arrangement")) }
            }
            if s.isMain == true, !d.isMain {
                if eff.contains(.mainDisplay) { p.changes.append(.main(d.desktopID)) } else { p.skipped.append(L("main display")) }
            }
            if let r = s.rotation, r != d.rotation {
                if eff.contains(.rotation) && ctx.guardClient.canMonitorPanel { p.changes.append(.rotation(d.hardwareID, r)) }
                else { p.skipped.append(L("rotation")) }
            }
            if s.mirrorSet {
                if eff.contains(.mirroring) {
                    let source = s.mirrorOf.flatMap { ManagedDisplays.info(ctx, key: $0)?.desktopID }
                    if source != d.mirrorOf && !(s.mirrorOf != nil && source == nil) { p.changes.append(.mirror(d.hardwareID, of: source)) }
                } else { p.skipped.append(L("mirroring")) }
            }
        }
        p.skipped = Array(Set(p.skipped)).sorted()
        return p
    }

    /// Brightness, volume (and, for manual applies, DDC input) after the layout transaction.
    /// DDC goes through C's controller: its per-control tuning maps the saved fraction, and
    /// `setInput` asks first (PreConfirm) with the user's input names and LG addressing.
    private func applyExtras(_ l: SavedLayout, ctx: DisplaysContext, manual: Bool) async {
        let eff = ctx.runtime.effectiveFeatures
        for (key, s) in l.displays.values {
            guard ManagedDisplays.info(ctx, key: key) != nil else { continue }
            if let b = s.brightness, eff.contains(.brightness) { ctx.brightness.set(b, for: key, source: .automation) }
            guard ctx.ddc.isAvailable(key), let ddc = ctx.ddc.controller else { continue }
            if let v = s.volume, eff.contains(.ddcControls), ddc.isControlEnabled(VCPPolicy.volume, for: key) {
                let current = ctx.runtime.runtime(for: key).volume
                if current.map({ abs($0 - v) > 0.005 }) ?? true { ddc.setFraction(VCPPolicy.volume, v, for: key) }
            }
            // DDC input is never part of auto-apply (§9.7) and always confirms (preConfirm code).
            if manual, let input = s.ddcInput, eff.contains(.ddcInput), ctx.runtime.runtime(for: key).input != input {
                let entries = ddc.inputList(for: key, includeHidden: true).filter { $0.value == input }
                let entry = entries.first(where: { !$0.lgAlt }) ?? entries.first
                    ?? DDCInputEntry(value: input, name: VCPPolicy.inputName(input))
                _ = ddc.setInput(entry, on: key)
            }
        }
        if eff.contains(.virtualScreens), let virtual = ctx.connectPlanner.virtual {
            for (id, on) in l.virtualScreens.values {
                if on { await virtual.connect(id) } else { await virtual.disconnect(id) }
            }
        }
    }

    /// Manual apply: one transaction plus brightness, volume and DDC input (§9.7).
    func apply(_ id: StableID) {
        guard let lifetime else { return }
        lifetime.spawn { [weak self] in _ = await self?.applyAwaiting(id) }
    }

    /// The manual apply, awaited (the CLI reports the outcome: 0 kept or applied, 6 reverted).
    /// `skipConfirmation`: `--yes` the user allowed (FIXES-R3 1). Nil when nothing was tried.
    @discardableResult
    func applyAwaiting(_ id: StableID, skipConfirmation: Bool = false) async -> TransactionOutcome? {
        guard let ctx = context, let lifetime, let l = layout(id) else { return nil }
        guard matches(l) != nil else {
            ctx.toasts.show(L("'\(l.name)' doesn't match the connected displays"), lifetime: lifetime)
            return nil
        }
        let p = plan(l, ctx: ctx)
        let trusted = isTrusted(l)
        let risk: TransactionRisk = l.hasTrialContent ? .trial : .low
        ctx.connectPlanner.beginUserChange()
        var outcome: TransactionOutcome = .applied
        if !p.changes.isEmpty {
            outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Apply layout"), risk: risk, changes: p.changes,
                                                                           skipConfirmation: skipConfirmation))
        }
        let ok = outcome == .applied || outcome == .kept
        ctx.connectPlanner.endUserChange(changed: ok)
        guard !lifetime.isEnded, context === ctx else { return outcome }
        guard ok else {
            if let text = ManagedTransactions.message(outcome) { ctx.toasts.show(text, lifetime: lifetime) }
            return outcome
        }
        await applyExtras(l, ctx: ctx, manual: true)
        guard !lifetime.isEnded, context === ctx else { return outcome }
        ctx.osd.show(.layout, text: l.name, on: ctx.registry.displays.first(where: \.isMain)?.desktopID ?? 0)
        if !p.skipped.isEmpty {
            ctx.toasts.show(L("Applied '\(l.name)'; skipped \(p.skipped.joined(separator: ", ")) (feature off)"), lifetime: lifetime)
        }
        if pendingMatch == id { pendingMatch = nil }
        if !trusted { offerTrust(id) }
        return outcome
    }

    /// "Keep for automatic use?" after a kept manual apply (R5.7).
    private func offerTrust(_ id: StableID) {
        guard let ctx = context, let l = layout(id), l.autoApply != .never else { return }
        ctx.toasts.show(L("Keep '\(l.name)' for automatic use?"), action: ToastAction(title: L("Keep")) { [weak self] in
            self?.trust(id)
        }, lifetime: lifetime)
    }

    func trust(_ id: StableID) {
        guard let l = layout(id) else { return }
        guard let stamp = LayoutPresetModel.stamp(l, osMajor: ManagedIdentity.osMajor, digest: ManagedIdentity.sha256Hex) else {
            context?.toasts.show(L("Layouts with displays that have no serial number can't apply automatically"), lifetime: lifetime)
            return
        }
        update(id) { $0.trust = stamp }
    }

    func untrust(_ id: StableID) { update(id) { $0.trust = nil } }

    // MARK: ConnectPlanner (step 3)

    func contribute(to inputs: inout ConnectInputs) {
        guard let ctx = context, effective.contains(.layouts), !managementAutomationPaused(ctx) else { return }
        let live = liveIdentities()
        // Fingerprint changes clear trust.
        for l in layouts where l.trust != nil {
            let r = LayoutPresetModel.revalidated(l, live: live)
            if r.trust == nil { update(l.id) { $0.trust = nil } }
        }
        inputs.layouts = layouts
        inputs.trustedLayouts = Set(layouts.filter { self.isTrusted($0) }.map(\.id))
        inputs.liveIdentities = live
    }

    func applyAutomatically(_ id: StableID) async {
        guard let ctx = context, let l = layout(id), isTrusted(l) else { return }
        // Undo: the state before, as a transient layout (CAS-checked by the queue).
        let before = Dictionary(uniqueKeysWithValues: ctx.registry.displays.filter(\.isActive).map { d in
            (d.key, (mode: d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref, rect: ManagedDisplays.rect(d), main: d.isMain))
        })
        let p = plan(l, ctx: ctx)
        let scope: FinalScope = ctx.virtualHosts.liveDisplays.isEmpty ? .permanently : .forSession
        if !p.changes.isEmpty {
            let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Apply layout"), risk: .restore,
                                                                               changes: p.changes, finalScope: scope, automatic: true))
            guard outcome == .applied || outcome == .kept else { return }
        }
        await applyExtras(l, ctx: ctx, manual: false)
        autoApplies += 1
        guard ctx.config.value.layouts.undoToast, !p.changes.isEmpty else { return }
        ctx.toasts.show(L("Applied '\(l.name)'"), action: ToastAction(title: L("Undo")) { [weak self] in
            guard let self, let ctx = self.context, let lifetime = self.lifetime else { return }
            var undo: [DisplayChange] = []
            for (key, b) in before {
                guard let d = ManagedDisplays.info(ctx, key: key) else { continue }
                if let m = b.mode, m != (d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref) { undo.append(.mode(d.desktopID, m)) }
                let r = ManagedDisplays.rect(d)
                if r.x != b.rect.x || r.y != b.rect.y { undo.append(.origin(d.desktopID, x: b.rect.x, y: b.rect.y)) }
                if b.main && !d.isMain { undo.append(.main(d.desktopID)) }
            }
            guard !undo.isEmpty else { return }
            ManagedTransactions.submit(ctx, TransactionRequest(label: L("Undo layout"), risk: .low, changes: undo), lifetime: lifetime)
        }, lifetime: lifetime)
    }

    /// Untrusted match: "Apply 'Office'?" plus a menu item in case the toast is missed.
    func promptApply(_ id: StableID) {
        guard let ctx = context, let l = layout(id) else { return }
        pendingMatch = id
        ctx.toasts.show(L("Apply '\(l.name)'?"), action: ToastAction(title: L("Apply")) { [weak self] in self?.apply(id) },
                        lifetime: lifetime)
    }

    // MARK: Actions / CLI

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        for n in 1...9 {
            ctx.actions.register(Action(id: .dLayout(n), title: L("Apply Layout \(n)"), feature: .layouts, cliAllowed: true) { [weak self] _ in
                guard let self, self.layouts.indices.contains(n - 1) else { return }
                self.apply(self.layouts[n - 1].id)
            }, lifetime: lifetime)
        }
    }

    private func find(_ selector: String) -> SavedLayout? {
        if let n = Int(selector), layouts.indices.contains(n - 1) { return layouts[n - 1] }
        if let id = StableID(rawValue: selector) { return layout(id) }
        let lower = selector.lowercased()
        return layouts.first { $0.name.lowercased() == lower } ?? layouts.first { $0.name.lowercased().hasPrefix(lower) }
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("layout", policy: .trial, offOnly: false, cliAllowed: true,
                              summary: L("layout list | apply <name|number> | capture <name>"), lifetime: lifetime) { [weak self] req, _ in
            guard let self, self.effective.contains(.layouts) else { return .failure(ControlExit.unavailable, L("Layouts are off")) }
            let a = req.arguments
            switch a.first?.lowercased() {
            case "list", nil:
                if req.json {
                    let rows: [[String: Any]] = self.layouts.enumerated().map { i, l in
                        ["number": i + 1, "id": l.id.rawValue, "name": l.name, "matches": self.matches(l) != nil,
                         "trusted": self.isTrusted(l), "auto": l.autoApply != .never]
                    }
                    return .ok(KitControl.jsonText(rows) ?? "[]")
                }
                return .ok(self.layouts.enumerated().map { pair -> String in
                    let i = pair.offset
                    let l = pair.element
                    let flags = [self.matches(l) != nil ? "matches" : nil, self.isTrusted(l) ? "trusted" : nil, l.autoApply == .never ? nil : "auto"]
                        .compactMap { $0 }.joined(separator: ",")
                    return "\(i + 1). \(l.name)" + (flags.isEmpty ? "" : " [\(flags)]")
                }.joined(separator: "\n"))
            case "apply":
                guard a.count > 1, let l = self.find(a.dropFirst().joined(separator: " ")) else {
                    return .failure(ControlExit.notFound, L("No such layout"))
                }
                guard self.matches(l) != nil else { return .failure(ControlExit.refused, L("The layout doesn't match the connected displays")) }
                // Awaits the outcome: 0 applied or kept, 6 declined or timed out (FIXES-R3 10).
                guard let outcome = await self.applyAwaiting(l.id, skipConfirmation: req.skipConfirmation) else {
                    return .failure(ControlExit.unavailable, L("Layouts are off"))
                }
                let response = ManagedTransactions.response(outcome, ok: l.name)
                if req.json, response.exitCode == ControlExit.ok {
                    return .ok(KitControl.jsonText(["name": l.name, "id": l.id.rawValue, "outcome": ManagedTransactions.outcomeName(outcome)]) ?? "{}")
                }
                return response
            case "capture":
                let name = a.count > 1 ? TextSanitizer.clean(a.dropFirst().joined(separator: " "), maxScalars: SavedLayout.maxNameScalars) : nil
                guard let l = self.captureCurrent(name: name) else { return .failure(ControlExit.refused, L("Couldn't capture a layout")) }
                if req.json { return .ok(KitControl.jsonText(["name": l.name, "id": l.id.rawValue]) ?? "{}") }
                return .ok(l.name)
            default:
                return .failure(ControlExit.usage, L("Usage: layout list | apply <name> | capture <name>"))
            }
        }
    }

    func diagnostics() -> [(String, String)] {
        [(L("Layouts"), String(layouts.count)),
         (L("Trusted"), String(layouts.filter { self.isTrusted($0) }.count)),
         (L("Matching now"), String(layouts.filter { matches($0) != nil }.count)),
         (L("Automatic applies this session"), String(autoApplies))]
    }
}
