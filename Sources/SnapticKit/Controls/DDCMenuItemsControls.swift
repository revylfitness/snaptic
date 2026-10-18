import Foundation

// DDCMenuItems' controls (owner: C; PLAN 0.3 §4.8 "0.2 menu", §5.2): volume, contrast and custom-control sliders at
// the top level under a display's row (Show / Hide), and the Input group, Mute and Turn Off Display in the display
// submenu (Show / In Display Submenu / Hide; Turn Off Display at the top level when Show, migration M10).

package enum DDCMenuItemsControls: ControlTable {
    package static let surface = "menu.display.c"

    private static func section(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec("Displays section", customize: .checkbox, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    private static func submenu(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec("display submenu", customize: .threeWay, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.c.volume", .menuSlider,
                    when: [.displayFeature(.ddcControls), .hardware(.ddcVolume), .perItem("display")],
                    replaces: ["l.menu.c.ddc.volume"], menu: section("c.ddc.volume")),
        ControlSpec("menu.display.c.contrast", .menuSlider,
                    when: [.displayFeature(.ddcControls), .hardware(.ddcDisplay), .perItem("display")],
                    replaces: ["l.menu.c.ddc.contrast"], menu: section("c.ddc.contrast")),
        ControlSpec("menu.display.c.custom", .menuSlider,
                    when: [.displayFeature(.ddcCustom), .hardware(.ddcDisplay), .perItem("customControl")],
                    replaces: ["l.menu.c.ddc.custom"], menu: section("c.ddc.custom")),
        ControlSpec("menu.display.c.customCommand", .menuItem,
                    when: [.displayFeature(.ddcCustom), .hardware(.ddcDisplay), .perItem("customControl")],
                    menu: section("c.ddc.custom")),
        ControlSpec("menu.display.c.inputHeader", .menuItem,
                    when: [.displayFeature(.ddcInput), .hardware(.ddcDisplay), .perItem("display")],
                    replaces: ["l.menu.c.ddc.input"], menu: submenu("c.ddc.input")),
        ControlSpec("menu.display.c.input", .menuItem,
                    when: [.displayFeature(.ddcInput), .hardware(.ddcDisplay), .perItem("input")],
                    menu: submenu("c.ddc.input")),
        ControlSpec("menu.display.c.mute", .menuItem,
                    when: [.displayFeature(.ddcControls), .hardware(.ddcVolume), .perItem("display")],
                    replaces: ["l.menu.c.ddc.mute", "l.menu.fixed.displays.moreMute"], menu: submenu("c.ddc.mute")),
        ControlSpec("menu.display.c.power", .menuItem,
                    when: [.displayFeature(.ddcPower), .hardware(.ddcDisplay), .perItem("display")],
                    replaces: ["l.menu.c.ddc.power"], menu: submenu("c.ddc.power")),
    ]
}
