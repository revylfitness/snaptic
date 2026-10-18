import AppKit
import SnapticKit

/// Main display, arrangement and mirroring (PLAN §9.6). Origins and main are low risk;
/// mirroring is a trial with `.forSession` scope.
@MainActor final class ArrangementController: DisplayFeatureController, DisplayMenuContributor, DiagnosticsContributor {
    static var id: DisplayControllerID { .arrangement }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var changes = 0

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.menus.register(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Arrangement"), lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        context?.requestMenuRebuild()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {}

    func stop() {
        lifetime = nil
        context = nil
        effective = []
    }

    // MARK: Changes

    private func submit(_ request: TransactionRequest, completion: (@MainActor (TransactionOutcome) -> Void)? = nil) {
        guard let ctx = context, let lifetime else { return }
        ctx.connectPlanner.beginUserChange()
        ManagedTransactions.submit(ctx, request, lifetime: lifetime) { [weak self] outcome in
            let ok = outcome == .applied || outcome == .kept
            if ok { self?.changes += 1 }
            self?.context?.connectPlanner.endUserChange(changed: ok)
            completion?(outcome)
        }
    }

    /// Why a display can't become main, or nil (invariant 7).
    func setMainRefusal(_ key: DisplayKey) -> String? {
        guard let ctx = context, let d = ManagedDisplays.info(ctx, key: key) else { return L("Display not found") }
        if d.isMain { return L("Already the main display") }
        if !d.isActive || d.mirrorOf != nil { return L("Mirrored or disconnected displays can't be main") }
        let anyStrong = ctx.registry.displays.contains(where: \.isStronglyVisible)
        if anyStrong && !d.isStronglyVisible { return L("The main display must be a visible physical display") }
        return nil
    }

    func setMain(_ key: DisplayKey) {
        guard effective.contains(.mainDisplay), let ctx = context, let d = ManagedDisplays.info(ctx, key: key) else { return }
        if let why = setMainRefusal(key) {
            ctx.toasts.show(why, lifetime: lifetime)
            return
        }
        submit(TransactionRequest(label: L("Set main display"), risk: .low, changes: [.main(d.desktopID)]))
    }

    /// New origins from the canvas or the Position/Align form, normalized so main stays at (0, 0).
    func arrange(_ rects: [DisplayKey: ArrangeRect]) {
        guard effective.contains(.arrangement), let ctx = context else { return }
        guard let main = ctx.registry.displays.first(where: \.isMain)?.key else { return }
        let normalized = ArrangementMath.normalized(rects, main: main)
        guard ArrangementMath.isValid(Array(normalized.values)) else {
            ctx.toasts.show(L("Displays must touch and must not overlap"), lifetime: lifetime)
            return
        }
        var changes: [DisplayChange] = []
        for (key, r) in normalized.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let d = ManagedDisplays.info(ctx, key: key), d.isActive, d.mirrorOf == nil else { continue }
            let now = ManagedDisplays.rect(d)
            if now.x != r.x || now.y != r.y { changes.append(.origin(d.desktopID, x: r.x, y: r.y)) }
        }
        guard !changes.isEmpty else { return }
        submit(TransactionRequest(label: L("Arrange displays"), risk: .low, changes: changes))
    }

    /// Position/Align (16 placements) relative to another display.
    func place(_ key: DisplayKey, _ placement: ArrangementPlacement, relativeTo reference: DisplayKey) {
        guard let ctx = context, key != reference, let d = ManagedDisplays.info(ctx, key: key),
              let r = ManagedDisplays.info(ctx, key: reference) else { return }
        var rects = currentRects()
        let o = ArrangementMath.origin(width: Int(d.bounds.width), height: Int(d.bounds.height),
                                       relativeTo: ManagedDisplays.rect(r), placement: placement)
        rects[key] = ManagedDisplays.rect(d).moved(x: o.x, y: o.y)
        arrange(rects)
    }

    func currentRects() -> [DisplayKey: ArrangeRect] {
        guard let ctx = context else { return [:] }
        var rects: [DisplayKey: ArrangeRect] = [:]
        for d in ctx.registry.displays where d.isActive && d.mirrorOf == nil { rects[d.key] = ManagedDisplays.rect(d) }
        return rects
    }

