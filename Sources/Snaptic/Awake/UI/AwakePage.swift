import AppKit
import IOKit.ps
import SwiftUI
import SnapticKit

/// What the Awake pages and sheets read and act on (owner: G; PLAN 0.3 §4.3): the module's stores and runtime, which
/// live as long as the app, and, while the module runs, its context. AwakeModule builds one and keeps it.
@MainActor final class AwakePageEnvironment: ObservableObject {
    let config: ConfigStore<AwakeConfig>
    let history: ConfigStore<AwakeHistory>
    let runtime: AwakeRuntimeState
    /// Custom… and Add Time… from the status row; its starts are `.settings` (UI starts, R5-8).
    let custom = CustomSessionWindow(source: .settings)
    /// A rule the Awake menu asked to open (AwakeRuleLink); the page opens its editor and clears it.
    @Published var pendingRule: StableID?
    private let contextProvider: @MainActor () -> AwakeContext?

    init(config: ConfigStore<AwakeConfig>, history: ConfigStore<AwakeHistory>, runtime: AwakeRuntimeState,
         context: @escaping @MainActor () -> AwakeContext?) {
        self.config = config
        self.history = history
        self.runtime = runtime
        contextProvider = context
    }

    /// The running module's context; nil while Awake is off, starting or stopped.
    var context: AwakeContext? {
        guard runtime.moduleState == .running else { return nil }
        return contextProvider()
    }

    /// Custom… (start) or Add Time… (extend) in the small panel.
    func presentCustom(_ mode: CustomSessionPanel.Mode) {
        guard let ctx = context else { return }
        custom.context = ctx
        custom.present(mode)
    }
}

/// Whether this Mac has a built-in battery (the "End sessions automatically" section is for laptops only). The
/// runtime's power facts answer while Awake runs; this IOPS read answers before that, once per process.
@MainActor enum AwakeHardware {
    static let hasBattery: Bool = {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        return list.contains { ps in
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else {
                return false
            }
            return d["Type"] as? String == "InternalBattery"
        }
    }()
}

/// The Awake page (owner: G; PLAN 0.3 §4.3 "Awake", R5-9, R5-10, R5-11): header switch "Use Awake", the status row
/// (every session kind starts from here alone), Sessions, End sessions automatically and Lid closed (laptops; the
/// latter from 0.3.3), Start automatically, Keyboard, Drives › and History ›, and the footer. Rendered whether or not
/// Awake runs; while it is off it shows what it does.
struct AwakePage: View, ControlDeclaring {
    typealias Controls = AwakePageControls

    private let env: AwakePageEnvironment

    static let title = L("Awake")
    static let summary = L("Keep your Mac awake for a while, or automatically when certain conditions are met.")
    static let symbol = "cup.and.saucer.fill"
    static let tint = SettingsTint.orange

