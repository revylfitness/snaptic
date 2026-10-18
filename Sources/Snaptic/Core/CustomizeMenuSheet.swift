import AppKit
import SwiftUI
import SnapticKit

/// Menu Bar › Customize Displays Menu… (PLAN 0.3 §4.3, R5-11, N16): every Displays menu item with a 0.3 location
/// has a row here. Independent disclosure groups in one grouped form (no accordion): Displays (order and
/// visibility, section order, badges, the display row with one display), Per Display (expanded by default),
/// Displays Section and Display Tools. The filter shows matching rows in every group and expands the groups that
/// have one. In each group the items whose feature is off collapse into one dimmed row that lists them with
/// "Turn On in Settings…". Choices are stored in `DisplaysConfig.menu` (the one source the menu builder reads);
/// a custom action's checkbox is its Automations › "Show in menu" flag.
///
/// `focus`: the display Display Details' "Customize Displays Menu…" link asked for (parity M6): the Displays group
/// opens with that display's row marked. A search result expands the group holding its row
/// (`SettingsRevealExpansion`), and the sheet reports its appearance so the highlight shows at once.
struct CustomizeMenuSheet: View, ControlDeclaring {
    typealias Controls = CustomizeMenuSheetControls

    var focus: DisplayKey?

    var body: some View {
        if let host = SettingsShell.shared.host {
            CustomizeMenuContent(host: host, displays: host.displaysStore, env: host.displays.pageEnvironment,
                                 runtime: host.displays.runtime, focus: focus)
        } else {
            UnavailablePage()
        }
    }
}

private struct CustomizeMenuContent: View {
    typealias Controls = CustomizeMenuSheetControls

    let host: ModuleHost
    @ObservedObject var displays: ConfigStore<DisplaysConfig>
    @ObservedObject var env: DisplaysPageEnvironment
    @ObservedObject var runtime: DisplaysRuntimeState
    let focus: DisplayKey?
    @State private var filter = ""
    @State private var expanded: Set<String> = [DisplayMenuCustomizeGroup.perDisplay.rawValue]

    private static let displaysGroupID = "displays"

    var body: some View {
        AdvancedSheet(L("Customize Displays Menu"),
                      restoreDefaults: RestoreDefaults(
                          title: L("Restore Displays Menu Defaults…"),
                          question: L("Restore the Displays menu to its defaults?"),
                          message: L("Display order, visibility and every item's place go back to their defaults. Your other Snaptic settings stay as they are."),
                          button: L("Restore Defaults"), destructive: false) {
                          displays.value.menu = displays.value.menu.restoringDefaults(scope: .displaysMenu)
                      }) {
            Section {
                MenuFilterField(text: $filter, prompt: L("Filter menu items"))
            }
            Section {
                let open = isExpanded(Self.displaysGroupID, hasMatch: displaysGroupMatches)
                DisclosureGroup(isExpanded: open) {
                    displaysGroup
                } label: {
                    Text(L("Displays"))
                        .modifier(SettingsAnchor(ControlID("menubar.customize.displays")))
                }
                .modifier(SettingsRevealExpansion([
                    ControlID("menubar.customize.displays"), ControlID("menubar.customize.useDefaultOrder"),
                    ControlID("menubar.customize.sectionOrder"), ControlID("menubar.customize.showBadges"),
                    ControlID("menubar.customize.headerForSingleDisplay"),
                ], isExpanded: open))
            }
            ForEach(DisplayMenuCustomizeGroup.allCases, id: \.self) { group in
                let rows = matchingRows(group)
                let actions = group == .section ? matchingActions : []
                if filter.isEmpty || !rows.isEmpty || !actions.isEmpty {
                    Section {
                        let open = isExpanded(group.rawValue, hasMatch: !rows.isEmpty || !actions.isEmpty)
                        DisclosureGroup(isExpanded: open) {
                            itemRows(rows, actions: actions, group: group)
                        } label: {
                            Text(group.title)
                        }
                        .modifier(SettingsRevealExpansion(Self.anchors(in: group), isExpanded: open))
                    }
                }
            }
        }
        // A search result's highlight is shown now that the sheet is up (each group above expands for its rows).
        .onAppear {
            SettingsShell.shared.sheetDidAppear()
            revealFocus()
        }
        .onChange(of: focus) { _, _ in revealFocus() }
    }

