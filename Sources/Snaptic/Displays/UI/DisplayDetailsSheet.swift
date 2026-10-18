import AppKit
import SwiftUI
import SnapticKit

/// Display Details… (owner F; PLAN 0.3 §4.3): the selected display's name and icon, a link to its menu visibility
/// (Menu Bar › Customize Displays Menu), its manage actions (Copy Settings From ▾, Forget Remembered Resolution,
/// Forget This Display…) and an Information disclosure (connection, masked serial, EDID copies). Never presents
/// another sheet; Forget asks with a standard alert. The owners' Connection, Menu bar overlays and Match text size
/// groups join in step 3.
struct DisplayDetailsSheet: View, ControlDeclaring {
    typealias Controls = DisplayDetailsSheetControls

    let env: DisplaysPageEnvironment
    let key: DisplayKey?
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false

    init(env: DisplaysPageEnvironment, key: DisplayKey?) {
        self.env = env
        self.key = key
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
    }

    private var display: DisplayInfo? { runtime.displays.first { $0.key == key } }

    var body: some View {
        AdvancedSheet(display?.name ?? L("Display Details"), restoreDefaults: nil) {
            if let display {
                identity(display)
                manage(display)
                information(display)
            } else {
                Section {
                    StatusRow(L("This display isn’t connected anymore."))
                }
            }
        }
        .alert(L("Forget “\(display?.name ?? "")”?"), isPresented: $confirmForget) {
            Button(L("Forget"), role: .destructive) { forgetDisplay() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Snaptic removes this display’s brightness, color, resolution, and menu settings. It starts with the defaults the next time it connects."))
        }
    }

    // MARK: Identity

    @ViewBuilder private func identity(_ display: DisplayInfo) -> some View {
        Section {
            DisplayNameRow(display: display, config: env.config, identity: identity(of: display.key))
            PickerSetting(L("Icon"), help: L("Shown in the menu, the Displays panel, and Settings."),
                          selection: symbolBinding(display), options: symbolOptions(display), style: .popUp,
                          defaultValue: "", anchor: ControlID("displays.details.icon"))
            LabeledContent {
                Button(L("Customize Displays Menu…")) { openCustomizeMenu(display.key) }
                    .modifier(SettingsAnchor(ControlID("displays.details.customizeMenu")))
            } label: {
                Text(L("Show in the menu"))
                Text(L("Whether and where this display appears in the menu is set on the Menu Bar page."))
            }
        }
    }

    private func identity(of key: DisplayKey) -> PerDisplayIdentity {
        perDisplay.value[key]?.identity ?? PerDisplayIdentity()
    }

    /// "" = Automatic (by connection).
    private func symbolBinding(_ display: DisplayInfo) -> Binding<String> {
        let config = env.config
        let key = display.key
        return Binding(get: { config.value.perDisplay[key]?.identity.symbol ?? "" }, set: { symbol in
            var value = config.value
            var entry = value.perDisplay[key] ?? PerDisplayConfig()
            let chosen: String? = symbol.isEmpty ? nil : symbol
            guard entry.identity.symbol != chosen else { return }
            entry.identity.symbol = chosen
            value.perDisplay[key] = entry
            config.value = value
        })
    }

    private func symbolOptions(_ display: DisplayInfo) -> [PickerOption<String>] {
        var options = [PickerOption("", L("Automatic"), symbol: DisplaysLive.automaticSymbol(for: display))]
        options += DisplaysUIText.displaySymbols.map { PickerOption($0.symbol, $0.title, symbol: $0.symbol) }
        // A symbol set elsewhere (an imported configuration) stays selectable.
        if let other = identity(of: display.key).symbol, !DisplaysUIText.isCuratedSymbol(other) {
            options.append(PickerOption(other, other, symbol: other))
        }
        return options
    }

    /// Closes the sheet, then shows Menu Bar › Customize Displays Menu with this display selected (parity M6).
    private func openCustomizeMenu(_ key: DisplayKey) {
        dismiss()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let shell = SettingsShell.shared
                shell.selectedDisplay = key
                shell.go(to: SettingsLocation(root: SettingsRootID.menuBar))
                shell.openSheet = CustomizeMenuSheetControls.surface
            }
        }
    }

    // MARK: Manage

    @ViewBuilder private func manage(_ display: DisplayInfo) -> some View {
        let remembered = rememberedDisplays
        let persisted = perDisplay.value[display.key]?.resolution.persisted
        Section {
            if !remembered.isEmpty {
                LabeledContent {
                    ActionMenuButton(L("Choose Display"), items: remembered.map { source in
                        ActionMenuItem(id: source.rawValue, title: rememberedName(source)) {
                            copySettings(from: source, to: display.key)
                        }
                    }, primaryAction: nil, control: ControlID("displays.details.copySettings"))
                } label: {
                    Text(L("Copy settings from"))
                    Text(L("Uses a display Snaptic remembers for brightness, color, and resolution."))
                }
            }
            if let persisted {
                LabeledContent {
                    Button(L("Forget")) { forgetResolution(display.key) }
                        .modifier(SettingsAnchor(ControlID("displays.details.forgetResolution")))
                } label: {
                    Text(L("Remembered resolution"))
                    Text(L("Snaptic restores \(DisplaysUIText.modeLabel(persisted.mode)) when macOS doesn’t."))
                }
            }
            LabeledContent {
                Button(L("Forget This Display…"), role: .destructive) { confirmForget = true }
                    .modifier(SettingsAnchor(ControlID("displays.details.forget")))
            } label: {
                Text(L("Forget this display"))
                Text(L("Removes everything Snaptic remembers about it."))
            }
        }
    }

    /// Displays with saved settings that aren't connected now.
    private var rememberedDisplays: [DisplayKey] {
        let online = Set(runtime.displays.map(\.key))
        return perDisplay.value.values.keys.filter { !online.contains($0) }.sorted { $0.rawValue < $1.rawValue }
    }

    private func rememberedName(_ key: DisplayKey) -> String {
        let identity = identity(of: key)
        return identity.customName ?? identity.lastKnownName ?? L("Display \(DiagnosticsText.shortKey(key))")
    }

    /// Copies a remembered display's settings onto this one (keeping this display's own identity), then forgets the
    /// source.
    private func copySettings(from source: DisplayKey, to target: DisplayKey) {
        var value = env.config.value
        guard var copied = value.perDisplay[source] else { return }
        copied.identity = value.perDisplay[target]?.identity ?? PerDisplayIdentity()
        value.perDisplay[target] = copied
        value.perDisplay[source] = nil
        value.menu.forget(source)
        env.config.value = value
        EventLog.shared.record(.registry, "Copied a remembered display's settings")
    }

    private func forgetResolution(_ key: DisplayKey) {
        var value = env.config.value
        guard var entry = value.perDisplay[key], entry.resolution.persisted != nil else { return }
        entry.resolution.persisted = nil
        value.perDisplay[key] = entry
        env.config.value = value
    }

    private func forgetDisplay() {
        guard let key else { return }
        var value = env.config.value
        value.perDisplay[key] = nil
        value.menu.forget(key)
        env.config.value = value
        EventLog.shared.record(.registry, "Forgot a display")
        dismiss()
    }

    // MARK: Information

    private func information(_ display: DisplayInfo) -> some View {
        Section {
            DisplayInformationDisclosure(display: display, context: env.context)
                .modifier(SettingsAnchor(ControlID("displays.details.information")))
        }
    }
}

