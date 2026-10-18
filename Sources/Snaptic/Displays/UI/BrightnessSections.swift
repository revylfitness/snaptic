import SwiftUI
import SnapticKit

/// The sections of Brightness and Dimming (owner: C; PLAN 0.3 §4.3): restore at login and wake, smooth transitions
/// and nits; sync (two or more displays; source and follow mode, and for the selected display whether it follows
/// and its offset); extra brightness (XDR displays only, Beta; the selected display's maximum, shown in nits, and
/// the battery floor); dimming on lock and to black. Each feature switch is the feature itself, through Displays'
/// `DisplaysFeatureSwitcher` (it asks before a turn-off that stops other features).
struct BrightnessSections: View, ControlDeclaring {
    typealias Controls = BrightnessSubpageControls

    let env: DisplaysPageEnvironment
    let context: DisplaysContext
    let displays: [DisplayInfo]
    let display: DisplayInfo?
    @ObservedObject var switcher: DisplaysFeatureSwitcher
    let features: [DisplayFeature: Bool]
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var xdrRevision: ControllerRevision
    @ObservedObject private var syncRevision: ControllerRevision
    @StateObject private var settings: ConfigSlice<DisplaysConfig, BrightnessConfig>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>

    init(env: DisplaysPageEnvironment, context: DisplaysContext, displays: [DisplayInfo], display: DisplayInfo?,
         switcher: DisplaysFeatureSwitcher, features: [DisplayFeature: Bool]) {
        self.env = env
        self.context = context
        self.displays = displays
        self.display = display
        _switcher = ObservedObject(wrappedValue: switcher)
        self.features = features
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _xdrRevision = ObservedObject(wrappedValue: env.runtime.revision(.xdr))
        _syncRevision = ObservedObject(wrappedValue: env.runtime.revision(.sync))
        _settings = StateObject(wrappedValue: ConfigSlice(env.config, \.brightness))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
    }

    var body: some View {
        generalSection
        if displays.count > 1 { syncSection }
        if displays.contains(where: Self.isXDR) { extraBrightnessSection }
        dimmingSection
    }

    // MARK: Helpers

    private func raw(_ feature: DisplayFeature) -> Bool { FeatureGraph.rawState(feature, in: features) }

    private func feature(_ feature: DisplayFeature, _ title: String) -> Binding<Bool> {
        switcher.binding([feature], title: title)
    }

    private func perDisplayBrightness(_ key: DisplayKey) -> PerDisplayBrightness {
        perDisplay.value[key]?.brightness ?? PerDisplayBrightness()
    }

    static func isXDR(_ display: DisplayInfo) -> Bool { display.edrPotential > 1.01 }

    // MARK: Restore, smooth transitions, nits

    private var restoreChoice: Binding<BrightnessRestoreMode> {
        let config = env.config
        let restoreFeature = feature(.brightnessRestore, L("Restore brightness"))
        return Binding(get: {
            BrightnessRestoreChoice.shown(featureOn: restoreFeature.wrappedValue, mode: config.value.brightness.restoreMode)
        }, set: { choice in
            let stored = BrightnessRestoreChoice.stored(choice, current: config.value.brightness.restoreMode)
            if config.value.brightness.restoreMode != stored.mode { config.value.brightness.restoreMode = stored.mode }
            if restoreFeature.wrappedValue != stored.featureOn { restoreFeature.wrappedValue = stored.featureOn }
        })
    }

    private var showNits: Binding<Bool> {
        let config = env.config
        let nitsFeature = feature(.nits, L("Show brightness in nits"))
        return Binding(get: {
            nitsFeature.wrappedValue && config.value.brightness.showNits
        }, set: { on in
            if config.value.brightness.showNits != on { config.value.brightness.showNits = on }
            // Off keeps the nits model (Advanced's custom range still applies); on needs it.
            if on, !nitsFeature.wrappedValue { nitsFeature.wrappedValue = true }
        })
    }

