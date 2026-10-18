import AppKit
import SwiftUI
import SnapticKit

/// The always-on overview controller (PLAN §2.1 `overview`, R5.8): registers the
/// "Show Displays panel", Identify and Redetect actions (menu Tools items, quick-menu
/// item, shortcuts, CLI verbs) and owns the floating Displays panel and the Identify labels.
@MainActor final class OverviewController: DisplayFeatureController, DisplayMenuContributor, DiagnosticsContributor,
    SessionParticipant {
    static var id: DisplayControllerID { .overview }
    static var privateSymbols: [PrivateSymbol] { [] }

    static let showPanelAction = DisplayActionID(rawValue: "f.showPanel")
    static let identifyAction = DisplayActionID(rawValue: "f.identify")
    static let redetectAction = DisplayActionID(rawValue: "f.redetect")
    static let identifyItem = DisplayMenuItemID(rawValue: "f.tools.identify")
    static let redetectItem = DisplayMenuItemID(rawValue: "f.tools.redetect")
    static let panelItem = DisplayMenuItemID(rawValue: "f.tools.panel")
    static let quickRedetectItem = DisplayMenuItemID(rawValue: "f.quick.redetect")

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var hotkeyLifetime: Lifetime?
    private var hotkeyProblems: [String] = []
    private let panel = DisplaysPanelController()
    private let identifyOverlay = IdentifyOverlay()

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        panel.owner = self
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        context.menus.register(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Displays menu and panel"), lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        registerHotkeys(context.config.value.menu, announce: false)
        lifetime.onEnd { [weak self] in self?.closeUI() }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {}

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.menu.showPanelShortcut != new.menu.showPanelShortcut || old.menu.identifyShortcut != new.menu.identifyShortcut {
            registerHotkeys(new.menu, announce: true)
        }
    }

    func stop() {
        closeUI()
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        hotkeyProblems = []
        lifetime = nil
        context = nil
    }

    // MARK: SessionParticipant (locked or switched-out sessions get no floating UI)

    func sessionDidPause() { closeUI() }
    func sessionDidResume() {}

    private func closeUI() {
        panel.close()
        identifyOverlay.dismiss(animated: false)
    }

    // MARK: Registrations

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: Self.showPanelAction, title: L("Show Displays Panel"), feature: .overview,
                                    cliAllowed: true) { [weak self] _ in self?.togglePanel() }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.identifyAction, title: L("Identify Displays"), feature: .overview,
                                    cliAllowed: true) { [weak self] _ in _ = self?.identifyDisplays() }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.redetectAction, title: L("Redetect Displays"), feature: .overview,
                                    cliAllowed: true) { [weak self] _ in self?.redetect() }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("identify", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Show each display's number and name for 3 seconds"),
                              lifetime: lifetime) { [weak self] _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Displays isn't running")) }
            let count = self.identifyDisplays()
            return .ok(L("Identifying \(count) displays"))
        }
        ctx.commands.register("redetect", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Look for connected displays again"), lifetime: lifetime) { [weak self] _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Displays isn't running")) }
            self.redetect()
            return .ok(L("Looking for displays"))
        }
    }

    private func registerHotkeys(_ menu: MenuConfig, announce: Bool) {
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        hotkeyProblems = []
        guard let ctx = context, let lifetime else { return }
        let life = lifetime.child()
        hotkeyLifetime = life
        let wanted: [(HotkeyCombo?, String, @MainActor () -> Void)] = [
            (menu.showPanelShortcut, L("Show Displays panel"), { [weak self] in self?.togglePanel() }),
            (menu.identifyShortcut, L("Identify displays"), { [weak self] in _ = self?.identifyDisplays() }),
        ]
        for (combo, owner, action) in wanted {
            guard let combo else { continue }
            do {
                _ = try ctx.hotkeys.register(combo, owner: owner, lifetime: life, action: action)
            } catch {
                let problem = "\(owner): \(Self.describe(error))"
                hotkeyProblems.append(problem)
                EventLog.shared.record(.keys, "Displays shortcut not registered: \(Self.describe(error))")
                if announce { ctx.toasts.show(problem, lifetime: lifetime) }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? GlobalHotkeys.RegisterError else { return L("the shortcut couldn't be registered") }
        switch error {
        case .conflict(let owner): return L("already used by \(owner)")
        case .systemRefused: return L("macOS refused the shortcut")
        case .notBuilt: return L("global shortcuts aren't available yet")
        case .invalid(let reason): return reason
        case .ended: return L("the feature stopped before the shortcut was registered")
        }
    }

    // MARK: Actions

    func togglePanel() {
        guard let ctx = context else { return }
        panel.toggle(context: ctx)
    }

    /// Shows the labels; returns how many displays were labeled.
    @discardableResult
    func identifyDisplays() -> Int {
        guard let ctx = context else { return 0 }
        let labels = Self.identifyLabels(ctx)
        identifyOverlay.show(labels)
        EventLog.shared.record(.registry, "Identify: \(labels.count) screens")
        return labels.count
    }

    /// Numbers follow the menu order (hidden displays included); mirrored displays share
    /// their source's screen. Falls back to NSScreen when the registry has nothing yet.
    static func identifyLabels(_ ctx: DisplaysContext) -> [IdentifyOverlay.Label] {
        let displays = DisplaysMenuBuilder.orderedDisplays(ctx, includeHidden: true).filter { $0.isOnline && $0.isActive }
        guard !displays.isEmpty else {
            return NSScreen.screens.enumerated().map { IdentifyOverlay.Label(number: "\($0.offset + 1)", name: $0.element.localizedName, screen: $0.element) }
        }
        var order: [UInt32] = []
        var groups: [UInt32: (screen: NSScreen, numbers: [String], names: [String])] = [:]
        for (index, display) in displays.enumerated() {
            let screenID = display.mirrorOf ?? display.desktopID
            guard let screen = NSScreen.screen(for: screenID) ?? NSScreen.screen(for: display.desktopID) else { continue }
            if groups[screenID] == nil {
                order.append(screenID)
                groups[screenID] = (screen, [], [])
            }
            groups[screenID]?.numbers.append("\(index + 1)")
            groups[screenID]?.names.append(display.name)
        }
        return order.compactMap { id in
            guard let g = groups[id] else { return nil }
            return IdentifyOverlay.Label(number: g.numbers.joined(separator: " · "), name: g.names.joined(separator: "\n"),
                                         screen: g.screen)
        }
    }

    func redetect() {
        guard let ctx = context else { return }
        ctx.registry.refresh()
        ctx.connectPlanner.trigger(.reconfigure)
        EventLog.shared.record(.registry, "Redetect requested")
        if let lifetime { ctx.toasts.show(L("Looking for displays…"), lifetime: lifetime) }
    }

    /// The display's full menu block, popped up at the pointer (the panel's "More" button).
    func popUpMenu(for display: DisplayInfo) {
        guard let ctx = context else { return }
        let items = DisplayMenuBlock(display: display, context: ctx, showHeader: false, forceExpanded: true).items()
        guard !items.isEmpty else { return }
        let menu = DisplayMenuBlock.menu(items, title: display.name)
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: DisplayMenuContributor

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: Self.identifyItem, title: L("Identify Displays"), slot: .tools, defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.redetectItem, title: L("Redetect Displays"), slot: .tools, defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.panelItem, title: L("Show Displays Panel"), slot: .tools, defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.quickRedetectItem, title: L("Redetect Displays"), slot: .quick, defaultVisibility: .visible),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        switch slot {
        case .tools:
            return [
                (Self.identifyItem, DisplayMenuBlock.actionItem(L("Identify Displays"), symbol: "number.square") { [weak self] in
                    _ = self?.identifyDisplays()
                }),
                (Self.redetectItem, redetectItem()),
                (Self.panelItem, DisplayMenuBlock.actionItem(L("Show Displays Panel"), symbol: "slider.horizontal.3") { [weak self] in
                    self?.togglePanel()
                }),
            ]
        case .quick:
            return [(Self.quickRedetectItem, redetectItem())]
        case .display, .header:
            return []
        }
    }

    private func redetectItem() -> NSMenuItem {
        DisplayMenuBlock.actionItem(L("Redetect Displays"), symbol: "arrow.triangle.2.circlepath") { [weak self] in
            self?.redetect()
        }
    }

    // MARK: DiagnosticsContributor

    func diagnostics() -> [(String, String)] {
        let menu = context?.config.value.menu ?? MenuConfig()
        return [
            ("Panel shortcut", menu.showPanelShortcut == nil ? "none" : "set"),
            ("Identify shortcut", menu.identifyShortcut == nil ? "none" : "set"),
            ("Shortcut problems", hotkeyProblems.isEmpty ? "none" : hotkeyProblems.joined(separator: "; ")),
            ("Panel open", panel.isVisible ? "yes" : "no"),
            ("Menu style", menu.compact ? "compact" : "expanded"),
            ("Section order", menu.orderedSections.map(\.rawValue).joined(separator: ", ")),
            ("Hidden displays", "\(menu.hiddenDisplays.count)"),
            ("Item overrides", "\(menu.items.values.count)"),
        ]
    }
}

