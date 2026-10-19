import Foundation

// New Virtual Display… and a virtual display's Details… (owner: D; PLAN 0.3 §4.3 Virtual Displays). Search opens
// the Virtual Displays page, then this sheet for the first virtual display (or New Virtual Display… without one).

package enum VirtualDisplayEditorSheetControls: ControlTable {
    package static let surface = "displays.virtual.editor"
    /// `SettingsShell.openSheet` id of the sheet (the Virtual Displays page presents it).
    package static let sheet = "displays.virtual.editor"

    private static let virtual: [ControlCondition] = [.module(.displays), .displayFeature(.virtualScreens)]
    private static let screen: [ControlCondition] = virtual + [.perItem("virtualDisplay")]

    private static func search(_ title: String, _ keywords: [String]) -> SearchSpec {
        SearchSpec(title, keywords: keywords, root: SettingsRootID.displays, route: SettingsRoute("displays.virtual"),
                   sheet: sheet)
    }

    package static let controls: [ControlSpec] = [
        // New Virtual Display…
        ControlSpec("displays.virtual.editor.shape", .setting, when: virtual,
                    replaces: ["l.d.virtual.new.shape"],
                    search: search("Virtual display shape", ["aspect ratio", "iPad", "new virtual display"])),
        ControlSpec("displays.virtual.editor.create", .button, when: virtual,
                    replaces: ["l.d.virtual.new.create"]),
        ControlSpec("displays.virtual.editor.recipes", .list, when: virtual,
                    replaces: ["l.d.virtual.recipes"],
                    search: search("Virtual display recipes", ["headless", "recording", "teleprompter", "portrait"])),

        // Details…
        ControlSpec("displays.virtual.editor.name", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.name"], keys: ["virtualScreens.screens.*.name"],
                    search: search("Virtual display name", ["rename"])),
        ControlSpec("displays.virtual.editor.aspect", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.aspect"],
                    keys: ["virtualScreens.screens.*.aspectWidth", "virtualScreens.screens.*.aspectHeight"],
                    search: search("Aspect ratio", ["virtual display shape"])),
        ControlSpec("displays.virtual.editor.diagonal", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.diagonal"], keys: ["virtualScreens.screens.*.sizeInches"],
                    search: search("Diagonal", ["inches", "virtual display size"])),
        ControlSpec("displays.virtual.editor.hiDPI", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.hiDPI"], keys: ["virtualScreens.screens.*.hiDPI"],
                    search: search("HiDPI virtual display", ["Retina", "sharper"])),
        ControlSpec("displays.virtual.editor.portrait", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.portrait"], keys: ["virtualScreens.screens.*.portrait"],
                    search: search("Portrait virtual display", ["vertical", "rotate"])),
        ControlSpec("displays.virtual.editor.reconnect", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.reconnect"], keys: ["virtualScreens.screens.*.recreateOnLaunch"],
                    search: search("Connect when Snaptic opens", ["reconnect at launch", "virtual display"])),
        ControlSpec("displays.virtual.editor.hdr", .setting, when: screen + [.displayFeature(.hdrVirtual)],
                    replaces: ["l.d.virtual.editor.hdr"], keys: ["virtualScreens.screens.*.hdr"],
                    search: search("HDR modes", ["PQ", "virtual display HDR"])),
        ControlSpec("displays.virtual.editor.refresh", .setting, when: screen,
                    replaces: ["l.d.virtual.editor.refresh"], keys: ["virtualScreens.screens.*.modes"],
                    search: search("Virtual display refresh rate", ["Hz", "hertz"])),
        ControlSpec("displays.virtual.editor.sizes", .list, when: screen,
                    replaces: ["l.d.virtual.editor.sizes"], keys: ["virtualScreens.screens.*.modes"],
                    search: search("Virtual display sizes", ["modes", "resolutions"])),
        ControlSpec("displays.virtual.editor.addSize", .button, when: screen),
        ControlSpec("displays.virtual.editor.fillSizes", .button, when: screen,
                    replaces: ["l.d.virtual.editor.fillSizes"]),
        ControlSpec("displays.virtual.editor.links", .list, when: screen,
                    replaces: ["l.d.virtual.editor.associations"], keys: ["virtualScreens.screens.*.associations"],
                    search: search("Linked displays", ["associations", "mirror onto", "stream onto"])),
        ControlSpec("displays.virtual.editor.addLink", .button, when: screen),
        ControlSpec("displays.virtual.editor.delete", .button, when: screen,
                    replaces: ["l.d.virtual.delete"]),
    ]
}
