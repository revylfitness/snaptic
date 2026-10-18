import AppKit
import Combine
import SnapticKit

/// Rotation, underscan and HDR (PLAN §9.6, R5.2): always trials, journaled by the queue as
/// MonitorPanel steps; refused when the safety helper can't revert them, and HDR/underscan
/// are refused on the only strongly visible display. Panic doesn't touch them (R5.4).
@MainActor final class PanelPropsController: DisplayFeatureController, DiagnosticsContributor {
    static var id: DisplayControllerID { .panelProps }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Reads no config: rotation, HDR and underscan are live panel state (0.3 §4.5).
    static var observedSections: Set<DisplaysConfigSection> { [] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    /// Held here: the menu registry keeps contributors weakly.
    private var menu: ManagementMenuItems?
    private var sinks: [AnyCancellable] = []

    static let rotations = [0, 90, 180, 270]

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        // MonitorPanel groups are probed by PrivateDisplayAPI, which marks these unavailable.
        .available
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        let items = ManagementMenuItems(context: context)
        items.panelProps = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.diagnostics.register(self, section: ManagementText.panelPropertiesSection, lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        // Rotation, HDR and underscan also change outside Snaptic (System Settings, a replug): pages re-read.
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.context?.runtime.revision(Self.id).bump() } }
            .store(in: &sinks)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        changed()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {}

    func stop() {
        sinks.removeAll()
        menu = nil
        lifetime = nil
        context = nil
        effective = []
    }

    // MARK: State

    func rotation(_ d: DisplayInfo) -> Int { context?.monitorPanel.rotation(of: d.key) ?? d.rotation }
    func hdrEnabled(_ d: DisplayInfo) -> Bool? { context?.monitorPanel.hdrEnabled(of: d.key) ?? d.hdrEnabled }
    func underscan(_ d: DisplayInfo) -> Double? { context?.monitorPanel.underscan(of: d.key) }

    /// Why a panel change can't run, or nil.
    func refusal(_ feature: DisplayFeature, for d: DisplayInfo) -> String? {
        guard let ctx = context else { return L("Displays is off") }
        guard effective.contains(feature) else { return L("This feature is off") }
        guard ctx.guardClient.canMonitorPanel else { return L("Safety helper can't revert this") }
        let group = feature == .rotation ? "rotation" : feature == .hdrToggle ? "hdr" : "underscan"
        guard ctx.privateAPI.monitorPanelSupports(group) else { return L("Not supported on this Mac") }
        switch feature {
        case .rotation:
            if d.isBuiltin { return L("The built-in display can't be rotated") }
        case .hdrToggle:
            if d.hdrSupported != true { return L("This display doesn't support HDR") }
            if ManagedDisplays.onlyStronglyVisible(ctx) == d.key { return L("Refused on the only visible display") }
        case .underscan:
            if ManagedDisplays.onlyStronglyVisible(ctx) == d.key { return L("Refused on the only visible display") }
        default: break
        }
        return nil
    }

    private func submit(_ feature: DisplayFeature, _ key: DisplayKey, label: String, change: (DisplayInfo) -> DisplayChange) {
        guard let ctx = context, let lifetime, let d = ManagedDisplays.info(ctx, key: key) else { return }
        if let why = refusal(feature, for: d) {
            ctx.toasts.show(why, lifetime: lifetime)
            return
        }
        ctx.connectPlanner.beginUserChange()
        ManagedTransactions.submit(ctx, TransactionRequest(label: label, risk: .trial, changes: [change(d)], finalScope: .permanently),
                                   lifetime: lifetime) { [weak self] outcome in
            self?.context?.connectPlanner.endUserChange(changed: outcome == .applied || outcome == .kept)
            self?.changed()
        }
    }

    /// Page-visible state changed: one revision bump and a menu rebuild.
    private func changed() {
        context?.runtime.revision(Self.id).bump()
        context?.requestMenuRebuild()
    }

    func rotate(_ key: DisplayKey, to degrees: Int) {
        guard Self.rotations.contains(degrees) else { return }
        submit(.rotation, key, label: L("Rotate display")) { .rotation($0.hardwareID, degrees) }
    }

    func rotateNext(_ key: DisplayKey) {
        guard let ctx = context, let d = ManagedDisplays.info(ctx, key: key) else { return }
        rotate(key, to: (rotation(d) + 90) % 360)
    }

    func setHDR(_ key: DisplayKey, _ on: Bool) {
        submit(.hdrToggle, key, label: on ? L("Turn on HDR") : L("Turn off HDR")) { .hdr($0.hardwareID, on) }
    }

    func setUnderscan(_ key: DisplayKey, _ value: Double) {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        submit(.underscan, key, label: L("Change underscan")) { .underscan($0.hardwareID, v) }
    }

    // MARK: Actions / CLI

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: .dRotate, title: L("Rotate Display"), feature: .rotation, cliAllowed: true) { [weak self] t in
            guard let self, let ctx = self.context else { return }
            ManagedDisplays.resolve(ctx, t).forEach { self.rotateNext($0.key) }
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .dHDRToggle, title: ManagementText.toggleHighDynamicRange, feature: .hdrToggle, cliAllowed: true) { [weak self] t in
            guard let self, let ctx = self.context else { return }
            for d in ManagedDisplays.resolve(ctx, t) { self.setHDR(d.key, !(self.hdrEnabled(d) ?? false)) }
        }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("rotate", policy: .trial, offOnly: false, cliAllowed: true, summary: L("rotate <display> 0|90|180|270"),
                              lifetime: lifetime) { [weak self] req, _ in
            guard let self, let ctx = self.context, self.effective.contains(.rotation) else {
                return .failure(ControlExit.unavailable, L("Rotation is off"))
            }
            let a = req.arguments
            guard a.count == 2, let deg = Int(a[1]), Self.rotations.contains(deg) else {
                return .failure(ControlExit.usage, L("Usage: rotate <display> 0|90|180|270"))
            }
            let pick = ManagedDisplays.cliSelectOne(ctx, a[0])
            if let error = pick.error { return error }
            guard let d = pick.display else { return .failure(ControlExit.notFound, "") }
            if let why = self.refusal(.rotation, for: d) { return .failure(ControlExit.refused, why) }
            ctx.connectPlanner.beginUserChange()
            let outcome = await ManagedTransactions.run(
                ctx, TransactionRequest(label: L("Rotate display"), risk: .trial, changes: [.rotation(d.hardwareID, deg)],
                                        finalScope: .permanently, skipConfirmation: req.skipConfirmation))
            ctx.connectPlanner.endUserChange(changed: outcome == .applied || outcome == .kept)
            return ManagedTransactions.response(outcome)
        }
    }

    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [] }
        var rows: [(String, String)] = [(L("Safety helper can revert panel changes"), ctx.guardClient.canMonitorPanel ? L("Yes") : L("No"))]
        for d in ctx.registry.displays {
            let hdr = hdrEnabled(d).map { $0 ? L("HDR on") : L("HDR off") } ?? L("HDR n/a")
            rows.append((d.name, "\(rotation(d))°, \(hdr)" + (underscan(d).map { String(format: ", underscan %.0f%%", $0 * 100) } ?? "")))
        }
        return rows
    }
}
