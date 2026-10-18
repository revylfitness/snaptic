import Foundation

/// Window Switcher › More Shortcuts… (H; PLAN 0.3 §4.3, design m12): the other switcher shortcuts with their own
/// options, Add Shortcut, Delete Shortcut, and the Gather Windows shortcut.
package enum SwitcherShortcutsSheetControls: ControlTable {
    package static let surface = "switcher.shortcuts"
    package static let sheet = "switcher.shortcuts"
    package static let controls: [ControlSpec] = [
        ControlSpec("switcher.shortcuts.list", .list, when: [.perItem("shortcut")]),
        ControlSpec("switcher.shortcuts.add", .button, replaces: ["l.sw.shortcut.add"],
                    search: SearchSpec("Add Shortcut", keywords: ["another shortcut", "second shortcut"],
                                       root: SettingsRootID.windowSwitcher, sheet: sheet)),
        ControlSpec("switcher.shortcuts.delete", .button, when: [.perItem("shortcut")], replaces: ["l.sw.shortcut.delete"]),
        ControlSpec("switcher.shortcuts.gather", .shortcut, replaces: ["l.sw.gatherShortcut"], keys: ["gatherShortcut"],
                    search: SearchSpec("Gather windows", keywords: ["move windows", "gather", "shortcut"],
                                       root: SettingsRootID.windowSwitcher, sheet: sheet)),
    ]
}