    /// Mirrors `key` onto `source` (nil stops mirroring). Mirroring is a trial (§4.3);
    /// stopping only restores visibility, so it is low (the classifier agrees).
    func mirror(_ key: DisplayKey, of source: DisplayKey?) {
        guard effective.contains(.mirroring), let ctx = context, let d = ManagedDisplays.info(ctx, key: key) else { return }
        var sourceID: UInt32?
        if let source {
            guard source != key, let s = ManagedDisplays.info(ctx, key: source), s.isActive else { return }
            sourceID = s.desktopID
        }
        if sourceID == nil && d.mirrorOf == nil { return }
        submit(TransactionRequest(label: sourceID == nil ? L("Stop mirroring") : L("Mirror display"),
                                  risk: sourceID == nil ? .low : .trial,
                                  changes: [.mirror(d.hardwareID, of: sourceID)], finalScope: .forSession))
    }

    /// ⌘ + brightness-down: mirror the target onto main, or stop.
    func toggleMirror(_ key: DisplayKey) {
        guard let ctx = context, let d = ManagedDisplays.info(ctx, key: key) else { return }
        if d.mirrorOf != nil {
            mirror(key, of: nil)
        } else if let main = ctx.registry.displays.first(where: { $0.isMain && $0.key != key }) {
            mirror(key, of: main.key)
        }
    }

    // MARK: Menu

    var descriptors: [DisplayMenuItemDescriptor] {
        var list = [DisplayMenuItemDescriptor(id: .dSetMain, title: L("Set as Main Display"), slot: .display, defaultVisibility: .inSubmenu),
                    DisplayMenuItemDescriptor(id: .dMirrorMenu, title: L("Mirroring"), slot: .display, defaultVisibility: .inSubmenu)]
        if effective.contains(.arrangement) {
            list.append(DisplayMenuItemDescriptor(id: .dArrange, title: L("Arrange…"), slot: .tools, defaultVisibility: .visible))
        }
        return list
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let ctx = context else { return [] }
        let key = display.key
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if effective.contains(.mainDisplay), !display.isMain, setMainRefusal(key) == nil {
            items.append((.dSetMain, ManagedMenuItem(L("Set as Main Display")) { [weak self] in self?.setMain(key) }))
        }
        if effective.contains(.mirroring) {
            var sub: [NSMenuItem] = []
            if display.mirrorOf != nil {
                sub.append(ManagedMenuItem(L("Stop Mirroring")) { [weak self] in self?.mirror(key, of: nil) })
            }
            for other in ManagedDisplays.all(ctx) where other.key != key && other.isActive && other.mirrorOf == nil {
                let on = display.mirrorOf == other.desktopID
                let source = other.key
                sub.append(ManagedMenuItem(L("Mirror \(other.name)"), on: on) { [weak self] in self?.mirror(key, of: source) })
            }
            if !sub.isEmpty { items.append((.dMirrorMenu, ManagedMenuItem.submenu(L("Mirroring"), items: sub))) }
        }
        return items
    }

