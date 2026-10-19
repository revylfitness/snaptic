import AppKit
import Combine
import ServiceManagement
import SwiftUI
import SnapticKit

/// 0.2 page ids still passed by callers (StatusMenu, AppDelegate, the `open-settings` verb); `SettingsLocation`
/// maps them to the 0.3 roots (General, About).
enum GeneralPages {
    static let aboutID = "general.about"
}

/// Settings › General (H; PLAN 0.3 §4.3): hero header; the one-time cards; the module switches while every module
/// is off; Safe Mode status; Open at login; Command-line control (+ Copy Install Command); backup. Footer:
/// Advanced… (?). The module navigation rows of r1 are gone (the sidebar lists the modules; design M1).
struct GeneralPage: View, ControlDeclaring {
    typealias Controls = GeneralPageControls
    @ObservedObject var host: ModuleHost

    var body: some View {
        GeneralPageContent(host: host, modules: host.modulesStore, shell: SettingsShell.shared)
    }
}

private struct GeneralPageContent: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var modules: ConfigStore<ModulesConfig>
    @ObservedObject var shell: SettingsShell

    private var enabled: Set<ModuleID> { Set(modules.value.enabledModules) }

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.general)) {
            SettingsPageHeader(L("General"), summary: L("Startup, command line, backup, and Safe Mode."),
                               symbol: "gearshape", tint: .gray)
            if host.showsV031Welcome, let updater = host.updaterController {
                Section {
                    WelcomeV031Card(host: host, updater: updater, permissions: host.permissions)
                }
            }
            ForEach(GeneralCardRules.visible(modules.value.newModuleCards, enabled: enabled,
                                             blocked: host.disabledByDefaults), id: \.self) { card in
                Section {
                    NewModuleCardView(card: card, primary: { act(on: card) }, dismiss: { dismiss(card) })
                }
            }
            if GeneralCardRules.showsModuleChooser(enabled: enabled, blocked: host.disabledByDefaults) {
                moduleChooser
            }
            if host.safeMode.isActive {
                Section {
                    StatusRow(L("Safe Mode is on."), style: .warning, actions: [
                        StatusAction(title: L("Leave Safe Mode…"), control: ControlID("general.page.leaveSafeMode")) {
                            SafeModeLeave.confirm(relauncher: host.relauncher)
                        },
                    ])
                }
            }
            Section {
                OpenAtLoginRow()
            }
            Section {
                ToggleSetting(L("Command-line control"),
                              help: L("Lets scripts and other apps control Snaptic with the snaptic command."),
                              isOn: SettingsBinding.store(modules, \.commandLine.enabled),
                              anchor: ControlID("general.page.commandLine"))
                if modules.value.commandLine.enabled {
                    ButtonRow(L("Copy Install Command"), help: L("Copies a Terminal command that installs snaptic."),
                              subordinate: true, control: ControlID("general.page.copyInstall")) {
                        copyInstallCommand()
                    }
                    if case .failed(let reason) = host.controlServer.status {
                        SettingsRowNote(reason)
                    }
                }
            }
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Button(L("Export Settings…")) { Backup.export(host: host) }
                            .modifier(SettingsAnchor(ControlID("general.page.export")))
                        Button(L("Import Settings…")) { Backup.`import`(host: host) }
                            .modifier(SettingsAnchor(ControlID("general.page.import")))
                    }
                    .fixedSize()
                } label: {
                    Text(L("Backup"))
                    Text(L("Save your settings to a file, or bring them in from one."))
                }
            }
            PageFooterButtons(advanced: { shell.openSheet = GeneralAdvancedSheetControls.sheet },
                              help: SettingsRoute(SettingsRootID.general),
                              advancedControl: ControlID("general.page.advanced"))
        }
        .sheet(isPresented: shell.sheetBinding(GeneralAdvancedSheetControls.sheet)) {
            GeneralAdvancedSheet(host: host, modules: modules)
        }
    }

    private var moduleChooser: some View {
        Section {
            ForEach(ModuleID.allCases, id: \.self) { id in
                ModuleSwitchRow(id, title: host.module(id).title, isOn: shell.moduleEnabled(id),
                                blocked: host.disabledByDefaults.contains(id), anchor: ControlID("general.page.modules"))
            }
        } header: {
            Text(L("Choose what Snaptic does"))
        } footer: {
            Text(L("Anything that’s off adds nothing to the menu bar and doesn’t run. Each one has its own page in the sidebar."))
                .foregroundStyle(.secondary)
        }
    }

    /// Turn On Awake / Turn On Displays turn the module on; Show Awake doesn't. Each opens the module's page.
    private func act(on card: NewModuleCard) {
        let id = GeneralCardRules.module(of: card)
        var config = GeneralCardRules.dismissing(card, in: modules.value)
        if card != .awakeMigrated { config.setEnabled(true, for: id) }
        modules.value = config
        shell.go(to: SettingsLocation(root: id.rawValue))
    }

    private func dismiss(_ card: NewModuleCard) {
        modules.value = GeneralCardRules.dismissing(card, in: modules.value)
    }

    private func copyInstallCommand() {
        let executable = Bundle.main.executablePath ?? (Bundle.main.bundlePath + "/Contents/MacOS/Snaptic")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(KitControl.installCommand(executable: executable), forType: .string)
        host.toasts.show(L("Install command copied. Paste it into Terminal; it asks for your password."))
    }
}

