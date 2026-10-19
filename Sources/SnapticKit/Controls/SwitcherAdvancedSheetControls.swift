import Foundation

/// Window Switcher › Advanced… (H; PLAN 0.3 §4.3, 19 controls): window thumbnails, behavior, mouse, keys and
/// the app lists. Footer: Restore Window Switcher Defaults….
package enum SwitcherAdvancedSheetControls: ControlTable {
    package static let surface = "switcher.advanced"
    package static let sheet = "switcher.advanced"
    private static let root = SettingsRootID.windowSwitcher

    private static func find(_ title: String, _ keywords: [String] = []) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, sheet: sheet)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("switcher.advanced.thumbnails", .setting, replaces: ["l.sw.feature.thumbnails"], keys: ["disabledFeatures"],
                    search: find("Window thumbnails", ["screen recording", "previews", "capture"])),
        ControlSpec("switcher.advanced.showOn", .setting, replaces: ["l.sw.showOnScreen"], keys: ["showOnScreen"],
                    search: find("Show on", ["display", "pointer", "screen"])),
        // The per-shortcut switch is also the windowless feature's only control (ux M3): turning it on turns it on.
        ControlSpec("switcher.advanced.includeWindowless", .setting,
                    replaces: ["l.sw.shortcut.includeWindowlessApps", "l.sw.feature.windowlessApps"],
                    keys: ["shortcuts.*.includeWindowlessApps", "disabledFeatures"],
                    search: find("Include apps with no open windows", ["windowless", "apps with no open windows", "main shortcut"])),
        ControlSpec("switcher.advanced.oneWindowPerApp", .setting, replaces: ["l.sw.shortcut.oneWindowPerApp"],
                    keys: ["shortcuts.*.oneWindowPerApp"], search: find("One entry per app", ["most recent window", "main shortcut"])),
        ControlSpec("switcher.advanced.search", .setting, replaces: ["l.sw.feature.search"], keys: ["disabledFeatures"],
                    search: find("Search", ["type to find", "filter", "find a window"])),
        ControlSpec("switcher.advanced.actions", .setting,
                    replaces: ["l.sw.feature.actionClose", "l.sw.feature.actionMinimize", "l.sw.feature.actionFullscreen",
                               "l.sw.feature.actionHide", "l.sw.feature.actionQuit"],
                    keys: ["disabledFeatures"],
                    search: find("Window actions", ["close", "minimize", "full screen", "hide", "quit"])),
        ControlSpec("switcher.advanced.hoverButtons", .setting, replaces: ["l.sw.feature.hoverButtons"],
                    keys: ["disabledFeatures"], search: find("Window buttons on hover", ["mouse", "hover"])),
        ControlSpec("switcher.advanced.selectOnHover", .setting, replaces: ["l.sw.feature.hoverSelect", "l.sw.selectOnHover"],
                    keys: ["selectOnHover", "disabledFeatures"], search: find("Select by hovering", ["mouse", "pointer"])),
        ControlSpec("switcher.advanced.commandTab", .setting, replaces: ["l.sw.feature.commandTabTakeover"],
                    keys: ["disabledFeatures"], search: find("⌘⇥ replaces the app switcher", ["command tab", "app switcher", "⌘ shortcuts"])),
        ControlSpec("switcher.advanced.passthrough", .setting, replaces: ["l.sw.feature.passthrough"],
                    keys: ["disabledFeatures"],
                    search: find("Pass shortcuts through to apps", ["virtual machine", "remote desktop", "passthrough"])),
        ControlSpec("switcher.advanced.passthroughFullScreen", .setting,
                    when: [.parentOn(ControlID("switcher.advanced.passthrough"))],
                    replaces: ["l.sw.passthroughOnlyWhenFullscreen"], keys: ["passthroughOnlyWhenFullscreen"],
                    search: find("Only while full screen")),
        ControlSpec("switcher.advanced.passthroughApps", .list, when: [.parentOn(ControlID("switcher.advanced.passthrough"))],
                    replaces: ["l.sw.passthroughBundleIDs"], keys: ["passthroughBundleIDs"],
                    search: find("Apps that keep the shortcut", ["passthrough", "virtual machine", "remote desktop"])),
        ControlSpec("switcher.advanced.excludedApps", .list, replaces: ["l.sw.excludedBundleIDs"], keys: ["excludedBundleIDs"],
                    search: find("Apps hidden from the switcher", ["exclude", "hide apps"])),
        ControlSpec("switcher.advanced.protectPrivate", .setting, replaces: ["l.sw.protectPrivateWindows"],
                    keys: ["protectPrivateWindows"],
                    search: find("Protect private windows", ["privacy", "password managers", "never show thumbnails"])),
        ControlSpec("switcher.advanced.privateApps", .list, when: [.parentOn(ControlID("switcher.advanced.protectPrivate"))],
                    replaces: ["l.sw.privateBundleIDs"], keys: ["privateBundleIDs"],
                    search: find("Never show thumbnails for", ["private apps", "password managers", "privacy"])),
        ControlSpec("switcher.advanced.restoreDefaults", .button,
                    search: find("Restore Window Switcher Defaults", ["reset", "defaults"])),
    ]
}
