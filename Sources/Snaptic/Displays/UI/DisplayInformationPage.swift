import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

/// Displays › Display Information (owner F; PLAN 0.3 §4.3, design M4; replaces the 0.2 Diagnostics page and the
/// status parts of the 0.2 Safety and Display Names pages). The report is live: it is rebuilt whenever the displays,
/// the safety state or the remembered settings change, so there is no Refresh button. Copy Report and Export… use the
/// same text as Copy Display Information Report and `snaptic diagnostics`: identifiers masked, display names replaced, never
/// serial numbers, EDID bytes, window titles or app names. File panels open on the Settings window, never on a sheet.
struct DisplayInformationPage: View, ControlDeclaring {
    typealias Controls = DisplayInformationPageControls

    static let title = L("Display Information")
    static let summary = L("A live report about your displays, to copy when something goes wrong.")
    static let symbol = "info.circle.fill"

    private let env: DisplaysPageEnvironment?

    /// The Displays module's page environment, found through the Settings shell.
    init() {
        env = SettingsShell.shared.host?.displays.pageEnvironment
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env {
            DisplayInformationContent(env: env)
        } else {
            SettingsPageScaffold(route: SettingsRoute(Controls.surface)) {
                SettingsPageHeader(Self.title, summary: Self.summary, symbol: Self.symbol, tint: .gray)
                Section {
                    StatusRow(L("Displays settings aren’t available right now."), style: .warning)
                }
            }
        }
    }
}

