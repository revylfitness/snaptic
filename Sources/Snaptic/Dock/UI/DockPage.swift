import SwiftUI
import SnapticKit

/// Settings › Dock Previews (lead; PLAN 0.5 §4.17, §4.18, §4.11, A7): the header switch "Use Dock Previews", the
/// status row and its added rows (Kit `DockPageRules` over `DockPreviewsModule.pageFacts`), the Previews and Dock
/// click actions sections, and the footer's Restore Defaults… and Advanced…. Rows 1 and 2 (kill switch, off) show
/// their row and the footer's (?) only; Starting and rows 3 to 9 show the controls and the full footer, so a paused
/// module can still be set up.
struct DockPage: View, ControlDeclaring {
    typealias Controls = DockPageControls

    let module: DockPreviewsModule

    static let title = L("Dock Previews")
    static let summary = L("See an app’s windows when you point at it in the Dock.")
    static let symbol = "dock.rectangle"
    static let tint = SettingsTint.green
    static let route = SettingsRoute(SettingsRootID.dockPreviews)

    /// Shown while Dock Previews is off (the module's `highlights`; §4.18).
    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "dock.point", symbol: "dock.rectangle", title: L("Point at an app in the Dock"),
                         text: L("Its windows appear next to the Dock, including minimized and hidden ones.")),
        FeatureHighlight(id: "dock.click", symbol: "macwindow.on.rectangle",
                         title: L("Click a window to bring it forward"),
                         text: L("Or close, minimize, or quit from the preview.")),
        FeatureHighlight(id: "dock.titles", symbol: "text.below.photo", title: L("Works without Screen Recording"),
                         text: L("Without it, previews show window titles instead of pictures.")),
    ]

    /// The Settings sidebar root (`DockPreviewsModule.settingsRoot()`).
    @MainActor static func settingsRoot(module: DockPreviewsModule) -> SettingsRoot {
        SettingsRoot(id: SettingsRootID.dockPreviews, title: title, symbol: symbol, tint: tint) {
            AnyView(DockPage(module: module))
        }
    }

    /// Search entries from the control tables (`DockPreviewsModule.settingsIndex()`).
    static func searchEntries() -> [SettingsSearchEntry] {
        SettingsIndex.entries(ControlRegistry.tables, root: SettingsRootID.dockPreviews)
    }

    var body: some View {
        if let host = SettingsShell.shared.host {
            DockRootContent(module: module, host: host)
        } else {
            UnavailablePage()
        }
    }
}

// MARK: - Root content

private struct DockRootContent: View {
    let module: DockPreviewsModule
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var modules: ConfigStore<ModulesConfig>
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var config: ConfigStore<DockConfig>
    /// Bumped when a window feature stops or is tried again (§4.17's crash-guard rows).
    @State private var stopsTick = 0

    init(module: DockPreviewsModule, host: ModuleHost) {
        self.module = module
        _host = ObservedObject(wrappedValue: host)
        _modules = ObservedObject(wrappedValue: host.modulesStore)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _config = ObservedObject(wrappedValue: module.config)
    }

    var body: some View {
        let _ = stopsTick
        let blocked = host.disabledByDefaults.contains(.dockPreviews)
        let enabled = !blocked && modules.value.isEnabled(.dockPreviews)
        let status = DockPageRules.status(module.pageFacts(killSwitch: blocked, enabled: enabled))
        // The host hasn't started the module yet: nothing is read, so the row is Starting (§4.17).
        let started = host.isRunning(.dockPreviews) && module.state != .stopped
        SettingsPageScaffold(route: DockPage.route) {
            SettingsPageHeader(DockPage.title, summary: DockPage.summary, symbol: DockPage.symbol, tint: DockPage.tint,
                               isOn: shell.moduleEnabled(.dockPreviews), switchLabel: L("Use Dock Previews"),
                               control: ControlID("dock.page.useDockPreviews"))
                .disabled(blocked)
            switch status.row {
            case .killSwitch:
                Section {
                    DefaultsLockRow(module: .dockPreviews)
                }
            case .off:
                FeatureHighlights(DockPage.highlights)
            default:
                if started {
                    statusSection(status)
                } else {
                    Section {
                        StatusRow(L("Starting…"))
                    }
                }
                previewsSection
                clickActionsSection
            }
            PageFooterButtons(advanced: enabled ? openAdvanced : nil, help: DockPage.route,
                              restoreDefaults: enabled ? restore : nil,
                              advancedControl: ControlID("dock.page.advanced"),
                              restoreControl: ControlID("dock.page.restore"))
        }
        .sheet(isPresented: shell.sheetBinding(DockAdvancedSheetControls.sheet)) {
            DockAdvancedSheet(module: module)
        }
        .onReceive(NotificationCenter.default.publisher(for: PrivateWindowAPI.stopsChanged)) { _ in stopsTick += 1 }
    }

