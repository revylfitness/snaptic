import Foundation
import SwiftUI
import SnapticKit

/// Displays › **Virtual Displays** (owner D; PLAN 0.3 §4.3 sub-page table): header switch "Virtual displays"
/// (`virtualScreens`, Beta), the list (Connected switch, Details…; drag or ▲▼ to reorder, which sets Virtual
/// Display 1–8 in Keyboard Shortcuts), New Virtual Display… and **Sharper text on this display** (Smart HiDPI, Beta,
/// per external display). Advanced: the Sharper text switch (`smartHiDPI`), its size and HDR per display, the three
/// behavior switches, All Virtual Displays ▾, and HDR virtual modes (Experimental `hdrVirtual`). Details… and New
/// Virtual Display… open `VirtualDisplayEditorSheet`.
///
/// Live updates (§4.5): connection state follows `revision(.virtual)`, Sharper text `revision(.smartHiDPI)`.
struct VirtualDisplaysPage: View, ControlDeclaring {
    typealias Controls = VirtualDisplaysPageControls

    private let env: DisplaysPageEnvironment?

    init() {
        env = DisplaysSettingsLookup.environment()
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env {
            VirtualDisplaysContent(env: env)
        } else {
            UnavailablePage()
        }
    }

    static let title = L("Virtual Displays")
    static let summary = L("Create displays that exist only in software.")
    static let symbol = "display.2"
}

/// A virtual display as a list item.
private struct VirtualItem: Identifiable {
    let spec: VirtualScreenSpec
    var id: StableID { spec.id }
}

