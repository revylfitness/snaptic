import Foundation

// Dock Previews › Advanced (lead; PLAN 0.5 §4.18, §4.10, §4.15, §4.16): sort, keys, apps with no open windows, other
// Dock preview tools, VoiceOver, the shared Privacy section, the Dock-only hidden apps list, and the read-only kill
// switches. Footer: the sheet's own Restore Defaults (its rows only; never the shared privacy keys).

package enum DockAdvancedSheetControls: ControlTable {
    package static let surface = "dock.advanced"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "dock.advanced"

    private static let root = SettingsRootID.dockPreviews
    private static let dock: [ControlCondition] = [.module(.dockPreviews)]

    package static let controls: [ControlSpec] = [
        ControlSpec("dock.advanced.sort", .setting, when: dock, keys: ["sort"],
                    search: SearchSpec("Sort windows by", keywords: ["order", "recently used", "minimized", "title"],
                                       root: root, sheet: sheet)),
        ControlSpec("dock.advanced.keys", .setting, when: dock, keys: ["keys"],
                    search: SearchSpec("Keyboard shortcuts in previews",
                                       keywords: ["keyboard", "arrow keys", "shortcut", "return", "escape"],
                                       root: root, sheet: sheet)),
        ControlSpec("dock.advanced.windowlessApps", .setting, when: dock, keys: ["windowlessApps"],
                    search: SearchSpec("Apps with no open windows", keywords: ["no windows", "empty", "small card"],
                                       root: root, sheet: sheet)),
        ControlSpec("dock.advanced.otherTools", .setting, when: dock, keys: ["runAlongsideOtherTools"],
                    search: SearchSpec("When another app shows Dock previews",
                                       keywords: ["dockdoor", "hyperdock", "conflict", "run both anyway", "pause"],
                                       root: root, sheet: sheet)),
        ControlSpec("dock.advanced.voiceOver", .setting, when: dock, keys: ["showWithVoiceOver"],
                    search: SearchSpec("Show previews while VoiceOver is on",
                                       keywords: ["voiceover", "screen reader", "accessibility"], root: root,
                                       sheet: sheet)),
        // Privacy: the switcher's two fields, shared (§4.10). Both sheets bind to the same store.
        ControlSpec("dock.advanced.protectPrivate", .setting, when: dock, keys: ["protectPrivateWindows"],
                    search: SearchSpec("Protect private windows",
                                       keywords: ["privacy", "password managers", "never show thumbnails"], root: root,
                                       sheet: sheet)),
        ControlSpec("dock.advanced.privateApps", .list,
                    when: dock + [.parentOn(ControlID("dock.advanced.protectPrivate"))], keys: ["privateBundleIDs"],
                    search: SearchSpec("Never show thumbnails for", keywords: ["private apps", "password managers",
                                                                               "privacy"], root: root, sheet: sheet)),
        // Outside the Privacy section: Dock only.
        ControlSpec("dock.advanced.hiddenApps", .list, when: dock, keys: ["hiddenBundleIDs"],
                    search: SearchSpec("Apps hidden from Dock previews",
                                       keywords: ["exclude", "ignore", "hide app", "never preview"], root: root,
                                       sheet: sheet)),
        // Diagnostics lock rows: `Dock.disable.*` and `Windows.disable.*` only.
        ControlSpec("dock.advanced.killSwitch", .list, when: dock + [.perItem("killSwitch")]),
        ControlSpec("dock.advanced.restore", .button, when: dock,
                    keys: ["sort", "keys", "windowlessApps", "runAlongsideOtherTools", "showWithVoiceOver",
                           "hiddenBundleIDs"],
                    search: SearchSpec("Restore Dock Previews advanced defaults", keywords: ["reset", "defaults"],
                                       root: root, sheet: sheet)),
    ]
}
