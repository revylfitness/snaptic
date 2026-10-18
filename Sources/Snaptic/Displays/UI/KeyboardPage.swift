import SwiftUI
import SnapticKit
import SnapticShims

/// Displays › Keyboard (owner: C; PLAN 0.3 §4.3 sub-page table, route `displays.keyboard`; §4.4 duplicates 5, 12
/// and 14): a status row while the keys need Accessibility, Brightness keys (switch + "Change" target), Volume keys
/// (switch + target), the brightness and volume indicator (style, with the system indicator on macOS 14 and 15, and
/// position) and Keyboard Shortcuts… (`ButtonRow` → one grouped list of every Displays action). No feature switch
/// of its own. Advanced… holds steps, F14/F15, "also let macOS handle" and per-display key settings, input slots,
/// the indicator's target and value, and Preview Indicator.
struct KeyboardPage: View, ControlDeclaring {
    typealias Controls = KeyboardPageControls

    static let title = L("Keyboard")
    static let summary = L("Brightness and volume keys, the brightness indicator, and shortcuts.")
    static let symbol = "keyboard.fill"
    static let tint = SettingsTint.graphite

    private let env: DisplaysPageEnvironment?

    /// The Displays module's page environment, found through the Settings shell.
    init() {
        env = CDisplays.environment
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env, let host = SettingsShell.shared.host {
            KeyboardPageContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

/// The macOS release the indicator choices depend on.
enum KeyboardIndicator {
    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// macOS draws its own indicator and Snaptic can call it (14 and 15).
    static var systemOffered: Bool { KeysConfig.nativeOSDOffered(osMajor: osMajor) && SNOSD.isAvailable() }
}

private struct KeyboardPageContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var keysRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var keys: ConfigSlice<DisplaysConfig, KeysConfig>
    @StateObject private var switcher: DisplaysFeatureSwitcher

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _keysRevision = ObservedObject(wrappedValue: env.runtime.revision(.keys))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _keys = StateObject(wrappedValue: ConfigSlice(env.config, \.keys))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        SettingsPageScaffold(route: SettingsRoute(KeyboardPageControls.surface)) {
            SettingsPageHeader(KeyboardPage.title, summary: KeyboardPage.summary, symbol: KeyboardPage.symbol,
                               tint: KeyboardPage.tint)
            if let context {
                permissionSection(context)
                keysSection
                indicatorSection(context)
                Section {
                    ButtonRow(L("Keyboard Shortcuts…"), symbol: "command",
                              control: ControlID("displays.keyboard.shortcutsButton")) {
                        shell.openSheet = KeyboardPageControls.shortcutsSheet
                    }
                } header: {
                    Text(L("Shortcuts"))
                }
            } else {
                CDisplaysOffSection(runtime: runtime, running: host.isRunning(.displays))
            }
            PageFooterButtons(advanced: { shell.openSheet = KeyboardPageControls.advancedSheet },
                              help: SettingsRoute(KeyboardPageControls.surface),
                              advancedControl: ControlID("displays.keyboard.advancedButton"))
        }
        .sheet(isPresented: shell.sheetBinding(KeyboardPageControls.shortcutsSheet)) {
            KeyboardShortcutsSheet(env: env, host: host)
        }
        .sheet(isPresented: shell.sheetBinding(KeyboardPageControls.advancedSheet)) {
            KeyboardAdvancedSheet(env: env, host: host)
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    private func raw(_ feature: DisplayFeature) -> Bool { FeatureGraph.rawState(feature, in: features.value) }

    private func feature(_ feature: DisplayFeature, _ title: String) -> Binding<Bool> {
        switcher.binding([feature], title: title)
    }

    // MARK: Permission

    @ViewBuilder
    private func permissionSection(_ context: DisplaysContext) -> some View {
        let usesKeys = runtime.isEffective(.brightnessKeys) || runtime.isEffective(.volumeKeys)
        let granted = context.permissions.state(.accessibility) == .granted
        let listening = context.mediaKeys.keysController?.tapRunning ?? false
        if usesKeys, !granted || !listening {
            let pane = KeyboardIndicator.osMajor >= 27 ? L("Device Control and Data Access") : L("Accessibility")
            Section {
                StatusRow(granted ? L("Snaptic isn’t receiving the brightness and volume keys.")
                                  : L("Brightness and volume keys need \(pane)."),
                          style: .warning,
                          actions: [
                              StatusAction(title: L("Open \(pane) Settings…"),
                                           control: ControlID("displays.keyboard.permission")) {
                                  context.permissions.presentGuide(.accessibility,
                                                                   reason: L("Snaptic needs this to use the brightness and volume keys with your displays."))
                              },
                              StatusAction(title: L("Try Again")) {
                                  context.permissions.refresh()
                                  context.mediaKeys.keysController?.retryTap()
                              },
                          ])
            }
        }
    }

    // MARK: Brightness and volume keys

    @ViewBuilder private var keysSection: some View {
        Section {
            ToggleSetting(L("Brightness keys"), help: L("The brightness keys also change external displays."),
                          isOn: feature(.brightnessKeys, L("Brightness keys")),
                          anchor: ControlID("displays.keyboard.brightnessKeys"),
                          disabledReason: switcher.unavailableReason([.brightnessKeys]))
            if raw(.brightnessKeys) {
                PickerSetting(L("Change"), help: L("Which display the brightness keys adjust."),
                              selection: SettingsBinding.store(env.config, \.keys.target),
                              options: KeyTarget.allCases.map { PickerOption($0, $0.title) }, style: .popUp,
                              defaultValue: KeysConfig().target, anchor: ControlID("displays.keyboard.brightnessTarget"),
                              subordinate: true)
            }
            ToggleSetting(L("Volume keys"), help: L("The volume keys change a display’s speakers."),
                          isOn: feature(.volumeKeys, L("Volume keys")),
                          anchor: ControlID("displays.keyboard.volumeKeys"),
                          disabledReason: switcher.unavailableReason([.volumeKeys]))
            if raw(.volumeKeys) {
                PickerSetting(L("Change the display"), help: L("Only displays with speakers take the volume keys."),
                              selection: SettingsBinding.store(env.config, \.keys.volumePolicy),
                              options: VolumePolicy.allCases.map { PickerOption($0, $0.title) }, style: .popUp,
                              defaultValue: KeysConfig().volumePolicy,
                              anchor: ControlID("displays.keyboard.volumeTarget"), subordinate: true)
            }
        } header: {
            Text(L("Keys"))
        } footer: {
            if raw(.brightnessKeys) {
                Text(L("Hold ⌥⇧ for fine steps. More modifier keys are in Advanced."))
            }
        }
    }

    // MARK: Indicator

    @ViewBuilder
    private func indicatorSection(_ context: DisplaysContext) -> some View {
        if runtime.isEffective(.osd) {
            let offered = KeyboardIndicator.systemOffered
            let config = env.config
            let osMajor = KeyboardIndicator.osMajor
            let styles = Self.styleOptions(osMajor: osMajor, systemOffered: offered)
            let position = OSDPosition.osDefault(majorVersion: osMajor).title
            Section {
                PickerSetting(L("Style"),
                              selection: Binding(get: { keys.value.indicatorChoice(systemOffered: offered) }, set: { choice in
                                  let next = config.value.keys.settingIndicator(choice)
                                  if next != config.value.keys { config.value.keys = next }
                              }),
                              options: styles, style: .popUp, defaultValue: .automatic,
                              anchor: ControlID("displays.keyboard.indicatorStyle"))
                PickerSetting(L("Position"), selection: SettingsBinding.store(env.config, \.keys.osdPosition),
                              options: [PickerOption<OSDPosition?>(nil, L("Automatic (\(position))"))]
                                  + OSDPosition.allCases.map { PickerOption<OSDPosition?>($0, $0.title) },
                              style: .popUp, defaultValue: .some(nil),
                              anchor: ControlID("displays.keyboard.indicatorPosition"))
            } header: {
                Text(L("Brightness and volume indicator"))
            } footer: {
                if keys.value.effectiveOSDPosition(osMajor: osMajor) == .topRight, osMajor >= 27 {
                    Text(L("On macOS 27 the system’s own indicator also shows at the top right, so the two can overlap."))
                } else {
                    Text(L("The indicator doesn’t show in screenshots or screen sharing."))
                }
            }
        } else {
            CFeatureOffSection(title: L("Brightness indicator"), feature: .osd, isOn: raw(.osd), context: context,
                               switcher: switcher)
        }
    }
}

private extension KeyboardPageContent {
    static func styleOptions(osMajor: Int, systemOffered: Bool) -> [PickerOption<IndicatorStyleChoice>] {
        let automatic = OSDStyle.osDefault(majorVersion: osMajor).title
        var styles = [PickerOption(IndicatorStyleChoice.automatic, L("Automatic (\(automatic))")),
                      PickerOption(IndicatorStyleChoice.classic, OSDStyle.classic.title),
                      PickerOption(IndicatorStyleChoice.rounded, OSDStyle.rounded.title)]
        if systemOffered {
            styles.append(PickerOption(IndicatorStyleChoice.system, L("Use the System Indicator"),
                                       help: L("macOS draws it where it can; Snaptic’s own shows otherwise.")))
        }
        return styles
    }
}

// MARK: - Advanced

/// Keyboard › Advanced… (PLAN 0.3 §4.3 "A" column, §4.8 "Keys", "OSD"). Restore Keyboard Defaults… keeps the
/// shortcuts recorded in Keyboard Shortcuts…. Never presents another sheet.
private struct KeyboardAdvancedSheet: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var keys: ConfigSlice<DisplaysConfig, KeysConfig>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _keys = StateObject(wrappedValue: ConfigSlice(env.config, \.keys))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        AdvancedSheet(L("Keyboard Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("displays.keyboard.advanced.restoreDefaults")) {
            if raw(.brightnessKeys) {
                brightnessKeysSection
            }
            if raw(.volumeKeys) {
                Section {
                    ToggleSetting(L("Also let macOS handle the volume keys"),
                                  help: L("macOS changes its own output too, so both move together."),
                                  isOn: SettingsBinding.store(env.config, \.keys.volumeAlsoSystem),
                                  anchor: ControlID("displays.keyboard.advanced.volumeAlsoSystem"))
                    ToggleSetting(L("Also let macOS handle the mute key"),
                                  isOn: SettingsBinding.store(env.config, \.keys.muteAlsoSystem),
                                  anchor: ControlID("displays.keyboard.advanced.muteAlsoSystem"))
                } header: {
                    Text(L("Volume keys"))
                }
            }
            if let display, raw(.brightnessKeys) || raw(.volumeKeys) {
                displaySection(display)
            }
            if context != nil, runtime.isEffective(.ddcInput) {
                InputSlotsSection(env: env, keys: keys.value, displays: displays.filter { !$0.isBuiltin },
                                  context: context)
            }
            if runtime.isEffective(.osd) {
                indicatorSection(context)
            }
        }
    }

    private func raw(_ feature: DisplayFeature) -> Bool { FeatureGraph.rawState(feature, in: features.value) }

    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(title: L("Restore Keyboard Defaults…"),
                               question: L("Restore keyboard settings to their defaults?"),
                               message: L("Your keyboard shortcuts and your other Snaptic settings stay as they are."),
                               button: L("Restore Defaults"), destructive: false) {
            let next = config.value.restoringKeyboardDefaults()
            if next != config.value { config.value = next }
        }
    }

    private var brightnessKeysSection: some View {
        Section {
            PickerSetting(L("Use the brightness keys for"),
                          selection: SettingsBinding.store(env.config, \.keys.brightnessPolicy),
                          options: KeyPolicy.allCases.map { PickerOption($0, $0.title) }, style: .popUp,
                          defaultValue: KeysConfig().brightnessPolicy,
                          anchor: ControlID("displays.keyboard.advanced.brightnessPolicy"))
            ToggleSetting(L("Also let macOS handle the brightness keys"),
                          help: L("The built-in display follows macOS while Snaptic changes the others."),
                          isOn: SettingsBinding.store(env.config, \.keys.brightnessAlsoSystem),
                          anchor: ControlID("displays.keyboard.advanced.brightnessAlsoSystem"))
            StepperSetting(L("Steps"), help: L("Key presses from darkest to brightest."),
                           value: SettingsBinding.store(env.config, \.keys.steps), in: KeysConfig.stepRange,
                           defaultValue: KeysConfig().steps, format: .plain(digits: 0),
                           anchor: ControlID("displays.keyboard.advanced.steps"))
            StepperSetting(L("Fine steps"), help: L("The same with ⌥⇧ held."),
                           value: SettingsBinding.store(env.config, \.keys.fineSteps), in: KeysConfig.fineStepRange,
                           defaultValue: KeysConfig().fineSteps, format: .plain(digits: 0),
                           anchor: ControlID("displays.keyboard.advanced.fineSteps"))
            ToggleSetting(L("F14 and F15 change brightness"), help: L("For keyboards without brightness keys."),
                          isOn: SettingsBinding.store(env.config, \.keys.alternateKeys),
                          anchor: ControlID("displays.keyboard.advanced.alternateKeys"))
            LabeledContent {
                InfoButton(L("Modifier keys"), message: Self.modifiers)
            } label: {
                Text(L("Modifier keys"))
                Text(L("Hold them with the brightness keys for other displays and fine steps."))
            }
            .modifier(SettingsAnchor(ControlID("displays.keyboard.advanced.modifiers")))
        } header: {
            Text(L("Brightness keys"))
        }
    }

    static let modifiers = [
        L("⌥⇧: fine steps"),
        L("⇧: this display only (no sync)"),
        L("⌃: built-in display only"),
        L("⌃⌘: external displays only"),
        L("⇧⌘: every display except the one with the pointer"),
        L("⌥ with a brightness key: open Brightness settings"),
        L("⌘ with brightness down: mirror or unmirror the display"),
    ].joined(separator: "\n")

    @ViewBuilder
    private func displaySection(_ display: DisplayInfo) -> some View {
        let key = display.key
        let name = CDisplays.name(display)
        Section {
            ToggleSetting(L("Keys change this display"),
                          help: L("The brightness and volume keys include this display."),
                          isOn: CBind.display(env.config, key, \.keys.keysEnabled),
                          anchor: ControlID("displays.keyboard.advanced.keysChangeDisplay"))
            if raw(.volumeKeys) {
                ToggleSetting(L("Show the volume indicator"),
                              isOn: CBind.display(env.config, key, \.keys.showVolumeOSD),
                              anchor: ControlID("displays.keyboard.advanced.showVolumeIndicator"))
                SettingRow(L("Sound output name"),
                           help: L("When the sound output’s name differs from the display’s."),
                           anchor: ControlID("displays.keyboard.advanced.soundOutputName")) {
                    TextField(L("Sound output name"), text: Binding(get: {
                        perDisplay.value[key]?.keys.audioDeviceName ?? ""
                    }, set: { [env] text in
                        let value: String? = text.isEmpty ? nil : String(text.prefix(64))
                        CBind.display(env.config, key, \.keys.audioDeviceName).wrappedValue = value
                    }), prompt: Text(name))
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
            }
        } header: {
            Text(L("“\(name)”"))
        }
    }

    @ViewBuilder
    private func indicatorSection(_ context: DisplaysContext?) -> some View {
        Section {
            PickerSetting(L("Show the indicator on"), selection: SettingsBinding.store(env.config, \.keys.osdTarget),
                          options: OSDTarget.allCases.map { PickerOption($0, $0.title) }, style: .popUp,
                          defaultValue: KeysConfig().osdTarget,
                          anchor: ControlID("displays.keyboard.advanced.indicatorTarget"))
            ToggleSetting(L("Show the value"), help: L("The percent, or nits when brightness shows in nits."),
                          isOn: SettingsBinding.store(env.config, \.keys.osdShowValue),
                          anchor: ControlID("displays.keyboard.advanced.indicatorValue"))
            ButtonRow(L("Preview Indicator"), symbol: "eye", control: ControlID("displays.keyboard.advanced.previewIndicator")) {
                guard let context else { return }
                if let controller = context.osd.controller {
                    controller.preview()
                } else if let main = context.registry.displays.first(where: \.isMain) {
                    context.osd.show(.brightness, value: context.brightness.value(for: main.key) ?? 0.6, max: 1,
                                     on: main.desktopID, detail: L("Preview"))
                }
            }
            .disabled(context == nil)
        } header: {
            Text(L("Brightness and volume indicator"))
        } footer: {
            Text(L("VoiceOver announces changes whether or not the indicator shows."))
        }
    }
}

/// Input slots: up to ten display + input pairs, each switched by its "Input Slot n" shortcut.
private struct InputSlotsSection: View {
    let env: DisplaysPageEnvironment
    let keys: KeysConfig
    let displays: [DisplayInfo]
    let context: DisplaysContext?

    var body: some View {
        let slots = keys.inputSlots
        Section {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                row(index, slot)
            }
            if slots.isEmpty {
                Text(L("No input slots yet.")).foregroundStyle(.secondary)
            }
            if slots.count < KeysConfig.maxSlots {
                ButtonRow(L("Add Slot"), symbol: "plus") { [env] in
                    env.config.value.keys.inputSlots = Array((env.config.value.keys.inputSlots + [InputSlot()])
                        .prefix(KeysConfig.maxSlots))
                }
            }
        } header: {
            Text(L("Input slots"))
                .modifier(SettingsAnchor(ControlID("displays.keyboard.advanced.inputSlots")))
        } footer: {
            Text(L("Give each slot a shortcut (“Input Slot 1”…) in Keyboard Shortcuts. A slot without a display switches the one the keys change."))
        }
    }

    private func update(_ index: Int, _ change: (inout InputSlot) -> Void) {
        var list = env.config.value.keys.inputSlots
        guard list.indices.contains(index) else { return }
        change(&list[index])
        if list != env.config.value.keys.inputSlots { env.config.value.keys.inputSlots = list }
    }

    private func row(_ index: Int, _ slot: InputSlot) -> some View {
        HStack {
            Text(L("Slot \(index + 1)"))
                .frame(width: 56, alignment: .leading)
            Picker(L("Display"), selection: Binding(get: { slot.display }, set: { value in update(index) { $0.display = value } })) {
                Text(L("The display the keys change")).tag(DisplayKey?.none)
                ForEach(displays) { d in
                    Text(CDisplays.name(d)).tag(Optional(d.key))
                }
            }
            .labelsHidden()
            Picker(L("Input"), selection: Binding(get: { slot.value }, set: { value in update(index) { $0.value = value } })) {
                ForEach(inputs(slot), id: \.self) { value in
                    Text(VCPPolicy.inputName(value)).tag(value)
                }
            }
            .labelsHidden()
            Toggle(L("LG"), isOn: Binding(get: { slot.lgAlt }, set: { value in update(index) { $0.lgAlt = value } }))
                .toggleStyle(.checkbox)
                .help(L("Use LG’s alternate input command"))
            Button {
                var list = env.config.value.keys.inputSlots
                guard list.indices.contains(index) else { return }
                list.remove(at: index)
                env.config.value.keys.inputSlots = list
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Remove slot \(index + 1)"))
        }
    }

    private func inputs(_ slot: InputSlot) -> [UInt16] {
        var values = DisplaysUIText.commonInputs
        if let key = slot.display, let listed = context?.ddc.cachedCapabilities(key)?.inputSources, !listed.isEmpty {
            values = listed.map { $0 & 0xFF }
        }
        if !values.contains(slot.value) { values.append(slot.value) }
        return Array(Set(values)).sorted()
    }
}
