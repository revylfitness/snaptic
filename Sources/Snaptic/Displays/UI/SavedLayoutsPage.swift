import SwiftUI
import SnapticKit

/// Displays › **Saved Layouts** (owner D; PLAN 0.3 §4.3 sub-page table): header switch "Saved layouts" (`layouts`),
/// Save Current Layout…, the layouts (name, Matches, Apply, Details…; drag or ▲▼ to reorder, which sets the
/// numbered actions 1–9) and **Protect the current arrangement** (`protection`). Advanced: the protected fields,
/// Update Protected State to Current, Forget All…, and Offer Undo after an automatic apply. Details… is a sheet:
/// apply automatically, priority, trust, Update to Current, Delete.
///
/// Live updates (§4.5): the list and match badges follow `revision(.layouts)`, protection `revision(.protection)`;
/// config through slices.
struct SavedLayoutsPage: View, ControlDeclaring {
    typealias Controls = SavedLayoutsPageControls

    private let env: DisplaysPageEnvironment?

    init() {
        env = DisplaysSettingsLookup.environment()
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env {
            SavedLayoutsContent(env: env)
        } else {
            UnavailablePage()
        }
    }

    static let title = L("Saved Layouts")
    static let summary = L("Save display arrangements and apply them automatically.")
    static let symbol = "rectangle.3.group.fill"
}

/// A layout as a list item (`SavedLayout` stays a plain Kit value).
private struct LayoutItem: Identifiable {
    let layout: SavedLayout
    var id: StableID { layout.id }
}

