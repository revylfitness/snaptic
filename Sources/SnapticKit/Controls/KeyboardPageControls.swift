import Foundation

// Displays › Keyboard (owner: C; PLAN 0.3 §4.3 sub-page table, §4.4 duplicates 5, 12 and 14, §4.8 "Keys" and
// "OSD"): brightness and volume keys, the brightness and volume indicator, and Keyboard Shortcuts…; its Keyboard
// Shortcuts sheet (`displays.keyboard.shortcuts.*`, one grouped list of every Displays action) and its Advanced
// sheet (`displays.keyboard.advanced.*`) are in the same table.

package enum KeyboardPageControls: ControlTable {
    package static let surface = "displays.keyboard"
    /// `SettingsShell.openSheet` ids of the two sheets.
    package static let advancedSheet = "displays.keyboard.advanced"
    package static let shortcutsSheet = "displays.keyboard.shortcuts"

    private static func search(_ title: String, _ keywords: [String], sheet: String? = nil) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute(surface), sheet: sheet)
    }

    private static func advanced(_ title: String, _ keywords: [String]) -> SearchSpec {
        search(title, keywords, sheet: advancedSheet)
    }

    private static let brightnessKeys: [ControlCondition] = [.displayFeature(.brightnessKeys)]
    private static let volumeKeys: [ControlCondition] = [.displayFeature(.volumeKeys)]
    private static let indicator: [ControlCondition] = [.displayFeature(.osd)]

    /// Every frozen 0.2 Displays action: each one's shortcut is a row of the Keyboard Shortcuts sheet. Restore All
    /// Displays' shortcut has its home in Displays › Advanced › Confirm display changes (B); the sheet mirrors it.
    private static let actions: [String] = [
        "l.action.c.brightnessUp", "l.action.c.brightnessDown", "l.action.c.brightnessUpFine",
        "l.action.c.brightnessDownFine", "l.action.c.volumeUp", "l.action.c.volumeDown", "l.action.c.volumeUpFine",
        "l.action.c.volumeDownFine", "l.action.c.mute", "l.action.c.contrastUp", "l.action.c.contrastDown",
        "l.action.c.contrastUpFine", "l.action.c.contrastDownFine", "l.action.c.gammaUp", "l.action.c.gammaDown",
        "l.action.c.gammaUpFine", "l.action.c.gammaDownFine", "l.action.c.temperatureUp",
        "l.action.c.temperatureDown", "l.action.c.temperatureUpFine", "l.action.c.temperatureDownFine",
        "l.action.c.invert", "l.action.c.colorReset", "l.action.c.colorSuspend", "l.action.c.menuBarStrip",
        "l.action.c.nightShiftToggle", "l.action.c.nightShiftUp", "l.action.c.nightShiftDown",
        "l.action.c.syncToggle", "l.action.c.xdrToggle", "l.action.c.xdrUp", "l.action.c.xdrDown",
        "l.action.c.ddcPowerOn", "l.action.c.ddcStandby", "l.action.c.inputSlot*", "l.action.d.resolutionUp",
        "l.action.d.resolutionDown", "l.action.d.hiDPIToggle", "l.action.d.nativeMode", "l.action.d.defaultMode",
        "l.action.d.nativeHalved", "l.action.d.resolutionUndo", "l.action.d.resolutionRedo", "l.action.d.notchToggle",
        "l.action.d.matchUI", "l.action.d.rotate", "l.action.d.hdrToggle", "l.action.d.setMain",
        "l.action.d.mirrorToggle", "l.action.d.toggleBuiltin", "l.action.d.connectAll", "l.action.d.disconnect",
        "l.action.d.disconnectAllButMain", "l.action.d.protectionToggle", "l.action.d.smartHiDPIToggle",
        "l.action.d.favorite*", "l.action.d.layout*", "l.action.d.virtualToggle*", "l.action.e.pipToggle.*",
        "l.action.e.pipToggleDisplay", "l.action.e.pipPickWindow", "l.action.e.pipPauseAll", "l.action.e.pipHideAll",
        "l.action.e.pipStopAll", "l.action.f.showPanel", "l.action.f.identify", "l.action.f.redetect",
        "l.action.f.copyDiagnostics", "l.action.b.resumeAutomation", "l.action.a.custom.*",
    ]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.keyboard.permission", .statusAction,
                    when: [.state(.accessibilityMissing)],
                    replaces: ["l.d.keys.permission.pane", "l.d.keys.permission.status", "l.d.keys.permission.grant",
                               "l.d.keys.permission.retry"]),
        ControlSpec("displays.keyboard.brightnessKeys", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.brightnessKeys"],
                    search: search("Brightness keys", ["F1", "F2", "media keys", "external display brightness"])),
        ControlSpec("displays.keyboard.brightnessTarget", .setting,
                    when: [.parentOn(ControlID("displays.keyboard.brightnessKeys"))],
                    replaces: ["l.d.keys.target"],
                    keys: ["keys.target"],
                    search: search("Brightness keys change", ["pointer", "all displays", "target"])),
        ControlSpec("displays.keyboard.volumeKeys", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.volumeKeys"],
                    search: search("Volume keys", ["F10", "F11", "F12", "speakers", "media keys"])),
        ControlSpec("displays.keyboard.volumeTarget", .setting,
                    when: [.parentOn(ControlID("displays.keyboard.volumeKeys"))],
                    replaces: ["l.d.keys.volumePolicy"],
                    keys: ["keys.volumePolicy"],
                    search: search("Volume keys change the display", ["sound output", "speakers", "target"])),
        ControlSpec("displays.keyboard.indicatorStyle", .setting, when: indicator,
                    replaces: ["l.d.osd.style", "l.d.osd.native"],
                    keys: ["keys.osdStyle", "keys.osdNative"],
                    search: search("Brightness and volume indicator", ["OSD", "HUD", "on-screen display", "style"])),
        ControlSpec("displays.keyboard.indicatorPosition", .setting, when: indicator,
                    replaces: ["l.d.osd.position"],
                    keys: ["keys.osdPosition"],
                    search: search("Indicator position", ["OSD", "HUD", "on-screen display"])),
        ControlSpec("displays.keyboard.shortcutsButton", .button, when: [.module(.displays)],
                    search: search("Keyboard Shortcuts", ["shortcut", "hotkey", "key combination"])),
        ControlSpec("displays.keyboard.advancedButton", .button, when: [.module(.displays)]),

        // Keyboard Shortcuts sheet
        ControlSpec("displays.keyboard.shortcuts.list", .list, when: [.displayFeature(.shortcuts)],
                    replaces: actions + ["l.d.keys.shortcutFilter", "l.d.overview.showPanelShortcut",
                                         "l.d.overview.identifyShortcut"],
                    keys: ["keys.shortcuts.*.keyCode", "keys.shortcuts.*.carbonModifiers"],
                    search: search("Displays keyboard shortcuts", ["hotkey", "brightness up", "resolution", "panel",
                                                                   "identify", "input slot", "custom action"],
                                   sheet: shortcutsSheet)),
        ControlSpec("displays.keyboard.shortcuts.action", .shortcut, when: [.displayFeature(.shortcuts), .perItem("action")]),
        ControlSpec("displays.keyboard.shortcuts.restoreAll", .shortcut, when: [.module(.displays)]),
        ControlSpec("displays.keyboard.shortcuts.useDefaultRestoreAll", .button, when: [.module(.displays)]),

        // Advanced
        ControlSpec("displays.keyboard.advanced.brightnessPolicy", .setting, when: brightnessKeys,
                    replaces: ["l.d.keys.brightnessPolicy"],
                    keys: ["keys.brightnessPolicy"],
                    search: advanced("Use the brightness keys for", ["displays macOS can't control", "always"])),
        ControlSpec("displays.keyboard.advanced.brightnessAlsoSystem", .setting, when: brightnessKeys,
                    replaces: ["l.d.keys.brightnessAlsoSystem"],
                    keys: ["keys.brightnessAlsoSystem"],
                    search: advanced("Also let macOS handle the brightness keys", ["system", "built-in"])),
        ControlSpec("displays.keyboard.advanced.steps", .setting, when: brightnessKeys,
                    replaces: ["l.d.keys.steps"],
                    keys: ["keys.steps"],
                    search: advanced("Steps", ["key steps", "increments"])),
        ControlSpec("displays.keyboard.advanced.fineSteps", .setting, when: brightnessKeys,
                    replaces: ["l.d.keys.fineSteps"],
                    keys: ["keys.fineSteps"],
                    search: advanced("Fine steps", ["option shift", "small steps"])),
        ControlSpec("displays.keyboard.advanced.alternateKeys", .setting, when: brightnessKeys,
                    replaces: ["l.d.keys.alternateKeys"],
                    keys: ["keys.alternateKeys"],
                    search: advanced("F14 and F15 change brightness", ["F14", "F15", "extended keyboard"])),
        ControlSpec("displays.keyboard.advanced.modifiers", .button, when: brightnessKeys,
                    replaces: ["l.d.keys.modifiers"],
                    search: advanced("Modifier keys", ["shift", "option", "control", "command", "fine steps"])),
        ControlSpec("displays.keyboard.advanced.volumeAlsoSystem", .setting, when: volumeKeys,
                    replaces: ["l.d.keys.volumeAlsoSystem"],
                    keys: ["keys.volumeAlsoSystem"],
                    search: advanced("Also let macOS handle the volume keys", ["system"])),
        ControlSpec("displays.keyboard.advanced.muteAlsoSystem", .setting, when: volumeKeys,
                    replaces: ["l.d.keys.muteAlsoSystem"],
                    keys: ["keys.muteAlsoSystem"],
                    search: advanced("Also let macOS handle the mute key", ["system", "mute"])),
        ControlSpec("displays.keyboard.advanced.keysChangeDisplay", .setting, when: [.perItem("display")],
                    replaces: ["l.d.keys.perDisplay.keysEnabled"],
                    keys: ["perDisplay.*.keys.keysEnabled"],
                    search: advanced("Keys change this display", ["exclude display", "per display"])),
        ControlSpec("displays.keyboard.advanced.showVolumeIndicator", .setting, when: volumeKeys + [.perItem("display")],
                    replaces: ["l.d.keys.perDisplay.showVolumeOSD"],
                    keys: ["perDisplay.*.keys.showVolumeOSD"],
                    search: advanced("Show the volume indicator", ["OSD", "per display"])),
        ControlSpec("displays.keyboard.advanced.soundOutputName", .setting, when: volumeKeys + [.perItem("display")],
                    replaces: ["l.d.keys.perDisplay.audioDeviceName"],
                    keys: ["perDisplay.*.keys.audioDeviceName"],
                    search: advanced("Sound output name", ["audio device", "speakers"])),
        ControlSpec("displays.keyboard.advanced.inputSlots", .list, when: [.displayFeature(.ddcInput)],
                    replaces: ["l.d.keys.inputSlots"],
                    keys: ["keys.inputSlots.*.display", "keys.inputSlots.*.value", "keys.inputSlots.*.lgAlt"],
                    search: advanced("Input slots", ["input shortcut", "switch input", "HDMI"])),
        ControlSpec("displays.keyboard.advanced.indicatorTarget", .setting, when: indicator,
                    replaces: ["l.d.osd.target"],
                    keys: ["keys.osdTarget"],
                    search: advanced("Show the indicator on", ["OSD", "which display"])),
        ControlSpec("displays.keyboard.advanced.indicatorValue", .setting, when: indicator,
                    replaces: ["l.d.osd.showValue"],
                    keys: ["keys.osdShowValue"],
                    search: advanced("Show the value in the indicator", ["OSD", "percent"])),
        ControlSpec("displays.keyboard.advanced.previewIndicator", .button, when: indicator,
                    replaces: ["l.d.osd.preview"],
                    search: advanced("Preview Indicator", ["OSD", "test"])),
        ControlSpec("displays.keyboard.advanced.restoreDefaults", .button, when: [.module(.displays)],
                    search: advanced("Restore Keyboard Defaults", ["reset keys"])),
    ]
}
