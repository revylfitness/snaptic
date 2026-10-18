import Foundation

// Awake › Advanced (owner: G; PLAN 0.3 §4.3 "Advanced (11)", §2.14, R5-11): Activity, End sessions automatically,
// Display, Restart, and the live "Other apps keeping your Mac awake" section (OtherAssertionsSection, J's reader).
// Footer: Restore Awake Defaults… (keeps history, the rules, the indicator and the shortcuts).

package enum AwakeAdvancedSheetControls: ControlTable {
    package static let surface = "awake.advanced"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "awake.advanced"

    private static let root = SettingsRootID.awake
    private static let awake: [ControlCondition] = [.module(.awake)]

    package static let controls: [ControlSpec] = [
        // Activity.
        ControlSpec("awake.advanced.appearActive", .setting, when: awake, keys: ["sessions.defaultOptions.activity"],
                    search: SearchSpec("Appear active", keywords: ["away status", "idle", "user activity", "Slack",
                                                                   "Teams"], root: root, sheet: sheet)),
        ControlSpec("awake.advanced.pointerNudge", .setting,
                    when: awake + [.parentOn(ControlID("awake.advanced.appearActive"))],
                    search: SearchSpec("Move the pointer slightly", keywords: ["jiggle", "mouse", "cursor"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.advanced.stopAfter", .setting,
                    when: awake + [.parentOn(ControlID("awake.advanced.appearActive"))],
                    keys: ["activity.stopAfterHours"],
                    search: SearchSpec("Stop appearing active after", keywords: ["limit", "hours"], root: root,
                                       sheet: sheet)),
        // End sessions automatically.
        ControlSpec("awake.advanced.endOnSleep", .setting, when: awake, keys: ["sessions.behavior.endOnSystemSleep"],
                    search: SearchSpec("End sessions when your Mac sleeps", keywords: ["lid", "sleep"], root: root,
                                       sheet: sheet)),
        ControlSpec("awake.advanced.userSwitch", .setting, when: awake, keys: ["sessions.behavior.userSwitchEnd"],
                    search: SearchSpec("End sessions when you switch users", keywords: ["fast user switching"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.advanced.lowPowerMode", .setting, when: awake, keys: ["guards.endOnLowPowerMode"],
                    search: SearchSpec("End sessions when Low Power Mode turns on", keywords: ["battery saver"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.advanced.endAfterLocked", .setting, when: awake,
                    keys: ["sessions.behavior.endAfterLockedHours"],
                    search: SearchSpec("End sessions after the screen has been locked", keywords: ["lock screen"],
                                       root: root, sheet: sheet)),
        // Display.
        ControlSpec("awake.advanced.keepDisplayOnWhileLocked", .setting, when: awake,
                    keys: ["sessions.behavior.keepDisplayOnWhileLocked"],
                    search: SearchSpec("Keep the display on while locked", keywords: ["lock screen", "display sleep"],
                                       root: root, sheet: sheet)),
        // Restart.
        ControlSpec("awake.advanced.resumeAfterRestart", .setting, when: awake,
                    keys: ["sessions.behavior.resumeAfterRestart"],
                    search: SearchSpec("Continue sessions after Snaptic restarts", keywords: ["relaunch", "resume"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.advanced.startAtLaunch", .setting, when: awake, keys: ["sessions.behavior.startAtLaunch"],
                    search: SearchSpec("Start a session when Snaptic opens", keywords: ["launch", "login"], root: root,
                                       sheet: sheet)),
        // Other apps (always present; read live while shown).
        ControlSpec("awake.advanced.otherApps", .list, when: awake,
                    search: SearchSpec("Other apps keeping your Mac awake", keywords: ["assertions", "power assertions",
                                                                                       "sleep disabled", "insomnia",
                                                                                       "amphetamine"],
                                       root: root, sheet: sheet)),
        ControlSpec("awake.advanced.restore", .button, keys: ["features", "sessions", "guards", "activity"],
                    search: SearchSpec("Restore Awake Defaults", keywords: ["reset"], root: root, sheet: sheet)),
    ]
}
