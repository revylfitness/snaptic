import AppKit
import SwiftUI
import SnapticKit

/// Settings › Hidden Icons (lead; PLAN 0.4 §4.9, §4.17, A7): the header switch "Use Hidden Icons", the status row and
/// its notes, automatic hiding, launch hiding, Always Hidden, Section dividers, the shortcut, Sections ›, How to
/// Arrange…, and the footer's Restore Defaults… and Advanced…. While the module is off it shows what it does.
/// Turning it on here opens the How to Arrange sheet (§4.0).
struct IconsPage: View, ControlDeclaring {
    typealias Controls = IconsPageControls

    let module: IconsModule

    static let title = L("Hidden Icons")
    static let summary = IconsPageRules.summary
    static let symbol = "eye.slash.fill"
    static let tint = SettingsTint.teal
    static let route = SettingsRoute(SettingsRootID.hiddenIcons)

    /// Shown while Hidden Icons is off (the module's `highlights`).
    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "icons.hide", symbol: "eye.slash.fill", title: L("Hide the icons you don’t need"),
                         text: L("Click the arrow to hide the icons to its left, and click it again to show them.")),
        FeatureHighlight(id: "icons.alwaysHidden", symbol: "lock.fill",
                         title: L("Keep some icons hidden even when shown"),
                         text: L("Icons left of the ⋮ divider stay hidden until you Option-click the arrow.")),
        FeatureHighlight(id: "icons.list", symbol: "list.bullet", title: L("Open hidden icons from the Snaptic menu"),
                         text: L("Choose a hidden icon to open its menu without showing them all.")),
    ]

    /// The Settings sidebar root (`IconsModule.settingsRoot()`).
    @MainActor static func settingsRoot(module: IconsModule) -> SettingsRoot {
        SettingsRoot(id: SettingsRootID.hiddenIcons, title: title, symbol: symbol, tint: tint) {
            AnyView(IconsPage(module: module))
        }
    }

    /// Search entries from the control tables (`IconsModule.settingsIndex()`).
    static func searchEntries() -> [SettingsSearchEntry] {
        SettingsIndex.entries(ControlRegistry.tables, root: SettingsRootID.hiddenIcons)
    }

    var body: some View {
        if let host = SettingsShell.shared.host {
            IconsRootContent(module: module, host: host)
        } else {
            UnavailablePage()
        }
    }
}

// MARK: - Root content

private struct IconsRootContent: View {
    let module: IconsModule
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var modules: ConfigStore<ModulesConfig>
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var config: ConfigStore<IconsConfig>
    @ObservedObject private var apps: ConfigStore<IconsAppsState>

    init(module: IconsModule, host: ModuleHost) {
        self.module = module
        _host = ObservedObject(wrappedValue: host)
        _modules = ObservedObject(wrappedValue: host.modulesStore)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _config = ObservedObject(wrappedValue: module.config)
        _apps = ObservedObject(wrappedValue: module.apps)
    }

    var body: some View {
        let blocked = host.disabledByDefaults.contains(.hiddenIcons)
        let enabled = !blocked && modules.value.isEnabled(.hiddenIcons)
        let running = host.isRunning(.hiddenIcons) && module.state == .running
        SettingsPageScaffold(route: IconsPage.route) {
            SettingsPageHeader(IconsPage.title, summary: IconsPage.summary, symbol: IconsPage.symbol,
                               tint: IconsPage.tint, isOn: useHiddenIcons, switchLabel: L("Use Hidden Icons"),
                               control: ControlID("icons.page.useHiddenIcons"))
                .disabled(blocked)
            if blocked {
                Section {
                    DefaultsLockRow(module: .hiddenIcons)
                }
            }
            if !enabled {
                FeatureHighlights(IconsPage.highlights)
            } else if running {
                mainSection
            } else {
                Section {
                    if case .degraded(let reason) = module.state {
                        StatusRow(reason, style: .warning)
                    } else {
                        StatusRow(L("Starting…"))
                    }
                }
            }
            PageFooterButtons(advanced: enabled && running ? openAdvanced : nil, help: IconsPage.route,
                              restoreDefaults: enabled ? restore : nil,
                              advancedControl: ControlID("icons.page.advanced"),
                              restoreControl: ControlID("icons.page.restore"))
        }
        .sheet(isPresented: shell.sheetBinding(IconsAdvancedSheetControls.sheet)) {
            IconsAdvancedSheet(module: module)
        }
        .sheet(isPresented: shell.sheetBinding(IconsPageControls.arrangeSheet)) {
            IconsArrangeSheet(engine: module.engineKind ?? IconsArrangeSheet.engineForThisMac,
                              alwaysHidden: config.value.alwaysHidden)
        }
    }

    // MARK: Rows

