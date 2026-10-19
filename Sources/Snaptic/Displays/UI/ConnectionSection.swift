import SwiftUI
import SnapticKit

/// Display Details › **Connection** (owner D; PLAN 0.3 §4.3 Display Details, design M9): Disconnect / Connect
/// (`disconnect`), turning the built-in display off automatically (`autoDisconnectBuiltin`, Beta), "This display
/// doesn't support hardware controls" on an external display while that runs, and Underscan (Experimental
/// `underscan`; applies on release as a trial, so "Keep this change?" confirms it).
///
/// `ConnectionSection(env:key:)` is a section for F's Details sheet; it shows nothing when none of its rows applies.
/// `ConnectionSection()` is the `displays.connection` page (the menu's "Underscan…") for the selected display.
struct ConnectionSection: View, ControlDeclaring {
    typealias Controls = ConnectionSectionControls

    private let env: DisplaysPageEnvironment?
    private let key: DisplayKey?
    private let isPage: Bool

    init() {
        env = DisplaysSettingsLookup.environment()
        key = nil
        isPage = true
    }

    init(env: DisplaysPageEnvironment, key: DisplayKey) {
        self.env = env
        self.key = key
        isPage = false
    }

    var body: some View {
        if isPage {
            if let env {
                ConnectionPage(env: env)
            } else {
                UnavailablePage()
            }
        } else if let env, let key {
            ConnectionRows(env: env, key: key, showsEmpty: false)
        }
    }
}

/// The `displays.connection` page: display tiles and the rows for the selected display.
private struct ConnectionPage: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var shell: SettingsShell

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
    }

    private static let route = SettingsRoute(ConnectionSectionControls.surface)

    var body: some View {
        let displays = runtime.displays.filter(\.isOnline)
        let display = DisplaysSettingsLookup.selected(displays) { _ in true }
        SettingsPageScaffold(route: Self.route) {
            SettingsPageHeader(L("Connection"), summary: L("Disconnect, underscan, and automatic disconnection."),
                               symbol: "cable.connector", tint: .gray)
            if env.context == nil {
                Section {
                    StatusRow(L("Turn on Displays to change how displays connect."))
                }
            } else if let display {
                if displays.count > 1 {
                    Section {
                        PerDisplayPicker(DisplaysSettingsLookup.tiles(displays), selection: $shell.selectedDisplay)
                    }
                }
                ConnectionRows(env: env, key: display.key, showsEmpty: true)
            } else {
                Section {
                    StatusRow(L("No displays are connected."))
                }
            }
            PageFooterButtons(advanced: nil, help: Self.route)
        }
    }
}

private struct ConnectionRows: View {
    typealias Controls = ConnectionSectionControls

    let env: DisplaysPageEnvironment
    let key: DisplayKey
    /// The page says why there is nothing to change; the Details sheet leaves the group out.
    let showsEmpty: Bool
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var power: ControllerRevision
    @ObservedObject private var panel: ControllerRevision
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var management: ConfigSlice<DisplaysConfig, ManagementConfig>

    init(env: DisplaysPageEnvironment, key: DisplayKey, showsEmpty: Bool) {
        self.env = env
        self.key = key
        self.showsEmpty = showsEmpty
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _power = ObservedObject(wrappedValue: env.runtime.revision(.power))
        _panel = ObservedObject(wrappedValue: env.runtime.revision(.panelProps))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _management = StateObject(wrappedValue: ConfigSlice(env.config, \.management))
    }

    private var display: DisplayInfo? { runtime.displays.first { $0.key == key } }

    var body: some View {
        if let display, let planner = env.context?.connectPlanner {
            let rows = visibleRows(display, planner: planner)
            if !rows.isEmpty {
                Section {
                    if rows.contains(.disconnect), let c = planner.power { disconnectRow(display, c) }
                    if rows.contains(.automatic) { automaticRow(display) }
                    if rows.contains(.withoutReading) { withoutReadingRow }
                    if rows.contains(.underscan), let c = planner.panelProps { underscanRow(display, c) }
                } header: {
                    Text(L("Connection"))
                } footer: {
                    if rows.contains(.disconnect), let note = PowerController.disconnectNote {
                        Text(note)
                    }
                }
                .modifier(DisplaysFeatureOffAlert(switcher: switcher))
            } else if showsEmpty {
                Section {
                    StatusRow(L("Turn on Disconnect displays or Underscan in Displays › Advanced to change how this display connects."))
                }
            }
        }
    }

