import Foundation

// Restore All Displays and Resume Display Automation in the Displays menu (owner: B; PLAN 0.3 §4.8 "Registered
// items" b.*, §5.2). PanicCoordinator builds the items; the Displays menu builder places them by their 0.2 id:
// Restore All Displays in Display Tools (and top-level while a change awaits confirmation), Resume under the
// "Display automation is paused" status row, always while paused.

package enum PanicCoordinatorControls: ControlTable {
    package static let surface = "menu.display.b"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.b.restoreAll", .menuItem, replaces: ["l.menu.b.restoreAll"],
                    menu: MenuPlacementSpec("Display Tools", customize: .checkbox,
                                            legacy: DisplayMenuItemID(rawValue: "b.restoreAll"))),
        ControlSpec("menu.display.b.resume", .menuItem, when: [.state(.automationPaused)],
                    replaces: ["l.menu.b.resumeAutomation"],
                    menu: MenuPlacementSpec("Displays section", customize: .checkbox,
                                            legacy: DisplayMenuItemID(rawValue: "b.resumeAutomation"))),
    ]
}