    // MARK: Reveal

    /// Opens the Displays group when Display Details asked for one of its displays.
    private func revealFocus() {
        guard let focus, runtime.displays.contains(where: { $0.key == focus }) else { return }
        expanded.insert(Self.displaysGroupID)
    }

    /// The search anchors of a group's rows (its custom actions' row too).
    private static func anchors(in group: DisplayMenuCustomizeGroup) -> [ControlID] {
        let rows = DisplaysMenuPlan.customizeRows(group).compactMap { control(for: $0.id) }
        return group == .section ? rows + [ControlID("menubar.customize.actions")] : rows
    }

    private static func needGroupID(_ group: DisplayMenuCustomizeGroup) -> String { "need." + group.rawValue }

    // MARK: Disclosure

    /// Independent groups (R5-11); while filtering, a group with a match is open.
    private func isExpanded(_ id: String, hasMatch: Bool) -> Binding<Bool> {
        Binding(get: { filter.isEmpty ? expanded.contains(id) : hasMatch },
                set: { open in
                    guard filter.isEmpty else { return }
                    if open { expanded.insert(id) } else { expanded.remove(id) }
                })
    }

    // MARK: Displays group

    private struct DisplayRow: Identifiable {
        let id: DisplayKey
        let name: String
        let symbol: String
        let isMain: Bool
    }

    private var menu: MenuConfig { displays.value.menu }

    private var mainKey: DisplayKey? { runtime.displays.first(where: \.isMain)?.key }

    private var displayRows: [DisplayRow] {
        let all = runtime.displays
        let order = menu.orderedDisplays(all.map(\.key), main: mainKey, includeHidden: true)
        return order.compactMap { key in
            all.first { $0.key == key }.map {
                DisplayRow(id: $0.key, name: $0.name, symbol: DisplayMenuBlock.symbol(for: $0, config: displays.value),
                           isMain: $0.isMain)
            }
        }
    }

    private var displaysGroupMatches: Bool {
        !filter.isEmpty && (displayRows.contains { DisplaysMenuPlan.matches($0.name, query: filter) }
            || [L("Section order"), L("Status badges"), L("Display row with one display")]
                .contains { DisplaysMenuPlan.matches($0, query: filter) })
    }

