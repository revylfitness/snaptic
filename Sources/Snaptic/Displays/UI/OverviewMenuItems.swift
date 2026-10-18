import AppKit
import SnapticKit

/// F's items in the Displays menu's Display Tools submenu (PLAN 0.3 §5.2): Identify Displays, Redetect Displays and
/// Show Displays Panel, built with MenuKit. Constructed and registered by OverviewController in start(); the
/// actions run through the controller, the same ones the panel, the shortcuts and the CLI use.
@MainActor final class OverviewMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = OverviewMenuItemsControls

    static let identifyItem = DisplayMenuItemID(rawValue: "f.tools.identify")
    static let redetectItem = DisplayMenuItemID(rawValue: "f.tools.redetect")
    static let panelItem = DisplayMenuItemID(rawValue: "f.tools.panel")

    static var menuItemIDs: [DisplayMenuItemID] { [identifyItem, redetectItem, panelItem] }

    weak var context: DisplaysContext?
    /// Runs the actions; set by OverviewController right after init.
    weak var owner: OverviewController?

    init(context: DisplaysContext) { self.context = context }

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: Self.identifyItem, title: L("Identify Displays"), slot: .tools,
                                      defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.redetectItem, title: L("Redetect Displays"), slot: .tools,
                                      defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.panelItem, title: L("Show Displays Panel"), slot: .tools,
                                      defaultVisibility: .visible),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, context != nil else { return [] }
        return [
            (Self.identifyItem, MenuKit.action(L("Identify Displays"), symbol: "number.square",
                                               control: ControlID("menu.display.f.identify")) { [weak self] in
                _ = self?.owner?.identifyDisplays()
            }),
            (Self.redetectItem, MenuKit.action(L("Redetect Displays"), symbol: "arrow.triangle.2.circlepath",
                                               control: ControlID("menu.display.f.redetect")) { [weak self] in
                self?.owner?.redetect()
            }),
            (Self.panelItem, MenuKit.action(L("Show Displays Panel"), symbol: "slider.horizontal.3",
                                            control: ControlID("menu.display.f.panel")) { [weak self] in
                self?.owner?.togglePanel()
            }),
        ]
    }
}
