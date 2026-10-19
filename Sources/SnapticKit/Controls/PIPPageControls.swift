import Foundation

// Displays › Picture in Picture (owner E; PLAN 0.3 §4.3 sub-page row "Picture in Picture (E)", §4.8 "PIP" rows):
// the feature switch, the Screen Recording status row, the Running and Saved lists, New Picture in Picture… / New Stream…,
// Import Color Lookup Table… and the page's Advanced sheet (Filters, Never capture these apps, pause covered PIPs,
// the ⌃⌥⌘P switch). The editor sheet has its own table (`PIPEditorSheetControls`).

package enum PIPPageControls: ControlTable {
    package static let surface = "displays.pip"
    /// `SettingsShell.openSheet` id of the page's Advanced sheet.
    package static let advancedSheet = "displays.pip.advanced"
    /// The page's route (the Displays root's "Picture in Picture ›" row).
    package static let route = SettingsRoute("displays.pip")

    private static let root = SettingsRootID.displays
    private static let pip: [ControlCondition] = [.displayFeature(.pip)]

    private static func page(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: route)
    }

    private static func advanced(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: route, sheet: advancedSheet)
    }

    package static let controls: [ControlSpec] = [
        // Header
        ControlSpec("displays.pip.usePIP", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.pip"],
                    keys: ["features.pip"],
                    search: page("Picture in Picture", ["PIP", "floating window", "live view", "stream",
                                                         "mirror a window", "teleprompter"])),
        // Status
        ControlSpec("displays.pip.status.screenRecording", .statusAction,
                    when: pip + [.state(.screenRecordingMissing)],
                    replaces: ["l.d.pip.screenRecording"]),
        // Running (Pause/Show/Stop per row; Crop in the row menu)
        ControlSpec("displays.pip.running", .list, when: pip,
                    replaces: ["l.d.pip.running.pause", "l.d.pip.running.show", "l.d.pip.running.crop",
                               "l.d.pip.running.stop"],
                    search: page("Running pictures in picture", ["pause", "hide", "show", "crop", "stop"])),
        // Stop All ▾ in the Running header (Pause All, Hide All in its menu)
        ControlSpec("displays.pip.running.stopAll", .button, when: pip,
                    replaces: ["l.d.pip.running.bulk", "l.action.e.pipStopAll", "l.action.e.pipPauseAll",
                               "l.action.e.pipHideAll"],
                    search: page("Stop All Pictures in Picture", ["stop all", "pause all", "hide all"])),
        // Saved (Start, Edit…)
        ControlSpec("displays.pip.saved", .list, when: pip,
                    replaces: ["l.d.pip.config.start", "l.d.pip.config.edit", "l.action.e.pipToggle.*",
                               "l.action.e.pipToggleDisplay"],
                    keys: ["pip.windowConfigurations", "perDisplay.*.pip.configurations"],
                    search: page("Saved pictures in picture", ["start", "edit", "configuration"])),
        ControlSpec("displays.pip.new", .button, when: pip,
                    replaces: ["l.d.pip.new", "l.d.pip.windows", "l.action.e.pipPickWindow"],
                    search: page("New Picture in Picture", ["new PIP", "window", "display", "add"])),
        ControlSpec("displays.pip.newStream", .button, when: pip + [.hardware(.twoDisplays)],
                    replaces: ["l.d.pip.newStream"],
                    search: page("New Stream", ["full screen", "stream", "another display", "teleprompter"])),
        // Color lookup tables
        ControlSpec("displays.pip.importLUT", .button, when: pip,
                    replaces: ["l.d.pip.importLUT"],
                    keys: ["pip.luts"],
                    search: page("Import Color Lookup Table", ["LUT", ".cube", "color grading", "3D LUT"])),
        ControlSpec("displays.pip.luts", .list, when: pip + [.displayFeature(.pipFilters)],
                    search: page("Color lookup tables", ["LUT", "delete LUT"])),
        // Footer
        ControlSpec("displays.pip.advanced", .button, when: [.module(.displays)],
                    search: page("Picture in Picture Advanced Settings", ["PIP options", "privacy"])),
        // Advanced sheet
        ControlSpec("displays.pip.advanced.filters", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.pipFilters"],
                    keys: ["features.pipFilters"],
                    search: advanced("Filters", ["PIP filters", "effects", "color adjustments", "LUT"])),
        ControlSpec("displays.pip.advanced.neverCapture", .setting, when: [.module(.displays)],
                    replaces: ["l.d.pip.privacy.prefixes"],
                    keys: ["pip.protectedBundlePrefixes"],
                    search: advanced("Never capture these apps", ["privacy", "password manager", "exclude",
                                                                  "hide app", "capture"])),
        ControlSpec("displays.pip.advanced.restoreApps", .button, when: [.module(.displays), .state(.notAtDefault)],
                    replaces: ["l.d.pip.privacy.restoreDefaults"],
                    search: advanced("Restore Default Apps", ["never capture", "privacy defaults"])),
        ControlSpec("displays.pip.advanced.pauseCovered", .setting, when: [.module(.displays)],
                    replaces: ["l.d.pip.pauseWhenOccluded"],
                    keys: ["pip.pauseWhenOccluded"],
                    search: advanced("Pause pictures in picture that are covered", ["occluded", "hidden", "energy"])),
        ControlSpec("displays.pip.advanced.stopShortcut", .setting, when: [.module(.displays)],
                    replaces: ["l.d.pip.stopHotkeyEnabled"],
                    keys: ["pip.stopHotkeyEnabled"],
                    search: advanced("⌃⌥⌘P stops streams", ["shortcut", "hotkey", "click-through", "stop stream"])),
        ControlSpec("displays.pip.advanced.restoreDefaults", .button, when: [.module(.displays)],
                    search: advanced("Restore Picture in Picture Defaults", ["reset PIP"])),
    ]
}