    @ViewBuilder private var displaysGroup: some View {
        let rows = displayRows.filter { DisplaysMenuPlan.matches($0.name, query: filter) }
        if runtime.displays.isEmpty {
            Text(L("Turn on Displays to choose which displays the menu shows."))
                .foregroundStyle(.secondary)
        } else {
            ReorderableList(orderBinding, onDelete: nil) { row in
                Toggle(isOn: visibleBinding(row.id)) {
                    HStack(spacing: 6) {
                        Image(systemName: row.symbol)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(row.name)
                        Spacer(minLength: 8)
                        if row.isMain && menu.mainFirst {
                            Label(L("Main display"), systemImage: "pin.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel(row.isMain ? L("\(row.name), main display") : row.name)
                .accessibilityAddTraits(row.id == focus ? .isSelected : [])
                .background {
                    if row.id == focus {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .padding(.horizontal, -6)
                            .padding(.vertical, -3)
                            .accessibilityHidden(true)
                    }
                }
                .opacity(filter.isEmpty || rows.contains { $0.id == row.id } ? 1 : 0.4)
            }
            if !menu.displayOrder.isEmpty || !menu.mainFirst {
                ButtonRow(L("Use Default Order"), control: ControlID("menubar.customize.useDefaultOrder")) {
                    displays.value.menu.displayOrder = []
                    displays.value.menu.mainFirst = true
                }
            }
        }
        PickerSetting(L("Section order"), help: L("Whether the displays or the tools and submenus come first."),
                      selection: sectionOrderBinding,
                      options: [PickerOption(DisplaysMenuSection.displays, L("Displays First")),
                                PickerOption(DisplaysMenuSection.tools, L("Tools First"))],
                      style: .segmented, defaultValue: DisplaysMenuSection.displays,
                      anchor: ControlID("menubar.customize.sectionOrder"))
        ToggleSetting(L("Status badges"), help: L("Notes such as “Main” under each display's name."),
                      isOn: SettingsBinding.store(displays, \.menu.showBadges),
                      anchor: ControlID("menubar.customize.showBadges"),
                      disabledReason: menu.style == .compact ? L("The Compact style shows no badges.") : nil)
        ToggleSetting(L("Display row with one display"),
                      help: L("When off, a single display's sliders come before its row."),
                      isOn: SettingsBinding.store(displays, \.menu.headerForSingleDisplay),
                      anchor: ControlID("menubar.customize.headerForSingleDisplay"))
    }

    /// The order as shown; moving the main display off the top (or another display above it) unpins it, moving
    /// it back to the top pins it again ("Main display first").
    private var orderBinding: Binding<[DisplayRow]> {
        let store = displays
        let main = mainKey
        return Binding(get: { displayRows }, set: { rows in
            var config = store.value.menu
            let keys = rows.map(\.id)
            let shown = Set(keys)
            config.mainFirst = main != nil && keys.first == main
            config.displayOrder = keys + config.displayOrder.filter { !shown.contains($0) }
            config = config.sanitized()
            if store.value.menu != config { store.value.menu = config }
        })
    }

    private func visibleBinding(_ key: DisplayKey) -> Binding<Bool> {
        let store = displays
        return Binding(get: { !store.value.menu.isHidden(key) },
                       set: { visible in
                           guard store.value.menu.isHidden(key) == visible else { return }
                           store.value.menu.setHidden(!visible, for: key)
                       })
    }

    private var sectionOrderBinding: Binding<DisplaysMenuSection> {
        let store = displays
        return Binding(get: { store.value.menu.orderedSections.first ?? .displays },
                       set: { first in
                           guard store.value.menu.orderedSections.first != first else { return }
                           store.value.menu.sectionOrder = [first] + DisplaysMenuSection.allCases.filter { $0 != first }
                       })
    }

    // MARK: Item groups

    private func matchingRows(_ group: DisplayMenuCustomizeGroup) -> [DisplayMenuItemInfo] {
        DisplaysMenuPlan.customizeRows(group).filter { DisplaysMenuPlan.matches($0.title, query: filter) }
    }

    private var matchingActions: [CustomActionSpec] {
        displays.value.automation.actions.filter {
            !$0.name.isEmpty && (DisplaysMenuPlan.matches($0.name, query: filter)
                                 || DisplaysMenuPlan.matches(L("Actions"), query: filter))
        }
    }

    private func featureOn(_ feature: DisplayFeature) -> Bool {
        FeatureGraph.rawState(feature, in: displays.value.rawFeatures)
    }

    @ViewBuilder
    private func itemRows(_ rows: [DisplayMenuItemInfo], actions: [CustomActionSpec],
                          group: DisplayMenuCustomizeGroup) -> some View {
        let split = DisplaysMenuPlan.partition(rows, featureOn: featureOn)
        ForEach(split.available) { info in
            itemRow(info)
        }
        if !actions.isEmpty && featureOn(.customActions) {
            ForEach(actions) { action in
                ToggleSetting(L("Actions › \(action.name)"), isOn: actionBinding(action.id),
                              anchor: ControlID("menubar.customize.actions"))
                    .toggleStyle(.checkbox)
            }
        }
        let off = needFeatureRows(split.needFeatures, actions: actions)
        if !off.isEmpty {
            let open = isExpanded(Self.needGroupID(group), hasMatch: true)
            DisclosureGroup(isExpanded: open) {
                ForEach(off) { info in
                    LabeledContent {
                        Button(L("Turn On in Settings…")) { openFeature(info.feature) }
                            .controlSize(.small)
                            .modifier(SettingsAnchor(ControlID("menubar.customize.needFeatures")))
                    } label: {
                        Text(info.title)
                        if let feature = info.feature { Text(L("Needs \(DisplaysUIText.title(feature))")) }
                    }
                    .modifier(OptionalSettingsAnchor(Self.control(for: info.id)))
                }
            } label: {
                Text(DisplaysMenuPlan.needFeaturesTitle(off.count))
                    .foregroundStyle(.secondary)
            }
            .modifier(SettingsRevealExpansion(off.compactMap { Self.control(for: $0.id) }, isExpanded: open))
        }
    }

    /// The rows whose feature is off, with the Actions family when custom actions are off.
    private func needFeatureRows(_ rows: [DisplayMenuItemInfo], actions: [CustomActionSpec]) -> [DisplayMenuItemInfo] {
        guard !actions.isEmpty, !featureOn(.customActions),
              let family = DisplaysMenuPlan.info(for: DisplayMenuItemID(rawValue: DisplaysMenuPlan.customActionPrefix))
        else { return rows }
        return rows + [family]
    }

    @ViewBuilder
    private func itemRow(_ info: DisplayMenuItemInfo) -> some View {
        let fallback = defaultVisibility(info.id)
        let anchor = Self.control(for: info.id)
        if info.isLocked {
            ToggleSetting(info.title, help: L("Shown whenever display automation is paused."), isOn: .constant(true),
                          anchor: anchor)
                .toggleStyle(.checkbox)
                .disabled(true)
        } else if info.offersSubmenuChoice {
            PickerSetting(info.title, help: L("Show puts it right under the display's name."),
                          selection: visibilityBinding(info.id, default: fallback),
                          options: [PickerOption(MenuItemVisibility.visible, L("Show")),
                                    PickerOption(MenuItemVisibility.inSubmenu, L("In Display Submenu")),
                                    PickerOption(MenuItemVisibility.hidden, L("Hide"))],
                          style: .popUp, defaultValue: fallback, anchor: anchor)
        } else {
            ToggleSetting(info.title, isOn: shownBinding(info.id, default: fallback), anchor: anchor)
                .toggleStyle(.checkbox)
        }
    }

    /// The running contributor's default, else the Kit table's (the two are equal, DisplaysMenuPlanTests).
    private func defaultVisibility(_ id: DisplayMenuItemID) -> MenuItemVisibility {
        let declared = env.context?.menus.descriptors.first { $0.id == id }?.defaultVisibility
        return DisplaysMenuPlan.defaultVisibility(id, declared: declared)
    }

    private func shownBinding(_ id: DisplayMenuItemID, default fallback: MenuItemVisibility) -> Binding<Bool> {
        let store = displays
        return Binding(get: { store.value.menu.isShown(id, default: fallback) },
                       set: { shown in
                           guard store.value.menu.isShown(id, default: fallback) != shown else { return }
                           store.value.menu.setShown(shown, for: id, default: fallback)
                       })
    }

    private func visibilityBinding(_ id: DisplayMenuItemID, default fallback: MenuItemVisibility) -> Binding<MenuItemVisibility> {
        let store = displays
        return Binding(get: { store.value.menu.visibility(of: id, default: fallback) },
                       set: { choice in
                           guard store.value.menu.visibility(of: id, default: fallback) != choice else { return }
                           store.value.menu.setVisibility(choice, for: id, default: fallback)
                       })
    }

    /// The same flag as Automations › "Show in menu".
    private func actionBinding(_ id: StableID) -> Binding<Bool> {
        let store = displays
        return Binding(get: { store.value.automation.actions.first { $0.id == id }?.showInMenu ?? false },
                       set: { on in
                           guard let i = store.value.automation.actions.firstIndex(where: { $0.id == id }),
                                 store.value.automation.actions[i].showInMenu != on else { return }
                           store.value.automation.actions[i].showInMenu = on
                       })
    }

    /// Closes the sheet and shows the feature's settings (the Displays root when that page isn't there).
    private func openFeature(_ feature: DisplayFeature?) {
        let shell = SettingsShell.shared
        shell.openSheet = nil
        let page = feature.flatMap { FeatureGraph.specs[$0]?.page }.map { "displays." + $0 } ?? SettingsRootID.displays
        shell.open(page: page, external: false)
    }

    /// The sheet row of each 0.2 menu id (CustomizeMenuSheetControls).
    private static func control(for id: DisplayMenuItemID) -> ControlID? {
        switch id.rawValue {
        case "c.brightness.slider": return ControlID("menubar.customize.brightness")
        case "c.ddc.volume": return ControlID("menubar.customize.volume")
        case "c.ddc.contrast": return ControlID("menubar.customize.contrast")
        case "c.ddc.custom": return ControlID("menubar.customize.customControl")
        case "d.resolutionSlider": return ControlID("menubar.customize.resolutionSlider")
        case "d.resolutionMenu": return ControlID("menubar.customize.resolutions")
        case "d.setMain": return ControlID("menubar.customize.useAsMain")
        case "d.mirrorMenu": return ControlID("menubar.customize.mirror")
        case "d.hdrToggle": return ControlID("menubar.customize.hdr")
        case "c.xdr.toggle": return ControlID("menubar.customize.extraBrightness")
        case "d.smartHiDPI": return ControlID("menubar.customize.sharperText")
        case "c.color.submenu": return ControlID("menubar.customize.adjustColors")
        case "c.color.autoBrightness": return ControlID("menubar.customize.autoBrightness")
        case "c.menuBarStrip.toggle": return ControlID("menubar.customize.menuBarBackground")
        case "d.underscanMenu": return ControlID("menubar.customize.underscan")
        case "e.pip.display": return ControlID("menubar.customize.pip")
        case "d.rotationMenu": return ControlID("menubar.customize.rotation")
        case "c.color.profiles": return ControlID("menubar.customize.colorProfile")
        case "c.color.applePresets": return ControlID("menubar.customize.preset")
        case "c.ddc.input": return ControlID("menubar.customize.input")
        case "c.ddc.mute": return ControlID("menubar.customize.mute")
        case "c.ddc.power": return ControlID("menubar.customize.power")
        case "d.disconnectItem": return ControlID("menubar.customize.disconnect")
        case "b.resumeAutomation": return ControlID("menubar.customize.resume")
        case "d.arrange": return ControlID("menubar.customize.arrange")
        case "d.layoutsMenu": return ControlID("menubar.customize.layouts")
        case "d.layoutMatch": return ControlID("menubar.customize.layoutMatch")
        case "d.protection": return ControlID("menubar.customize.protection")
        case "d.virtualMenu": return ControlID("menubar.customize.virtual")
        case "e.pip.tools": return ControlID("menubar.customize.pipTools")
        case "f.tools.identify": return ControlID("menubar.customize.identify")
        case "f.tools.redetect": return ControlID("menubar.customize.redetect")
        case "f.tools.panel": return ControlID("menubar.customize.panel")
        case "d.matchUI": return ControlID("menubar.customize.matchTextSize")
        case "d.connectAll": return ControlID("menubar.customize.connectAll")
        case "d.disconnectAllButMain": return ControlID("menubar.customize.disconnectAllButMain")
        case "b.restoreAll": return ControlID("menubar.customize.restoreAll")
        case "c.sync.toggle": return ControlID("menubar.customize.sync")
        case "c.tools.nightShift": return ControlID("menubar.customize.nightShift")
        default: return nil
        }
    }
}

/// The sheet's filter: a native search field (AppKit's rounded field with the magnifier and clear button).
private struct MenuFilterField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
