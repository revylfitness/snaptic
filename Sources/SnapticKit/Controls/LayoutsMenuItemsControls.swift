import Foundation

// LayoutsMenuItems' controls (owner: D; PLAN 0.3 §4.8 "0.2 menu", §5.2): Displays section › Saved Layouts. Its
// "Protect Arrangement" row is ManagementMenuItems' (`menu.display.dm.protectArrangement`).

package enum LayoutsMenuItemsControls: ControlTable {
    package static let surface = "menu.display.d"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.d.savedLayouts", .menuSubmenu,
                    when: [.displayFeature(.layouts)],
                    replaces: ["l.menu.d.layoutsMenu"],
                    menu: MenuPlacementSpec("Displays section", customize: .checkbox, legacy: .dLayoutsMenu)),
        ControlSpec("menu.display.d.savedLayout", .menuItem,
                    when: [.displayFeature(.layouts), .perItem("layout"), .parentOn(ControlID("menu.display.d.savedLayouts"))],
                    menu: MenuPlacementSpec("Saved Layouts submenu", customize: .none, legacy: .dLayoutsMenu)),
        ControlSpec("menu.display.d.applyMatchingLayout", .menuItem,
                    when: [.displayFeature(.layouts), .parentOn(ControlID("menu.display.d.savedLayouts"))],
                    replaces: ["l.menu.d.layoutMatch"],
                    menu: MenuPlacementSpec("Saved Layouts submenu", customize: .checkbox, legacy: .dLayoutMatch)),
        ControlSpec("menu.display.d.saveCurrentLayout", .menuItem,
                    when: [.displayFeature(.layouts), .parentOn(ControlID("menu.display.d.savedLayouts"))],
                    menu: MenuPlacementSpec("Saved Layouts submenu", customize: .none, legacy: .dLayoutsMenu)),
    ]
}