/// 0.3.1 E1a: the upgraders' welcome card. Release builds are now Developer ID-signed, so macOS dropped the old
/// grants once: a row per permission to allow again, the update choice, and one line of what's new. Done hides it;
/// it also hides itself once the choice is made and nothing is left to allow.
private struct WelcomeV031Card: View {
    let host: ModuleHost
    @ObservedObject var updater: UpdaterController
    @ObservedObject var permissions: PermissionFlow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon("sparkles", tint: SettingsTint.blue, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Welcome to Snaptic 0.3.1")).font(.headline)
                Text(L("Snaptic is now signed by its developer, so macOS asks you to allow it again once. After this, updates keep your permissions."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(host.v031RegrantRows, id: \.self) { permission in
                    row(PermissionFlow.paneName(permission),
                        detail: L("Remove the old Snaptic with −, then turn on the new one.")) {
                        Button(L("Open System Settings…")) { permissions.presentGuide(permission) }
                            .modifier(SettingsAnchor(permission == .accessibility
                                ? ControlID("general.page.card.v031.openAccessibility")
                                : ControlID("general.page.card.v031.openScreenRecording")))
                    }
                }
                if !updater.consentDecided {
                    row(L("Keep Snaptic up to date"), detail: nil) {
                        Button(L("Not Now")) { answer(false) }
                            .modifier(SettingsAnchor(ControlID("general.page.card.v031.notNow")))
                        Button(L("Check Automatically")) { answer(true) }
                            .modifier(SettingsAnchor(ControlID("general.page.card.v031.autoCheck")))
                    }
                }
                Text(L("New in 0.3.1: tabs in the Snaptic menu, keeping awake with the lid closed, and automatic updates."))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Done")) { host.dismissV031Welcome() }
                    .modifier(SettingsAnchor(ControlID("general.page.card.v031.done")))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .onAppear { finishIfDone() }
        .onChange(of: permissions.granted) { finishIfDone() }
    }

    private func row<Actions: View>(_ title: String, detail: String?, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            actions()
        }
    }

    /// Check Automatically also turns on automatic install, except for root-owned copies (E1a).
    private func answer(_ allowed: Bool) {
        updater.setConsent(allowed)
        finishIfDone()
    }

    private func finishIfDone() {
        permissions.refresh()
        host.finishV031WelcomeIfDone()
    }
}

/// A one-time card: "New: Awake" [Turn On Awake] [Not Now], or "Your display sleep setting moved to Awake."
/// [Show Awake] [OK] (C7, design M3).
private struct NewModuleCardView: View {
    let card: NewModuleCard
    let primary: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let style = SettingsShell.sidebarStyle[GeneralCardRules.module(of: card).rawValue]
            ?? (symbol: "sparkles", tint: SettingsTint.blue)
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(style.symbol, tint: style.tint, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(primaryTitle, action: primary)
                        .modifier(SettingsAnchor(ControlID("general.page.card.primary")))
                    Button(dismissTitle, action: dismiss)
                        .modifier(SettingsAnchor(ControlID("general.page.card.dismiss")))
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch card {
        case .displays: return L("New: Displays")
        case .awake: return L("New: Awake")
        case .awakeMigrated: return L("Your display sleep setting moved to Awake.")
        }
    }

    private var text: String {
        switch card {
        case .displays: return L("Brightness, resolution, and arrangement for every display.")
        case .awake: return L("Keep your Mac awake for a while, or whenever you choose.")
        case .awakeMigrated: return L("Awake now keeps your Mac awake while the displays you chose are connected.")
        }
    }

    private var primaryTitle: String {
        switch card {
        case .displays: return L("Turn On Displays")
        case .awake: return L("Turn On Awake")
        case .awakeMigrated: return L("Show Awake")
        }
    }

    private var dismissTitle: String { card == .awakeMigrated ? L("OK") : L("Not Now") }
}

/// "Open at login" through `SMAppService.mainApp`. The switch shows the system's state, re-read when the page
/// appears and whenever Snaptic becomes active (the user may change it in System Settings › Login Items).
private struct OpenAtLoginRow: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToggleSetting(L("Open at login"), help: L("Snaptic starts when you log in to your Mac."),
                          isOn: Binding(get: { isOn }, set: { set($0) }),
                          anchor: ControlID("general.page.openAtLogin"))
            if needsApproval {
                SettingsRowNote(L("Allow Snaptic in Login Items to finish turning this on."),
                                fix: StatusAction(title: L("Open Login Items Settings…")) {
                                    SMAppService.openSystemSettingsLoginItems()
                                })
            } else if let problem {
                SettingsRowNote(problem)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        let status = SMAppService.mainApp.status
        if isOn != (status == .enabled) { isOn = status == .enabled }
        if needsApproval != (status == .requiresApproval) { needsApproval = status == .requiresApproval }
    }

    private func set(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
            problem = nil
        } catch {
            problem = on ? L("Snaptic couldn’t be added to your login items. Try again, or add it in System Settings.")
                : L("Snaptic couldn’t be removed from your login items. Remove it in System Settings.")
        }
        refresh()
    }
}
