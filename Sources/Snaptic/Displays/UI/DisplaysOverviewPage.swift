import AppKit
import CoreGraphics
import SwiftUI
import SnapticKit

/// The Displays Overview page (R5.8): live controls per display — the primary control
/// surface on macOS 27, where the status item can sit in the menu bar's overflow — plus
/// module state, Safe Mode / panic banners and the other-apps paused notice.
struct DisplaysOverviewPage: View {
    @ObservedObject private var env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            if let ctx = env.context {
                live(ctx)
            } else {
                Section {
                    Label(L("Displays is turned off"), systemImage: "display.2")
                        .font(.headline)
                    Text(L("Turn on Displays in General → Modules to see live controls here."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func live(_ ctx: DisplaysContext) -> some View {
        let displays = DisplaysMenuBuilder.orderedDisplays(ctx, includeHidden: true)
        if displays.isEmpty {
            Section(L("Displays")) {
                Text(L("No displays detected yet.")).foregroundStyle(.secondary)
                Button(L("Redetect Displays")) { _ = ctx.actions.perform(OverviewController.redetectAction, on: .all) }
            }
        }
        ForEach(Array(displays.enumerated()), id: \.element.key) { index, display in
            Section {
                DisplayControlsCard(display: display, number: index + 1, runtime: env.runtime, context: ctx,
                                    compact: false, enableFeature: env.enableFeature)
            }
        }
        Section(L("Tools")) {
            HStack {
                Button(L("Identify Displays")) { _ = ctx.actions.perform(OverviewController.identifyAction, on: .all) }
                Button(L("Redetect")) { _ = ctx.actions.perform(OverviewController.redetectAction, on: .all) }
                Button(L("Show Displays Panel")) { _ = ctx.actions.perform(OverviewController.showPanelAction, on: .pointer) }
            }
            LabeledContent(L("Displays panel shortcut")) {
                ShortcutRecorder(combo: shortcutBinding(\.showPanelShortcut))
            }
            Text(L("Opens these controls at the pointer, even when the menu-bar icon is hidden in the menu bar's overflow."))
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent(L("Identify shortcut")) {
                ShortcutRecorder(combo: shortcutBinding(\.identifyShortcut))
            }
        }
        Section(L("Features")) {
            let on = env.runtime.effectiveFeatures.count
            LabeledContent(L("Active features"), value: "\(on) of \(DisplayFeature.allCases.count)")
            Text(L("Choose features on the Display Features page."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutBinding(_ path: WritableKeyPath<MenuConfig, HotkeyCombo?>) -> Binding<HotkeyCombo?> {
        let config = env.config
        return Binding(
            get: { config.value.menu[keyPath: path] },
            set: { config.value.menu[keyPath: path] = $0.flatMap(MenuConfig.sanitizedCombo) })
    }
}

// MARK: - Status banners (shared by the Overview, Features and Names pages)

struct DisplaysStatusSection: View {
    @ObservedObject private var env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    var body: some View {
        if let ctx = env.context, hasBanner(ctx) {
            Section {
                if case .degraded(let reason) = env.runtime.moduleState {
                    Label(L("Displays is running with problems: \(reason)"), systemImage: "exclamationmark.triangle")
                }
                if ctx.safeMode.isActive {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Safe Mode is on"), systemImage: "exclamationmark.shield").font(.headline)
                        Text(ctx.safeMode.reason ?? L("Snaptic started in Safe Mode."))
                        Text(L("Restoring brightness, layouts, virtual screens, protection and automatic DDC writes is off."))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(L("Leave Safe Mode…")) { ctx.relauncher.relaunch(reason: L("Leave Safe Mode")) }
                    }
                    .accessibilityElement(children: .contain)
                }
                if ctx.panic.isLatched {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Display automation is paused"), systemImage: "pause.circle").font(.headline)
                        Text(env.runtime.lastPanicSummary ?? L("Restore All Displays ran."))
                        Text(L("Layouts, protection, hooks and virtual-screen recreation wait until you resume."))
                            .font(.caption).foregroundStyle(.secondary)
                        // B's registered Resume action (the same one its Tools item and the CLI use).
                        Button(L("Resume Display Automation")) {
                            _ = ctx.actions.perform(PanicCoordinator.resumeActionID, on: .all)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                let paused = ctx.otherApps.pausedDisplayFeatures
                if !paused.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Some features are paused"), systemImage: "pause.circle").font(.headline)
                        ForEach(DisplaysMenuBuilder.pauseReasons(paused, monitor: ctx.otherApps), id: \.self) { Text($0) }
                        Text(paused.map(DisplaysUIText.title).sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let reason = DisplaysMenuBuilder.unprotectedReason(ctx) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Unprotected"), systemImage: "exclamationmark.shield").font(.headline)
                        Text(reason)
                        Button(L("Restart Snaptic")) { ctx.relauncher.relaunch(reason: L("Restart the safety helper")) }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func hasBanner(_ ctx: DisplaysContext) -> Bool {
        if case .degraded = env.runtime.moduleState { return true }
        return ctx.safeMode.isActive || ctx.panic.isLatched || !ctx.otherApps.pausedDisplayFeatures.isEmpty
            || DisplaysMenuBuilder.isUnprotected(ctx)
    }
}

/// A small capsule label ("Main", "Beta").
struct DisplaysBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(Capsule().strokeBorder(tint.opacity(0.6)))
    }
}

// MARK: - Live controls for one display (Overview page and floating panel)

/// One display's live controls. Every change goes through the owning team's controller:
/// brightness through BrightnessService, resolution through D's ResolutionController
/// (`ctx.connectPlanner.resolution`), volume, mute, input and power through C's
/// DDCController (`ctx.ddc.controller`). Those controllers report failures themselves.
struct DisplayControlsCard: View {
    let display: DisplayInfo
    let number: Int
    let compact: Bool
    let enableFeature: @MainActor (DisplayFeature) -> Void
    /// Shows the display's full menu (every contributor's items); the floating panel sets it.
    let showMore: (@MainActor (DisplayInfo) -> Void)?
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var live: DisplayRuntime
    @StateObject private var model: DisplayControlModel
    /// The resolution slider's position while it is being moved (index into the stops).
    @State private var draggingStop: Double?

    init(display: DisplayInfo, number: Int, runtime: DisplaysRuntimeState, context: DisplaysContext, compact: Bool,
         enableFeature: @escaping @MainActor (DisplayFeature) -> Void,
         showMore: (@MainActor (DisplayInfo) -> Void)? = nil) {
        self.display = display
        self.number = number
        self.compact = compact
        self.enableFeature = enableFeature
        self.showMore = showMore
        _runtime = ObservedObject(wrappedValue: runtime)
        _live = ObservedObject(wrappedValue: runtime.runtime(for: display.key))
        _model = StateObject(wrappedValue: DisplayControlModel(key: display.key, context: context))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            header
            if runtime.isEffective(.brightness) { brightness }
            if runtime.isEffective(.ddcControls), model.showsVolume { volume }
            if runtime.isEffective(.resolution), model.showsResolution(display) { resolution }
            if runtime.isEffective(.ddcInput) {
                let inputs = model.inputs
                if !inputs.isEmpty { input(inputs) }
            }
            if !compact { details }
            ForEach(model.hints(for: display), id: \.feature) { hint in
                HStack {
                    Text(hint.text).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if hint.canTurnOn {
                        Button(L("Turn On")) { enableFeature(hint.feature) }
                            .controlSize(.small)
                            .accessibilityLabel(L("Turn on \(DisplaysUIText.title(hint.feature))"))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L("Display \(number): \(display.name)")))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbol(for: display))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(display.name)
                .font(.headline)
                .lineLimit(1)
            ForEach(model.badges(for: display), id: \.self) { DisplaysBadge(text: $0) }
            Spacer(minLength: 4)
            if runtime.isEffective(.ddcPower), model.showsPower {
                Toggle(isOn: Binding(get: { live.powerOn ?? true }, set: { model.setPower($0) })) {
                    Text(L("Power"))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(L("Power for \(display.name)"))
            }
            if let showMore {
                Button { showMore(display) } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help(L("More options"))
                .accessibilityLabel(L("More options for \(display.name)"))
            }
        }
    }

    @ViewBuilder
    private var brightness: some View {
        if let value = live.brightness ?? model.brightness() {
            DisplaySliderRow(title: L("Brightness"), symbol: "sun.max", value: value) { v in
                live.brightness = v
                model.setBrightness(v)
            }
        } else {
            Label(L("Brightness can't be read on this display yet."), systemImage: "sun.max")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var volume: some View {
        HStack(spacing: 6) {
            DisplaySliderRow(title: L("Volume"), symbol: "speaker.wave.2", value: live.volume ?? 0.5) { v in
                model.setVolume(v)
            }
            Button { model.toggleMute() } label: {
                Image(systemName: live.muted == true ? "speaker.slash.fill" : "speaker.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(live.muted == true ? L("Unmute") : L("Mute"))
        }
    }

    // MARK: Resolution (D's ResolutionController)

    @ViewBuilder
    private var resolution: some View {
        let current = model.currentMode(display)
        let stops = model.sliderStops()
        if stops.count >= 2, let current, let index = stops.firstIndex(of: current) {
            resolutionSlider(stops: stops, index: index)
        }
        let modes = model.modes()
        if !modes.isEmpty {
            Picker(selection: Binding<ModeRef?>(
                get: { current },
                set: { if let mode = $0 { model.apply(mode, display: display) } })) {
                ForEach(modes.prefix(DisplayControlModel.pickerLimit), id: \.ref) { mode in
                    Text(model.label(mode)).tag(Optional(mode.ref))
                }
            } label: {
                Label(L("Resolution"), systemImage: "rectangle.arrowtriangle.2.outward")
            }
            .pickerStyle(.menu)
            .accessibilityLabel(L("Resolution of \(display.name)"))
            if modes.count > DisplayControlModel.pickerLimit {
                Button(L("All Modes in Settings…")) { model.openSettings("displays.resolution") }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private func resolutionSlider(stops: [ModeRef], index: Int) -> some View {
        let shown = Int((draggingStop ?? Double(index)).rounded())
        let text = model.sliderText(stops[min(max(shown, 0), stops.count - 1)])
        return HStack(spacing: 8) {
            Image(systemName: "rectangle.arrowtriangle.2.outward")
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { draggingStop ?? Double(index) }, set: { v in
                draggingStop = v
                // Keyboard and VoiceOver changes end no drag: apply after a short pause.
                model.scheduleSlider(Int(v.rounded()), stops: stops)
            }), in: 0...Double(stops.count - 1), step: 1, label: { Text(L("Resolution")) }, onEditingChanged: { editing in
                guard !editing, let v = draggingStop else { return }
                model.applySlider(Int(v.rounded()), stops: stops)
                draggingStop = nil
            })
            .labelsHidden()
            .accessibilityLabel(Text(L("Resolution size")))
            .accessibilityValue(Text(text))
            Text(text)
                .monospacedDigit()
                .font(.caption)
                .lineLimit(1)
                .frame(minWidth: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .onChange(of: index) { _, _ in draggingStop = nil }
    }

    // MARK: Input (C's DDCController)

    private func input(_ inputs: [DDCInputEntry]) -> some View {
        Picker(selection: Binding<String?>(
            get: { inputs.first { !$0.lgAlt && $0.value == live.input }?.id },
            set: { id in if let entry = inputs.first(where: { $0.id == id }) { model.setInput(entry) } })) {
            ForEach(inputs) { entry in
                Text(model.inputName(entry)).tag(Optional(entry.id))
            }
        } label: {
            Label(L("Input"), systemImage: "cable.connector")
        }
        .pickerStyle(.menu)
        .accessibilityLabel(L("Input of \(display.name)"))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let mode = model.currentMode(display) {
                Text(model.label(mode))
            }
            if let text = live.statusText { Text(text) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Icon, slider, percentage. While dragging, the slider shows the dragged value even if
/// the live value lags behind.
struct DisplaySliderRow: View {
    let title: String
    let symbol: String
    let value: Double
    let onChange: (Double) -> Void
    @State private var dragging: Double?

    init(title: String, symbol: String, value: Double, onChange: @escaping (Double) -> Void) {
        self.title = title
        self.symbol = symbol
        self.value = value
        self.onChange = onChange
    }

    var body: some View {
        let current = dragging ?? value
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { dragging ?? value }, set: { v in
                dragging = v
                onChange(v)
            }), in: 0...1, label: { Text(title) }, onEditingChanged: { editing in
                if !editing { dragging = nil }
            })
            .labelsHidden()
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("\(Int((current * 100).rounded())) %"))
            Text("\(Int((current * 100).rounded()))%")
                .monospacedDigit()
                .font(.caption)
                .frame(width: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Model

/// Reads and actions for one display's controls, delegating to the owning controllers.
/// Holds the context weakly; nothing here talks to DDC or CoreGraphics directly.
@MainActor final class DisplayControlModel: ObservableObject {
    struct Hint {
        let feature: DisplayFeature
        let text: String
        let canTurnOn: Bool
    }

    /// Modes listed in the picker (the rest are on the Resolution page), like D's menu.
    static let pickerLimit = 60

    let key: DisplayKey
    private weak var context: DisplaysContext?
    private var sliderWork: DispatchWorkItem?

    init(key: DisplayKey, context: DisplaysContext?) {
        self.key = key
        self.context = context
    }

    private var resolutionController: ResolutionController? { context?.connectPlanner.resolution }
    private var ddcController: DDCController? { context?.ddc.controller }

    var isPaused: Bool { !(context?.otherApps.pausedDisplayFeatures.isEmpty ?? true) }

    func symbol(for display: DisplayInfo) -> String {
        DisplayMenuBlock.symbol(for: display, config: context?.config.value)
    }

    func badges(for display: DisplayInfo) -> [String] {
        guard let ctx = context else { return DisplayMenuBlock.badges(for: display, paused: false) }
        return DisplayMenuBlock.badges(for: display, context: ctx)
    }

    func openSettings(_ page: String) { context?.openSettings(page) }

    func hints(for display: DisplayInfo) -> [Hint] {
        guard let ctx = context else { return [] }
        var result: [Hint] = []
        for feature in [DisplayFeature.brightness, .resolution, .ddcControls] {
            if feature == .ddcControls && display.isBuiltin { continue }
            switch DisplayMenuBlock.hint(for: feature, context: ctx) {
            case .nothing: break
            case .paused(let reason):
                result.append(Hint(feature: feature, text: "\(DisplaysUIText.title(feature)): \(reason)", canTurnOn: false))
            case .turnOn:
                result.append(Hint(feature: feature, text: L("\(DisplaysUIText.title(feature)) is off"), canTurnOn: true))
            }
        }
        return result
    }

    // MARK: Brightness

    func brightness() -> Double? { context?.brightness.value(for: key) }

    func setBrightness(_ value: Double) {
        guard let ctx = context, ctx.runtime.isEffective(.brightness) else { return }
        ctx.brightness.set(min(max(value, 0), 1), for: key, source: .user)
    }

    // MARK: Resolution (D)

    func showsResolution(_ display: DisplayInfo) -> Bool {
        display.isActive && display.mirrorOf == nil && resolutionController != nil
    }

    func currentMode(_ display: DisplayInfo) -> ModeRef? { resolutionController?.currentMode(display) }

    func modes() -> [DisplayModeDescriptor] { resolutionController?.modes(for: key) ?? [] }

    func label(_ mode: DisplayModeDescriptor) -> String { resolutionController?.label(mode) ?? DisplaysUIText.modeLabel(mode.ref) }

    func label(_ mode: ModeRef) -> String {
        resolutionController?.label(mode, markers: true, key: key) ?? DisplaysUIText.modeLabel(mode)
    }

    func sliderStops() -> [ModeRef] { resolutionController?.sliderModes(for: key) ?? [] }

    func sliderText(_ mode: ModeRef) -> String {
        resolutionController?.sliderValueText(mode, key: key) ?? DisplaysUIText.modeLabel(mode)
    }

    func apply(_ mode: ModeRef, display: DisplayInfo) {
        guard let c = resolutionController, mode != c.currentMode(display) else { return }
        c.apply(mode, to: key, label: L("Resolution of “\(display.name)”"))
    }

    /// Slider release: snaps (unless ⌥ is held) and applies through D.
    func applySlider(_ index: Int, stops: [ModeRef]) {
        sliderWork?.cancel()
        sliderWork = nil
        guard let c = resolutionController, stops.count >= 2 else { return }
        let raw = min(max(index, 0), stops.count - 1)
        let bypass = NSEvent.modifierFlags.contains(.option)
        let i = c.snappedStop(raw, in: stops, key: key, bypass: bypass)
        c.apply(stops[i], to: key)
    }

    /// Keyboard / VoiceOver changes: apply 0.4 s after the last step (mode changes are slow).
    func scheduleSlider(_ index: Int, stops: [ModeRef]) {
        sliderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applySlider(index, stops: stops) }
        }
        sliderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: DDC (C)

    private var ddcAvailable: Bool { context?.ddc.isAvailable(key) ?? false }

    /// The same rule as C's menu: the volume control only when the display has VCP 0x62.
    var showsVolume: Bool {
        guard let ctx = context, ddcAvailable, ddcController != nil else { return false }
        let caps = ctx.ddc.cachedCapabilities(key)
        return caps?.supports(VCPPolicy.volume) == true || (caps == nil && ctx.ddc.lastReading(VCPPolicy.volume, of: key) != nil)
    }

    var showsPower: Bool {
        guard let ctx = context, ddcAvailable, ddcController != nil else { return false }
        let caps = ctx.ddc.cachedCapabilities(key)
        return caps == nil || caps?.supports(VCPPolicy.power) == true
    }

    var inputs: [DDCInputEntry] {
        guard ddcAvailable, let c = ddcController else { return [] }
        return c.inputList(for: key)
    }

    func inputName(_ entry: DDCInputEntry) -> String { ddcController?.inputName(entry) ?? DisplaysUIText.inputName(entry.value) }

    func setVolume(_ value: Double) { ddcController?.setFraction(VCPPolicy.volume, min(max(value, 0), 1), for: key) }

    func toggleMute() { ddcController?.toggleMute(.display(key)) }

    /// C confirms first (switching input can leave this Mac without a picture).
    func setInput(_ entry: DDCInputEntry) { _ = ddcController?.setInput(entry, on: key) }

    /// C confirms standby and refuses it for the only display you can see.
    func setPower(_ on: Bool) { _ = ddcController?.setPower(on, on: key) }

    // MARK: System modes (onboarding only)

    /// Desktop-usable modes of a display, HiDPI and LoDPI variants included, from D's mode
    /// list. Only the onboarding step's "Sharper text" check uses it; live controls go through D.
    static func systemModes(_ id: CGDirectDisplayID) -> [ModeRef] {
        ManagedModes.modes(for: id).map(\.ref)
    }
}
