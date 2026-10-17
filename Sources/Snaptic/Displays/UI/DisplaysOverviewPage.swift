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
                Button(L("Redetect Displays")) { ctx.actions.perform(OverviewController.redetectAction, on: .all) }
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
                Button(L("Identify Displays")) { ctx.actions.perform(OverviewController.identifyAction, on: .all) }
                Button(L("Redetect")) { ctx.actions.perform(OverviewController.redetectAction, on: .all) }
                Button(L("Show Displays Panel")) { ctx.actions.perform(OverviewController.showPanelAction, on: .pointer) }
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
                if env.runtime.isPanicLatched {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Display automation is paused"), systemImage: "pause.circle").font(.headline)
                        Text(env.runtime.lastPanicSummary ?? L("Restore All Displays ran."))
                        Text(L("Layouts, protection, hooks and virtual-screen recreation wait until you resume."))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(L("Resume Display Automation")) { ctx.panic.resume() }
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
                if DisplaysMenuBuilder.isUnprotected(ctx) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Unprotected"), systemImage: "exclamationmark.shield").font(.headline)
                        Text(L("The safety helper that reverts risky display changes isn't running."))
                        Button(L("Restart Snaptic")) { ctx.relauncher.relaunch(reason: L("Restart the safety helper")) }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func hasBanner(_ ctx: DisplaysContext) -> Bool {
        if case .degraded = env.runtime.moduleState { return true }
        return ctx.safeMode.isActive || env.runtime.isPanicLatched || !ctx.otherApps.pausedDisplayFeatures.isEmpty
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
            if runtime.isEffective(.ddcControls), live.volume != nil { volume }
            if runtime.isEffective(.resolution), display.isActive, !display.isSmartHiDPIPair, !model.modes.isEmpty {
                resolution
            }
            if runtime.isEffective(.ddcInput), model.supportsInput { input }
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
            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { model.refresh(display, runtime: live) }
        .onChange(of: display.desktopID) { _, _ in model.refresh(display, runtime: live) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L("Display \(number): \(display.name)")))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: DisplayMenuBlock.symbol(for: display))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(display.name)
                .font(.headline)
                .lineLimit(1)
            ForEach(DisplayMenuBlock.badges(for: display, paused: model.isPaused), id: \.self) { DisplaysBadge(text: $0) }
            Spacer(minLength: 4)
            if runtime.isEffective(.ddcPower), model.ddcAvailable {
                Toggle(isOn: Binding(get: { live.powerOn ?? true },
                                     set: { model.setPower($0, display: display, runtime: live) })) {
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
            DisplaySliderRow(title: L("Volume"), symbol: "speaker.wave.2", value: live.volume ?? 0) { v in
                model.setVolume(v, runtime: live)
            }
            if live.muted != nil {
                Button { model.toggleMute(runtime: live) } label: {
                    Image(systemName: live.muted == true ? "speaker.slash.fill" : "speaker.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(live.muted == true ? L("Unmute") : L("Mute"))
            }
        }
    }

    private var resolution: some View {
        Picker(selection: Binding<ModeRef?>(
            get: { display.currentMode?.ref ?? model.currentMode },
            set: { if let mode = $0 { model.setMode(mode, display: display) } })) {
            ForEach(model.modes, id: \.self) { mode in
                Text(DisplaysUIText.modeLabel(mode)).tag(Optional(mode))
            }
        } label: {
            Label(L("Resolution"), systemImage: "rectangle.arrowtriangle.2.outward")
        }
        .pickerStyle(.menu)
        .accessibilityLabel(L("Resolution of \(display.name)"))
    }

    private var input: some View {
        Picker(selection: Binding<UInt16?>(
            get: { live.input },
            set: { if let code = $0 { model.setInput(code, display: display, runtime: live) } })) {
            ForEach(model.inputs, id: \.self) { code in
                Text(DisplaysUIText.inputName(code)).tag(Optional(code))
            }
        } label: {
            Label(L("Input"), systemImage: "cable.connector")
        }
        .pickerStyle(.menu)
        .accessibilityLabel(L("Input of \(display.name)"))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let mode = display.currentMode?.ref ?? model.currentMode {
                Text(DisplaysUIText.modeLabel(mode))
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

/// Live state and actions for one display's controls. Holds the context weakly; async
/// work runs on the module's lifetime, so it ends when Displays stops.
@MainActor final class DisplayControlModel: ObservableObject {
    struct Hint {
        let feature: DisplayFeature
        let text: String
        let canTurnOn: Bool
    }

    let key: DisplayKey
    private weak var context: DisplaysContext?
    @Published private(set) var modes: [ModeRef] = []
    @Published private(set) var currentMode: ModeRef?
    @Published private(set) var inputs: [UInt16] = []
    @Published private(set) var supportsInput = false
    @Published var notice: String?
    private var modesFor: UInt32?
    private var capabilitiesRequested = false
    private var volumeMax: UInt16 = 100
    private var pendingVolume: UInt16?
    private var volumeWriting = false

    init(key: DisplayKey, context: DisplaysContext?) {
        self.key = key
        self.context = context
    }

    var isPaused: Bool { !(context?.otherApps.pausedDisplayFeatures.isEmpty ?? true) }
    var ddcAvailable: Bool { context?.ddc.isAvailable(key) ?? false }

    func refresh(_ display: DisplayInfo, runtime live: DisplayRuntime) {
        if modesFor != display.desktopID {
            modesFor = display.desktopID
            let system = Self.systemModes(display.desktopID)
            currentMode = Self.systemCurrentMode(display.desktopID)
            modes = DisplayModeChoices.choices(system, current: display.currentMode?.ref ?? currentMode)
        }
        loadDDC(live)
    }

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

    // MARK: DDC (volume, mute, input, power)

    private func loadDDC(_ live: DisplayRuntime) {
        guard !capabilitiesRequested, let ctx = context, ctx.ddc.isAvailable(key) else { return }
        let wantsVolume = ctx.runtime.isEffective(.ddcControls)
        let wantsInput = ctx.runtime.isEffective(.ddcInput)
        guard wantsVolume || wantsInput else { return }
        capabilitiesRequested = true
        let ddc = ctx.ddc
        let key = key
        ctx.lifetime.spawn { [weak self] in
            let caps = await ddc.capabilities(of: key, refresh: false)
            if wantsInput {
                let listed = caps?.vcp[0x60] ?? []
                self?.inputs = listed.isEmpty ? DisplaysUIText.commonInputs : listed.sorted()
                self?.supportsInput = caps == nil || caps?.supports(0x60) == true
                if live.input == nil, let reading = await ddc.read(0x60, from: key) { live.input = reading.current & 0xFF }
            }
            if wantsVolume, caps == nil || caps?.supports(0x62) == true, let reading = await ddc.read(0x62, from: key),
               reading.max > 0 {
                self?.volumeMax = reading.max
                if live.volume == nil { live.volume = Double(reading.current) / Double(reading.max) }
                if live.muted == nil, caps?.supports(0x8D) == true, let mute = await ddc.read(0x8D, from: key) {
                    live.muted = mute.current == 1
                }
            }
        }
    }

    /// Slider writes are coalesced: one write in flight per display, the latest value wins.
    func setVolume(_ value: Double, runtime live: DisplayRuntime) {
        let clamped = min(max(value, 0), 1)
        live.volume = clamped
        pendingVolume = UInt16((clamped * Double(volumeMax)).rounded())
        pumpVolume()
    }

    private func pumpVolume() {
        guard !volumeWriting, let value = pendingVolume, let ctx = context else { return }
        pendingVolume = nil
        volumeWriting = true
        let ddc = ctx.ddc
        let key = key
        let task = ctx.lifetime.spawn { [weak self] in
            let ok = await ddc.write(0x62, value, to: key, interactive: true, token: nil)
            guard let self else { return }
            self.volumeWriting = false
            if !ok { self.notice = L("The monitor didn't accept the volume change.") }
            self.pumpVolume()
        }
        if task == nil { volumeWriting = false }
    }

    func toggleMute(runtime live: DisplayRuntime) {
        guard let ctx = context else { return }
        let mute = !(live.muted ?? false)
        live.muted = mute
        let ddc = ctx.ddc
        let key = key
        ctx.lifetime.spawn { [weak self] in
            if !(await ddc.write(0x8D, mute ? 1 : 2, to: key, interactive: true, token: nil)) {
                live.muted = !mute
                self?.notice = L("The monitor didn't accept the mute change.")
            }
        }
    }

    /// Switching input can leave this Mac without the picture, so it is confirmed first.
    func setInput(_ code: UInt16, display: DisplayInfo, runtime live: DisplayRuntime) {
        guard let ctx = context, code != live.input else { return }
        let ddc = ctx.ddc
        let confirm = ctx.preConfirm
        let key = key
        let message = L("Switch “\(display.name)” to \(DisplaysUIText.inputName(code))? It shows that source until you switch back with the monitor's buttons or from Snaptic.")
        ctx.lifetime.spawn { [weak self] in
            guard let token = await confirm.confirm(key: key, vcp: 0x60, value: code, message: message, allowKey: "ddc.input") else {
                return
            }
            if await ddc.write(0x60, code, to: key, interactive: true, token: token) {
                live.input = code
            } else {
                self?.notice = L("The monitor didn't switch inputs.")
            }
        }
    }

    /// DDC power (VCP 0xD6): on is safe; standby is confirmed, and refused for the only
    /// display you can see.
    func setPower(_ on: Bool, display: DisplayInfo, runtime live: DisplayRuntime) {
        guard let ctx = context else { return }
        let ddc = ctx.ddc
        let key = key
        if on {
            ctx.lifetime.spawn { [weak self] in
                if await ddc.write(0xD6, 1, to: key, interactive: true, token: nil) {
                    live.powerOn = true
                } else {
                    self?.notice = L("The monitor didn't turn on.")
                }
            }
            return
        }
        let visible = ctx.runtime.displays.filter(\.isStronglyVisible)
        if display.isStronglyVisible && visible.count <= 1 {
            notice = L("This is the only display you can see, so Snaptic won't put it in standby.")
            return
        }
        let confirm = ctx.preConfirm
        let message = L("Put “\(display.name)” in standby? Wake it from Snaptic or with the monitor's power button.")
        ctx.lifetime.spawn { [weak self] in
            guard let token = await confirm.confirm(key: key, vcp: 0xD6, value: 4, message: message, allowKey: "ddc.power") else {
                return
            }
            if await ddc.write(0xD6, 4, to: key, interactive: true, token: token) {
                live.powerOn = false
            } else {
                self?.notice = L("The monitor didn't go to standby.")
            }
        }
    }

    // MARK: Resolution

    func setMode(_ mode: ModeRef, display: DisplayInfo) {
        guard let ctx = context, ctx.runtime.isEffective(.resolution),
              mode != (display.currentMode?.ref ?? currentMode) else { return }
        let onlyVisible = display.isStronglyVisible && ctx.runtime.displays.filter(\.isStronglyVisible).count <= 1
        let request = TransactionRequest(label: L("Resolution of “\(display.name)”"),
                                         risk: onlyVisible ? .trial : .low,
                                         changes: [.mode(display.desktopID, mode)])
        let queue = ctx.transactions
        notice = nil
        ctx.lifetime.spawn { [weak self] in
            let outcome = await queue.submit(request)
            guard let self else { return }
            switch outcome {
            case .applied, .kept:
                self.currentMode = mode
            case .reverted(let why), .failed(let why):
                self.notice = why
            case .refused:
                self.notice = L("Snaptic didn't make this change because it could leave you without a usable display.")
            case .busy:
                self.notice = L("Another display change is in progress. Try again in a moment.")
            }
        }
    }

    /// Desktop-usable modes of a display, HiDPI and LoDPI variants included (public CG API).
    static func systemModes(_ id: CGDirectDisplayID) -> [ModeRef] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let list = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [] }
        return list.filter { $0.isUsableForDesktopGUI() }.map(modeRef)
    }

    static func systemCurrentMode(_ id: CGDirectDisplayID) -> ModeRef? {
        CGDisplayCopyDisplayMode(id).map(modeRef)
    }

    private static func modeRef(_ mode: CGDisplayMode) -> ModeRef {
        ModeRef(ioModeID: mode.ioDisplayModeID, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                pointWidth: mode.width, pointHeight: mode.height,
                refreshMilliHz: mode.refreshRate.isFinite ? Int((mode.refreshRate * 1000).rounded()) : 0)
    }
}
