import SwiftUI
import SnapticKit

/// Display Names (PLAN §2.1 `overview`: identity, hide, order, forget / transfer /
/// forget-all): per-display info, menu visibility and order, renaming, and the displays
/// Snaptic remembers settings for.
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
            Image(systemName: DisplayMenuBlock.symbol(for: display))
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).font(.headline)
                HStack(spacing: 4) {
                    ForEach(DisplayMenuBlock.badges(for: display, paused: false), id: \.self) { DisplaysBadge(text: $0) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        NameField(display: display, config: env.config)
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
        if !remembered.isEmpty {
            Menu(L("Copy Settings From…")) {
                ForEach(remembered, id: \.self) { source in
                    Button(Self.rememberedName(source, config: env.config.value)) { transfer(from: source, to: display.key) }
                }
            }
            .help(L("Use a remembered display's brightness, color and resolution settings for this display"))
        }
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

/// Rename field. Names are stored in PerDisplayIdentity (team B's ConfigIdentity) through
/// DisplayNameFields; until those fields exist the field is read-only and says so.
private struct NameField: View {
    let display: DisplayInfo
    @ObservedObject var config: ConfigStore<DisplaysConfig>
    @State private var draft = ""

    init(display: DisplayInfo, config: ConfigStore<DisplaysConfig>) {
        self.display = display
        _config = ObservedObject(wrappedValue: config)
    }

    var body: some View {
        if DisplayNameFields.isSupported {
            TextField(L("Name"), text: $draft, prompt: Text(display.name))
                .onAppear { draft = DisplayNameFields.customName(identity) ?? "" }
                .onSubmit { save() }
                .accessibilityLabel(L("Name for \(display.name)"))
            if DisplayNameFields.customName(identity) != nil {
                Button(L("Use the System Name")) {
                    draft = ""
                    save()
                }
            }
        } else {
            LabeledContent(L("Name"), value: display.name)
            Text(L("Renaming displays arrives with display identity support."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var identity: PerDisplayIdentity { config.value.perDisplay[display.key]?.identity ?? PerDisplayIdentity() }

    private func save() {
        let name = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(64))
        var value = config.value
        var perDisplay = value.perDisplay[display.key] ?? PerDisplayConfig()
        DisplayNameFields.setCustomName(name.isEmpty ? nil : name, in: &perDisplay.identity)
        value.perDisplay[display.key] = perDisplay
        config.value = value
    }
}

/// The one place that touches PerDisplayIdentity's name fields (team B owns the type).
/// B's ConfigIdentity needs: `customName: String?` (≤ 64 scalars, sanitized, applied by the
/// registry to DisplayInfo.name), `lastKnownName: String?` (the system name, written by the
/// registry, shown for remembered displays) and `symbol: String?` (SF Symbol for the menu).
/// When they land, set `isSupported` and the three accessors to use them.
private enum DisplayNameFields {
    static let isSupported = false
    static func customName(_ identity: PerDisplayIdentity) -> String? { nil }
    static func setCustomName(_ name: String?, in identity: inout PerDisplayIdentity) {}
    static func savedName(_ identity: PerDisplayIdentity) -> String? { nil }
}
