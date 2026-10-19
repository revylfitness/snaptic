import Foundation

// Arrange Displays… and the root page's Arrangement rows (owner: D; PLAN 0.3 §4.3 Arrangement): "Use as" and the
// Arrange Displays… button on the root page, and the sheet's canvas, Snap to edges and keyboard placement.

package enum ArrangeSheetControls: ControlTable {
    package static let surface = "displays.arrange"
    /// `SettingsShell.openSheet` id of the sheet (the root page presents it).
    package static let sheet = "displays.arrange"

    private static let root = SettingsRootID.displays
    private static let arranging: [ControlCondition] = [.module(.displays), .displayFeature(.arrangement),
                                                        .hardware(.twoDisplays)]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.arrange.useAs", .setting, when: [.module(.displays), .hardware(.twoDisplays), .perItem("display")],
                    replaces: ["l.d.arrangement.mainDisplay", "l.d.arrangement.mirroring"],
                    search: SearchSpec("Use as", keywords: ["main display", "extended display", "mirror", "menu bar display"],
                                       root: root)),
        ControlSpec("displays.arrange.open", .button, when: arranging,
                    search: SearchSpec("Arrange Displays", keywords: ["arrangement", "position", "move display"],
                                       root: root)),
        ControlSpec("displays.arrange.canvas", .setting, when: arranging,
                    replaces: ["l.d.arrangement.canvas"],
                    search: SearchSpec("Display arrangement", keywords: ["drag displays", "position"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.arrange.snap", .setting, when: arranging,
                    replaces: ["l.d.arrangement.snap"], keys: ["management.snapArrangement"],
                    search: SearchSpec("Snap to edges", keywords: ["align displays", "arrangement"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.arrange.position", .button, when: arranging,
                    replaces: ["l.d.arrangement.positionForm"],
                    search: SearchSpec("Move with the keyboard", keywords: ["position", "align", "place display"],
                                       root: root, sheet: sheet)),
    ]
}
