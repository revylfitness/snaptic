import SwiftUI
import SnapticKit

/// Color (PLAN §6.2, §6.5, parity §5): software adjustments per display (contrast, gamma
/// and RGB gamma, gain and RGB gain, temperature, levels, invert, suspend), the
/// custom-profile safeguard, ColorSync profiles, Night Shift, Apple display presets,
/// auto-brightness and the menu-bar overlays (strip, rounded corners).
struct ColorPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var selected: DisplayKey?
    @State private var showRGB = false
    @State private var nightShiftStrength: Double = 0.5
    @State private var nightShiftOn = false

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            Section(L("Display")) {
                CDisplayPicker(env: env, selection: $selected)
            }
            if let key = selectedKey {
                adjustmentsSection(key)
                profileSection(key)
                presetsSection(key)
                autoBrightnessSection(key)
                overlaysSection(key)
            }
            safeguardSection
            nightShiftSection
        }
        .formStyle(.grouped)
        .onAppear(perform: loadNightShift)
    }

    private var selectedKey: DisplayKey? {
        let online = env.runtime.displays.filter(\.isOnline)
        if let selected, online.contains(where: { $0.key == selected }) { return selected }
        return online.first(where: \.isMain)?.key ?? online.first?.key
    }

    private var selectedInfo: DisplayInfo? { env.runtime.displays.first { $0.key == selectedKey } }

    // MARK: Adjustments

    private func adj(_ key: DisplayKey, _ path: WritableKeyPath<ColorAdjustments, Double>) -> Binding<Double> {
        let full = (\PerDisplayConfig.color.adjustments).appending(path: path)
        return CBind.display(env, key, full)
    }

    @ViewBuilder
    private func adjustmentsSection(_ key: DisplayKey) -> some View {
        Section(L("Color adjustments")) {
            CFeatureNote(env: env, feature: .color)
            if env.runtime.isEffective(.color) {
                if let reason = unavailableReason(key) {
                    Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
                let suspended = CBind.display(env, key, \.color.suspended)
                Toggle(L("Suspend adjustments on this display"), isOn: suspended)
                Toggle(L("Suspend adjustments on all displays"), isOn: CBind.global(env, \.color.suspendAll))
                Group {
                    CSlider(title: L("Contrast"), value: adj(key, \.contrast), range: ColorAdjustments.contrastRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Gamma"), value: adj(key, \.gamma), range: ColorAdjustments.gammaRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Gain"), value: adj(key, \.gain), range: ColorAdjustments.gainRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Temperature"), value: adj(key, \.temperature), range: ColorAdjustments.temperatureRange,
                            step: 50, format: { String(format: "%.0f K", $0) })
                    CSlider(title: L("Black level"), value: adj(key, \.blackLevel), range: ColorAdjustments.blackLevelRange,
                            step: 0.005)
                    CSlider(title: L("White level"), value: adj(key, \.whiteLevel), range: ColorAdjustments.whiteLevelRange,
                            step: 0.005)
                    Toggle(L("Invert colors"), isOn: CBind.display(env, key, \.color.adjustments.inverted))
                }
                .disabled(suspended.wrappedValue || env.config.value.color.suspendAll)
                DisclosureGroup(L("Red, green and blue"), isExpanded: $showRGB) {
                    CSlider(title: L("Red gain"), value: adj(key, \.red), range: ColorAdjustments.gainRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Green gain"), value: adj(key, \.green), range: ColorAdjustments.gainRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Blue gain"), value: adj(key, \.blue), range: ColorAdjustments.gainRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Red gamma"), value: adj(key, \.redGamma), range: ColorAdjustments.gammaRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Green gamma"), value: adj(key, \.greenGamma), range: ColorAdjustments.gammaRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                    CSlider(title: L("Blue gamma"), value: adj(key, \.blueGamma), range: ColorAdjustments.gammaRange, step: 0.01,
                            format: { String(format: "%.2f", $0) })
                }
                HStack {
                    Spacer()
                    Button(L("Reset This Display")) {
                        var config = env.config.value
                        var per = config.perDisplay[key] ?? PerDisplayConfig()
                        let brightness = per.color.adjustments.brightness
                        per.color.adjustments = ColorAdjustments()
                        per.color.adjustments.brightness = brightness
                        per.color.suspended = false
                        config.perDisplay[key] = per
                        env.config.value = config
                    }
                }
                Text(L("Adjustments use the display's color table, so they show in screenshots and don't apply to AirPlay, DisplayLink or Sidecar. Panic (Restore All Displays) resets them until you change something."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func unavailableReason(_ key: DisplayKey) -> String? {
        guard let ctx = env.context else { return nil }
        if let controller = ctx.gamma.colorController, let info = ctx.registry.info(for: key) {
            return controller.canAdjust(info) ? nil : controller.reasonUnavailable(info)
        }
        return nil
    }

    // MARK: Safeguard

    @ViewBuilder
    private var safeguardSection: some View {
        Section(L("Custom color profiles")) {
            Toggle(L("Keep color-table dimming and adjustments with a custom profile"),
                   isOn: Binding(get: { env.config.value.color.allowGammaWithCustomProfile },
                                 set: { value in
                                     env.config.value.color.allowGammaWithCustomProfile = value
                                     env.context?.gamma.refreshSafeguard()
                                 }))
            if let ctx = env.context, ctx.gamma.blockedByCustomProfile {
                Label(L("A custom profile is active: dimming uses overlays and color adjustments are off."),
                      systemImage: "exclamationmark.triangle")
            }
            Text(L("On recent macOS versions, color tables combined with custom ICC profiles can leave displays black after wake. By default Snaptic switches to overlay dimming while a custom profile is active."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Profiles

    @ViewBuilder
    private func profileSection(_ key: DisplayKey) -> some View {
        Section(L("Color profile")) {
            CFeatureNote(env: env, feature: .colorProfiles)
            if env.runtime.isEffective(.colorProfiles), let ctx = env.context {
                let current = ctx.colorSync.currentProfile(for: key)
                let profiles = ctx.colorSync.installedProfiles()
                Picker(L("Profile"), selection: Binding<URL?>(
                    get: { ctx.colorSync.hasCustomProfile(for: key) ? current?.url : nil },
                    set: { url in
                        let profile = url.flatMap { u in profiles.first { $0.url == u } }
                        if let controller = ctx.colorSync.systemColors {
                            controller.applyProfile(profile, to: key)
                        } else {
                            _ = ctx.colorSync.setProfile(profile?.url, for: key)
                            ctx.gamma.refreshSafeguard()
                        }
                    })) {
                    Text(L("Factory profile")).tag(URL?.none)
                    ForEach(profiles) { profile in
                        Text(TextSanitizer.clean(profile.name, maxScalars: 64)).tag(Optional(profile.url))
                    }
                }
                HStack {
                    if let current {
                        Button(L("Show in Finder")) { ctx.colorSync.showInFinder(current) }
                        Button(L("Open in ColorSync Utility")) { ctx.colorSync.openInColorSyncUtility(current) }
                    }
                    Spacer()
                    if ctx.colorSync.canRestorePrevious {
                        Button(L("Restore Previous")) {
                            ctx.colorSync.restorePrevious(for: key)
                            ctx.gamma.refreshSafeguard()
                        }
                    }
                }
            }
        }
    }

    // MARK: Apple presets and auto-brightness

    @ViewBuilder
    private func presetsSection(_ key: DisplayKey) -> some View {
        if env.runtime.isEffective(.applePresets), let ctx = env.context {
            let presets = ctx.monitorPanel.presetList(for: key)
            Section(L("Apple display preset")) {
                if presets.isEmpty {
                    Text(L("This display has no Apple presets.")).foregroundStyle(.secondary)
                } else {
                    Picker(L("Preset"), selection: Binding<Int?>(
                        get: { presets.first(where: \.isActive)?.id },
                        set: { id in
                            guard let id, let preset = presets.first(where: { $0.id == id }) else { return }
                            if let controller = ctx.colorSync.systemColors {
                                controller.applyPreset(preset, to: key)
                            } else {
                                _ = ctx.monitorPanel.applyPreset(id: id, for: key)
                            }
                        })) {
                        if !presets.contains(where: \.isActive) { Text(L("Unknown")).tag(Int?.none) }
                        ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Text(L("Presets with a fixed brightness turn off Apple brightness control; Snaptic then dims in software."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if env.config.value.features[.applePresets] == true {
            Section(L("Apple display preset")) { CFeatureNote(env: env, feature: .applePresets) }
        }
    }

    @ViewBuilder
    private func autoBrightnessSection(_ key: DisplayKey) -> some View {
        if env.runtime.isEffective(.autoBrightness), let ctx = env.context, let on = ctx.appleBrightness.autoBrightness(of: key) {
            Section(L("Auto-brightness")) {
                Toggle(L("Automatically adjust brightness"), isOn: Binding(get: { on }, set: { value in
                    if let controller = ctx.colorSync.systemColors {
                        controller.setAutoBrightness(value, for: key)
                    } else {
                        _ = ctx.appleBrightness.setAutoBrightness(value, of: key)
                    }
                    env.objectWillChange.send()
                }))
            }
        }
    }

    // MARK: Menu-bar overlays

    @ViewBuilder
    private func overlaysSection(_ key: DisplayKey) -> some View {
        Section(L("Menu bar and corners")) {
            CFeatureNote(env: env, feature: .menuBarOverlays)
            if env.runtime.isEffective(.menuBarOverlays) {
                if selectedInfo?.mirrorOf != nil {
                    Text(L("Mirrored displays use their source's overlays.")).foregroundStyle(.secondary)
                } else {
                    Toggle(L("Black strip behind the menu bar"), isOn: CBind.display(env, key, \.color.menuBarStrip))
                    if let notch = selectedInfo?.notchInset, notch > 0 {
                        Text(L("Hides the notch area.")).font(.caption).foregroundStyle(.secondary)
                    }
                    CSlider(title: L("Top corner radius"), value: CBind.display(env, key, \.color.cornerRadiusTop),
                            range: PerDisplayColor.cornerRange, step: 0.001, format: { String(format: "%.1f%%", $0 * 100) })
                    CSlider(title: L("Bottom corner radius"), value: CBind.display(env, key, \.color.cornerRadiusBottom),
                            range: PerDisplayColor.cornerRange, step: 0.001, format: { String(format: "%.1f%%", $0 * 100) })
                    Text(L("Overlays don't show in screenshots or screen sharing and are removed by Restore All Displays."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Night Shift

    @ViewBuilder
    private var nightShiftSection: some View {
        Section(L("Night Shift")) {
            CFeatureNote(env: env, feature: .nightShift)
            if env.runtime.isEffective(.nightShift), let controller = env.context?.colorSync.systemColors {
                Toggle(L("Night Shift on"), isOn: Binding(get: { nightShiftOn }, set: { value in
                    if value != (controller.nightShiftOn ?? false) { _ = controller.toggleNightShift() }
                    loadNightShift()
                }))
                CSlider(title: L("Warmth"), value: Binding(get: { nightShiftStrength }, set: { value in
                    nightShiftStrength = value
                    controller.setNightShiftStrength(value)
                }), range: 0...1, step: 0.05)
                Text(L("Schedules stay in System Settings → Displays → Night Shift."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func loadNightShift() {
        guard let controller = env.context?.colorSync.systemColors else { return }
        controller.refreshNightShift()
        nightShiftOn = controller.nightShiftOn ?? false
        nightShiftStrength = controller.nightShiftStrength ?? 0.5
    }
}
