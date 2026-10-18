import SwiftUI
import SnapticKit

/// Brightness and Dimming › Advanced… (owner: C; PLAN 0.3 §4.3 "A" column, §4.8 "Brightness"): **Brightness
/// methods** (the four method switches, then for the selected display the method in use and why, its "Use" choice,
/// the custom switchover, the minimum hardware level and the color-table check), the display's nits (now and a
/// custom range), the extra-brightness defaults with the "Is it brighter?" test, and sync's "Follow outside
/// changes". Footer: Restore Brightness Defaults…. Never presents another sheet.
struct BrightnessAdvancedSheet: View, ControlDeclaring {
    typealias Controls = BrightnessAdvancedSheetControls

    static let title = L("Brightness Advanced Settings")

    private let env: DisplaysPageEnvironment?

    init() {
        env = CDisplays.environment
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env, let host = SettingsShell.shared.host {
            BrightnessAdvancedContent(env: env, host: host)
        } else {
            AdvancedSheet(Self.title, restoreDefaults: nil) {
                Section {
                    StatusRow(L("Displays settings aren’t available right now."), style: .warning)
                }
            }
        }
    }
}

private struct BrightnessAdvancedContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var brightnessRevision: ControllerRevision
    @ObservedObject private var xdrRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var settings: ConfigSlice<DisplaysConfig, BrightnessConfig>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @State private var calibrating = false

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _brightnessRevision = ObservedObject(wrappedValue: env.runtime.revision(.brightness))
        _xdrRevision = ObservedObject(wrappedValue: env.runtime.revision(.xdr))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _settings = StateObject(wrappedValue: ConfigSlice(env.config, \.brightness))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        let managed = context != nil && runtime.isEffective(.brightness)
        AdvancedSheet(BrightnessAdvancedSheet.title, restoreDefaults: restore,
                      restoreControl: ControlID("displays.brightness.advanced.restoreDefaults")) {
            methodsSection(managed ? context : nil, display)
            if managed, let context, let display {
                nitsSection(context, display)
            }
            if managed, let context, displays.contains(where: BrightnessSections.isXDR), runtime.isEffective(.xdr) {
                extraBrightnessSection(context, display)
            }
            if managed, displays.count > 1, runtime.isEffective(.sync) {
                Section {
                    ToggleSetting(L("Follow changes made outside Snaptic"),
                                  help: L("A display’s own buttons count only while hardware read-back is on."),
                                  isOn: SettingsBinding.store(env.config, \.brightness.syncExternalChanges),
                                  anchor: ControlID("displays.brightness.advanced.syncExternalChanges"))
                } header: {
                    Text(L("Sync"))
                }
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(scopeName: L("Brightness"), destructive: false) {
            let next = config.value.restoringDefaults(scope: .brightness)
            if next != config.value { config.value = next }
        }
    }

    private func feature(_ feature: DisplayFeature, _ title: String) -> Binding<Bool> {
        switcher.binding([feature], title: title)
    }

    // MARK: Brightness methods

    @ViewBuilder
    private func methodsSection(_ context: DisplaysContext?, _ display: DisplayInfo?) -> some View {
        Section {
            ToggleSetting(L("Apple native"), help: L("Built-in and Apple displays change their own backlight."),
                          isOn: feature(.brightnessApple, L("Apple native brightness")),
                          anchor: ControlID("displays.brightness.advanced.methodApple"),
                          disabledReason: switcher.unavailableReason([.brightnessApple]))
            ToggleSetting(L("Hardware (DDC)"), help: L("External displays that support it change their own backlight."),
                          isOn: feature(.brightnessDDC, L("Hardware brightness")),
                          anchor: ControlID("displays.brightness.advanced.methodHardware"),
                          disabledReason: switcher.unavailableReason([.brightnessDDC]))
            ToggleSetting(L("Color table"), help: L("Dims in software by scaling the display’s colors."),
                          isOn: feature(.brightnessGamma, L("Color table dimming")),
                          anchor: ControlID("displays.brightness.advanced.methodColorTable"),
                          disabledReason: switcher.unavailableReason([.brightnessGamma]))
            ToggleSetting(L("Overlay"), help: L("Dims in software with a dark layer over the screen."),
                          isOn: feature(.brightnessOverlay, L("Overlay dimming")),
                          anchor: ControlID("displays.brightness.advanced.methodOverlay"),
                          disabledReason: switcher.unavailableReason([.brightnessOverlay]))
            if let context, let display {
                displayMethodRows(context, display)
            }
        } header: {
            Text(L("Brightness methods"))
        } footer: {
            Text(L("Snaptic uses the display’s backlight first, then dims further in software below the switchover."))
        }
    }

    @ViewBuilder
    private func displayMethodRows(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let key = display.key
        let service = context.brightness
        let hardware = service.hardwareMethod(for: key)
        let software = service.softwareMethod(for: key)
        let now = [hardware?.title, software?.title].compactMap { $0 }.joined(separator: " + ")
        PickerSetting(L("Method for “\(CDisplays.name(display))”"),
                      help: now.isEmpty ? service.methodReason(for: key) : L("Now using \(now)."),
                      selection: CBind.display(env.config, key, \.brightness.method),
                      options: [PickerOption<BrightnessMethod?>(nil, L("Automatic"))]
                          + BrightnessMethod.allCases.map { PickerOption<BrightnessMethod?>($0, $0.title) },
                      style: .popUp, defaultValue: .some(nil), anchor: ControlID("displays.brightness.advanced.use"))
        if hardware != nil, software != nil {
            let fallback = CombinedScale.defaultSwitchover(hardware: hardware, xdrOn: false)
            let stored = CBind.display(env.config, key, \.brightness.switchover)
            ToggleSetting(L("Custom switchover"),
                          help: L("Below the switchover the backlight stays at its minimum and software dims further."),
                          isOn: Binding(get: { stored.wrappedValue != nil },
                                        set: { stored.wrappedValue = $0 ? fallback : nil }),
                          anchor: ControlID("displays.brightness.advanced.customSwitchover"))
            if stored.wrappedValue != nil {
                SliderSetting(L("Switchover"), value: SettingsBinding.unwrapped(stored, fallback: fallback),
                              in: 0...0.9, step: 0.01, defaultValue: fallback, format: .percent(of: 1),
                              anchor: ControlID("displays.brightness.advanced.switchover"), subordinate: true)
            }
        }
        if hardware != nil {
            SliderSetting(L("Minimum hardware level"), help: L("Keeps the backlight above this level, for example to avoid flicker."),
                          value: CBind.display(env.config, key, \.brightness.minHardware), in: 0...0.9, step: 0.01,
                          defaultValue: PerDisplayBrightness().minHardware, format: .percent(of: 1),
                          anchor: ControlID("displays.brightness.advanced.minHardware"))
        }
        let works = perDisplay.value[key]?.brightness.gammaWorks
        if software == .gamma || works == false {
            LabeledContent {
                if works != nil {
                    Button(L("Ask Again")) { [env] in
                        CBind.display(env.config, key, \.brightness.gammaWorks).wrappedValue = nil
                        context.gamma.resetGiveUp(key)
                    }
                }
            } label: {
                Text(L("Color table check"))
                Text(works == false ? L("It didn’t get darker, so the overlay dims this display.")
                     : works == true ? L("Color table dimming works on this display.") : L("Not checked yet."))
            }
            .modifier(SettingsAnchor(ControlID("displays.brightness.advanced.colorTableCheck")))
        }
    }

    // MARK: Nits

    @ViewBuilder
    private func nitsSection(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let key = display.key
        let estimate = NitsModel.defaultRange(isBuiltin: display.isBuiltin, isXDR: BrightnessSections.isXDR(display),
                                              chipName: HostInfo.current.chipName)
        let stored = CBind.display(env.config, key, \.brightness.nits)
        Section {
            if runtime.isEffective(.nits), let nits = context.brightness.nits(for: key) {
                LabeledContent(L("Now")) {
                    Text(NitsModel.label(nits.value, estimate: nits.estimate)).monospacedDigit()
                }
            }
            ToggleSetting(L("Custom nits range"), help: L("Use your display’s measured or published values instead of an estimate."),
                          isOn: Binding(get: { stored.wrappedValue != nil }, set: { on in
                              stored.wrappedValue = on ? NitsRange(minimum: estimate.minimum, maximum: estimate.maximum,
                                                                   peak: estimate.peak, isEstimate: false) : nil
                          }),
                          anchor: ControlID("displays.brightness.advanced.customNits"))
            if let range = stored.wrappedValue {
                nitsRow(L("Minimum"), \.minimum, range: range, stored: stored,
                        anchor: ControlID("displays.brightness.advanced.nitsMinimum"))
                nitsRow(L("Maximum (SDR)"), \.maximum, range: range, stored: stored,
                        anchor: ControlID("displays.brightness.advanced.nitsMaximum"))
                nitsRow(L("Peak (HDR)"), \.peak, range: range, stored: stored,
                        anchor: ControlID("displays.brightness.advanced.nitsPeak"))
            }
        } header: {
            Text(L("Nits for “\(CDisplays.name(display))”"))
        } footer: {
            Text(L("Without a custom range Snaptic estimates from the model: \(Int(estimate.minimum))–\(Int(estimate.maximum)) nits, \(Int(estimate.peak)) at peak."))
        }
    }

    private func nitsRow(_ title: String, _ path: WritableKeyPath<NitsRange, Double>, range: NitsRange,
                         stored: Binding<NitsRange?>, anchor: ControlID) -> some View {
        SettingRow(title, anchor: anchor) {
            NumberField(title, value: Binding(get: { range[keyPath: path] }, set: { value in
                var next = stored.wrappedValue ?? range
                next[keyPath: path] = value
                next.isEstimate = false
                let clean = next.sanitized()
                if clean != stored.wrappedValue { stored.wrappedValue = clean }
            }), in: NitsRange.limits, step: 1, format: .nits)
        }
        .padding(.leading, 20)
    }

    // MARK: Extra brightness

    @ViewBuilder
    private func extraBrightnessSection(_ context: DisplaysContext, _ display: DisplayInfo?) -> some View {
        Section {
            SliderSetting(L("Default maximum"), help: L("Each display goes this high unless you set its own maximum."),
                          value: SettingsBinding.store(env.config, \.brightness.xdrMaxScale),
                          in: BrightnessConfig.xdrScaleRange, step: 0.05, defaultValue: BrightnessConfig().xdrMaxScale,
                          format: .percent(of: 1), anchor: ControlID("displays.brightness.advanced.xdrMaximum"))
            PickerSetting(L("Method"), help: L("Automatic picks what works on each display."),
                          selection: SettingsBinding.store(env.config, \.brightness.xdrMethod),
                          options: XDRMethod.allCases.map { PickerOption($0, $0.title) }, style: .popUp,
                          defaultValue: BrightnessConfig().xdrMethod,
                          anchor: ControlID("displays.brightness.advanced.xdrMethod"))
            ToggleSetting(L("Pause in Low Power Mode"),
                          isOn: SettingsBinding.store(env.config, \.brightness.xdrPauseOnLowPower),
                          anchor: ControlID("displays.brightness.advanced.xdrLowPower"))
            ToggleSetting(L("Stop at 100% first"),
                          help: L("The brightness keys pause at 100% before going into extra brightness."),
                          isOn: SettingsBinding.store(env.config, \.brightness.xdrDetent),
                          anchor: ControlID("displays.brightness.advanced.xdrDetent"))
            if let display, BrightnessSections.isXDR(display) {
                testRow(context, display)
            }
        } header: {
            Text(L("Extra brightness"))
        }
    }

    @ViewBuilder
    private func testRow(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let edr = context.edr
        let method = edr.xdrMethod(for: display.key).0
        LabeledContent {
            if calibrating {
                HStack(spacing: 8) {
                    Button(L("Yes")) {
                        edr.finishCalibration(brighter: true)
                        calibrating = false
                    }
                    Button(L("No Change")) {
                        edr.finishCalibration(brighter: false)
                        calibrating = false
                    }
                }
            } else {
                Button(L("Test")) {
                    guard let method else { return }
                    edr.beginCalibration(display.key, method: method)
                    calibrating = true
                }
                .disabled(method == nil)
            }
        } label: {
            Text(calibrating ? L("Is “\(CDisplays.name(display))” brighter now?") : L("Test extra brightness"))
            Text(calibrating ? L("Answer to keep or change the method.")
                 : L("Briefly raises “\(CDisplays.name(display))” and asks whether it got brighter."))
        }
        .modifier(SettingsAnchor(ControlID("displays.brightness.advanced.xdrTest")))
    }
}
