import Foundation

// The Menu Bar page's controls (owner: M; PLAN 0.3 §4.3 Menu Bar, N7): one presence pop-up per module with its icon
// tiles, Awake's Time and Icon (and, 0.3.3, lid-closed mode's switch), the hidden-icon warnings, the Displays menu's
// Style and scrolling, Customize Displays Menu…, the Snaptic icon and the footer's Restore Menu Bar Defaults….

package enum MenuBarPageControls: ControlTable {
    package static let surface = "menubar.page"

    private static let root = "menuBar"

    private static func search(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords + ["menu bar", "status item"], root: root)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("menubar.page.switcherPresence", .setting, when: [.module(.windowSwitcher)],
                    replaces: ["l.gen.menu.switcher.show"], keys: ["modules.*.presence"],
                    search: search("Window Switcher in the menu bar", ["show", "icon", "hide"])),
        ControlSpec("menubar.page.switcherIcon", .setting, when: [.module(.windowSwitcher)],
                    replaces: ["l.gen.menu.switcher.icon"], keys: ["modules.*.symbol"],
                    search: search("Window Switcher icon", ["glyph", "symbol"])),
        ControlSpec("menubar.page.displaysPresence", .setting, when: [.module(.displays)],
                    replaces: ["l.gen.menu.displays.show", "l.gen.menu.displays.hideWithoutExternal"],
                    keys: ["modules.*.presence"],
                    search: search("Displays in the menu bar", ["show when active", "external display", "hide"])),
        ControlSpec("menubar.page.displaysIcon", .setting, when: [.module(.displays)],
                    replaces: ["l.gen.menu.displays.icon"], keys: ["modules.*.symbol"],
                    search: search("Displays icon", ["glyph", "symbol"])),
        ControlSpec("menubar.page.awakePresence", .setting, when: [.module(.awake)], keys: ["modules.*.presence"],
                    search: search("Awake in the menu bar", ["keep awake", "show when active", "hide"])),
        ControlSpec("menubar.page.awakeTime", .setting, when: [.module(.awake)], keys: ["indicator.style"],
                    search: search("Awake time in the menu bar", ["countdown", "time remaining", "end time"])),
        ControlSpec("menubar.page.awakeIcon", .setting, when: [.module(.awake)], keys: ["indicator.glyph"],
                    search: search("Awake icon", ["cup", "eye", "lightbulb", "glyph"])),
        // 0.3.3: lid-closed mode's opt-in, a second switch for `awake.page.lidClosed`'s setting (the precedent is an
        // action's Show in Menu, on the Automations page and in Customize Displays Menu). Shown where the Awake page's
        // switch is.
        ControlSpec("menubar.page.awakeLidClosed", .setting, when: [.module(.awake), .hardware(.battery)],
                    keys: ["features.lidClosed"],
                    search: search("Keep Awake with the Lid Closed in the Awake menu",
                                   ["lid", "clamshell", "lid-closed mode", "Awake menu"])),
        ControlSpec("menubar.page.warning", .statusAction, when: [.state(.hiddenIconWarning)],
                    replaces: ["l.gen.menu.hiddenIconWarnings"]),
        ControlSpec("menubar.page.style", .setting, when: [.module(.displays)], replaces: ["l.gen.menu.compact"],
                    keys: ["menu.compact"], search: search("Displays menu style", ["compact", "standard", "sliders"])),
        ControlSpec("menubar.page.scroll", .setting, when: [.module(.displays)],
                    replaces: ["l.gen.menu.scrollAdjustsSliders"], keys: ["menu.scrollAdjustsSliders"],
                    search: search("Scroll over a slider to adjust it", ["scroll wheel", "trackpad"])),
        ControlSpec("menubar.page.customize", .button, when: [.module(.displays)],
                    search: search("Customize Displays Menu", ["menu items", "reorder", "hide", "submenu", "display tools"])),
        ControlSpec("menubar.page.snapticIcon", .setting, replaces: ["l.gen.menu.snaptic.icon"], keys: ["sharedSymbol"],
                    search: search("Snaptic icon", ["glyph", "symbol"])),
        ControlSpec("menubar.page.restoreDefaults", .button, replaces: ["l.gen.menu.reset"],
                    keys: ["modules.*.presence", "modules.*.symbol", "sharedSymbol"],
                    search: search("Restore Menu Bar Defaults", ["reset"])),
    ]
}