    private enum Row { case disconnect, automatic, withoutReading, underscan }

    /// Hardware or a feature can't do it → the row is left out (§4.2 States).
    private func visibleRows(_ d: DisplayInfo, planner: ConnectPlanner) -> [Row] {
        var rows: [Row] = []
        if runtime.isEffective(.disconnect), planner.power != nil { rows.append(.disconnect) }
        let autoAvailable: Bool = {
            if case .unavailable? = runtime.availability[.autoDisconnectBuiltin] { return false }
            return true
        }()
        if d.isBuiltin, autoAvailable { rows.append(.automatic) }
        if !d.isBuiltin, d.transport != .snapticVirtual, runtime.isEffective(.autoDisconnectBuiltin) {
            rows.append(.withoutReading)
        }
        if runtime.isEffective(.underscan), let c = planner.panelProps, c.underscan(d) != nil || !d.isBuiltin {
            rows.append(.underscan)
        }
        return rows
    }

    // MARK: Rows

    private func disconnectRow(_ d: DisplayInfo, _ c: PowerController) -> some View {
        let disconnected = c.disabledKeys.contains(d.key) || !d.isActive
        let refusal = disconnected ? nil : c.disconnectRefusal(d)
        return LabeledContent {
            if disconnected {
                Button(L("Connect")) { c.connect(d.key) }
                    .modifier(SettingsAnchor(ControlID("displays.connection.connect")))
            } else {
                Button(L("Disconnect")) { c.disconnect(d.key) }
                    .disabled(refusal != nil)
                    .help(refusal ?? "")
                    .modifier(SettingsAnchor(ControlID("displays.connection.connect")))
            }
        } label: {
            Text(disconnected ? L("Disconnected") : L("Connected"))
            Text(refusal ?? (disconnected
                ? L("Snaptic turned this display off. It comes back when you connect it, quit Snaptic, or restart.")
                : L("Turns the display off until you connect it again, as if you unplugged it.")))
        }
    }

    /// The built-in display turns off while an external display is in use and the lid is open. A Mac has one
    /// built-in display, so 0.2's per-display "Never auto-disconnect" folds into this switch (off = never).
    private func automaticRow(_ d: DisplayInfo) -> some View {
        let feature = switcher.binding([.autoDisconnectBuiltin], title: L("Turn off automatically"))
        let ignore = SettingsBinding.lossyEntry(env.config, \.perDisplay, d.key, fallback: { PerDisplayConfig() },
                                                \.management.ignoreForAutoDisconnect)
        return ToggleSetting(L("Turn off automatically"),
                             help: L("Turns this display off while an external display is in use and the lid is open."),
                             isOn: Binding(get: { feature.wrappedValue && !ignore.wrappedValue }, set: { on in
                                 if on {
                                     ignore.wrappedValue = false
                                     if !feature.wrappedValue { feature.wrappedValue = true }
                                 } else {
                                     feature.wrappedValue = false
                                 }
                             }),
                             anchor: ControlID("displays.connection.automatic"), badge: .beta,
                             disabledReason: switcher.unavailableReason([.autoDisconnectBuiltin])
                                 ?? env.context?.otherApps.pauseReason(for: .autoDisconnectBuiltin))
    }

    private var withoutReadingRow: some View {
        ToggleSetting(L("This display doesn’t support hardware controls"),
                      help: L("Lets the built-in display turn off without reading whether this display is on."),
                      isOn: SettingsBinding.store(env.config, \.management.autoDisconnectWithoutDDC),
                      anchor: ControlID("displays.connection.withoutReading"))
    }

    private func underscanRow(_ d: DisplayInfo, _ c: PanelPropsController) -> some View {
        SliderSetting(L("Underscan"),
                      help: L("Shrinks the picture to fit a TV that cuts off its edges."),
                      value: Binding(get: { c.underscan(d) ?? 0 }, set: { c.setUnderscan(d.key, $0) }),
                      in: 0...1, step: 0.01, defaultValue: 0, format: .percent(of: 1),
                      commit: .onRelease, anchor: ControlID("displays.connection.underscan"),
                      disabledReason: c.refusal(.underscan, for: d))
    }
}
