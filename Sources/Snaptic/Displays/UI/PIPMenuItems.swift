import AppKit
import SnapticKit

fileprivate extension DisplayMenuItemID {
    static let pipDisplay = DisplayMenuItemID(rawValue: "e.pip.display")
    static let pipTools = DisplayMenuItemID(rawValue: "e.pip.tools")
}

/// Picture in Picture menu items (0.3 §5.2, §4.8 rows `e.pip.display` and `e.pip.tools`), built with MenuKit:
/// - display submenu: ✓ "Show in Picture in Picture" (a window PIP of that display; click starts or stops it);
/// - Displays section: "Picture in Picture ›" while something is saved: the saved PIPs and streams (✓ = running;
///   a click starts or stops one), ─, Stop All, and "More…" when the list is cut short (`PIPMenuPlan`).
/// Constructed and registered by PIPController in start(). Items capture DisplayKeys and configuration ids and
/// re-resolve them at click time.
@MainActor final class PIPMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = PIPMenuItemsControls

    weak var context: DisplaysContext?
    weak var controller: PIPController?

    init(context: DisplaysContext) { self.context = context }

    static var menuItemIDs: [DisplayMenuItemID] { [.pipDisplay, .pipTools] }

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: .pipDisplay, title: L("Show in Picture in Picture"), slot: .display,
                                      defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: .pipTools, title: L("Picture in Picture"), slot: .tools, defaultVisibility: .visible),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let ctx = context, let controller, ctx.runtime.isEffective(.pip), display.isOnline else { return [] }
        let key = display.key
        let item = MenuKit.toggle(L("Show in Picture in Picture"), isOn: controller.isShowingDisplay(key),
                                  control: ControlID("menu.display.e.showInPIP")) { [weak controller] in
            controller?.toggleDisplay(key)
        }
        return [(.pipDisplay, item)]
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let ctx = context, let controller, ctx.runtime.isEffective(.pip) else { return [] }
        let entries = PIPConfig.entries(in: ctx.config.value)
        let running = Set(ctx.capture.sessions.map(\.id))
        let connected = Set(ctx.registry.displays.filter(\.isOnline).map(\.key))
        guard let plan = PIPMenuPlan.plan(entries: entries, running: running, connected: connected) else { return [] }
        let states = Dictionary(ctx.capture.sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })

        var items: [NSMenuItem] = []
        for row in plan.rows {
            let id = row.id
            let item = MenuKit.toggle(row.name, isOn: row.running, enabled: row.available,
                                      control: ControlID("menu.display.e.pip.saved")) { [weak controller] in
                controller?.toggle(id)
            }
            items.append(MenuKit.withSubtitle(item, subtitle(row, state: states[id], ctx: ctx, entries: entries)))
        }
        items.append(MenuKit.separator())
        items.append(MenuKit.action(L("Stop All"), enabled: plan.anyRunning,
                                    control: ControlID("menu.display.e.pip.stopAll")) { [weak controller] in
            controller?.stopAll()
        })
        if plan.truncated {
            items.append(MenuKit.action(L("More…"), control: ControlID("menu.display.e.pip.more")) { [weak ctx] in
                ctx?.openSettings("displays.pip")
            })
        }
        let submenu = MenuKit.submenu(L("Picture in Picture"), symbol: "pip", control: ControlID("menu.display.e.pip"), items)
        return [(.pipTools, submenu)]
    }

    /// The secondary line: what a running PIP is doing when it isn't simply showing ("Paused", "Hidden"), why an
    /// idle one can't start, or where a stream goes.
    private func subtitle(_ row: PIPMenuPlan.Row, state: PIPSessionInfo.State?, ctx: DisplaysContext,
                          entries: [PIPEntry]) -> String? {
        if let state, state != .running { return state.title }
        guard !row.available else {
            guard row.kind == .fullScreen, state == nil,
                  let target = entries.first(where: { $0.configuration.id == row.id })?.configuration.target,
                  let name = ctx.registry.info(for: target)?.name else { return nil }
            return L("Full screen on \(name)")
        }
        return L("Display not connected")
    }
}
