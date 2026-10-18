import Foundation

// IndicatorController's controls (owner: G; PLAN 0.3 §5.3): Awake's own status item. Its menu's rows are
// AwakeMenuRows' (menu.awake.*).

package enum IndicatorControllerControls: ControlTable {
    package static let surface = "menu.awake.item"

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.awake.item.button", .menuItem, menu: MenuPlacementSpec("menu bar", customize: .none)),
    ]
}
