import Foundation

// The Window Switcher's menu section (owner: A; PLAN 0.3 §5.2, §4.8): built by `WindowSwitcherModule.menuSection()`
// on MenuKit, in the Snaptic menu or the Switcher's own menu.

package enum WindowSwitcherModuleControls: ControlTable {
    package static let surface = "menu.switcher"

    private static let section = MenuPlacementSpec("Window Switcher section", customize: .none)

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.switcher.grantAccessibility", .menuItem, when: [.state(.accessibilityMissing)], menu: section),
        // C8: opens the switcher in sticky mode; replaces 0.2's "Press ⌥⇥ to switch" hint row.
        ControlSpec("menu.switcher.switchWindows", .menuItem, replaces: ["l.menu.fixed.switcher.pressHint"], menu: section),
        ControlSpec("menu.switcher.noShortcut", .menuItem, menu: section),
        ControlSpec("menu.switcher.gather", .menuItem, replaces: ["l.menu.fixed.switcher.gather"], menu: section),
        ControlSpec("menu.switcher.turnOnThumbnails", .menuItem, when: [.state(.screenRecordingMissing)],
                    replaces: ["l.menu.fixed.switcher.enableThumbnails"], menu: section),
    ]
}