private struct DisplayInformationContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    /// B bumps it when the guard, panic or transaction state changes.
    @ObservedObject private var safetyRevision: ControllerRevision
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @StateObject private var kept: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, KeptModes>>
    @State private var copied = false
    @State private var forgetting: DisplayKey?
    @State private var confirmForgetAll = false

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _safetyRevision = ObservedObject(wrappedValue: env.runtime.revision(.diagnostics))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
        _kept = StateObject(wrappedValue: ConfigSlice(env.config, \.safety.keptModes))
    }

    var body: some View {
        let context = env.context
        let report = DiagnosticsController.makeReport(context: context, runtime: runtime)
        SettingsPageScaffold(route: SettingsRoute(DisplayInformationPageControls.surface)) {
            SettingsPageHeader(DisplayInformationPage.title, summary: DisplayInformationPage.summary,
                               symbol: DisplayInformationPage.symbol, tint: .gray)
            reportActions(context)
            if let context {
                safetySection(context)
                unavailableSection(context)
                edidSection(context)
            }
            rememberedDisplaysSection
            rememberedResolutionsSection
            reportSection(report)
            PageFooterButtons(advanced: nil, help: SettingsRoute(DisplayInformationPageControls.surface))
        }
        .confirmationDialog(L("Forget “\(forgetting.map(rememberedName) ?? "")”?"),
                            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button(L("Forget"), role: .destructive) {
                if let key = forgetting { forget([key]) }
                forgetting = nil
            }
            Button(L("Cancel"), role: .cancel) { forgetting = nil }
        } message: {
            Text(L("Snaptic removes this display’s brightness, color, resolution, and menu settings."))
        }
        .confirmationDialog(L("Forget every remembered display?"), isPresented: $confirmForgetAll) {
            Button(L("Forget All"), role: .destructive) { forget(remembered) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Snaptic removes the settings of \(remembered.count) displays that aren’t connected."))
        }
    }

    // MARK: Report actions

    @ViewBuilder private func reportActions(_ context: DisplaysContext?) -> some View {
        Section {
            HStack(spacing: 8) {
                Button(L("Copy Report")) { copy() }
                    .modifier(SettingsAnchor(ControlID("displays.info.copyReport")))
                Button(L("Export…")) { export() }
                    .modifier(SettingsAnchor(ControlID("displays.info.export")))
                Spacer(minLength: 8)
                if copied {
                    Label(L("Copied"), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Attach the report when you report a problem. It has no display names, serial numbers, window titles, or app names, and identifiers are masked."))
                if context == nil {
                    Text(L("Displays is off, so the report has only system facts and recent events."))
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func copy() {
        let text = DiagnosticsController.makeReport(context: env.context, runtime: runtime).text
        DiagnosticsController.copyToClipboard(text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [copied = $copied] in
            MainActor.assumeIsolated { copied.wrappedValue = false }
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: L("Report copied"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    private func export() {
        let data = Data(DiagnosticsController.makeReport(context: env.context, runtime: runtime).text.utf8)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Snaptic Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        DisplayInformationFiles.save(data, with: panel, failure: "Diagnostics export failed")
    }

    // MARK: Safety helper

    @ViewBuilder private func safetySection(_ ctx: DisplaysContext) -> some View {
        Section {
            LabeledContent(L("Status"), value: guardStatus(ctx))
            if let unprotected = DisplaysLive.unprotectedReason(ctx) {
                // The real reason (it names `helpers.unavailable` when the helpers can't run; review6 ux nit 6).
                StatusRow(unprotected, style: .warning, actions: [
                    StatusAction(title: L("Restart Snaptic"), control: ControlID("displays.info.restartHelper")) {
                        ctx.relauncher.relaunch(reason: L("Restart the safety helper"))
                    },
                ])
            }
            LabeledContent(L("Can revert rotation and HDR"), value: ctx.guardClient.canMonitorPanel ? L("Yes") : L("No"))
            LabeledContent(L("Change awaiting confirmation"),
                           value: ctx.transactions.hasPendingTrial ? L("Yes") : L("No"))
            LabeledContent(L("Undo journal"),
                           value: DisplayInformationText.journal(hasSessionJournal: ctx.transactions.hasSessionJournal,
                                                                 permanentSteps: ctx.transactions.permanentJournalCount))
        } header: {
            Text(L("Safety helper"))
        }
        .modifier(SettingsAnchor(ControlID("displays.info.safetyHelper")))
    }

    private func guardStatus(_ ctx: DisplaysContext) -> String {
        if ctx.guardClient.isAlive { return L("Running") }
        return ctx.guardClient.lastFailure ?? L("Starts when needed")
    }

    // MARK: Unavailable on this Mac

    @ViewBuilder private func unavailableSection(_ ctx: DisplaysContext) -> some View {
        let rows = unavailableRows(ctx)
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(L("Unavailable on this Mac"))
            }
            .modifier(SettingsAnchor(ControlID("displays.info.unavailable")))
        }
    }

    /// Features this Mac can't run, by their user titles (never camelCase), with the reason.
    private func unavailableRows(_ ctx: DisplaysContext) -> [DiagnosticsRow] {
        var reasons: [DisplayFeature: String] = ctx.privateAPI.unavailableFeatures()
        for (feature, availability) in runtime.availability {
            if case .unavailable(let reason) = availability { reasons[feature] = reason }
        }
        return DisplayFeature.allCases.compactMap { feature in
            reasons[feature].map { DiagnosticsRow(DisplaysUIText.title(feature), $0) }
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    // MARK: EDID

    @ViewBuilder private func edidSection(_ ctx: DisplaysContext) -> some View {
        let displays = DisplaysLive.ordered(runtime: runtime, menu: ctx.config.value.menu, includeHidden: true)
            .filter { $0.isOnline && $0.transport != .snapticVirtual && $0.transport != .foreignVirtual }
        if !displays.isEmpty {
            Section {
                ForEach(displays) { display in
                    LabeledContent {
                        Button(L("Export EDID…")) { exportEDID(display, context: ctx) }
                            .accessibilityLabel(L("Export the EDID of \(display.name)"))
                    } label: {
                        Text(display.name)
                        Text(DisplaysUIText.transportName(display.transport))
                    }
                }
            } header: {
                Text(L("EDID"))
            } footer: {
                Text(L("The data a display reports about itself, saved as a file for support or other apps."))
                    .foregroundStyle(.secondary)
            }
            .modifier(SettingsAnchor(ControlID("displays.info.exportEDID")))
        }
    }

    private func exportEDID(_ display: DisplayInfo, context ctx: DisplaysContext) {
        let info = ctx.privateAPI.function(.coreDisplayInfo, as: IORegistryDisplays.InfoDictionaryFn.self)
        guard let edid = IORegistryDisplays.facts(for: display.hardwareID, coreDisplayInfo: info).edid, !edid.isEmpty else {
            ctx.toasts.show(L("macOS doesn’t provide an EDID for this display."))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = EDIDText.exportFileName(displayName: display.name)
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.canCreateDirectories = true
        DisplayInformationFiles.save(Data(edid.prefix(EDIDInfo.maxBytes)), with: panel, failure: "EDID export failed")
    }

    // MARK: Remembered displays

    /// Displays with saved settings that aren't connected now.
    private var remembered: [DisplayKey] {
        DisplayInformationText.remembered(stored: Array(perDisplay.value.values.keys),
                                          online: Set(runtime.displays.filter(\.isOnline).map(\.key)))
    }

    private func rememberedName(_ key: DisplayKey) -> String {
        DisplayInformationText.name(key, identity: perDisplay.value[key]?.identity)
    }

    @ViewBuilder private var rememberedDisplaysSection: some View {
        let keys = remembered
        Section {
            if keys.isEmpty {
                Text(L("Displays you connect are remembered here, with their settings."))
                    .foregroundStyle(.secondary)
            }
            ForEach(keys, id: \.self) { key in
                LabeledContent {
                    Button(L("Forget…")) { forgetting = key }
                        .accessibilityLabel(L("Forget \(rememberedName(key))"))
                } label: {
                    Text(rememberedName(key))
                    if let seen = perDisplay.value[key]?.identity.lastSeen {
                        Text(L("Last connected \(Date(timeIntervalSince1970: seen).formatted(date: .abbreviated, time: .omitted))"))
                    }
                }
            }
            if keys.count > 1 {
                ButtonRow(L("Forget All…"), control: ControlID("displays.info.forgetAll")) { confirmForgetAll = true }
            }
        } header: {
            Text(L("Remembered displays"))
        } footer: {
            Text(L("Snaptic keeps the settings of up to \(DisplaysConfig.maxRememberedDisplays) displays."))
                .foregroundStyle(.secondary)
        }
        .modifier(SettingsAnchor(ControlID("displays.info.remembered")))
    }

    private func forget(_ keys: [DisplayKey]) {
        guard !keys.isEmpty else { return }
        var value = env.config.value
        for key in keys {
            value.perDisplay[key] = nil
            value.menu.forget(key)
        }
        env.config.value = value
        EventLog.shared.record(.registry, keys.count == 1 ? "Forgot a remembered display" : "Forgot remembered displays")
    }

    // MARK: Remembered resolutions

    @ViewBuilder private var rememberedResolutionsSection: some View {
        let keys = kept.value.values.keys.sorted { $0.rawValue < $1.rawValue }
        Section {
            if keys.isEmpty {
                Text(L("Resolutions you keep are remembered here, so Snaptic doesn’t ask again."))
                    .foregroundStyle(.secondary)
            }
            ForEach(keys, id: \.self) { key in
                LabeledContent {
                    Button(L("Forget")) { forgetKeptModes(key) }
                        .accessibilityLabel(L("Forget the resolutions of \(displayName(key))"))
                } label: {
                    Text(displayName(key))
                    Text(DisplayInformationText.resolutionCount(kept.value[key]?.modes.count ?? 0))
                }
            }
        } header: {
            Text(L("Remembered resolutions"))
        }
        .modifier(SettingsAnchor(ControlID("displays.info.rememberedResolutions")))
    }

    private func displayName(_ key: DisplayKey) -> String {
        runtime.displays.first { $0.key == key }?.name ?? rememberedName(key)
    }

    private func forgetKeptModes(_ key: DisplayKey) {
        var value = env.config.value
        guard value.safety.keptModes[key] != nil else { return }
        value.safety.keptModes[key] = nil
        env.config.value = value
    }

    // MARK: The report

    private func reportSection(_ report: DiagnosticsReport) -> some View {
        Section {
            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                DisclosureGroup(section.title) {
                    if section.rows.isEmpty {
                        Text(L("Nothing to report")).foregroundStyle(.secondary)
                    }
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            DisclosureGroup(L("Recent events (\(report.events.count))")) {
                if report.events.isEmpty {
                    Text(L("No events yet")).foregroundStyle(.secondary)
                } else {
                    Text(report.events.suffix(60).joined(separator: "\n"))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    if report.events.count > 60 {
                        Text(L("The copied report has all \(report.events.count) events."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(L("Report"))
        }
        .modifier(SettingsAnchor(ControlID("displays.info.report")))
    }
}

/// Save panels for Display Information: on the Settings window when it is key, never over a sheet.
@MainActor private enum DisplayInformationFiles {
    static func save(_ data: Data, with panel: NSSavePanel, failure: String) {
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                EventLog.shared.record(.modules, failure)
            }
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }
}
