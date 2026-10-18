import Foundation

/// Window Switcher (H; PLAN 0.3 §4.3): header switch, permission status rows, the primary shortcut and its options,
/// More Shortcuts…, and the Windows section. Footer: Advanced… (?).
package enum SwitcherPageControls: ControlTable {
    package static let surface = "switcher.page"
    private static let root = SettingsRootID.windowSwitcher
    package static let controls: [ControlSpec] = [
        ControlSpec("switcher.page.header", .setting, replaces: ["l.gen.modules.switcher"], keys: ["modules.*.enabled"],
                    search: SearchSpec("Use Window Switcher", keywords: ["alt-tab", "turn on", "turn off", "module"], root: root)),
        ControlSpec("switcher.page.accessibility", .statusAction, when: [.state(.accessibilityMissing)]),
        ControlSpec("switcher.page.screenRecording", .statusAction,
                    when: [.state(.screenRecordingMissing), .switcherFeature(.thumbnails)]),
        ControlSpec("switcher.page.shortcut", .setting, replaces: ["l.sw.shortcut.modifier", "l.sw.shortcut.keyCode"],
                    keys: ["shortcuts.*.modifier", "shortcuts.*.keyCode"],
                    search: SearchSpec("Shortcut", keywords: ["keyboard shortcut", "hotkey", "option tab", "keys"], root: root)),
        ControlSpec("switcher.page.moreShortcuts", .button,
                    search: SearchSpec("More Shortcuts", keywords: ["add shortcut", "second shortcut", "gather"], root: root)),
        ControlSpec("switcher.page.releaseToSwitch", .setting, replaces: ["l.sw.releaseToSwitch"], keys: ["releaseToSwitch"],
                    search: SearchSpec("Switch when you release the keys", keywords: ["release", "modifier", "sticky"],
                                       root: root)),
        ControlSpec("switcher.page.scope", .setting, replaces: ["l.sw.shortcut.scope"], keys: ["shortcuts.*.scope"],
                    search: SearchSpec("Show", keywords: ["all windows", "active app", "this display"], root: root)),
        ControlSpec("switcher.page.style", .setting, replaces: ["l.sw.shortcut.style"], keys: ["shortcuts.*.style"],
                    search: SearchSpec("Style", keywords: ["thumbnails", "icons", "list", "appearance"], root: root)),
        ControlSpec("switcher.page.preview", .setting, when: [.switcherFeature(.thumbnails)],
                    replaces: ["l.sw.previewSelected", "l.sw.feature.preview"], keys: ["previewSelected"],
                    search: SearchSpec("Preview the selected window", keywords: ["full size", "preview"], root: root)),
        ControlSpec("switcher.page.autoSize", .setting, when: [.switcherFeature(.thumbnails)], replaces: ["l.sw.autoSize"],
                    keys: ["autoSize"],
                    search: SearchSpec("Size thumbnails automatically", keywords: ["auto size", "fit"], root: root)),
        ControlSpec("switcher.page.thumbnailSize", .setting,
                    when: [.switcherFeature(.thumbnails)],
                    replaces: ["l.sw.thumbnailSize"], keys: ["thumbnailSize"],
                    search: SearchSpec("Thumbnail size", keywords: ["size", "bigger", "smaller"], root: root)),
        ControlSpec("switcher.page.includeMinimized", .setting, replaces: ["l.sw.shortcut.includeMinimized"],
                    keys: ["shortcuts.*.includeMinimized"],
                    search: SearchSpec("Include minimized and hidden windows", keywords: ["minimized", "hidden"], root: root)),
        ControlSpec("switcher.page.spaces", .setting, replaces: ["l.sw.shortcut.spaces"], keys: ["shortcuts.*.spaces"],
                    search: SearchSpec("Windows from", keywords: ["spaces", "desktops", "current space"], root: root)),
        ControlSpec("switcher.page.advanced", .button),
    ]
}
