import AppKit
import SwiftUI
import SnapticKit

/// Settings → General (PLAN §3.7): Modules, Menu, Command-line control, Startup,
/// Permissions, Backup & Reset, Safe Mode, Other display apps, About & Licenses.
enum GeneralPages {
    static let modulesID = "general.modules"
    static let menuID = "general.menu"
    static let permissionsID = "general.permissions"
    static let safeModeID = "general.safemode"
    static let aboutID = "general.about"

    @MainActor static func pages(host: ModuleHost) -> [SettingsPage] {
        [
            SettingsPage(id: modulesID, title: L("Modules"), symbol: "square.grid.2x2") {
                AnyView(ModulesPage(host: host, store: host.modulesStore))
            },
            SettingsPage(id: menuID, title: L("Menu"), symbol: "menubar.rectangle") {
                AnyView(MenuPage(host: host, store: host.modulesStore, env: host.displays.pageEnvironment))
            },
            SettingsPage(id: "general.cli", title: L("Command-Line Control"), symbol: "terminal") {
                AnyView(CommandLinePage(store: host.modulesStore))
            },
            SettingsPage(id: "general.startup", title: L("Startup"), symbol: "power") {
                AnyView(Form { LaunchAtLoginSection() }.formStyle(.grouped))
            },
            SettingsPage(id: permissionsID, title: L("Permissions"), symbol: "lock.shield") {
                AnyView(PermissionsPage(host: host, permissions: host.permissions))
            },
            SettingsPage(id: "general.backup", title: L("Backup & Reset"), symbol: "externaldrive") {
                AnyView(BackupResetPage(host: host))
            },
            SettingsPage(id: safeModeID, title: L("Safe Mode"), symbol: "shield.lefthalf.filled") {
                AnyView(SafeModePage(host: host))
            },
            SettingsPage(id: "general.otherapps", title: L("Other Display Apps"), symbol: "app.badge") {
                AnyView(OtherAppsPage())
            },
            SettingsPage(id: aboutID, title: L("About & Licenses"), symbol: "info.circle") {
                AnyView(AboutPage())
            },
        ]
    }
}

// MARK: - Modules