    /// Shown while Awake is off (the module's `highlights`).
    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "awake.sessions", symbol: "cup.and.saucer.fill", title: L("Keep your Mac awake for a while"),
                         text: L("For an hour, until a set time, while an app is running, or until a download finishes.")),
        FeatureHighlight(id: "awake.rules", symbol: "wand.and.stars", title: L("Start automatically"),
                         text: L("While a display is connected, on a schedule, on power, and in other situations you choose.")),
        FeatureHighlight(id: "awake.guards", symbol: "battery.50percent", title: L("Ends on its own"),
                         text: L("Sessions end when the battery runs low or your Mac gets too hot.")),
    ]

    init(env: AwakePageEnvironment) { self.env = env }

    /// The Settings sidebar root (`AwakeModule.settingsRoot()`).
    @MainActor static func settingsRoot(env: AwakePageEnvironment) -> SettingsRoot {
        SettingsRoot(id: SettingsRootID.awake, title: title, symbol: symbol, tint: tint) {
            AnyView(AwakePage(env: env))
        }
    }

    /// The History sub-page (`AwakeModule.settingsDestination(_:)` routes `awake.history` here; J's Drives page is
    /// `awake.drives`).
    @MainActor static func historyPage(env: AwakePageEnvironment) -> AnyView {
        AnyView(AwakeHistoryPage(env: env))
    }

    /// Awake's search entries, derived from its control tables (R5-13; `AwakeModule.settingsIndex()`).
    static func searchEntries() -> [SettingsSearchEntry] {
        SettingsIndex.entries(ControlRegistry.tables, root: SettingsRootID.awake)
    }

    var body: some View {
        if let host = SettingsShell.shared.host {
            AwakeRootContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

/// The Awake menus' way into the rules (§5.3): "Edit Rules…" reveals the Start automatically list, a rule row also
/// opens that rule's editor (the page consumes `AwakePageEnvironment.pendingRule` when it appears or while it shows).
@MainActor enum AwakeRuleLink {
    /// Opens Settings on Awake, scrolls to the rules and, for `rule`, opens its editor.
    static func open(rule: StableID?, host: AwakeHost) {
        let module = SettingsShell.shared.host?.modules.first { $0.id == .awake } as? AwakeModule
        module?.pageEnvironment.pendingRule = rule
        host.openSettings(SettingsRoute(SettingsRootID.awake))
        let anchor = AwakePageControls.rulesAnchor
        SettingsShell.shared.reveal(SettingsSearchEntry(id: anchor, title: L("Start automatically"),
                                                        root: SettingsRootID.awake, anchor: anchor,
                                                        sheet: rule == nil ? nil : TriggerEditorSheetControls.sheet))
    }
}

/// A rule the editor works on.
enum AwakeRuleEditTarget: Identifiable, Equatable {
    case new(StableID)
    case existing(StableID)

    var id: StableID {
        switch self {
        case .new(let id), .existing(let id): return id
        }
    }
}

// MARK: - Root content

private struct AwakeRootContent: View {
    let env: AwakePageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var modules: ConfigStore<ModulesConfig>
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: AwakeRuntimeState
    @StateObject private var triggers: ConfigSlice<AwakeConfig, AwakeTriggersConfig>
    @State private var confirmTurnOff = false
    @State private var editing: AwakeRuleEditTarget?

    init(env: AwakePageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _modules = ObservedObject(wrappedValue: host.modulesStore)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _triggers = StateObject(wrappedValue: ConfigSlice(env.config, \.triggers))
    }

    var body: some View {
        let blocked = host.disabledByDefaults.contains(.awake)
        let enabled = !blocked && modules.value.isEnabled(.awake)
        let context = host.isRunning(.awake) ? env.context : nil
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.awake)) {
            SettingsPageHeader(AwakePage.title, summary: AwakePage.summary, symbol: AwakePage.symbol,
                               tint: AwakePage.tint, isOn: useAwake, switchLabel: L("Use Awake"),
                               control: ControlID("awake.page.useAwake"))
                .disabled(blocked)
            if blocked {
                Section {
                    DefaultsLockRow(module: .awake)
                }
            }
            // 0.3.1 B3.4 (lead decision): the host's leftover rows show whatever Awake's state, also while it's off.
            AwakeLidLeftoverSection(recovery: host.lidRecovery)
            if !enabled {
                FeatureHighlights(AwakePage.highlights)
            } else if let context {
                if host.safeMode.isActive {
                    // ux N2: Safe Mode removes rules, activity and Drive Alive only; sessions still run. One leave
                    // confirmation everywhere (ux N5, H's SafeModeLeave).
                    Section {
                        StatusRow(AwakeFeatureLock.safeModeStatus, style: .warning, actions: [
                            StatusAction(title: L("Leave Safe Mode…"), control: ControlID("awake.page.leaveSafeMode")) {
                                SafeModeLeave.confirm(relauncher: host.relauncher)
                            },
                        ])
                    }
                }
                AwakeStatusSection(env: env, context: context)
                AwakeSessionsSection(env: env)
                if runtime.power?.batteryPresent ?? AwakeHardware.hasBattery {
                    AwakeBatterySection(env: env)
                    AwakeLidSection(env: env)
                }
                rulesSection
                if runtime.isEffective(.shortcuts) {
                    Section {
                        ButtonRow(L("Keyboard Shortcuts…"), control: ControlID("awake.page.shortcuts")) {
                            shell.openSheet = AwakePageControls.shortcutsSheet
                        }
                    } header: {
                        Text(L("Keyboard"))
                    }
                }
                AwakeNavigationSection(env: env)
            } else {
                Section {
                    if case .degraded(let reason) = runtime.moduleState {
                        StatusRow(reason, style: .warning)
                    } else {
                        StatusRow(L("Starting…"))
                    }
                }
            }
            PageFooterButtons(advanced: enabled && context != nil ? openAdvanced : nil,
                              help: SettingsRoute(SettingsRootID.awake),
                              advancedControl: ControlID("awake.page.advanced"))
        }
        .alert(L("Turn off Awake?"), isPresented: $confirmTurnOff) {
            Button(L("Turn Off"), role: .destructive) { shell.moduleEnabled(.awake).wrappedValue = false }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This ends the current session and stops automatic sessions."))
        }
        .sheet(isPresented: shell.sheetBinding(AwakeAdvancedSheetControls.sheet)) {
            AwakeAdvancedSheet(env: env)
        }
        .sheet(isPresented: shell.sheetBinding(PresetEditorSheetControls.sheet)) {
            PresetEditorSheet(env: env)
        }
        .sheet(isPresented: shell.sheetBinding(AwakePageControls.shortcutsSheet)) {
            AwakeShortcutsSheet(env: env)
        }
        .onReceive(env.$pendingRule) { id in
            guard let id else { return }
            env.pendingRule = nil
            if triggers.value.triggers.contains(where: { $0.id == id }) { editing = .existing(id) }
        }
        .sheet(isPresented: shell.sheetBinding(TriggerEditorSheetControls.sheet)) {
            if let target = editing ?? env.pendingRule.map(AwakeRuleEditTarget.existing) {
                TriggerEditorSheet(env: env, target: target)
            } else {
                Color.clear.frame(width: 1, height: 1).onAppear { shell.openSheet = nil }
            }
        }
    }

    /// Opens the rule editor through the shell (one sheet at a time, §4.3).
    private func edit(_ target: AwakeRuleEditTarget) {
        editing = target
        shell.openSheet = TriggerEditorSheetControls.sheet
    }

    private var openAdvanced: (() -> Void)? {
        let shell = self.shell
        return { shell.openSheet = AwakeAdvancedSheetControls.sheet }
    }

    /// The header switch: turning Awake off while a session or an enabled rule exists asks first (§4.3 "Turn-off
    /// confirmation"; the only copy of that text).
    private var useAwake: Binding<Bool> {
        let module = shell.moduleEnabled(.awake)
        let runtime = env.runtime
        let config = env.config
        return Binding(get: { module.wrappedValue }, set: { on in
            let busy = runtime.governing.isActive || config.value.triggers.triggers.contains { $0.enabled }
            if !on && module.wrappedValue && busy {
                confirmTurnOff = true
            } else {
                module.wrappedValue = on
            }
        })
    }

    // MARK: Start automatically (design M4: no section switch; Add Rule… turns rules on)

    @ViewBuilder private var rulesSection: some View {
        let list = triggers.value.triggers
        // ux N2: rules removed by Safe Mode or `Awake.disable.triggers` say so, and no new rule can be added.
        let lock = AwakeFormat.lock([.triggers])
        Section {
            if let lock {
                if lock.lock == .killSwitch {
                    DefaultsLockRow(key: KillSwitches.key(prefix: "Awake", id: AwakeFeature.triggers.rawValue))
                } else {
                    StatusRow(AwakeFeatureLock.rulesNote(lock.lock))
                }
            }
            if list.isEmpty {
                Text(L("Keep your Mac awake automatically, for example while a display is connected."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ReorderableList(SettingsBinding.store(env.config, \.triggers.triggers),
                                onEdit: { rule in edit(.existing(rule.id)) }, onDelete: nil) { rule in
                    AwakeRuleRow(rule: rule, runtime: runtime) { edit(.existing(rule.id)) }
                }
            }
            ButtonRow(L("Add Rule…"), control: ControlID("awake.page.addRule")) {
                edit(.new(StableID()))
            }
            .disabled(list.count >= AwakeTrigger.maxTriggers || lock != nil)
        } header: {
            Text(L("Start automatically"))
                .modifier(SettingsAnchor(ControlID("awake.page.rules")))
        } footer: {
            if list.count > 1 {
                Text(L("Higher in the list wins."))
            }
        }
    }
}

/// "Your Mac can’t sleep…" with Turn Sleep Back On…, Keep Sleep Off and Not Now (0.3.1 B3.4), while a leftover shows.
private struct AwakeLidLeftoverSection: View {
    @ObservedObject var recovery: LidRecoveryState

    var body: some View {
        if recovery.showsRows {
            Section {
                LidLeftoverRow(recovery: recovery, restore: ControlID("awake.page.status.lidRestore"),
                               keepOff: ControlID("awake.page.status.lidKeepOff"),
                               dismiss: ControlID("awake.page.status.lidDismiss"))
            }
        }
    }
}

/// One rule: name, its conditions as a sentence, and "Active" / "Waiting" / "Off"; a click opens the editor.
private struct AwakeRuleRow: View {
    let rule: AwakeTrigger
    @ObservedObject var runtime: AwakeRuntimeState
    let open: @MainActor () -> Void

    var body: some View {
        let state = AwakeRuleRowText.state(enabled: rule.enabled, active: runtime.activeTriggerIDs.contains(rule.id),
                                           waiting: runtime.waitingTriggerIDs.contains(rule.id))
        Button {
            open()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.displayName(AwakeFormat.text))
                        .foregroundStyle(rule.enabled ? Color.primary : Color.secondary)
                    if !rule.name.isEmpty {
                        Text(TriggerEngine.summary(rule, text: AwakeFormat.text))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let state {
                    Text(state)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rule.displayName(AwakeFormat.text))
        .accessibilityValue(state ?? "")
        .accessibilityHint(L("Opens the rule."))
    }
}

// MARK: - Sessions

private struct AwakeSessionsSection: View {
    let env: AwakePageEnvironment
    @StateObject private var sessions: ConfigSlice<AwakeConfig, AwakeSessionsConfig>
    @ObservedObject private var shell = SettingsShell.shared

    init(env: AwakePageEnvironment) {
        self.env = env
        _sessions = StateObject(wrappedValue: ConfigSlice(env.config, \.sessions))
    }

    var body: some View {
        let value = sessions.value
        let indefinite = AwakeSessionsConfig.derivedPresetID("indefinite")
        Section {
            PickerSetting(L("Default session"), help: L("Starts when you click Keep Awake or press its shortcut."),
                          selection: defaultSession,
                          options: value.presets.map { PickerOption($0.id, $0.title(AwakeFormat.text)) },
                          style: .popUp,
                          defaultValue: value.presets.contains { $0.id == indefinite } ? indefinite : nil,
                          anchor: ControlID("awake.page.defaultSession"))
            ToggleSetting(L("Keep the display on"), help: L("When off, your Mac stays awake but the display can turn off."),
                          isOn: keepDisplayOn, anchor: ControlID("awake.page.keepDisplayOn"))
            SettingRow(L("Sessions in the menu"), help: L("The sessions Keep Awake and the Awake menu offer, in order."),
                       anchor: ControlID("awake.page.sessions")) {
                Button(L("Edit…")) { shell.openSheet = PresetEditorSheetControls.sheet }
            }
        } header: {
            Text(L("Sessions"))
        }
    }

    private var defaultSession: Binding<StableID> {
        let config = env.config
        return Binding(get: { config.value.sessions.defaultPreset.id },
                       set: { id in
                           if config.value.sessions.defaultPresetID != id { config.value.sessions.defaultPresetID = id }
                       })
    }

    /// R5-11: applies to every session that uses default options, a running one at once.
    private var keepDisplayOn: Binding<Bool> {
        let config = env.config
        return Binding(get: { config.value.sessions.defaultOptions.display != .maySleep },
                       set: { on in
                           let next = config.value.settingKeepDisplayOn(on)
                           if next != config.value { config.value = next }
                       })
    }
}

// MARK: - End sessions automatically (laptops)

private struct AwakeBatterySection: View {
    let env: AwakePageEnvironment
    @StateObject private var guards: ConfigSlice<AwakeConfig, AwakeGuardsConfig>

    init(env: AwakePageEnvironment) {
        self.env = env
        _guards = StateObject(wrappedValue: ConfigSlice(env.config, \.guards))
    }

    var body: some View {
        let range = AwakeGuardsConfig.floorRange
        Section {
            ToggleSetting(L("When the battery is low"), help: L("Ends sessions when the battery drops below the level you choose."),
                          isOn: SettingsBinding.store(env.config, \.guards.batteryFloorEnabled),
                          anchor: ControlID("awake.page.batteryLow"))
            if guards.value.batteryFloorEnabled {
                SliderSetting(L("Battery level"),
                              value: SettingsBinding.double(SettingsBinding.store(env.config, \.guards.batteryFloor),
                                                            in: range),
                              in: Double(range.lowerBound)...Double(range.upperBound),
                              step: Double(AwakeGuardsConfig.floorStep),
                              defaultValue: Double(AwakeGuardsConfig().batteryFloor), format: .percent(of: 100),
                              minSymbol: "battery.25percent", maxSymbol: "battery.75percent",
                              anchor: ControlID("awake.page.batteryFloor"), subordinate: true)
            }
            ToggleSetting(L("When the power adapter is disconnected"),
                          help: L("Ends sessions as soon as your Mac switches to battery power."),
                          isOn: SettingsBinding.store(env.config, \.guards.endOnAdapterDisconnect),
                          anchor: ControlID("awake.page.adapter"))
        } header: {
            Text(L("End sessions automatically"))
        } footer: {
            Text(L("Sessions always end below 5% battery or if your Mac gets very hot."))
        }
    }
}

// MARK: - Lid closed (laptops; 0.3.1 B1, on this page from 0.3.3)

/// Lid-closed mode's one-time opt-in (`features[.lidClosed]`, off by default), moved here from Awake › Advanced in
/// 0.3.3 with its notes: the writable-bundle note while on, the translocated row instead of the switch, and the limits
/// in the footer. The Menu Bar page has a second switch for the same setting (`MenuBarPage`). The leftover rows are
/// `AwakeLidLeftoverSection`, at the top of this page.
private struct AwakeLidSection: View {
    let env: AwakePageEnvironment
    @StateObject private var features: ConfigSlice<AwakeConfig, LossyMap<AwakeFeature, Bool>>
    /// File-system checks of this copy of Snaptic (B1).
    private let translocated = PermissionFlow.isTranslocated
    private let bundleWritable = PermissionFlow.bundleIsUserWritable

    init(env: AwakePageEnvironment) {
        self.env = env
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.features))
    }

    var body: some View {
        let on = features.value[.lidClosed] ?? false
        let lock = AwakeFormat.lock([.lidClosed])
        Section {
            if translocated {
                StatusRow(AwakeLidText.translocated, style: .warning)
            } else {
                ToggleSetting(AwakeLidText.setting, help: AwakeLidText.settingHelp,
                              isOn: Binding(get: { on }, set: { value in setLidClosed(value) }),
                              anchor: ControlID("awake.page.lidClosed"),
                              disabledReason: lock?.lock == .safeMode ? lock?.lock.text : nil)
                    .disabled(lock != nil)
                if let lock, lock.lock == .killSwitch {
                    DefaultsLockRow(key: KillSwitches.key(prefix: "Awake", id: lock.feature.rawValue))
                }
                if on && lock == nil && bundleWritable {
                    SettingsRowNote(BundleCopyText.lidWritable,
                                    fix: StatusAction(title: AwakeLidText.learnMore,
                                                      control: ControlID("awake.page.lidBundleLearnMore")) {
                                        Self.open(BundleCopyText.passwordHelpURL)
                                    })
                }
            }
        } header: {
            Text(AwakeLidText.section)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(AwakeLidText.footer)
                Button(AwakeLidText.learnMore) { Self.open(BundleCopyText.lidHelpURL) }
                    .buttonStyle(.link)
            }
        }
    }

    private func setLidClosed(_ on: Bool) {
        var next = env.config.value
        next.features[.lidClosed] = on
        if next != env.config.value { env.config.value = next }
    }

    /// A README section (BundleCopyText's lid-closed links).
    private static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Drives and History

private struct AwakeNavigationSection: View {
    let env: AwakePageEnvironment
    @ObservedObject private var runtime: AwakeRuntimeState
    @ObservedObject private var history: ConfigStore<AwakeHistory>
    @ObservedObject private var shell = SettingsShell.shared
    @StateObject private var drives: ConfigSlice<AwakeConfig, DriveAliveConfig>
    @StateObject private var features: ConfigSlice<AwakeConfig, LossyMap<AwakeFeature, Bool>>

    init(env: AwakePageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _history = ObservedObject(wrappedValue: env.history)
        _drives = StateObject(wrappedValue: ConfigSlice(env.config, \.drives))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.features))
    }

    var body: some View {
        Section {
            NavigationRow(L("Drives"), symbol: "externaldrive.fill", tint: .gray,
                          value: DrivesPage.navigationValue(config: env.config.value),
                          route: DrivesPage.route, control: ControlID("awake.page.nav.drives"))
            if runtime.isEffective(.history) {
                NavigationRow(L("History"), symbol: "clock.arrow.circlepath", tint: .orange, value: todayValue,
                              route: AwakePageControls.historyRoute, control: ControlID("awake.page.nav.history"))
            }
        } footer: {
            Button(L("Choose where Awake appears in Menu Bar settings.")) {
                shell.root = SettingsRootID.menuBar
            }
            .buttonStyle(.link)
            .modifier(SettingsAnchor(ControlID("awake.page.menuBar")))
        }
    }

    /// "Today 2h 10m".
    private var todayValue: String {
        let now = Date()
        let start = Calendar.autoupdatingCurrent.startOfDay(for: now)
        let totals = history.value.totals(todayStart: start.timeIntervalSince1970, weekStart: start.timeIntervalSince1970,
                                          now: now.timeIntervalSince1970)
        return L("Today ") + AwakeHistoryText.total(totals.today)
    }
}