enum VirtualDisplaysText {
    static func bytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .memory)
    }

    /// "16:10 · 27 in · HiDPI · 12 sizes".
    static func summary(_ spec: VirtualScreenSpec) -> String {
        var parts = ["\(spec.aspectWidth):\(spec.aspectHeight)", L("\(Self.inches(spec.sizeInches)) in"),
                     spec.hiDPI ? L("HiDPI") : L("Standard"),
                     spec.modes.count == 1 ? L("1 size") : L("\(spec.modes.count) sizes")]
        if spec.headlessPrimary { parts.append(L("Headless")) }
        if !spec.associations.isEmpty {
            parts.append(spec.associations.count == 1 ? L("1 display linked") : L("\(spec.associations.count) displays linked"))
        }
        return parts.joined(separator: " · ")
    }

    static func inches(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

private struct VirtualDisplaysContent: View {
    typealias Controls = VirtualDisplaysPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var virtualRevision: ControllerRevision
    @ObservedObject private var smartRevision: ControllerRevision
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var virtual: ConfigSlice<DisplaysConfig, VirtualConfig>
    /// What the editor sheet edits; nil = the first virtual display (a search result opens the sheet by id).
    @State private var editorTarget: VirtualEditorTarget?

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _virtualRevision = ObservedObject(wrappedValue: env.runtime.revision(.virtual))
        _smartRevision = ObservedObject(wrappedValue: env.runtime.revision(.smartHiDPI))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _virtual = StateObject(wrappedValue: ConfigSlice(env.config, \.virtualScreens))
    }

    private static let route = SettingsRoute(VirtualDisplaysPageControls.surface)
    private var controller: VirtualController? { env.context?.connectPlanner.virtual }

    var body: some View {
        SettingsPageScaffold(route: Self.route) {
            SettingsPageHeader(VirtualDisplaysPage.title, summary: VirtualDisplaysPage.summary,
                               symbol: VirtualDisplaysPage.symbol, tint: .teal,
                               isOn: switcher.binding([.virtualScreens], title: L("Virtual displays")),
                               switchLabel: L("Virtual displays"), badge: .beta,
                               control: ControlID("displays.virtual.enabled"))
            if env.context == nil {
                Section {
                    StatusRow(L("Turn on Displays to use virtual displays."))
                }
            } else if let reason = unavailable(.virtualScreens) {
                Section {
                    StatusRow(reason, style: .warning)
                }
            } else if runtime.isEffective(.virtualScreens), let c = controller {
                listSection(c)
                sharperTextSection
            } else {
                FeatureHighlights([
                    FeatureHighlight(id: "virtual.create", symbol: "display.2", title: L("Displays in software"),
                                     text: L("Extra desktops for screen sharing, recording, or a Mac without a monitor.")),
                    FeatureHighlight(id: "virtual.sharper", symbol: "textformat.size", title: L("Sharper text"),
                                     text: L("Renders an external display at twice the size, like a Retina display.")),
                ])
            }
            PageFooterButtons(advanced: { shell.openSheet = VirtualDisplaysPageControls.advancedSheet }, help: Self.route,
                              advancedControl: ControlID("displays.virtual.advanced"))
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
        .sheet(isPresented: shell.sheetBinding(VirtualDisplaysPageControls.advancedSheet)) {
            VirtualDisplaysAdvancedSheet(env: env)
        }
        .sheet(isPresented: editorBinding) {
            VirtualDisplayEditorSheet(env: env, target: resolvedTarget)
        }
    }

    private func unavailable(_ feature: DisplayFeature) -> String? {
        if case .unavailable(let reason)? = runtime.availability[feature] { return reason }
        if runtime.isEffective(feature) { return nil }
        guard FeatureGraph.rawState(feature, in: env.config.value.rawFeatures) else { return nil }
        return env.context?.otherApps.pauseReason(for: feature)
    }

    // MARK: Editor sheet (Details… and New Virtual Display…; search opens it by its sheet id)

    private var editorBinding: Binding<Bool> {
        let sheet = shell.sheetBinding(VirtualDisplayEditorSheetControls.sheet)
        return Binding(get: { sheet.wrappedValue }, set: { open in
            sheet.wrappedValue = open
            if !open { editorTarget = nil }
        })
    }

    private func openEditor(_ target: VirtualEditorTarget) {
        editorTarget = target
        shell.openSheet = VirtualDisplayEditorSheetControls.sheet
    }

    private var resolvedTarget: VirtualEditorTarget {
        if let editorTarget { return editorTarget }
        return virtual.value.screens.first.map { .edit($0.id) } ?? .new
    }

    // MARK: List

    @ViewBuilder private func listSection(_ c: VirtualController) -> some View {
        let screens = virtual.value.screens
        let full = screens.count >= VirtualConfig.maxScreens
        Section {
            if screens.isEmpty {
                EmptyListView(L("No Virtual Displays"), symbol: VirtualDisplaysPage.symbol,
                              text: L("Create a display that exists only in software."),
                              action: StatusAction(title: L("New Virtual Display…")) { openEditor(.new) })
            } else {
                ReorderableList(itemsBinding, onEdit: { openEditor(.edit($0.id)) }, onDelete: nil) { item in
                    VirtualDisplayRow(spec: item.spec, controller: c, revision: virtualRevision) {
                        openEditor(.edit(item.id))
                    }
                    .modifier(OptionalSettingsAnchor(item.id == screens.first?.id ? ControlID("displays.virtual.list") : nil))
                }
                ButtonRow(L("New Virtual Display…"), control: ControlID("displays.virtual.new")) {
                    openEditor(.new)
                }
                .disabled(full)
            }
        } footer: {
            if let ctx = env.context, !screens.isEmpty {
                let budget = SoCCaps.maxBackingBytes(ram: ManagedHardware.ram)
                Text(L("Graphics memory in use: \(VirtualDisplaysText.bytes(ctx.virtualHosts.totalBackingBytes)) of \(VirtualDisplaysText.bytes(budget)). Up to \(VirtualConfig.maxScreens) virtual displays."))
            }
        }
    }

    private var itemsBinding: Binding<[VirtualItem]> {
        let config = env.config
        return Binding(get: { config.value.virtualScreens.screens.map(VirtualItem.init) }, set: { items in
            let current = config.value.virtualScreens.screens
            let next = ListReorder.reordered(current, id: \.id, order: items.map(\.id))
            if next.map(\.id) != current.map(\.id) { config.value.virtualScreens.screens = next }
        })
    }

    // MARK: Sharper text (Smart HiDPI)

    /// External displays (and any display that has it on, so it can be turned off).
    @ViewBuilder private var sharperTextSection: some View {
        if runtime.isEffective(.smartHiDPI), let c = env.context?.connectPlanner.smartHiDPI {
            let displays = runtime.displays.filter {
                ($0.transport == .wired && !$0.isSmartHiDPIPair) || c.isActive($0.key)
            }
            if !displays.isEmpty {
                Section {
                    ForEach(displays, id: \.key) { d in
                        ToggleSetting(displays.count == 1 ? L("Sharper text on this display")
                                                          : L("Sharper text on \(d.name)"),
                                      help: L("Renders \(d.name) at twice the size and scales it down, like a Retina display."),
                                      isOn: Binding(get: { c.isActive(d.key) }, set: { on in
                                          if on != c.isActive(d.key) { c.toggle(d.key) }
                                      }),
                                      anchor: d.key == displays.first?.key ? ControlID("displays.virtual.sharperText") : nil,
                                      badge: .beta,
                                      disabledReason: c.isBusy(d.key) ? L("Changing…") : nil)
                    }
                } footer: {
                    if let error = c.lastError {
                        Text(error)
                    } else {
                        Text(L("Turning it on is a trial. It costs graphics memory and GPU time, and protected video can’t play on it."))
                    }
                }
            }
        }
    }
}

/// One virtual display: name and summary, Connected, Details….
private struct VirtualDisplayRow: View {
    let spec: VirtualScreenSpec
    let controller: VirtualController
    @ObservedObject var revision: ControllerRevision
    let showDetails: () -> Void

    var body: some View {
        let live = controller.isLive(spec.id)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name)
                Text(VirtualDisplaysText.summary(spec))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Toggle(L("Connected"), isOn: Binding(get: { live }, set: { on in
                if on != controller.isLive(spec.id) { controller.toggle(spec.id) }
            }))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(controller.isBusy(spec.id))
            .help(live ? L("Connected") : L("Not connected"))
            .accessibilityLabel(L("\(spec.name) connected"))
            Button(L("Details…"), action: showDetails)
                .accessibilityLabel(L("Details for \(spec.name)"))
        }
    }
}

