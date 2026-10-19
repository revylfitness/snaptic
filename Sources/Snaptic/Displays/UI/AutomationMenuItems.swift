import AppKit
import SnapticKit

/// The custom actions marked "Show in menu" (PLAN 0.3 §5.2 "Actions ›", §4.8 `a.custom.<id>`): one item per action
/// that runs it. Constructed and registered by `AutomationController` while custom actions run; built on MenuKit.
@MainActor final class AutomationMenuItems: DisplayMenuContributor {
    typealias Controls = AutomationMenuItemsControls

    weak var context: DisplaysContext?
    weak var controller: AutomationController?

    init(context: DisplaysContext) { self.context = context }

    // `menuItemIDs` stays empty: the ids are per action (`a.custom.<action id>`), a family no static list can name.

    private var shown: [CustomActionSpec] {
        context?.config.value.automation.actions.filter { $0.showInMenu && !$0.name.isEmpty } ?? []
    }

    var descriptors: [DisplayMenuItemDescriptor] {
        shown.map { DisplayMenuItemDescriptor(id: Self.menuID($0), title: $0.name, slot: .tools, defaultVisibility: .visible) }
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let controller else { return [] }
        return shown.map { spec in
            let id = spec.id
            let item = MenuKit.action(spec.name, control: ControlID("menu.display.a.action")) { [weak controller] in
                controller?.runAction(id)
            }
            return (Self.menuID(spec), item)
        }
    }

    static func menuID(_ spec: CustomActionSpec) -> DisplayMenuItemID {
        DisplayMenuItemID(rawValue: "a.custom." + spec.id.rawValue)
    }
}
