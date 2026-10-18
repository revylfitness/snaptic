import Foundation

// BrightnessMenuItems' controls (owner: C; PLAN 0.3 §4.8 "0.2 menu", §5.2): the brightness slider under each display's
// row in the Displays section, or a status row while the monitor's first read is pending. The 0.2 brightness-method
// submenu has no menu home (ControlRemovals: Brightness › Advanced › Brightness methods).

package enum BrightnessMenuItemsControls: ControlTable {
    package static let surface = "menu.display.c"

    private static let displaysSection = MenuPlacementSpec("Displays section", customize: .checkbox,
                                                           legacy: DisplayMenuItemID(rawValue: "c.brightness.slider"))

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.c.brightness", .menuSlider,
                    when: [.displayFeature(.brightness), .perItem("display")],
                    replaces: ["l.menu.c.brightness.slider"], menu: displaysSection),
        ControlSpec("menu.display.c.brightnessReading", .menuItem,
                    when: [.displayFeature(.brightness), .displayFeature(.brightnessDDC), .hardware(.ddcDisplay),
                           .perItem("display")],
                    menu: displaysSection),
    ]
}
