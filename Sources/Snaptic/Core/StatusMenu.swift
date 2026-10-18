import AppKit
import Combine
import SnapticKit

/// A menu item that runs a closure (0.2 factory). New code uses `MenuKit`; this stays for the 0.2 contributors
/// until they move to MenuKit and it is deleted at the 0.3 step-3 exit (PLAN 0.3 §5.1).
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

/// The status items (PLAN 0.3 §5.2): the Snaptic item, one item per module shown on its own, and the items modules
/// build themselves (`StatusItemProvider`, Awake), all from the Kit plan (`ModulesConfig.statusItemPlan`).
///
/// - The plan is applied in one turn: the host-built items change and every provider's `applyStatusItem` runs
///   before `applyPlan` returns, so the plan and the items never disagree (code R2-M6). While one of these menus is
///   open the plan waits for it to close.
/// - Menus are rebuilt in `menuNeedsUpdate` when dirty, never in `menuDidClose` (the chosen item's action hasn't
///   run yet); every item comes from MenuKit, sections are separated by one separator, and "Settings…" then
///   "Quit" come last.
/// - No right-click menu, hover, programmatic highlight or occlusion dependence (C3; macOS 27 delivers none of
///   them reliably). Each item has a plain `NSMenu` and a stable autosave name, so the system and the user can
///   place and hide items independently; everything is also reachable from Settings, shortcuts and the CLI, and
///   opening Snaptic again shows Settings (§5.5).
@MainActor final class StatusMenu: NSObject, NSMenuDelegate, ControlDeclaring {
    typealias Controls = StatusMenuControls

    /// Autosave names: positions and visibility are remembered per item (the Awake item has its own, G's).
    static let sharedAutosaveName = "Snaptic"
    static func autosaveName(_ id: ModuleID) -> String { "Snaptic." + id.rawValue }

    @MainActor private final class Slot {
        let item: NSStatusItem
        let menu = NSMenu()
        let module: ModuleID?
        var dirty = true

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
    private var sinks: [AnyCancellable] = []
    /// The plan last applied (nil before `install`).
    private(set) var plan: StatusItemPlan?
    /// What the providers were last told about Recent Notices.
    private var providerNotices = false

    init(host: ModuleHost) {
        self.host = host
        super.init()
    }

