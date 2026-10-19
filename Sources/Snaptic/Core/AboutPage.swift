import AppKit
import SwiftUI
import SnapticKit

/// Settings › About (H; PLAN 0.3 §4.3): app icon, name and version; Updates (0.3.1 E1: Check for Updates…, the
/// automatic check and install switches, and the status row); Acknowledgements… (a sheet with the credits and the MIT
/// License); and Display Information… while Displays runs (it says where it goes; design m14) or Diagnostics Report…
/// (a host report sheet) when it doesn't.
struct AboutPage: View, ControlDeclaring {
    typealias Controls = AboutPageControls
    @ObservedObject var host: ModuleHost
    @State private var showingAcknowledgements = false
    @State private var showingReport = false

    static let releasesURL = UpdatePolicy.releasesURL

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.about)) {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text(L("Snaptic"))
                        .font(.title2.weight(.semibold))
                    Text(Self.version)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            if let updater = host.updaterController {
                UpdatesSection(updater: updater)
            } else {
                Section {
                    // Built from source (ad hoc): no Sparkle, so the button opens the Releases page.
                    StatusRow(UpdateStatusText.text(.fromSource, uses24Hour: false))
                    ButtonRow(L("Check for Updates…"), help: L("Opens the Snaptic releases page in your browser."),
                              control: ControlID("about.page.checkUpdates")) {
                        if let url = URL(string: Self.releasesURL) { NSWorkspace.shared.open(url) }
                    }
                } header: {
                    Text(L("Updates"))
                }
            }
            Section {
                ButtonRow(L("Acknowledgements…"), help: L("The MIT License and the projects Snaptic builds on."),
                          control: ControlID("about.page.acknowledgements")) {
                    showingAcknowledgements = true
                }
                if host.isRunning(.displays) {
                    ButtonRow(L("Display Information…"), help: L("Opens Displays › Display Information."),
                              control: ControlID("about.page.displayInformation")) {
                        SettingsShell.shared.open(page: DisplayInformationPageControls.surface, external: false)
                    }
                } else {
                    ButtonRow(L("Diagnostics Report…"), help: L("A summary of Snaptic’s state to attach to a bug report."),
                              control: ControlID("about.page.diagnostics")) {
                        showingReport = true
                    }
                }
            } footer: {
                Text(L("Free and open source under the MIT License. Snaptic connects only to GitHub to check for updates, and only if you allow it. No analytics."))
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingAcknowledgements) { AcknowledgementsSheet() }
        .sheet(isPresented: $showingReport) { DiagnosticsReportSheet(report: HostDiagnostics.report(host: host)) }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return SettingsText.version(short: info?["CFBundleShortVersionString"] as? String,
                                    build: info?["CFBundleVersion"] as? String)
    }
}

/// 0.3.1 E1: Settings › About › Updates in builds that carry Sparkle. Root-owned copies can't install by themselves,
/// so their automatic-install switch is replaced by a note. The status row is Kit's `UpdateStatusText`.
private struct UpdatesSection: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Section {
            ButtonRow(L("Check for Updates…"), help: L("Checks GitHub for a newer version of Snaptic now."),
                      control: ControlID("about.page.checkUpdates")) {
                updater.checkForUpdates()
            }
            ToggleSetting(L("Check for updates automatically"),
                          help: L("Once a day, Snaptic checks GitHub for a newer version. GitHub sees your IP address and macOS version, nothing more."),
                          isOn: Binding(get: { updater.automaticallyChecksForUpdates },
                                        set: { updater.automaticallyChecksForUpdates = $0 }),
                          anchor: ControlID("about.page.autoCheck"))
            if updater.automaticallyChecksForUpdates {
                if updater.needsAdministrator {
                    SettingsRowNote(L("Only an administrator can change this copy of Snaptic, so each update asks for an administrator password."))
                } else {
                    ToggleSetting(L("Download and install updates automatically"),
                                  help: L("Updates download in the background and install the next time Snaptic quits."),
                                  isOn: Binding(get: { updater.automaticallyDownloadsUpdates },
                                                set: { updater.automaticallyDownloadsUpdates = $0 }),
                                  subordinate: true, anchor: ControlID("about.page.autoInstall"))
                }
            }
            StatusRow(updater.statusText(), actions: updater.offersInstall ? [
                StatusAction(title: L("Install and Relaunch…"), control: ControlID("about.page.installUpdate")) {
                    updater.installUpdate()
                },
            ] : [])
        } header: {
            Text(L("Updates"))
        }
    }
}

