import Foundation

// Displays › Brightness and Dimming › Advanced (owner: C; PLAN 0.3 §4.3 sub-page table "A" column, §4.8
// "Brightness"): brightness methods for the selected display, the custom nits range, the extra-brightness defaults
// and test, and sync's "Follow outside changes". Footer: Restore Brightness Defaults….

package enum BrightnessAdvancedSheetControls: ControlTable {
    package static let surface = "displays.brightness.advanced"
    /// `SettingsShell.openSheet` id of the sheet.
    package static let sheet = "displays.brightness.advanced"

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute("displays.brightness"),
                   sheet: sheet)
    }

    private static let on: [ControlCondition] = [.displayFeature(.brightness)]
    private static let perDisplay: [ControlCondition] = [.displayFeature(.brightness), .perItem("display")]
    private static let xdr: [ControlCondition] = [.displayFeature(.xdr), .hardware(.xdrDisplay)]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.brightness.advanced.methodApple", .setting, when: on,
                    replaces: ["l.dfeat.brightnessApple"],
                    search: search("Apple native brightness", ["brightness methods", "DisplayServices", "backlight"])),
        ControlSpec("displays.brightness.advanced.methodHardware", .setting, when: on,
                    replaces: ["l.dfeat.brightnessDDC"],
                    search: search("Hardware brightness (DDC)", ["brightness methods", "DDC", "monitor", "backlight"])),
        ControlSpec("displays.brightness.advanced.methodColorTable", .setting, when: on,
                    replaces: ["l.dfeat.brightnessGamma"],
                    search: search("Color table dimming", ["brightness methods", "gamma", "software dimming"])),
        ControlSpec("displays.brightness.advanced.methodOverlay", .setting, when: on,
                    replaces: ["l.dfeat.brightnessOverlay"],
                    search: search("Overlay dimming", ["brightness methods", "software dimming", "overlay"])),
        ControlSpec("displays.brightness.advanced.use", .setting, when: perDisplay,
                    replaces: ["l.d.brightness.method", "l.d.brightness.use"],
                    keys: ["perDisplay.*.brightness.method"],
                    search: search("Brightness method for this display", ["now using", "method", "DDC", "gamma"])),
        ControlSpec("displays.brightness.advanced.customSwitchover", .setting, when: perDisplay,
                    replaces: ["l.d.brightness.switchover"],
                    search: search("Custom switchover", ["software dimming", "hardware minimum", "switchover"])),
        ControlSpec("displays.brightness.advanced.switchover", .setting,
                    when: [.parentOn(ControlID("displays.brightness.advanced.customSwitchover")), .perItem("display")],
                    replaces: ["l.d.brightness.switchoverValue"],
                    keys: ["perDisplay.*.brightness.switchover"],
                    search: search("Switchover level", ["software dimming", "switchover"])),
        ControlSpec("displays.brightness.advanced.minHardware", .setting, when: perDisplay,
                    replaces: ["l.d.brightness.minHardware"],
                    keys: ["perDisplay.*.brightness.minHardware"],
                    search: search("Minimum hardware level", ["PWM", "flicker", "backlight floor"])),
        ControlSpec("displays.brightness.advanced.colorTableCheck", .button, when: perDisplay,
                    replaces: ["l.d.brightness.gammaStatus", "l.d.brightness.gammaAskAgain"],
                    keys: ["perDisplay.*.brightness.gammaWorks"],
                    search: search("Color table dimming check", ["ask again", "gamma", "didn't get darker"])),
        ControlSpec("displays.brightness.advanced.customNits", .setting, when: perDisplay,
                    replaces: ["l.d.brightness.nits.custom"],
                    keys: ["perDisplay.*.brightness.nits.isEstimate"],
                    search: search("Custom nits range", ["nits", "luminance", "calibration"])),
        ControlSpec("displays.brightness.advanced.nitsMinimum", .setting,
                    when: [.parentOn(ControlID("displays.brightness.advanced.customNits")), .perItem("display")],
                    replaces: ["l.d.brightness.nits.min"],
                    keys: ["perDisplay.*.brightness.nits.minimum"],
                    search: search("Minimum nits", ["nits", "darkest"])),
        ControlSpec("displays.brightness.advanced.nitsMaximum", .setting,
                    when: [.parentOn(ControlID("displays.brightness.advanced.customNits")), .perItem("display")],
                    replaces: ["l.d.brightness.nits.max"],
                    keys: ["perDisplay.*.brightness.nits.maximum"],
                    search: search("Maximum nits", ["nits", "SDR", "brightest"])),
        ControlSpec("displays.brightness.advanced.nitsPeak", .setting,
                    when: [.parentOn(ControlID("displays.brightness.advanced.customNits")), .perItem("display")],
                    replaces: ["l.d.brightness.nits.peak"],
                    keys: ["perDisplay.*.brightness.nits.peak"],
                    search: search("Peak nits", ["nits", "HDR", "XDR"])),
        ControlSpec("displays.brightness.advanced.xdrMaximum", .setting, when: xdr,
                    replaces: ["l.d.brightness.xdr.globalMax"],
                    keys: ["brightness.xdrMaxScale"],
                    search: search("Default maximum extra brightness", ["XDR", "limit"])),
        ControlSpec("displays.brightness.advanced.xdrMethod", .setting, when: xdr,
                    replaces: ["l.d.brightness.xdr.method"],
                    keys: ["brightness.xdrMethod"],
                    search: search("Extra brightness method", ["XDR", "overlay", "color table"])),
        ControlSpec("displays.brightness.advanced.xdrLowPower", .setting, when: xdr,
                    replaces: ["l.d.brightness.xdr.pauseOnLowPower"],
                    keys: ["brightness.xdrPauseOnLowPower"],
                    search: search("Pause extra brightness in Low Power Mode", ["XDR", "battery", "low power"])),
        ControlSpec("displays.brightness.advanced.xdrDetent", .setting, when: xdr,
                    replaces: ["l.d.brightness.xdr.detent"],
                    keys: ["brightness.xdrDetent"],
                    search: search("Stop at 100% before extra brightness", ["XDR", "detent", "keys"])),
        ControlSpec("displays.brightness.advanced.xdrTest", .button, when: xdr + [.perItem("display")],
                    replaces: ["l.d.brightness.xdr.test"],
                    keys: ["perDisplay.*.brightness.xdrOverlayWorks", "perDisplay.*.brightness.xdrGammaWorks"],
                    search: search("Test extra brightness", ["XDR", "is it brighter", "calibrate"])),
        ControlSpec("displays.brightness.advanced.syncExternalChanges", .setting,
                    when: [.displayFeature(.sync), .hardware(.twoDisplays)],
                    replaces: ["l.d.brightness.sync.externalChanges"],
                    keys: ["brightness.syncExternalChanges"],
                    search: search("Follow brightness changes made outside Snaptic", ["sync", "monitor buttons"])),
        ControlSpec("displays.brightness.advanced.restoreDefaults", .button, when: [.module(.displays)],
                    search: search("Restore Brightness Defaults", ["reset brightness"])),
    ]
}
