import Combine
import SwiftUI
import SnapticKit

/// Displays › Hardware Controls (owner: C; PLAN 0.3 §4.3 sub-page table, route `displays.hardware`): header switch
/// "Hardware controls" (`ddcControls`); while it's off, what it does. On: external display tiles, then for the
/// selected display "Use hardware controls for this display", Volume (`.live`) and Mute, Hardware contrast
/// (`.live`), Input (with `ddcInput`), Turn Off / Turn On (with `ddcPower`) and the custom control sliders (with
/// `ddcCustom`). Live sliders write only through the shared `DisplaysContext.live`; values come from
/// `DisplayRuntime` and DDCController's revision. Every write goes through DDCController (VCP policy and
/// confirmation). Advanced… holds the feature switches, read-back, tuning, the input list, custom controls, raw
/// commands, timing and the hardware information.
struct HardwareControlsPage: View, ControlDeclaring {
    typealias Controls = HardwareControlsPageControls

    static let title = L("Hardware Controls")
    static let summary = L("Volume, input, and power for displays that support them.")
    static let symbol = "slider.horizontal.3"
    static let tint = SettingsTint.gray
    static let switchTitle = L("Hardware controls")

    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "displays.hardware.volume", symbol: "speaker.wave.2.fill", title: L("Volume and contrast"),
                         text: L("Change a display’s speakers and contrast from the menu, the keys, and here.")),
        FeatureHighlight(id: "displays.hardware.input", symbol: "cable.connector", title: L("Input and power"),
                         text: L("Switch a display to another computer, or turn it off, without its buttons.")),
        FeatureHighlight(id: "displays.hardware.safe", symbol: "checkmark.shield", title: L("Asks first"),
                         text: L("Changes that could leave you without a picture ask before they’re sent.")),
    ]

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
            HardwareControlsContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

private struct HardwareControlsContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var ddcRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var drag = CLiveDrag()

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _ddcRevision = ObservedObject(wrappedValue: env.runtime.revision(.ddc))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime, externalOnly: true)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        let isOn = FeatureGraph.rawState(.ddcControls, in: features.value)
        SettingsPageScaffold(route: SettingsRoute(HardwareControlsPageControls.surface)) {
            SettingsPageHeader(HardwareControlsPage.title, summary: HardwareControlsPage.summary,
                               symbol: HardwareControlsPage.symbol, tint: HardwareControlsPage.tint,
                               isOn: switcher.binding([.ddcControls], title: HardwareControlsPage.switchTitle),
                               switchLabel: HardwareControlsPage.switchTitle,
                               control: ControlID("displays.hardware.enabled"))
            if !isOn {
                FeatureHighlights(HardwareControlsPage.highlights)
            } else if let context {
                if !runtime.isEffective(.ddcControls) {
                    CFeatureOffSection(title: HardwareControlsPage.switchTitle, feature: .ddcControls, isOn: true,
                                       context: context, switcher: switcher)
                } else if let display {
                    if displays.count > 1 {
                        Section {
                            PerDisplayPicker(CDisplays.tiles(displays), selection: $shell.selectedDisplay)
                                .modifier(SettingsAnchor(ControlID("displays.hardware.display")))
                        }
                    }
                    displaySection(context, display)
                } else {
                    Section {
                        EmptyListView(L("No External Display"), symbol: "display",
                                      text: L("Connect a display that supports hardware controls."), action: nil)
                    }
                }
            } else {
                CDisplaysOffSection(runtime: runtime, running: host.isRunning(.displays))
            }
            PageFooterButtons(advanced: { shell.openSheet = HardwareControlsPageControls.advancedSheet },
                              help: SettingsRoute(HardwareControlsPageControls.surface),
                              advancedControl: ControlID("displays.hardware.advancedButton"))
        }
        .sheet(isPresented: shell.sheetBinding(HardwareControlsPageControls.advancedSheet)) {
            HardwareAdvancedSheet(env: env, host: host)
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    // MARK: The selected display

    @ViewBuilder
    private func displaySection(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let key = display.key
        let ddc = context.ddc
        let enabled = perDisplay.value[key]?.ddc.enabled ?? PerDisplayDDC().enabled
        Section {
            ToggleSetting(L("Use hardware controls for this display"),
                          help: L("Brightness, volume, and contrast go to the display itself."),
                          isOn: CBind.display(env.config, key, \.ddc.enabled),
                          anchor: ControlID("displays.hardware.useDisplay"))
            if enabled {
                if ddc.isAvailable(key), let controller = ddc.controller {
                    HardwareLiveRows(context: context, controller: controller, display: display,
                                     live: runtime.runtime(for: key), drag: drag,
                                     showsInput: runtime.isEffective(.ddcInput),
                                     showsPower: runtime.isEffective(.ddcPower),
                                     showsCustom: runtime.isEffective(.ddcCustom),
                                     customControls: perDisplay.value[key]?.ddc.customControls ?? [])
                } else if ddc.linkStatus(key) == .unknown {
                    StatusRow(L("Checking whether this display answers…"))
                } else {
                    StatusRow(L("This display doesn’t answer hardware controls, so Snaptic dims it in software."),
                              actions: [StatusAction(title: L("Check Again")) {
                                  context.lifetime.spawn { _ = await ddc.probe(key) }
                              }])
                }
            }
        } header: {
            Text(L("“\(CDisplays.name(display))”"))
        } footer: {
            Text(L("Many TVs, DisplayLink adapters, some docks, and some HDMI ports don’t pass hardware controls."))
        }
    }
}

