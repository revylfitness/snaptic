import Foundation

// Displays › Virtual Displays (owner: D; PLAN 0.3 §4.3 sub-page table): the page and its Advanced sheet.

package enum VirtualDisplaysPageControls: ControlTable {
    package static let surface = "displays.virtual"
    /// `SettingsShell.openSheet` id of the page's Advanced sheet.
    package static let advancedSheet = "displays.virtual.advanced"

    private static let root = SettingsRootID.displays
    private static let page = SettingsRoute(surface)
    private static let virtual: [ControlCondition] = [.module(.displays), .displayFeature(.virtualScreens)]
    private static let smart: [ControlCondition] = [.module(.displays), .displayFeature(.smartHiDPI)]

    private static func onPage(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: page)
    }

    private static func inAdvanced(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: page, sheet: advancedSheet)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.virtual.enabled", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.virtualScreens"], keys: ["features.virtualScreens"],
                    search: onPage("Virtual displays", ["virtual screens", "dummy display", "headless"])),
        ControlSpec("displays.virtual.list", .list, when: virtual,
                    replaces: ["l.d.virtual.connected", "l.d.virtual.edit"],
                    keys: ["virtualScreens.screens", "virtualScreens.connected"],
                    search: onPage("Connect a virtual display", ["virtual displays", "connected"])),
        ControlSpec("displays.virtual.new", .button, when: virtual,
                    search: onPage("New Virtual Display", ["create virtual display", "add display"])),
        ControlSpec("displays.virtual.sharperText", .setting,
                    when: virtual + [.displayFeature(.smartHiDPI), .hardware(.externalDisplay), .perItem("display")],
                    replaces: ["l.d.virtual.smartHiDPI.enabled"], keys: ["virtualScreens.smartHiDPI"],
                    search: onPage("Sharper text on this display", ["Smart HiDPI", "HiDPI", "scaling", "blurry text"])),
        ControlSpec("displays.virtual.advanced", .button, when: [.module(.displays)],
                    search: onPage("Virtual Displays Advanced Settings", ["behavior", "Smart HiDPI"])),

        // Advanced sheet
        ControlSpec("displays.virtual.advanced.sharperText", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.smartHiDPI"], keys: ["features.smartHiDPI"],
                    search: inAdvanced("Sharper text", ["Smart HiDPI", "HiDPI"])),
        ControlSpec("displays.virtual.advanced.size", .setting,
                    when: smart + [.perItem("display"), .parentOn(ControlID("displays.virtual.advanced.sharperText"))],
                    replaces: ["l.d.virtual.smartHiDPI.size"], keys: ["virtualScreens.smartHiDPI.*.mode"],
                    search: inAdvanced("Sharper text size", ["Smart HiDPI size"])),
        ControlSpec("displays.virtual.advanced.smartHDR", .setting,
                    when: smart + [.displayFeature(.hdrVirtual), .perItem("display"),
                                   .parentOn(ControlID("displays.virtual.advanced.sharperText"))],
                    replaces: ["l.d.virtual.smartHiDPI.hdr"], keys: ["virtualScreens.smartHiDPI.*.hdr"],
                    search: inAdvanced("HDR for sharper text", ["PQ", "Smart HiDPI HDR"])),
        ControlSpec("displays.virtual.advanced.restoreLayout", .setting, when: [.module(.displays)],
                    replaces: ["l.d.virtual.behavior.restoreLayoutAfterConnect"],
                    keys: ["virtualScreens.restoreLayoutAfterConnect"],
                    search: inAdvanced("Restore the arrangement after a virtual display connects", ["arrangement"])),
        ControlSpec("displays.virtual.advanced.reconnectAfterWake", .setting, when: [.module(.displays)],
                    replaces: ["l.d.virtual.behavior.reconnectAfterWake"], keys: ["virtualScreens.reconnectAfterWake"],
                    search: inAdvanced("Reconnect after wake", ["virtual displays", "sleep"])),
        ControlSpec("displays.virtual.advanced.disconnectOnLock", .setting, when: [.module(.displays)],
                    replaces: ["l.d.virtual.behavior.disconnectOnLock"], keys: ["virtualScreens.disconnectOnLock"],
                    search: inAdvanced("Disconnect while the screen is locked", ["lock", "virtual displays"])),
        ControlSpec("displays.virtual.advanced.bulk", .button, when: virtual,
                    replaces: ["l.d.virtual.bulk"],
                    search: inAdvanced("All Virtual Displays", ["connect all", "disconnect all", "discard all"])),
        ControlSpec("displays.virtual.advanced.hdr", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.hdrVirtual"], keys: ["features.hdrVirtual"],
                    search: inAdvanced("HDR virtual modes", ["HDR", "PQ"])),
        ControlSpec("displays.virtual.advanced.restore", .button, when: [.module(.displays)],
                    search: inAdvanced("Restore Virtual Displays Defaults", ["reset"])),
    ]
}