    @ViewBuilder private var mainSection: some View {
        let value = config.value
        let engine = module.engineKind
        Section {
            statusRow(IconsPageRules.status(module.pageFacts()))
            ToggleSetting(IconsPageRules.autoCollapseTitle(value.autoCollapseSeconds),
                          isOn: SettingsBinding.store(config, \.autoCollapse),
                          anchor: ControlID("icons.page.autoCollapse"))
            if value.autoCollapse {
                StepperSetting(L("Seconds"), value: SettingsBinding.store(config, \.autoCollapseSeconds),
                               in: IconsConfig.autoCollapseRange, step: 5,
                               defaultValue: IconsConfig.defaultAutoCollapseSeconds, format: .seconds)
                    .padding(.leading, 20)
            }
            ToggleSetting(IconsPageRules.launchTitle, help: IconsPageRules.launchHelp,
                          isOn: SettingsBinding.store(config, \.collapseAtLaunch),
                          anchor: ControlID("icons.page.collapseAtLaunch"))
            ToggleSetting(IconsPageRules.alwaysHiddenTitle, help: IconsPageRules.alwaysHiddenHelp,
                          isOn: SettingsBinding.store(config, \.alwaysHidden),
                          anchor: ControlID("icons.page.alwaysHidden"))
            if let engine, IconsPageRules.showsDividers(engine: engine, alwaysHidden: value.alwaysHidden) {
                ToggleSetting(IconsPageRules.dividersTitle, help: IconsPageRules.dividersHelp(engine),
                              isOn: SettingsBinding.store(config, \.dividers),
                              anchor: ControlID("icons.page.dividers"))
            }
            ShortcutSetting(IconsPageRules.shortcutTitle, combo: SettingsBinding.store(config, \.shortcut),
                            owner: IconsPageRules.shortcutName, anchor: ControlID("icons.page.shortcut"))
            NavigationRow(L("Sections"), symbol: "rectangle.split.3x1", tint: .teal,
                          value: IconsPageRules.sectionsValue(hidden: module.hiddenCount,
                                                              choices: choiceCount(engine)),
                          route: IconsSectionsPage.route, control: ControlID("icons.page.sections"))
            ButtonRow(L("How to Arrange…"), control: ControlID("icons.page.howToArrange")) {
                shell.openSheet = IconsPageControls.arrangeSheet
            }
        }
    }

    /// Choices count on Native only (14–26 keeps them unused).
    private func choiceCount(_ engine: IconsEngineKind?) -> Int {
        engine == .native ? apps.value.choices.count : 0
    }

    @ViewBuilder private func statusRow(_ status: IconsStatus) -> some View {
        StatusRow(status.text, style: status.warning ? .warning : .info,
                  actions: status.action.map { [statusAction($0)] } ?? [])
        ForEach(Array(status.notes.enumerated()), id: \.offset) { _, note in
            if note.warning {
                SettingsRowNote(note.text)
            } else {
                Text(note.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusAction(_ action: IconsStatusAction) -> StatusAction {
        let module = self.module
        let shell = self.shell
        switch action {
        case .showIcons:
            return StatusAction(title: action.title, control: ControlID("icons.page.showIcons")) {
                module.perform(.show, from: .settings)
            }
        case .hideIcons:
            return StatusAction(title: action.title, control: ControlID("icons.page.hideIcons")) {
                module.perform(.hide, from: .settings)
            }
        case .openPrivacy:
            return StatusAction(title: action.title, control: ControlID("icons.page.openPrivacy")) {
                module.openPrivacy()
            }
        case .relaunch:
            return StatusAction(title: action.title, control: ControlID("icons.page.relaunch")) {
                module.relaunch()
            }
        case .showArrow, .showDivider, .showAlwaysHiddenDivider:
            return StatusAction(title: action.title, control: ControlID("icons.page.showArrow")) {
                module.showMissingItems()
            }
        case .tryAgain:
            return StatusAction(title: action.title, control: ControlID("icons.page.tryAgain")) {
                module.clearDisabledBuild()
            }
        case .arrangeNow:
            return StatusAction(title: action.title, control: ControlID("icons.page.arrangeNow")) {
                shell.openSheet = IconsPageControls.arrangeSheet
            }
        }
    }

    // MARK: Footer and switch

    private var openAdvanced: (() -> Void)? {
        let shell = self.shell
        return { shell.openSheet = IconsAdvancedSheetControls.sheet }
    }

    private var restore: RestoreDefaults {
        let config = self.config
        let apps = self.apps
        return RestoreDefaults(title: L("Restore Defaults…"), question: IconsPageRules.restoreTitle,
                               message: IconsPageRules.restoreMessage, button: L("Restore Defaults"),
                               destructive: false) {
            config.value = config.value.restoringDefaults()
            apps.value = apps.value.restoringDefaults()
        }
    }

    /// Turning Hidden Icons on here also opens How to Arrange (§4.0).
    private var useHiddenIcons: Binding<Bool> {
        let module = shell.moduleEnabled(.hiddenIcons)
        let shell = self.shell
        return Binding(get: { module.wrappedValue }, set: { on in
            let wasOn = module.wrappedValue
            module.wrappedValue = on
            if on, !wasOn { shell.openSheet = IconsPageControls.arrangeSheet }
        })
    }
}