    /// Tools › "Arrange…" opens the Arrangement page (PLAN §3.7 Tools list).
    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, effective.contains(.arrangement), let ctx = context else { return [] }
        weak var weakCtx = ctx
        return [(.dArrange, ManagedMenuItem(L("Arrange…")) { weakCtx?.openSettings("displays.arrangement") })]
    }

    // MARK: Actions / CLI

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: .dSetMain, title: L("Set as Main Display"), feature: .mainDisplay, cliAllowed: true) { [weak self] t in
            guard let self, let ctx = self.context, let d = ManagedDisplays.resolve(ctx, t).first else { return }
            self.setMain(d.key)
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .dMirrorToggle, title: L("Toggle Mirroring"), feature: .mirroring, cliAllowed: true) { [weak self] t in
            guard let self, let ctx = self.context, let d = ManagedDisplays.resolve(ctx, t).first else { return }
            self.toggleMirror(d.key)
        }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("main", policy: .low, offOnly: false, cliAllowed: true, summary: L("main <display>: set the main display"),
                              lifetime: lifetime) { [weak self] req in
            guard let self, let ctx = self.context, self.effective.contains(.mainDisplay) else {
                return .failure(ControlExit.unavailable, L("Main display control is off"))
            }
            guard let sel = req.arguments.first else { return .failure(ControlExit.usage, L("Usage: main <display>")) }
            let pick = ManagedDisplays.cliSelectOne(ctx, sel)
            if let error = pick.error { return error }
            guard let d = pick.display else { return .failure(ControlExit.notFound, "") }
            if let why = self.setMainRefusal(d.key) { return .failure(ControlExit.refused, why) }
            return ManagedTransactions.response(await ManagedTransactions.run(
                ctx, TransactionRequest(label: L("Set main display"), risk: .low, changes: [.main(d.desktopID)],
                                        skipConfirmation: req.skipConfirmation)))
        }
        ctx.commands.register("arrange", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("arrange <display> <x> <y> | arrange <display> <placement> <reference>"),
                              lifetime: lifetime) { [weak self] req in
            guard let self, let ctx = self.context, self.effective.contains(.arrangement) else {
                return .failure(ControlExit.unavailable, L("Arrangement is off"))
            }
            let a = req.arguments
            guard a.count == 3 else {
                return .failure(ControlExit.usage, L("Usage: arrange <display> <x> <y> | <placement> <reference>"))
            }
            let pick = ManagedDisplays.cliSelectOne(ctx, a[0])
            if let error = pick.error { return error }
            guard let d = pick.display else { return .failure(ControlExit.notFound, "") }
            var rects = self.currentRects()
            if let x = Int32(a[1]), let y = Int32(a[2]) {
                rects[d.key] = ManagedDisplays.rect(d).moved(x: x, y: y)
            } else if let p = ArrangementPlacement.allCases.first(where: { $0.rawValue.lowercased() == a[1].lowercased() }) {
                let ref = ManagedDisplays.cliSelectOne(ctx, a[2])
                if let error = ref.error { return error }
                guard let r = ref.display, r.key != d.key else {
                    return .failure(ControlExit.usage, L("The reference must be another display"))
                }
                let o = ArrangementMath.origin(width: Int(d.bounds.width), height: Int(d.bounds.height),
                                               relativeTo: ManagedDisplays.rect(r), placement: p)
                rects[d.key] = ManagedDisplays.rect(d).moved(x: o.x, y: o.y)
            } else {
                return .failure(ControlExit.usage, L("Placements: ") + ArrangementPlacement.allCases.map(\.rawValue).joined(separator: ", "))
            }
            guard let main = ctx.registry.displays.first(where: \.isMain)?.key else { return .failure(ControlExit.notFound, "") }
            let normalized = ArrangementMath.normalized(rects, main: main)
            guard ArrangementMath.isValid(Array(normalized.values)) else {
                return .failure(ControlExit.refused, L("Displays must touch and must not overlap"))
            }
            let changes: [DisplayChange] = normalized.compactMap { k, r in
                ManagedDisplays.info(ctx, key: k).flatMap { (info: DisplayInfo) -> DisplayChange? in
                    let now = ManagedDisplays.rect(info)
                    return now.x == r.x && now.y == r.y ? nil : DisplayChange.origin(info.desktopID, x: r.x, y: r.y)
                }
            }
            guard !changes.isEmpty else { return .ok() }
            return ManagedTransactions.response(await ManagedTransactions.run(
                ctx, TransactionRequest(label: L("Arrange displays"), risk: .low, changes: changes,
                                        skipConfirmation: req.skipConfirmation)))
        }
        ctx.commands.register("mirror", policy: .trial, offOnly: false, cliAllowed: true,
                              summary: L("mirror <display> <source>|off"), lifetime: lifetime) { [weak self] req in
            guard let self, let ctx = self.context, self.effective.contains(.mirroring) else {
                return .failure(ControlExit.unavailable, L("Mirroring is off"))
            }
            let a = req.arguments
            guard a.count == 2 else { return .failure(ControlExit.usage, L("Usage: mirror <display> <source>|off")) }
            let pick = ManagedDisplays.cliSelectOne(ctx, a[0])
            if let error = pick.error { return error }
            guard let d = pick.display else { return .failure(ControlExit.notFound, "") }
            var source: UInt32?
            if a[1].lowercased() != "off" {
                let src = ManagedDisplays.cliSelectOne(ctx, a[1])
                if let error = src.error { return error }
                guard let s = src.display, s.key != d.key else {
                    return .failure(ControlExit.usage, L("A display can't mirror itself"))
                }
                source = s.desktopID
            }
            return ManagedTransactions.response(await ManagedTransactions.run(
                ctx, TransactionRequest(label: source == nil ? L("Stop mirroring") : L("Mirror display"),
                                        risk: source == nil ? .low : .trial, changes: [.mirror(d.hardwareID, of: source)],
                                        finalScope: .forSession, skipConfirmation: req.skipConfirmation)))
        }
    }

    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [] }
        var rows: [(String, String)] = [(L("Changes this session"), String(changes))]
        for d in ctx.registry.displays {
            let r = ManagedDisplays.rect(d)
            rows.append((d.name, "\(r.x),\(r.y) \(r.width)×\(r.height)" + (d.isMain ? " main" : "")
                         + (d.mirrorOf != nil ? " mirrored" : "")))
        }
        return rows
    }
}
