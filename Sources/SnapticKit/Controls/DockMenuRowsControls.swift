import Foundation

// DockMenuRows' controls (lead; PLAN 0.5 §4.19): the Dock Previews section of the Snaptic menu, in order: the status
// item (rows 3 to 8, and a pause held under Starting, row 4 or row 5), Open Accessibility Settings… (row 4), Pause
// for 1 Hour (row 9) or Resume (row 8 and a held pause), and Dock Previews Settings…. Built fresh on each open, through
// MenuKit only.

package enum DockMenuRowsControls: ControlTable {
    package static let surface = "menu.dock"

    private static let rows = MenuPlacementSpec("Dock Previews section", customize: .none)
    private static let dock: [ControlCondition] = [.module(.dockPreviews)]

    package static let controls: [ControlSpec] = [
        ControlSpec("menu.dock.status", .menuItem, when: dock, menu: rows),
        ControlSpec("menu.dock.openPrivacy", .menuItem, when: dock + [.state(.dockNeedsPermission)], menu: rows),
        ControlSpec("menu.dock.pause", .menuItem, when: dock + [.state(.dockWorking)], menu: rows),
        ControlSpec("menu.dock.resume", .menuItem, when: dock + [.state(.dockCommandPause)], menu: rows),
        ControlSpec("menu.dock.settings", .menuItem, when: dock, menu: rows),
    ]
}
