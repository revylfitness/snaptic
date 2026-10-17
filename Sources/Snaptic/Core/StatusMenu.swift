import AppKit
import SnapticKit

/// A menu item that runs a closure (no target object needed).
@MainActor final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire() { handler() }
}

/// The status items (PLAN §3.5): one shared item and/or one per module, per
/// ModulesConfig. Rebuilds are deferred: a dirty flag per menu, rebuilt in
/// `menuNeedsUpdate`, never mutated in `menuDidClose` (R3C §5.6, R4C §4.6). A right-click
/// on the shared item opens the quick menu.
@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    @MainActor private final class Slot {
        let item: NSStatusItem
        let menu = NSMenu()
        let module: ModuleID?
        var dirty = true
        var showingQuick = false

        init(item: NSStatusItem, module: ModuleID?) {
            self.item = item
            self.module = module
        }
    }

    private weak var host: ModuleHost?
    private var shared: Slot?
    private var own: [ModuleID: Slot] = [:]
    private var openMenus = 0
    private var planPending = false
    private var screenToken: NSObjectProtocol?

    init(host: ModuleHost) {
        self.host = host
        super.init()
    }

    func install() {
        if screenToken == nil {
            screenToken = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPlan() }
            }
        }
        applyPlan()
    }

    /// True when no status item is visible (a relaunch then opens Settings).
    var hasVisibleItem: Bool {
        (shared?.item.isVisible ?? false) || own.values.contains { $0.item.isVisible }
    }

    /// Creates, updates or removes status items to match the plan. Deferred while a menu
    /// is open.
    func applyPlan() {
        guard let host else { return }
        if openMenus > 0 {
            planPending = true
            return
        }
        planPending = false
        let config = host.modulesStore.value
        let plan = config.statusItemPlan(running: host.runningModules)

        if plan.showShared {
            let slot = shared ?? makeSlot(module: nil)
            shared = slot
            setIcon(slot, symbol: MenuPlacement.sharedSymbol(in: config), label: L("Snaptic"))
        } else if let slot = shared {
            NSStatusBar.system.removeStatusItem(slot.item)
            shared = nil
        }

        for (id, slot) in own where !plan.ownIcon.contains(id) {
            NSStatusBar.system.removeStatusItem(slot.item)
            own[id] = nil
        }
        let external = MenuPlacement.hasExternalDisplay
        for id in plan.ownIcon {
            let slot = own[id] ?? makeSlot(module: id)
            own[id] = slot
            let module = host.module(id)
            setIcon(slot, symbol: MenuPlacement.symbol(for: module, in: config), label: module.title)
            slot.item.isVisible = !(config.preferences(id).hideWithoutExternalDisplay && !external)
        }
        requestRebuild()
    }

    /// Marks every menu dirty; each rebuilds when it next opens.
    func requestRebuild() {
        shared?.dirty = true
        for slot in own.values { slot.dirty = true }
    }

    func remove() {
        for slot in own.values { NSStatusBar.system.removeStatusItem(slot.item) }
        own = [:]
        if let shared { NSStatusBar.system.removeStatusItem(shared.item) }
        shared = nil
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        host?.permissions.refresh()
        guard let slot = slot(for: menu) else { return }
        let event = NSApp.currentEvent
        let quick = slot.module == nil && (event?.type == .rightMouseDown || event?.type == .rightMouseUp
            || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true))
        guard slot.dirty || quick != slot.showingQuick else { return }
        if quick { buildQuick(slot) } else { build(slot) }
        slot.showingQuick = quick
        slot.dirty = false
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus += 1
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus = max(0, openMenus - 1)
        // Nothing structural here: the chosen item's action hasn't run yet (R3C §5.6).
        if planPending && openMenus == 0 {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.applyPlan() }
            }
        }
    }

    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        false   // AppKit's key-equivalent scans must not trigger rebuilds
    }

    // MARK: Building

    private func makeSlot(module: ModuleID?) -> Slot {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let slot = Slot(item: item, module: module)
        slot.menu.delegate = self
        slot.menu.autoenablesItems = false
        item.menu = slot.menu
        return slot
    }

    private func setIcon(_ slot: Slot, symbol: String, label: String) {
        guard let button = slot.item.button else { return }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: MenuPlacement.defaultSharedSymbol, accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityLabel(label)
    }

    private func slot(for menu: NSMenu) -> Slot? {
        if shared?.menu === menu { return shared }
        return own.values.first { $0.menu === menu }
    }

    private func build(_ slot: Slot) {
        let menu = slot.menu
        menu.removeAllItems()
        guard let host else { return }
        let config = host.modulesStore.value
        let plan = config.statusItemPlan(running: host.runningModules)

        if host.safeMode.isActive {
            let banner = NSMenuItem(title: L("Safe Mode is on"), action: nil, keyEquivalent: "")
            banner.isEnabled = false
            menu.addItem(banner)
            menu.addItem(ClosureMenuItem(title: L("Leave Safe Mode")) { [weak host] in
                host?.relauncher.relaunch(reason: "leave safe mode")
            })
            menu.addItem(.separator())
        }

        let ids: [ModuleID]
        if let module = slot.module {
            ids = [module]
        } else {
            ids = plan.shared
        }
        if slot.module == nil && plan.noModulesEnabled {
            menu.addItem(ClosureMenuItem(title: L("No modules enabled — Open Settings…")) { [weak host] in
                host?.openSettings(page: GeneralPages.modulesID)
            })
            menu.addItem(.separator())
        }
        for (index, id) in ids.enumerated() {
            let module = host.module(id)
            let items = module.menuSection()
            if ids.count > 1 { menu.addItem(NSMenuItem.sectionHeader(title: module.title)) }
            for item in items { menu.addItem(item) }
            if index < ids.count - 1 || !items.isEmpty { menu.addItem(.separator()) }
        }
        addFooter(menu, host: host, config: config, includeUpgrade: slot.module == nil || plan.shared.isEmpty)
    }

    /// Right-click: Settings, the Displays quick items (Connect All, Redetect, Restore All
    /// Displays…), Quit.
    private func buildQuick(_ slot: Slot) {
        let menu = slot.menu
        menu.removeAllItems()
        guard let host else { return }
        menu.addItem(ClosureMenuItem(title: L("Settings…"), keyEquivalent: ",") { [weak host] in host?.openSettings() })
        if let registry = host.displays.pageEnvironment.context?.menus {
            let defaults = Dictionary(registry.descriptors.map { ($0.id, $0.defaultVisibility) }, uniquingKeysWith: { a, _ in a })
            let menu = host.displaysStore.value.menu
            let items = registry.globalItems(slot: .quick) { id in
                menu.visibility(of: id, default: defaults[id] ?? .visible)
            }
            let all = items.visible + items.more
            if !all.isEmpty {
                menu.addItem(.separator())
                for item in all { menu.addItem(item) }
            }
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Quit Snaptic"), keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    private func addFooter(_ menu: NSMenu, host: ModuleHost, config: ModulesConfig, includeUpgrade: Bool) {
        if includeUpgrade && config.showNewDisplaysCard && !config.isEnabled(.displays) {
            menu.addItem(ClosureMenuItem(title: L("More display features…")) { [weak host] in
                host?.openSettings(page: GeneralPages.modulesID)
            })
        }
        let recent = host.toasts.recent
        if !recent.isEmpty {
            let item = NSMenuItem(title: L("Recent Notices"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for text in recent.reversed() {
                let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                row.isEnabled = false
                submenu.addItem(row)
            }
            submenu.addItem(.separator())
            submenu.addItem(ClosureMenuItem(title: L("Clear")) { [weak host] in host?.toasts.clearRecent() })
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.addItem(ClosureMenuItem(title: L("Settings…"), keyEquivalent: ",") { [weak host] in host?.openSettings() })
        menu.addItem(ClosureMenuItem(title: L("Quit Snaptic"), keyEquivalent: "q") { NSApp.terminate(nil) })
    }
}
