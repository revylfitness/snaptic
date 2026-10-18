import Foundation

// Display Details › Match text size (owner: D; PLAN 0.3 §4.3 Display Details, §4.8 `scaleMatch`). Search opens the
// `displays.matchTextSize` page (Display Tools › "Match Text Size…"), which shows the same group.

package enum MatchTextSizeSectionControls: ControlTable {
    package static let surface = "displays.matchTextSize"

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute(surface))
    }

    private static let base: [ControlCondition] = [.module(.displays), .hardware(.twoDisplays), .perItem("display")]
    private static let on: [ControlCondition] = base + [.displayFeature(.scaleMatch),
                                                        .parentOn(ControlID("displays.matchTextSize.enabled"))]

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.matchTextSize.enabled", .setting, when: base,
                    replaces: ["l.dfeat.scaleMatch"], keys: ["features.scaleMatch"],
                    search: search("Match text size", ["match UI size", "scale match", "same text size"])),
        ControlSpec("displays.matchTextSize.include", .setting, when: on,
                    replaces: ["l.d.resolution.matchUIScale"], keys: ["perDisplay.*.resolution.matchUIScale"],
                    search: search("Include this display", ["match text size", "match UI size"])),
        ControlSpec("displays.matchTextSize.reference", .setting, when: on,
                    replaces: ["l.d.resolution.scaleMatch.reference"], keys: ["resolution.scaleMatchReference"],
                    search: search("Reference display", ["match text size"])),
        ControlSpec("displays.matchTextSize.tolerance", .setting, when: on,
                    replaces: ["l.d.resolution.scaleMatch.tolerance"], keys: ["resolution.scaleMatchTolerance"],
                    search: search("Match tolerance", ["match text size", "tolerance"])),
        ControlSpec("displays.matchTextSize.preview", .button, when: on,
                    replaces: ["l.d.resolution.scaleMatch.preview"]),
        ControlSpec("displays.matchTextSize.apply", .button, when: on,
                    replaces: ["l.d.resolution.scaleMatch.apply"]),
    ]
}
