import AppKit
import SnapticKit

/// Tools ▸ Virtual Screens. Constructed and registered by its controller in start().
@MainActor final class VirtualMenuItems: DisplayMenuContributor {
    weak var context: DisplaysContext?
    weak var controller: VirtualController?

    init(context: DisplaysContext) { self.context = context }

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: .dVirtualMenu, title: L("Virtual Screens"), slot: .tools, defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let c = controller, c.effective.contains(.virtualScreens) else { return [] }
        var items: [NSMenuItem] = []
        for s in c.screens {
            let id = s.id
            let item = ManagedMenuItem(s.name, on: c.isLive(id), enabled: !c.isBusy(id)) { [weak c] in c?.toggle(id) }
            item.toolTip = "\(s.aspectWidth):\(s.aspectHeight)" + (s.headlessPrimary ? " · " + L("Headless") : "")
            items.append(item)
        }
        if !c.screens.isEmpty {
            items.append(.separator())
            items.append(ManagedMenuItem(L("Connect All")) { [weak c] in c?.connectAll() })
            items.append(ManagedMenuItem(L("Disconnect All")) { [weak c] in c?.disconnectAll() })
        }
        items.append(ManagedMenuItem(L("New Virtual Screen…")) { [weak self] in self?.context?.openSettings("displays.virtual") })
        return [(.dVirtualMenu, ManagedMenuItem.submenu(L("Virtual Screens"), items: items))]
    }
}
