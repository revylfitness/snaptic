import SwiftUI
import SnapticKit

/// General → Menu, Displays part (PLAN §3.5): the Displays menu layout (compact or
/// expanded blocks, main display first, badges, section order, display order), then every
/// registered menu item descriptor, by slot, with Visible / In submenu / Hidden. Choices
/// are stored in the Displays settings' MenuConfig (the one source of truth the menu
/// builder reads); choosing an item's default removes the override.
struct MenuCustomizationPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    var body: some View {
        layoutSections
        itemSections
    }

    // MARK: Layout

    @ViewBuilder
    private var layoutSections: some View {
        let menu = env.config.value.menu
        Section {
            Picker(L("Display blocks"), selection: menuBinding(\.compact)) {
                Text(L("Expanded")).tag(false)
                Text(L("Compact")).tag(true)
            }
            Toggle(L("Main display first"), isOn: menuBinding(\.mainFirst))
            Toggle(L("Status badges in display headers"), isOn: menuBinding(\.showBadges))
                .disabled(menu.compact)
            Toggle(L("Show the header row with only one display"), isOn: menuBinding(\.headerForSingleDisplay))
        } header: {
            Text(L("Displays menu layout"))
        } footer: {
            Text(menu.compact
                 ? L("Compact blocks put the “More” items on the header row and leave out badges.")
                 : L("Expanded blocks show each display's controls on their own rows."))
        }
        Section(L("Section order")) {
            let sections = menu.orderedSections
            ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                HStack {
                    Text(Self.title(section))
                    Spacer()
                    moveButtons(name: Self.title(section), canUp: index > 0, canDown: index < sections.count - 1,
                                up: { env.config.value.menu.moveSection(section, by: -1) },
                                down: { env.config.value.menu.moveSection(section, by: 1) })
                }
            }
        }
        displayOrderSection(menu)
    }

    @ViewBuilder
    private func displayOrderSection(_ menu: MenuConfig) -> some View {
        let all = env.runtime.displays
        let main = all.first(where: \.isMain)?.key
        let order = menu.orderedDisplays(all.map(\.key), main: main, includeHidden: true)
        let rows = order.compactMap { key in all.first { $0.key == key } }
        // With "Main display first", the main display is pinned at the top.
        let pinned = menu.mainFirst && main != nil && order.first == main ? 1 : 0
        Section {
            if rows.isEmpty {
                Text(env.context == nil ? L("Turn on Displays to order the connected displays.")
                                        : L("No displays detected yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(rows.enumerated()), id: \.element.key) { index, display in
                HStack {
                    // The same numbers `snaptic list`, Identify and bare CLI selectors use.
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(display.name)
                    if display.key == main && pinned == 1 {
                        Text(L("Main, always first")).font(.caption).foregroundStyle(.secondary)
                    }
                    if menu.isHidden(display.key) {
                        Text(L("Hidden")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    moveButtons(name: display.name, canUp: index > pinned, canDown: index >= pinned && index < rows.count - 1,
                                up: { env.config.value.menu.move(display.key, by: -1, in: order) },
                                down: { env.config.value.menu.move(display.key, by: 1, in: order) })
                }
            }
            if !menu.displayOrder.isEmpty || menu.sectionOrder != DisplaysMenuSection.allCases {
                Button(L("Use the Default Order")) {
                    env.config.value.menu.displayOrder = []
                    env.config.value.menu.sectionOrder = DisplaysMenuSection.allCases
                }
            }
        } header: {
            Text(L("Display order"))
        } footer: {
            Text(L("Menu, floating panel and Identify use this order. Hide or rename displays under Displays → Display Names."))
        }
    }

    private func moveButtons(name: String, canUp: Bool, canDown: Bool,
                             up: @escaping () -> Void, down: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: up) { Image(systemName: "chevron.up") }
                .disabled(!canUp)
                .accessibilityLabel(L("Move \(name) up"))
            Button(action: down) { Image(systemName: "chevron.down") }
                .disabled(!canDown)
                .accessibilityLabel(L("Move \(name) down"))
        }
        .buttonStyle(.borderless)
    }

    private func menuBinding(_ keyPath: WritableKeyPath<MenuConfig, Bool>) -> Binding<Bool> {
        Binding(get: { env.config.value.menu[keyPath: keyPath] },
                set: { env.config.value.menu[keyPath: keyPath] = $0 })
    }

    static func title(_ section: DisplaysMenuSection) -> String {
        switch section {
        case .displays: return L("Displays")
        case .tools: return L("Tools")
        }
    }

    // MARK: Items

    @ViewBuilder
    private var itemSections: some View {
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
