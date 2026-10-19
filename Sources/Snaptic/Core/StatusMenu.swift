import AppKit
import Combine
import SnapticKit

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
/// - 0.3.1 Part A: with two or more modules the Snaptic item shows a tab bar and only the selected module's section
///   (`MenuTabs` decides; the choice is remembered). A tab click swaps exactly that section in the open menu, in the
///   control's action; everything else still waits for the next open. Host-level rows (Safe Mode, the B3.4 leftover
///   rows) head every menu above the tabs; the E1 update row sits in the footer above Snaptic Settings….
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
    /// What the providers were last told (Recent Notices, the leftover rows, the update row).
    private var providerFacts = ProviderFacts()
    /// The Snaptic item's menu is open (a ⌘n item's action may run while it still is: A3, HW-26).
    private var sharedMenuOpen = false

    // 0.3.1 A2: the tabbed Snaptic menu as built at its last open; empty or nil without tabs.
    /// The tabs, in `plan.shared` order.
    private var tabs: [ModuleID] = []
    /// The tab shown (the stored choice, or the first tab when that module isn't a tab now).
    private var selectedTab: ModuleID?
    private var tabBarItem: NSMenuItem?
    /// Exactly the items inserted for the selected section (a tab switch removes these and nothing else).
    private var sectionItems: [NSMenuItem] = []
    /// The separator above the footer: a switch inserts the new section before it.
    private var footerSeparator: NSMenuItem?
    /// The footer's Show … Tab items, in tab order (⌘1…⌘n).
    private var showTabItems: [NSMenuItem] = []

    private struct ProviderFacts: Equatable {
        var notices = false
        var leftover = false
        var update = false
    }

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
            // The Keep Awake shortcut: stored combo, registration failures, G's "registered now" flag, and Awake
            // running (its start registers the shortcut before `moduleState` turns `.running`).
            let runtime = host.awake.runtime
            Publishers.CombineLatest4(host.awakeStore.$value.map(\.shortcuts), runtime.$failedShortcuts,
                                      runtime.$keepAwakeRegistered, runtime.$moduleState.map { $0 != .stopped })
                .map { (MenuLayout.awakeShortcutStatus($0, failed: $1, registered: $2), $3) }
                .removeDuplicates(by: ==)
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.applyAwakePresenceFallback()
                        self?.applyPlan()
                    }
                }
                .store(in: &sinks)
            // Awake set to Don't Show by a path that skips the Menu Bar page's check (backup import, outside write).
            host.modulesStore.$value
                .map { $0.isEnabled(.awake) && $0.presence(.awake) == .hidden }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyAwakePresenceFallback() } }
                .store(in: &sinks)
            // Menus are built when they open, so any change to what they show only marks them dirty (rebuilds are
            // lazy): every Awake runtime change (keeps the display on, holds, preset, rules paused…), Awake's
            // settings (sessions, rules, default preset) and Displays' settings (Customize Displays Menu, hidden
            // displays, order, style; also the menu's own Show All Displays).
            host.awake.runtime.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.requestRebuild() } }
                .store(in: &sinks)
            host.awakeStore.$value
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.requestRebuild() } }
                .store(in: &sinks)
            host.displaysStore.$value
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.requestRebuild() } }
                .store(in: &sinks)
            // 0.3.1: the host-level rows. B3.4's leftover rows (LidRecovery) and E1's update row (the updater; lead
            // decision 3) are read when a menu is built, so a change marks every menu dirty and re-tells the providers.
            // The main-queue hop also lets `objectWillChange` land before the rows are read.
            host.lidRecovery.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.requestRebuild() } }
                .store(in: &sinks)
            host.updaterChanged
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.requestRebuild() } }
                .store(in: &sinks)
            // B1: the Snaptic glyph's N11 label says ", even with the lid closed" while lid-closed mode is on.
            host.awake.runtime.$lidMode
                .map(\.isOn)
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyPlan() } }
                .store(in: &sinks)
        }
        applyAwakePresenceFallback()
        applyPlan()
    }

    /// The Don't Show fallback (§5.2, parity minor 11): Awake hidden while the Keep Awake shortcut isn't registered
    /// (unset, taken by another app or macOS, or Awake's shortcuts turned off) would leave no way to it in the menu
    /// bar, so it goes back to Show When Active and a toast says why. Never while Awake doesn't run (off, or turned
    /// off by a defaults setting: it shows nothing then, ui N3).
    private func applyAwakePresenceFallback() {
        guard let host else { return }
        let status = awakeShortcutStatus(host)
        guard let presence = host.modulesStore.value.awakePresenceFallback(awakeRunning: awakeRuns(host),
                                                                           awakeShortcutBound: status.isBound)
        else { return }
        host.modulesStore.value.setPresence(presence, for: .awake)
        if let notice = MenuLayout.awakeFallbackNotice(status) { host.toasts.show(notice) }
    }

    /// Awake runs now (started, not turned off by a defaults setting); its shortcut registration is settled then.
    private func awakeRuns(_ host: ModuleHost) -> Bool {
        host.runningModules.contains(.awake) && host.awake.runtime.moduleState != .stopped
    }

    /// The Keep Awake shortcut as the menu bar sees it: registered only per G's runtime flag (code M1).
    private func awakeShortcutStatus(_ host: ModuleHost) -> MenuLayout.AwakeShortcutStatus {
        MenuLayout.awakeShortcutStatus(host.awakeStore.value.shortcuts, failed: host.awake.runtime.failedShortcuts,
                                       registered: host.awake.runtime.keepAwakeRegistered)
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
            awakeShortcutBound: awakeShortcutStatus(host).isBound,
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
            let ownIcons = plan.ownIcon.map { host.module($0) }
            setIcon(slot, symbol: MenuPlacement.sharedSymbol(in: config, ownIcons: ownIcons), label: L("Snaptic"),
                    active: plan.sharedActiveGlyph, lidClosed: host.awake.lidModeOn)
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
        let facts = providerFacts(plan, host: host)
        providerFacts = facts
        for module in host.modules {
            guard let provider = module as? StatusItemProvider else { continue }
            // The leftover and update rows come from StatusMenu's builders each time the provider's menu opens;
            // re-sending the row on a change to `facts` marks that menu for a rebuild.
            provider.applyStatusItem(CustomItemRow(exists: plan.custom.contains(module.id),
                                                   presence: config.presence(module.id),
                                                   footer: plan.sharedFooterInOwnMenus, recentNotices: facts.notices))
        }
    }

    /// What a provider's menu adds from the host: Recent Notices and the update row only with the shared footer
    /// (E1: own and Awake menus carry the update row only where they carry that footer); the leftover rows always.
    private func providerFacts(_ plan: StatusItemPlan, host: ModuleHost) -> ProviderFacts {
        ProviderFacts(notices: !host.toasts.recent.isEmpty,
                      leftover: host.lidRecovery.showsRows,
                      update: plan.sharedFooterInOwnMenus && host.updater?.availableUpdate != nil)
    }

    /// Marks every menu dirty; each rebuilds when it next opens. Providers hear about Recent Notices, the leftover
    /// rows or the update row appearing or going away.
    func requestRebuild() {
        shared?.dirty = true
        for slot in own.values { slot.dirty = true }
        guard let host, let plan, openMenus == 0, !planPending,
              providerFacts(plan, host: host) != providerFacts else { return }
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
        resetTabs()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        host?.permissions.refresh()
        guard let slot = slot(for: menu) else { return }
        if slot.dirty {
            build(slot)
            slot.dirty = false
        }
        // A3: Full Keyboard Access posts no change notification, so the Show … Tab items are re-checked on every
        // open; a property change, not a rebuild.
        if slot.module == nil { updateShowTabItems() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus += 1
        if menu === shared?.menu { sharedMenuOpen = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus = max(0, openMenus - 1)
        if menu === shared?.menu { sharedMenuOpen = false }
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

    /// A3: ⌘1…⌘n in the open Snaptic menu answer with that position's Show … Tab item. Everything else is false, as
    /// in 0.3: AppKit's key-equivalent scans must not trigger rebuilds (R4C §4.6), and this never builds anything.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        guard openMenus > 0, menu === shared?.menu, !showTabItems.isEmpty, event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let n = MenuTabs.keyIndex(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
                                        commandOnly: modifiers == .command, tabCount: showTabItems.count),
              showTabItems.indices.contains(n - 1) else { return false }
        let item = showTabItems[n - 1]
        target.pointee = item.target
        action.pointee = item.action
        return true
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
    /// says so in the accessibility label, with ", even with the lid closed" while lid-closed mode is on (B1).
    private func setIcon(_ slot: Slot, symbol: String, label: String, active: Bool, lidClosed: Bool = false) {
        guard let button = slot.item.button else { return }
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: MenuPlacement.defaultSharedSymbol, accessibilityDescription: label)
        var image = base
        if active, let base {
            image = NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: label) ?? Self.badged(base)
        }
        image?.isTemplate = true
        button.image = image
        var spoken = label
        if active {
            spoken += L(", keeping your Mac awake")
            if lidClosed { spoken += AwakeLidText.statusSuffix }
        }
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
        if slot.module == nil { resetTabs() }
        guard let host else { return }
        let config = host.modulesStore.value
        let plan = self.plan ?? currentPlan(host)

        var groups: [[NSMenuItem]] = []
        // The host safety group heads every menu, above any tabs (A1, B3.4).
        groups.append(hostSafetyRows(host))
        var minimumWidth: CGFloat?
        let tabs = slot.module == nil ? MenuTabs.tabs(plan: plan) : []
        if let id = slot.module {
            groups.append(section(id, host: host, header: false))
            groups.append(ownFooter(id, host: host, config: config, plan: plan))
        } else if !tabs.isEmpty {
            let stored = UserDefaults.standard.string(forKey: MenuTabs.defaultsKey)
            let selected = MenuTabs.selected(stored: stored, tabs: tabs) ?? tabs[0]
            // A2 width: the widest tab sets the minimum, so a switch never widens the open menu and the segment
            // never moves under the pointer.
            let width = max(MenuKit.width, widestSection(tabs, selected: selected, host: host, config: config,
                                                         plan: plan))
            minimumWidth = width
            let bar = tabBar(tabs, selected: selected, host: host, width: width)
            let items = tabSection(selected, host: host)
            showTabItems = makeShowTabItems(tabs, selected: selected, host: host)
            self.tabs = tabs
            selectedTab = selected
            tabBarItem = bar
            sectionItems = items
            groups.append([bar])
            groups.append(items)
            groups.append(sharedFooter(host: host, config: config, plan: plan, showTabItems: showTabItems))
        } else {
            if plan.noModulesEnabled {
                groups.append([MenuKit.status(L("No Modules Are On"), control: ControlID("menu.snaptic.noModules"))])
            }
            for id in plan.shared {
                // One module: its 0.3 section, with its header; the compact Awake section has none (§5.4).
                groups.append(section(id, host: host, header: id != .awake, compact: id == .awake))
            }
            groups.append(sharedFooter(host: host, config: config, plan: plan, showTabItems: []))
        }

        let nonEmpty = groups.filter { !$0.isEmpty }
        for (index, group) in nonEmpty.enumerated() {
            if !menu.items.isEmpty {
                let separator = MenuKit.separator()
                menu.addItem(separator)
                // The footer is always the last group: a tab switch inserts the new section above this separator.
                if index == nonEmpty.count - 1, !tabs.isEmpty { footerSeparator = separator }
            }
            for item in group { menu.addItem(item) }
        }
        menu.minimumWidth = minimumWidth ?? (MenuKit.hasCustomRows(menu) ? MenuKit.width : 0)
        if slot.module == nil { updateShowTabItems() }
    }

    /// Safe Mode's rows, then the B3.4 leftover rows: one group, first in every menu and above the tabs.
    private func hostSafetyRows(_ host: ModuleHost) -> [NSMenuItem] {
        (host.safeMode.isActive ? safeModeRows(host) : []) + Self.leftoverItems(host: host)
    }

    private func safeModeRows(_ host: ModuleHost) -> [NSMenuItem] {
        [
            MenuKit.status(L("Safe Mode Is On"), control: ControlID("menu.snaptic.safeMode")),
            // The same confirmation as General and Displays (ux N5): the ellipsis promises a question.
            MenuKit.action(L("Leave Safe Mode…"), control: ControlID("menu.snaptic.leaveSafeMode")) { [weak host] in
                guard let host else { return }
                SafeModeLeave.confirm(relauncher: host.relauncher)
            },
        ]
    }

    /// A module's section without leading, trailing or doubled separators; empty when it has nothing to show. The
    /// compact Awake section in the Snaptic item has no internal separators either (§5.4: the switch header's height
    /// sets the group apart). `tabbed`: the section for a tab (A4; Awake's full rows, style `tab`).
    private func section(_ id: ModuleID, host: ModuleHost, header: Bool, compact: Bool = false,
                         tabbed: Bool = false) -> [NSMenuItem] {
        let module = host.module(id)
        var items: [NSMenuItem] = []
        for item in module.menuSection(tabbed: tabbed)
        where !(item.isSeparatorItem && (compact || (items.last?.isSeparatorItem ?? true))) {
            item.menu?.removeItem(item)
            items.append(item)
        }
        while items.last?.isSeparatorItem == true { items.removeLast() }
        guard !items.isEmpty else { return [] }
        guard header else { return items }
        return [MenuKit.header(module.title, control: ControlID("menu.snaptic.sectionHeader"))] + items
    }

    /// Snaptic item footer: the upgrade item, Recent Notices ›, the Show … Tab items (A3; hidden unless an assistive
    /// input is in use), the update row (E1, directly above Settings whenever the tab items are hidden), Snaptic
    /// Settings…, Quit Snaptic.
    private func sharedFooter(host: ModuleHost, config: ModulesConfig, plan: StatusItemPlan,
                              showTabItems: [NSMenuItem]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let upgrade = upgradeItem(host: host, config: config) { items.append(upgrade) }
        if let notices = recentNotices(host) { items.append(notices) }
        items += showTabItems
        items += Self.updateItems(host: host)
        let page = plan.noModulesEnabled ? SettingsRootID.general : nil
        items.append(MenuKit.settings(L("Snaptic Settings…"), control: ControlID("menu.snaptic.settings")) { [weak host] in
            host?.openSettings(page: page)
        })
        items.append(MenuKit.quit(control: ControlID("menu.snaptic.quit")))
        return items
    }

    /// Own-icon footer: "<Module> Settings…", then (Snaptic item absent) the upgrade item, Recent Notices ›, the
    /// update row (E1: only where the shared footer is) and Quit Snaptic (§5.2).
    private func ownFooter(_ id: ModuleID, host: ModuleHost, config: ModulesConfig, plan: StatusItemPlan) -> [NSMenuItem] {
        let module = host.module(id)
        // The module's sidebar root (its id): "Displays Settings…" opens Settings › Displays.
        let page = id.rawValue
        var items = [MenuKit.settings(L("\(module.title) Settings…"), control: ControlID("menu.snaptic.moduleSettings")) { [weak host] in
            host?.openSettings(page: page)
        }]
        guard plan.sharedFooterInOwnMenus else { return items }
        if let upgrade = upgradeItem(host: host, config: config) { items.append(upgrade) }
        if let notices = recentNotices(host) { items.append(notices) }
        items += Self.updateItems(host: host)
        items.append(MenuKit.quit(control: ControlID("menu.snaptic.quit")))
        return items
    }

    /// 0.2's "More display features…" for upgraders who haven't turned Displays on (the General card's twin): opens
    /// Settings › Displays, whose header switch turns it on.
    private func upgradeItem(host: ModuleHost, config: ModulesConfig) -> NSMenuItem? {
        guard !config.isEnabled(.displays),
              config.showNewDisplaysCard || config.newModuleCards.contains(.displays) else { return nil }
        return MenuKit.action(L("More Display Features…"), control: ControlID("menu.snaptic.upgrade")) { [weak host] in
            host?.openSettings(page: SettingsRootID.displays)
        }
    }

    // MARK: 0.3.1 cross-team hooks (lead, step 0)

    /// B3.4: "Sleep Is Turned Off" and "Turn Sleep Back On…", first in every Snaptic menu while a leftover shows.
    /// Static and fresh on each call, because a menu item belongs to one menu: IndicatorController builds Awake's own
    /// menu from it too (`CustomItemRow.leftover`). No Keep Sleep Off here: it has no undo but Terminal.
    static func leftoverItems(host: ModuleHost) -> [NSMenuItem] {
        guard host.lidRecovery.showsRows else { return [] }
        return [
            MenuKit.status(AwakeLidText.menuLeftover, control: ControlID("menu.snaptic.lidLeftover")),
            MenuKit.action(AwakeLidText.turnSleepBackOn, control: ControlID("menu.snaptic.lidRestore")) { [weak host] in
                host?.lidRecovery.turnSleepBackOn()
            },
        ]
    }

    /// E1: "Update Available: Snaptic 0.3.2…", or "Restart to Update Snaptic…" once it downloaded and installs at
    /// quit; directly above Snaptic Settings… in the shared footer (`CustomItemRow.updateAvailable` for Awake's menu).
    static func updateItems(host: ModuleHost) -> [NSMenuItem] {
        guard let updater = host.updater, let offer = updater.availableUpdate else { return [] }
        // E4: while lid-closed mode or a display trial holds the install, the row says why instead of offering it.
        if offer.readyToRestart, let wait = updater.waitText {
            return [MenuKit.status(wait, control: ControlID("menu.snaptic.updateAvailable"))]
        }
        let title = UpdatePolicy.menuTitle(offer)
        return [MenuKit.action(title, control: ControlID("menu.snaptic.updateAvailable")) { [weak updater] in
            updater?.installUpdate()
        }]
    }

    // MARK: Tabs (0.3.1 A1–A5)

    private func resetTabs() {
        tabs = []
        selectedTab = nil
        tabBarItem = nil
        sectionItems = []
        footerSeparator = nil
        showTabItems = []
    }

    /// The section a tab shows: `menuSection(tabbed: true)` without a header (the tab names it), or "Nothing to Show"
    /// when the module has nothing (it stopped while the menu was open), so the groups stay single-separated.
    private func tabSection(_ id: ModuleID, host: ModuleHost) -> [NSMenuItem] {
        let items = section(id, host: host, header: false, tabbed: true)
        return items.isEmpty ? [MenuKit.status(MenuTabs.emptySection, control: ControlID("menu.snaptic.emptyTab"))] : items
    }

    /// A2: the width of the widest tab, measured in a scratch menu. NSMenu lays items out in shared columns (image,
    /// title, key equivalent, submenu arrow), so each section is measured beside fresh copies of the host rows and the
    /// footer (⌘, and ⌘Q, Recent Notices ›, the Show … Tab items as they'll show): measured alone, a wide section
    /// misses the key column and a switch still resizes the open menu (r1 U1). The items are removed right after, so
    /// nothing keeps refreshing them (Awake prunes its live headers by `menu == nil`; sliders' sinks die with their
    /// rows). Every tab's `menuSection(tabbed:)` is cheap and free of side effects (A2), so the selected one is built
    /// again to show it.
    private func widestSection(_ tabs: [ModuleID], selected: ModuleID, host: ModuleHost, config: ModulesConfig,
                               plan: StatusItemPlan) -> CGFloat {
        let scratch = NSMenu()
        scratch.autoenablesItems = false
        let showTabs = makeShowTabItems(tabs, selected: selected, host: host)
        let assistive = Self.assistiveInputInUse()
        for item in showTabs { item.isHidden = !assistive }
        let head = hostSafetyRows(host)
        let footer = sharedFooter(host: host, config: config, plan: plan, showTabItems: showTabs)
        var widest: CGFloat = 0
        for id in tabs {
            // An item belongs to one menu at a time; `removeAllItems()` frees the shared ones for the next tab.
            for item in head + tabSection(id, host: host) + footer { scratch.addItem(item) }
            widest = max(widest, scratch.size.width)
            scratch.removeAllItems()
        }
        return widest
    }

    /// The tab bar: module titles (short ones when they don't fit), the attention marks (`menuAttention`), and
    /// ", on" for Awake while it governs (no active image: N11's glyph already shows it).
    private func tabBar(_ tabs: [ModuleID], selected: ModuleID, host: ModuleHost, width: CGFloat) -> NSMenuItem {
        let modules = tabs.map { host.module($0) }
        let flags = Dictionary(modules.map { ($0.id, $0.menuAttention) }, uniquingKeysWith: { $0 || $1 })
        let marked = MenuTabs.attention(flags, tabs: tabs)
        let governing = host.awake.runtime.governing != .inactive
        return MenuKit.tabBar(labels: modules.map { MenuTabLabel(title: $0.title, shortTitle: $0.id.shortTitle) },
                              selected: tabs.firstIndex(of: selected) ?? 0,
                              attention: Set(tabs.indices.filter { marked.contains(tabs[$0]) }),
                              active: governing ? tabs.firstIndex(of: .awake) : nil,
                              width: width, control: ControlID("menu.snaptic.tabs")) { [weak self] index in
            self?.tabClicked(index)
        }
    }

    /// A3: the native twin of each tab, "Show Displays Tab" with ⌘n by position; the shown tab is checked.
    private func makeShowTabItems(_ tabs: [ModuleID], selected: ModuleID, host: ModuleHost) -> [NSMenuItem] {
        tabs.prefix(MenuTabs.maxKeyIndex).enumerated().map { index, id in
            let item = MenuKit.action(MenuTabs.showTabTitle(host.module(id).title), key: String(index + 1),
                                      control: ControlID("menu.snaptic.showTab")) { [weak self] in
                self?.showTabChosen(id)
            }
            item.allowsKeyEquivalentWhenHidden = true
            item.state = id == selected ? .on : .off
            return item
        }
    }

    /// A3: the Show … Tab items show only while an assistive input is in use; hidden, their ⌘n still works.
    private func updateShowTabItems() {
        let assistive = Self.assistiveInputInUse()
        for item in showTabItems { item.isHidden = !assistive }
    }

    /// VoiceOver, Switch Control, Keyboard navigation (`isFullKeyboardAccessEnabled`, `AppleKeyboardUIMode`) or
    /// Accessibility › Full Keyboard Access, which has no public API and no change notification: its preference is
    /// read on every open (r1 U2; HW-25 confirms the key). Unreadable counts as off.
    private static func assistiveInputInUse() -> Bool {
        let workspace = NSWorkspace.shared
        let domain = MenuTabs.fullKeyboardAccessDomain as CFString
        // Another process writes this domain; drop any cached copy first.
        _ = CFPreferencesAppSynchronize(domain)
        let fullKeyboardAccess = CFPreferencesGetAppBooleanValue(MenuTabs.fullKeyboardAccessKey as CFString, domain, nil)
        return MenuTabs.showsTabItems(voiceOver: workspace.isVoiceOverEnabled,
                                      switchControl: workspace.isSwitchControlEnabled,
                                      keyboardNavigation: NSApp.isFullKeyboardAccessEnabled,
                                      fullKeyboardAccess: fullKeyboardAccess)
    }

    /// A5: the choice is remembered across opens and relaunches.
    private static func storeTab(_ id: ModuleID) {
        UserDefaults.standard.set(id.rawValue, forKey: MenuTabs.defaultsKey)
    }

    /// A segment was chosen (mouse or VoiceOver), in the control's action: remember it and switch in place.
    private func tabClicked(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let id = tabs[index]
        Self.storeTab(id)
        showTab(id)
    }

    /// A Show … Tab item or ⌘n: remember the choice and show it at the next open. AppKit normally closes the menu
    /// before an item's action runs; if the Snaptic menu is still open (HW-26: tracking continued after ⌘n), the tab
    /// switches in place instead.
    private func showTabChosen(_ id: ModuleID) {
        Self.storeTab(id)
        shared?.dirty = true
        if sharedMenuOpen { showTab(id) }
    }

    /// A2: switches the open Snaptic menu to `id`. Only `sectionItems` are removed, and the new section goes above
    /// the footer's separator; no `cancelTracking()` (it would end all menu tracking; removing an item closes its
    /// open submenu: HW-24), no timers and no run-loop perform (N15). Rows that are removed are never under the
    /// pointer (the pointer is on the tab bar), so R2C c12 doesn't apply.
    private func showTab(_ id: ModuleID) {
        guard let host, let menu = shared?.menu, id != selectedTab, let index = tabs.firstIndex(of: id),
              let tabBarItem, tabBarItem.menu === menu,
              let footerSeparator, footerSeparator.menu === menu else { return }
        for item in sectionItems where item.menu === menu { menu.removeItem(item) }
        let items = tabSection(id, host: host)
        var at = menu.index(of: footerSeparator)
        for item in items {
            menu.insertItem(item, at: at)
            at += 1
        }
        sectionItems = items
        selectedTab = id
        for (position, item) in showTabItems.enumerated() { item.state = position == index ? .on : .off }
        if let view = tabBarItem.view as? MenuTabBarView {
            if view.selectedIndex != index { view.select(index) }
            // NSMenu has no public window accessor; the bar's window is the menu's.
            NSAccessibility.post(element: view.window ?? view, notification: .layoutChanged)
        }
    }

    private func recentNotices(_ host: ModuleHost) -> NSMenuItem? {
        let recent = host.toasts.recent
        guard !recent.isEmpty else { return nil }
        var rows = recent.reversed().map { MenuKit.status($0, control: ControlID("menu.snaptic.notice")) }
        rows.append(MenuKit.separator())
        rows.append(MenuKit.action(L("Clear Menu"), control: ControlID("menu.snaptic.clearNotices")) { [weak host] in
            host?.toasts.clearRecent()
        })
        return MenuKit.submenu(L("Recent Notices"), control: ControlID("menu.snaptic.recentNotices"), rows)
    }
}
