import Foundation

// Displays › Saved Layouts (owner: D; PLAN 0.3 §4.3 sub-page table): the page, its Advanced sheet and the layout
// Details… sheet. A layout's Details… opens per layout, so its rows' search results open the page.

package enum SavedLayoutsPageControls: ControlTable {
    package static let surface = "displays.layouts"
    /// `SettingsShell.openSheet` id of the page's Advanced sheet.
    package static let advancedSheet = "displays.layouts.advanced"

    private static let root = SettingsRootID.displays
    private static let page = SettingsRoute(surface)
    private static let layouts: [ControlCondition] = [.module(.displays), .displayFeature(.layouts)]
    private static let layout: [ControlCondition] = layouts + [.perItem("layout")]

    private static func onPage(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: page)
    }

    private static func inAdvanced(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: root, route: page, sheet: advancedSheet)
    }

    package static let controls: [ControlSpec] = [
        ControlSpec("displays.layouts.enabled", .setting, when: [.module(.displays)],
                    replaces: ["l.dfeat.layouts"], keys: ["features.layouts"],
                    search: onPage("Saved layouts", ["layouts", "presets", "display profiles"])),
        ControlSpec("displays.layouts.save", .button, when: layouts,
                    replaces: ["l.d.protection.layout.save"],
                    search: onPage("Save Current Layout", ["capture layout", "new layout"])),
        ControlSpec("displays.layouts.list", .list, when: layouts,
                    replaces: ["l.d.protection.layout.status", "l.d.protection.layout.apply", "l.d.protection.layout.move"],
                    keys: ["layouts.layouts"],
                    search: onPage("Layouts", ["apply layout", "reorder layouts"])),
        ControlSpec("displays.layouts.protect", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.protect", "l.dfeat.protection"],
                    keys: ["features.protection", "management.protection"],
                    search: onPage("Protect the current arrangement", ["protection", "keep arrangement", "lock layout"])),
        ControlSpec("displays.layouts.advanced", .button, when: [.module(.displays)]),

        // Details… (one layout)
        ControlSpec("displays.layouts.details.name", .setting, when: layout,
                    replaces: ["l.d.protection.layout.name"], keys: ["layouts.layouts.*.name"],
                    search: onPage("Layout name", ["rename layout"])),
        ControlSpec("displays.layouts.details.autoApply", .setting, when: layout,
                    replaces: ["l.d.protection.layout.applyAutomatically"], keys: ["layouts.layouts.*.autoApply"],
                    search: onPage("Apply automatically", ["auto apply", "layout"])),
        ControlSpec("displays.layouts.details.priority", .setting, when: layout,
                    replaces: ["l.d.protection.layout.priority"], keys: ["layouts.layouts.*.priority"],
                    search: onPage("Layout priority", ["priority"])),
        ControlSpec("displays.layouts.details.stopTrusting", .button, when: layout,
                    replaces: ["l.d.protection.layout.stopTrusting"],
                    search: onPage("Stop Trusting", ["trust", "layout"])),
        ControlSpec("displays.layouts.details.update", .button, when: layout,
                    replaces: ["l.d.protection.layout.update"],
                    search: onPage("Update to Current", ["update layout", "recapture"])),
        ControlSpec("displays.layouts.details.delete", .button, when: layout,
                    replaces: ["l.d.protection.layout.delete"]),

        // Advanced sheet
        ControlSpec("displays.layouts.advanced.fieldMode", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.fields"], keys: ["management.protectionFields.mode"],
                    search: inAdvanced("Protect resolution and refresh rate", ["protected fields"])),
        ControlSpec("displays.layouts.advanced.fieldPosition", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.fields"], keys: ["management.protectionFields.origin"],
                    search: inAdvanced("Protect position", ["protected fields", "arrangement"])),
        ControlSpec("displays.layouts.advanced.fieldMain", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.fields"], keys: ["management.protectionFields.main"],
                    search: inAdvanced("Protect main display", ["protected fields"])),
        ControlSpec("displays.layouts.advanced.fieldMirroring", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.fields"], keys: ["management.protectionFields.mirror"],
                    search: inAdvanced("Protect mirroring", ["protected fields"])),
        ControlSpec("displays.layouts.advanced.fieldRotation", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.fields"], keys: ["management.protectionFields.rotation"],
                    search: inAdvanced("Protect rotation", ["protected fields"])),
        ControlSpec("displays.layouts.advanced.updateProtected", .button,
                    when: [.module(.displays), .displayFeature(.protection)],
                    replaces: ["l.d.protection.saveProtected"],
                    search: inAdvanced("Update Protected State to Current", ["protection", "save protected"])),
        ControlSpec("displays.layouts.advanced.forgetAll", .button, when: [.module(.displays)],
                    replaces: ["l.d.protection.forgetAll"],
                    search: inAdvanced("Forget all protected arrangements", ["protection", "reset"])),
        ControlSpec("displays.layouts.advanced.undoToast", .setting, when: [.module(.displays)],
                    replaces: ["l.d.protection.undoToast"], keys: ["layouts.undoToast"],
                    search: inAdvanced("Offer Undo after an automatic apply", ["undo", "notice", "layout"])),
        ControlSpec("displays.layouts.advanced.restore", .button, when: [.module(.displays)]),
    ]
}
