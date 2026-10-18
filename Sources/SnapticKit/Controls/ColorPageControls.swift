import Foundation

// Displays › Color (owner: C; PLAN 0.3 §4.3 sub-page table, §4.4 duplicates 8 and 9, §4.8 "Color"): the header
// switch, display tiles, the five software sliders, invert, "Adjust this display", the color profile and the Apple
// preset; its Advanced sheet (`displays.color.advanced.*`) is in the same table.

package enum ColorPageControls: ControlTable {
    package static let surface = "displays.color"
    /// `SettingsShell.openSheet` id of the Advanced sheet.
    package static let advancedSheet = "displays.color.advanced"

    private static func search(_ title: String, _ keywords: [String], sheet: String? = nil) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute(surface), sheet: sheet)
    }

    private static func advanced(_ title: String, _ keywords: [String]) -> SearchSpec {
        search(title, keywords, sheet: advancedSheet)
    }

    private static let on: [ControlCondition] = [.displayFeature(.color)]
    private static let perDisplay: [ControlCondition] = [.displayFeature(.color), .perItem("display")]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.color.enabled", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.color"],
                    search: search("Color adjustments", ["color", "gamma", "contrast", "temperature", "software"])),
        ControlSpec("displays.color.display", .setting, when: on + [.hardware(.twoDisplays)],
                    replaces: ["l.d.color.display"],
                    search: search("Display for color settings", ["choose display", "select display"])),
        ControlSpec("displays.color.adjustDisplay", .setting, when: perDisplay,
                    replaces: ["l.d.color.suspend"],
                    keys: ["perDisplay.*.color.suspended"],
                    search: search("Adjust this display", ["suspend", "pause color", "color adjustments"])),
        ControlSpec("displays.color.contrast", .setting, when: perDisplay,
                    replaces: ["l.d.color.contrast"],
                    keys: ["perDisplay.*.color.adjustments.contrast"],
                    search: search("Software contrast", ["contrast", "color"])),
        ControlSpec("displays.color.gamma", .setting, when: perDisplay,
                    replaces: ["l.d.color.gamma"],
                    keys: ["perDisplay.*.color.adjustments.gamma"],
                    search: search("Gamma", ["mid-tones", "color"])),
        ControlSpec("displays.color.temperature", .setting, when: perDisplay,
                    replaces: ["l.d.color.temperature"],
                    keys: ["perDisplay.*.color.adjustments.temperature"],
                    search: search("Temperature", ["warm", "cool", "white point", "kelvin"])),
        ControlSpec("displays.color.blackLevel", .setting, when: perDisplay,
                    replaces: ["l.d.color.blackLevel"],
                    keys: ["perDisplay.*.color.adjustments.blackLevel"],
                    search: search("Black level", ["levels", "shadows"])),
        ControlSpec("displays.color.whiteLevel", .setting, when: perDisplay,
                    replaces: ["l.d.color.whiteLevel"],
                    keys: ["perDisplay.*.color.adjustments.whiteLevel"],
                    search: search("White level", ["levels", "highlights"])),
        ControlSpec("displays.color.invert", .setting, when: perDisplay,
                    replaces: ["l.d.color.invert"],
                    keys: ["perDisplay.*.color.adjustments.inverted"],
                    search: search("Invert colors", ["negative", "invert"])),
        ControlSpec("displays.color.profile", .setting, when: [.displayFeature(.colorProfiles), .perItem("display")],
                    replaces: ["l.d.color.profile"],
                    search: search("Color profile", ["ICC", "ColorSync", "profile"])),
        ControlSpec("displays.color.applePreset", .setting,
                    when: [.displayFeature(.applePresets), .hardware(.appleDisplay), .perItem("display")],
                    replaces: ["l.d.color.applePreset"],
                    search: search("Apple display preset", ["reference mode", "preset", "Studio Display", "XDR"])),
        ControlSpec("displays.color.advancedButton", .button, when: [.module(.displays)]),

        // Advanced
        ControlSpec("displays.color.advanced.colorProfiles", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.colorProfiles"],
                    search: advanced("Color profiles", ["ICC", "ColorSync", "profile"])),
        ControlSpec("displays.color.advanced.gain", .setting, when: perDisplay,
                    replaces: ["l.d.color.gain"],
                    keys: ["perDisplay.*.color.adjustments.gain"],
                    search: advanced("Gain", ["color", "intensity"])),
        ControlSpec("displays.color.advanced.redGain", .setting, when: perDisplay,
                    replaces: ["l.d.color.rgbGain.red"],
                    keys: ["perDisplay.*.color.adjustments.red"],
                    search: advanced("Red gain", ["RGB", "color balance"])),
        ControlSpec("displays.color.advanced.greenGain", .setting, when: perDisplay,
                    replaces: ["l.d.color.rgbGain.green"],
                    keys: ["perDisplay.*.color.adjustments.green"],
                    search: advanced("Green gain", ["RGB", "color balance"])),
        ControlSpec("displays.color.advanced.blueGain", .setting, when: perDisplay,
                    replaces: ["l.d.color.rgbGain.blue"],
                    keys: ["perDisplay.*.color.adjustments.blue"],
                    search: advanced("Blue gain", ["RGB", "color balance"])),
        ControlSpec("displays.color.advanced.redGamma", .setting, when: perDisplay,
                    replaces: ["l.d.color.rgbGamma.red"],
                    keys: ["perDisplay.*.color.adjustments.redGamma"],
                    search: advanced("Red gamma", ["RGB", "color balance"])),
        ControlSpec("displays.color.advanced.greenGamma", .setting, when: perDisplay,
                    replaces: ["l.d.color.rgbGamma.green"],
                    keys: ["perDisplay.*.color.adjustments.greenGamma"],
                    search: advanced("Green gamma", ["RGB", "color balance"])),
        ControlSpec("displays.color.advanced.blueGamma", .setting, when: perDisplay,
                    replaces: ["l.d.color.rgbGamma.blue"],
                    keys: ["perDisplay.*.color.adjustments.blueGamma"],
                    search: advanced("Blue gamma", ["RGB", "color balance"])),
        ControlSpec("displays.color.advanced.profileActions", .button,
                    when: [.displayFeature(.colorProfiles), .perItem("display")],
                    replaces: ["l.d.color.profile.showInFinder", "l.d.color.profile.openColorSync",
                               "l.d.color.profile.restorePrevious"],
                    search: advanced("Color profile actions", ["Show in Finder", "ColorSync Utility", "restore previous"])),
        ControlSpec("displays.color.advanced.keepColorTable", .setting, when: [.module(.displays)],
                    replaces: ["l.d.color.allowGammaWithCustomProfile"],
                    keys: ["color.allowGammaWithCustomProfile"],
                    search: advanced("Keep color-table dimming with custom profiles", ["ICC", "black after wake"])),
        ControlSpec("displays.color.advanced.suspendAll", .setting, when: on,
                    replaces: ["l.d.color.suspendAll"],
                    keys: ["color.suspendAll"],
                    search: advanced("Pause adjustments on all displays", ["suspend", "color"])),
        ControlSpec("displays.color.advanced.shortcutStep", .setting, when: on,
                    keys: ["color.shortcutStep"],
                    search: advanced("Contrast and gamma shortcut step", ["keyboard shortcut", "step"])),
        ControlSpec("displays.color.advanced.temperatureStep", .setting, when: on,
                    keys: ["color.temperatureStep"],
                    search: advanced("Temperature shortcut step", ["keyboard shortcut", "kelvin", "step"])),
        ControlSpec("displays.color.advanced.nightShift", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.nightShift"],
                    search: advanced("Night Shift controls", ["Night Shift", "warm", "blue light"])),
        ControlSpec("displays.color.advanced.nightShiftOn", .setting,
                    when: [.parentOn(ControlID("displays.color.advanced.nightShift"))],
                    replaces: ["l.d.color.nightShift"],
                    search: advanced("Night Shift", ["blue light", "warm"])),
        ControlSpec("displays.color.advanced.nightShiftWarmth", .setting,
                    when: [.parentOn(ControlID("displays.color.advanced.nightShift"))],
                    replaces: ["l.d.color.nightShiftWarmth"],
                    search: advanced("Night Shift warmth", ["blue light", "warm", "strength"])),
        ControlSpec("displays.color.advanced.applePresets", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.applePresets"],
                    search: advanced("Apple display presets", ["reference mode", "preset"])),
        ControlSpec("displays.color.advanced.restoreDefaults", .button, when: [.module(.displays)],
                    replaces: ["l.d.color.resetDisplay"],
                    keys: ["perDisplay.*.color.adjustments.brightness"],
                    search: advanced("Restore Color Defaults", ["reset this display", "reset colors"])),
    ]
}
