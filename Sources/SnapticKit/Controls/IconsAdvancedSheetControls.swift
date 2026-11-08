import Foundation

// Hidden Icons › Advanced (lead; PLAN 0.4 §4.9, §4.7, §4.10, §4.2.5): hover, new apps' icons (macOS 27), other
// hiders, the full menu bar, Reset Arrow Position…, and Diagnostics with the read-only kill switches. Footer: the
// sheet's own Restore Defaults (its rows only).

package enum IconsAdvancedSheetControls: ControlTable {
    package static let surface = "icons.advanced"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "icons.advanced"

    private static let root = SettingsRootID.hiddenIcons
    private static let icons: [ControlCondition] = [.module(.hiddenIcons)]

    package static let controls: [ControlSpec] = [
        ControlSpec("icons.advanced.hover", .setting, when: icons, keys: ["hover"],
                    search: SearchSpec("Show icons on hover", keywords: ["pointer", "mouse", "rest", "hover"],
                                       root: root, sheet: sheet)),
        ControlSpec("icons.advanced.newApps", .setting, when: icons + [.iconsEngine(.native)], keys: ["newApps"],
                    search: SearchSpec("New apps’ icons", keywords: ["new app", "new icon", "install"], root: root,
                                       sheet: sheet)),
        ControlSpec("icons.advanced.otherHiders", .setting, when: icons, keys: ["otherHiders"],
                    search: SearchSpec("When another menu bar app hides icons",
                                       keywords: ["bartender", "hidden bar", "ice", "conflict", "pause"], root: root,
                                       sheet: sheet)),
        ControlSpec("icons.advanced.fullBar", .setting, when: icons, keys: ["fullBarOnExpand"],
                    search: SearchSpec("Use the full menu bar while icons are shown",
                                       keywords: ["app menus", "notch", "space", "room"], root: root, sheet: sheet)),
        ControlSpec("icons.advanced.resetArrow", .button, when: icons, keys: ["arranged"],
                    search: SearchSpec("Reset Arrow Position", keywords: ["arrow", "divider", "position", "lost"],
                                       root: root, sheet: sheet)),
        ControlSpec("icons.advanced.diagnostics", .list, when: icons,
                    search: SearchSpec("Hidden Icons diagnostics", keywords: ["engine", "layout", "fail-safe",
                                                                              "troubleshoot"],
                                       root: root, sheet: sheet)),
        ControlSpec("icons.advanced.killSwitch", .list, when: icons + [.perItem("killSwitch")]),
        ControlSpec("icons.advanced.restore", .button, when: icons,
                    keys: ["hover", "newApps", "otherHiders", "fullBarOnExpand"],
                    search: SearchSpec("Restore Hidden Icons advanced defaults", keywords: ["reset", "defaults"],
                                       root: root, sheet: sheet)),
    ]
}
