import Foundation

// Displays › Brightness and Dimming (owner: C; PLAN 0.3 §4.3 sub-page table, §4.4 duplicate 3, §4.8 "Brightness"):
// the per-display picker, restore and smooth transitions, sync, extra brightness, dimming and nits.
// `BrightnessSubpage` and its `BrightnessSections` share this table.

package enum BrightnessSubpageControls: ControlTable {
    package static let surface = "displays.brightness"

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute(surface))
    }

    private static let on: [ControlCondition] = [.displayFeature(.brightness)]
    private static let perDisplay: [ControlCondition] = [.displayFeature(.brightness), .perItem("display")]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.brightness.display", .setting, when: on + [.hardware(.twoDisplays)],
                    replaces: ["l.d.brightness.display"],
                    search: search("Display for brightness settings", ["choose display", "select display"])),
        ControlSpec("displays.brightness.restore", .setting, when: on,
                    replaces: ["l.dfeat.brightnessRestore", "l.d.brightness.restoreMode"],
                    keys: ["brightness.restoreMode"],
                    search: search("Restore brightness at login and wake", ["restore", "wake", "login", "reconnect"])),
        ControlSpec("displays.brightness.smoothTransitions", .setting, when: on,
                    replaces: ["l.d.brightness.smoothTransitions"],
                    keys: ["brightness.smoothTransitions"],
                    search: search("Smooth transitions", ["fade", "animation", "brightness change"])),
        ControlSpec("displays.brightness.sync", .setting, when: on + [.hardware(.twoDisplays)],
                    replaces: ["l.dfeat.sync", "l.d.brightness.sync.enabled"],
                    keys: ["brightness.syncPaused"],
                    search: search("Sync brightness", ["follow", "match brightness", "all displays", "together"])),
        ControlSpec("displays.brightness.syncResume", .statusAction,
                    when: [.parentOn(ControlID("displays.brightness.sync"))]),
        ControlSpec("displays.brightness.syncSource", .setting,
                    when: [.parentOn(ControlID("displays.brightness.sync"))],
                    replaces: ["l.d.brightness.sync.source"],
                    keys: ["brightness.syncSource"],
                    search: search("Sync source", ["sync brightness", "follow display"])),
        ControlSpec("displays.brightness.syncMode", .setting,
                    when: [.parentOn(ControlID("displays.brightness.sync"))],
                    replaces: ["l.d.brightness.sync.mode"],
                    keys: ["brightness.syncMode"],
                    search: search("Follow the same level or the same change", ["sync brightness", "sync mode"])),
        ControlSpec("displays.brightness.syncFollow", .setting,
                    when: [.parentOn(ControlID("displays.brightness.sync")), .perItem("display")],
                    replaces: ["l.d.brightness.sync.follow"],
                    keys: ["perDisplay.*.brightness.syncEnabled"],
                    search: search("Follow the sync source", ["sync brightness", "this display"])),
        ControlSpec("displays.brightness.syncOffset", .setting,
                    when: [.parentOn(ControlID("displays.brightness.sync")), .perItem("display")],
                    replaces: ["l.d.brightness.sync.offset"],
                    keys: ["perDisplay.*.brightness.syncOffset"],
                    search: search("Sync offset", ["sync brightness", "brighter", "darker"])),
        ControlSpec("displays.brightness.xdr", .setting, when: on + [.hardware(.xdrDisplay)],
                    replaces: ["l.dfeat.xdr"],
                    search: search("Extra brightness", ["XDR", "HDR", "brighter than 100%", "nits", "boost"])),
        ControlSpec("displays.brightness.xdrDisplay", .setting,
                    when: [.parentOn(ControlID("displays.brightness.xdr")), .perItem("display")],
                    replaces: ["l.d.brightness.xdr.enabled"],
                    keys: ["perDisplay.*.brightness.xdrEnabled"],
                    search: search("Use extra brightness on this display", ["XDR", "boost"])),
        ControlSpec("displays.brightness.xdrMaximum", .setting,
                    when: [.parentOn(ControlID("displays.brightness.xdr")), .perItem("display")],
                    replaces: ["l.d.brightness.xdr.customMax", "l.d.brightness.xdr.max"],
                    keys: ["perDisplay.*.brightness.xdrMax"],
                    search: search("Maximum extra brightness", ["XDR", "limit", "nits"])),
        ControlSpec("displays.brightness.xdrBatteryFloor", .setting,
                    when: [.parentOn(ControlID("displays.brightness.xdr")), .hardware(.battery)],
                    replaces: ["l.d.brightness.xdr.batteryFloor"],
                    keys: ["brightness.xdrBatteryFloor"],
                    search: search("Pause extra brightness below battery", ["XDR", "battery", "power"])),
        ControlSpec("displays.brightness.dimOnLock", .setting, when: on,
                    replaces: ["l.dfeat.dimOnLock"],
                    search: search("Dim when the screen locks", ["lock", "dim", "darken", "screen lock"])),
        ControlSpec("displays.brightness.dimOnLockLevel", .setting,
                    when: [.parentOn(ControlID("displays.brightness.dimOnLock"))],
                    replaces: ["l.d.brightness.dimOnLockLevel"],
                    keys: ["brightness.dimOnLockLevel"],
                    search: search("Dim level when locked", ["lock", "dim"])),
        ControlSpec("displays.brightness.dimToBlack", .setting, when: on,
                    replaces: ["l.dfeat.dimToBlack", "l.d.brightness.dimToBlack"],
                    search: search("Dim all the way to black", ["black", "darker", "minimum brightness", "dim"])),
        ControlSpec("displays.brightness.showNits", .setting, when: on,
                    replaces: ["l.dfeat.nits", "l.d.brightness.showNits", "l.d.osd.showNits"],
                    keys: ["brightness.showNits", "keys.osdShowNits"],
                    search: search("Show brightness in nits", ["nits", "luminance", "candela", "brightness indicator"])),
        ControlSpec("displays.brightness.advancedButton", .button, when: [.module(.displays)],
                    search: search("Brightness Advanced Settings", ["brightness methods", "nits range", "XDR"])),
    ]
}