/// Volume and Mute, Hardware contrast, Input, Turn Off / Turn On and custom sliders of one display; it alone
/// re-renders when a live value changes.
private struct HardwareLiveRows: View {
    let context: DisplaysContext
    let controller: DDCController
    let display: DisplayInfo
    @ObservedObject var live: DisplayRuntime
    @ObservedObject var drag: CLiveDrag
    /// Custom range controls' live values (DDCController's custom publisher): re-renders during and after a drag
    /// and on menu or read-back changes, like `live` does for volume and contrast.
    @StateObject var customLive = CCustomLiveValues()
    let showsInput: Bool
    let showsPower: Bool
    let showsCustom: Bool
    let customControls: [DDCCustomControl]

    private var key: DisplayKey { display.key }

    /// The menu's rule: volume only for displays with VCP 0x62.
    private var showsVolume: Bool {
        let caps = context.ddc.cachedCapabilities(key)
        let reported = caps?.supports(VCPPolicy.volume) == true
            || (caps == nil && context.ddc.lastReading(VCPPolicy.volume, of: key) != nil)
        return reported && controller.isControlEnabled(VCPPolicy.volume, for: key)
    }

    var body: some View {
        if showsVolume, live.volume != nil {
            liveSlider(L("Volume"), .volume, value: live.volume, range: live.volumeRange, minSymbol: "speaker.fill",
                       maxSymbol: "speaker.wave.3.fill", anchor: ControlID("displays.hardware.volume"))
            ToggleSetting(L("Mute"), isOn: Binding(get: { live.muted ?? false }, set: { _ in
                controller.toggleMute(.display(display.key))
            }), anchor: ControlID("displays.hardware.mute"))
        }
        if controller.isControlEnabled(VCPPolicy.contrast, for: key), live.contrast != nil {
            liveSlider(L("Hardware contrast"), .contrast, value: live.contrast, range: live.contrastRange,
                       minSymbol: "circle.lefthalf.filled", maxSymbol: "circle.righthalf.filled",
                       anchor: ControlID("displays.hardware.contrast"))
        }
        if showsInput {
            inputPicker
        }
        if showsPower {
            powerRow
        }
        if showsCustom {
            let ranges = customControls.filter { $0.kind == .range }
            ForEach(ranges) { control in
                customSlider(control)
            }
            .onChange(of: CCustomLiveValues.Tracked(key: key, codes: ranges.map(\.code)), initial: true) { _, tracked in
                customLive.track(controller, tracked)
            }
            ForEach(customControls.filter { $0.kind == .command }) { control in
                ButtonRow(L("Send “\(name(control))”"), help: L("Sends \(VCPPolicy.hex(control.code)) = \(control.value)."),
                          control: ControlID("displays.hardware.customControl")) {
                    controller.runCustom(control, on: display.key)
                }
            }
        }
    }

    private func name(_ control: DDCCustomControl) -> String {
        control.name.isEmpty ? VCPPolicy.name(control.code) : TextSanitizer.clean(control.name, maxScalars: 64)
    }

    private func liveSlider(_ title: String, _ control: LiveControl, value: Double?, range: ClosedRange<Double>,
                            minSymbol: String?, maxSymbol: String?, anchor: ControlID) -> some View {
        let current = min(max(value ?? range.lowerBound, range.lowerBound), range.upperBound)
        let context = self.context
        let key = self.key
        let drag = self.drag
        return SliderSetting(title, value: Binding(get: { current }, set: { drag.set(control, $0, key: key, context: context) }),
                             in: range, defaultValue: nil, format: .percent(of: 1), minSymbol: minSymbol,
                             maxSymbol: maxSymbol, commit: .live, anchor: anchor,
                             phase: { drag.phase(control, $0, current: current, key: key, context: context) })
    }

