import Foundation

// ManagementMenuItems' controls (owner: D; PLAN 0.3 §4.8 "0.2 menu", §5.2, R5-13): the items of the Arrangement,
// PanelProps, Power, Protection and SmartHiDPI controllers — per-display rows in each display submenu, Arrange
// Displays… in the Displays section, the connect tools in Display Tools and Protect Arrangement in Saved Layouts.

package enum ManagementMenuItemsControls: ControlTable {
    package static let surface = "menu.display.dm"

    private static let submenu = "display submenu"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.dm.useAsMain", .menuItem,
                    when: [.displayFeature(.mainDisplay), .hardware(.twoDisplays), .perItem("display")],
                    replaces: ["l.menu.d.setMain"],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dSetMain)),
        ControlSpec("menu.display.dm.mirror", .menuItem,
                    when: [.displayFeature(.mirroring), .hardware(.twoDisplays), .perItem("display")],
                    replaces: ["l.menu.d.mirrorMenu"],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dMirrorMenu)),
        ControlSpec("menu.display.dm.rotation", .menuItem,
                    when: [.displayFeature(.rotation), .hardware(.externalDisplay), .perItem("display")],
                    replaces: ["l.menu.d.rotationMenu"],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dRotationMenu)),
        ControlSpec("menu.display.dm.hdr", .menuItem,
                    when: [.displayFeature(.hdrToggle), .hardware(.hdrDisplay), .perItem("display")],
                    replaces: ["l.menu.d.hdrToggle"],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dHDRToggle)),
        ControlSpec("menu.display.dm.underscan", .menuItem,
                    when: [.displayFeature(.underscan), .perItem("display")],
                    replaces: ["l.menu.d.underscanMenu"],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dUnderscanMenu)),
        ControlSpec("menu.display.dm.sharperText", .menuItem,
                    when: [.displayFeature(.smartHiDPI), .perItem("display")],
                    replaces: ["l.menu.d.smartHiDPI"],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dSmartHiDPI)),
        ControlSpec("menu.display.dm.disconnect", .menuItem,
                    when: [.displayFeature(.disconnect), .hardware(.twoDisplays), .perItem("display")],
                    replaces: ["l.menu.d.disconnectItem"],
                    menu: MenuPlacementSpec("display submenu; under the device row when shown", customize: .threeWay,
                                            legacy: .dDisconnectItem)),
        ControlSpec("menu.display.dm.connect", .menuItem,
                    when: [.displayFeature(.disconnect), .state(.disconnectedDisplay), .perItem("display")],
                    replaces: ["l.d.arrangement.connect"],
                    menu: MenuPlacementSpec("disconnected display's submenu", customize: .none, legacy: .dDisconnectItem)),
        ControlSpec("menu.display.dm.preventSleep", .menuItem,
                    when: [.displayFeature(.sleepPrevention), .perItem("display")],
                    menu: MenuPlacementSpec(submenu, customize: .threeWay, legacy: .dSleepPrevention)),
        ControlSpec("menu.display.dm.connectAll", .menuItem,
                    when: [.displayFeature(.disconnect)],
                    replaces: ["l.menu.d.connectAll", "l.d.arrangement.connectAll"],
                    menu: MenuPlacementSpec("Display Tools", customize: .checkbox, legacy: .dConnectAll)),
        ControlSpec("menu.display.dm.disconnectAllButMain", .menuItem,
                    when: [.displayFeature(.disconnect), .hardware(.twoDisplays)],
                    replaces: ["l.menu.d.disconnectAllButMain"],
                    menu: MenuPlacementSpec("Display Tools", customize: .checkbox, legacy: .dDisconnectAllButMain)),
        ControlSpec("menu.display.dm.arrange", .menuItem,
                    when: [.displayFeature(.arrangement), .hardware(.twoDisplays)],
                    replaces: ["l.menu.d.arrange"],
                    menu: MenuPlacementSpec("Displays section", customize: .checkbox, legacy: .dArrange)),
        ControlSpec("menu.display.dm.protectArrangement", .menuItem,
                    when: [.displayFeature(.protection)],
                    replaces: ["l.menu.d.protection"],
                    menu: MenuPlacementSpec("Saved Layouts submenu", customize: .checkbox, legacy: .dProtection)),
    ]
}
