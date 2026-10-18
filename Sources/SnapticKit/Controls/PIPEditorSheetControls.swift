import Foundation

// The Picture in Picture editor sheet (owner E; PLAN 0.3 §4.3 "Editor = sheet", §4.8 "PIP | Editor (≈ 30 controls) |
// PIP editor sheet, all fields kept"): one saved configuration (or a new one), with Name, Show as, Stream onto,
// Window, Capture, Orientation, Full screen and Filters. Every row is per configuration. Search takes you to the
// Picture in Picture page, where you choose which one to edit.

package enum PIPEditorSheetControls: ControlTable {
    package static let surface = "displays.pip.editor"

    private static let item: [ControlCondition] = [.displayFeature(.pip), .perItem("pip")]
    private static let filters: [ControlCondition] = item + [.displayFeature(.pipFilters)]

    /// The configuration field at both places a configuration is stored (window sources and display sources).
    private static func field(_ name: String) -> [String] {
        ["pip.windowConfigurations.*.\(name)", "perDisplay.*.pip.configurations.*.\(name)"]
    }

    private static func search(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: ["picture in picture", "PIP"] + keywords, root: SettingsRootID.displays,
                   route: PIPPageControls.route)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.pip.editor.source", .setting, when: item,
                    search: search("Source", ["window", "display", "capture"])),
        ControlSpec("displays.pip.editor.name", .setting, when: item,
                    replaces: ["l.d.pip.editor.name"], keys: field("name"),
                    search: search("Picture in Picture name", ["rename"])),
        ControlSpec("displays.pip.editor.showAs", .setting, when: item,
                    replaces: ["l.d.pip.editor.showAs"], keys: field("kind"),
                    search: search("Show as", ["floating window", "full-screen stream"])),
        ControlSpec("displays.pip.editor.target", .setting, when: item,
                    replaces: ["l.d.pip.editor.target"], keys: field("target"),
                    search: search("Stream onto", ["target display", "full screen"])),
        ControlSpec("displays.pip.editor.autoStart", .setting, when: item,
                    replaces: ["l.d.pip.editor.autoStart"], keys: field("autoStart"),
                    search: search("Offer to start when the display connects", ["automatically", "auto start"])),
        // Window
        ControlSpec("displays.pip.editor.level", .setting, when: item,
                    replaces: ["l.d.pip.editor.level"], keys: field("level"),
                    search: search("Window level", ["always on top", "floating", "above everything"])),
        ControlSpec("displays.pip.editor.opacity", .setting, when: item,
                    replaces: ["l.d.pip.editor.opacity"], keys: field("opacity"),
                    search: search("Opacity", ["transparency", "see-through"])),
        ControlSpec("displays.pip.editor.clickThrough", .setting, when: item,
                    replaces: ["l.d.pip.editor.clickThrough"], keys: field("clickThrough"),
                    search: search("Click through", ["ignore clicks", "pass clicks"])),
        ControlSpec("displays.pip.editor.lockPosition", .setting, when: item,
                    replaces: ["l.d.pip.editor.lockPosition"], keys: field("lockPosition"),
                    search: search("Lock position", ["pin window", "don't move"])),
        ControlSpec("displays.pip.editor.lockAspect", .setting, when: item,
                    replaces: ["l.d.pip.editor.lockAspect"], keys: field("lockAspect"),
                    search: search("Keep the aspect ratio", ["proportions"])),
        ControlSpec("displays.pip.editor.integerScaling", .setting, when: item,
                    replaces: ["l.d.pip.editor.integerScaling"], keys: field("integerScaling"),
                    search: search("Sharp pixels", ["integer scaling", "pixel art", "nearest neighbor"])),
        ControlSpec("displays.pip.editor.showTitleBar", .setting, when: item,
                    replaces: ["l.d.pip.editor.showTitleBar"], keys: field("showTitleBar"),
                    search: search("Title bar", ["window title"])),
        ControlSpec("displays.pip.editor.snapToQuarters", .setting, when: item,
                    replaces: ["l.d.pip.editor.snapToQuarters"], keys: field("snapToQuarters"),
                    search: search("Snap size to 25% steps", ["resize", "quarter"])),
        ControlSpec("displays.pip.editor.shadow", .setting, when: item,
                    replaces: ["l.d.pip.editor.shadow"], keys: field("shadow"),
                    search: search("Window shadow", ["shadow"])),
        ControlSpec("displays.pip.editor.resetPosition", .button, when: item,
                    replaces: ["l.d.pip.editor.resetPosition"], keys: field("windowFrame"),
                    search: search("Reset Window Position", ["window frame", "move back"])),
        // Capture
        ControlSpec("displays.pip.editor.matchRefresh", .setting, when: item,
                    replaces: ["l.d.pip.editor.matchRefresh"],
                    search: search("Match the display’s refresh rate", ["frame rate", "fps", "Hz"])),
        ControlSpec("displays.pip.editor.fps", .setting, when: item,
                    replaces: ["l.d.pip.editor.fps"], keys: field("fps"),
                    search: search("Frames per second", ["frame rate", "fps"])),
        ControlSpec("displays.pip.editor.showCursor", .setting, when: item,
                    replaces: ["l.d.pip.editor.showCursor"], keys: field("showCursor"),
                    search: search("Show the pointer", ["cursor", "mouse"])),
        ControlSpec("displays.pip.editor.warpOnCommandClick", .setting, when: item,
                    replaces: ["l.d.pip.editor.warpOnCommandClick"], keys: field("warpOnCommandClick"),
                    search: search("Command-click moves the pointer", ["⌘-click", "warp", "jump"])),
        ControlSpec("displays.pip.editor.crop", .button, when: item,
                    replaces: ["l.d.pip.editor.crop"], keys: field("crop"),
                    search: search("Crop", ["region", "part of the screen", "zoom"])),
        // Orientation
        ControlSpec("displays.pip.editor.rotation", .setting, when: item,
                    replaces: ["l.d.pip.editor.rotation"], keys: field("rotation"),
                    search: search("Rotation", ["rotate", "portrait", "90°"])),
        ControlSpec("displays.pip.editor.flipHorizontal", .setting, when: item,
                    replaces: ["l.d.pip.editor.flip"], keys: field("flipHorizontal"),
                    search: search("Flip horizontally", ["mirror"])),
        ControlSpec("displays.pip.editor.flipVertical", .setting, when: item,
                    replaces: ["l.d.pip.editor.flip"], keys: field("flipVertical"),
                    search: search("Flip vertically", ["teleprompter", "upside down"])),
        // Full screen
        ControlSpec("displays.pip.editor.scaling", .setting, when: item,
                    replaces: ["l.d.pip.editor.scaling"], keys: field("scaling"),
                    search: search("Scaling", ["fit", "fill", "1:1", "integer"])),
        ControlSpec("displays.pip.editor.size", .setting, when: item,
                    replaces: ["l.d.pip.editor.size"], keys: field("underscanPercent"),
                    search: search("Stream size", ["underscan", "zoom", "scale"])),
        ControlSpec("displays.pip.editor.nativeMode", .setting, when: item,
                    replaces: ["l.d.pip.editor.nativeMode"], keys: field("nativeModeWhileStreaming"),
                    search: search("Use the native resolution while streaming", ["native mode", "resolution"])),
        // Filters
        ControlSpec("displays.pip.editor.turnOnFilters", .statusAction, when: item),
        ControlSpec("displays.pip.editor.lut", .setting, when: filters,
                    replaces: ["l.d.pip.editor.lut"], keys: field("lutID"),
                    search: search("Color lookup table", ["LUT", ".cube", "color grading"])),
        ControlSpec("displays.pip.editor.filters", .list, when: filters,
                    replaces: ["l.d.pip.editor.filters"], keys: field("filters"),
                    search: search("Picture in picture filters", ["effects", "sepia", "blur", "sharpen", "invert"])),
        ControlSpec("displays.pip.editor.addFilter", .button, when: filters,
                    search: search("Add Filter", ["effect"])),
        // Footer
        ControlSpec("displays.pip.editor.delete", .button, when: item,
                    replaces: ["l.d.pip.editor.delete"],
                    search: search("Delete Picture in Picture", ["remove"])),
    ]
}
