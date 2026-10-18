import SwiftUI
import SnapticKit

/// Displays › Color (owner: C; PLAN 0.3 §4.3 sub-page table, route `displays.color`; §4.4 duplicates 8 and 9):
/// header switch "Color adjustments" (`color`); while it's off, what it does. On: display tiles, then for the
/// selected display "Adjust this display" (on = not suspended), Software contrast, Gamma, Temperature, Black level,
/// White level (each a `SliderSetting` with its reset glyph), Invert colors, the color profile (with
/// `colorProfiles`) and the Apple display preset (with `applePresets`). Advanced… holds gain and per-channel
/// gain and gamma, profile actions, the custom-profile safeguard, the shortcut steps, and the Experimental Night
/// Shift and Apple presets; its footer restores this display's or every display's colors.
struct ColorPage: View, ControlDeclaring {
    typealias Controls = ColorPageControls

    static let title = L("Color")
    static let summary = L("Contrast, gamma, temperature, and color profiles in software.")
    static let symbol = "paintpalette.fill"
    static let tint = SettingsTint.purple
    static let switchTitle = L("Color adjustments")

    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "displays.color.adjust", symbol: "slider.horizontal.3", title: L("Adjust any display"),
                         text: L("Contrast, gamma, temperature, and levels in software, also for displays without controls.")),
        FeatureHighlight(id: "displays.color.profiles", symbol: "paintpalette", title: L("Color profiles"),
                         text: L("Switch a display’s ICC profile here or from the menu.")),
        FeatureHighlight(id: "displays.color.undo", symbol: "arrow.counterclockwise", title: L("Always undoable"),
                         text: L("Each slider resets on its own, and Restore All Displays undoes every change.")),
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
            ColorPageContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

