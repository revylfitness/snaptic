import AppKit
import SwiftUI
import SnapticKit

/// The always-on overview controller (PLAN §2.1 `overview`, R5.8; 0.3 §5.6): registers the "Show Displays Panel",
/// Identify and Redetect actions (Display Tools items through `OverviewMenuItems`, CLI verbs) and owns the floating
/// Displays panel and the Identify labels. Their shortcuts are ordinary Displays shortcuts
/// (`keys.shortcuts[.fShowPanel]` / `[.fIdentify]`, migration M4), registered by `KeysController` like every other
/// action's (0.3 §4.4 #5). Its menu items live in `OverviewMenuItems`; the controller itself contributes none.
@MainActor final class OverviewController: DisplayFeatureController, DiagnosticsContributor, SessionParticipant {
    static var id: DisplayControllerID { .overview }
    static var privateSymbols: [PrivateSymbol] { [] }

    static let redetectAction = DisplayActionID(rawValue: "f.redetect")

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private let panel = DisplaysPanelController()
    private let identifyOverlay = IdentifyOverlay()
    private var menuItems: OverviewMenuItems?

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
        let items = OverviewMenuItems(context: context)
        items.owner = self
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Displays menu and panel"), lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        lifetime.onEnd { [weak self] in self?.closeUI() }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {}

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {}

    func stop() {
        closeUI()
        menuItems = nil
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
        ctx.actions.register(Action(id: .fShowPanel, title: L("Show Displays Panel"), feature: .overview,
                                    cliAllowed: true) { [weak self] _ in self?.togglePanel() }, lifetime: lifetime)
        ctx.actions.register(Action(id: .fIdentify, title: L("Identify Displays"), feature: .overview,
                                    cliAllowed: true) { [weak self] _ in _ = self?.identifyDisplays() }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.redetectAction, title: L("Redetect Displays"), feature: .overview,
                                    cliAllowed: true) { [weak self] _ in self?.redetect() }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("identify", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Show each display's number and name for 3 seconds"),
                              lifetime: lifetime) { [weak self] _, _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Displays isn't running")) }
            let count = self.identifyDisplays()
            return .ok(L("Identifying \(count) displays"))
        }
        ctx.commands.register("redetect", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Look for connected displays again"), lifetime: lifetime) { [weak self] _, _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Displays isn't running")) }
            self.redetect()
            return .ok(L("Looking for displays"))
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

    /// The display's menu content as a real NSMenu, popped up under the panel's "⋯" button (at the pointer when the
    /// button's view isn't known), so the panel never mixes its rows with menu items (0.3 §5.6).
    func popUpMenu(for display: DisplayInfo, at view: NSView?) {
        guard let ctx = context else { return }
        let items = DisplayMenuBlock(display: display, context: ctx, showHeader: false, forceExpanded: true).items()
        guard !items.isEmpty else { return }
        let menu = DisplayMenuBlock.menu(items, title: display.name)
        if let view, view.window != nil {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4), in: view)
        } else {
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    // MARK: DiagnosticsContributor

    func diagnostics() -> [(String, String)] {
        let config = context?.config.value
        let menu = config?.menu ?? MenuConfig()
        let shortcuts = config?.keys.shortcuts
        return [
            // Registered (and any problem reported) by KeysController, like every Displays shortcut.
            ("Panel shortcut", shortcuts?[.fShowPanel] == nil ? "none" : "set"),
            ("Identify shortcut", shortcuts?[.fIdentify] == nil ? "none" : "set"),
            ("Panel open", panel.isVisible ? "yes" : "no"),
            ("Menu style", menu.compact ? "compact" : "expanded"),
            ("Section order", menu.orderedSections.map(\.rawValue).joined(separator: ", ")),
            ("Hidden displays", "\(menu.hiddenDisplays.count)"),
            ("Item overrides", "\(menu.items.values.count)"),
        ]
    }
}

// MARK: - Floating Displays panel (R5.8)

/// The floating Displays panel (0.3 §5.6): the Displays root page's live rows (`DisplaysPanelContent`), opened at
/// the pointer by the "Show Displays Panel" action or shortcut. On macOS 26 and 27 the status item can be hidden or
/// in the overflow, so this is how the controls stay reachable. Non-activating (Snaptic stays an accessory app);
/// Escape or clicking elsewhere closes it.
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
            restoreAll: { [weak context] in context?.panic.panic(reason: L("Restore All Displays (Displays panel)")) },
            // B's registered Resume action (the same one its menu item and the CLI use).
            resume: { [weak context] in _ = context?.actions.perform(PanicCoordinator.resumeActionID, on: .all) },
            settings: { [weak self, weak context] in
                self?.close()
                context?.openSettings(SettingsRootID.displays)
            },
            showMore: { [weak self] display, view in self?.owner?.popUpMenu(for: display, at: view) })
        let host = NSHostingController(rootView: DisplaysPanelContent(context: context, actions: actions))
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
