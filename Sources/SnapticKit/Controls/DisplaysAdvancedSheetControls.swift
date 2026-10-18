import Foundation

// Displays › Advanced (owner F; PLAN 0.3 §4.3 "Displays › Advanced sheet"): the feature switches without a sub-page
// switch of their own ("Use Snaptic for"), the Experimental group and the permissions status. Confirm display
// changes (B), Other display apps (A) and Resolution filters (D) are the owners' sections with their own tables.

package enum DisplaysAdvancedSheetControls: ControlTable {
    package static let surface = "displays.advanced"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "displays.advanced"

    private static let root = SettingsRootID.displays

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.advanced.useFor.brightness", .setting, replaces: ["l.dfeat.brightness"],
                    keys: ["features.brightness"],
                    search: SearchSpec("Brightness control", keywords: ["brightness feature"], root: root, sheet: sheet)),
        ControlSpec("displays.advanced.useFor.resolution", .setting, replaces: ["l.dfeat.resolution"],
                    keys: ["features.resolution"],
                    search: SearchSpec("Resolution control", keywords: ["resolution feature", "modes"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.advanced.useFor.arrangement", .setting,
                    replaces: ["l.dfeat.arrangement", "l.dfeat.mainDisplay", "l.dfeat.mirroring"],
                    keys: ["features.arrangement", "features.mainDisplay", "features.mirroring"],
                    search: SearchSpec("Arrangement and mirroring", keywords: ["main display", "mirror"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.advanced.useFor.rotation", .setting, replaces: ["l.dfeat.rotation"],
                    keys: ["features.rotation"],
                    search: SearchSpec("Rotation", keywords: ["rotate", "portrait"], root: root, sheet: sheet)),
        ControlSpec("displays.advanced.useFor.shortcuts", .setting, replaces: ["l.dfeat.shortcuts"],
                    keys: ["features.shortcuts"],
                    search: SearchSpec("Keyboard shortcuts for displays", keywords: ["hotkeys"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.advanced.useFor.indicator", .setting, replaces: ["l.dfeat.osd"],
                    keys: ["features.osd"],
                    search: SearchSpec("Brightness indicator", keywords: ["OSD", "on-screen display", "HUD"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.advanced.useFor.disconnect", .setting, replaces: ["l.dfeat.disconnect"],
                    keys: ["features.disconnect"],
                    search: SearchSpec("Disconnect displays", keywords: ["turn display off", "disable display"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.advanced.experimental.hdr", .setting, replaces: ["l.dfeat.hdrToggle"],
                    keys: ["features.hdrToggle"],
                    search: SearchSpec("High Dynamic Range switch", keywords: ["HDR"], root: root, sheet: sheet)),
        ControlSpec("displays.advanced.experimental.underscan", .setting, replaces: ["l.dfeat.underscan"],
                    keys: ["features.underscan"],
                    search: SearchSpec("Underscan", keywords: ["overscan", "TV"], root: root, sheet: sheet)),
        ControlSpec("displays.advanced.experimental.autoBrightness", .setting, replaces: ["l.dfeat.autoBrightness"],
                    keys: ["features.autoBrightness"],
                    search: SearchSpec("Built-in auto-brightness", keywords: ["ambient light", "automatic brightness"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.advanced.experimental.broadcast", .setting,
                    replaces: ["l.dfeat.osdBroadcast", "l.d.osd.broadcastName"],
                    keys: ["features.osdBroadcast"],
                    search: SearchSpec("Brightness broadcast", keywords: ["notification", "other apps"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.advanced.experimental.allResolutions", .setting, replaces: ["l.dfeat.hiddenModes"],
                    keys: ["features.hiddenModes"],
                    search: SearchSpec("Show all resolutions", keywords: ["hidden modes"], root: root, sheet: sheet)),
        ControlSpec("displays.advanced.permissions", .statusAction, when: [.state(.accessibilityMissing)],
                    replaces: ["l.d.features.permissionRows"]),
    ]
}
