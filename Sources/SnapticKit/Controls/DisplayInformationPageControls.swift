import Foundation

// Displays › Display Information (owner F; PLAN 0.3 §4.3 "Display Information", design M4; replaces the 0.2
// Diagnostics page and the status parts of the 0.2 Safety and Display Names pages): the live report with Copy and
// Export, EDID export, the safety helper's state, what's unavailable on this Mac, and the remembered displays and
// resolutions.

package enum DisplayInformationPageControls: ControlTable {
    package static let surface = "displays.info"

    private static let root = SettingsRootID.displays
    private static let route = SettingsRoute(surface)

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.info.copyReport", .button,
                    replaces: ["l.d.diagnostics.copyReport"],
                    search: SearchSpec("Copy Report", keywords: ["diagnostics", "bug report", "support", "copy"],
                                       root: root, route: route)),
        ControlSpec("displays.info.export", .button, replaces: ["l.d.diagnostics.export"],
                    search: SearchSpec("Export Report", keywords: ["diagnostics", "save report"], root: root,
                                       route: route)),
        ControlSpec("displays.info.report", .list, replaces: ["l.d.diagnostics.report"],
                    search: SearchSpec("Diagnostics report", keywords: ["recent events", "log", "effective features"],
                                       root: root, route: route)),
        ControlSpec("displays.info.exportEDID", .button, when: [.module(.displays), .perItem("display")],
                    replaces: ["l.d.names.edid.export"],
                    search: SearchSpec("Export EDID", keywords: ["EDID", "bin", "display data"], root: root,
                                       route: route)),
        ControlSpec("displays.info.safetyHelper", .list, when: [.module(.displays)],
                    replaces: ["l.d.safety.helper.status", "l.d.safety.helper.canRevert",
                               "l.d.safety.pendingConfirmation", "l.d.safety.undoJournal"],
                    search: SearchSpec("Safety helper", keywords: ["guard", "undo journal", "pending confirmation",
                                                                   "revert rotation"], root: root, route: route)),
        ControlSpec("displays.info.restartHelper", .statusAction, when: [.state(.helperStopped)]),
        ControlSpec("displays.info.unavailable", .list, when: [.module(.displays)],
                    replaces: ["l.d.safety.unavailable"],
                    search: SearchSpec("Unavailable on this Mac", keywords: ["unsupported", "missing", "private API"],
                                       root: root, route: route)),
        ControlSpec("displays.info.remembered", .list, when: [.state(.disconnectedDisplay)],
                    search: SearchSpec("Remembered displays", keywords: ["forget display", "saved displays"],
                                       root: root, route: route)),
        ControlSpec("displays.info.forgetAll", .button, when: [.state(.disconnectedDisplay)],
                    replaces: ["l.d.names.forgetAll"],
                    search: SearchSpec("Forget All Remembered Displays", keywords: ["forget", "remove settings"],
                                       root: root, route: route)),
        ControlSpec("displays.info.rememberedResolutions", .list, replaces: ["l.d.safety.keptModes.forget"],
                    keys: ["safety.keptModes"],
                    search: SearchSpec("Remembered resolutions", keywords: ["kept modes", "don't ask again"],
                                       root: root, route: route)),
    ]
}
