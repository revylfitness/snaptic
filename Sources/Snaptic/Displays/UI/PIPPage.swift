import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

/// Displays › Picture in Picture (owner E; PLAN 0.3 §4.3 sub-page "Picture in Picture (E)"): the feature switch, the
/// Screen Recording status row, the Running list (Pause, Show, Stop; Crop in the row menu; Stop All ▾ in the section
/// header), the Saved list (Start, Edit…), New PIP… / New Stream…, Import Color Lookup Table… and the footer
/// (Advanced… · ?). Each saved picture in picture opens in `PIPEditorSheet`; the Advanced sheet holds Filters, Never
/// capture these apps, pause covered PIPs and the ⌃⌥⌘P switch.
/// Config arrives through slices and session state through `CaptureService` (0.3 §4.5): a write elsewhere doesn't
/// re-render the page.
struct PIPPage: View, ControlDeclaring {
    typealias Controls = PIPPageControls

    let env: DisplaysPageEnvironment

    static let title = L("Picture in Picture")
    static let summary = L("Show a live view of any window or display.")
    static let symbol = "pip.fill"
    static let tint = SettingsTint.green

    /// Shown while Picture in Picture is off.
    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "displays.pip.window", symbol: "pip", title: L("A window on any display"),
                         text: L("Keep an eye on another display or one window in a small floating window.")),
        FeatureHighlight(id: "displays.pip.stream", symbol: "rectangle.on.rectangle", title: L("Full-screen streams"),
                         text: L("Show one display full screen on another, rotated or flipped for a teleprompter.")),
        FeatureHighlight(id: "displays.pip.filters", symbol: "camera.filters", title: L("Crop and filters"),
                         text: L("Show only part of the source, and adjust its colors with filters.")),
    ]

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let host = SettingsShell.shared.host {
            PIPPageContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

/// Which configuration the editor sheet shows.
struct PIPEditorRequest: Identifiable {
    enum Mode {
        case edit
        /// A draft that's saved only with Add.
        case new(PIPConfiguration, PIPSourceRef)
    }

    let id: StableID
    let mode: Mode

    static func edit(_ id: StableID) -> PIPEditorRequest { PIPEditorRequest(id: id, mode: .edit) }

    static func new(_ draft: PIPConfiguration, source: PIPSourceRef) -> PIPEditorRequest {
        PIPEditorRequest(id: draft.id, mode: .new(draft, source))
    }
}

/// Display names for sources and targets, also while a display isn't connected.
@MainActor enum PIPPageText {
    static func displayName(_ key: DisplayKey, runtime: DisplaysRuntimeState, config: DisplaysConfig) -> String {
        if let d = runtime.displays.first(where: { $0.key == key }) { return d.name }
        let identity = config.perDisplay[key]?.identity
        return identity?.customName ?? identity?.lastKnownName ?? L("A display that isn’t connected")
    }

    static func sourceName(_ source: PIPSourceRef, runtime: DisplaysRuntimeState, config: DisplaysConfig) -> String? {
        switch source {
        case .display(let key): return displayName(key, runtime: runtime, config: config)
        case .window: return nil
        }
    }

    static func connected(_ runtime: DisplaysRuntimeState) -> [DisplayInfo] {
        runtime.displays.filter(\.isOnline)
    }
}

fileprivate extension DisplaysConfig {
    /// Every saved configuration with its source, in `PIPConfig.entries(in:)` order (the page's slice).
    var pipPageEntries: [PIPEntry] { PIPConfig.entries(in: self) }
}

// MARK: - Page

private struct PIPPageContent: View, ControlDeclaring {
    typealias Controls = PIPPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @State private var editor: PIPEditorRequest?

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let isOn = FeatureGraph.rawState(.pip, in: features.value)
        SettingsPageScaffold(route: PIPPageControls.route) {
            SettingsPageHeader(PIPPage.title, summary: PIPPage.summary, symbol: PIPPage.symbol, tint: PIPPage.tint,
                               isOn: switcher.binding([.pip], title: PIPPage.title),
                               switchLabel: L("Use Picture in Picture"),
                               control: ControlID("displays.pip.usePIP"))
                .disabled(host.disabledByDefaults.contains(.displays))
            if !isOn {
                FeatureHighlights(PIPPage.highlights)
            } else if let context {
                if let reason = blockedReason(context) {
                    Section {
                        StatusRow(reason, style: .warning)
                    }
                } else {
                    PIPPermissionSection(permissions: context.permissions)
                    PIPListsSection(env: env, capture: context.capture, onEdit: { editor = .edit($0) },
                                    onNew: { editor = $0 })
                    PIPLUTSection(env: env, switcher: switcher)
                }
            } else {
                Section {
                    StatusRow(L("Turn on Displays to use Picture in Picture."))
                }
            }
            PageFooterButtons(advanced: { shell.openSheet = PIPPageControls.advancedSheet },
                              help: PIPPageControls.route,
                              advancedControl: ControlID("displays.pip.advanced"))
        }
        .sheet(isPresented: shell.sheetBinding(PIPPageControls.advancedSheet)) {
            PIPAdvancedSheet(env: env, switcher: switcher)
        }
        .sheet(item: $editor) { request in
            PIPEditorSheet(env: env, request: request)
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    /// Why Picture in Picture isn't running although it's on: unavailable on this Mac, paused for another app,
    /// or still starting.
    private func blockedReason(_ ctx: DisplaysContext) -> String? {
        if runtime.isEffective(.pip) { return nil }
        if case .unavailable(let reason)? = runtime.availability[.pip] { return reason }
        if let reason = ctx.otherApps.pauseReason(for: .pip) { return reason }
        if ctx.safeMode.isActive { return L("Picture in Picture is off in Safe Mode.") }
        return L("Picture in Picture is starting…")
    }
}

// MARK: - Screen Recording

/// "Picture in Picture needs Screen Recording." while the grant is missing (re-renders when it changes).
private struct PIPPermissionSection: View, ControlDeclaring {
    typealias Controls = PIPPageControls

    @ObservedObject var permissions: PermissionFlow

    var body: some View {
        if !permissions.granted.contains(.screenRecording) {
            Section {
                StatusRow(L("Picture in Picture needs Screen Recording."), style: .warning, actions: [
                    StatusAction(title: L("Open Privacy Settings…"),
                                 control: ControlID("displays.pip.status.screenRecording")) {
                        permissions.presentGuide(.screenRecording,
                                                 reason: L("Picture in Picture shows the contents of your displays and windows."))
                    },
                ])
            }
        }
    }
}

// MARK: - Running and saved

private struct PIPListsSection: View, ControlDeclaring {
    typealias Controls = PIPPageControls

    let env: DisplaysPageEnvironment
    let onEdit: (StableID) -> Void
    let onNew: (PIPEditorRequest) -> Void
    @ObservedObject private var capture: CaptureService
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var entries: ConfigSlice<DisplaysConfig, [PIPEntry]>
    @State private var deleting: PIPEntry?

    init(env: DisplaysPageEnvironment, capture: CaptureService, onEdit: @escaping (StableID) -> Void,
         onNew: @escaping (PIPEditorRequest) -> Void) {
        self.env = env
        self.onEdit = onEdit
        self.onNew = onNew
        _capture = ObservedObject(wrappedValue: capture)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _entries = StateObject(wrappedValue: ConfigSlice(env.config, \.pipPageEntries))
    }

    private var controller: PIPController? { capture.controller }

    var body: some View {
        let sessions = capture.sessions
        if !sessions.isEmpty {
            Section {
                ForEach(sessions) { info in
                    PIPRunningRow(info: info, controller: controller)
                }
            } header: {
                HStack {
                    Text(L("Running"))
                        .modifier(SettingsAnchor(ControlID("displays.pip.running")))
                    Spacer(minLength: 8)
                    ActionMenuButton(L("Stop All"), items: bulkItems, primaryAction: { controller?.stopAll() },
                                     control: ControlID("displays.pip.running.stopAll"))
                        .disabled(controller == nil)
                }
            }
        }
        savedSection(running: Set(sessions.map(\.id)))
            .alert(L("Delete “\(deleting?.configuration.name ?? "")”?"),
                   isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(L("Delete"), role: .destructive) {
                    if let id = deleting?.configuration.id { delete(id) }
                    deleting = nil
                }
                Button(L("Cancel"), role: .cancel) { deleting = nil }
            } message: {
                Text(L("It stops first if it’s running."))
            }
    }

    /// Stop All ▾: a click stops everything; the menu pauses or hides every window.
    private var bulkItems: [ActionMenuItem] {
        let paused = controller?.allPaused ?? false
        let hidden = controller?.allHidden ?? false
        let windows = capture.sessions.contains { $0.kind == .window }
        return [
            ActionMenuItem(id: "pauseAll", title: paused ? L("Resume All") : L("Pause All"), enabled: windows) {
                controller?.setAllPaused(!paused)
            },
            ActionMenuItem(id: "hideAll", title: hidden ? L("Show All") : L("Hide All"), enabled: windows) {
                controller?.setAllHidden(!hidden)
            },
        ]
    }

    @ViewBuilder private func savedSection(running: Set<StableID>) -> some View {
        let config = env.config.value
        let connected = Set(PIPPageText.connected(runtime).map(\.key))
        Section {
            if entries.value.isEmpty {
                EmptyListView(L("No Pictures in Picture"), symbol: "pip",
                              text: L("Show a live view of any window or display."), action: nil)
            }
            ForEach(entries.value, id: \.configuration.id) { entry in
                PIPSavedRow(entry: entry,
                            subtitle: subtitle(entry, config: config),
                            running: running.contains(entry.configuration.id),
                            available: PIPMenuPlan.isAvailable(entry, connected: connected),
                            controller: controller,
                            onEdit: { onEdit(entry.configuration.id) },
                            onDelete: { deleting = entry })
            }
            newButtons(config: config)
        } header: {
            if !entries.value.isEmpty {
                Text(L("Saved"))
                    .modifier(SettingsAnchor(ControlID("displays.pip.saved")))
            }
        }
    }

    private func subtitle(_ entry: PIPEntry, config: DisplaysConfig) -> String {
        let c = entry.configuration
        let source = PIPPageText.sourceName(entry.source, runtime: runtime, config: config)
        let target = c.target.map { PIPPageText.displayName($0, runtime: runtime, config: config) }
        return PIPSettingsText.subtitle(c, sourceName: source, targetName: target)
    }

    /// New PIP… (a window or a display in a floating window) and New Stream… (with two displays or more).
    private func newButtons(config: DisplaysConfig) -> some View {
        let displays = PIPPageText.connected(runtime)
        let windowSource = PIPSettingsText.canAdd(source: .window, in: config)
        let displaySources = displays.filter { PIPSettingsText.canAdd(source: .display($0.key), in: config) }
        return HStack(spacing: 8) {
            Spacer(minLength: 0)
            if displays.count > 1 {
                Button(L("New Stream…")) { newStream(displays: displays, sources: displaySources) }
                    .disabled(displaySources.isEmpty)
                    .help(L("Show one display full screen on another."))
                    .modifier(SettingsAnchor(ControlID("displays.pip.newStream")))
            }
            Button(L("New PIP…")) { newPIP(windowSource: windowSource, sources: displaySources) }
                .disabled(!windowSource && displaySources.isEmpty)
                .help(L("Show a window or a display in a floating window."))
                .modifier(SettingsAnchor(ControlID("displays.pip.new")))
        }
    }

    private func newPIP(windowSource: Bool, sources: [DisplayInfo]) {
        let source: PIPSourceRef = windowSource ? .window : (sources.first.map { .display($0.key) } ?? .window)
        onNew(.new(PIPConfiguration(kind: .window), source: source))
    }

    private func newStream(displays: [DisplayInfo], sources: [DisplayInfo]) {
        let selected = SettingsShell.shared.selectedDisplay
        guard let source = sources.first(where: { $0.key == selected }) ?? sources.first(where: \.isMain)
            ?? sources.first else { return }
        var draft = PIPConfiguration(kind: .fullScreen)
        draft.target = displays.first { $0.key != source.key }?.key
        onNew(.new(draft, source: .display(source.key)))
    }

    private func delete(_ id: StableID) {
        controller?.endSession(id, reason: nil)
        var value = env.config.value
        guard PIPConfig.remove(id, from: &value) else { return }
        env.config.value = value
    }
}

/// One running picture in picture or stream: Pause and Show/Hide (windows), Stop; Crop… in the row menu.
private struct PIPRunningRow: View {
    let info: PIPSessionInfo
    let controller: PIPController?

    var body: some View {
        let paused = info.state == .paused
        let hidden = info.state == .hidden
        HStack(spacing: 8) {
            Image(systemName: info.kind == .fullScreen ? "rectangle.on.rectangle" : "pip")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(info.state.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if info.kind == .window {
                PIPIconButton(symbol: paused ? "play.fill" : "pause.fill", label: paused ? L("Resume") : L("Pause")) {
                    controller?.setPaused(info.id, !paused)
                }
                PIPIconButton(symbol: hidden ? "eye" : "eye.slash", label: hidden ? L("Show") : L("Hide")) {
                    controller?.setHidden(info.id, !hidden)
                }
            }
            PIPIconButton(symbol: "stop.fill", label: L("Stop")) {
                controller?.endSession(info.id, reason: nil)
            }
        }
        .disabled(controller == nil)
        .contextMenu {
            if info.kind == .window {
                Button(paused ? L("Resume") : L("Pause")) { controller?.setPaused(info.id, !paused) }
                Button(hidden ? L("Show") : L("Hide")) { controller?.setHidden(info.id, !hidden) }
                Button(L("Crop…")) { controller?.beginCrop(info.id) }
                    .disabled(hidden)
                Divider()
            }
            Button(L("Stop")) { controller?.endSession(info.id, reason: nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(info.name)
        .accessibilityValue(info.state.title)
        .accessibilityActions {
            if info.kind == .window {
                Button(L("Crop")) { controller?.beginCrop(info.id) }
            }
        }
    }
}

/// One saved configuration: Start or Stop, and Edit…; Delete… in the row menu.
private struct PIPSavedRow: View {
    let entry: PIPEntry
    let subtitle: String
    let running: Bool
    let available: Bool
    let controller: PIPController?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let c = entry.configuration
        HStack(spacing: 8) {
            Image(systemName: c.kind == .fullScreen ? "rectangle.on.rectangle" : "pip")
                .foregroundStyle(running ? Color.accentColor : Color.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(available || running ? subtitle : L("Not connected") + " · " + subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(running ? L("Stop") : L("Start")) { toggle() }
                .disabled(controller == nil || (!running && !available))
            Button(L("Edit…"), action: onEdit)
        }
        .contextMenu {
            Button(running ? L("Stop") : L("Start")) { toggle() }
                .disabled(controller == nil || (!running && !available))
            Button(L("Edit…"), action: onEdit)
            Divider()
            Button(L("Delete…"), role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(c.name)
        .accessibilityValue(running ? L("Running") : subtitle)
        .accessibilityActions {
            Button(L("Edit"), action: onEdit)
            Button(L("Delete"), action: onDelete)
        }
    }

    private func toggle() {
        if running {
            controller?.endSession(entry.configuration.id, reason: nil)
        } else if SettingsShell.shared.mayStart() {
            controller?.userStart(entry.configuration.id)
        }
    }
}

/// A borderless SF Symbol button with a tooltip and a spoken label.
private struct PIPIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Color lookup tables

/// Import Color Lookup Table… (its file panel is a sheet on the Settings window, never over another sheet) and the
/// imported tables, each with Delete. Needs Filters.
private struct PIPLUTSection: View, ControlDeclaring {
    typealias Controls = PIPPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject var switcher: DisplaysFeatureSwitcher
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var luts: ConfigSlice<DisplaysConfig, [PIPLUTReference]>
    @State private var importing = false
    @State private var message: String?

    init(env: DisplaysPageEnvironment, switcher: DisplaysFeatureSwitcher) {
        self.env = env
        self.switcher = switcher
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _luts = StateObject(wrappedValue: ConfigSlice(env.config, \.pip.luts))
    }

    var body: some View {
        let filtersOn = runtime.isEffective(.pipFilters)
        let list = luts.value
        Section {
            if filtersOn {
                ForEach(list) { lut in
                    HStack(spacing: 8) {
                        Image(systemName: "cube")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(lut.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(L("\(lut.size) points per side"))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        PIPIconButton(symbol: "minus.circle", label: L("Delete \(lut.name)")) { delete(lut.id) }
                    }
                    .contextMenu {
                        Button(L("Delete"), role: .destructive) { delete(lut.id) }
                    }
                }
            }
            ButtonRow(L("Import Color Lookup Table…"),
                      help: L("A 3D .cube file, for the filters of a picture in picture."),
                      control: ControlID("displays.pip.importLUT")) {
                importLUT()
            }
            .disabled(!filtersOn || importing || list.count >= PIPConfig.maxLUTs)
            if !filtersOn {
                SettingsRowNote(L("Color lookup tables need Filters."),
                                fix: StatusAction(title: L("Turn On Filters")) {
                                    switcher.binding([.pipFilters], title: L("Filters")).wrappedValue = true
                                })
            } else if importing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Importing…")).foregroundStyle(.secondary)
                }
            } else if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            if filtersOn && !list.isEmpty {
                Text(L("Color lookup tables"))
                    .modifier(SettingsAnchor(ControlID("displays.pip.luts")))
            }
        }
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = false
        panel.message = L("Choose a 3D color lookup table (.cube).")
        if let type = UTType(filenameExtension: "cube") { panel.allowedContentTypes = [type] }
        // On the Settings window (never over a sheet); app-modal only when that window isn't key.
        if let window = NSApp.keyWindow, window.attachedSheet == nil, !(window is NSPanel) {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    guard response == .OK, let url = panel.url else { return }
                    load(url)
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    /// Parses off the main thread (files up to the LUT store's size limit), then adds the reference.
    private func load(_ url: URL) {
        let path = url.path
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let id = StableID()
        importing = true
        message = nil
        let config = env.config
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CubeLUT, CubeLUTError> in
                do {
                    return .success(try PIPLUTStore.importFile(atPath: path, id: id))
                } catch let error as CubeLUTError {
                    return .failure(error)
                } catch {
                    return .failure(.unreadable)
                }
            }.value
            importing = false
            switch result {
            case .success(let lut):
                let name = lut.title.isEmpty ? fallbackName : lut.title
                if let ref = PIPLUTReference(id: id, name: name, size: lut.size).sanitized(),
                   config.value.pip.luts.count < PIPConfig.maxLUTs {
                    config.value.pip.luts.append(ref)
                    message = L("Imported “\(ref.name)”. Choose it in a picture in picture’s filters.")
                } else {
                    Task.detached(priority: .utility) { PIPLUTStore.delete(id) }
                    message = L("Snaptic can keep up to \(PIPConfig.maxLUTs) lookup tables. Delete one first.")
                }
            case .failure(let error):
                message = error.message
            }
        }
    }

    private func delete(_ id: StableID) {
        var value = env.config.value
        PIPConfig.removeLUT(id, from: &value)
        env.config.value = value
        env.context?.capture.controller?.forgetLUT(id)
        Task.detached(priority: .utility) { PIPLUTStore.delete(id) }
    }
}

// MARK: - Advanced

/// Picture in Picture › Advanced…: Filters, Never capture these apps, pause covered PIPs, the ⌃⌥⌘P switch.
private struct PIPAdvancedSheet: View, ControlDeclaring {
    typealias Controls = PIPPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject var switcher: DisplaysFeatureSwitcher
    @StateObject private var pip: ConfigSlice<DisplaysConfig, PIPConfig>
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>

    init(env: DisplaysPageEnvironment, switcher: DisplaysFeatureSwitcher) {
        self.env = env
        self.switcher = switcher
        _pip = StateObject(wrappedValue: ConfigSlice(env.config, \.pip))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
    }

    var body: some View {
        AdvancedSheet(L("Picture in Picture"),
                      restoreDefaults: RestoreDefaults(scopeName: L("Picture in Picture"), destructive: false) {
                          restoreDefaults()
                      },
                      restoreControl: ControlID("displays.pip.advanced.restoreDefaults")) {
            Section {
                ToggleSetting(L("Filters"),
                              help: L("Color adjustments, effects, and lookup tables for each picture in picture."),
                              isOn: switcher.binding([.pipFilters], title: L("Filters")),
                              anchor: ControlID("displays.pip.advanced.filters"),
                              disabledReason: switcher.unavailableReason([.pipFilters]))
            }
            AppListEditor(L("Never capture these apps"),
                          help: L("Their windows never appear when Snaptic captures a display. Snaptic, Notification Center, and private browser windows are always left out."),
                          bundleIDs: prefixes,
                          anchor: ControlID("displays.pip.advanced.neverCapture"))
            if !PIPPrivacy.isDefaultList(pip.value.protectedBundlePrefixes) {
                Section {
                    ButtonRow(L("Restore Default Apps"),
                              help: L("Password managers and Tor Browser."),
                              control: ControlID("displays.pip.advanced.restoreApps")) {
                        env.config.value.pip.protectedBundlePrefixes = PIPPrivacy.defaultProtectedPrefixes
                    }
                }
            }
            Section {
                ToggleSetting(L("Pause pictures in picture that are covered"),
                              help: L("Saves energy while other windows hide one completely."),
                              isOn: SettingsBinding.store(env.config, \.pip.pauseWhenOccluded),
                              anchor: ControlID("displays.pip.advanced.pauseCovered"))
                ToggleSetting(L("⌃⌥⌘P stops streams"),
                              help: L("Also turns click-through off. Restore All Displays always stops everything."),
                              isOn: SettingsBinding.store(env.config, \.pip.stopHotkeyEnabled),
                              anchor: ControlID("displays.pip.advanced.stopShortcut"))
            }
        }
    }

    /// Bundle ids and prefixes; only valid entries are stored, each once.
    private var prefixes: Binding<[String]> {
        let config = env.config
        return Binding(get: { config.value.pip.protectedBundlePrefixes },
                       set: { list in
                           let clean = PIPPrivacy.sanitizedPrefixes(list)
                           if clean != config.value.pip.protectedBundlePrefixes {
                               config.value.pip.protectedBundlePrefixes = clean
                           }
                       })
    }

    /// The options and the app list go back to their defaults; saved pictures in picture and imported lookup tables
    /// stay. Filters goes back to off through the feature switch (it stops nothing else).
    private func restoreDefaults() {
        var value = env.config.value
        let defaults = PIPConfig()
        value.pip.pauseWhenOccluded = defaults.pauseWhenOccluded
        value.pip.stopHotkeyEnabled = defaults.stopHotkeyEnabled
        value.pip.protectedBundlePrefixes = defaults.protectedBundlePrefixes
        if value != env.config.value { env.config.value = value }
        let filtersDefault = FeatureGraph.isOnByDefault(.pipFilters)
        if FeatureGraph.rawState(.pipFilters, in: features.value) != filtersDefault {
            switcher.binding([.pipFilters], title: L("Filters")).wrappedValue = filtersDefault
        }
    }
}