// MARK: - Advanced sheet

private struct VirtualDisplaysAdvancedSheet: View {
    typealias Controls = VirtualDisplaysPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var smartRevision: ControllerRevision
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var virtual: ConfigSlice<DisplaysConfig, VirtualConfig>
    @State private var confirmDiscard = false

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _smartRevision = ObservedObject(wrappedValue: env.runtime.revision(.smartHiDPI))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _virtual = StateObject(wrappedValue: ConfigSlice(env.config, \.virtualScreens))
    }

    var body: some View {
        AdvancedSheet(L("Virtual Displays Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("displays.virtual.advanced.restore")) {
            sharperText
            Section {
                ToggleSetting(L("Restore the arrangement after a virtual display connects"),
                              help: L("Puts every display back where it was before the virtual display appeared."),
                              isOn: SettingsBinding.store(env.config, \.virtualScreens.restoreLayoutAfterConnect),
                              anchor: ControlID("displays.virtual.advanced.restoreLayout"))
                ToggleSetting(L("Reconnect after wake"),
                              help: L("Virtual displays that were connected come back when your Mac wakes."),
                              isOn: SettingsBinding.store(env.config, \.virtualScreens.reconnectAfterWake),
                              anchor: ControlID("displays.virtual.advanced.reconnectAfterWake"))
                ToggleSetting(L("Disconnect while the screen is locked"),
                              help: L("Reconnects them when you unlock."),
                              isOn: SettingsBinding.store(env.config, \.virtualScreens.disconnectOnLock),
                              anchor: ControlID("displays.virtual.advanced.disconnectOnLock"))
                if let c = env.context?.connectPlanner.virtual {
                    LabeledContent {
                        ActionMenuButton(L("All Virtual Displays"), items: bulkItems(c), primaryAction: nil,
                                         control: ControlID("displays.virtual.advanced.bulk"))
                            .fixedSize()
                            .disabled(virtual.value.screens.isEmpty)
                    } label: {
                        Text(L("Every virtual display at once"))
                    }
                }
            } header: {
                Text(L("Virtual displays"))
            }
            Section {
                ToggleSetting(L("HDR virtual modes"),
                              help: L("Offers HDR (PQ) modes on virtual displays and Sharper text."),
                              isOn: switcher.binding([.hdrVirtual], title: L("HDR virtual modes")),
                              anchor: ControlID("displays.virtual.advanced.hdr"), badge: .experimental,
                              disabledReason: switcher.unavailableReason([.hdrVirtual]))
            } header: {
                Text(L("Experimental"))
            }
            if let ctx = env.context, ctx.virtualHosts.hostCount > 0 {
                Section {
                    StatusRow(L("\(ctx.virtualHosts.hostCount) helper processes use \(VirtualDisplaysText.bytes(ctx.virtualHosts.totalHostFootprint)) of memory."))
                }
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
        .alert(L("Discard all virtual displays?"), isPresented: $confirmDiscard) {
            Button(L("Discard All"), role: .destructive) { env.context?.connectPlanner.virtual?.discardAll() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("They disconnect and their settings are deleted."))
        }
    }

    @ViewBuilder private var sharperText: some View {
        Section {
            ToggleSetting(L("Sharper text"),
                          help: L("Offers Sharper text for external displays on the Virtual Displays page."),
                          isOn: switcher.binding([.smartHiDPI], title: L("Sharper text")),
                          anchor: ControlID("displays.virtual.advanced.sharperText"), badge: .beta,
                          disabledReason: switcher.unavailableReason([.smartHiDPI]))
            if runtime.isEffective(.smartHiDPI), let c = env.context?.connectPlanner.smartHiDPI {
                let keys = c.pairs.keys.sorted { $0.rawValue < $1.rawValue }
                ForEach(keys, id: \.self) { key in
                    if let pair = c.pairs[key] {
                        pairRows(key, pair: pair, controller: c, first: key == keys.first)
                    }
                }
            }
        } header: {
            Text(L("Sharper text"))
        }
    }

    @ViewBuilder private func pairRows(_ key: DisplayKey, pair: SmartHiDPIPair, controller c: SmartHiDPIController,
                                       first: Bool) -> some View {
        let options = c.modeOptions(key)
        let name = DisplaysSettingsLookup.name(key, env: env)
        PickerSetting(L("Size on \(name)"),
                      help: pair.limitToInitial ? L("Only the first size: the HiDPI check failed once.") : nil,
                      selection: Binding(get: { pair.mode }, set: { c.setMode(key, $0) }),
                      options: (options.contains(pair.mode) ? options : options + [pair.mode]).map { PickerOption($0, $0.label) },
                      style: .popUp, defaultValue: nil,
                      anchor: first ? ControlID("displays.virtual.advanced.size") : nil, subordinate: true)
        if runtime.isEffective(.hdrVirtual) {
            ToggleSetting(L("HDR (PQ) on \(name)"),
                          isOn: Binding(get: { pair.hdr }, set: { on in
                              guard var p = env.config.value.virtualScreens.smartHiDPI[key], p.hdr != on else { return }
                              p.hdr = on
                              env.config.value.virtualScreens.smartHiDPI[key] = p
                          }),
                          subordinate: true,
                          anchor: first ? ControlID("displays.virtual.advanced.smartHDR") : nil)
        }
    }

    private func bulkItems(_ c: VirtualController) -> [ActionMenuItem] {
        [
            ActionMenuItem(id: "connect", title: L("Connect All")) { c.connectAll() },
            ActionMenuItem(id: "disconnect", title: L("Disconnect All")) { c.disconnectAll() },
            ActionMenuItem(id: "reconnect", title: L("Reconnect All")) { c.reconnectAll() },
            ActionMenuItem(id: "disassociate", title: L("Unlink All")) { c.disassociateAll() },
            .separator("discardSeparator"),
            ActionMenuItem(id: "discard", title: L("Discard All…")) { confirmDiscard = true },
        ]
    }

    /// The behavior switches back to their defaults; virtual displays and Sharper text stay.
    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(scopeName: L("Virtual Displays"), destructive: false) {
            let defaults = VirtualConfig()
            var value = config.value
            value.virtualScreens.restoreLayoutAfterConnect = defaults.restoreLayoutAfterConnect
            value.virtualScreens.reconnectAfterWake = defaults.reconnectAfterWake
            value.virtualScreens.disconnectOnLock = defaults.disconnectOnLock
            if value != config.value { config.value = value }
        }
    }
}