private struct SavedLayoutsContent: View {
    typealias Controls = SavedLayoutsPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var layoutsRevision: ControllerRevision
    @ObservedObject private var protectionRevision: ControllerRevision
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var layouts: ConfigSlice<DisplaysConfig, LayoutsConfig>
    @StateObject private var management: ConfigSlice<DisplaysConfig, ManagementConfig>
    @State private var details: LayoutItem?
    @State private var saving = false
    @State private var newName = ""

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _layoutsRevision = ObservedObject(wrappedValue: env.runtime.revision(.layouts))
        _protectionRevision = ObservedObject(wrappedValue: env.runtime.revision(.protection))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _layouts = StateObject(wrappedValue: ConfigSlice(env.config, \.layouts))
        _management = StateObject(wrappedValue: ConfigSlice(env.config, \.management))
    }

    private static let route = SettingsRoute(SavedLayoutsPageControls.surface)
    private var controller: LayoutsController? { env.context?.connectPlanner.layouts }

    var body: some View {
        SettingsPageScaffold(route: Self.route) {
            SettingsPageHeader(SavedLayoutsPage.title, summary: SavedLayoutsPage.summary, symbol: SavedLayoutsPage.symbol,
                               tint: .indigo, isOn: switcher.binding([.layouts], title: L("Saved layouts")),
                               switchLabel: L("Saved layouts"), control: ControlID("displays.layouts.enabled"))
            if env.context == nil {
                Section {
                    StatusRow(L("Turn on Displays to save and apply layouts."))
                }
            } else {
                if let reason = unavailable(.layouts) {
                    Section {
                        if let locked = switcher.lockedFeature([.layouts]) {
                            DefaultsLockRow(key: KillSwitches.key(prefix: "Displays", id: locked.rawValue))
                        } else {
                            StatusRow(reason, style: .warning)
                        }
                    }
                } else if runtime.isEffective(.layouts), let c = controller {
                    layoutsSection(c)
                } else if !FeatureGraph.rawState(.layouts, in: env.config.value.rawFeatures) {
                    FeatureHighlights([
                        FeatureHighlight(id: "layouts.save", symbol: "square.and.arrow.down",
                                         title: L("Save an arrangement"),
                                         text: L("Resolution, position, the main display, and mirroring, for every display.")),
                        FeatureHighlight(id: "layouts.auto", symbol: "bolt.horizontal",
                                         title: L("Apply it automatically"),
                                         text: L("When the same displays connect again, after you’ve kept it once.")),
                    ])
                }
                protectionSection
            }
            PageFooterButtons(advanced: { shell.openSheet = SavedLayoutsPageControls.advancedSheet }, help: Self.route,
                              advancedControl: ControlID("displays.layouts.advanced"))
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
        .sheet(isPresented: shell.sheetBinding(SavedLayoutsPageControls.advancedSheet)) {
            SavedLayoutsAdvancedSheet(env: env)
        }
        .sheet(isPresented: detailsBinding) {
            if let id = details?.id ?? layouts.value.layouts.first?.id {
                LayoutDetailsSheet(env: env, id: id)
            }
        }
        .alert(L("Save Current Layout"), isPresented: $saving) {
            TextField(L("Name"), text: $newName)
            Button(L("Save")) { save() }
            Button(L("Cancel"), role: .cancel) { newName = "" }
        } message: {
            Text(L("Saves the resolution, position, main display, and mirroring of every connected display."))
        }
    }

    private func unavailable(_ feature: DisplayFeature) -> String? {
        if case .unavailable(let reason)? = runtime.availability[feature] { return reason }
        if runtime.isEffective(feature) { return nil }
        guard FeatureGraph.rawState(feature, in: env.config.value.rawFeatures) else { return nil }
        return env.context?.otherApps.pauseReason(for: feature)
    }

    // MARK: Layouts

    @ViewBuilder private func layoutsSection(_ c: LayoutsController) -> some View {
        let full = layouts.value.layouts.count >= LayoutPresetModel.maxLayouts
        Section {
            if layouts.value.layouts.isEmpty {
                EmptyListView(L("No Saved Layouts"), symbol: SavedLayoutsPage.symbol,
                              text: L("Save your current arrangement to restore it later."),
                              action: StatusAction(title: L("Save Current Layout…")) { saving = true })
            } else {
                ReorderableList(itemsBinding, onEdit: { showDetails($0) }, onDelete: nil) { item in
                    LayoutRow(layout: item.layout, controller: c) {
                        showDetails(item)
                    }
                    .modifier(OptionalSettingsAnchor(index(of: item.id) == 0 ? ControlID("displays.layouts.list") : nil))
                }
                ButtonRow(L("Save Current Layout…"), control: ControlID("displays.layouts.save")) {
                    saving = true
                }
                .disabled(full)
            }
        } header: {
            Text(L("Layouts"))
        } footer: {
            if full {
                Text(L("You can save up to \(LayoutPresetModel.maxLayouts) layouts."))
            } else if !layouts.value.layouts.isEmpty {
                Text(L("The first nine are Layout 1–9 in Keyboard Shortcuts. Drag to reorder."))
            }
        }
    }

    /// Details… goes through the shell like every sheet (one sheet at a time, search reveals into it).
    private var detailsBinding: Binding<Bool> {
        let sheet = shell.sheetBinding(SavedLayoutsPageControls.detailsSheet)
        return Binding(get: { sheet.wrappedValue }, set: { open in
            sheet.wrappedValue = open
            if !open { details = nil }
        })
    }

    private func showDetails(_ item: LayoutItem) {
        details = item
        shell.openSheet = SavedLayoutsPageControls.detailsSheet
    }

    private var itemsBinding: Binding<[LayoutItem]> {
        let config = env.config
        return Binding(get: { config.value.layouts.layouts.map(LayoutItem.init) }, set: { items in
            let next = ListReorder.reordered(config.value.layouts.layouts, id: \.id, order: items.map(\.id))
            if next.map(\.id) != config.value.layouts.layouts.map(\.id) { config.value.layouts.layouts = next }
        })
    }

    private func index(of id: StableID) -> Int {
        layouts.value.layouts.firstIndex { $0.id == id } ?? 0
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        _ = controller?.captureCurrent(name: name.isEmpty ? nil : name)
    }

    // MARK: Protection

    @ViewBuilder private var protectionSection: some View {
        if let c = env.context?.connectPlanner.protection {
            let reason: String? = {
                if case .unavailable(let why)? = runtime.availability[.protection] { return why }
                return env.context?.otherApps.pauseReason(for: .protection)
            }()
            Section {
                ToggleSetting(L("Protect the current arrangement"),
                              help: L("Puts these displays back the way they are when macOS or another app changes them."),
                              isOn: Binding(get: { runtime.isEffective(.protection) && c.isProtectingCurrent },
                                            set: { on in setProtected(on, controller: c) }),
                              anchor: ControlID("displays.layouts.protect"),
                              disabledReason: reason)
                if runtime.isEffective(.protection), c.isProtectingCurrent, c.isPaused {
                    SettingsRowNote(L("Paused: macOS kept changing this arrangement. Change it in Snaptic to protect it again."))
                }
            }
        }
    }

    /// On: turns the `protection` feature on when needed, then records the current arrangement as protected (on the
    /// next turn, once the controller runs the feature). Off: forgets the protected state for these displays only.
    private func setProtected(_ on: Bool, controller c: ProtectionController) {
        guard on else {
            c.removeCurrent()
            return
        }
        if runtime.isEffective(.protection) {
            c.captureCurrent()
            return
        }
        switcher.binding([.protection], title: L("Protect the current arrangement")).wrappedValue = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated { c.captureCurrent() }
        }
    }
}

