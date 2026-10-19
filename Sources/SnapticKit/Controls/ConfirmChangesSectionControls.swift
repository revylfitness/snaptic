import Foundation

// Displays › Advanced › Confirm display changes (owner: B; PLAN 0.3 §4.3 Displays › Advanced group 2, §4.4
// duplicates 1, 2 and 14, §4.6 M6). The 0.2 Safety page's settings. Its other rows have homes elsewhere (§4.8):
// Restore All Displays Now in Display Tools (DisplaysPage, DisplaysMenuBuilder); helper status, "can revert rotation
// and HDR", pending confirmation, undo journal, remembered resolutions and "unavailable on this Mac" on Display
// Information (F). Search entries open F's Advanced sheet and scroll to the row (`SettingsIndex` derives them).

package enum ConfirmChangesSectionControls: ControlTable {
    package static let surface = "displays.advanced.confirm"

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, sheet: DisplaysAdvancedSheetControls.sheet)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.advanced.confirm.resume", .statusAction, when: [.state(.automationPaused)],
                    replaces: ["l.d.safety.resume"]),
        ControlSpec("displays.advanced.confirm.resolution", .setting,
                    replaces: ["l.d.safety.confirm", "l.d.resolution.confirm"],
                    keys: ["safety.confirmResolution"],
                    search: search("Confirm resolution changes", ["safety", "keep this change", "revert", "resolution"])),
        ControlSpec("displays.advanced.confirm.revertAfter", .setting,
                    replaces: ["l.d.safety.confirmSeconds"],
                    keys: ["safety.confirmSeconds"],
                    search: search("Revert after", ["safety", "countdown", "seconds", "timeout", "keep this change"])),
        ControlSpec("displays.advanced.confirm.announceRecovery", .setting,
                    replaces: ["l.d.safety.announceRecovery"],
                    keys: ["safety.announceRecovery"],
                    search: search("Tell me when displays were restored", ["safety", "recovery", "crash", "notice"])),
        ControlSpec("displays.advanced.confirm.shortcut", .shortcut,
                    // §4.4 #14: the one place the Restore All Displays shortcut is edited (Keyboard Shortcuts mirrors it).
                    replaces: ["l.d.safety.panicHotkey", "l.action.b.restoreAll"],
                    keys: ["safety.panicHotkey", "safety.panicHotkeyEnabled"],
                    search: search("Restore All Displays shortcut", ["panic", "keyboard shortcut", "safety", "escape"])),
        ControlSpec("displays.advanced.confirm.useDefaultShortcut", .button),
        ControlSpec("displays.advanced.confirm.allowedWithoutAsking", .list,
                    replaces: ["l.d.safety.allowedWithoutAsking", "l.d.ddc.allowedWithoutAsking"],
                    keys: ["safety.preConfirmAllowed"],
                    search: search("Allowed without asking", ["safety", "input", "standby", "hardware controls", "DDC"])),
        ControlSpec("displays.advanced.confirm.askAgain", .button, when: [.perItem("display")]),
    ]
}
