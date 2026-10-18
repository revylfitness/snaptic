import Foundation

// DisplaysMenuBuilder's controls (owner: M; PLAN 0.3 §4.8 "0.2 menu", §5.2): the Displays section's status rows,
// its top-level items and submenus, and Display Tools. A global 0.2 menu id's home (`replaces:`) is the spec of the
// item's builder (A, B, C, D, E, F tables); these specs only place it (`menu.legacyMenuID`), and the Customize
// Displays Menu sheet has one row per placed id.

package enum DisplaysMenuBuilderControls: ControlTable {
    package static let surface = "menu.displays"

    private static let section = "Displays section"
    private static let tools = "Display Tools"

    private static func item(_ location: String, _ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec(location, customize: .checkbox, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    private static func fixed(_ location: String) -> MenuPlacementSpec { MenuPlacementSpec(location, customize: .none) }

    package static let controls: [ControlSpec] = [
        // Status rows (only while true).
        ControlSpec("menu.displays.status", .menuItem, menu: fixed(section)),
        ControlSpec("menu.displays.restartHelper", .menuItem, when: [.state(.helperStopped)], menu: fixed(section)),
        ControlSpec("menu.displays.paused", .menuItem, when: [.state(.automationPaused)], menu: fixed(section)),
        ControlSpec("menu.displays.resume", .menuItem, when: [.state(.automationPaused)],
                    menu: item(section, "b.resumeAutomation")),
        ControlSpec("menu.displays.noDisplays", .menuItem, menu: fixed(section)),
        ControlSpec("menu.displays.allHidden", .menuItem, menu: fixed(section)),
        ControlSpec("menu.displays.showAll", .menuItem, menu: fixed(section)),
        // Top-level items and submenus.
        ControlSpec("menu.displays.restorePending", .menuItem, when: [.state(.pendingConfirmation)], menu: fixed(section)),
        ControlSpec("menu.displays.arrange", .menuItem, when: [.displayFeature(.arrangement)],
                    menu: item(section, "d.arrange")),
        ControlSpec("menu.displays.layouts", .menuSubmenu, when: [.displayFeature(.layouts)],
                    menu: item(section, "d.layoutsMenu")),
        ControlSpec("menu.displays.layoutMatch", .menuItem, when: [.displayFeature(.layouts)],
                    menu: item("Saved Layouts submenu", "d.layoutMatch")),
        ControlSpec("menu.displays.protection", .menuItem, when: [.displayFeature(.protection)],
                    menu: item("Saved Layouts submenu", "d.protection")),
        ControlSpec("menu.displays.virtual", .menuSubmenu, when: [.displayFeature(.virtualScreens)],
                    menu: item(section, "d.virtualMenu")),
        ControlSpec("menu.displays.pip", .menuSubmenu, when: [.displayFeature(.pip)],
                    menu: item(section, "e.pip.tools")),
        ControlSpec("menu.displays.actions", .menuSubmenu, when: [.displayFeature(.customActions), .perItem("customAction")],
                    menu: item(section, "a.custom.")),
        // Display Tools.
        ControlSpec("menu.displays.tools", .menuSubmenu, replaces: ["l.menu.fixed.tools.header"], menu: fixed(section)),
        ControlSpec("menu.displays.identify", .menuItem, menu: item(tools, "f.tools.identify")),
        ControlSpec("menu.displays.redetect", .menuItem, menu: item(tools, "f.tools.redetect")),
        ControlSpec("menu.displays.panel", .menuItem, menu: item(tools, "f.tools.panel")),
        ControlSpec("menu.displays.matchTextSize", .menuItem, when: [.displayFeature(.scaleMatch)],
                    menu: item(tools, "d.matchUI")),
        ControlSpec("menu.displays.connectAll", .menuItem, when: [.displayFeature(.disconnect)],
                    menu: item(tools, "d.connectAll")),
        ControlSpec("menu.displays.disconnectAllButMain", .menuItem, when: [.displayFeature(.disconnect)],
                    menu: item(tools, "d.disconnectAllButMain")),
        ControlSpec("menu.displays.restoreAll", .menuItem, menu: item(tools, "b.restoreAll")),
        ControlSpec("menu.displays.sync", .menuItem, when: [.displayFeature(.sync), .hardware(.twoDisplays)],
                    menu: item(tools, "c.sync.toggle")),
        ControlSpec("menu.displays.nightShift", .menuItem, when: [.displayFeature(.nightShift)],
                    menu: item(tools, "c.tools.nightShift")),
    ]
}
