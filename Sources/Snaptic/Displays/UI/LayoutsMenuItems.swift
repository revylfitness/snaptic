import AppKit
import SnapticKit

/// Displays section › "Saved Layouts" (PLAN 0.3 §5.2): the layouts (click applies; ✓ = the displays are arranged that
/// way now; layouts whose displays aren't connected are dimmed), then Apply Matching Layout, Protect Arrangement
/// (ManagementMenuItems' row, while protection is on) and Save Current Layout. Apply Matching Layout and Protect
/// Arrangement follow their own Customize Displays Menu checkboxes. Constructed and registered by LayoutsController.
@MainActor final class LayoutsMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = LayoutsMenuItemsControls

    weak var context: DisplaysContext?
    weak var controller: LayoutsController?

    init(context: DisplaysContext) { self.context = context }

    static var menuItemIDs: [DisplayMenuItemID] { [.dLayoutsMenu, .dLayoutMatch] }

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: .dLayoutsMenu, title: L("Saved Layouts"), slot: .tools, defaultVisibility: .visible),
         DisplayMenuItemDescriptor(id: .dLayoutMatch, title: L("Apply Matching Layout"), slot: .tools, defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let ctx = context, let c = controller, c.effective.contains(.layouts) else { return [] }
        let menu = ctx.config.value.menu
        var items: [NSMenuItem] = []
        let states = c.liveStates()
        for l in c.layouts {
            let id = l.id
            let connected = c.matches(l) != nil
            let current = connected && LayoutPresetModel.isCurrent(l, states: states)
            let item = MenuKit.toggle(l.name, isOn: current, enabled: connected,
                                      control: ControlID("menu.display.d.savedLayout")) { [weak c] in
                c?.apply(id)
            }
            if !connected { item.toolTip = L("Its displays aren’t all connected") }
            items.append(item)
        }
        var actions: [NSMenuItem] = []
        if menu.visibility(of: .dLayoutMatch, default: .visible) != .hidden {
            let match = c.matchingLayout()
            let enabled = match.map { !LayoutPresetModel.isCurrent($0, states: states) } ?? false
            let item = MenuKit.action(L("Apply Matching Layout"), enabled: enabled,
                                      control: ControlID("menu.display.d.applyMatchingLayout")) { [weak c] in
                guard let c, let l = c.matchingLayout() else { return }
                c.apply(l.id)
            }
            actions.append(MenuKit.withSubtitle(item, match?.name))
        }
        if menu.visibility(of: .dProtection, default: .visible) != .hidden,
           let protect = ManagementMenuItems.protectionItems(in: ctx.menus)?.protectArrangementItem() {
            actions.append(protect)
        }
        let save = MenuKit.action(L("Save Current Layout"), enabled: c.layouts.count < LayoutPresetModel.maxLayouts,
                                  control: ControlID("menu.display.d.saveCurrentLayout")) { [weak c] in
            _ = c?.captureCurrent()
        }
        actions.append(save)
        if !items.isEmpty { items.append(MenuKit.separator()) }
        items += actions
        let submenu = MenuKit.submenu(L("Saved Layouts"), symbol: "square.stack.3d.up",
                                      control: ControlID("menu.display.d.savedLayouts"), items)
        return [(.dLayoutsMenu, submenu)]
    }
}
