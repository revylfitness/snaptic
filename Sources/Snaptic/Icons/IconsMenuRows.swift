import AppKit
import UniformTypeIdentifiers
import SnapticKit

// The Hidden Icons section of the Snaptic menu and the arrow's menu (lead; PLAN 0.4 §4.3, §4.8, §4.13, A6): one row
// set, built fresh on each open through MenuKit only. Kit's `IconsHiddenListRules` decides the list and its slot;
// this turns them into items and runs a row's press through the module. The arrow's menu adds Hide Icons
// Automatically and has no Quit (the Snaptic menu and Settings have it).

@MainActor final class IconsMenuRows: NSObject, NSMenuDelegate {
    typealias Controls = IconsMenuRowsControls

    private unowned let module: IconsModule
    /// When an open last asked for a background re-read (uptime).
    private var lastRefreshAsk: Double?

    init(module: IconsModule) {
        self.module = module
    }

    // MARK: Menus

    /// The arrow's menu (§4.3), for `IconsItems.menuProvider`.
    func arrowMenu() -> NSMenu {
        let menu = NSMenu(title: module.title)
        menu.autoenablesItems = false
        menu.delegate = self
        for item in items(arrow: true) { menu.addItem(item) }
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        module.ownMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        module.ownMenuOpen = false
    }

    /// The rows: Show/Hide, Show All (the ⌥ alternate, or a plain item under assistive input), the hidden list, the
    /// Shown Icons submenu, then Hide Icons Automatically (`arrow` only) and Hidden Icons Settings….
    func items(arrow: Bool) -> [NSMenuItem] {
        askForRefresh()
        var out: [NSMenuItem] = []
        let state = module.engineState
        if module.engineKind != nil, !Self.isUnavailable(state) {
            out += toggleRows(state)
            out.append(MenuKit.separator())
        }
        out += listRows()
        out.append(MenuKit.separator())
        if arrow {
            let on = module.config.value.autoCollapse
            out.append(MenuKit.toggle(L("Hide Icons Automatically"), isOn: on,
                                      control: ControlID("menu.icons.autoCollapse")) { [weak self] in
                self?.toggleAutoCollapse()
            })
        }
        out.append(MenuKit.action(L("Hidden Icons Settings…"), control: ControlID("menu.icons.settings")) {
            [weak self] in
            self?.module.openSettings(SettingsRootID.hiddenIcons)
        })
        return out
    }

    // MARK: Show and hide

    private func toggleRows(_ state: IconsEngineState) -> [NSMenuItem] {
        let primary: NSMenuItem
        if case .expanded = state {
            primary = MenuKit.action(L("Hide Icons Again"), control: ControlID("menu.icons.hide")) { [weak self] in
                self?.module.perform(.hide, from: .menu)
            }
        } else {
            primary = MenuKit.action(L("Show Hidden Icons"), control: ControlID("menu.icons.show")) { [weak self] in
                self?.module.perform(.show, from: .menu)
            }
        }
        let showAll: @MainActor () -> Void = { [weak self] in self?.module.perform(.showAll, from: .menu) }
        guard !StatusMenu.assistiveInputInUse() else {
            // VoiceOver, Switch Control and Full Keyboard Access can't reach an ⌥ alternate (§4.13).
            return [primary, MenuKit.action(L("Show All Hidden Icons"), control: ControlID("menu.icons.showAll"),
                                            showAll)]
        }
        return [primary, MenuKit.alternate(of: primary, title: L("Show All Hidden Icons"),
                                           control: ControlID("menu.icons.showAll"), showAll)]
    }

    // MARK: The hidden list (§4.8)

    private func listRows() -> [NSMenuItem] {
        let content = IconsHiddenListRules.content(module.listFacts()) { module.hiddenList() }
        switch content {
        case .none:
            return []
        case .reason(let text):
            return [MenuKit.status(text, control: ControlID("menu.icons.reason"))]
        case .needsPermission:
            return [MenuKit.status(L("Needs Permission"), control: ControlID("menu.icons.needsPermission"))]
        case .allowAccessibility:
            // Opens Permissions; the menu never prompts (§4.8).
            return [MenuKit.action(L("Allow Accessibility to List Icons…"),
                                   control: ControlID("menu.icons.allowAccessibility")) { [weak self] in
                self?.module.openSettings(SettingsRootID.permissions)
            }]
        case .rows(let list):
            var out: [NSMenuItem] = []
            if list.isEmpty {
                out.append(MenuKit.status(L("No Hidden Icons"), control: ControlID("menu.icons.empty")))
            }
            let enabled = module.pressEnabled
            if !list.hidden.isEmpty {
                out.append(MenuKit.header(IconsHiddenListRules.hiddenHeader(list.hidden.count),
                                          control: ControlID("menu.icons.hiddenHeader")))
                out += list.hidden.map { row($0, enabled: enabled, control: ControlID("menu.icons.icon")) }
            }
            if !list.behindNotch.isEmpty {
                out.append(MenuKit.header(IconsHiddenListRules.notchHeader(list.behindNotch.count),
                                          control: ControlID("menu.icons.notchHeader")))
                out += list.behindNotch.map { row($0, enabled: enabled, control: ControlID("menu.icons.icon")) }
            }
            if !list.shown.isEmpty {
                let rows = list.shown.map { row($0, enabled: enabled, control: ControlID("menu.icons.shownIcon")) }
                out.append(MenuKit.submenu(L("Shown Icons"), control: ControlID("menu.icons.shownIcons"), rows))
            }
            return out
        }
    }

    /// One extra: its app's icon at 16 pt (decorative; a DS exception, G-21), the title as its label, and the hint
    /// "Opens its menu." (§4.13). `Icons.disable.axpress` leaves it shown but disabled.
    private func row(_ row: IconsListRow, enabled: Bool, control: ControlID) -> NSMenuItem {
        let app = NSRunningApplication(processIdentifier: row.extra.pid)
        let launched = app?.launchDate
        let item = MenuKit.action(row.title, enabled: enabled, control: control) { [weak self] in
            self?.module.press(row, launchDate: launched)
        }
        item.image = Self.icon(app)
        item.toolTip = L("Opens its menu.")
        return item
    }

    private static func icon(_ app: NSRunningApplication?) -> NSImage? {
        let source = app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        guard let image = source.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        // The title already names the app.
        image.accessibilityDescription = ""
        return image
    }

    // MARK: Helpers

    private func askForRefresh() {
        let now = ProcessInfo.processInfo.systemUptime
        guard IconsHiddenListRules.wantsRefresh(lastAsk: lastRefreshAsk, now: now) else { return }
        lastRefreshAsk = now
        module.listOpened()
    }

    private func toggleAutoCollapse() {
        var value = module.config.value
        value.autoCollapse.toggle()
        module.config.value = value
    }

    private static func isUnavailable(_ state: IconsEngineState) -> Bool {
        if case .unavailable = state { return true }
        return false
    }
}