    @ViewBuilder private var generalSection: some View {
        let defaultRestore = BrightnessRestoreChoice.shown(featureOn: FeatureGraph.isOnByDefault(.brightnessRestore),
                                                           mode: BrightnessConfig().restoreMode)
        Section {
            PickerSetting(L("Restore brightness at login and wake"),
                          help: L("Brings back each display’s brightness after login, wake, and reconnecting."),
                          selection: restoreChoice,
                          options: [
                              PickerOption(BrightnessRestoreMode.brightness, L("Brightness and color")),
                              PickerOption(BrightnessRestoreMode.adjustmentsOnly, L("Color adjustments only")),
                              PickerOption(BrightnessRestoreMode.off, L("Off")),
                          ],
                          style: .popUp, defaultValue: defaultRestore,
                          anchor: ControlID("displays.brightness.restore"))
            ToggleSetting(L("Smooth transitions"), help: L("Brightness fades to a new level instead of jumping."),
                          isOn: SettingsBinding.store(env.config, \.brightness.smoothTransitions),
                          anchor: ControlID("displays.brightness.smoothTransitions"))
            ToggleSetting(L("Show brightness in nits"),
                          help: L("The menu, the indicator, and Settings show estimated nits next to the percent."),
                          isOn: showNits, anchor: ControlID("displays.brightness.showNits"),
                          disabledReason: switcher.unavailableReason([.nits]))
        } footer: {
            Text(L("Restoring never goes below 15%, and Safe Mode skips it. Nits are estimates unless you enter your display’s values in Advanced."))
        }
    }

    // MARK: Sync

    /// The display the others follow: the chosen one while it's connected, else the built-in display.
    private var sourceKey: DisplayKey? {
        if let chosen = settings.value.syncSource, displays.contains(where: { $0.key == chosen }) { return chosen }
        return displays.first(where: \.isBuiltin)?.key
    }

    @ViewBuilder private var syncSection: some View {
        Section {
            ToggleSetting(L("Sync brightness"), help: L("Other displays follow the brightness of one display."),
                          isOn: feature(.sync, L("Sync brightness")), anchor: ControlID("displays.brightness.sync"),
                          disabledReason: switcher.unavailableReason([.sync]))
            if raw(.sync), runtime.isEffective(.sync) {
                if settings.value.syncPaused {
                    SettingsRowNote(L("Paused from the menu."),
                                    fix: StatusAction(title: L("Resume"),
                                                      control: ControlID("displays.brightness.syncResume")) { [env] in
                                        env.config.value.brightness.syncPaused = false
                                    })
                        .padding(.leading, 20)
                }
                PickerSetting(L("Source"), help: L("The display the others follow."),
                              selection: SettingsBinding.store(env.config, \.brightness.syncSource),
                              options: sourceOptions, style: .popUp, defaultValue: .some(nil),
                              anchor: ControlID("displays.brightness.syncSource"), subordinate: true)
                PickerSetting(L("Follow"),
                              selection: SettingsBinding.store(env.config, \.brightness.syncMode),
                              options: [
                                  PickerOption(SyncMode.absolute, L("The same level"),
                                               help: L("Each display matches the source, plus its offset.")),
                                  PickerOption(SyncMode.delta, L("The same change"),
                                               help: L("Each display moves by as much as the source moved.")),
                              ],
                              style: .popUp, defaultValue: BrightnessConfig().syncMode,
                              anchor: ControlID("displays.brightness.syncMode"), subordinate: true)
                if let display, display.key != sourceKey {
                    followRows(display)
                }
            }
        } header: {
            Text(L("Sync"))
        } footer: {
            if raw(.sync) {
                Text(L("Hold ⇧ with the brightness keys to change one display without syncing."))
            }
        }
    }

    private var sourceOptions: [PickerOption<DisplayKey?>] {
        var options = [PickerOption<DisplayKey?>(nil, L("Built-in display"),
                                                 help: L("Or the first display while the built-in one is closed."))]
        options += displays.map { PickerOption<DisplayKey?>($0.key, CDisplays.name($0)) }
        return options
    }

    @ViewBuilder private func followRows(_ display: DisplayInfo) -> some View {
        let key = display.key
        let follows = CBind.display(env.config, key, \.brightness.syncEnabled)
        ToggleSetting(L("“\(CDisplays.name(display))” follows the source"),
                      help: L("Turn off to keep this display’s brightness separate."),
                      isOn: follows, subordinate: true, anchor: ControlID("displays.brightness.syncFollow"))
        if perDisplayBrightness(key).syncEnabled {
            SliderSetting(L("Offset"), help: L("Keeps this display brighter or darker than the source."),
                          value: CBind.display(env.config, key, \.brightness.syncOffset), in: -0.5...0.5, step: 0.01,
                          defaultValue: PerDisplayBrightness().syncOffset, format: .percent(of: 1),
                          anchor: ControlID("displays.brightness.syncOffset"), subordinate: true)
        }
    }

    // MARK: Extra brightness (XDR)

