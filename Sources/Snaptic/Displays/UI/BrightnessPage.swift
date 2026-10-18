import SwiftUI
import SnapticKit

// MARK: Shared helpers for C's settings pages

/// Bindings into the Displays settings (global and per display).
@MainActor enum CBind {
    static func global<T>(_ env: DisplaysPageEnvironment, _ path: WritableKeyPath<DisplaysConfig, T>) -> Binding<T> {
        Binding(get: { env.config.value[keyPath: path] }, set: { env.config.value[keyPath: path] = $0 })
    }

    static func display<T>(_ env: DisplaysPageEnvironment, _ key: DisplayKey,
                           _ path: WritableKeyPath<PerDisplayConfig, T>) -> Binding<T> {
        Binding(get: { (env.config.value.perDisplay[key] ?? PerDisplayConfig())[keyPath: path] },
                set: { newValue in
                    var config = env.config.value
                    var per = config.perDisplay[key] ?? PerDisplayConfig()
                    per[keyPath: path] = newValue
                    config.perDisplay[key] = per
                    env.config.value = config
                })
    }

    /// An optional Double edited with a "custom" switch.
    static func optional(_ binding: Binding<Double?>, fallback: Double) -> (on: Binding<Bool>, value: Binding<Double>) {
        (Binding(get: { binding.wrappedValue != nil }, set: { binding.wrappedValue = $0 ? fallback : nil }),
         Binding(get: { binding.wrappedValue ?? fallback }, set: { binding.wrappedValue = $0 }))
    }
}

/// "Needs X" / "Unavailable: reason" / "Turn on" for a feature (pages never hold the
/// on/off switches themselves; the Features page does).
struct CFeatureNote: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let feature: DisplayFeature

    var body: some View {
        if !env.runtime.isEffective(feature) {
            HStack(alignment: .firstTextBaseline) {
                if case .unavailable(let reason)? = env.runtime.availability[feature] {
                    Label(DisplaysUIText.title(feature) + ": " + reason, systemImage: "nosign")
                        .foregroundStyle(.secondary)
                } else {
                    Label(DisplaysUIText.title(feature) + " " + L("is off"), systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Turn On")) { env.enableFeature(feature) }
                        .accessibilityLabel(L("Turn on \(DisplaysUIText.title(feature))"))
                }
            }
            .font(.callout)
        }
    }
}

/// Picks one connected display (by key).
struct CDisplayPicker: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @Binding var selection: DisplayKey?
    var filter: (DisplayInfo) -> Bool = { _ in true }

    private var displays: [DisplayInfo] { env.runtime.displays.filter { $0.isOnline && filter($0) } }

    var body: some View {
        Picker(L("Display"), selection: Binding(get: { current }, set: { selection = $0 })) {
            ForEach(displays) { d in
                Text(TextSanitizer.clean(d.name, maxScalars: 64) + (d.isBuiltin ? L(" (built-in)") : "")).tag(Optional(d.key))
            }
        }
        .onAppear { if selection == nil { selection = current } }
    }

    private var current: DisplayKey? {
        if let selection, displays.contains(where: { $0.key == selection }) { return selection }
        return displays.first(where: \.isMain)?.key ?? displays.first?.key
    }
}

/// A labeled slider with a value readout.
/// A slider for a live hardware value (0.3 §4.5): it observes the display's `DisplayRuntime`, so a change from the
/// keys, the menu, the CLI or a read-back shows while the page is open. Hidden while the value is unknown.
struct CLiveSlider: View {
    let title: String
    @ObservedObject var live: DisplayRuntime
    let value: KeyPath<DisplayRuntime, Double?>
    var range: KeyPath<DisplayRuntime, ClosedRange<Double>>? = nil
    let set: (Double) -> Void

    var body: some View {
        if let current = live[keyPath: value] {
            let live = self.live
            let value = self.value
            CSlider(title: title, value: Binding(get: { live[keyPath: value] ?? current }, set: set),
                    range: range.map { live[keyPath: $0] } ?? 0...1)
        }
    }
}