private struct ModulesPage: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var store: ConfigStore<ModulesConfig>

    var body: some View {
        Form {
            if store.value.showNewDisplaysCard && !store.value.isEnabled(.displays) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("New: Displays"), systemImage: "sparkles")
                            .font(.headline)
                        Text(host.displays.summary)
                        Text(L("Brightness and volume for external monitors, resolutions, virtual screens, picture in picture and more. Everything is off until you choose it."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(L("Turn On Displays")) { host.setEnabled(true, .displays) }
                                .keyboardShortcut(.defaultAction)
                            Button(L("Not Now")) { store.value.showNewDisplaysCard = false }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                ForEach(ModuleID.allCases, id: \.self) { id in
                    ModuleRow(host: host, module: host.module(id), isOn: binding(id))
                }
            } header: {
                Text(L("Modules"))
            } footer: {
                Text(L("A module that is off costs nothing: no shortcuts, timers, observers or permission requests."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ id: ModuleID) -> Binding<Bool> {
        Binding(get: { store.value.isEnabled(id) }, set: { host.setEnabled($0, id) })
    }
}

private struct ModuleRow: View {
    @ObservedObject var host: ModuleHost
    let module: any SnapticModule
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: module.symbolName)
                .font(.title2)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).fontWeight(.medium)
                Text(module.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }
            Spacer()
            Toggle(module.title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }

    private var stateText: String {
        _ = host.revision
        switch module.state {
        case .running: return L("Running")
        case .stopped: return isOn ? L("Starting…") : L("Off")
        case .degraded(let reason): return reason
        }
    }

    private var stateColor: Color {
        if case .degraded = module.state { return .orange }
        return .secondary
    }
}

// MARK: - Menu

private struct MenuPage: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var store: ConfigStore<ModulesConfig>
    @ObservedObject var env: DisplaysPageEnvironment

    var body: some View {
        Form {
            let plan = store.value.statusItemPlan(running: host.runningModules)
            if plan.everythingHidden {
                Section {
                    Label(L("Every menu bar icon is hidden. Open Snaptic again from Finder or Launchpad to come back to Settings; shortcuts keep working."),
                          systemImage: "eye.slash")
                }
            }
            ForEach(ModuleID.allCases, id: \.self) { id in
                moduleSection(id)
            }
            Section(L("Snaptic's menu")) {
                Picker(L("Icon"), selection: Binding(get: { store.value.sharedSymbol },
                                                    set: { store.value.sharedSymbol = $0 })) {
                    Text(L("Default")).tag("")
                    ForEach(ModulesConfig.curatedSymbols, id: \.self) { symbol in
                        Label(symbol, systemImage: symbol).tag(symbol)
                    }
                }
                Toggle(L("Scroll on a slider to adjust"), isOn: Binding(
                    get: { env.config.value.menu.scrollAdjustsSliders },
                    set: { env.config.value.menu.scrollAdjustsSliders = $0 }))
            }
            MenuCustomizationPage(env: env)
            Section {
                Button(L("Reset Menu Settings")) {
                    store.value.resetMenu()
                    env.config.value.menu.resetLayout()
                    env.config.value.menu.scrollAdjustsSliders = true
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func moduleSection(_ id: ModuleID) -> some View {
        let module = host.module(id)
        Section(module.title) {
            Picker(L("Show"), selection: Binding(get: { store.value.placement(id) },
                                                set: { store.value.setPlacement($0, for: id) })) {
                ForEach(MenuPlacementChoice.allCases, id: \.self) { choice in
                    Text(MenuPlacement.title(choice)).tag(choice)
                }
            }
            if store.value.placement(id) == .ownIcon {
                Picker(L("Icon"), selection: Binding(get: { store.value.preferences(id).symbol },
                                                    set: { store.value.setSymbol($0, for: id) })) {
                    Text(L("Default")).tag("")
                    ForEach(ModulesConfig.curatedSymbols, id: \.self) { symbol in
                        Label(symbol, systemImage: symbol).tag(symbol)
                    }
                }
                if id == .displays {
                    Toggle(L("Hide the icon when no external display is connected"), isOn: Binding(
                        get: { store.value.preferences(id).hideWithoutExternalDisplay },
                        set: { on in
                            var p = store.value.preferences(id)
                            p.hideWithoutExternalDisplay = on
                            store.value.modules[id] = p
                        }))
                }
            }
            if !store.value.isEnabled(id) {
                Text(L("This module is off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Command line

private struct CommandLinePage: View {
    @ObservedObject var store: ConfigStore<ModulesConfig>

    var body: some View {
        Form {
            Section {
                Text(L("Control Snaptic from Terminal, Shortcuts, Stream Deck or Raycast with the snaptic command. The command-line server arrives in the next update; these settings are kept until then."))
                    .foregroundStyle(.secondary)
                Toggle(L("Allow command-line control"), isOn: Binding(get: { store.value.commandLine.enabled },
                                                                     set: { store.value.commandLine.enabled = $0 }))
                Toggle(L("Let commands skip the confirmation panel"), isOn: Binding(
                    get: { store.value.commandLine.maySkipConfirmation },
                    set: { store.value.commandLine.maySkipConfirmation = $0 }))
                    .disabled(!store.value.commandLine.enabled)
            } header: {
                Text(L("Command-Line Control"))
            } footer: {
                Text(L("Commands can only turn protected features off, never on. Snaptic never listens on the network."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    let host: ModuleHost
    @ObservedObject var permissions: PermissionFlow

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(
                        title: PermissionFlow.paneName(permission),
                        detail: PermissionFlow.purpose(permission) + " " + neededBy(permission),
                        granted: permissions.granted.contains(permission),
                        open: { permissions.presentGuide(permission) }
                    )
                }
            } header: {
                Text(L("Permissions"))
            } footer: {
                Text(L("Snaptic asks only for what the modules and features you turned on need. After a grant, macOS may need Snaptic to relaunch."))
                    .foregroundStyle(.secondary)
            }
            Section(L("This copy of Snaptic")) {
                LabeledContent {
                    Text(PermissionFlow.bundlePath).textSelection(.enabled).lineLimit(2)
                } label: {
                    Text(L("Location"))
                }
                LabeledContent {
                    Text(PermissionFlow.signer)
                } label: {
                    Text(L("Signed by"))
                }
                if PermissionFlow.bundleIsUserWritable {
                    Label(L("This folder can be changed by your account, so another program could replace Snaptic and inherit its permissions. Prefer a signed release, or install with INSTALL=1."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if PermissionFlow.isTranslocated {
                    Label(L("Snaptic is running from a temporary location. Move it to Applications before granting permissions."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button(L("Relaunch Snaptic")) { host.relauncher.relaunch(reason: "permissions page") }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }

    private func neededBy(_ permission: Permission) -> String {
        let names = host.modules.filter { host.isRunning($0.id) && $0.requiredPermissions.contains(permission) }.map { $0.title }
        return names.isEmpty ? L("Not needed by your current settings.") : L("Needed by ") + names.joined(separator: L(" and ")) + "."
    }
}

// MARK: - Backup & Reset

private struct BackupResetPage: View {
    let host: ModuleHost

    var body: some View {
        Form {
            Section {
                Text(L("Exporting and importing settings arrive in the next update. Exports will never include hooks, actions, command-line settings or anything marked sensitive."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Backup"))
            }
            Section {
                Button(L("Reset All Settings…"), role: .destructive) { host.resetAllSettings() }
            } header: {
                Text(L("Reset"))
            } footer: {
                Text(L("Every module, shortcut, menu and display setting goes back to its default, then Snaptic restarts."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Safe Mode

private struct SafeModePage: View {
    let host: ModuleHost

    var body: some View {
        Form {
            Section {
                if host.safeMode.isActive {
                    Label(L("Snaptic is running in Safe Mode."), systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(.orange)
                    if let reason = host.safeMode.reason { Text(reason).foregroundStyle(.secondary) }
                    Button(L("Leave Safe Mode")) { host.relauncher.relaunch(reason: "leave safe mode") }
                } else {
                    Text(L("Safe Mode starts Snaptic without anything that changes your displays by itself. It starts automatically after two quick unexpected quits, or when you hold ⇧ while opening Snaptic."))
                    Button(L("Restart in Safe Mode")) { host.relauncher.relaunch(reason: "enter safe mode", safeMode: true) }
                }
            } header: {
                Text(L("Safe Mode"))
            }
            Section(L("Safe Mode skips")) {
                ForEach(SafeMode.skipped, id: \.self) { Text($0) }
            }
            Section(L("Still runs")) {
                ForEach(SafeMode.stillRuns, id: \.self) { Text($0) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Other display apps

private struct OtherAppsPage: View {
    var body: some View {
        Form {
            Section {
                Text(L("When BetterDisplay, MonitorControl or Lunar runs, Snaptic will offer to pause the Displays features that overlap with it. Detection arrives in the next update."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Other Display Apps"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutPage: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return short + " (" + build + ")"
    }

    private struct Credit: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    private let credits: [Credit] = [
        Credit(name: "yabai", detail: L("Window focus technique (MIT)")),
        Credit(name: "MonitorControl", detail: L("DDC/CI approach (MIT)")),
        Credit(name: "m1ddc", detail: L("Apple silicon DDC (MIT)")),
        Credit(name: "displayplacer", detail: L("Display arrangement (MIT)")),
        Credit(name: "force-hidpi", detail: L("HiDPI virtual displays (MIT)")),
        Credit(name: "Chromium", detail: L("Process responsibility handling (BSD)")),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(version)
                } label: {
                    Text(L("Snaptic"))
                }
                Text(L("Free and open source under the MIT License. Snaptic never connects to the network: no telemetry, no update checks."))
                    .foregroundStyle(.secondary)
                Button(L("Check for Updates…")) {
                    if let url = URL(string: "https://github.com/revylfitness/snaptic/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text(L("About"))
            }
            Section(L("Thanks to")) {
                ForEach(credits) { credit in
                    LabeledContent {
                        Text(credit.detail).foregroundStyle(.secondary)
                    } label: {
                        Text(credit.name)
                    }
                }
            }
            Section(L("License")) {
                Text(Self.license)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    static let license = """
    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
    documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
    the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and \
    to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions \
    of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO \
    THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF \
    CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
    DEALINGS IN THE SOFTWARE.
    """
}
