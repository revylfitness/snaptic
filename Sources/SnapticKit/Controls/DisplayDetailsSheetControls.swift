import Foundation

// Display Details… (owner F; PLAN 0.3 §4.3 "Display Details… sheet"): the selected display's identity, its manage
// actions and its information. The Connection, Menu bar overlays and Match text size groups are the owners'
// section views with their own tables.

package enum DisplayDetailsSheetControls: ControlTable {
    package static let surface = "displays.details"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "displays.details"

    private static let root = SettingsRootID.displays
    private static let perDisplay: [ControlCondition] = [.module(.displays), .perItem("display")]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.details.name", .setting, when: perDisplay,
                    replaces: ["l.d.names.name", "l.d.names.useSystemName"],
                    keys: ["perDisplay.*.identity.customName"],
                    search: SearchSpec("Display name", keywords: ["rename", "name"], root: root, sheet: sheet)),
        ControlSpec("displays.details.icon", .setting, when: perDisplay, replaces: ["l.d.names.icon"],
                    keys: ["perDisplay.*.identity.symbol"],
                    search: SearchSpec("Display icon", keywords: ["symbol", "glyph"], root: root, sheet: sheet)),
        ControlSpec("displays.details.customizeMenu", .button, when: perDisplay,
                    search: SearchSpec("Show this display in the menu", keywords: ["hide display", "menu order"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.details.connection", .navigation,
                    when: perDisplay + [.displayFeature(.disconnect)],
                    search: SearchSpec("Connection", keywords: ["disconnect", "underscan", "turn display off"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.details.matchTextSize", .navigation, when: perDisplay + [.displayFeature(.scaleMatch)],
                    search: SearchSpec("Match Text Size", keywords: ["text size", "UI scale", "same size"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.details.copySettings", .button, when: perDisplay + [.state(.disconnectedDisplay)],
                    replaces: ["l.d.names.copySettingsFrom"],
                    search: SearchSpec("Copy Settings From", keywords: ["transfer", "remembered display"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.details.forgetResolution", .button, when: perDisplay,
                    replaces: ["l.d.resolution.forgetRemembered"],
                    search: SearchSpec("Forget Remembered Resolution", keywords: ["remembered choice"], root: root,
                                       sheet: sheet)),
        ControlSpec("displays.details.forget", .button, when: perDisplay, replaces: ["l.d.names.forget"],
                    search: SearchSpec("Forget This Display", keywords: ["remove settings", "reset display"],
                                       root: root, sheet: sheet)),
        ControlSpec("displays.details.information", .list, when: perDisplay,
                    replaces: ["l.d.names.edid.copyHex", "l.d.names.edid.copyBase64"],
                    search: SearchSpec("Display information", keywords: ["EDID", "serial", "connection", "transport"],
                                       root: root, sheet: sheet)),
    ]
}
