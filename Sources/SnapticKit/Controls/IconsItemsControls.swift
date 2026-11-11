import Foundation

// IconsItems' controls (lead; PLAN 0.4 §4.1, §4.3): Hidden Icons' own status items. The arrow (click: show or hide;
// ⌥: include Always Hidden; right-click: the arrow's menu), `|` (Length; click: the same menu) and `⋮` (Always
// Hidden). They aren't `StatusItemProvider`s, so the Menu Bar page's icon rows never list them (H2).

package enum IconsItemsControls: ControlTable {
    package static let surface = "menu.iconItems"

    private static let bar = MenuPlacementSpec("Menu bar", customize: .none)
    private static let icons: [ControlCondition] = [.module(.hiddenIcons)]

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.iconItems.arrow", .button, when: icons, menu: bar),
        ControlSpec("menu.iconItems.divider", .button, when: icons + [.iconsEngine(.length)], keys: ["dividers"],
                    menu: bar),
        ControlSpec("menu.iconItems.alwaysHiddenDivider", .button, when: icons, keys: ["alwaysHidden"], menu: bar),
    ]
}
