import Foundation

// Restore All Displays in the Displays menu (owner: B; PLAN 0.3 §4.8 "Registered items" b.*, §5.2). Display Tools
// holds the item; while a change awaits confirmation a copy sits at the top level of the Displays section; while
// automation is paused the section starts with a status row and Resume Display Automation.

package enum PanicCoordinatorControls: ControlTable {
    package static let surface = "menu.display.b"

    private static let tools = MenuPlacementSpec("Display Tools", customize: .checkbox,
                                                 legacy: DisplayMenuItemID(rawValue: "b.restoreAll"))
    private static let section = MenuPlacementSpec("Displays section", customize: .none)

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.b.restoreAll", .menuItem, replaces: ["l.menu.b.restoreAll"], menu: tools),
        ControlSpec("menu.display.b.restoreAllPending", .menuItem, when: [.state(.pendingConfirmation)], menu: section),
        ControlSpec("menu.display.b.paused", .menuItem, when: [.state(.automationPaused)], menu: section),
        ControlSpec("menu.display.b.resume", .menuItem, when: [.state(.automationPaused)],
                    replaces: ["l.menu.b.resumeAutomation"],
                    menu: MenuPlacementSpec("Displays section", customize: .none,
                                            legacy: DisplayMenuItemID(rawValue: "b.resumeAutomation"))),
    ]
}