// MARK: - Floating Displays panel (R5.8)

/// The floating Displays panel: the same live controls as the Overview page, opened at
/// the pointer by the "Show Displays panel" action or shortcut. On macOS 27 the status
/// item can be hidden in the overflow, so this is how the controls stay reachable.
/// Non-activating (Snaptic stays an accessory app); Escape or clicking elsewhere closes it.
@MainActor final class DisplaysPanelController: NSObject, NSWindowDelegate {
    weak var owner: OverviewController?
    private var panel: FloatingPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(context: DisplaysContext) {
        if isVisible { close() } else { show(context: context) }
    }

    func show(context: DisplaysContext) {
        close()
        let actions = DisplaysPanelActions(
            identify: { [weak self] in _ = self?.owner?.identifyDisplays() },
            redetect: { [weak self] in self?.owner?.redetect() },
            restoreAll: { [weak context] in context?.panic.panic(reason: L("Restore All Displays (Displays panel)")) },
            // B's registered Resume action (the same one its Tools item and the CLI use).
            resume: { [weak context] in _ = context?.actions.perform(PanicCoordinator.resumeActionID, on: .all) },
            settings: { [weak self, weak context] in
                self?.close()
                context?.openSettings("displays.overview")
            },
            showMore: { [weak self] display in self?.owner?.popUpMenu(for: display) },
            enable: { [weak context] feature in if let context { DisplayMenuBlock.enable(feature, context: context) } })
        let root = DisplaysPanelView(runtime: context.runtime, config: context.config, context: context, actions: actions)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                                  styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        panel.title = L("Displays")
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        panel.contentViewController = host
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        if size.width > 0, size.height > 0 { panel.setContentSize(size) }
        panel.setFrameOrigin(Self.origin(for: panel.frame.size, at: NSEvent.mouseLocation))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSAccessibility.post(element: panel, notification: .created)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { panel = nil }
    }

