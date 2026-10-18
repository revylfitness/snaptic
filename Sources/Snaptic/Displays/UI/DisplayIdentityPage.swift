import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

/// Display Names (PLAN §2.1 `overview`: identity, hide, order, forget / transfer /
/// forget-all): per-display info and EDID, menu visibility and order, name and icon, and the
/// displays Snaptic remembers settings for.
struct DisplayIdentityPage: View {
    @ObservedObject private var env: DisplaysPageEnvironment
    @State private var forgetting: DisplayKey?
    @State private var confirmForgetAll = false

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    private var connected: [DisplayInfo] {
        let all = env.runtime.displays
        let main = all.first(where: \.isMain)?.key
        let order = env.config.value.menu.orderedDisplays(all.map(\.key), main: main, includeHidden: true)
        return order.compactMap { key in all.first { $0.key == key } }
    }

    /// Displays with saved settings that aren't connected now.
    private var remembered: [DisplayKey] {
        let online = Set(env.runtime.displays.map(\.key))
        return env.config.value.perDisplay.values.keys.filter { !online.contains($0) }.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            if env.context == nil {
                Section {
                    Text(L("Turn on Displays to see connected displays. Remembered displays are listed below."))
                        .foregroundStyle(.secondary)
                }
            } else if connected.isEmpty {
                Section(L("Connected")) {
                    Text(L("No displays detected yet.")).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(connected.enumerated()), id: \.element.key) { index, display in
                Section {
                    connectedRow(display, index: index)
                } header: {
                    Text(L("Display \(index + 1)"))
                }
            }
            Section {
                if remembered.isEmpty {
                    Text(L("No other displays are remembered.")).foregroundStyle(.secondary)
                }
                ForEach(remembered, id: \.self) { key in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.rememberedName(key, config: env.config.value))
                            Text(L("Identifier \(DiagnosticsText.shortKey(key))"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Forget…")) { forgetting = key }
                            .accessibilityLabel(L("Forget \(Self.rememberedName(key, config: env.config.value))"))
                    }
                }
                if remembered.count > 1 {
                    Button(L("Forget All Disconnected Displays…"), role: .destructive) { confirmForgetAll = true }
                }
            } header: {
                Text(L("Remembered displays"))
            } footer: {
                Text(L("Snaptic keeps up to \(DisplaysConfig.maxRememberedDisplays) displays' settings. Forgetting removes a display's brightness, color, resolution and menu settings."))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("Forget this display?"), isPresented: Binding(get: { forgetting != nil },
                                                                           set: { if !$0 { forgetting = nil } })) {
            Button(L("Forget"), role: .destructive) {
                if let key = forgetting { forget(key) }
                forgetting = nil
            }
        } message: {
            Text(L("Its settings are removed. If it connects again it starts with the defaults."))
        }
        .confirmationDialog(L("Forget every disconnected display?"), isPresented: $confirmForgetAll) {
            Button(L("Forget All"), role: .destructive) { remembered.forEach(forget) }
        } message: {
            Text(L("\(remembered.count) displays' settings are removed."))
        }
    }

    @ViewBuilder
    private func connectedRow(_ display: DisplayInfo, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: DisplayMenuBlock.symbol(for: display, config: env.config.value))
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).font(.headline)
                HStack(spacing: 4) {
                    ForEach(badges(display), id: \.self) { DisplaysBadge(text: $0) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        NameField(display: display, config: env.config)
        SymbolPicker(display: display, config: env.config)
        Toggle(L("Show in the menu and the Displays panel"), isOn: Binding(
            get: { !env.config.value.menu.isHidden(display.key) },
            set: { env.config.value.menu.setHidden(!$0, for: display.key) }))
        HStack {
            Text(L("Menu order"))
            Spacer()
            Button { move(display.key, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
                .accessibilityLabel(L("Move \(display.name) up"))
            Button { move(display.key, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index >= connected.count - 1)
                .accessibilityLabel(L("Move \(display.name) down"))
        }
        if env.config.value.menu.mainFirst && display.isMain {
            Text(L("The main display is listed first (General → Menu)."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        DisclosureGroup(L("Details")) {
            ForEach(Self.details(display), id: \.label) { row in
                LabeledContent(row.label) { Text(row.value).textSelection(.enabled) }
            }
        }
        EDIDDisclosure(display: display, context: env.context)
        if !remembered.isEmpty {
            Menu(L("Copy Settings From…")) {
                ForEach(remembered, id: \.self) { source in
                    Button(Self.rememberedName(source, config: env.config.value)) { transfer(from: source, to: display.key) }
                }
            }
            .help(L("Use a remembered display's brightness, color and resolution settings for this display"))
        }
    }

    private func badges(_ display: DisplayInfo) -> [String] {
        guard let ctx = env.context else { return DisplayMenuBlock.badges(for: display, paused: false) }
        return DisplayMenuBlock.badges(for: display, context: ctx)
    }

    // MARK: Actions

    private func move(_ key: DisplayKey, by offset: Int) {
        env.config.value.menu.move(key, by: offset, in: connected.map(\.key))
    }

    private func forget(_ key: DisplayKey) {
        var value = env.config.value
        value.perDisplay[key] = nil
        value.menu.forget(key)
        env.config.value = value
        EventLog.shared.record(.registry, "Forgot a remembered display")
    }

    /// Copies a remembered display's settings onto a connected one (keeping the target's
    /// own identity section), then forgets the source.
    private func transfer(from source: DisplayKey, to target: DisplayKey) {
        var value = env.config.value
        guard var copied = value.perDisplay[source] else { return }
        copied.identity = value.perDisplay[target]?.identity ?? PerDisplayIdentity()
        value.perDisplay[target] = copied
        value.perDisplay[source] = nil
        value.menu.forget(source)
        env.config.value = value
        EventLog.shared.record(.registry, "Transferred a remembered display's settings")
    }

    // MARK: Text

    static func rememberedName(_ key: DisplayKey, config: DisplaysConfig) -> String {
        if let identity = config.perDisplay[key]?.identity, let name = DisplayNameFields.savedName(identity) { return name }
        return L("Display \(DiagnosticsText.shortKey(key))")
    }

    static func details(_ d: DisplayInfo) -> [DiagnosticsRow] {
        var rows: [DiagnosticsRow] = []
        rows.append(DiagnosticsRow(L("Connection"), transportName(d.transport)))
        if let mode = d.currentMode {
            rows.append(DiagnosticsRow(L("Resolution"), DisplaysUIText.modeLabel(mode.ref)))
            rows.append(DiagnosticsRow(L("Pixels"), "\(mode.ref.pixelWidth) × \(mode.ref.pixelHeight)"))
        }
        if let inches = DisplaysUIText.diagonalInches(widthMM: d.physicalSizeMM.width, heightMM: d.physicalSizeMM.height) {
            rows.append(DiagnosticsRow(L("Size"), String(format: L("%.1f-inch"), inches)))
        }
        if d.rotation != 0 { rows.append(DiagnosticsRow(L("Rotation"), "\(d.rotation)°")) }
        if let hdr = d.hdrSupported {
            rows.append(DiagnosticsRow(L("HDR"), hdr ? (d.hdrEnabled == true ? L("On") : L("Off")) : L("Not supported")))
        }
        if d.edrPotential > 1 { rows.append(DiagnosticsRow(L("Extra brightness headroom"), String(format: "%.1f×", d.edrPotential))) }
        rows.append(DiagnosticsRow(L("Built-in"), d.isBuiltin ? L("Yes") : L("No")))
        rows.append(DiagnosticsRow(L("Identifier"), DiagnosticsText.shortKey(d.key)))
        return rows
    }

    static func transportName(_ transport: Transport) -> String {
        switch transport {
        case .builtin: return L("Built-in")
        case .wired: return L("Cable")
        case .displayLink: return L("DisplayLink")
        case .airplay: return L("AirPlay")
        case .sidecar: return L("Sidecar")
        case .snapticVirtual: return L("Snaptic virtual screen")
        case .foreignVirtual: return L("Virtual screen (other app)")
        }
    }
}

/// Rename field: `PerDisplayIdentity.customName` (B's ConfigIdentity); the registry shows it
/// as the display's name everywhere. Empty = the system name (`lastKnownName`).
private struct NameField: View {
    let display: DisplayInfo
    @ObservedObject var config: ConfigStore<DisplaysConfig>
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(display: DisplayInfo, config: ConfigStore<DisplaysConfig>) {
        self.display = display
        _config = ObservedObject(wrappedValue: config)
    }

    var body: some View {
        TextField(L("Name"), text: $draft, prompt: Text(systemName))
            .focused($focused)
            .onAppear { draft = DisplayNameFields.customName(identity) ?? "" }
            .onSubmit { save() }
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
            .accessibilityLabel(L("Name for \(display.name)"))
        if DisplayNameFields.customName(identity) != nil {
            Button(L("Use the System Name")) {
                draft = ""
                save()
            }
        }
    }

    private var identity: PerDisplayIdentity { config.value.perDisplay[display.key]?.identity ?? PerDisplayIdentity() }

    /// What macOS calls the display (shown as the placeholder).
    private var systemName: String { identity.lastKnownName ?? display.name }

    private func save() {
        let name = PerDisplayIdentity.cleanName(draft)
        guard name != DisplayNameFields.customName(identity) else { return }
        var value = config.value
        var perDisplay = value.perDisplay[display.key] ?? PerDisplayConfig()
        DisplayNameFields.setCustomName(name, in: &perDisplay.identity)
        value.perDisplay[display.key] = perDisplay
        config.value = value
        draft = name ?? ""
        EventLog.shared.record(.registry, name == nil ? "Display name reset" : "Display renamed")
    }
}

/// The display's icon in the menu, the panel and these pages: a curated set of SF Symbols,
/// or Automatic (by connection type).
private struct SymbolPicker: View {
    let display: DisplayInfo
    @ObservedObject var config: ConfigStore<DisplaysConfig>

    init(display: DisplayInfo, config: ConfigStore<DisplaysConfig>) {
        self.display = display
        _config = ObservedObject(wrappedValue: config)
    }

    var body: some View {
        Picker(selection: Binding<String?>(
            get: { DisplayNameFields.symbol(config.value.perDisplay[display.key]?.identity ?? PerDisplayIdentity()) },
            set: { set($0) })) {
            Label(L("Automatic"), systemImage: DisplayMenuBlock.symbol(for: display)).tag(String?.none)
            Divider()
            ForEach(DisplaysUIText.displaySymbols, id: \.symbol) { entry in
                Label(entry.title, systemImage: entry.symbol).tag(Optional(entry.symbol))
            }
            // A symbol set elsewhere (an imported config) stays selectable.
            if let other = DisplayNameFields.symbol(config.value.perDisplay[display.key]?.identity ?? PerDisplayIdentity()),
               !DisplaysUIText.isCuratedSymbol(other) {
                Label(other, systemImage: other).tag(Optional(other))
            }
        } label: {
            Text(L("Icon"))
        }
        .pickerStyle(.menu)
        .accessibilityLabel(L("Icon for \(display.name)"))
    }

    private func set(_ symbol: String?) {
        var value = config.value
        var perDisplay = value.perDisplay[display.key] ?? PerDisplayConfig()
        guard perDisplay.identity.symbol != symbol else { return }
        perDisplay.identity.symbol = symbol
        value.perDisplay[display.key] = perDisplay
        config.value = value
    }
}

/// The one place that touches PerDisplayIdentity's name and icon fields (team B owns the type).
private enum DisplayNameFields {
    static func customName(_ identity: PerDisplayIdentity) -> String? { identity.customName }

    static func setCustomName(_ name: String?, in identity: inout PerDisplayIdentity) {
        identity.customName = PerDisplayIdentity.cleanName(name)
    }

    /// The name for a display that isn't connected: the user's name, else the last system name.
    static func savedName(_ identity: PerDisplayIdentity) -> String? { identity.customName ?? identity.lastKnownName }

    static func symbol(_ identity: PerDisplayIdentity) -> String? { identity.symbol }
}

// MARK: - EDID (parity: BetterDisplay's EDID view)

/// The display's EDID: decoded summary (Kit `EDIDInfo`), copy as hex or Base64, export
/// the raw bytes. Read on demand from B's `IORegistryDisplays` when expanded. EDID bytes
/// never go into the diagnostics report or the event log.
private struct EDIDDisclosure: View {
    let display: DisplayInfo
    weak var context: DisplaysContext?
    @State private var expanded = false
    @State private var bytes: [UInt8]?
    @State private var loaded = false

    var body: some View {
        DisclosureGroup(L("EDID"), isExpanded: $expanded) {
            if context == nil {
                Text(L("Turn on Displays to read the EDID.")).foregroundStyle(.secondary)
            } else if !loaded {
                ProgressView().controlSize(.small)
            } else if let bytes, !bytes.isEmpty {
                if let info = EDIDInfo.parse(bytes) {
                    ForEach(Array(EDIDText.summary(info, byteCount: bytes.count).enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.label) { Text(row.value).textSelection(.enabled) }
                    }
                } else {
                    Text(L("The EDID couldn't be decoded (\(bytes.count) bytes)."))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("Copy Hex")) { copy(EDIDText.hex(bytes)) }
                    Button(L("Copy Base64")) { copy(EDIDText.base64(bytes)) }
                    Spacer()
                    Button(L("Export .bin…")) { export(bytes) }
                }
            } else {
                Text(L("macOS doesn't expose an EDID for this display."))
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

    private func load() {
        guard let ctx = context else { return }
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

    private func export(_ bytes: [UInt8]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = EDIDText.exportFileName(displayName: display.name)
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.canCreateDirectories = true
        let data = Data(bytes)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                EventLog.shared.record(.registry, "EDID export failed")
            }
        }
    }
}
