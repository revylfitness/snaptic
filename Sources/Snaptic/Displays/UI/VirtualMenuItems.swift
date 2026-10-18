import AppKit
import SnapticKit

/// Displays section › "Virtual Displays" (PLAN 0.3 §5.2): one checkmark per virtual display (connected), then
/// "Virtual Displays Settings…". Shown only while at least one virtual display exists. Constructed and registered by
/// VirtualController in start().
@MainActor final class VirtualMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = VirtualMenuItemsControls

    weak var context: DisplaysContext?
    weak var controller: VirtualController?

    init(context: DisplaysContext) { self.context = context }

    static var menuItemIDs: [DisplayMenuItemID] { [.dVirtualMenu] }

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: .dVirtualMenu, title: L("Virtual Displays"), slot: .tools, defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let c = controller, c.effective.contains(.virtualScreens), !c.screens.isEmpty else { return [] }
        var items: [NSMenuItem] = []
        for s in c.screens {
            let id = s.id
            let item = MenuKit.toggle(s.name, isOn: c.isLive(id), enabled: !c.isBusy(id),
                                      control: ControlID("menu.display.d.virtualDisplay")) { [weak c] in
                c?.toggle(id)
            }
            items.append(item)
        }
        items.append(MenuKit.separator())
        let settings = MenuKit.action(L("Virtual Displays Settings…"),
                                      control: ControlID("menu.display.d.virtualSettings")) { [weak self] in
            self?.context?.openSettings("displays.virtual")
        }
        items.append(settings)
        let submenu = MenuKit.submenu(L("Virtual Displays"), symbol: "display.2",
                                      control: ControlID("menu.display.d.virtualDisplays"), items)
        return [(.dVirtualMenu, submenu)]
    }
}