    // MARK: Status row and added rows (§4.17)

    @ViewBuilder private func statusSection(_ status: DockPageStatus) -> some View {
        if status.text != nil || !status.notes.isEmpty {
            Section {
                if let text = status.text {
                    StatusRow(text, style: status.warning ? .warning : .info,
                              actions: status.action.map { [action($0)] } ?? [])
                }
                ForEach(Array(status.notes.enumerated()), id: \.offset) { _, note in
                    StatusRow(note.text, style: note.warning ? .warning : .info,
                              actions: note.action.map { [action($0, note: note)] } ?? [])
                }
            }
        }
    }

    /// The status row's button, or an added row's (`note`): the same action can mean a different permission or a
    /// stopped feature there.
    private func action(_ action: DockPageAction, note: DockPageNote? = nil) -> StatusAction {
        let module = self.module
        switch action {
        case .openPrivacy where note != nil:
            return StatusAction(title: action.title, control: ControlID("dock.page.thumbnailsPrivacy")) {
                module.openPrivacy(.screenRecording)
            }
        case .openPrivacy:
            return StatusAction(title: action.title, control: ControlID("dock.page.openPrivacy")) {
                module.openPrivacy(.accessibility)
            }
        case .tryAgain:
            if let name = note?.feature {
                let feature = WindowFeature.allCases.first { $0.displayName == name }
                return StatusAction(title: action.title, control: ControlID("dock.page.crashGuardTryAgain")) {
                    if let feature { module.tryAgain(feature) }
                }
            }
            return StatusAction(title: action.title, control: ControlID("dock.page.tryAgain")) {
                module.tryAgain()
            }
        case .advancedOtherTools:
            return StatusAction(title: action.title, control: ControlID("dock.page.otherToolAdvanced")) {
                openAdvanced(at: DockAdvancedAnchor.otherTools)
            }
        case .advancedVoiceOver:
            return StatusAction(title: action.title, control: ControlID("dock.page.voiceOverAdvanced")) {
                openAdvanced(at: DockAdvancedAnchor.voiceOver)
            }
        case .resume:
            return StatusAction(title: action.title, control: ControlID("dock.page.resume")) {
                module.resumeCommandPause()
            }
        case .relaunch:
            return StatusAction(title: action.title, control: ControlID("dock.page.relaunch")) {
                module.relaunch()
            }
        }
    }

    // MARK: Previews (§4.18 rows 1–5)

    @ViewBuilder private var previewsSection: some View {
        Section {
            SliderSetting(L("Show previews after"), help: L("How long you point at an app before its windows appear."),
                          value: delay, in: 0...DockConfig.delayPosition(DockConfig.delayRange.upperBound), step: 1,
                          defaultValue: DockConfig.delayPosition(DockConfig.defaultDelay), format: .seconds,
                          anchor: ControlID("dock.page.delay"),
                          labels: DockConfig.delayLabels(decimalSeparator: SettingsFormat.decimalSeparator))
            PickerSetting(L("Card size"), selection: SettingsBinding.store(config, \.cardSize),
                          options: [PickerOption(DockCardSize.small, L("Small")),
                                    PickerOption(DockCardSize.medium, L("Medium")),
                                    PickerOption(DockCardSize.large, L("Large"))],
                          style: .segmented, defaultValue: DockConfig().cardSize,
                          anchor: ControlID("dock.page.cardSize"))
            ToggleSetting(L("Window thumbnails"),
                          help: L("Pictures of your windows. Off: titles only, and no Screen Recording needed."),
                          isOn: SettingsBinding.store(config, \.thumbnails), anchor: ControlID("dock.page.thumbnails"))
            ToggleSetting(L("Include minimized and hidden windows"),
                          help: L("Lists windows that are minimized or belong to hidden apps."),
                          isOn: SettingsBinding.store(config, \.includeMinimizedAndHidden),
                          anchor: ControlID("dock.page.includeMinimizedAndHidden"))
            ToggleSetting(L("Windows on other Spaces"), help: L("Off: only windows on the current Space are shown."),
                          isOn: SettingsBinding.store(config, \.otherSpaces),
                          anchor: ControlID("dock.page.otherSpaces"))
        } header: {
            Text(L("Previews"))
        } footer: {
            Text(L("macOS may show its screen-recording indicator or a reminder while thumbnails are taken."))
                .foregroundStyle(.secondary)
        }
    }

