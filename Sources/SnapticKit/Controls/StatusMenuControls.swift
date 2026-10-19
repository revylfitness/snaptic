import Foundation

// StatusMenu's controls (owner: M; PLAN 0.3 §4.8 "0.2 menu" fixed rows, §5.2): the Snaptic menu's status rows,
// section headers and footer, and the footer of own-icon menus. 0.3.1 (lead, step 0): the tab bar and its Show … Tab
// items (A6), the host-level leftover rows (B7) and the Update Available row (E7).

package enum StatusMenuControls: ControlTable {
    package static let surface = "menu.snaptic"

    private static let snapticMenu = MenuPlacementSpec("Snaptic menu", customize: .none)
    private static let ownMenus = MenuPlacementSpec("own menus", customize: .none)
    /// B3.4: the leftover rows head every Snaptic menu (a spec has one placement, so the three are named together).
    private static let everyMenu = MenuPlacementSpec("Snaptic menu, own menus and Awake menu", customize: .none)
    /// E1: the shared footer, and own and Awake menus where they carry it.
    private static let sharedFooter = MenuPlacementSpec(
        "Snaptic menu footer, and own and Awake menus with the shared footer", customize: .none)

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.snaptic.safeMode", .menuItem, when: [.state(.safeMode)],
                    replaces: ["l.menu.fixed.safeModeRow"], menu: snapticMenu),
        ControlSpec("menu.snaptic.leaveSafeMode", .menuItem, when: [.state(.safeMode)], menu: snapticMenu),
        ControlSpec("menu.snaptic.noModules", .menuItem, menu: snapticMenu),
        ControlSpec("menu.snaptic.sectionHeader", .menuItem, when: [.perItem("module")], menu: snapticMenu),
        ControlSpec("menu.snaptic.upgrade", .menuItem, replaces: ["l.menu.fixed.upgradeCard"], menu: snapticMenu),
        ControlSpec("menu.snaptic.recentNotices", .menuSubmenu, replaces: ["l.menu.fixed.recentNotices"],
                    menu: snapticMenu),
        ControlSpec("menu.snaptic.notice", .menuItem, when: [.perItem("notice")], menu: snapticMenu),
        ControlSpec("menu.snaptic.clearNotices", .menuItem, menu: snapticMenu),
        ControlSpec("menu.snaptic.settings", .menuItem, replaces: ["l.menu.fixed.settings"], menu: snapticMenu),
        ControlSpec("menu.snaptic.moduleSettings", .menuItem, when: [.perItem("module")], menu: ownMenus),
        ControlSpec("menu.snaptic.quit", .menuItem, replaces: ["l.menu.fixed.quit"], menu: snapticMenu),
        // 0.3.1 A6: tabs (2+ modules in the Snaptic menu); the Show … Tab items carry ⌘n.
        ControlSpec("menu.snaptic.tabs", .menuTabBar, menu: snapticMenu),
        ControlSpec("menu.snaptic.showTab", .menuItem, when: [.perItem("module")], menu: snapticMenu),
        // 0.3.1 B7: "Sleep Is Turned Off" and "Turn Sleep Back On…" (no Keep Sleep Off in menus).
        ControlSpec("menu.snaptic.lidLeftover", .menuItem, when: [.state(.lidLeftover)], menu: everyMenu),
        ControlSpec("menu.snaptic.lidRestore", .menuItem, when: [.state(.lidLeftover)], menu: everyMenu),
        // 0.3.1 E7: "Update Available: Snaptic 0.3.2…" / "Restart to Update Snaptic…".
        ControlSpec("menu.snaptic.updateAvailable", .menuItem, when: [.state(.updateAvailable)], menu: sharedFooter),
    ]
}