    /// Top-left corner at the pointer, kept inside the pointer's screen.
    static func origin(for size: NSSize, at point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = point.x - 24
        var y = point.y - size.height + 12
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    /// Becomes key without activating Snaptic, so sliders take the keyboard.
    final class FloatingPanel: NSPanel {
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }
}

struct DisplaysPanelActions {
    let identify: @MainActor () -> Void
    let redetect: @MainActor () -> Void
    let restoreAll: @MainActor () -> Void
    let resume: @MainActor () -> Void
    let settings: @MainActor () -> Void
    let showMore: @MainActor (DisplayInfo) -> Void
    let enable: @MainActor (DisplayFeature) -> Void
}

private struct DisplaysPanelView: View {
    @ObservedObject var runtime: DisplaysRuntimeState
    @ObservedObject var config: ConfigStore<DisplaysConfig>
    weak var context: DisplaysContext?
    let actions: DisplaysPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            banners
            if let ctx = context {
                let displays = DisplaysMenuBuilder.orderedDisplays(ctx)
                if displays.isEmpty {
                    Text(runtime.displays.isEmpty ? L("No displays detected") : L("All displays are hidden from the menu"))
                        .foregroundStyle(.secondary)
                } else if displays.count > 3 {
                    ScrollView { cards(displays, ctx) }.frame(height: 480)
                } else {
                    cards(displays, ctx)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button(L("Identify")) { actions.identify() }
                    .help(L("Show each display's number and name"))
                Button(L("Redetect")) { actions.redetect() }
                Spacer()
                Button(L("Restore All")) { actions.restoreAll() }
                    .help(L("Undo Snaptic's display changes (same as ⌃⌥⌘⎋)"))
                Button { actions.settings() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(L("Displays settings"))
                    .help(L("Displays settings"))
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cards(_ displays: [DisplayInfo], _ ctx: DisplaysContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(displays.enumerated()), id: \.element.key) { index, display in
                if index > 0 { Divider() }
                DisplayControlsCard(display: display, number: index + 1, runtime: runtime, context: ctx, compact: true,
                                    enableFeature: actions.enable, showMore: actions.showMore)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let ctx = context {
            if ctx.safeMode.isActive {
                Label(L("Safe Mode: display automation is off"), systemImage: "exclamationmark.shield")
                    .font(.caption)
            }
            if ctx.panic.isLatched {
                HStack {
                    Label(L("Display automation is paused"), systemImage: "pause.circle").font(.caption)
                    Spacer()
                    Button(L("Resume")) { actions.resume() }.controlSize(.small)
                }
            }
            let paused = ctx.otherApps.pausedDisplayFeatures
            if !paused.isEmpty {
                Label(DisplaysMenuBuilder.pauseReasons(paused, monitor: ctx.otherApps).first ?? L("Some features are paused"),
                      systemImage: "pause.circle")
                    .font(.caption)
            }
            if let reason = DisplaysMenuBuilder.unprotectedReason(ctx) {
                Label(L("Unprotected"), systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .help(reason)
                    .accessibilityValue(Text(reason))
            }
        }
    }
}
