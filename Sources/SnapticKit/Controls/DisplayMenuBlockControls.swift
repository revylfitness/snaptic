import Foundation

// DisplayMenuBlock's controls (owner: M; PLAN 0.3 §4.8 "0.2 menu", §5.2): one display's device row and submenu, and
// the place of every per-display item the contributors build. A 0.2 menu id's home (`replaces:`) is the spec of the
// item's builder (C, D, E, F, B tables); these specs only place it (`menu.legacyMenuID`), and the Customize Displays
// Menu sheet has one row per placed id (CustomizeMenuSheetControls; both checked by DisplaysMenuPlanTests).

package enum DisplayMenuBlockControls: ControlTable {
    package static let surface = "menu.display"

    private static let section = "Displays section"
    private static let submenu = "display submenu"
    private static let display = ControlCondition.perItem("display")

    private static func slider(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec(section, customize: .checkbox, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    private static func inSubmenu(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec(submenu, customize: .threeWay, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    private static func promotable(_ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec(submenu, customize: .threeWay, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    package static let controls: [ControlSpec] = [
        // The device row and its submenu.
        ControlSpec("menu.display.device", .menuSubmenu, when: [display],
                    replaces: ["l.menu.fixed.displays.header", "l.menu.fixed.displays.more"],
                    menu: MenuPlacementSpec(section, customize: .none)),
        ControlSpec("menu.display.disconnected", .menuSubmenu, when: [display, .state(.disconnectedDisplay)],
                    menu: MenuPlacementSpec(section, customize: .none)),
        ControlSpec("menu.display.moreResolutions", .menuItem, when: [display, .displayFeature(.resolution)],
                    menu: MenuPlacementSpec(submenu, customize: .none)),
        ControlSpec("menu.display.settings", .menuItem, when: [display], menu: MenuPlacementSpec(submenu, customize: .none)),
        // Sliders: top level under the device row, Show / Hide.
        ControlSpec("menu.display.brightness", .menuSlider, when: [display, .displayFeature(.brightness)],
                    menu: slider("c.brightness.slider")),
        ControlSpec("menu.display.volume", .menuSlider,
                    when: [display, .displayFeature(.ddcControls), .hardware(.ddcVolume)],
                    menu: slider("c.ddc.volume")),
        ControlSpec("menu.display.contrast", .menuSlider,
                    when: [display, .displayFeature(.ddcControls), .hardware(.ddcDisplay)],
                    menu: slider("c.ddc.contrast")),
        ControlSpec("menu.display.customControl", .menuSlider,
                    when: [display, .displayFeature(.ddcCustom), .hardware(.ddcDisplay)],
                    menu: slider("c.ddc.custom")),
        ControlSpec("menu.display.resolutionSlider", .menuSlider, when: [display, .displayFeature(.resolution)],
                    menu: slider("d.resolutionSlider")),
        // The display submenu, in §5.2 order.
        ControlSpec("menu.display.resolutions", .menuItem, when: [display, .displayFeature(.resolution)],
                    menu: inSubmenu("d.resolutionMenu")),
        ControlSpec("menu.display.useAsMain", .menuItem, when: [display, .displayFeature(.mainDisplay), .hardware(.twoDisplays)],
                    menu: inSubmenu("d.setMain")),
        ControlSpec("menu.display.mirror", .menuItem, when: [display, .displayFeature(.mirroring), .hardware(.twoDisplays)],
                    menu: inSubmenu("d.mirrorMenu")),
        ControlSpec("menu.display.hdr", .menuItem, when: [display, .displayFeature(.hdrToggle), .hardware(.hdrDisplay)],
                    menu: inSubmenu("d.hdrToggle")),
        ControlSpec("menu.display.extraBrightness", .menuItem, when: [display, .displayFeature(.xdr), .hardware(.xdrDisplay)],
                    menu: inSubmenu("c.xdr.toggle")),
        ControlSpec("menu.display.sharperText", .menuItem, when: [display, .displayFeature(.smartHiDPI)],
                    menu: inSubmenu("d.smartHiDPI")),
        ControlSpec("menu.display.adjustColors", .menuItem, when: [display, .displayFeature(.color)],
                    menu: inSubmenu("c.color.submenu")),
        ControlSpec("menu.display.autoBrightness", .menuItem,
                    when: [display, .displayFeature(.autoBrightness), .hardware(.builtinDisplay)],
                    menu: inSubmenu("c.color.autoBrightness")),
        ControlSpec("menu.display.menuBarBackground", .menuItem, when: [display, .displayFeature(.menuBarOverlays)],
                    menu: inSubmenu("c.menuBarStrip.toggle")),
        ControlSpec("menu.display.underscan", .menuItem, when: [display, .displayFeature(.underscan)],
                    menu: inSubmenu("d.underscanMenu")),
        ControlSpec("menu.display.pip", .menuItem, when: [display, .displayFeature(.pip)],
                    menu: inSubmenu("e.pip.display")),
        ControlSpec("menu.display.rotation", .menuItem, when: [display, .displayFeature(.rotation)],
                    menu: inSubmenu("d.rotationMenu")),
        ControlSpec("menu.display.colorProfile", .menuItem, when: [display, .displayFeature(.colorProfiles)],
                    menu: inSubmenu("c.color.profiles")),
        ControlSpec("menu.display.preset", .menuItem,
                    when: [display, .displayFeature(.applePresets), .hardware(.appleDisplay)],
                    menu: inSubmenu("c.color.applePresets")),
        ControlSpec("menu.display.input", .menuItem, when: [display, .displayFeature(.ddcInput), .hardware(.ddcDisplay)],
                    menu: inSubmenu("c.ddc.input")),
        ControlSpec("menu.display.mute", .menuItem,
                    when: [display, .displayFeature(.ddcControls), .hardware(.ddcVolume)],
                    menu: inSubmenu("c.ddc.mute")),
        ControlSpec("menu.display.power", .menuItem, when: [display, .displayFeature(.ddcPower), .hardware(.ddcDisplay)],
                    menu: promotable("c.ddc.power")),
        ControlSpec("menu.display.disconnect", .menuItem, when: [display, .displayFeature(.disconnect)],
                    menu: promotable("d.disconnectItem")),
    ]
}
