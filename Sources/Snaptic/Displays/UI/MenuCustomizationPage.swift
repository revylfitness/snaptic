import SwiftUI
import SnapticKit

/// General → Menu, Displays part (PLAN §3.5): every registered menu item descriptor, by
/// slot, with Visible / In submenu / Hidden. Choices are stored in the Displays
/// settings' MenuConfig (the one source of truth the menu builder reads); choosing an
/// item's default removes the override.
struct MenuCustomizationPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    var body: some View {
        if let registry = env.context?.menus {
            let descriptors = registry.descriptors
            if descriptors.isEmpty {
                Section(L("Displays menu items")) {
                    Text(L("No Displays features with menu items are on."))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(MenuSlot.allCases, id: \.self) { slot in
                    let rows = descriptors.filter { $0.slot == slot }
                    if !rows.isEmpty {
                        Section(Self.title(slot)) {
                            ForEach(rows, id: \.id) { descriptor in
                                Picker(descriptor.title, selection: binding(descriptor)) {
                                    ForEach(MenuItemVisibility.allCases, id: \.self) { choice in
                                        Text(MenuPlacement.title(choice)).tag(choice)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Section(L("Displays menu items")) {
                Text(L("Turn on the Displays module to choose which of its items appear in the menu."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(_ descriptor: DisplayMenuItemDescriptor) -> Binding<MenuItemVisibility> {
        Binding(
            get: { env.config.value.menu.visibility(of: descriptor.id, default: descriptor.defaultVisibility) },
            set: { env.config.value.menu.setVisibility($0, for: descriptor.id, default: descriptor.defaultVisibility) }
        )
    }

    static func title(_ slot: MenuSlot) -> String {
        switch slot {
        case .display: return L("Display blocks")
        case .header: return L("Display headers")
        case .tools: return L("Tools")
        case .quick: return L("Right-click menu")
        }
    }
}