/// The host's own report (About, while Displays doesn't run): version, macOS, Safe Mode, command line, module
/// states, permissions, Awake's lines while Awake is enabled, and the recent event log (all free of names and
/// identifiers, §4.10(2)).
@MainActor enum HostDiagnostics {
    static func report(host: ModuleHost) -> String {
        let modules = host.modules.map { module -> HostReport.Module in
            let state: String
            if host.disabledByDefaults.contains(module.id) {
                state = DefaultsLock.state(key: ModuleHost.disableKey(module.id))
            } else if !host.modulesStore.value.isEnabled(module.id) {
                state = L("Off")
            } else {
                switch module.state {
                case .running: state = L("Running")
                case .stopped: state = L("Starting")
                case .degraded(let reason): state = reason
                }
            }
            return HostReport.Module(title: module.title, state: state)
        }
        let awakeEnabled = host.modulesStore.value.isEnabled(.awake) && !host.disabledByDefaults.contains(.awake)
        let commandLine: String
        switch host.controlServer.status {
        case .off: commandLine = L("Off")
        case .listening: commandLine = L("On")
        case .failed(let reason): commandLine = reason
        }
        let sections = HostReport.sections(version: AboutPage.version,
                                           system: ProcessInfo.processInfo.operatingSystemVersionString,
                                           safeMode: host.safeMode.isActive, modules: modules,
                                           granted: host.permissions.granted, commandLine: commandLine,
                                           awake: awakeEnabled ? host.awake.diagnosticsLines() : nil)
        let events = EventLog.shared.recent(100).map { entry in
            entry.date.formatted(date: .omitted, time: .standard) + " " + entry.category.rawValue + " " + entry.message
        }
        return DiagnosticsText.report(header: L("Snaptic diagnostics report"), sections: sections, events: events)
    }
}

/// Credits and the license. Done = Return; Esc closes.
private struct AcknowledgementsSheet: View {
    @Environment(\.dismiss) private var dismiss

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
        // 0.3.1: bundled in release builds; its full license and notices are in THIRD_PARTY_NOTICES.md.
        Credit(name: "Sparkle", detail: L("Software updates, version 2.10.0 (MIT)")),
    ]

    /// Awake's behavior references (THIRD_PARTY_NOTICES.md): rules Snaptic follows, none of their code.
    private let references: [Credit] = [
        Credit(name: "Insomnia", detail: L("Awake session and battery rules (MIT, no code used)")),
        Credit(name: "KeepingYouAwake", detail: L("Low Power Mode and power-source rules (MIT, no code used)")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Acknowledgements"))
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            Form {
                Section(L("Snaptic builds on")) {
                    ForEach(credits) { credit in
                        LabeledContent(credit.name) {
                            Text(credit.detail).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(references) { credit in
                        LabeledContent(credit.name) {
                            Text(credit.detail).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("Awake’s behavior follows"))
                } footer: {
                    Text(L("Snaptic studied what these apps do and follows some of their rules. It includes none of their code."))
                }
                Section(L("License")) {
                    Text(Self.license)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .onExitCommand { dismiss() }
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

/// The host report, selectable, with Copy Report. Done = Return; Esc closes.
private struct DiagnosticsReportSheet: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Diagnostics Report"))
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                Text(report)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .padding(.horizontal, 16)
            Text(L("The report has no names, window titles, or serial numbers. Read it before you share it."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Button(copied ? L("Copied") : L("Copy Report")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
        .onExitCommand { dismiss() }
    }
}
