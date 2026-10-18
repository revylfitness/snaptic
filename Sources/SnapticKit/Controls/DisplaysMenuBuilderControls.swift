import Foundation

// DisplaysMenuBuilder's controls (owner: M; PLAN 0.3 §4.8 "0.2 menu", §5.2): the Displays section's status rows,
// its top-level items and submenus, and Display Tools. Every global 0.2 menu id has its home here; the Customize
// Displays Menu sheet has one row per spec with a `legacyMenuID`.

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
        ControlSpec("menu.displays.restartHelper", .menuItem, when: [.state(.helperStopped)],
                    replaces: ["l.d.overview.banner.restartHelper"], menu: fixed(section)),
        ControlSpec("menu.displays.paused", .menuItem, when: [.state(.automationPaused)], menu: fixed(section)),
        ControlSpec("menu.displays.resume", .menuItem, when: [.state(.automationPaused)],
                    replaces: ["l.menu.b.resumeAutomation", "l.d.overview.banner.resume"],
                    menu: item(section, "b.resumeAutomation")),
        ControlSpec("menu.displays.noDisplays", .menuItem, menu: fixed(section)),
        ControlSpec("menu.displays.allHidden", .menuItem, menu: fixed(section)),
        ControlSpec("menu.displays.showAll", .menuItem, menu: fixed(section)),
        // Top-level items and submenus.
        ControlSpec("menu.displays.restorePending", .menuItem, when: [.state(.pendingConfirmation)], menu: fixed(section)),
        ControlSpec("menu.displays.arrange", .menuItem, when: [.displayFeature(.arrangement)],
                    replaces: ["l.menu.d.arrange"], menu: item(section, "d.arrange")),
        ControlSpec("menu.displays.layouts", .menuSubmenu, when: [.displayFeature(.layouts)],
                    replaces: ["l.menu.d.layoutsMenu"], menu: item(section, "d.layoutsMenu")),
        ControlSpec("menu.displays.layoutMatch", .menuItem, when: [.displayFeature(.layouts)],
                    replaces: ["l.menu.d.layoutMatch"], menu: item("Saved Layouts", "d.layoutMatch")),
        ControlSpec("menu.displays.protection", .menuItem, when: [.displayFeature(.protection)],
                    replaces: ["l.menu.d.protection"], menu: item("Saved Layouts", "d.protection")),
        ControlSpec("menu.displays.virtual", .menuSubmenu, when: [.displayFeature(.virtualScreens)],
                    replaces: ["l.menu.d.virtualMenu"], menu: item(section, "d.virtualMenu")),
        ControlSpec("menu.displays.pip", .menuSubmenu, when: [.displayFeature(.pip)],
                    replaces: ["l.menu.e.pip.tools"], menu: item(section, "e.pip.tools")),
        ControlSpec("menu.displays.actions", .menuSubmenu, when: [.displayFeature(.customActions), .perItem("customAction")],
                    replaces: ["l.menu.a.custom.*"], menu: item(section, "a.custom.")),
        // Display Tools.
        ControlSpec("menu.displays.tools", .menuSubmenu, replaces: ["l.menu.fixed.tools.header"], menu: fixed(section)),
        ControlSpec("menu.displays.identify", .menuItem, replaces: ["l.menu.f.tools.identify", "l.d.overview.identify"],
                    menu: item(tools, "f.tools.identify")),
        ControlSpec("menu.displays.redetect", .menuItem, replaces: ["l.menu.f.tools.redetect", "l.d.overview.redetect"],
                    menu: item(tools, "f.tools.redetect")),
        ControlSpec("menu.displays.panel", .menuItem, replaces: ["l.menu.f.tools.panel", "l.d.overview.showPanel"],
                    menu: item(tools, "f.tools.panel")),
        ControlSpec("menu.displays.matchTextSize", .menuItem, when: [.displayFeature(.scaleMatch)],
                    replaces: ["l.menu.d.matchUI"], menu: item(tools, "d.matchUI")),
        ControlSpec("menu.displays.connectAll", .menuItem, when: [.displayFeature(.disconnect)],
                    replaces: ["l.menu.d.connectAll", "l.d.arrangement.connectAll"], menu: item(tools, "d.connectAll")),
        ControlSpec("menu.displays.disconnectAllButMain", .menuItem, when: [.displayFeature(.disconnect)],
                    replaces: ["l.menu.d.disconnectAllButMain"], menu: item(tools, "d.disconnectAllButMain")),
        ControlSpec("menu.displays.restoreAll", .menuItem,
                    replaces: ["l.menu.b.restoreAll", "l.d.safety.restoreAllNow"], menu: item(tools, "b.restoreAll")),
        ControlSpec("menu.displays.sync", .menuItem, when: [.displayFeature(.sync), .hardware(.twoDisplays)],
                    replaces: ["l.menu.c.sync.toggle"], menu: item(tools, "c.sync.toggle")),
        ControlSpec("menu.displays.nightShift", .menuItem, when: [.displayFeature(.nightShift)],
                    replaces: ["l.menu.c.tools.nightShift"], menu: item(tools, "c.tools.nightShift")),
    ]
}
