import Foundation

// The Displays menu's Display Tools items owned by F (PLAN 0.3 §5.2, §4.8 "0.2 menu"): Identify Displays,
// Redetect Displays and Show Displays Panel. The 0.2 quick-menu twin is removed (ControlRemovals).

package enum OverviewMenuItemsControls: ControlTable {
    package static let surface = "menu.display.f"

    private static func tools(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec("Display Tools", customize: .checkbox, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.f.identify", .menuItem, when: [.module(.displays)],
                    replaces: ["l.menu.f.tools.identify"], menu: tools("f.tools.identify")),
        ControlSpec("menu.display.f.redetect", .menuItem, when: [.module(.displays)],
                    replaces: ["l.menu.f.tools.redetect"], menu: tools("f.tools.redetect")),
        ControlSpec("menu.display.f.panel", .menuItem, when: [.module(.displays)],
                    replaces: ["l.menu.f.tools.panel"], menu: tools("f.tools.panel")),
    ]
}
