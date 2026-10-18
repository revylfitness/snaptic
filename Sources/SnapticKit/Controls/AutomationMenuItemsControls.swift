import Foundation

// The custom actions' menu items (owner: A; PLAN 0.3 §5.2 "Actions ›", §4.8 `a.custom.<id>`, R5-13): built by
// `AutomationMenuItems` on MenuKit, one per action marked "Show in menu" (the same flag as the checkbox in Customize
// Displays Menu).

package enum AutomationMenuItemsControls: ControlTable {
    package static let surface = "menu.display.a"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.a.action", .menuItem,
                    when: [.displayFeature(.customActions), .perItem("customAction")],
                    replaces: ["l.menu.a.custom.*"],
                    menu: MenuPlacementSpec("Displays section, Actions submenu", customize: .checkbox)),
    ]
}
