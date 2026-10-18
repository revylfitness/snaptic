import AppKit
import SnapticKit

/// The Displays section of a menu (PLAN 0.3 §5.2), called from `DisplaysModule.menuSection()` on every rebuild:
///
/// ```
/// [!] status rows (only while true): module state, "Display automation is paused" + Resume Display Automation,
///     other display apps, "Unprotected" + Restart Snaptic
/// [▭] one device row per display (+ its sliders), disconnected displays dimmed at the end
/// [↺] Restore All Displays            only while a change awaits confirmation
/// [▦] Arrange Displays…
/// [▤] Saved Layouts ›  [▢] Virtual Displays ›  [⧉] Picture in Picture ›  [ϟ] Actions ›
/// [🔧] Display Tools ›
/// ```
///
/// The section header ("Displays") and Safe Mode's row come from StatusMenu. Every top-level item has a 16 pt
/// template symbol, items inside submenus have none (§5.1). The user's section order (displays or tools first)
/// is kept; there is no separator inside the section. No right-click menu (C3): the 0.2 quick-menu items have their
/// Display Tools twins.
@MainActor final class DisplaysMenuBuilder: ControlDeclaring {
    typealias Controls = DisplaysMenuBuilderControls

    weak var context: DisplaysContext?

    init(context: DisplaysContext) { self.context = context }

    func build() -> [NSMenuItem] {
        guard let ctx = context else { return [] }
        let global = Self.collectGlobal(ctx)
        var items = statusRows(ctx)
        for section in ctx.config.value.menu.orderedSections {
            switch section {
            case .displays: items += displayRows(ctx)
            case .tools: items += sectionItems(global)
            }
        }
        return items
    }

    // MARK: Status rows

