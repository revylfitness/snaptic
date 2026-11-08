import Foundation

// IconsMenuRows' controls (lead; PLAN 0.4 §4.3, §4.8): the Hidden Icons section of the Snaptic menu and the arrow's
// menu share one row set; the Snaptic-menu section omits Hide Icons Automatically. Built fresh on each open, through
// MenuKit only.

package enum IconsMenuRowsControls: ControlTable {
    package static let surface = "menu.icons"

    private static let rows = MenuPlacementSpec("Hidden Icons section and the arrow's menu", customize: .none)
    private static let arrowMenu = MenuPlacementSpec("The arrow's menu", customize: .none)
    private static let shownSubmenu = MenuPlacementSpec("Hidden Icons section, Shown Icons submenu", customize: .none)
    private static let icons: [ControlCondition] = [.module(.hiddenIcons)]

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.icons.show", .menuItem, when: icons + [.state(.iconsCollapsed)], menu: rows),
        ControlSpec("menu.icons.hide", .menuItem, when: icons + [.state(.iconsExpanded)], menu: rows),
        // The ⌥ alternate of Show/Hide (a plain item while VoiceOver, Switch Control or Full Keyboard Access is on).
        ControlSpec("menu.icons.showAll", .menuItem, when: icons, menu: rows),
        // The hidden list (§4.8): section headers carry the meaning, one row per extra.
        ControlSpec("menu.icons.hiddenHeader", .menuItem, when: icons, menu: rows),
        ControlSpec("menu.icons.notchHeader", .menuItem, when: icons + [.hardware(.notch)], menu: rows),
        ControlSpec("menu.icons.icon", .menuItem, when: icons + [.perItem("extra")], menu: rows),
        ControlSpec("menu.icons.shownIcons", .menuSubmenu, when: icons, menu: rows),
        ControlSpec("menu.icons.shownIcon", .menuItem, when: icons + [.perItem("extra")], menu: shownSubmenu),
        // Empty and permission states (disabled rows, except Allow Accessibility…, which opens Permissions).
        ControlSpec("menu.icons.empty", .menuItem, when: icons, menu: rows),
        ControlSpec("menu.icons.allowAccessibility", .menuItem,
                    when: icons + [.iconsEngine(.length), .state(.accessibilityMissing)], menu: rows),
        ControlSpec("menu.icons.needsPermission", .menuItem,
                    when: icons + [.iconsEngine(.native), .state(.iconsNeedsPermission)], menu: rows),
        ControlSpec("menu.icons.reason", .menuItem, when: icons, menu: rows),
        // Footer.
        ControlSpec("menu.icons.autoCollapse", .menuItem, when: icons, keys: ["autoCollapse"], menu: arrowMenu),
        ControlSpec("menu.icons.settings", .menuItem, when: icons, menu: rows),
    ]
}
