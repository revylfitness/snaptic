import Foundation

// Display Details… › Menu bar overlays (owner: C; PLAN 0.3 §4.3 Display Details sheet, §4.8 "Color" and the
// `menuBarOverlays` feature): the group switch, the black strip behind the menu bar and the rounded corners of the
// selected display. F places `MenuBarOverlaysSection` in its Details sheet.

package enum MenuBarOverlaysSectionControls: ControlTable {
    package static let surface = "displays.overlays"

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, sheet: DisplayDetailsSheetControls.sheet)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.overlays.enabled", .setting, when: [.module(.displays), .perItem("display")],
                    replaces: ["l.dfeat.menuBarOverlays"],
                    search: search("Menu bar overlays", ["menu bar", "rounded corners", "notch", "black strip"])),
        ControlSpec("displays.overlays.strip", .setting,
                    when: [.parentOn(ControlID("displays.overlays.enabled")), .perItem("display")],
                    replaces: ["l.d.color.menuBarStrip"],
                    keys: ["perDisplay.*.color.menuBarStrip"],
                    search: search("Black strip behind the menu bar", ["menu bar", "notch", "background"])),
        ControlSpec("displays.overlays.topRadius", .setting,
                    when: [.parentOn(ControlID("displays.overlays.enabled")), .perItem("display")],
                    replaces: ["l.d.color.cornerRadiusTop"],
                    keys: ["perDisplay.*.color.cornerRadiusTop"],
                    search: search("Top corner radius", ["rounded corners", "corners"])),
        ControlSpec("displays.overlays.bottomRadius", .setting,
                    when: [.parentOn(ControlID("displays.overlays.enabled")), .perItem("display")],
                    replaces: ["l.d.color.cornerRadiusBottom"],
                    keys: ["perDisplay.*.color.cornerRadiusBottom"],
                    search: search("Bottom corner radius", ["rounded corners", "corners"])),
    ]
}