private struct ColorPageContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var colorRevision: ControllerRevision
    @ObservedObject private var systemColorsRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @StateObject private var colorSettings: ConfigSlice<DisplaysConfig, ColorConfig>
    @StateObject private var switcher: DisplaysFeatureSwitcher

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _colorRevision = ObservedObject(wrappedValue: env.runtime.revision(.color))
        _systemColorsRevision = ObservedObject(wrappedValue: env.runtime.revision(.systemColors))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
        _colorSettings = StateObject(wrappedValue: ConfigSlice(env.config, \.color))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        let isOn = FeatureGraph.rawState(.color, in: features.value)
        SettingsPageScaffold(route: SettingsRoute(ColorPageControls.surface)) {
            SettingsPageHeader(ColorPage.title, summary: ColorPage.summary, symbol: ColorPage.symbol, tint: ColorPage.tint,
                               isOn: switcher.binding([.color], title: ColorPage.switchTitle),
                               switchLabel: ColorPage.switchTitle, control: ControlID("displays.color.enabled"))
            if !isOn {
                FeatureHighlights(ColorPage.highlights)
            } else if let context {
                if !runtime.isEffective(.color) {
                    CFeatureOffSection(title: ColorPage.switchTitle, feature: .color, isOn: true, context: context,
                                       switcher: switcher)
                } else {
                    if displays.count > 1 {
                        Section {
                            PerDisplayPicker(CDisplays.tiles(displays), selection: $shell.selectedDisplay)
                                .modifier(SettingsAnchor(ControlID("displays.color.display")))
                        }
                    }
                    if let display {
                        adjustmentsSection(context, display)
                        profileSection(context, display)
                    }
                }
            } else {
                CDisplaysOffSection(runtime: runtime, running: host.isRunning(.displays))
            }
            PageFooterButtons(advanced: { shell.openSheet = ColorPageControls.advancedSheet },
                              help: SettingsRoute(ColorPageControls.surface),
                              advancedControl: ControlID("displays.color.advancedButton"))
        }
        .sheet(isPresented: shell.sheetBinding(ColorPageControls.advancedSheet)) {
            ColorAdvancedSheet(env: env, host: host)
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    // MARK: Adjustments

    @ViewBuilder
    private func adjustmentsSection(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let key = display.key
        let entry = perDisplay.value[key]?.color ?? PerDisplayColor()
        let paused = entry.suspended || colorSettings.value.suspendAll
        let unavailable = context.gamma.colorController.flatMap { $0.canAdjust(display) ? nil : $0.reasonUnavailable(display) }
        Section {
            if let unavailable {
                StatusRow(unavailable, style: .warning)
            }
            ToggleSetting(L("Adjust this display"),
                          help: L("Turn off to see this display’s own colors; your settings stay."),
                          isOn: SettingsBinding.inverted(CBind.display(env.config, key, \.color.suspended)),
                          anchor: ControlID("displays.color.adjustDisplay"))
            Group {
                ColorSlider(env: env, key: key, title: L("Software contrast"), path: \.contrast,
                            range: ColorAdjustments.contrastRange, step: 0.01, format: .percent(of: 1),
                            anchor: ControlID("displays.color.contrast"))
                ColorSlider(env: env, key: key, title: L("Gamma"), help: L("Above 1 lifts the mid-tones."), path: \.gamma,
                            range: ColorAdjustments.gammaRange, step: 0.01, format: .plain(digits: 2),
                            anchor: ControlID("displays.color.gamma"))
                ColorSlider(env: env, key: key, title: L("Temperature"), help: L("Lower is warmer."), path: \.temperature,
                            range: ColorAdjustments.temperatureRange, step: 50, format: .kelvin,
                            anchor: ControlID("displays.color.temperature"))
                ColorSlider(env: env, key: key, title: L("Black level"), path: \.blackLevel,
                            range: ColorAdjustments.blackLevelRange, step: 0.01, format: .percent(of: 1),
                            anchor: ControlID("displays.color.blackLevel"))
                ColorSlider(env: env, key: key, title: L("White level"), path: \.whiteLevel,
                            range: ColorAdjustments.whiteLevelRange, step: 0.01, format: .percent(of: 1),
                            anchor: ControlID("displays.color.whiteLevel"))
                ToggleSetting(L("Invert colors"),
                              isOn: CBind.display(env.config, key, \.color.adjustments.inverted),
                              anchor: ControlID("displays.color.invert"))
            }
            .disabled(paused || unavailable != nil)
        } header: {
            Text(L("Adjustments for “\(CDisplays.name(display))”"))
        } footer: {
            if colorSettings.value.suspendAll {
                Text(L("Adjustments are paused on every display (Advanced)."))
            } else {
                Text(L("Adjustments show in screenshots and don’t reach AirPlay, DisplayLink, or Sidecar displays. Restore All Displays resets them until you change something."))
            }
        }
    }

    // MARK: Color profile and Apple preset

    @ViewBuilder
    private func profileSection(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let key = display.key
        let showsProfiles = runtime.isEffective(.colorProfiles)
        let presets = runtime.isEffective(.applePresets) ? context.monitorPanel.presetList(for: key) : []
        if showsProfiles || !presets.isEmpty {
            Section {
                if showsProfiles {
                    profilePicker(context, key)
                }
                if !presets.isEmpty {
                    presetPicker(context, key, presets)
                }
            }
        }
    }

    private func profilePicker(_ context: DisplaysContext, _ key: DisplayKey) -> some View {
        let colorSync = context.colorSync
        let profiles = colorSync.installedProfiles()
        let selection = Binding<URL?>(get: {
            colorSync.hasCustomProfile(for: key) ? colorSync.currentProfile(for: key)?.url : nil
        }, set: { url in
            let profile = url.flatMap { u in profiles.first { $0.url == u } }
            if let controller = colorSync.systemColors {
                controller.applyProfile(profile, to: key)
            } else {
                _ = colorSync.setProfile(profile?.url, for: key)
                context.gamma.refreshSafeguard()
            }
        })
        return PickerSetting(L("Color profile"), help: L("A custom profile turns color-table dimming off unless you keep it in Advanced."),
                             selection: selection,
                             options: [PickerOption<URL?>(nil, L("Factory profile"))]
                                 + profiles.map { PickerOption<URL?>($0.url, TextSanitizer.clean($0.name, maxScalars: 64)) },
                             style: .popUp, defaultValue: .some(nil), anchor: ControlID("displays.color.profile"))
    }

    private func presetPicker(_ context: DisplaysContext, _ key: DisplayKey, _ presets: [AppleDisplayPreset]) -> some View {
        let selection = Binding<Int?>(get: { presets.first(where: \.isActive)?.id }, set: { id in
            guard let id, let preset = presets.first(where: { $0.id == id }) else { return }
            if let controller = context.colorSync.systemColors {
                controller.applyPreset(preset, to: key)
            } else {
                _ = context.monitorPanel.applyPreset(id: preset.id, for: key)
            }
        })
        var options = presets.map { PickerOption<Int?>($0.id, TextSanitizer.clean($0.name, maxScalars: 64)) }
        if !presets.contains(where: \.isActive) { options.insert(PickerOption<Int?>(nil, L("Unknown")), at: 0) }
        return PickerSetting(L("Apple display preset"),
                             help: L("Presets with a fixed brightness hand brightness to software dimming."),
                             selection: selection, options: options, style: .popUp, defaultValue: nil,
                             anchor: ControlID("displays.color.applePreset"))
    }
}