    /// The slider moves in tenths of a second (`DockConfig.delayPosition`), so its positions are 0…10 with ticks.
    private var delay: Binding<Double> {
        let config = self.config
        return Binding(get: { DockConfig.delayPosition(config.value.delay) }, set: { position in
            let seconds = DockConfig.delay(atPosition: position)
            if config.value.delay != seconds { config.value.delay = seconds }
        })
    }

    // MARK: Dock click actions (§4.11; §4.18 rows 6–7)

    @ViewBuilder private var clickActionsSection: some View {
        // Read live: the lock row shows as soon as the key is set (the tap itself reads it on each mouse-up).
        let killed = DockPreviewsModule.readKillSwitches(.standard).contains(.clickActions)
        Section {
            PickerSetting(L("When you click the active app in the Dock"),
                          help: L("Hide works like pressing ⌘H. Minimize sends each of its windows to the Dock."),
                          selection: SettingsBinding.store(config, \.clickActions),
                          options: [PickerOption(DockClickAction.doNothing, L("Do Nothing")),
                                    PickerOption(DockClickAction.hideApp, L("Hide the App")),
                                    PickerOption(DockClickAction.minimizeWindows, L("Minimize Its Windows"))],
                          style: .popUp, defaultValue: DockConfig().clickActions,
                          anchor: ControlID("dock.page.clickActions"))
                .disabled(killed)
            ToggleSetting(L("Restore all minimized windows"),
                          help: L("When all of an app’s windows are minimized, clicking its Dock icon brings them all back."),
                          isOn: SettingsBinding.store(config, \.restoreAllMinimized),
                          anchor: ControlID("dock.page.restoreAllMinimized"))
                .disabled(killed)
            if killed {
                DefaultsLockRow(key: KillSwitches.key(prefix: "Dock", id: DockFeature.clickActions.rawValue))
                    .modifier(SettingsAnchor(ControlID("dock.page.clickActionsLock")))
            }
        } header: {
            Text(L("Dock click actions"))
        } footer: {
            Text(L("Snaptic only watches Dock clicks. The Dock still handles every click as usual."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var openAdvanced: (() -> Void)? {
        let shell = self.shell
        return { shell.openSheet = DockAdvancedSheetControls.sheet }
    }

    /// Rows 6 and 7's [Advanced…]: the sheet opens at the row's setting, highlighted (§4.15, §4.17).
    private func openAdvanced(at anchor: String) {
        if let entry = SettingsIndex.anchorEntry(anchor, root: SettingsRootID.dockPreviews, in: ControlRegistry.tables) {
            shell.reveal(entry)
        } else {
            shell.openSheet = DockAdvancedSheetControls.sheet
        }
    }

    /// Every Dock Previews setting, Advanced included; never the shared privacy settings (§4.10, §4.18).
    private var restore: RestoreDefaults {
        let config = self.config
        return RestoreDefaults(title: L("Restore Defaults…"),
                               question: L("Restore Dock Previews settings to their defaults?"),
                               message: L("Preview, Dock click, and Advanced settings go back to their defaults. Dock Previews stays on. Protect private windows and its app list stay as they are, because the Window Switcher uses them too."),
                               button: L("Restore Defaults"), destructive: false) {
            config.value = DockConfig()
        }
    }
}

/// The Advanced sheet rows that rows 6 and 7 open at (`DockAdvancedSheetControls`).
enum DockAdvancedAnchor {
    static let otherTools = "dock.advanced.otherTools"
    static let voiceOver = "dock.advanced.voiceOver"
}
