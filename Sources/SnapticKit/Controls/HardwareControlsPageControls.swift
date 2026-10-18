import Foundation

// Displays › Hardware Controls (owner: C; PLAN 0.3 §4.3 sub-page table, §4.4 duplicate 8, §4.8 "DDC"): the header
// switch, external display tiles, "Use hardware controls for this display", Volume and Mute, Hardware contrast,
// Input, Turn Off / Turn On and custom control sliders; its Advanced sheet (`displays.hardware.advanced.*`) is in
// the same table.

package enum HardwareControlsPageControls: ControlTable {
    package static let surface = "displays.hardware"
    /// `SettingsShell.openSheet` id of the Advanced sheet.
    package static let advancedSheet = "displays.hardware.advanced"

    private static func search(_ title: String, _ keywords: [String], sheet: String? = nil) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute(surface), sheet: sheet)
    }

    private static func advanced(_ title: String, _ keywords: [String]) -> SearchSpec {
        search(title, keywords, sheet: advancedSheet)
    }

    private static let on: [ControlCondition] = [.displayFeature(.ddcControls)]
    private static let perDisplay: [ControlCondition] = [.displayFeature(.ddcControls), .hardware(.ddcDisplay),
                                                         .perItem("display")]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.hardware.enabled", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.ddcControls"],
                    search: search("Hardware controls", ["DDC", "monitor", "volume", "input", "power"])),
        ControlSpec("displays.hardware.display", .setting, when: on + [.hardware(.externalDisplay)],
                    replaces: ["l.d.ddc.display"],
                    search: search("Display for hardware controls", ["choose display", "external display"])),
        ControlSpec("displays.hardware.useDisplay", .setting, when: on + [.hardware(.externalDisplay), .perItem("display")],
                    replaces: ["l.d.ddc.enabled"],
                    keys: ["perDisplay.*.ddc.enabled"],
                    search: search("Use hardware controls for this display", ["DDC", "monitor"])),
        ControlSpec("displays.hardware.volume", .setting, when: on + [.hardware(.ddcVolume), .perItem("display")],
                    replaces: ["l.d.overview.volume", "l.d.ddc.volume"],
                    search: search("Volume", ["speakers", "sound", "DDC"])),
        ControlSpec("displays.hardware.mute", .setting, when: on + [.hardware(.ddcVolume), .perItem("display")],
                    replaces: ["l.d.overview.mute"],
                    search: search("Mute", ["speakers", "sound"])),
        ControlSpec("displays.hardware.contrast", .setting, when: perDisplay,
                    replaces: ["l.d.ddc.contrast"],
                    search: search("Hardware contrast", ["contrast", "DDC", "monitor"])),
        ControlSpec("displays.hardware.input", .setting, when: perDisplay + [.displayFeature(.ddcInput)],
                    replaces: ["l.d.overview.input", "l.d.ddc.input.switch"],
                    search: search("Input", ["HDMI", "DisplayPort", "USB-C", "source", "switch input"])),
        ControlSpec("displays.hardware.power", .button, when: perDisplay + [.displayFeature(.ddcPower)],
                    replaces: ["l.d.overview.ddcPower", "l.d.ddc.power.state", "l.d.ddc.power.on", "l.d.ddc.power.standby"],
                    search: search("Turn display off or on", ["standby", "power", "sleep display"])),
        ControlSpec("displays.hardware.customControl", .setting,
                    when: perDisplay + [.displayFeature(.ddcCustom), .perItem("customControl")],
                    search: search("Custom hardware controls", ["VCP", "custom slider", "DDC"])),
        ControlSpec("displays.hardware.advancedButton", .button, when: [.module(.displays)],
                    search: search("Hardware Controls Advanced Settings", ["DDC", "timing", "raw", "tuning"])),

        // Advanced
        ControlSpec("displays.hardware.advanced.inputSwitching", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.ddcInput"],
                    search: advanced("Input switching", ["HDMI", "DisplayPort", "source"])),
        ControlSpec("displays.hardware.advanced.powerControl", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.ddcPower"],
                    search: advanced("Power control", ["standby", "turn off display"])),
        ControlSpec("displays.hardware.advanced.customControls", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.ddcCustom"],
                    search: advanced("Custom controls", ["VCP", "raw", "manufacturer"])),
        ControlSpec("displays.hardware.advanced.readback", .setting, when: on,
                    replaces: ["l.d.ddc.readback"],
                    keys: ["ddc.readback"],
                    search: advanced("Read values back", ["readback", "monitor buttons", "poll"])),
        ControlSpec("displays.hardware.advanced.readbackInterval", .setting,
                    when: [.parentOn(ControlID("displays.hardware.advanced.readback"))],
                    replaces: ["l.d.ddc.readbackInterval"],
                    keys: ["ddc.defaultReadbackInterval"],
                    search: advanced("Read back every", ["readback", "interval", "seconds"])),
        ControlSpec("displays.hardware.advanced.restoreOnWake", .setting, when: on,
                    replaces: ["l.d.ddc.restoreOnWake"],
                    keys: ["ddc.restoreOnWake"],
                    search: advanced("Send values again after wake", ["wake", "restore", "re-send"])),
        ControlSpec("displays.hardware.advanced.tuning", .list, when: perDisplay + [.perItem("vcp")],
                    replaces: ["l.d.ddc.vcp.use", "l.d.ddc.vcp.min", "l.d.ddc.vcp.max", "l.d.ddc.vcp.invert",
                               "l.d.ddc.vcp.showInMenu", "l.d.ddc.vcp.readbackInterval"],
                    keys: ["perDisplay.*.ddc.controls.*.enabled", "perDisplay.*.ddc.controls.*.minimum",
                           "perDisplay.*.ddc.controls.*.maximum", "perDisplay.*.ddc.controls.*.inverted",
                           "perDisplay.*.ddc.controls.*.readbackInterval", "perDisplay.*.ddc.controls.*.showInMenu"],
                    search: advanced("Control tuning", ["raw range", "invert", "show in menu", "VCP"])),
        ControlSpec("displays.hardware.advanced.inputs", .list, when: perDisplay + [.displayFeature(.ddcInput)],
                    replaces: ["l.d.ddc.input.name", "l.d.ddc.input.hide", "l.d.ddc.input.order", "l.d.ddc.input.add",
                               "l.d.ddc.input.resetList"],
                    keys: ["perDisplay.*.ddc.inputs.*.value", "perDisplay.*.ddc.inputs.*.name",
                           "perDisplay.*.ddc.inputs.*.hidden", "perDisplay.*.ddc.inputs.*.lgAlt"],
                    search: advanced("Input list", ["rename input", "hide input", "LG", "order"])),
        ControlSpec("displays.hardware.advanced.standbyValue", .setting, when: perDisplay + [.displayFeature(.ddcPower)],
                    replaces: ["l.d.ddc.power.standbyValue"],
                    keys: ["perDisplay.*.ddc.standbyValue"],
                    search: advanced("Turn Off sends", ["standby", "suspend", "power"])),
        ControlSpec("displays.hardware.advanced.customList", .list, when: perDisplay + [.displayFeature(.ddcCustom)],
                    replaces: ["l.d.ddc.custom.list", "l.d.ddc.custom.add"],
                    keys: ["perDisplay.*.ddc.customControls.*.id", "perDisplay.*.ddc.customControls.*.name",
                           "perDisplay.*.ddc.customControls.*.code", "perDisplay.*.ddc.customControls.*.kind",
                           "perDisplay.*.ddc.customControls.*.value", "perDisplay.*.ddc.customControls.*.showInMenu"],
                    search: advanced("Custom control list", ["VCP", "add control"])),
        ControlSpec("displays.hardware.advanced.raw", .button, when: perDisplay + [.displayFeature(.ddcCustom)],
                    replaces: ["l.d.ddc.raw.code", "l.d.ddc.raw.value", "l.d.ddc.raw.read", "l.d.ddc.raw.send",
                               "l.d.ddc.raw.unlockCode", "l.d.ddc.raw.unlock", "l.d.ddc.raw.lockAll"],
                    keys: ["perDisplay.*.ddc.unlockedCodes"],
                    search: advanced("Raw commands", ["VCP", "unlock", "manufacturer code", "send", "read"])),
        ControlSpec("displays.hardware.advanced.replyDelay", .setting, when: perDisplay,
                    replaces: ["l.d.ddc.timing.replyDelay"],
                    keys: ["perDisplay.*.ddc.replyDelayMs"],
                    search: advanced("Reply delay", ["timing", "milliseconds", "flaky"])),
        ControlSpec("displays.hardware.advanced.retries", .setting, when: perDisplay,
                    replaces: ["l.d.ddc.timing.retries"],
                    keys: ["perDisplay.*.ddc.retries"],
                    search: advanced("Retries", ["timing", "flaky"])),
        ControlSpec("displays.hardware.advanced.writeTwice", .setting, when: perDisplay,
                    replaces: ["l.d.ddc.timing.writeTwice"],
                    keys: ["perDisplay.*.ddc.writeCount"],
                    search: advanced("Send every change twice", ["timing", "flaky"])),
        ControlSpec("displays.hardware.advanced.ignoreChecksum", .setting, when: perDisplay,
                    replaces: ["l.d.ddc.timing.ignoreChecksum"],
                    keys: ["perDisplay.*.ddc.ignoreChecksum"],
                    search: advanced("Ignore reply checksums", ["timing", "flaky"])),
        ControlSpec("displays.hardware.advanced.forgetFraming", .button, when: perDisplay,
                    replaces: ["l.d.ddc.timing.forgetFraming"],
                    keys: ["perDisplay.*.ddc.framing"],
                    search: advanced("Forget learned framing", ["timing", "framing"])),
        ControlSpec("displays.hardware.advanced.information", .button, when: perDisplay,
                    replaces: ["l.d.ddc.info", "l.d.ddc.readCapabilities", "l.d.ddc.checkConnection"],
                    search: advanced("Hardware information", ["capabilities", "MCCS", "model", "connection", "status"])),
        ControlSpec("displays.hardware.advanced.restoreDefaults", .button, when: [.module(.displays)],
                    search: advanced("Restore Hardware Controls Defaults", ["reset DDC"])),
    ]
}