/// Name (field + Use the System Name). Empty = the system's name. The field is a draft that follows the stored
/// name whenever it changes elsewhere, and saves on Return or when it loses focus.
private struct DisplayNameRow: View {
    let display: DisplayInfo
    let config: ConfigStore<DisplaysConfig>
    let identity: PerDisplayIdentity
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var systemName: String { identity.lastKnownName ?? display.name }

    var body: some View {
        SettingRow(L("Name"), help: L("Shown in the menu, the Displays panel, and Settings."),
                   anchor: ControlID("displays.details.name")) {
            HStack(spacing: 8) {
                TextField(L("Name"), text: $draft, prompt: Text(systemName))
                    .labelsHidden()
                    .frame(width: 200)
                    .focused($focused)
                    .onSubmit { save() }
                    .accessibilityLabel(L("Name for \(systemName)"))
                if identity.customName != nil {
                    Button(L("Use the System Name")) {
                        draft = ""
                        save()
                    }
                }
            }
        }
        .onAppear { draft = identity.customName ?? "" }
        .onChange(of: identity.customName) { _, stored in
            if !focused { draft = stored ?? "" }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { save() }
        }
    }

    private func save() {
        let name = PerDisplayIdentity.cleanName(draft)
        guard name != identity.customName else { return }
        var value = config.value
        var entry = value.perDisplay[display.key] ?? PerDisplayConfig()
        entry.identity.customName = name
        value.perDisplay[display.key] = entry
        config.value = value
        draft = name ?? ""
        EventLog.shared.record(.registry, name == nil ? "Display name reset" : "Display renamed")
    }
}