    func install() {
        guard let host else { return }
        if screenToken == nil {
            // An external display connecting or going away changes Displays' Show When Active.
            screenToken = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPlan() }
            }
        }
        if sinks.isEmpty {
            // AwakeHost.requestStatusPlan re-plans in the same turn; these keep the plan right whatever path changed
            // Awake's state or the Keep Awake shortcut.
            host.awake.runtime.$governing
                .map { $0 != .inactive }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyPlan() } }
                .store(in: &sinks)
            host.awakeStore.$value
                .map { MenuLayout.awakeShortcutBound($0.shortcuts) }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyPlan() } }
                .store(in: &sinks)
        }
        applyPlan()
    }

    /// False when no status item shows (a relaunch then opens Settings). Provider items count (code B3). From
    /// macOS 27 `isVisible` isn't enough (the system can hide items itself), so the item's window must be on
    /// screen too (W16); unknown counts as hidden, so Settings opens rather than nothing.
    var hasVisibleItem: Bool {
        var items = [shared?.item].compactMap { $0 } + own.values.map(\.item)
        if let host {
            items += host.modules.compactMap { ($0 as? StatusItemProvider)?.statusItem }
        }
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return items.contains { item in
            HostUIRules.statusItemShows(isVisible: item.isVisible, osMajor: osMajor,
                                        windowOnScreen: Self.windowOnScreen(item))
        }
    }

    private static func windowOnScreen(_ item: NSStatusItem) -> Bool? {
        guard let window = item.button?.window else { return nil }
        let frame = window.frame
        guard frame.width > 0, frame.height > 0, window.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    // MARK: Plan

    /// The plan for the current state: running modules, Awake governing, an external display, the Keep Awake
    /// shortcut, and whether the Snaptic item exists now (a session never removes an item shown at rest).
    private func currentPlan(_ host: ModuleHost) -> StatusItemPlan {
        host.modulesStore.value.statusItemPlan(
            running: host.runningModules,
            awakeActive: host.awake.runtime.governing != .inactive,
            displaysActive: MenuPlacement.hasExternalDisplay,
            awakeShortcutBound: MenuLayout.awakeShortcutBound(host.awakeStore.value.shortcuts),
            sharedExistsNow: shared != nil)
    }

    /// Creates, updates or removes every status item to match the plan, providers included, in this turn.
    /// Deferred while one of these menus is open.
    func applyPlan() {
        guard let host else { return }
        if openMenus > 0 {
            planPending = true
            return
        }
        planPending = false
        let config = host.modulesStore.value
        let plan = currentPlan(host)
        self.plan = plan

        if plan.showShared {
            let slot = shared ?? makeSlot(module: nil, autosaveName: Self.sharedAutosaveName)
            shared = slot
            setIcon(slot, symbol: MenuPlacement.sharedSymbol(in: config), label: L("Snaptic"),
                    active: plan.sharedActiveGlyph)
        } else if let slot = shared {
            NSStatusBar.system.removeStatusItem(slot.item)
            shared = nil
        }

        for (id, slot) in own where !plan.ownIcon.contains(id) {
            NSStatusBar.system.removeStatusItem(slot.item)
            own[id] = nil
        }
        for id in plan.ownIcon {
            let slot = own[id] ?? makeSlot(module: id, autosaveName: Self.autosaveName(id))
            own[id] = slot
            let module = host.module(id)
            setIcon(slot, symbol: MenuPlacement.symbol(for: module, in: config), label: module.title, active: false)
        }

        applyProviderRows(plan, config: config, host: host)
        requestRebuild()
    }

    /// Every provider learns what its item should be (also modules that don't run: their item goes away).
    private func applyProviderRows(_ plan: StatusItemPlan, config: ModulesConfig, host: ModuleHost) {
        let notices = !host.toasts.recent.isEmpty
        providerNotices = notices
        for module in host.modules {
            guard let provider = module as? StatusItemProvider else { continue }
            provider.applyStatusItem(CustomItemRow(exists: plan.custom.contains(module.id),
                                                   presence: config.presence(module.id),
                                                   footer: plan.sharedFooterInOwnMenus, recentNotices: notices))
        }
    }

    /// Marks every menu dirty; each rebuilds when it next opens. Providers whose footer shows Recent Notices hear
    /// about notices appearing or going away.
    func requestRebuild() {
        shared?.dirty = true
        for slot in own.values { slot.dirty = true }
        guard let host, let plan, openMenus == 0, !planPending,
              (!host.toasts.recent.isEmpty) != providerNotices else { return }
        applyProviderRows(plan, config: host.modulesStore.value, host: host)
    }

    func remove() {
        sinks.removeAll()
        for slot in own.values { NSStatusBar.system.removeStatusItem(slot.item) }
        own = [:]
        if let shared { NSStatusBar.system.removeStatusItem(shared.item) }
        shared = nil
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
        plan = nil
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        host?.permissions.refresh()
        guard let slot = slot(for: menu), slot.dirty else { return }
        build(slot)
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

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        MenuKit.menu(menu, willHighlight: item)
    }

    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        false   // AppKit's key-equivalent scans must not trigger rebuilds
    }

    // MARK: Items

    private func makeSlot(module: ModuleID?, autosaveName: String) -> Slot {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        // The autosave name can restore "hidden" from an earlier removal; a planned item is always shown.
        item.isVisible = true
        let slot = Slot(item: item, module: module)
        slot.menu.delegate = self
        slot.menu.autoenablesItems = false
        item.menu = slot.menu
        return slot
    }

    /// The template glyph; `active` (N11: Awake governs) uses the `.fill` variant, or the glyph with a dot, and
    /// says so in the accessibility label.
    private func setIcon(_ slot: Slot, symbol: String, label: String, active: Bool) {
        guard let button = slot.item.button else { return }
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: MenuPlacement.defaultSharedSymbol, accessibilityDescription: label)
        var image = base
        if active, let base {
            image = NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: label) ?? Self.badged(base)
        }
        image?.isTemplate = true
        button.image = image
        let spoken = active ? label + L(", keeping your Mac awake") : label
        button.setAccessibilityLabel(spoken)
        button.toolTip = spoken
    }

    /// The glyph with a small dot at its lower trailing corner, cut free of the glyph (template image).
    private static func badged(_ base: NSImage) -> NSImage {
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let d = max(4, min(size.width, size.height) * 0.36)
            let dot = NSRect(x: rect.maxX - d, y: rect.minY, width: d, height: d)
            if let context = NSGraphicsContext.current {
                context.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                context.compositingOperation = .sourceOver
            }
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func slot(for menu: NSMenu) -> Slot? {
        if shared?.menu === menu { return shared }
        return own.values.first { $0.menu === menu }
    }

    // MARK: Building

    private func build(_ slot: Slot) {
        let menu = slot.menu
        menu.removeAllItems()
        guard let host else { return }
        let config = host.modulesStore.value
        let plan = self.plan ?? currentPlan(host)

        var groups: [[NSMenuItem]] = []
        if host.safeMode.isActive { groups.append(safeModeRows(host)) }
        if let id = slot.module {
            groups.append(section(id, host: host, header: false))
            groups.append(ownFooter(id, host: host, config: config, plan: plan))
        } else {
            if plan.noModulesEnabled {
                groups.append([MenuKit.status(L("No Modules Are On"), control: ControlID("menu.snaptic.noModules"))])
            }
            for id in plan.shared {
                // The compact Awake section has no header (§5.4).
                groups.append(section(id, host: host, header: id != .awake))
            }
            groups.append(sharedFooter(host: host, config: config, plan: plan))
        }

        for group in groups where !group.isEmpty {
            if !menu.items.isEmpty { menu.addItem(MenuKit.separator()) }
            for item in group { menu.addItem(item) }
        }
        menu.minimumWidth = MenuKit.hasCustomRows(menu) ? MenuKit.width : 0
    }

    private func safeModeRows(_ host: ModuleHost) -> [NSMenuItem] {
        [
            MenuKit.status(L("Safe Mode is on"), control: ControlID("menu.snaptic.safeMode")),
            MenuKit.action(L("Leave Safe Mode…"), control: ControlID("menu.snaptic.leaveSafeMode")) { [weak host] in
                host?.relauncher.relaunch(reason: "leave safe mode")
            },
        ]
    }

    /// A module's section without leading, trailing or doubled separators; empty when it has nothing to show.
    private func section(_ id: ModuleID, host: ModuleHost, header: Bool) -> [NSMenuItem] {
        let module = host.module(id)
        var items: [NSMenuItem] = []
        for item in module.menuSection() where !(item.isSeparatorItem && (items.last?.isSeparatorItem ?? true)) {
            items.append(item)
        }
        while items.last?.isSeparatorItem == true { items.removeLast() }
        guard !items.isEmpty else { return [] }
        guard header else { return items }
        return [MenuKit.header(module.title, control: ControlID("menu.snaptic.sectionHeader"))] + items
    }

    /// Snaptic item footer: the upgrade item, Recent Notices ›, Snaptic Settings…, Quit Snaptic.
    private func sharedFooter(host: ModuleHost, config: ModulesConfig, plan: StatusItemPlan) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let upgrade = upgradeItem(host: host, config: config) { items.append(upgrade) }
        if let notices = recentNotices(host) { items.append(notices) }
        let page = plan.noModulesEnabled ? GeneralPages.modulesID : nil
        items.append(MenuKit.settings(L("Snaptic Settings…"), control: ControlID("menu.snaptic.settings")) { [weak host] in
            host?.openSettings(page: page)
        })
        items.append(MenuKit.quit(control: ControlID("menu.snaptic.quit")))
        return items
    }

    /// Own-icon footer: "<Module> Settings…", then (Snaptic item absent) the upgrade item, Recent Notices › and
    /// Quit Snaptic (§5.2).
    private func ownFooter(_ id: ModuleID, host: ModuleHost, config: ModulesConfig, plan: StatusItemPlan) -> [NSMenuItem] {
        let module = host.module(id)
        let page = module.settingsPages().first?.id ?? id.rawValue
        var items = [MenuKit.settings(module.title + L(" Settings…"), control: ControlID("menu.snaptic.moduleSettings")) { [weak host] in
            host?.openSettings(page: page)
        }]
        guard plan.sharedFooterInOwnMenus else { return items }
        if let upgrade = upgradeItem(host: host, config: config) { items.append(upgrade) }
        if let notices = recentNotices(host) { items.append(notices) }
        items.append(MenuKit.quit(control: ControlID("menu.snaptic.quit")))
        return items
    }

    /// 0.2's "More display features…" for upgraders who haven't turned Displays on (the General card's twin).
    private func upgradeItem(host: ModuleHost, config: ModulesConfig) -> NSMenuItem? {
        guard !config.isEnabled(.displays),
              config.showNewDisplaysCard || config.newModuleCards.contains(.displays) else { return nil }
        return MenuKit.action(L("More Display Features…"), control: ControlID("menu.snaptic.upgrade")) { [weak host] in
            host?.openSettings(page: GeneralPages.modulesID)
        }
    }

    private func recentNotices(_ host: ModuleHost) -> NSMenuItem? {
        let recent = host.toasts.recent
        guard !recent.isEmpty else { return nil }
        var rows = recent.reversed().map { MenuKit.status($0, control: ControlID("menu.snaptic.notice")) }
        rows.append(MenuKit.separator())
        rows.append(MenuKit.action(L("Clear"), control: ControlID("menu.snaptic.clearNotices")) { [weak host] in
            host?.toasts.clearRecent()
        })
        return MenuKit.submenu(L("Recent Notices"), control: ControlID("menu.snaptic.recentNotices"), rows)
    }
}
