import Foundation

// ResolutionMenuItems' controls (owner: D; PLAN 0.3 §4.8 "0.2 menu", §5.2): the resolution slider under each device
// row, the resolutions in each display submenu, and Display Tools › Match Text Size….

package enum ResolutionMenuItemsControls: ControlTable {
    package static let surface = "menu.display.d"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.d.resolutionSlider", .menuSlider,
                    when: [.displayFeature(.resolution), .perItem("display")],
                    replaces: ["l.menu.d.resolutionSlider"],
                    menu: MenuPlacementSpec("Displays section, under the device row", customize: .checkbox,
                                            legacy: .dResolutionSlider)),
        ControlSpec("menu.display.d.resolution", .menuItem,
                    when: [.displayFeature(.resolution), .perItem("display")],
                    replaces: ["l.menu.d.resolutionMenu"],
                    menu: MenuPlacementSpec("display submenu", customize: .threeWay, legacy: .dResolutionMenu)),
        ControlSpec("menu.display.d.moreResolutions", .menuItem,
                    when: [.displayFeature(.resolution), .perItem("display"), .parentOn(ControlID("menu.display.d.resolution"))],
                    replaces: ["l.menu.fixed.displays.moreResolution"],
                    menu: MenuPlacementSpec("display submenu", customize: .none, legacy: .dResolutionMenu)),
        ControlSpec("menu.display.d.resolutionUndo", .menuItem,
                    when: [.displayFeature(.resolution), .perItem("display"), .parentOn(ControlID("menu.display.d.resolution"))],
                    replaces: ["l.d.resolution.undo"],
                    menu: MenuPlacementSpec("display submenu", customize: .none, legacy: .dResolutionMenu)),
        ControlSpec("menu.display.d.resolutionRedo", .menuItem,
                    when: [.displayFeature(.resolution), .perItem("display"), .parentOn(ControlID("menu.display.d.resolution"))],
                    replaces: ["l.d.resolution.redo"],
                    menu: MenuPlacementSpec("display submenu", customize: .none, legacy: .dResolutionMenu)),
        ControlSpec("menu.display.d.matchTextSize", .menuItem,
                    when: [.displayFeature(.scaleMatch), .hardware(.twoDisplays)],
                    replaces: ["l.menu.d.matchUI"],
                    menu: MenuPlacementSpec("Display Tools", customize: .checkbox, legacy: .dMatchUI)),
    ]
}
