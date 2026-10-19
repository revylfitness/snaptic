import Foundation

// Display Details › Connection (owner: D; PLAN 0.3 §4.3 Display Details, design M9). Search opens the
// `displays.connection` page (the menu's "Underscan…"), which shows the same group for the selected display.

package enum ConnectionSectionControls: ControlTable {
    package static let surface = "displays.connection"

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute(surface))
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.connection.connect", .button,
                    when: [.module(.displays), .displayFeature(.disconnect), .perItem("display")],
                    replaces: ["l.d.arrangement.connect"],
                    search: search("Disconnect", ["connect", "turn display off", "disable display"])),
        ControlSpec("displays.connection.automatic", .setting,
                    when: [.module(.displays), .hardware(.builtinDisplay)],
                    replaces: ["l.dfeat.autoDisconnectBuiltin", "l.d.arrangement.ignoreForAutoDisconnect"],
                    keys: ["features.autoDisconnectBuiltin", "perDisplay.*.management.ignoreForAutoDisconnect"],
                    search: search("Turn off automatically", ["auto-disconnect", "clamshell", "built-in display off"])),
        ControlSpec("displays.connection.withoutReading", .setting,
                    when: [.module(.displays), .displayFeature(.autoDisconnectBuiltin), .hardware(.externalDisplay),
                           .perItem("display")],
                    replaces: ["l.d.arrangement.autoDisconnectWithoutDDC"],
                    keys: ["management.autoDisconnectWithoutDDC"],
                    search: search("This display doesn’t support hardware controls", ["no DDC", "dummy plug", "power reading"])),
        ControlSpec("displays.connection.underscan", .setting,
                    when: [.module(.displays), .displayFeature(.underscan), .perItem("display")],
                    replaces: ["l.d.arrangement.underscan", "l.d.arrangement.underscanApply"],
                    search: search("Underscan", ["overscan", "TV", "edges cut off"])),
    ]
}