/// One layout: name and status, Apply and Details….
private struct LayoutRow: View {
    let layout: SavedLayout
    let controller: LayoutsController
    let showDetails: () -> Void

    var body: some View {
        let match = controller.matches(layout)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name)
                Text(LayoutsText.status(match: match, trusted: controller.isTrusted(layout), autoApply: layout.autoApply))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if match != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(L("Matches the connected displays"))
                    .accessibilityHidden(true)
            }
            Button(L("Apply")) { controller.apply(layout.id) }
                .disabled(match == nil)
                .help(match == nil ? L("Connect the displays this layout was saved with.") : "")
                .accessibilityLabel(L("Apply \(layout.name)"))
            Button(L("Details…"), action: showDetails)
                .accessibilityLabel(L("Details for \(layout.name)"))
        }
    }
}

enum LayoutsText {
    static func status(match: LayoutMatch?, trusted: Bool, autoApply: LayoutAutoApply) -> String {
        var parts: [String] = []
        if let match {
            parts.append(match.exact ? L("Matches") : L("Matches, with more displays connected"))
        } else {
            parts.append(L("Other displays"))
        }
        switch autoApply {
        case .never: break
        case .whenExactly, .whenIncludes:
            parts.append(trusted ? L("Applies automatically") : L("Applies automatically after you keep it once"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Details… sheet

private struct LayoutDetailsSheet: View {
    typealias Controls = SavedLayoutsPageControls

    let env: DisplaysPageEnvironment
    let id: StableID
    @ObservedObject private var revision: ControllerRevision
    @StateObject private var layouts: ConfigSlice<DisplaysConfig, LayoutsConfig>
    @State private var name = ""

    init(env: DisplaysPageEnvironment, id: StableID) {
        self.env = env
        self.id = id
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.layouts))
        _layouts = StateObject(wrappedValue: ConfigSlice(env.config, \.layouts))
    }

    private var controller: LayoutsController? { env.context?.connectPlanner.layouts }
    private var layout: SavedLayout? { layouts.value.layout(id) }

    var body: some View {
        AdvancedSheet(layout?.name ?? L("Layout"), restoreDefaults: deleteButton,
                      restoreControl: ControlID("displays.layouts.details.delete")) {
            if let layout, let c = controller {
                content(layout, c)
            } else {
                Section {
                    StatusRow(L("This layout isn’t there anymore."))
                }
            }
        }
        .onAppear { name = layout?.name ?? "" }
        .onDisappear { commitName() }
    }

    /// The sheet's leading footer button: Delete Layout… with its confirmation.
    private var deleteButton: RestoreDefaults? {
        guard let layout, let c = controller else { return nil }
        let id = id
        return RestoreDefaults(title: L("Delete Layout…"), question: L("Delete “\(layout.name)”?"),
                               message: L("Its shortcut and menu item go away too."), button: L("Delete"),
                               destructive: true) {
            c.delete(id)
        }
    }

    @ViewBuilder private func content(_ layout: SavedLayout, _ c: LayoutsController) -> some View {
        let match = c.matches(layout)
        let trusted = c.isTrusted(layout)
        Section {
            SettingRow(L("Name"), anchor: ControlID("displays.layouts.details.name")) {
                TextField(L("Name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    .onSubmit { commitName() }
            }
            LabeledContent(L("Status")) {
                Text(LayoutsText.status(match: match, trusted: trusted, autoApply: layout.autoApply))
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            PickerSetting(L("Apply automatically"),
                          help: L("Only after you’ve applied it once and kept it."),
                          selection: Binding(get: { layout.autoApply }, set: { v in c.edit(id) { $0.autoApply = v } }),
                          options: [
                              PickerOption(LayoutAutoApply.never, L("Never")),
                              PickerOption(LayoutAutoApply.whenExactly, L("When Exactly These Displays Are Connected")),
                              PickerOption(LayoutAutoApply.whenIncludes, L("When These Displays Are Connected")),
                          ],
                          style: .popUp, defaultValue: LayoutAutoApply.never,
                          anchor: ControlID("displays.layouts.details.autoApply"))
            StepperSetting(L("Priority"),
                           help: L("When several layouts match, the highest priority applies."),
                           value: Binding(get: { layout.priority }, set: { v in c.edit(id) { $0.priority = v } }),
                           in: -100...100, defaultValue: 0, format: .plain(digits: 0),
                           anchor: ControlID("displays.layouts.details.priority"))
        }
        Section {
            if trusted {
                ButtonRow(L("Stop Trusting"),
                          help: L("It won’t apply automatically until you apply and keep it again."),
                          control: ControlID("displays.layouts.details.stopTrusting")) {
                    c.untrust(id)
                }
            }
            ButtonRow(L("Update to Current"),
                      help: match == nil ? L("Connect the displays this layout was saved with.")
                                         : L("Saves the current arrangement into this layout."),
                      control: ControlID("displays.layouts.details.update")) {
                update(c)
            }
            .disabled(match == nil)
        } footer: {
            Text(L("Trust checks that the layout hasn’t changed and the displays are the same ones, by serial number. It isn’t a password."))
        }
    }

    private func commitName() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let layout, clean != layout.name else { return }
        // Renaming doesn't change content, so trust stays.
        controller?.edit(id) { $0.name = clean }
    }

    /// Re-captures the layout's content from the current state (clears trust).
    private func update(_ c: LayoutsController) {
        guard let layout, let fresh = c.captureCurrent(name: layout.name) else { return }
        c.edit(id) { l in
            l.displays = fresh.displays
            l.virtualScreens = fresh.virtualScreens
        }
        c.delete(fresh.id)
    }
}

// MARK: - Advanced sheet

private struct SavedLayoutsAdvancedSheet: View {
    typealias Controls = SavedLayoutsPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var protectionRevision: ControllerRevision
    @StateObject private var management: ConfigSlice<DisplaysConfig, ManagementConfig>
    @State private var confirmForget = false

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _protectionRevision = ObservedObject(wrappedValue: env.runtime.revision(.protection))
        _management = StateObject(wrappedValue: ConfigSlice(env.config, \.management))
    }

    var body: some View {
        AdvancedSheet(L("Saved Layouts Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("displays.layouts.advanced.restore")) {
            Section {
                field(L("Resolution and refresh rate"), \.mode, feature: .resolution,
                      anchor: ControlID("displays.layouts.advanced.fieldMode"))
                field(L("Position"), \.origin, feature: .arrangement,
                      anchor: ControlID("displays.layouts.advanced.fieldPosition"))
                field(L("Main display"), \.main, feature: .mainDisplay,
                      anchor: ControlID("displays.layouts.advanced.fieldMain"))
                field(L("Mirroring"), \.mirror, feature: .mirroring,
                      anchor: ControlID("displays.layouts.advanced.fieldMirroring"))
                field(L("Rotation"), \.rotation, feature: .rotation,
                      anchor: ControlID("displays.layouts.advanced.fieldRotation"))
                if let c = env.context?.connectPlanner.protection {
                    ButtonRow(L("Update Protected State to Current"),
                              help: L("Saves the arrangement as it is now as the one to protect."),
                              control: ControlID("displays.layouts.advanced.updateProtected")) {
                        c.captureCurrent()
                    }
                    .disabled(!runtime.isEffective(.protection) || !c.isProtectingCurrent)
                }
                ButtonRow(L("Forget All…"),
                          help: management.value.protection.values.isEmpty
                              ? L("No arrangements are protected.")
                              : L("Protected display sets: \(management.value.protection.values.count)"),
                          control: ControlID("displays.layouts.advanced.forgetAll")) {
                    confirmForget = true
                }
                .disabled(management.value.protection.values.isEmpty)
            } header: {
                Text(L("Protect"))
            } footer: {
                Text(L("What “Protect the current arrangement” puts back. A setting whose feature is off is skipped."))
            }
            Section {
                ToggleSetting(L("Offer Undo after an automatic apply"),
                              help: L("A notice with Undo appears when a layout applies by itself."),
                              isOn: SettingsBinding.store(env.config, \.layouts.undoToast),
                              anchor: ControlID("displays.layouts.advanced.undoToast"))
            } header: {
                Text(L("Saved layouts"))
            }
        }
        .alert(L("Forget all protected arrangements?"), isPresented: $confirmForget) {
            Button(L("Forget All"), role: .destructive) {
                env.config.value.management.protection = LossyMap()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Snaptic stops putting these display sets back. Your saved layouts stay."))
        }
    }

    private func field(_ title: String, _ path: WritableKeyPath<ProtectedFields, Bool>, feature: DisplayFeature,
                       anchor: ControlID) -> some View {
        ToggleSetting(title, isOn: SettingsBinding.store(env.config, (\DisplaysConfig.management.protectionFields).appending(path: path)),
                      anchor: anchor,
                      disabledReason: runtime.isEffective(feature) ? nil : DisplaysUIText.skippedWhileOff(feature))
    }

    /// Protected fields and the undo notice back to their defaults; saved layouts and protected sets stay.
    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(scopeName: L("Saved Layouts"), destructive: false) {
            var value = config.value
            value.management.protectionFields = ManagementConfig().protectionFields
            value.layouts.undoToast = LayoutsConfig().undoToast
            if value != config.value { config.value = value }
        }
    }
}