    @ViewBuilder private var extraBrightnessSection: some View {
        Section {
            ToggleSetting(L("Extra brightness"),
                          help: L("Lets XDR displays go above 100%, up to their HDR peak."),
                          isOn: feature(.xdr, L("Extra brightness")), anchor: ControlID("displays.brightness.xdr"),
                          badge: .beta, disabledReason: switcher.unavailableReason([.xdr]))
            if raw(.xdr), runtime.isEffective(.xdr) {
                if let display, Self.isXDR(display) {
                    xdrDisplayRows(display)
                }
                SliderSetting(L("Pause below battery"),
                              help: L("Extra brightness pauses while the battery is lower than this."),
                              value: SettingsBinding.store(env.config, \.brightness.xdrBatteryFloor),
                              in: BrightnessConfig.batteryFloorRange, step: 0.05,
                              defaultValue: BrightnessConfig().xdrBatteryFloor, format: .percent(of: 1),
                              anchor: ControlID("displays.brightness.xdrBatteryFloor"), subordinate: true)
                if let paused = context.edr.pauseReason {
                    SettingsRowNote(L("Paused: \(paused)"))
                        .padding(.leading, 20)
                }
            }
        } header: {
            Text(L("Extra brightness"))
        } footer: {
            if raw(.xdr) {
                Text(L("Uses more power and heat, and can burn in OLED panels. It pauses when the Mac is hot, in Low Power Mode, on low battery, and while locked."))
            }
        }
    }

    @ViewBuilder private func xdrDisplayRows(_ display: DisplayInfo) -> some View {
        let key = display.key
        let xdr = context.edr.xdrMethod(for: key)
        if xdr.0 == nil {
            SettingsRowNote(xdr.1)
                .padding(.leading, 20)
        } else {
            ToggleSetting(L("Use on “\(CDisplays.name(display))”"),
                          isOn: CBind.display(env.config, key, \.brightness.xdrEnabled), subordinate: true,
                          anchor: ControlID("displays.brightness.xdrDisplay"))
            let maximum = CBind.override(env.config, key, \.brightness.xdrMax, fallback: settings.value.xdrMaxScale)
            SliderSetting(L("Maximum extra brightness"), help: peakHelp(display, scale: maximum.wrappedValue),
                          value: maximum, in: BrightnessConfig.xdrScaleRange, step: 0.05,
                          defaultValue: settings.value.xdrMaxScale, format: .percent(of: 1),
                          anchor: ControlID("displays.brightness.xdrMaximum"), subordinate: true)
        }
    }

    /// "Up to ≈1600 nits on this display." from the nits model (the custom range when one is set).
    private func peakHelp(_ display: DisplayInfo, scale: Double) -> String? {
        guard runtime.isEffective(.nits) else { return nil }
        let range = context.brightness.nitsRange(for: display)
        let nits = NitsModel.nits(hardware: 1, software: 1, xdr: scale, range: range)
        return L("Up to \(NitsModel.label(nits, estimate: range.isEstimate)) on this display.")
    }

    // MARK: Dimming

    @ViewBuilder private var dimmingSection: some View {
        Section {
            ToggleSetting(L("Dim when the screen locks"), help: L("Dims every display while your Mac is locked."),
                          isOn: feature(.dimOnLock, L("Dim when the screen locks")),
                          anchor: ControlID("displays.brightness.dimOnLock"),
                          disabledReason: switcher.unavailableReason([.dimOnLock]))
            if raw(.dimOnLock) {
                SliderSetting(L("Dim to"), help: L("Uses color-table dimming, so overlay-dimmed displays stay as they are."),
                              value: SettingsBinding.store(env.config, \.brightness.dimOnLockLevel),
                              in: BrightnessConfig.dimOnLockFloor...1, step: 0.05,
                              defaultValue: BrightnessConfig().dimOnLockLevel, format: .percent(of: 1),
                              anchor: ControlID("displays.brightness.dimOnLockLevel"), subordinate: true)
            }
            ToggleSetting(L("Dim all the way to black"),
                          help: L("Software dimming can reach black while another display stays visible."),
                          isOn: feature(.dimToBlack, L("Dim all the way to black")),
                          anchor: ControlID("displays.brightness.dimToBlack"),
                          disabledReason: switcher.unavailableReason([.dimToBlack]))
        } header: {
            Text(L("Dimming"))
        } footer: {
            Text(raw(.dimToBlack)
                 ? L("Black needs the safety helper. It rises to 30% while a confirmation or password window shows.")
                 : L("Without it, software dimming stops at 8%."))
        }
    }
}
