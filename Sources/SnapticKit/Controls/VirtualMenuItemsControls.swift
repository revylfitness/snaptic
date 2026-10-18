import Foundation

// VirtualMenuItems' controls (owner: D; PLAN 0.3 §4.8 "0.2 menu", §5.2): Displays section › Virtual Displays.

package enum VirtualMenuItemsControls: ControlTable {
    package static let surface = "menu.display.d"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.d.virtualDisplays", .menuSubmenu,
                    when: [.displayFeature(.virtualScreens)],
                    replaces: ["l.menu.d.virtualMenu"],
                    menu: MenuPlacementSpec("Displays section", customize: .checkbox, legacy: .dVirtualMenu)),
        ControlSpec("menu.display.d.virtualDisplay", .menuItem,
                    when: [.displayFeature(.virtualScreens), .perItem("virtualDisplay"),
                           .parentOn(ControlID("menu.display.d.virtualDisplays"))],
                    menu: MenuPlacementSpec("Virtual Displays submenu", customize: .none, legacy: .dVirtualMenu)),
        ControlSpec("menu.display.d.virtualSettings", .menuItem,
                    when: [.displayFeature(.virtualScreens), .parentOn(ControlID("menu.display.d.virtualDisplays"))],
                    menu: MenuPlacementSpec("Virtual Displays submenu", customize: .none, legacy: .dVirtualMenu)),
    ]
}
