import Foundation

// ColorMenuItems' controls (owner: C; PLAN 0.3 §4.8 "0.2 menu", §5.2; R5-13: the color, extra-brightness, sync,
// Night Shift and menu-bar background items moved here from their controllers). Per-display items live in the
// display submenu (Show / In Display Submenu / Hide); Sync Brightness and Night Shift in Display Tools (checkbox).

package enum ColorMenuItemsControls: ControlTable {
    package static let surface = "menu.display.c"

    private static func submenu(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec("display submenu", customize: .threeWay, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    private static func tools(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec("Display Tools", customize: .checkbox, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.c.adjustColors", .menuItem,
                    when: [.displayFeature(.color), .perItem("display")],
                    replaces: ["l.menu.c.color.submenu"], menu: submenu("c.color.submenu")),
        ControlSpec("menu.display.c.extraBrightness", .menuItem,
                    when: [.displayFeature(.xdr), .hardware(.xdrDisplay), .perItem("display")],
                    replaces: ["l.menu.c.xdr.toggle"], menu: submenu("c.xdr.toggle")),
        ControlSpec("menu.display.c.autoBrightness", .menuItem,
                    when: [.displayFeature(.autoBrightness), .hardware(.builtinDisplay), .perItem("display")],
                    replaces: ["l.menu.c.color.autoBrightness"], menu: submenu("c.color.autoBrightness")),
        ControlSpec("menu.display.c.menuBarBackground", .menuItem,
                    when: [.displayFeature(.menuBarOverlays), .perItem("display")],
                    replaces: ["l.menu.c.menuBarStrip.toggle"], menu: submenu("c.menuBarStrip.toggle")),
        ControlSpec("menu.display.c.profileHeader", .menuItem,
                    when: [.displayFeature(.colorProfiles), .perItem("display")],
                    replaces: ["l.menu.c.color.profiles"], menu: submenu("c.color.profiles")),
        ControlSpec("menu.display.c.profile", .menuItem,
                    when: [.displayFeature(.colorProfiles), .perItem("profile")],
                    menu: submenu("c.color.profiles")),
        ControlSpec("menu.display.c.moreProfiles", .menuItem,
                    when: [.displayFeature(.colorProfiles), .perItem("display")],
                    menu: submenu("c.color.profiles")),
        ControlSpec("menu.display.c.presetHeader", .menuItem,
                    when: [.displayFeature(.applePresets), .hardware(.appleDisplay), .perItem("display")],
                    replaces: ["l.menu.c.color.applePresets"], menu: submenu("c.color.applePresets")),
        ControlSpec("menu.display.c.preset", .menuItem,
                    when: [.displayFeature(.applePresets), .hardware(.appleDisplay), .perItem("preset")],
                    menu: submenu("c.color.applePresets")),
        ControlSpec("menu.display.c.syncBrightness", .menuItem,
                    when: [.displayFeature(.sync), .hardware(.twoDisplays)],
                    replaces: ["l.menu.c.sync.toggle"], menu: tools("c.sync.toggle")),
        ControlSpec("menu.display.c.nightShift", .menuItem,
                    when: [.displayFeature(.nightShift)],
                    replaces: ["l.menu.c.tools.nightShift"], menu: tools("c.tools.nightShift")),
    ]
}
