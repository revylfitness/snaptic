import Foundation

// The Awake page (owner: G; PLAN 0.3 §4.3 "Awake", §1.4, R5-9, R5-10, R5-11, R5-12): header switch "Use Awake", the
// status row (Keep Awake ▾, Options ▾, Turn Off, Pause Rules ▾ / Resume), Sessions, End sessions automatically
// (laptops), Start automatically (rules), Keyboard Shortcuts… (its sheet's rows are here too), Drives ›, History ›
// and the footer. Awake is new in 0.3; the 0.2 Displays sleep prevention it took over (feature switch, Arrangement
// row, hotkey) lives on as rules through migration M1 and the Pause Rules shortcut (R5-12).

package enum AwakePageControls: ControlTable {
    package static let surface = "awake.page"
    /// `SettingsShell.openSheet` id of the Keyboard Shortcuts sheet.
    package static let shortcutsSheet = "awake.shortcuts"
    /// The History sub-page (`AwakeModule.settingsDestination`); Drives is J's `DrivesPage.route`.
    package static let historyRoute = SettingsRoute(AwakeHistoryPageControls.surface)
    /// The Start automatically list's anchor (the Awake menus' Rules › rows and Edit Rules… reveal it).
    package static let rulesAnchor = "awake.page.rules"

    private static let root = SettingsRootID.awake
    private static let awake: [ControlCondition] = [.module(.awake)]

    package static let controls: [ControlSpec] = [
        ControlSpec("awake.page.useAwake", .setting, keys: ["modules.*.enabled"],
                    search: SearchSpec("Use Awake", keywords: ["keep awake", "caffeinate", "prevent sleep", "turn on",
                                                               "turn off"], root: root)),
        // Safe Mode row (ux N2, N5: the shared Leave Safe Mode confirmation).
        ControlSpec("awake.page.leaveSafeMode", .statusAction, when: awake + [.state(.safeMode)]),
        // Status row (R5-9: every session kind starts from Settings alone; R5-10, R5-11).
        ControlSpec("awake.page.status.keepAwake", .statusAction, when: awake + [.state(.awakeIdle)],
                    search: SearchSpec("Keep Awake", keywords: ["start session", "keep awake now", "stay awake"],
                                       root: root)),
        ControlSpec("awake.page.status.keepAwakeMenu", .statusAction,
                    when: awake + [.state(.awakeIdle), .perItem("preset")], keys: ["sessions.recentApps"],
                    search: SearchSpec("Start a session", keywords: ["for 1 hour", "while an app is running",
                                                                     "until downloads finish", "custom duration"],
                                       root: root)),
        ControlSpec("awake.page.status.options", .statusAction, when: awake + [.state(.awakeActive)],
                    search: SearchSpec("Session options", keywords: ["add time", "extend", "keep display on",
                                                                     "end command-line holds"], root: root)),
        ControlSpec("awake.page.status.replaceWith", .statusAction,
                    when: awake + [.state(.awakeActive), .perItem("preset")]),
        ControlSpec("awake.page.status.turnOff", .statusAction, when: awake + [.state(.awakeActive)],
                    search: SearchSpec("Turn Off Keep Awake", keywords: ["stop session", "end session"], root: root)),
        ControlSpec("awake.page.status.pauseRules", .statusAction,
                    when: awake + [.awakeFeature(.triggers), .state(.rulesExist)],
                    search: SearchSpec("Pause Rules", keywords: ["pause automatic", "for 1 hour", "until tomorrow"],
                                       root: root)),
        ControlSpec("awake.page.status.resume", .statusAction,
                    when: awake + [.awakeFeature(.triggers), .state(.rulesPaused)]),
        // Sessions.
        ControlSpec("awake.page.defaultSession", .setting, when: awake, keys: ["sessions.defaultPresetID"],
                    search: SearchSpec("Default session", keywords: ["default duration", "keep awake for",
                                                                     "until turned off"], root: root)),
        ControlSpec("awake.page.keepDisplayOn", .setting, when: awake, keys: ["sessions.defaultOptions"],
                    search: SearchSpec("Keep the display on", keywords: ["display sleep", "screen off",
                                                                         "let the display sleep"], root: root)),
        ControlSpec("awake.page.sessions", .button, when: awake,
                    search: SearchSpec("Sessions in the menu", keywords: ["presets", "durations", "edit sessions"],
                                       root: root)),
        // End sessions automatically (laptops only).
        ControlSpec("awake.page.batteryLow", .setting, when: awake + [.hardware(.battery)],
                    keys: ["guards.batteryFloorEnabled"],
                    search: SearchSpec("End sessions when the battery is low", keywords: ["battery", "low battery"],
                                       root: root)),
        ControlSpec("awake.page.batteryFloor", .setting,
                    when: awake + [.hardware(.battery), .parentOn(ControlID("awake.page.batteryLow"))],
                    keys: ["guards.batteryFloor"],
                    search: SearchSpec("Battery level", keywords: ["battery percentage", "floor"], root: root)),
        ControlSpec("awake.page.adapter", .setting, when: awake + [.hardware(.battery)],
                    keys: ["guards.endOnAdapterDisconnect"],
                    search: SearchSpec("End sessions when the power adapter is disconnected",
                                       keywords: ["charger", "unplugged", "AC power"], root: root)),
        // Start automatically: Displays' 0.2 sleep prevention (feature switch and the Arrangement row) became rules
        // through migration M1.
        ControlSpec("awake.page.rules", .list, when: awake,
                    replaces: ["l.dfeat.sleepPrevention", "l.d.arrangement.preventSleep"], keys: ["triggers"],
                    search: SearchSpec("Start automatically", keywords: ["rules", "triggers", "automatic",
                                                                         "while a display is connected",
                                                                         "prevent display sleep", "schedule"],
                                       root: root)),
        ControlSpec("awake.page.addRule", .button, when: awake,
                    search: SearchSpec("Add Rule", keywords: ["new rule", "new trigger"], root: root)),
        // Keyboard.
        ControlSpec("awake.page.shortcuts", .button, when: awake + [.awakeFeature(.shortcuts)],
                    search: SearchSpec("Awake keyboard shortcuts", keywords: ["hotkeys"], root: root)),
        ControlSpec("awake.page.shortcut.toggle", .shortcut, when: awake + [.awakeFeature(.shortcuts)],
                    keys: ["shortcuts"],
                    search: SearchSpec("Keep Awake shortcut", keywords: ["hotkey", "toggle"], root: root,
                                       sheet: shortcutsSheet)),
        ControlSpec("awake.page.shortcut.keepDisplayOn", .shortcut, when: awake + [.awakeFeature(.shortcuts)],
                    search: SearchSpec("Keep Display On shortcut", keywords: ["hotkey"], root: root,
                                       sheet: shortcutsSheet)),
        ControlSpec("awake.page.shortcut.preset", .shortcut,
                    when: awake + [.awakeFeature(.shortcuts), .perItem("preset")],
                    search: SearchSpec("Start session shortcuts", keywords: ["hotkey", "preset"], root: root,
                                       sheet: shortcutsSheet)),
        // R5-12: M1 binds the 0.2 display-sleep hotkey here.
        ControlSpec("awake.page.shortcut.pauseRules", .shortcut, when: awake + [.awakeFeature(.shortcuts)],
                    replaces: ["l.action.d.sleepPreventionToggle"],
                    search: SearchSpec("Pause Rules shortcut", keywords: ["hotkey", "display sleep shortcut"],
                                       root: root, sheet: shortcutsSheet)),
        // Navigation and footer.
        ControlSpec("awake.page.nav.drives", .navigation, when: awake,
                    search: SearchSpec("Drives", keywords: ["keep drives awake", "drive alive", "spin down",
                                                            "external disk"], root: root)),
        ControlSpec("awake.page.nav.history", .navigation, when: awake + [.awakeFeature(.history)],
                    search: SearchSpec("Awake history", keywords: ["statistics", "sessions", "today"], root: root)),
        ControlSpec("awake.page.menuBar", .button,
                    search: SearchSpec("Awake in the menu bar", keywords: ["menu bar icon", "status item"],
                                       root: root)),
        ControlSpec("awake.page.advanced", .button,
                    search: SearchSpec("Awake Advanced Settings", keywords: ["appear active", "end sessions",
                                                                             "other apps"], root: root)),
    ]
}