    private func customSlider(_ control: DDCCustomControl) -> some View {
        let context = self.context
        let controller = self.controller
        let customLive = self.customLive
        let key = self.key
        let drag = self.drag
        let code = control.code
        // Read at call time, never captured: the value follows drags, the menu and read-backs.
        let current = { customLive.value(code, key: key, controller: controller) }
        return SliderSetting(name(control),
                             value: Binding(get: current, set: { drag.set(.custom(code), $0, key: key, context: context) }),
                             in: 0...1, defaultValue: nil, format: .percent(of: 1), commit: .live,
                             anchor: ControlID("displays.hardware.customControl"),
                             phase: { drag.phase(.custom(code), $0, current: current(), key: key, context: context) })
    }

    @ViewBuilder private var inputPicker: some View {
        let inputs = controller.inputList(for: key)
        if !inputs.isEmpty {
            let selection = Binding<String?>(get: {
                inputs.first { $0.value == live.input && !$0.lgAlt }?.id
            }, set: { id in
                guard let id, let entry = inputs.first(where: { $0.id == id }) else { return }
                _ = controller.setInput(entry, on: display.key)
            })
            let options = (selection.wrappedValue == nil ? [PickerOption<String?>(nil, L("Unknown"))] : [])
                + inputs.map { PickerOption<String?>($0.id, controller.inputName($0)) }
            PickerSetting(L("Input"), help: L("Asks first: this Mac may lose the picture on this display."),
                          selection: selection, options: options, style: .popUp, defaultValue: nil,
                          anchor: ControlID("displays.hardware.input"))
        }
    }

    @ViewBuilder private var powerRow: some View {
        let isOn = live.powerOn ?? true
        let canTurnOff = context.registry.displays.contains { $0.key != display.key && $0.isOnline && $0.isStronglyVisible }
        if isOn {
            ButtonRow(L("Turn Off Display…"),
                      help: canTurnOff ? L("Asks first. Some displays wake only with their power button.")
                                       : L("Not for the only display you can see."),
                      control: ControlID("displays.hardware.power")) {
                _ = controller.setPower(false, on: display.key)
            }
            .disabled(!canTurnOff)
        } else {
            ButtonRow(L("Turn On Display"), help: L("This display is in standby."),
                      control: ControlID("displays.hardware.power")) {
                _ = controller.setPower(true, on: display.key)
            }
        }
    }
}

/// The live values of one display's custom range controls, from `DDCController.customPublisher` (which starts with
/// the current value and then sends every change: drags here, the menu's sliders, read-backs). Publishing re-renders
/// `HardwareLiveRows`, whose slider bindings then read the newest value.
@MainActor final class CCustomLiveValues: ObservableObject {
    struct Tracked: Equatable {
        let key: DisplayKey
        let codes: [UInt8]
    }

    @Published private(set) var values: [UInt8: Double] = [:]
    private var tracked: Tracked?
    private var sinks: [AnyCancellable] = []

    init() {}

    /// Follows `tracked`'s controls (again only when the display or the list changed).
    func track(_ controller: DDCController, _ tracked: Tracked) {
        guard tracked != self.tracked else { return }
        self.tracked = tracked
        sinks = []
        values = [:]
        for code in Set(tracked.codes) {
            sinks.append(controller.customPublisher(code, for: tracked.key)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    MainActor.assumeIsolated {
                        guard let self, self.tracked == tracked else { return }
                        self.values[code] = value
                    }
                })
        }
    }

    /// The newest value of a control: the published one, else the controller's, else the middle.
    func value(_ code: UInt8, key: DisplayKey, controller: DDCController) -> Double {
        let v = (tracked?.key == key ? values[code] : nil) ?? controller.customValue(code, for: key) ?? 0.5
        return v.isFinite ? min(1, max(0, v)) : 0.5
    }
}

// MARK: - Advanced

