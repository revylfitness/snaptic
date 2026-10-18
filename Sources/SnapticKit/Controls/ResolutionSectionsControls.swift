import Foundation

// Resolution for the selected display (owner: D; PLAN 0.3 §4.3 "Resolution (selected display)", Displays › Advanced
// group 4 "Resolution filters"). One table for `ResolutionSections`, `ResolutionOptionsSection` and
// `ResolutionFiltersSection` (step-0 rule: two files with one surface share the first file's table). Search opens
// the `displays.resolution` page for the per-display rows and the Advanced sheet for the filters.

package enum ResolutionSectionsControls: ControlTable {
    package static let surface = "displays.resolution"

    private static let root = SettingsRootID.displays
    private static let page = SettingsRoute(surface)
    private static let advanced = "displays.advanced"
    private static let display: [ControlCondition] = [.module(.displays), .displayFeature(.resolution), .perItem("display")]

    private static func onPage(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: page)
    }

    private static func inAdvanced(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, sheet: advanced)
    }

    /// The rows inside the root page's collapsed "Resolution options" disclosure (a search result opens it).
    package static let optionsAnchors: Set<String> = [
        "displays.resolution.slider", "displays.resolution.quickChanges", "displays.resolution.favorite",
        "displays.resolution.favorites",
    ]

    /// The rows inside the Advanced sheet's "Filters for <display>" disclosure.
    package static let displayFilterAnchors: Set<String> = [
        "displays.resolution.filters.dpi", "displays.resolution.filters.width", "displays.resolution.filters.refresh",
    ]

    package static func isInsideOptions(_ anchor: String) -> Bool { optionsAnchors.contains(anchor) }
    package static func isInsideDisplayFilters(_ anchor: String) -> Bool { displayFilterAnchors.contains(anchor) }

    package static let controls: [ControlSpec] = [
        // The selected display (root page rows and the displays.resolution page).
        ControlSpec("displays.resolution.mode", .setting, when: display,
                    replaces: ["l.d.resolution.mode"],
                    search: onPage("Resolution", ["mode", "scaled", "size", "larger text", "more space", "looks like"])),
        ControlSpec("displays.resolution.refresh", .setting, when: display,
                    replaces: ["l.d.resolution.refresh"],
                    search: onPage("Refresh rate", ["hertz", "Hz", "frame rate", "ProMotion"])),
        ControlSpec("displays.resolution.hdr", .setting,
                    when: [.module(.displays), .displayFeature(.hdrToggle), .hardware(.hdrDisplay), .perItem("display")],
                    replaces: ["l.d.arrangement.hdr"],
                    search: onPage("High Dynamic Range", ["HDR", "EDR"])),
        ControlSpec("displays.resolution.rotation", .setting,
                    when: [.module(.displays), .displayFeature(.rotation), .hardware(.externalDisplay), .perItem("display")],
                    replaces: ["l.d.arrangement.rotation"],
                    search: onPage("Rotation", ["rotate", "portrait", "90°"])),
        ControlSpec("displays.resolution.options", .button, when: display),
        ControlSpec("displays.resolution.slider", .setting, when: display,
                    replaces: ["l.d.overview.resolutionSlider"],
                    search: onPage("Resolution slider", ["scale", "larger text", "more space"])),
        ControlSpec("displays.resolution.quickChanges", .button, when: display,
                    replaces: ["l.d.resolution.quick.hiDPI", "l.d.resolution.quick.native", "l.d.resolution.quick.default",
                               "l.d.resolution.quick.nativeHalved", "l.d.resolution.quick.notch",
                               "l.d.resolution.undo", "l.d.resolution.redo"],
                    search: onPage("Quick Changes", ["HiDPI", "native resolution", "default resolution", "half of native",
                                                     "notch", "undo resolution change", "redo resolution change"])),
        ControlSpec("displays.resolution.favorite", .button, when: display,
                    replaces: ["l.d.resolution.addFavorite"],
                    search: onPage("Add to Favorites", ["favorite resolution", "star"])),
        ControlSpec("displays.resolution.favorites", .list, when: display,
                    replaces: ["l.d.resolution.favorite.apply", "l.d.resolution.favorite.remove"],
                    keys: ["perDisplay.*.resolution.favorites"],
                    search: onPage("Favorite resolutions", ["favorites", "apply favorite"])),
        ControlSpec("displays.resolution.allModes", .button, when: display + [.displayFeature(.hiddenModes)],
                    replaces: ["l.d.resolution.hiddenModes.display", "l.d.resolution.hiddenModes.try"],
                    search: onPage("Show All Resolutions", ["hidden modes", "hidden resolutions", "try"])),

        // Displays › Advanced › Resolution filters.
        ControlSpec("displays.resolution.filters.below720p", .setting, when: [.module(.displays)],
                    replaces: ["l.d.resolution.allowBelow720p"], keys: ["resolution.allowBelow720p"],
                    search: inAdvanced("Offer resolutions below 720p", ["small modes", "low resolution"])),
        ControlSpec("displays.resolution.filters.remember", .setting, when: [.module(.displays)],
                    replaces: ["l.d.resolution.persistedChoice"], keys: ["resolution.persistedChoice"],
                    search: inAdvanced("Remember my choice", ["persist resolution", "restore resolution"])),
        ControlSpec("displays.resolution.filters.nativeAspect", .setting, when: [.module(.displays)],
                    replaces: ["l.d.resolution.sliderNativeAspectOnly"], keys: ["resolution.sliderNativeAspectOnly"],
                    search: inAdvanced("Only the native aspect ratio on the slider", ["aspect ratio", "stretch"])),
        ControlSpec("displays.resolution.filters.valueStyle", .setting, when: [.module(.displays)],
                    replaces: ["l.d.resolution.sliderLabel"], keys: ["resolution.sliderLabel"],
                    search: inAdvanced("Show slider values as", ["percent", "size", "slider label"])),
        ControlSpec("displays.resolution.filters.snap", .setting, when: [.module(.displays)],
                    replaces: ["l.d.resolution.sliderSnapping"], keys: ["resolution.sliderSnapping"],
                    search: inAdvanced("Snap to favorites", ["slider snapping", "stops"])),
        ControlSpec("displays.resolution.filters.display", .button, when: [.module(.displays), .perItem("display")]),
        ControlSpec("displays.resolution.filters.dpi", .setting, when: [.module(.displays), .perItem("display")],
                    replaces: ["l.d.resolution.dpiFilter"], keys: ["perDisplay.*.resolution.dpiFilter"],
                    search: inAdvanced("Show HiDPI or standard sizes", ["HiDPI only", "filter resolutions"])),
        ControlSpec("displays.resolution.filters.width", .setting, when: [.module(.displays), .perItem("display")],
                    replaces: ["l.d.resolution.widthMin", "l.d.resolution.widthMax", "l.d.resolution.widthClear"],
                    keys: ["perDisplay.*.resolution.minWidth", "perDisplay.*.resolution.maxWidth"],
                    search: inAdvanced("Widths", ["width limit", "smallest", "largest", "range"])),
        ControlSpec("displays.resolution.filters.refresh", .setting, when: [.module(.displays), .perItem("display")],
                    replaces: ["l.d.resolution.refreshFilter"], keys: ["perDisplay.*.resolution.refreshFilter"],
                    search: inAdvanced("Refresh rate filter", ["hertz", "Hz", "only 60 Hz"])),
    ]
}
