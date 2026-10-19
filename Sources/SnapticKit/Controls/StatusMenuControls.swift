import Foundation

// StatusMenu's controls (owner: M; PLAN 0.3 §4.8 "0.2 menu" fixed rows, §5.2): the Snaptic menu's status rows,
// section headers and footer, and the footer of own-icon menus.

package enum StatusMenuControls: ControlTable {
    package static let surface = "menu.snaptic"

    private static let snapticMenu = MenuPlacementSpec("Snaptic menu", customize: .none)
    private static let ownMenus = MenuPlacementSpec("own menus", customize: .none)

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
    ]
}
