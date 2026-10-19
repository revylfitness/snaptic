import Foundation

// The Sessions sheet (owner: G; PLAN 0.3 §4.3 "Sessions sheet", R5-11): the presets shown in Start Session › and the
// Keep Awake ▾ list, in order, each with an Options disclosure (name, kind, length or time, At most, thresholds,
// display, activity).

package enum PresetEditorSheetControls: ControlTable {
    package static let surface = "awake.sessions"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "awake.sessions"

    private static let root = SettingsRootID.awake
    private static let awake: [ControlCondition] = [.module(.awake)]
    private static let preset: [ControlCondition] = [.module(.awake), .perItem("preset")]

    package static let controls: [ControlSpec] = [
        ControlSpec("awake.sessions.list", .list, when: awake, keys: ["sessions.presets"],
                    search: SearchSpec("Sessions", keywords: ["presets", "durations", "reorder sessions"], root: root,
                                       sheet: sheet)),
        ControlSpec("awake.sessions.add", .button, when: awake,
                    search: SearchSpec("Add Session", keywords: ["new preset"], root: root, sheet: sheet)),
        ControlSpec("awake.sessions.name", .setting, when: preset,
                    search: SearchSpec("Session name", keywords: ["rename preset"], root: root, sheet: sheet)),
        ControlSpec("awake.sessions.kind", .setting, when: preset,
                    search: SearchSpec("Session kind", keywords: ["for a duration", "until a time",
                                                                  "until downloads and tasks finish"], root: root,
                                       sheet: sheet)),
        ControlSpec("awake.sessions.duration", .setting, when: preset,
                    search: SearchSpec("Session length", keywords: ["hours", "minutes"], root: root, sheet: sheet)),
        ControlSpec("awake.sessions.untilTime", .setting, when: preset,
                    search: SearchSpec("Session end time", keywords: ["until"], root: root, sheet: sheet)),
        ControlSpec("awake.sessions.atMost", .setting, when: preset,
                    search: SearchSpec("At most", keywords: ["limit", "cap"], root: root, sheet: sheet)),
        ControlSpec("awake.sessions.thresholds", .setting, when: preset,
                    search: SearchSpec("Activity thresholds", keywords: ["CPU", "disk", "network", "quiet",
                                                                         "downloads"], root: root, sheet: sheet)),
        ControlSpec("awake.sessions.display", .setting, when: preset,
                    search: SearchSpec("Session display", keywords: ["keep on", "can turn off", "until idle"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.sessions.activity", .setting, when: preset + [.awakeFeature(.activity)],
                    search: SearchSpec("Session activity", keywords: ["appear active", "move the pointer"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.sessions.restore", .button, when: awake,
                    search: SearchSpec("Restore Default Sessions", keywords: ["reset presets"], root: root,
                                       sheet: sheet)),
    ]
}
