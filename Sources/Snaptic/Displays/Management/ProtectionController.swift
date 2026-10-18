import AppKit
import SnapticKit

/// Configuration protection (PLAN §9.6): a desired state per presented-display set,
/// re-applied only through the ConnectPlanner as `restore`, with fight detection.
@MainActor final class ProtectionController: DisplayFeatureController, DiagnosticsContributor {
    static var id: DisplayControllerID { .protection }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Protected profiles and fields live in `management` (0.3 §4.5).
    static var observedSections: Set<DisplaysConfigSection> { [.management] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var fights = ProtectionFightTracker()
    private var lastApplied: [DisplaySetKey: Double] = [:]
    private var suspended = false
    private var activationObserver: NSObjectProtocol?
    private var applies = 0
    /// Held here: the menu registry keeps contributors weakly.
    private var menu: ManagementMenuItems?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        let items = ManagementMenuItems(context: context)
        items.protection = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Protection"), lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        context.actions.register(Action(id: .dProtectionToggle, title: L("Protect Arrangement"), feature: .protection,
                                        cliAllowed: false) { [weak self] _ in self?.toggleCurrent() }, lifetime: lifetime)
        context.commands.register("protect", policy: .low, offOnly: true, cliAllowed: true,
                                  summary: L("protect off: stop configuration protection"), lifetime: lifetime) { [weak self] req in
            guard let self, let ctx = self.context else { return .failure(ControlExit.unavailable, "") }
            guard req.arguments.first?.lowercased() == "off" else { return .failure(ControlExit.refused, L("Only 'off' is allowed")) }
            ctx.config.value.features[.protection] = false
            return .ok()
        }
        // R5.4 exposure name; off-only: it can turn protection off, never on.
        context.commands.register("toggle protection", policy: .low, offOnly: true, cliAllowed: true,
                                  summary: L("toggle protection: turn configuration protection off"), lifetime: lifetime) { [weak self] _ in
            guard let self, let ctx = self.context else { return .failure(ControlExit.unavailable, "") }
            guard self.effective.contains(.protection) else {
                return .failure(ControlExit.refused, L("Protection can only be turned off from the command line"))
            }
            ctx.config.value.features[.protection] = false
            return .ok(L("Protection is off"))
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                    queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSuspended(false) }
        }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        changed()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.management.protection != new.management.protection
            || old.management.protectionFields != new.management.protectionFields { changed() }
    }

    /// Page-visible state changed (protected sets, paused): one revision bump and a menu rebuild.
    private func changed() {
        context?.runtime.revision(Self.id).bump()
        context?.requestMenuRebuild()
    }

    private func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        changed()
    }

    /// Re-applies stopped for the current set: macOS keeps changing it, or the last re-apply failed.
    var isPaused: Bool { suspended || (currentSet().map { fights.isStopped($0) } ?? false) }

    func stop() {
        if let o = activationObserver { NotificationCenter.default.removeObserver(o) }
        activationObserver = nil
        fights.resetAll()
        lastApplied = [:]
        suspended = false
        menu = nil
        lifetime = nil
        context = nil
        effective = []
    }

    // MARK: Desired state

    private func live(_ ctx: DisplaysContext) -> [LiveDisplayState] {
        ConnectInputs(trigger: .reconfigure, displays: ctx.connectPlanner.planDisplays(ctx)).liveStates
    }

    func currentSet() -> DisplaySetKey? {
        guard let ctx = context else { return nil }
        return DisplaySetKey(keys: Set(ctx.registry.displays.filter(\.isActive).map(\.key)))
    }

    func profile(for set: DisplaySetKey?) -> ProtectionProfile? {
        guard let set else { return nil }
        return context?.config.value.management.protection[set]
    }

    var isProtectingCurrent: Bool { profile(for: currentSet()) != nil }

    func captureCurrent() {
        guard let ctx = context, let set = currentSet() else { return }
        let p = ProtectionDiff.capture(live(ctx), at: managementWallClock())
        ctx.config.value.management.protection[set] = p
        fights.reset(set)
        EventLog.shared.record(.protection, "Protection captured for \(set.keys.count) display(s)")
    }

    func removeCurrent() {
        guard let ctx = context, let set = currentSet() else { return }
        ctx.config.value.management.protection[set] = nil
        fights.reset(set)
    }

    func toggleCurrent() {
        guard effective.contains(.protection) else { return }
        if isProtectingCurrent { removeCurrent() } else { captureCurrent() }
    }

    /// A Snaptic change (Keep, arrange) becomes the new desired state for the current set.
    func recaptureAfterSnapticChange() {
        guard let ctx = context, effective.contains(.protection), let set = currentSet(), let p = profile(for: set) else { return }
        let updated = ProtectionDiff.updating(p, with: live(ctx), at: managementWallClock())
        if updated != p { ctx.config.value.management.protection[set] = updated }
    }

    // MARK: ConnectPlanner

    func contribute(to inputs: inout ConnectInputs) {
        guard let ctx = context, effective.contains(.protection), let set = currentSet() else { return }
        inputs.protection = profile(for: set)
        inputs.protectionFields = ctx.config.value.management.protectionFields
        inputs.protectionStopped = suspended || fights.isStopped(set)
    }

    private func changes(for deltas: [ProtectionDelta], ctx: DisplaysContext) -> [DisplayChange] {
        deltas.compactMap { (delta: ProtectionDelta) -> DisplayChange? in
            guard let d = ManagedDisplays.info(ctx, key: delta.key) else { return nil }
            switch delta {
            case .mode(_, let m): return .mode(d.desktopID, m)
            case .origin(_, let x, let y): return .origin(d.desktopID, x: x, y: y)
            case .rotation(_, let r): return .rotation(d.hardwareID, r)
            case .main: return .main(d.desktopID)
            case .mirror(_, let source):
                let sourceID = source.flatMap { ManagedDisplays.info(ctx, key: $0)?.desktopID }
                if source != nil && sourceID == nil { return nil }
                return .mirror(d.hardwareID, of: sourceID)
            }
        }
    }

    /// While Snaptic virtuals are online, re-applies use `.forSession` (R5.2).
    private func scope(_ ctx: DisplaysContext) -> FinalScope {
        ctx.virtualHosts.liveDisplays.isEmpty ? .permanently : .forSession
    }

    func apply(_ deltas: [ProtectionDelta]) async {
        guard let ctx = context, let set = currentSet() else { return }
        let now = managementUptime()
        if let last = lastApplied[set], now - last <= ProtectionFightTracker.window, fights.noteOverwrite(set, at: now) {
            ctx.toasts.show(L("macOS keeps changing this arrangement; protection is paused for it"), lifetime: lifetime)
            EventLog.shared.record(.protection, "Protection stopped: fight detected")
            changed()
            return
        }
        let list = changes(for: deltas, ctx: ctx)
        guard !list.isEmpty else { return }
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Restore protected arrangement"), risk: .restore,
                                                                           changes: list, finalScope: scope(ctx), automatic: true))
        lastApplied[set] = managementUptime()
        applies += 1
        if case .failed = outcome {
            // E.g. kCGErrorCannotComplete: wait for the user to come back to Snaptic.
            setSuspended(true)
        }
    }

    func promptRestore(_ deltas: [ProtectionDelta]) {
        guard let ctx = context, let lifetime else { return }
        ctx.toasts.show(L("Restore your protected arrangement?"), action: ToastAction(title: L("Restore")) { [weak self] in
            guard let self, let ctx = self.context, let lifetime = self.lifetime else { return }
            let list = self.changes(for: deltas, ctx: ctx)
            guard !list.isEmpty else { return }
            // Only un-mirroring left to restore: that restores visibility, so it is low.
            let unmirrorOnly = list.allSatisfy { if case .mirror(_, of: .none) = $0 { return true }; return false }
            ManagedTransactions.submit(ctx, TransactionRequest(label: L("Restore protected arrangement"),
                                                               risk: unmirrorOnly ? .low : .trial, changes: list,
                                                               finalScope: self.scope(ctx)), lifetime: lifetime)
        }, lifetime: lifetime)
    }

    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [] }
        let set = currentSet()
        return [(L("Protected display sets"), String(ctx.config.value.management.protection.values.count)),
                (L("Current set protected"), isProtectingCurrent ? L("Yes") : L("No")),
                (L("Paused (fight or error)"), (set.map { fights.isStopped($0) } ?? false) || suspended ? L("Yes") : L("No")),
                (L("Re-applies this session"), String(applies))]
    }
}