    private func statusRows(_ ctx: DisplaysContext) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if case .degraded(let reason) = ctx.runtime.moduleState {
            items.append(MenuKit.status(L("Displays: \(reason)"), symbol: "exclamationmark.triangle",
                                        control: ControlID("menu.displays.status")))
        }
        if ctx.panic.isLatched {
            items.append(MenuKit.status(L("Display automation is paused"), symbol: "pause.circle",
                                        control: ControlID("menu.displays.paused")))
            let panic = ctx.panic
            items.append(MenuKit.action(L("Resume Display Automation"), symbol: "play.circle",
                                        control: ControlID("menu.displays.resume")) { [weak panic] in panic?.resume() })
        }
        let paused = ctx.otherApps.pausedDisplayFeatures
        if !paused.isEmpty {
            let item = MenuKit.status(Self.pauseReasons(paused, monitor: ctx.otherApps).first ?? L("Some features are paused"),
                                      symbol: "pause.circle", control: ControlID("menu.displays.status"))
            item.toolTip = paused.map(DisplaysUIText.title).sorted().joined(separator: ", ")
            items.append(item)
        }
        if let reason = Self.unprotectedReason(ctx) {
            let title = ctx.helpers.unavailable != nil ? L("Unprotected: Snaptic's helpers can't run")
                : L("Unprotected: the safety helper isn't running")
            let item = MenuKit.status(title, symbol: "exclamationmark.shield", control: ControlID("menu.displays.status"))
            item.toolTip = reason
            items.append(item)
            let relauncher = ctx.relauncher
            items.append(MenuKit.action(L("Restart Snaptic"), symbol: "arrow.clockwise",
                                        control: ControlID("menu.displays.restartHelper")) {
                relauncher.relaunch(reason: L("Restart the safety helper"))
            })
        }
        return items
    }

    /// Unique, sorted pause reasons ("Paused while MonitorControl runs").
    static func pauseReasons(_ paused: Set<DisplayFeature>, monitor: OtherAppsMonitor) -> [String] {
        Array(Set(paused.compactMap { monitor.pauseReason(for: $0) })).sorted()
    }

    /// PLAN §3.5 "Unprotected": the guard isn't alive while something it must undo is armed (B's
    /// `isUnprotected`), or helpers can't be spawned at all (A's spawner).
    static func isUnprotected(_ ctx: DisplaysContext) -> Bool { unprotectedReason(ctx) != nil }

    /// What the Unprotected row says, or nil when protected.
    static func unprotectedReason(_ ctx: DisplaysContext) -> String? {
        if let reason = ctx.helpers.unavailable {
            return L("Snaptic's helpers can't run (\(reason)), so risky display changes can't be reverted automatically.")
        }
        if ctx.guardClient.isUnprotected {
            return L("The safety helper that reverts risky display changes isn't running.")
        }
        return nil
    }

    // MARK: Displays

    /// Displays in menu order without hidden ones.
    static func orderedDisplays(_ ctx: DisplaysContext, includeHidden: Bool = false) -> [DisplayInfo] {
        let all = ctx.runtime.displays
        let main = all.first(where: \.isMain)?.key
        let order = ctx.config.value.menu.orderedDisplays(all.map(\.key), main: main, includeHidden: includeHidden)
        return order.compactMap { key in all.first { $0.key == key } }
    }

    private func displayRows(_ ctx: DisplaysContext) -> [NSMenuItem] {
        guard !ctx.runtime.displays.isEmpty else {
            return [MenuKit.status(L("No displays detected"), symbol: "display.trianglebadge.exclamationmark",
                                   control: ControlID("menu.displays.noDisplays"))]
        }
        let shown = Self.orderedDisplays(ctx)
        guard !shown.isEmpty else {
            let config = ctx.config
            return [
                MenuKit.status(L("All displays are hidden from the menu"), symbol: "eye.slash",
                               control: ControlID("menu.displays.allHidden")),
                MenuKit.action(L("Show All Displays"), symbol: "eye", control: ControlID("menu.displays.showAll")) {
                    config.value.menu.hiddenDisplays = []
                },
            ]
        }
        // Connected displays in the user's order, then the disconnected ones (dimmed rows offering Connect).
        let connected = shown.filter { $0.isOnline && $0.isActive }
        let disconnected = shown.filter { !($0.isOnline && $0.isActive) }
        let slidersFirst = DisplaysMenuPlan.slidersBeforeDevice(
            displayCount: connected.count, headerForSingleDisplay: ctx.config.value.menu.headerForSingleDisplay)
        var items: [NSMenuItem] = []
        for display in connected + disconnected {
            items += DisplayMenuBlock(display: display, context: ctx).topLevelItems(slidersFirst: slidersFirst)
        }
        return items
    }

    // MARK: Section items

    /// The global items (`globalItems(slot: .tools)`), placed with the Kit table and the user's choices.
    struct Global {
        var restorePending: [DisplayMenuBlock.Entry] = []
        var sectionItems: [DisplayMenuBlock.Entry] = []
        var menus: [DisplaysSectionMenu: [DisplayMenuBlock.Entry]] = [:]
        var tools: [DisplayMenuBlock.Entry] = []
        var toolToggles: [DisplayMenuBlock.Entry] = []
    }

    static func collectGlobal(_ ctx: DisplaysContext) -> Global {
        let menu = ctx.config.value.menu
        var defaults: [DisplayMenuItemID: MenuItemVisibility] = [:]
        for descriptor in ctx.menus.descriptors where defaults[descriptor.id] == nil {
            defaults[descriptor.id] = descriptor.defaultVisibility
        }
        let pending = ctx.transactions.hasPendingTrial
        var global = Global()
        for contributor in ctx.menus.contributors {
            for (id, item) in contributor.globalItems(slot: .tools) {
                DisplayMenuBlock.detach(item)
                let entry = DisplayMenuBlock.Entry(id: id, item: item)
                // A custom action shows exactly when Automations › "Show in menu" is on (the contributor filters).
                let visibility = DisplaysMenuPlan.isCustomAction(id) ? MenuItemVisibility.visible
                    : menu.visibility(of: id, default: defaults[id] ?? .visible)
                // The paused status row has its own Resume item.
                switch DisplaysMenuPlan.place(id, visibility: visibility, perDisplay: false, isCustomRow: item.view != nil,
                                              pendingConfirmation: pending, automationPaused: false) {
                case .sectionItem?:
                    if id.rawValue == "b.restoreAll" { global.restorePending.append(entry) } else { global.sectionItems.append(entry) }
                case .sectionMenu(let m)?: global.menus[m, default: []].append(entry)
                case .tools(let toggle)?:
                    if toggle { global.toolToggles.append(entry) } else { global.tools.append(entry) }
                case .slider?, .underDevice?, .submenu?, .pausedStatus?, nil: break
                }
            }
        }
        global.sectionItems = DisplayMenuBlock.sorted(global.sectionItems)
        global.tools = DisplayMenuBlock.sorted(global.tools)
        global.toolToggles = DisplayMenuBlock.sorted(global.toolToggles)
        for (m, entries) in global.menus { global.menus[m] = DisplayMenuBlock.sorted(entries) }
        return global
    }

    private func sectionItems(_ global: Global) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for entry in global.restorePending {
            items.append(topLevel(entry, symbol: "arrow.uturn.backward", control: ControlID("menu.displays.restorePending")))
        }
        for entry in global.sectionItems {
            let info = DisplaysMenuPlan.info(for: entry.id)
            if entry.id.rawValue == "d.arrange" { entry.item.title = L("Arrange Displays…") }
            items.append(topLevel(entry, symbol: info?.symbol ?? "rectangle.3.group", control: Self.control(for: entry.id)))
        }
        for m in DisplaysSectionMenu.allCases {
            let children = Self.submenuRows(global.menus[m] ?? [])
            guard !children.isEmpty else { continue }
            items.append(MenuKit.submenu(m.title, symbol: m.symbol, control: Self.control(for: m), children))
        }
        var tools = Self.submenuRows(global.tools)
        let toggles = Self.submenuRows(global.toolToggles)
        if !tools.isEmpty && !toggles.isEmpty { tools.append(MenuKit.separator()) }
        tools += toggles
        if !tools.isEmpty {
            items.append(MenuKit.submenu(L("Display Tools"), symbol: "wrench.and.screwdriver",
                                         control: ControlID("menu.displays.tools"), tools))
        }
        return items
    }

    private func topLevel(_ entry: DisplayMenuBlock.Entry, symbol: String, control: ControlID?) -> NSMenuItem {
        let item = entry.item
        if let image = MenuKit.symbolImage(symbol) { item.image = image }
        if item.identifier == nil, let control { item.identifier = NSUserInterfaceItemIdentifier(control.rawValue) }
        return item
    }

    private static func control(for menu: DisplaysSectionMenu) -> ControlID {
        switch menu {
        case .layouts: return ControlID("menu.displays.layouts")
        case .virtualDisplays: return ControlID("menu.displays.virtual")
        case .pictureInPicture: return ControlID("menu.displays.pip")
        case .actions: return ControlID("menu.displays.actions")
        }
    }

    /// The control a global 0.2 menu id is placed as.
    static func control(for id: DisplayMenuItemID) -> ControlID? {
        if DisplaysMenuPlan.isCustomAction(id) { return ControlID("menu.displays.actions") }
        switch id.rawValue {
        case "d.arrange": return ControlID("menu.displays.arrange")
        case "d.layoutsMenu": return ControlID("menu.displays.layouts")
        case "d.layoutMatch": return ControlID("menu.displays.layoutMatch")
        case "d.protection": return ControlID("menu.displays.protection")
        case "d.virtualMenu": return ControlID("menu.displays.virtual")
        case "e.pip.tools": return ControlID("menu.displays.pip")
        case "f.tools.identify": return ControlID("menu.displays.identify")
        case "f.tools.redetect": return ControlID("menu.displays.redetect")
        case "f.tools.panel": return ControlID("menu.displays.panel")
        case "d.matchUI": return ControlID("menu.displays.matchTextSize")
        case "d.connectAll": return ControlID("menu.displays.connectAll")
        case "d.disconnectAllButMain": return ControlID("menu.displays.disconnectAllButMain")
        case "b.restoreAll": return ControlID("menu.displays.restoreAll")
        case "c.sync.toggle": return ControlID("menu.displays.sync")
        case "c.tools.nightShift": return ControlID("menu.displays.nightShift")
        default: return nil
        }
    }

    /// Rows for a submenu built from entries: a submenu a contributor handed over contributes its children (nested
    /// submenus dropped), a run that came from such a list is set off from plain items by a separator ("layouts ─
    /// Apply Matching Layout, Protect Arrangement"), images are removed and rows are tagged with their control.
    static func submenuRows(_ entries: [DisplayMenuBlock.Entry]) -> [NSMenuItem] {
        var blocks: [(rows: [NSMenuItem], isList: Bool)] = []
        var index = 0
        while index < entries.count {
            let id = entries[index].id
            var rows: [NSMenuItem] = []
            var isList = false
            while index < entries.count && entries[index].id == id {
                let item = entries[index].item
                if let sub = item.submenu {
                    let children = sub.items
                    sub.removeAllItems()
                    rows += children.filter { $0.submenu == nil }
                    isList = true
                } else {
                    rows.append(item)
                }
                index += 1
            }
            while rows.first?.isSeparatorItem == true { rows.removeFirst() }
            while rows.last?.isSeparatorItem == true { rows.removeLast() }
            guard !rows.isEmpty else { continue }
            let control = Self.control(for: id)
            for row in rows {
                row.image = nil
                if row.identifier == nil, let control { row.identifier = NSUserInterfaceItemIdentifier(control.rawValue) }
            }
            blocks.append((rows, isList))
        }
        var result: [NSMenuItem] = []
        var previousWasList = false
        for (i, block) in blocks.enumerated() {
            if i > 0 && (previousWasList || block.isList) { result.append(MenuKit.separator()) }
            result += block.rows
            previousWasList = block.isList
        }
        return result
    }
}
