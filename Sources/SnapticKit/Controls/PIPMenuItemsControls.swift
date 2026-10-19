import Foundation

// PIPMenuItems' controls (owner: E; PLAN 0.3 §4.8 "0.2 menu" rows `e.pip.display` and `e.pip.tools`, §5.2): the
// per-display "Show in Picture in Picture" toggle and the Displays section's "Picture in Picture ›" submenu.

package enum PIPMenuItemsControls: ControlTable {
    package static let surface = "menu.display.e"

    private static let displaySubmenu = MenuPlacementSpec("display submenu", customize: .threeWay,
                                                          legacy: DisplayMenuItemID(rawValue: "e.pip.display"))
    private static let displaysSection = MenuPlacementSpec("Displays section", customize: .checkbox,
                                                           legacy: DisplayMenuItemID(rawValue: "e.pip.tools"))
    private static let inPIPSubmenu = MenuPlacementSpec("Picture in Picture submenu", customize: .none)

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.display.e.showInPIP", .menuItem, when: [.displayFeature(.pip), .perItem("display")],
                    replaces: ["l.menu.e.pip.display"], menu: displaySubmenu),
        ControlSpec("menu.display.e.pip", .menuSubmenu, when: [.displayFeature(.pip)],
                    replaces: ["l.menu.e.pip.tools"], menu: displaysSection),
        ControlSpec("menu.display.e.pip.saved", .menuItem, when: [.displayFeature(.pip), .perItem("pip")],
                    menu: inPIPSubmenu),
        ControlSpec("menu.display.e.pip.stopAll", .menuItem, when: [.displayFeature(.pip)],
                    menu: inPIPSubmenu),
        ControlSpec("menu.display.e.pip.more", .menuItem, when: [.displayFeature(.pip)],
                    menu: inPIPSubmenu),
    ]
}
