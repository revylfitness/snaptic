import AppKit
import SnapticKit

// The Dock Previews section of the Snaptic menu (lead; PLAN 0.5 §4.19, A7). Kit's `DockPageRules.menu` decides the
// rows from the module's facts; this turns them into MenuKit items, built fresh on each open, and runs a row through
// the module. Rows 1 and 2 have no section.

@MainActor struct DockMenuRows {
    typealias Controls = DockMenuRowsControls

    /// The menu's Pause Dock Previews for 1 Hour.
    static let pauseSeconds = 3600

    let module: DockPreviewsModule

    /// The status item, Open … Settings… (row 4), Pause for 1 Hour or Resume, and Dock Previews Settings….
    func items() -> [NSMenuItem] {
        DockPageRules.menu(module.pageFacts()).map(item)
    }

    private func item(_ row: DockMenuItem) -> NSMenuItem {
        switch row {
        case .status(let text):
            return MenuKit.status(text, control: ControlID("menu.dock.status"))
        case .openPane:
            return MenuKit.action(row.title, control: ControlID("menu.dock.openPrivacy")) { [weak module] in
                module?.openPrivacy(.accessibility)
            }
        case .pauseForOneHour:
            return MenuKit.action(row.title, control: ControlID("menu.dock.pause")) { [weak module] in
                module?.pauseByCommand(seconds: Self.pauseSeconds)
            }
        case .resume:
            return MenuKit.action(row.title, control: ControlID("menu.dock.resume")) { [weak module] in
                module?.resumeCommandPause()
            }
        case .settings:
            return MenuKit.action(row.title, control: ControlID("menu.dock.settings")) { [weak module] in
                module?.openSettings(SettingsRootID.dockPreviews)
            }
        }
    }
}
