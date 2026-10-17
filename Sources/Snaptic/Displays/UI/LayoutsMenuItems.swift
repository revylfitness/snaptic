import AppKit
import SnapticKit

/// Tools ▸ Layouts, plus "Apply 'Office' (matches now)" after a missed prompt (R5.7).
/// Constructed and registered by its controller in start().
@MainActor final class LayoutsMenuItems: DisplayMenuContributor {
    weak var context: DisplaysContext?
    weak var controller: LayoutsController?

    init(context: DisplaysContext) { self.context = context }

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: .dLayoutsMenu, title: L("Layouts"), slot: .tools, defaultVisibility: .visible),
         DisplayMenuItemDescriptor(id: .dLayoutMatch, title: L("Apply matching layout"), slot: .tools, defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let c = controller, c.effective.contains(.layouts) else { return [] }
        var result: [(DisplayMenuItemID, NSMenuItem)] = []
        if let pending = c.pendingMatch, let l = c.layout(pending) {
            result.append((.dLayoutMatch, ManagedMenuItem(L("Apply '\(l.name)' (matches now)")) { [weak c] in c?.apply(pending) }))
        }
        var items: [NSMenuItem] = []
        for l in c.layouts {
            let matches = c.matches(l) != nil
            let id = l.id
            let item = ManagedMenuItem(l.name, enabled: matches) { [weak c] in c?.apply(id) }
            if c.isTrusted(l) && l.autoApply != .never { item.toolTip = L("Applies automatically") }
            items.append(item)
        }
        if !items.isEmpty { items.append(.separator()) }
        items.append(ManagedMenuItem(L("Save Current Layout")) { [weak c] in _ = c?.captureCurrent() })
        items.append(ManagedMenuItem(L("Manage Layouts…")) { [weak self] in self?.context?.openSettings("displays.protection") })
        result.append((.dLayoutsMenu, ManagedMenuItem.submenu(L("Layouts"), items: items)))
        return result
    }
}
