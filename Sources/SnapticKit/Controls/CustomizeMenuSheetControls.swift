import Foundation

// The Customize Displays Menu sheet's controls (owner: M; PLAN 0.3 §4.3, §4.8, R5-11): the Displays group (display
// order and visibility, section order, badges, header row) and one row per 0.2 menu item with a 0.3 location. Each
// item row repeats the item's `MenuPlacementSpec` (same `legacyMenuID` and customize kind as its menu spec in
// DisplayMenuBlockControls / DisplaysMenuBuilderControls), so N16's "every opt-in item has a show/hide control" is
// checked by DisplaysMenuPlanTests.

package enum CustomizeMenuSheetControls: ControlTable {
    package static let surface = "menubar.customize"
    /// The sheet id (`SettingsShell.openSheet`, search entries).
    package static let sheetID = "menubar.customize"

    private static let root = "menuBar"
    private static let display = "display submenu"
    private static let section = "Displays section"
    private static let tools = "Display Tools"

    private static func search(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords + ["menu", "customize"], root: root, sheet: sheetID)
    }

    private static let items = ["menu.items"]

    private static func place(_ location: String, _ customize: MenuCustomize, _ legacy: String) -> MenuPlacementSpec {
        MenuPlacementSpec(location, customize: customize, legacy: DisplayMenuItemID(rawValue: legacy))
    }

    private static func item(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        search(title + " in the Displays menu", keywords)
    }

    package static let controls: [ControlSpec] = [
        // Displays group.
        ControlSpec("menubar.customize.displays", .list,
                    replaces: ["l.gen.menu.displayOrder", "l.gen.menu.mainFirst", "l.d.names.showInMenu",
                               "l.d.names.menuOrder"],
                    keys: ["menu.displayOrder", "menu.hiddenDisplays", "menu.mainFirst"]),
        ControlSpec("menubar.customize.useDefaultOrder", .button, replaces: ["l.gen.menu.useDefaultOrder"],
                    keys: ["menu.displayOrder"]),
        ControlSpec("menubar.customize.sectionOrder", .setting, replaces: ["l.gen.menu.sectionOrder"],
                    keys: ["menu.sectionOrder"], search: search("Section order", ["tools first"])),
        ControlSpec("menubar.customize.showBadges", .setting, replaces: ["l.gen.menu.showBadges"],
                    keys: ["menu.showBadges"], search: search("Status badges", ["main", "mirroring"])),
        ControlSpec("menubar.customize.headerForSingleDisplay", .setting, replaces: ["l.gen.menu.headerForSingleDisplay"],
                    keys: ["menu.headerForSingleDisplay"], search: search("Display row with one display", ["header"])),
        ControlSpec("menubar.customize.needFeatures", .button),
        ControlSpec("menubar.customize.restoreDefaults", .button, replaces: ["l.gen.menu.reset"],
                    keys: ["menu.items", "menu.sectionOrder"]),
        // Per Display.
        ControlSpec("menubar.customize.brightness", .setting, keys: items, menu: place(section, .checkbox, "c.brightness.slider"),
                    search: item("Brightness slider")),
        ControlSpec("menubar.customize.volume", .setting, keys: items, menu: place(section, .checkbox, "c.ddc.volume"),
                    search: item("Volume slider")),
        ControlSpec("menubar.customize.contrast", .setting, keys: items, menu: place(section, .checkbox, "c.ddc.contrast"),
                    search: item("Contrast slider")),
        ControlSpec("menubar.customize.customControl", .setting, keys: items, menu: place(section, .checkbox, "c.ddc.custom"),
                    search: item("Custom hardware control sliders", ["ddc"])),
        ControlSpec("menubar.customize.resolutionSlider", .setting, keys: items, menu: place(section, .checkbox, "d.resolutionSlider"),
                    search: item("Resolution slider")),
        ControlSpec("menubar.customize.resolutions", .setting, keys: items, menu: place(display, .checkbox, "d.resolutionMenu"),
                    search: item("Resolutions", ["modes"])),
        ControlSpec("menubar.customize.useAsMain", .setting, keys: items, menu: place(display, .checkbox, "d.setMain"),
                    search: item("Use as main display")),
        ControlSpec("menubar.customize.mirror", .setting, keys: items, menu: place(display, .checkbox, "d.mirrorMenu"),
                    search: item("Mirroring")),
        ControlSpec("menubar.customize.hdr", .setting, keys: items, menu: place(display, .checkbox, "d.hdrToggle"),
                    search: item("High dynamic range", ["hdr"])),
        ControlSpec("menubar.customize.extraBrightness", .setting, keys: items, menu: place(display, .checkbox, "c.xdr.toggle"),
                    search: item("Extra brightness", ["xdr"])),
        ControlSpec("menubar.customize.sharperText", .setting, keys: items, menu: place(display, .checkbox, "d.smartHiDPI"),
                    search: item("Sharper text", ["hidpi"])),
        ControlSpec("menubar.customize.adjustColors", .setting, keys: items, menu: place(display, .checkbox, "c.color.submenu"),
                    search: item("Adjust colors")),
        ControlSpec("menubar.customize.autoBrightness", .setting, keys: items, menu: place(display, .checkbox, "c.color.autoBrightness"),
                    search: item("Automatically adjust brightness")),
        ControlSpec("menubar.customize.menuBarBackground", .setting, keys: items, menu: place(display, .checkbox, "c.menuBarStrip.toggle"),
                    search: item("Black menu bar background", ["notch"])),
        ControlSpec("menubar.customize.underscan", .setting, keys: items, menu: place(display, .checkbox, "d.underscanMenu"),
                    search: item("Underscan")),
        ControlSpec("menubar.customize.pip", .setting, keys: items, menu: place(display, .checkbox, "e.pip.display"),
                    search: item("Show in Picture in Picture", ["pip"])),
        ControlSpec("menubar.customize.rotation", .setting, keys: items, menu: place(display, .checkbox, "d.rotationMenu"),
                    search: item("Rotation", ["rotate"])),
        ControlSpec("menubar.customize.colorProfile", .setting, keys: items, menu: place(display, .checkbox, "c.color.profiles"),
                    search: item("Color profile")),
        ControlSpec("menubar.customize.preset", .setting, keys: items, menu: place(display, .checkbox, "c.color.applePresets"),
                    search: item("Display preset")),
        ControlSpec("menubar.customize.input", .setting, keys: items, menu: place(display, .checkbox, "c.ddc.input"),
                    search: item("Input", ["source", "hdmi"])),
        ControlSpec("menubar.customize.mute", .setting, keys: items, menu: place(display, .checkbox, "c.ddc.mute"),
                    search: item("Mute")),
        ControlSpec("menubar.customize.power", .setting, keys: items, menu: place(display, .threeWay, "c.ddc.power"),
                    search: item("Turn display on or off", ["standby"])),
        ControlSpec("menubar.customize.disconnect", .setting, keys: items, menu: place(display, .threeWay, "d.disconnectItem"),
                    search: item("Disconnect")),
        // Displays Section.
        ControlSpec("menubar.customize.resume", .setting, keys: items, menu: place(section, .checkbox, "b.resumeAutomation"),
                    search: item("Resume display automation")),
        ControlSpec("menubar.customize.arrange", .setting, keys: items, menu: place(section, .checkbox, "d.arrange"),
                    search: item("Arrange displays")),
        ControlSpec("menubar.customize.layouts", .setting, keys: items, menu: place(section, .checkbox, "d.layoutsMenu"),
                    search: item("Saved layouts")),
        ControlSpec("menubar.customize.layoutMatch", .setting, keys: items, menu: place("Saved Layouts", .checkbox, "d.layoutMatch"),
                    search: item("Apply matching layout")),
        ControlSpec("menubar.customize.protection", .setting, keys: items, menu: place("Saved Layouts", .checkbox, "d.protection"),
                    search: item("Protect arrangement")),
        ControlSpec("menubar.customize.virtual", .setting, keys: items, menu: place(section, .checkbox, "d.virtualMenu"),
                    search: item("Virtual displays")),
        ControlSpec("menubar.customize.pipTools", .setting, keys: items, menu: place(section, .checkbox, "e.pip.tools"),
                    search: item("Picture in Picture menu", ["pip"])),
        ControlSpec("menubar.customize.actions", .setting, when: [.perItem("customAction")],
                    keys: ["automation.actions.*.showInMenu"],
                    menu: MenuPlacementSpec(section, customize: .checkbox, legacy: DisplayMenuItemID(rawValue: "a.custom.")),
                    search: search("Actions in the Displays menu", ["custom actions"])),
        // Display Tools.
        ControlSpec("menubar.customize.identify", .setting, keys: items, menu: place(tools, .checkbox, "f.tools.identify"),
                    search: item("Identify displays")),
        ControlSpec("menubar.customize.redetect", .setting, keys: items, menu: place(tools, .checkbox, "f.tools.redetect"),
                    search: item("Redetect displays")),
        ControlSpec("menubar.customize.panel", .setting, keys: items, menu: place(tools, .checkbox, "f.tools.panel"),
                    search: item("Show displays panel")),
        ControlSpec("menubar.customize.matchTextSize", .setting, keys: items, menu: place(tools, .checkbox, "d.matchUI"),
                    search: item("Match text size")),
        ControlSpec("menubar.customize.connectAll", .setting, keys: items, menu: place(tools, .checkbox, "d.connectAll"),
                    search: item("Connect all displays")),
        ControlSpec("menubar.customize.disconnectAllButMain", .setting, keys: items, menu: place(tools, .checkbox, "d.disconnectAllButMain"),
                    search: item("Disconnect all but main")),
        ControlSpec("menubar.customize.restoreAll", .setting, keys: items, menu: place(tools, .checkbox, "b.restoreAll"),
                    search: item("Restore all displays")),
        ControlSpec("menubar.customize.sync", .setting, keys: items, menu: place(tools, .checkbox, "c.sync.toggle"),
                    search: item("Sync brightness")),
        ControlSpec("menubar.customize.nightShift", .setting, keys: items, menu: place(tools, .checkbox, "c.tools.nightShift"),
                    search: item("Night Shift")),
    ]
}