/// Hardware Controls › Advanced… (PLAN 0.3 §4.3 "A" column): the Input switching, Power control and Custom
/// controls switches, read-back, and for the selected display per-control tuning (disclosure rows, no per-control
/// sheet), the input list, the Turn Off value, custom controls, raw commands with unlocks, timing and the hardware
/// information. Footer: Restore Hardware Controls Defaults…. Never presents another sheet.
private struct HardwareAdvancedSheet: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var ddcRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var ddcSettings: ConfigSlice<DisplaysConfig, DDCConfig>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @State private var capsLoading = false
    @State private var newCustomName = ""
    @State private var newCustomCode = ""
    @State private var newCustomKind = DDCCustomControl.Kind.range
    @State private var newCustomValue = ""
    @State private var rawCode = ""
    @State private var rawValue = ""
    @State private var rawResult: String?
    @State private var unlockText = ""
    @State private var unlockMessage: String?

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _ddcRevision = ObservedObject(wrappedValue: env.runtime.revision(.ddc))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _ddcSettings = StateObject(wrappedValue: ConfigSlice(env.config, \.ddc))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime, externalOnly: true)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        let on = FeatureGraph.rawState(.ddcControls, in: features.value)
        AdvancedSheet(L("Hardware Controls Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("displays.hardware.advanced.restoreDefaults")) {
            featureSection
            if on {
                readbackSection
            }
            if on, runtime.isEffective(.ddcControls), let context, let display, let controller = context.ddc.controller {
                displaySections(context, controller, display)
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(scopeName: L("Hardware Controls"), destructive: false) {
            let next = config.value.restoringDefaults(scope: .hardware)
            if next != config.value { config.value = next }
        }
    }

    private func feature(_ feature: DisplayFeature, _ title: String) -> Binding<Bool> {
        switcher.binding([feature], title: title)
    }

    private var featureSection: some View {
        Section {
            ToggleSetting(L("Input switching"), help: L("Switch a display’s input from Settings, the menu, and shortcuts."),
                          isOn: feature(.ddcInput, L("Input switching")),
                          anchor: ControlID("displays.hardware.advanced.inputSwitching"),
                          disabledReason: switcher.unavailableReason([.ddcInput]))
            ToggleSetting(L("Power control"), help: L("Turn a display off and on without its power button."),
                          isOn: feature(.ddcPower, L("Power control")),
                          anchor: ControlID("displays.hardware.advanced.powerControl"),
                          disabledReason: switcher.unavailableReason([.ddcPower]))
            ToggleSetting(L("Custom controls"), help: L("Your own sliders and commands for codes a display supports."),
                          isOn: feature(.ddcCustom, L("Custom controls")),
                          anchor: ControlID("displays.hardware.advanced.customControls"),
                          disabledReason: switcher.unavailableReason([.ddcCustom]))
        } header: {
            Text(L("Features"))
        }
    }

    private var readbackSection: some View {
        Section {
            ToggleSetting(L("Read values back"), help: L("Notices changes made with a display’s own buttons."),
                          isOn: SettingsBinding.store(env.config, \.ddc.readback),
                          anchor: ControlID("displays.hardware.advanced.readback"))
            if ddcSettings.value.readback {
                SliderSetting(L("Every"), value: SettingsBinding.store(env.config, \.ddc.defaultReadbackInterval),
                              in: 0.5...60, step: 0.5, defaultValue: DDCConfig().defaultReadbackInterval, format: .seconds,
                              anchor: ControlID("displays.hardware.advanced.readbackInterval"), subordinate: true)
            }
            ToggleSetting(L("Send values again after wake"),
                          help: L("Only when the display reports something different."),
                          isOn: SettingsBinding.store(env.config, \.ddc.restoreOnWake),
                          anchor: ControlID("displays.hardware.advanced.restoreOnWake"))
        } header: {
            Text(L("All displays"))
        } footer: {
            Text(L("Writes pause during sleep, display changes, and while you’re switched out; Safe Mode skips automatic writes."))
        }
    }

    // MARK: The selected display

    @ViewBuilder
    private func displaySections(_ context: DisplaysContext, _ controller: DDCController, _ display: DisplayInfo) -> some View {
        let key = display.key
        let per = perDisplay.value[key]?.ddc ?? PerDisplayDDC()
        Section {
            ForEach(knownCodes(context, key), id: \.self) { code in
                CRevealDisclosure(VCPPolicy.name(code) + " (" + VCPPolicy.hex(code) + ")",
                                  ids: [ControlID("displays.hardware.advanced.tuning")]) {
                    tuningRows(context, key, code)
                }
                .modifier(SettingsAnchor(ControlID("displays.hardware.advanced.tuning")))
            }
            if runtime.isEffective(.ddcPower) {
                PickerSetting(L("Turn Off sends"), help: L("What the display does when you turn it off from Snaptic."),
                              selection: CBind.display(env.config, key, \.ddc.standbyValue),
                              options: [PickerOption(UInt16(2), L("Standby")), PickerOption(UInt16(3), L("Suspend")),
                                        PickerOption(UInt16(4), L("Off"))],
                              style: .popUp, defaultValue: PerDisplayDDC().standbyValue,
                              anchor: ControlID("displays.hardware.advanced.standbyValue"))
            }
        } header: {
            Text(L("Controls of “\(CDisplays.name(display))”"))
        } footer: {
            Text(L("Tuning maps 0–100% onto the display’s raw range."))
        }
        if runtime.isEffective(.ddcInput) {
            inputsSection(controller, key)
        }
        if runtime.isEffective(.ddcCustom) {
            customSection(controller, key, per)
            rawSection(context, controller, key, per)
        }
        timingSection(key, per)
        informationSection(context, key)
    }

    private func knownCodes(_ context: DisplaysContext, _ key: DisplayKey) -> [UInt8] {
        let base: [UInt8] = [VCPPolicy.brightness, VCPPolicy.contrast, VCPPolicy.volume]
        let listed = context.ddc.cachedCapabilities(key)?.vcp.keys.filter { VCPPolicy.continuousCodes.contains($0) } ?? []
        return Array(Set(base).union(listed)).sorted()
    }

    private func tuning(_ key: DisplayKey, _ code: UInt8) -> Binding<DDCControlTuning> {
        let config = env.config
        return Binding(get: { config.value.perDisplay[key]?.ddc.tuning(code) ?? DDCControlTuning() },
                       set: { value in
                           var entry = config.value.perDisplay[key] ?? PerDisplayConfig()
                           let clean = value.sanitized()
                           guard entry.ddc.controls[VCPKey(code)] != clean else { return }
                           entry.ddc.controls[VCPKey(code)] = clean
                           config.value.perDisplay[key] = entry
                       })
    }

    @ViewBuilder
    private func tuningRows(_ context: DisplaysContext, _ key: DisplayKey, _ code: UInt8) -> some View {
        let t = tuning(key, code)
        let reported = Double(context.ddc.lastReading(code, of: key)?.max ?? 100)
        PickerSetting(L("Use"), selection: Binding(get: { t.wrappedValue.enabled }, set: { t.wrappedValue.enabled = $0 }),
                      options: [PickerOption<Bool?>(nil, L("Automatic")), PickerOption<Bool?>(true, L("On")),
                                PickerOption<Bool?>(false, L("Off"))],
                      style: .segmented, defaultValue: .some(nil))
        SettingRow(L("Raw value for 0%")) {
            NumberField(L("Raw value for 0%"),
                        value: Binding(get: { Double(t.wrappedValue.minimum) },
                                       set: { t.wrappedValue.minimum = UInt16(clamping: Int($0)) }),
                        in: 0...65535, step: 1, format: .plain(digits: 0))
        }
        SettingRow(L("Raw value for 100%"), help: t.wrappedValue.maximum == nil ? L("The value the display reports.") : nil,
                   isDefault: t.wrappedValue.maximum == nil, reset: { t.wrappedValue.maximum = nil }, resetGlyph: true) {
            NumberField(L("Raw value for 100%"),
                        value: Binding(get: { Double(t.wrappedValue.maximum.map(Int.init) ?? Int(reported)) },
                                       set: { t.wrappedValue.maximum = UInt16(clamping: Int($0)) }),
                        in: 1...65535, step: 1, format: .plain(digits: 0))
        }
        ToggleSetting(L("Invert"), isOn: Binding(get: { t.wrappedValue.inverted }, set: { t.wrappedValue.inverted = $0 }))
        PickerSetting(L("Show in the menu"),
                      selection: Binding(get: { t.wrappedValue.showInMenu }, set: { t.wrappedValue.showInMenu = $0 }),
                      options: [PickerOption<Bool?>(nil, L("Default")), PickerOption<Bool?>(true, L("Show")),
                                PickerOption<Bool?>(false, L("Hide"))],
                      style: .segmented, defaultValue: .some(nil))
        SliderSetting(L("Read back every"), help: L("0 uses the shared interval."),
                      value: Binding(get: { t.wrappedValue.readbackInterval }, set: { t.wrappedValue.readbackInterval = $0 }),
                      in: 0...60, step: 0.5, defaultValue: DDCControlTuning().readbackInterval, format: .seconds)
    }

    // MARK: Inputs

    private func inputList(_ controller: DDCController, _ key: DisplayKey) -> Binding<[DDCInputEntry]> {
        let config = env.config
        return Binding(get: { controller.inputList(for: key, includeHidden: true) }, set: { value in
            var entry = config.value.perDisplay[key] ?? PerDisplayConfig()
            let list = Array(value.prefix(PerDisplayDDC.maxInputs))
            guard entry.ddc.inputs != list else { return }
            entry.ddc.inputs = list
            config.value.perDisplay[key] = entry
        })
    }

    @ViewBuilder
    private func inputsSection(_ controller: DDCController, _ key: DisplayKey) -> some View {
        let list = inputList(controller, key)
        Section {
            ReorderableList(list, onDelete: { item in
                list.wrappedValue = list.wrappedValue.filter { $0.id != item.id }
            }, confirmDelete: { entry in
                L("Delete “\(entry.name.isEmpty ? VCPPolicy.inputName(entry.value) : TextSanitizer.clean(entry.name, maxScalars: 64))”?")
            }) { entry in
                HStack {
                    TextField(VCPPolicy.inputName(entry.value), text: Binding(get: { entry.name }, set: { name in
                        var l = list.wrappedValue
                        guard let i = l.firstIndex(where: { $0.id == entry.id }) else { return }
                        l[i].name = String(name.prefix(64))
                        list.wrappedValue = l
                    }))
                    .accessibilityLabel(L("Name of \(VCPPolicy.inputName(entry.value))"))
                    Text(String(format: entry.lgAlt ? "LG %02X" : "%02X", Int(entry.value)))
                        .monospaced()
                        .foregroundStyle(.secondary)
                    Toggle(L("Hide"), isOn: Binding(get: { entry.hidden }, set: { hidden in
                        var l = list.wrappedValue
                        guard let i = l.firstIndex(where: { $0.id == entry.id }) else { return }
                        l[i].hidden = hidden
                        list.wrappedValue = l
                    }))
                    .toggleStyle(.checkbox)
                }
            }
            .modifier(SettingsAnchor(ControlID("displays.hardware.advanced.inputs")))
            HStack {
                Menu(L("Add Input")) {
                    ForEach([UInt16](DisplaysUIText.commonInputs), id: \.self) { value in
                        Button(VCPPolicy.inputName(value)) { add(list, DDCInputEntry(value: value, name: "")) }
                    }
                    Divider()
                    ForEach([UInt16](DisplaysUIText.commonInputs), id: \.self) { value in
                        Button(L("LG alternate: \(VCPPolicy.inputName(value))")) {
                            add(list, DDCInputEntry(value: value, name: "", lgAlt: true))
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button(L("Reset List")) { list.wrappedValue = [] }
            }
        } header: {
            Text(L("Inputs"))
        } footer: {
            Text(L("Drag to reorder. LG alternate inputs use LG’s own command, which some LG displays need for USB-C and DisplayPort."))
        }
    }

    private func add(_ list: Binding<[DDCInputEntry]>, _ entry: DDCInputEntry) {
        guard !list.wrappedValue.contains(where: { $0.id == entry.id }) else { return }
        list.wrappedValue = list.wrappedValue + [entry]
    }

    // MARK: Custom controls

    private func customList(_ key: DisplayKey) -> Binding<[DDCCustomControl]> {
        let config = env.config
        return Binding(get: { config.value.perDisplay[key]?.ddc.customControls ?? [] }, set: { value in
            var entry = config.value.perDisplay[key] ?? PerDisplayConfig()
            let list = Array(value.prefix(PerDisplayDDC.maxCustom))
            guard entry.ddc.customControls != list else { return }
            entry.ddc.customControls = list
            config.value.perDisplay[key] = entry
        })
    }

    @ViewBuilder
    private func customSection(_ controller: DDCController, _ key: DisplayKey, _ per: PerDisplayDDC) -> some View {
        let list = customList(key)
        Section {
            ReorderableList(list, onDelete: { item in
                list.wrappedValue = list.wrappedValue.filter { $0.id != item.id }
            }, confirmDelete: { control in
                L("Delete “\(control.name.isEmpty ? VCPPolicy.name(control.code) : TextSanitizer.clean(control.name, maxScalars: 64))”?")
            }) { control in
                HStack {
                    Text((control.name.isEmpty ? VCPPolicy.name(control.code) : TextSanitizer.clean(control.name, maxScalars: 64))
                         + " (" + VCPPolicy.hex(control.code) + ")")
                    Spacer()
                    if control.kind == .command {
                        Text("= \(control.value)").monospaced().foregroundStyle(.secondary)
                    }
                    Toggle(L("In menu"), isOn: Binding(get: { control.showInMenu }, set: { on in
                        var l = list.wrappedValue
                        guard let i = l.firstIndex(where: { $0.id == control.id }) else { return }
                        l[i].showInMenu = on
                        list.wrappedValue = l
                    }))
                    .toggleStyle(.checkbox)
                }
            }
            .modifier(SettingsAnchor(ControlID("displays.hardware.advanced.customList")))
            HStack {
                TextField(L("Name"), text: $newCustomName)
                TextField(L("Code"), text: $newCustomCode)
                    .frame(width: 64)
                Picker(L("Kind"), selection: $newCustomKind) {
                    Text(L("Slider")).tag(DDCCustomControl.Kind.range)
                    Text(L("Command")).tag(DDCCustomControl.Kind.command)
                }
                .labelsHidden()
                .fixedSize()
                if newCustomKind == .command {
                    TextField(L("Value"), text: $newCustomValue)
                        .frame(width: 64)
                }
                Button(L("Add")) {
                    guard let code = VCPPolicy.parseCode(newCustomCode) else { return }
                    let value = newCustomKind == .command ? (HardwareControlText.parseValue(newCustomValue) ?? 0) : 0
                    list.wrappedValue = list.wrappedValue + [DDCCustomControl(name: String(newCustomName.prefix(64)),
                                                                              code: code, kind: newCustomKind, value: value)]
                    newCustomName = ""
                    newCustomCode = ""
                    newCustomValue = ""
                }
                .disabled(VCPPolicy.parseCode(newCustomCode) == nil || per.customControls.count >= PerDisplayDDC.maxCustom)
            }
        } header: {
            Text(L("Custom controls"))
        } footer: {
            Text(L("Codes that can switch the picture away or change power ask first; E0–FF need an unlock below; reset codes are never sent."))
        }
    }

    // MARK: Raw commands

    @ViewBuilder
    private func rawSection(_ context: DisplaysContext, _ controller: DDCController, _ key: DisplayKey,
                            _ per: PerDisplayDDC) -> some View {
        Section {
            CRevealDisclosure(L("Raw commands"), ids: [ControlID("displays.hardware.advanced.raw")]) {
                HStack {
                    TextField(L("Code"), text: $rawCode)
                        .frame(width: 72)
                    TextField(L("Value"), text: $rawValue)
                        .frame(width: 72)
                    Button(L("Read")) { readRaw(context, key) }
                    Button(L("Send")) { sendRaw(context, controller, key) }
                    Spacer()
                }
                if let rawResult {
                    Text(rawResult).monospaced().textSelection(.enabled)
                }
                HStack {
                    TextField(L("Manufacturer code to unlock (E0–FF)"), text: $unlockText)
                    Button(L("Unlock")) { unlock(key) }
                }
                if let unlockMessage {
                    Text(unlockMessage).foregroundStyle(.secondary)
                }
                if !per.unlockedCodes.isEmpty {
                    HStack {
                        Text(L("Unlocked: \(per.unlockedCodes.map(\.rawValue).joined(separator: " "))")).monospaced()
                        Spacer()
                        Button(L("Lock All")) { CBind.display(env.config, key, \.ddc.unlockedCodes).wrappedValue = [] }
                    }
                }
            }
            .modifier(SettingsAnchor(ControlID("displays.hardware.advanced.raw")))
        } footer: {
            Text(L("Manufacturer codes do different things on every display; an unlocked code still asks before each write."))
        }
    }

    private func readRaw(_ context: DisplaysContext, _ key: DisplayKey) {
        guard let code = VCPPolicy.parseCode(rawCode) else {
            rawResult = L("That isn’t a code from 00 to FF.")
            return
        }
        let ddc = context.ddc
        rawResult = L("Reading…")
        context.lifetime.spawn {
            if let r = await ddc.read(code, from: key) {
                rawResult = "\(VCPPolicy.hex(code)) = \(r.current) / \(r.max)"
            } else {
                rawResult = L("No reply.")
            }
        }
    }

    private func sendRaw(_ context: DisplaysContext, _ controller: DDCController, _ key: DisplayKey) {
        guard let code = VCPPolicy.parseCode(rawCode), let value = HardwareControlText.parseValue(rawValue) else {
            rawResult = L("Enter a code and a value.")
            return
        }
        rawResult = L("Sending…")
        context.lifetime.spawn {
            let ok = await controller.write(code, value, to: key)
            rawResult = ok ? L("Sent.") : L("Refused, not confirmed, or no reply.")
        }
    }

    private func unlock(_ key: DisplayKey) {
        guard let code = VCPPolicy.parseCode(unlockText),
              VCPPolicy.tier(code: code, value: 0, capabilities: nil) == .unlockable else {
            unlockMessage = L("Only manufacturer codes E0–FF that Snaptic doesn’t always ask about can be unlocked.")
            return
        }
        let codes = CBind.display(env.config, key, \.ddc.unlockedCodes)
        if !codes.wrappedValue.contains(VCPKey(code)), codes.wrappedValue.count < PerDisplayDDC.maxUnlocked {
            codes.wrappedValue = codes.wrappedValue + [VCPKey(code)]
        }
        unlockText = ""
        unlockMessage = L("Unlocked \(VCPPolicy.hex(code)) for this display.")
    }

    // MARK: Timing

    @ViewBuilder
    private func timingSection(_ key: DisplayKey, _ per: PerDisplayDDC) -> some View {
        let defaults = PerDisplayDDC()
        Section {
            StepperSetting(L("Reply delay"), help: L("Milliseconds to wait for a reply."),
                           value: CBind.display(env.config, key, \.ddc.replyDelayMs), in: 10...200, step: 10,
                           defaultValue: defaults.replyDelayMs, format: .plain(digits: 0),
                           anchor: ControlID("displays.hardware.advanced.replyDelay"))
            StepperSetting(L("Retries"), value: CBind.display(env.config, key, \.ddc.retries), in: 0...8,
                           defaultValue: defaults.retries, format: .plain(digits: 0),
                           anchor: ControlID("displays.hardware.advanced.retries"))
            ToggleSetting(L("Send every change twice"), help: L("For displays that sometimes miss a change."),
                          isOn: Binding(get: { per.writeCount > 1 }, set: { [env] on in
                              CBind.display(env.config, key, \.ddc.writeCount).wrappedValue = on ? 2 : 1
                          }),
                          anchor: ControlID("displays.hardware.advanced.writeTwice"))
            ToggleSetting(L("Ignore reply checksums"), help: L("For displays whose replies always fail the check."),
                          isOn: CBind.display(env.config, key, \.ddc.ignoreChecksum),
                          anchor: ControlID("displays.hardware.advanced.ignoreChecksum"))
            ButtonRow(L("Forget Learned Framing"), help: L("Snaptic learns again how this display frames its replies."),
                      control: ControlID("displays.hardware.advanced.forgetFraming")) { [env] in
                CBind.display(env.config, key, \.ddc.framing).wrappedValue = nil
            }
            .disabled(per.framing == nil)
        } header: {
            Text(L("Timing"))
        }
    }

    // MARK: Hardware information

    @ViewBuilder
    private func informationSection(_ context: DisplaysContext, _ key: DisplayKey) -> some View {
        let ddc = context.ddc
        Section {
            CRevealDisclosure(L("Hardware information"), ids: [ControlID("displays.hardware.advanced.information")]) {
                LabeledContent(L("Status")) {
                    switch ddc.linkStatus(key) {
                    case .ok: Text(L("Responding"))
                    case .failed: Text(L("No reply"))
                    case .unknown: Text(L("Not checked yet"))
                    }
                }
                if let transport = ddc.transportDescription(key) {
                    LabeledContent(L("Connection")) { Text(transport) }
                }
                if let framing = ddc.framing(key) {
                    LabeledContent(L("Framing")) { Text(framing.rawValue) }
                }
                LabeledContent(L("Writes today")) { Text(String(ddc.writesToday(key))).monospacedDigit() }
                if let caps = ddc.cachedCapabilities(key) {
                    if let model = caps.model {
                        LabeledContent(L("Model")) { Text(TextSanitizer.clean(model, maxScalars: 64)) }
                    }
                    if let mccs = caps.mccsVersion {
                        LabeledContent(L("MCCS")) { Text(TextSanitizer.clean(mccs, maxScalars: 16)) }
                    }
                    LabeledContent(L("Supported codes")) {
                        Text(caps.vcp.keys.sorted().map { VCPPolicy.hex($0) }.joined(separator: " "))
                            .monospaced()
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
                HStack {
                    Button(capsLoading ? L("Reading…") : L("Read Capabilities")) {
                        capsLoading = true
                        context.lifetime.spawn {
                            _ = await ddc.capabilities(of: key, refresh: true)
                            capsLoading = false
                            context.runtime.revision(.ddc).bump()
                        }
                    }
                    .disabled(capsLoading)
                    Button(L("Check Connection")) {
                        context.lifetime.spawn {
                            _ = await ddc.probe(key)
                            context.runtime.revision(.ddc).bump()
                        }
                    }
                }
            }
            .modifier(SettingsAnchor(ControlID("displays.hardware.advanced.information")))
        }
    }
}