struct CSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { VoiceOverAnnouncer.percent($0) }

    var body: some View {
        HStack {
            Text(title)
            if let step {
                Slider(value: $value, in: range, step: step) { Text(title) }
                    .labelsHidden()
            } else {
                Slider(value: $value, in: range) { Text(title) }
                    .labelsHidden()
            }
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
    }
}

// MARK: Brightness page

/// Brightness (PLAN §6.1, §6.4): the combined slider per display, methods and why,
/// switchover and minimum hardware level, nits, XDR with calibration, sync, restore,
/// dim on lock and dim to black.
struct BrightnessPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var selected: DisplayKey?
    @State private var calibrating = false

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            Section {
                CFeatureNote(env: env, feature: .brightness)
                ForEach([DisplayFeature.brightnessApple, .brightnessDDC, .brightnessGamma, .brightnessOverlay], id: \.self) {
                    CFeatureNote(env: env, feature: $0)
                }
            }
            if let ctx = env.context, env.runtime.isEffective(.brightness) {
                Section(L("Display")) {
                    CDisplayPicker(env: env, selection: $selected)
                    if let key = selectedKey { displaySection(ctx, key) }
                }
                if let key = selectedKey {
                    if env.runtime.isEffective(.nits) { nitsSection(ctx, key) }
                    xdrSection(ctx, key)
                    if env.runtime.isEffective(.sync) { syncDisplaySection(key) }
                }
            }
            restoreSection
            dimSection
            syncSection
            xdrGlobalSection
        }
        .formStyle(.grouped)
    }

    private var selectedKey: DisplayKey? {
        let online = env.runtime.displays.filter(\.isOnline)
        if let selected, online.contains(where: { $0.key == selected }) { return selected }
        return online.first(where: \.isMain)?.key ?? online.first?.key
    }

    // MARK: Per display

    @ViewBuilder
    private func displaySection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        let b = ctx.brightness
        let live = env.runtime.runtime(for: key)
        if b.value(for: key) != nil {
            CLiveSlider(title: L("Brightness"), live: live, value: \.brightnessPosition, range: \.brightnessRange) {
                b.set(b.scale(for: key)?.snapped($0) ?? $0, for: key, source: .user)
            }
            if let scale = b.scale(for: key), !scale.snapMarks.isEmpty {
                Text(L("Snap marks: ") + scale.snapMarks.map { $0 == 1 ? L("Max HW (100%)") : L("Min HW (\(VoiceOverAnnouncer.percent($0)))") }
                    .joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if b.isAwaitingFirstRead(key) {
            LabeledContent(L("Brightness")) {
                Text(L("Reading brightness…")).foregroundStyle(.secondary)
            }
        }
        LabeledContent(L("Method")) {
            Text([b.hardwareMethod(for: key)?.title, b.softwareMethod(for: key)?.title].compactMap { $0 }
                .joined(separator: " + ").nonEmpty ?? L("None"))
        }
        Text(b.methodReason(for: key)).font(.caption).foregroundStyle(.secondary)
        Picker(L("Use"), selection: CBind.display(env, key, \.brightness.method)) {
            Text(L("Automatic")).tag(BrightnessMethod?.none)
            ForEach(BrightnessMethod.allCases, id: \.self) { m in
                Text(m.title).tag(Optional(m))
            }
        }
        let switchover = CBind.optional(CBind.display(env, key, \.brightness.switchover),
                                        fallback: CombinedScale.defaultSwitchover(hardware: b.hardwareMethod(for: key), xdrOn: false))
        if b.hardwareMethod(for: key) != nil && b.softwareMethod(for: key) != nil {
            Toggle(L("Custom software-dimming switchover"), isOn: switchover.on)
            if switchover.on.wrappedValue {
                CSlider(title: L("Switchover"), value: switchover.value, range: 0...0.9, step: 0.01)
            }
            Text(L("Below the switchover the hardware stays at its minimum and software dims further. Defaults: 25% for Apple displays, 0% for DDC, 20% with XDR."))
                .font(.caption).foregroundStyle(.secondary)
        }
        if b.hardwareMethod(for: key) != nil {
            CSlider(title: L("Minimum hardware level"), value: CBind.display(env, key, \.brightness.minHardware), range: 0...0.9,
                    step: 0.01)
            Text(L("Keeps the backlight above this level, e.g. to avoid PWM flicker."))
                .font(.caption).foregroundStyle(.secondary)
        }
        if b.softwareMethod(for: key) == .gamma || env.config.value.perDisplay[key]?.brightness.gammaWorks == false {
            let works = env.config.value.perDisplay[key]?.brightness.gammaWorks
            LabeledContent(L("Color-table dimming")) {
                Text(works == false ? L("Didn't get darker: overlay is used") : (works == true ? L("Works") : L("Not checked yet")))
            }
            if works != nil {
                Button(L("Ask Again")) {
                    CBind.display(env, key, \.brightness.gammaWorks).wrappedValue = nil
                    ctx.gamma.resetGiveUp(key)
                }
            }
        }
    }

    @ViewBuilder
    private func nitsSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        Section(L("Nits")) {
            if let nits = ctx.brightness.nits(for: key) {
                LabeledContent(L("Now")) { Text(NitsModel.label(nits.value, estimate: nits.estimate)) }
            }
            let custom = CBind.display(env, key, \.brightness.nits)
            if let display = env.runtime.displays.first(where: { $0.key == key }) {
                let defaults = ctx.brightness.nitsRange(for: display)
                Toggle(L("Custom range"), isOn: Binding(get: { custom.wrappedValue != nil },
                                                         set: { custom.wrappedValue = $0 ? NitsRange(minimum: defaults.minimum,
                                                                                                    maximum: defaults.maximum,
                                                                                                    peak: defaults.peak,
                                                                                                    isEstimate: false) : nil }))
                let range = custom.wrappedValue ?? defaults
                ForEach([(L("Minimum"), \NitsRange.minimum), (L("Maximum (SDR)"), \NitsRange.maximum), (L("Peak (HDR)"), \NitsRange.peak)],
                        id: \.0) { title, path in
                    LabeledContent(title) {
                        TextField(title, value: Binding(get: { range[keyPath: path] },
                                                        set: { v in
                                                            var r = custom.wrappedValue ?? defaults
                                                            r[keyPath: path] = v
                                                            r.isEstimate = false
                                                            custom.wrappedValue = r.sanitized()
                                                        }), format: .number)
                            .frame(width: 80)
                            .disabled(custom.wrappedValue == nil)
                    }
                }
                Text(range.isEstimate ? L("Estimated from the model; edit for accuracy.") : L("Your values."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L("Show nits in the menu and OSD"), isOn: CBind.global(env, \.brightness.showNits))
        }
    }

    @ViewBuilder
    private func xdrSection(_ ctx: DisplaysContext, _ key: DisplayKey) -> some View {
        if env.runtime.isEffective(.xdr) {
            let xdr = ctx.edr
            Section(L("Extra brightness (XDR, Beta)")) {
                let (method, reason) = xdr.xdrMethod(for: key)
                if method == nil {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Toggle(L("Extra brightness on this display"), isOn: CBind.display(env, key, \.brightness.xdrEnabled))
                    LabeledContent(L("Method")) { Text(reason) }
                    let maxBinding = CBind.optional(CBind.display(env, key, \.brightness.xdrMax),
                                                    fallback: env.config.value.brightness.xdrMaxScale)
                    Toggle(L("Custom maximum for this display"), isOn: maxBinding.on)
                    if maxBinding.on.wrappedValue {
                        CSlider(title: L("Maximum"), value: maxBinding.value, range: BrightnessConfig.xdrScaleRange, step: 0.05)
                    }
                    if let paused = ctx.edr.pauseReason { Label(L("Paused: ") + paused, systemImage: "pause.circle") }
                    if calibrating {
                        Text(L("Is the screen brighter now?"))
                        HStack {
                            Button(L("Yes, it's brighter")) { xdr.finishCalibration(brighter: true); calibrating = false }
                            Button(L("No change")) { xdr.finishCalibration(brighter: false); calibrating = false }
                        }
                    } else if let method {
                        Button(L("Test (“Is it brighter?”)")) {
                            xdr.beginCalibration(key, method: method)
                            calibrating = true
                        }
                    }
                }
                Text(L("Extra brightness uses more power and heat, can blow out HDR video, and can burn in OLED panels. It pauses when the Mac is hot, in Low Power Mode, on low battery and while locked."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func syncDisplaySection(_ key: DisplayKey) -> some View {
        Section(L("Sync for this display")) {
            Toggle(L("Follow the sync source"), isOn: CBind.display(env, key, \.brightness.syncEnabled))
            CSlider(title: L("Offset"), value: CBind.display(env, key, \.brightness.syncOffset), range: -0.5...0.5, step: 0.01,
                    format: { String(format: "%+.0f%%", $0 * 100) })
        }
    }

    // MARK: Global

    @ViewBuilder
    private var restoreSection: some View {
        Section(L("Restore")) {
            CFeatureNote(env: env, feature: .brightnessRestore)
            Picker(L("On launch and wake, restore"), selection: CBind.global(env, \.brightness.restoreMode)) {
                ForEach(BrightnessRestoreMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(!env.runtime.isEffective(.brightnessRestore))
            Toggle(L("Smooth transitions"), isOn: CBind.global(env, \.brightness.smoothTransitions))
            Text(L("Restore never goes below 15%. DDC values are re-sent only when the monitor reports something different. Safe Mode skips restoring."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dimSection: some View {
        Section(L("Dimming")) {
            CFeatureNote(env: env, feature: .dimToBlack)
            if env.runtime.isEffective(.dimToBlack) {
                Text(L("Software dimming can reach black while another display stays visible and the safety helper runs. It's raised to 30% while a confirmation or password window shows."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L("Without dim to black, software dimming stops at 8%."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            CFeatureNote(env: env, feature: .dimOnLock)
            if env.runtime.isEffective(.dimOnLock) {
                CSlider(title: L("Dim on lock to"), value: CBind.global(env, \.brightness.dimOnLockLevel),
                        range: BrightnessConfig.dimOnLockFloor...1, step: 0.05)
                Text(L("Uses color-table dimming, so displays dimmed with an overlay aren't affected."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            CFeatureNote(env: env, feature: .nits)
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section(L("Brightness sync")) {
            CFeatureNote(env: env, feature: .sync)
            if env.runtime.isEffective(.sync) {
                Toggle(L("Sync on"), isOn: Binding(get: { !env.config.value.brightness.syncPaused },
                                                   set: { env.config.value.brightness.syncPaused = !$0 }))
                Picker(L("Source"), selection: CBind.global(env, \.brightness.syncSource)) {
                    Text(L("Built-in display")).tag(DisplayKey?.none)
                    ForEach(env.runtime.displays.filter(\.isOnline)) { d in
                        Text(TextSanitizer.clean(d.name, maxScalars: 64)).tag(Optional(d.key))
                    }
                }
                Picker(L("Follow"), selection: CBind.global(env, \.brightness.syncMode)) {
                    Text(L("The same level (plus offset)")).tag(SyncMode.absolute)
                    Text(L("The same change")).tag(SyncMode.delta)
                }
                Toggle(L("Follow changes made outside Snaptic"), isOn: CBind.global(env, \.brightness.syncExternalChanges))
                Text(L("Changes made with a monitor's own buttons are noticed only with DDC readback on. Hold ⇧ on the brightness keys to change one display without syncing."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var xdrGlobalSection: some View {
        Section(L("Extra brightness (XDR)")) {
            CFeatureNote(env: env, feature: .xdr)
            if env.runtime.isEffective(.xdr) {
                CSlider(title: L("Maximum"), value: CBind.global(env, \.brightness.xdrMaxScale), range: BrightnessConfig.xdrScaleRange,
                        step: 0.05)
                Picker(L("Method"), selection: CBind.global(env, \.brightness.xdrMethod)) {
                    ForEach(XDRMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                CSlider(title: L("Pause below battery"), value: CBind.global(env, \.brightness.xdrBatteryFloor),
                        range: BrightnessConfig.batteryFloorRange, step: 0.05)
                Toggle(L("Pause in Low Power Mode"), isOn: CBind.global(env, \.brightness.xdrPauseOnLowPower))
                Toggle(L("Stop at 100% before going higher"), isOn: CBind.global(env, \.brightness.xdrDetent))
            }
        }
    }
}

fileprivate extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