/// One software color slider of the selected display; the reset glyph brings back the neutral value.
private struct ColorSlider: View {
    let env: DisplaysPageEnvironment
    let key: DisplayKey
    let title: String
    var help: String?
    let path: WritableKeyPath<ColorAdjustments, Double>
    let range: ClosedRange<Double>
    let step: Double
    let format: ValueFormat
    let anchor: ControlID
    var subordinate = false

    init(env: DisplaysPageEnvironment, key: DisplayKey, title: String, help: String? = nil,
         path: WritableKeyPath<ColorAdjustments, Double>, range: ClosedRange<Double>, step: Double, format: ValueFormat,
         anchor: ControlID, subordinate: Bool = false) {
        self.env = env
        self.key = key
        self.title = title
        self.help = help
        self.path = path
        self.range = range
        self.step = step
        self.format = format
        self.anchor = anchor
        self.subordinate = subordinate
    }

    var body: some View {
        SliderSetting(title, help: help,
                      value: CBind.display(env.config, key, (\PerDisplayConfig.color.adjustments).appending(path: path)),
                      in: range, step: step, defaultValue: ColorAdjustments()[keyPath: path], format: format,
                      anchor: anchor, subordinate: subordinate)
    }
}

// MARK: - Advanced

/// Color › Advanced… (PLAN 0.3 §4.3 "A" column): profiles, the selected display's gain and per-channel gain and
/// gamma, every-display settings, and the Experimental Night Shift and Apple presets. Restore Color Defaults… asks
/// "This Display" or "All Displays" (replaces 0.2's Reset This Display). Never presents another sheet.
private struct ColorAdvancedSheet: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var systemColorsRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var colorSettings: ConfigSlice<DisplaysConfig, ColorConfig>
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @State private var askScope = false

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _systemColorsRevision = ObservedObject(wrappedValue: env.runtime.revision(.systemColors))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _colorSettings = StateObject(wrappedValue: ConfigSlice(env.config, \.color))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        let colorOn = FeatureGraph.rawState(.color, in: features.value)
        AdvancedSheet(L("Color Advanced Settings"),
                      restoreDefaults: RestoreDefaults(title: L("Restore Color Defaults…"), destructive: false,
                                                       confirmsItself: { askScope = true }),
                      restoreControl: ControlID("displays.color.advanced.restoreDefaults")) {
            profilesSection(context, display)
            if colorOn, runtime.isEffective(.color), let display {
                channelsSection(display)
            }
            if colorOn {
                allDisplaysSection
            }
            experimentalSection(context)
        }
        .confirmationDialog(L("Restore color settings to their defaults?"), isPresented: $askScope) {
            if let display {
                Button(L("Only “\(CDisplays.name(display))”")) { restore(display.key) }
            }
            Button(L("All Displays")) { restore(nil) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Brightness, the menu bar overlays, and your other settings stay as they are."))
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
        .onAppear { context?.colorSync.systemColors?.refreshNightShift() }
    }

    private func restore(_ key: DisplayKey?) {
        let next = env.config.value.restoringColorDefaults(for: key)
        if next != env.config.value { env.config.value = next }
    }

    private func feature(_ feature: DisplayFeature, _ title: String) -> Binding<Bool> {
        switcher.binding([feature], title: title)
    }

    // MARK: Profiles

    @ViewBuilder
    private func profilesSection(_ context: DisplaysContext?, _ display: DisplayInfo?) -> some View {
        Section {
            ToggleSetting(L("Color profiles"), help: L("Choose each display’s ICC profile here and in the menu."),
                          isOn: feature(.colorProfiles, L("Color profiles")),
                          anchor: ControlID("displays.color.advanced.colorProfiles"),
                          disabledReason: switcher.unavailableReason([.colorProfiles]))
            if let context, let display, runtime.isEffective(.colorProfiles) {
                profileActions(context, display)
            }
            ToggleSetting(L("Keep color-table dimming with custom profiles"),
                          help: L("On recent macOS this can leave a display black after wake."),
                          isOn: Binding(get: { colorSettings.value.allowGammaWithCustomProfile }, set: { [env] on in
                              guard env.config.value.color.allowGammaWithCustomProfile != on else { return }
                              env.config.value.color.allowGammaWithCustomProfile = on
                              env.context?.gamma.refreshSafeguard()
                          }),
                          anchor: ControlID("displays.color.advanced.keepColorTable"))
            if context?.gamma.blockedByCustomProfile == true {
                SettingsRowNote(L("A custom profile is active, so the overlay dims and color adjustments are off."))
            }
        } header: {
            Text(L("Color profiles"))
        }
    }

    private func profileActions(_ context: DisplaysContext, _ display: DisplayInfo) -> some View {
        let colorSync = context.colorSync
        let key = display.key
        let current = colorSync.currentProfile(for: key)
        return LabeledContent {
            ActionMenuButton(L("Profile"), items: [
                ActionMenuItem(id: "finder", title: L("Show in Finder"), enabled: current != nil) {
                    if let current { colorSync.showInFinder(current) }
                },
                ActionMenuItem(id: "colorSync", title: L("Open in ColorSync Utility"), enabled: current != nil) {
                    if let current { colorSync.openInColorSyncUtility(current) }
                },
                ActionMenuItem(id: "previous", title: L("Restore Previous Profile"), enabled: colorSync.canRestorePrevious) {
                    colorSync.restorePrevious(for: key)
                    context.gamma.refreshSafeguard()
                },
            ], primaryAction: nil, control: ControlID("displays.color.advanced.profileActions"))
        } label: {
            Text(L("Profile of “\(CDisplays.name(display))”"))
            Text(current.map { TextSanitizer.clean($0.name, maxScalars: 64) } ?? L("Factory profile"))
        }
    }

    // MARK: Gain and channels

    @ViewBuilder
    private func channelsSection(_ display: DisplayInfo) -> some View {
        let key = display.key
        Section {
            ColorSlider(env: env, key: key, title: L("Gain"), path: \.gain, range: ColorAdjustments.gainRange, step: 0.01,
                        format: .percent(of: 1), anchor: ControlID("displays.color.advanced.gain"))
            ColorSlider(env: env, key: key, title: L("Red gain"), path: \.red, range: ColorAdjustments.gainRange,
                        step: 0.01, format: .percent(of: 1), anchor: ControlID("displays.color.advanced.redGain"))
            ColorSlider(env: env, key: key, title: L("Green gain"), path: \.green, range: ColorAdjustments.gainRange,
                        step: 0.01, format: .percent(of: 1), anchor: ControlID("displays.color.advanced.greenGain"))
            ColorSlider(env: env, key: key, title: L("Blue gain"), path: \.blue, range: ColorAdjustments.gainRange,
                        step: 0.01, format: .percent(of: 1), anchor: ControlID("displays.color.advanced.blueGain"))
            ColorSlider(env: env, key: key, title: L("Red gamma"), path: \.redGamma, range: ColorAdjustments.gammaRange,
                        step: 0.01, format: .plain(digits: 2), anchor: ControlID("displays.color.advanced.redGamma"))
            ColorSlider(env: env, key: key, title: L("Green gamma"), path: \.greenGamma, range: ColorAdjustments.gammaRange,
                        step: 0.01, format: .plain(digits: 2), anchor: ControlID("displays.color.advanced.greenGamma"))
            ColorSlider(env: env, key: key, title: L("Blue gamma"), path: \.blueGamma, range: ColorAdjustments.gammaRange,
                        step: 0.01, format: .plain(digits: 2), anchor: ControlID("displays.color.advanced.blueGamma"))
        } header: {
            Text(L("Gain and channels for “\(CDisplays.name(display))”"))
        }
    }

    // MARK: Every display

    private var allDisplaysSection: some View {
        Section {
            ToggleSetting(L("Pause adjustments on all displays"), help: L("Shows every display’s own colors; brightness stays."),
                          isOn: SettingsBinding.store(env.config, \.color.suspendAll),
                          anchor: ControlID("displays.color.advanced.suspendAll"))
            SliderSetting(L("Contrast and gamma step"), help: L("How much the contrast and gamma shortcuts change at a time."),
                          value: SettingsBinding.store(env.config, \.color.shortcutStep), in: 0.01...0.25, step: 0.01,
                          defaultValue: ColorConfig().shortcutStep, format: .percent(of: 1),
                          anchor: ControlID("displays.color.advanced.shortcutStep"))
            SliderSetting(L("Temperature step"), help: L("How much the temperature shortcuts change at a time."),
                          value: SettingsBinding.store(env.config, \.color.temperatureStep), in: 50...1000, step: 50,
                          defaultValue: ColorConfig().temperatureStep, format: .kelvin,
                          anchor: ControlID("displays.color.advanced.temperatureStep"))
        } header: {
            Text(L("All displays"))
        }
    }

    // MARK: Experimental

    @ViewBuilder
    private func experimentalSection(_ context: DisplaysContext?) -> some View {
        Section {
            ToggleSetting(L("Night Shift controls"), help: L("Turn Night Shift on and set its warmth from Snaptic."),
                          isOn: feature(.nightShift, L("Night Shift controls")),
                          anchor: ControlID("displays.color.advanced.nightShift"), badge: .experimental,
                          disabledReason: switcher.unavailableReason([.nightShift]))
            if runtime.isEffective(.nightShift), let controller = context?.colorSync.systemColors {
                ToggleSetting(L("Night Shift"), help: L("Schedules stay in System Settings › Displays › Night Shift."),
                              isOn: Binding(get: { controller.nightShiftOn ?? false }, set: { on in
                                  if on != (controller.nightShiftOn ?? false) { _ = controller.toggleNightShift() }
                              }),
                              subordinate: true, anchor: ControlID("displays.color.advanced.nightShiftOn"))
                SliderSetting(L("Night Shift warmth"),
                              value: Binding(get: { controller.nightShiftStrength ?? 0.5 },
                                             set: { controller.setNightShiftStrength($0) }),
                              in: 0...1, step: 0.05, defaultValue: nil, format: .percent(of: 1),
                              anchor: ControlID("displays.color.advanced.nightShiftWarmth"), subordinate: true)
            }
            ToggleSetting(L("Apple display presets"),
                          help: L("Switch reference modes on Apple displays here and in the menu."),
                          isOn: feature(.applePresets, L("Apple display presets")),
                          anchor: ControlID("displays.color.advanced.applePresets"), badge: .experimental,
                          disabledReason: switcher.unavailableReason([.applePresets]))
        } header: {
            Text(L("Experimental"))
        }
    }
}