/// Connection facts and the decoded EDID (read when expanded; the serial is masked), with Copy Hex / Copy Base64.
/// EDID bytes never go into the diagnostics report or the event log; exporting them lives on Display Information.
private struct DisplayInformationDisclosure: View {
    let display: DisplayInfo
    weak var context: DisplaysContext?
    @State private var expanded = false
    @State private var bytes: [UInt8]?
    @State private var loaded = false

    var body: some View {
        DisclosureGroup(L("Information"), isExpanded: $expanded) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, row in
                LabeledContent(row.label) { Text(row.value).textSelection(.enabled) }
            }
            if !loaded {
                ProgressView().controlSize(.small)
            } else if let bytes, !bytes.isEmpty {
                if let info = EDIDInfo.parse(bytes) {
                    ForEach(Array(EDIDText.summary(info, byteCount: bytes.count).enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.label) { Text(row.value).textSelection(.enabled) }
                    }
                } else {
                    Text(L("The EDID couldn’t be decoded (\(bytes.count) bytes)."))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L("Copy EDID as Hex")) { copy(EDIDText.hex(bytes)) }
                    Button(L("Copy EDID as Base64")) { copy(EDIDText.base64(bytes)) }
                }
            } else {
                Text(context == nil ? L("Turn on Displays to read the EDID.")
                                    : L("macOS doesn’t provide an EDID for this display."))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: expanded) { _, isExpanded in if isExpanded && !loaded { load() } }
        .onChange(of: display.hardwareID) { _, _ in
            loaded = false
            bytes = nil
            if expanded { load() }
        }
    }

    private var facts: [DiagnosticsRow] {
        var rows: [DiagnosticsRow] = [DiagnosticsRow(L("Connection"), Self.transportName(display.transport))]
        if let mode = display.currentMode {
            rows.append(DiagnosticsRow(L("Resolution"), DisplaysUIText.modeLabel(mode.ref)))
            rows.append(DiagnosticsRow(L("Pixels"), "\(mode.ref.pixelWidth) × \(mode.ref.pixelHeight)"))
        }
        if let inches = DisplaysUIText.diagonalInches(widthMM: display.physicalSizeMM.width,
                                                      heightMM: display.physicalSizeMM.height) {
            rows.append(DiagnosticsRow(L("Size"), String(format: L("%.1f-inch"), inches)))
        }
        if display.rotation != 0 { rows.append(DiagnosticsRow(L("Rotation"), "\(display.rotation)°")) }
        if let hdr = display.hdrSupported {
            rows.append(DiagnosticsRow(L("High Dynamic Range"),
                                       hdr ? (display.hdrEnabled == true ? L("On") : L("Off")) : L("Not supported")))
        }
        if display.edrPotential > 1 {
            rows.append(DiagnosticsRow(L("Extra brightness headroom"), String(format: "%.1f×", display.edrPotential)))
        }
        rows.append(DiagnosticsRow(L("Identifier"), DiagnosticsText.shortKey(display.key)))
        return rows
    }

    static func transportName(_ transport: Transport) -> String {
        switch transport {
        case .builtin: return L("Built-in")
        case .wired: return L("Cable")
        case .displayLink: return L("DisplayLink")
        case .airplay: return L("AirPlay")
        case .sidecar: return L("Sidecar")
        case .snapticVirtual: return L("Snaptic virtual display")
        case .foreignVirtual: return L("Virtual display (other app)")
        }
    }

    private func load() {
        guard let ctx = context else {
            loaded = true
            return
        }
        let info = ctx.privateAPI.function(.coreDisplayInfo, as: IORegistryDisplays.InfoDictionaryFn.self)
        let data = IORegistryDisplays.facts(for: display.hardwareID, coreDisplayInfo: info).edid
        bytes = data.map { [UInt8]($0.prefix(EDIDInfo.maxBytes)) }
        loaded = true
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
