import AppKit
import SwiftUI
import SnapticKit

// Live per-display controls (owner F; PLAN 0.3 §4.3, §4.5, §5.6): the rows the Displays root page and the floating
// Displays panel share, and the panel's content. Values come from `DisplayRuntime` (brightness, volume, mute,
// input) and the owners' controllers, observed through their `ControllerRevision`; hardware writes go only
// through `DisplayLiveControlling` (C), resolution changes through D's ResolutionController, input and mute
// through C's DDCController. No row keeps a copy of a model value: a drag's local value lives in SliderSetting.

// MARK: - Model

/// What one display's live rows read and do. Holds the context weakly; owned by the row group as a StateObject and
/// re-created when the display changes (`.id(key)`).
@MainActor final class DisplayLiveModel: ObservableObject {
    let key: DisplayKey
    private weak var context: DisplaysContext?
    private let writer: DisplayLiveControlling
    /// Controls being dragged now, and the last value sent for each, so `.ended` carries the final value.
    private var dragging: Set<LiveControl> = []
    private var lastSent: [LiveControl: Double] = [:]

    init(key: DisplayKey, context: DisplaysContext?) {
        self.key = key
        self.context = context
        writer = DisplaysLive.makeWriter(context)
    }

    // MARK: Live values (C)

    /// Every value change: part of a drag, or a single change (keyboard, VoiceOver, a click on the track).
    func set(_ control: LiveControl, _ value: Double) {
        lastSent[control] = value
        writer.set(control, value, for: key, phase: dragging.contains(control) ? .changed : .ended)
    }

    /// SliderSetting's drag phases; `.ended` repeats the final value so the mailbox always delivers it.
    func phase(_ control: LiveControl, _ phase: DragPhase, current: Double) {
        switch phase {
        case .began:
            dragging.insert(control)
            lastSent[control] = current
            writer.set(control, current, for: key, phase: .began)
        case .changed:
            break
        case .ended:
            dragging.remove(control)
            writer.set(control, lastSent[control] ?? current, for: key, phase: .ended)
        }
    }

    /// Until C's runtime fields are written, the brightness service's own reading.
    var brightnessReading: Double? { context?.brightness.value(for: key) }

    var isReadingBrightness: Bool { context?.brightness.isAwaitingFirstRead(key) ?? false }

    // MARK: Resolution (D)

    private var resolution: ResolutionController? { context?.connectPlanner.resolution }

    func current(_ display: DisplayInfo) -> ModeRef? { resolution?.currentMode(display) }

    func modes() -> [DisplayModeDescriptor] { resolution?.modes(for: key) ?? [] }

    func favorites(_ modes: [DisplayModeDescriptor]) -> [ModeRef] {
        let refs = modes.map(\.ref)
        return (resolution?.favorites(key) ?? []).compactMap { $0.resolve(in: refs) }
    }

    func apply(_ mode: ModeRef, display: DisplayInfo) {
        guard let resolution, mode != resolution.currentMode(display) else { return }
        resolution.apply(mode, to: key, label: L("Resolution of “\(display.name)”"))
    }

    // MARK: Hardware controls (C)

    private var ddc: DDCController? { context?.ddc.controller }
    private var ddcAvailable: Bool { context?.ddc.isAvailable(key) ?? false }

    /// The same rule as the menu: volume only for displays with VCP 0x62.
    var showsVolume: Bool {
        guard let ctx = context, ddcAvailable, ddc != nil else { return false }
        let caps = ctx.ddc.cachedCapabilities(key)
        return caps?.supports(VCPPolicy.volume) == true
            || (caps == nil && ctx.ddc.lastReading(VCPPolicy.volume, of: key) != nil)
    }

    var inputs: [DDCInputEntry] {
        guard ddcAvailable, let ddc else { return [] }
        return ddc.inputList(for: key)
    }

    func inputName(_ entry: DDCInputEntry) -> String { ddc?.inputName(entry) ?? DisplaysUIText.inputName(entry.value) }

    /// C confirms first: switching the input can leave this Mac without a picture.
    func setInput(_ entry: DDCInputEntry) { _ = ddc?.setInput(entry, on: key) }

    func toggleMute() { ddc?.toggleMute(.display(key)) }

    // MARK: Built-in auto-brightness (C)

    func autoBrightness() -> Bool? { context?.appleBrightness.autoBrightness(of: key) }

    func setAutoBrightness(_ on: Bool) {
        guard let ctx = context else { return }
        if let controller = ctx.colorSync.systemColors {
            controller.setAutoBrightness(on, for: key)
        } else {
            _ = ctx.appleBrightness.setAutoBrightness(on, of: key)
        }
    }
}

/// One model per connected display for a page that shows one display at a time (the root page): models survive
/// switching between display tiles and are dropped when the module restarts.
@MainActor final class DisplayLiveModelCache: ObservableObject {
    private var models: [DisplayKey: DisplayLiveModel] = [:]
    private weak var context: DisplaysContext?

    init() {}

    func model(_ key: DisplayKey, context: DisplaysContext) -> DisplayLiveModel {
        if self.context !== context {
            models = [:]
            self.context = context
        }
        if let model = models[key] { return model }
        let model = DisplayLiveModel(key: key, context: context)
        models[key] = model
        return model
    }
}

// MARK: - Shared rows

/// Brightness for one display: the full range including extra (XDR) brightness, written live, no default.
struct LiveBrightnessRow: View {
    let anchor: ControlID?
    @ObservedObject var live: DisplayRuntime
    @ObservedObject var model: DisplayLiveModel

    var body: some View {
        if let value = live.brightnessPosition ?? live.brightness ?? model.brightnessReading {
            let range: ClosedRange<Double> = live.brightnessPosition == nil ? 0...1 : live.brightnessRange
            SliderSetting(L("Brightness"), value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                                                          set: { model.set(.brightness, $0) }),
                          in: range, defaultValue: nil, format: .percent(of: 1), minSymbol: "sun.min",
                          maxSymbol: "sun.max", commit: .live, anchor: anchor,
                          phase: { model.phase(.brightness, $0, current: value) })
        } else if model.isReadingBrightness {
            SliderSetting(L("Brightness"), value: .constant(0), in: 0...1, defaultValue: nil, format: .percent(of: 1),
                          minSymbol: "sun.min", maxSymbol: "sun.max", commit: .live, anchor: anchor,
                          disabledReason: L("Reading this display’s brightness…"))
        }
    }
}

/// The display's speaker volume (hardware controls) and Mute.
struct LiveVolumeRows: View {
    @ObservedObject var live: DisplayRuntime
    @ObservedObject var model: DisplayLiveModel

    var body: some View {
        let range = live.volumeRange
        let value = min(max(live.volume ?? range.lowerBound, range.lowerBound), range.upperBound)
        SliderSetting(L("Volume"), value: Binding(get: { value }, set: { model.set(.volume, $0) }), in: range,
                      defaultValue: nil, format: .percent(of: 1), minSymbol: "speaker.fill",
                      maxSymbol: "speaker.wave.3.fill", commit: .live,
                      phase: { model.phase(.volume, $0, current: value) })
        ToggleSetting(L("Mute"), isOn: Binding(get: { live.muted ?? false }, set: { _ in model.toggleMute() }))
    }
}

/// The Resolution pop-up: the default size first, then every size from largest to smallest; favorites marked.
struct LiveResolutionRow: View {
    let display: DisplayInfo
    let anchor: ControlID?
    @ObservedObject var model: DisplayLiveModel
    /// Re-reads the mode list when D reports a change (undo, favorites, filters).
    @ObservedObject var revision: ControllerRevision

    var body: some View {
        let modes = model.modes()
        let current = model.current(display)
        let sizes = LiveResolution.sizes(modes, current: current, favorites: model.favorites(modes))
        if !sizes.isEmpty, let current {
            PickerSetting(L("Resolution"),
                          selection: Binding(get: { LiveResolution.sizeID(of: current) }, set: { id in
                              if let mode = LiveResolution.mode(forSize: id, in: modes, current: current) {
                                  model.apply(mode, display: display)
                              }
                          }),
                          options: sizes.map { PickerOption($0.id, $0.title, symbol: $0.isFavorite ? "star.fill" : nil) },
                          style: .popUp, defaultValue: nil, anchor: anchor)
        }
    }
}

/// The Refresh rate pop-up, only when the current size offers more than one rate.
struct LiveRefreshRow: View {
    let display: DisplayInfo
    let anchor: ControlID?
    @ObservedObject var model: DisplayLiveModel
    @ObservedObject var revision: ControllerRevision

    var body: some View {
        let modes = model.modes()
        let current = model.current(display)
        let rates = LiveResolution.refreshRates(modes, current: current)
        if rates.count > 1, let current, let selected = LiveResolution.choice(for: current.refreshMilliHz, in: rates) {
            PickerSetting(L("Refresh rate"),
                          selection: Binding(get: { selected }, set: { hz in
                              if let mode = LiveResolution.mode(forRefresh: hz, in: modes, current: current) {
                                  model.apply(mode, display: display)
                              }
                          }),
                          options: rates.map { PickerOption($0.milliHz, $0.title) },
                          style: .popUp, defaultValue: nil, anchor: anchor)
        }
    }
}

/// The display's input source (hardware controls with input switching). C asks before switching.
struct LiveInputRow: View {
    @ObservedObject var live: DisplayRuntime
    @ObservedObject var model: DisplayLiveModel
    @ObservedObject var revision: ControllerRevision

    var body: some View {
        let inputs = model.inputs
        if !inputs.isEmpty {
            let currentID = inputs.first { !$0.lgAlt && $0.value == live.input }?.id
            PickerSetting(L("Input"),
                          selection: Binding(get: { currentID ?? "" }, set: { id in
                              if let entry = inputs.first(where: { $0.id == id }) { model.setInput(entry) }
                          }),
                          options: options(inputs, known: currentID != nil),
                          style: .popUp, defaultValue: nil)
        }
    }

    /// The inputs, after an "Unknown" placeholder while the current input isn't one of them.
    private func options(_ inputs: [DDCInputEntry], known: Bool) -> [PickerOption<String>] {
        var options: [PickerOption<String>] = known ? [] : [PickerOption("", L("Unknown"), enabled: false)]
        for entry in inputs { options.append(PickerOption(entry.id, model.inputName(entry))) }
        return options
    }
}

/// Automatically adjust brightness (built-in displays, with the Experimental `autoBrightness` feature on).
struct LiveAutoBrightnessRow: View {
    let anchor: ControlID?
    @ObservedObject var model: DisplayLiveModel
    @ObservedObject var revision: ControllerRevision

    var body: some View {
        if let on = model.autoBrightness() {
            ToggleSetting(L("Automatically adjust brightness"),
                          help: L("The built-in display follows the light around your Mac."),
                          isOn: Binding(get: { on }, set: { model.setAutoBrightness($0) }), anchor: anchor)
        }
    }
}

// MARK: - Panel content (PLAN 0.3 §5.6)

/// One display's group in the floating panel: header with the "⋯" button, then the shared live rows (brightness,
/// volume, resolution, input).
struct DisplayLiveControls: View, ControlDeclaring {
    typealias Controls = DisplayLiveControlsControls

    let display: DisplayInfo
    let context: DisplaysContext
    let showMore: @MainActor (DisplayInfo, NSView?) -> Void
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var live: DisplayRuntime
    @StateObject private var model: DisplayLiveModel
    @State private var moreAnchor = ViewAnchor()

    init(display: DisplayInfo, context: DisplaysContext, showMore: @escaping @MainActor (DisplayInfo, NSView?) -> Void) {
        self.display = display
        self.context = context
        self.showMore = showMore
        _runtime = ObservedObject(wrappedValue: context.runtime)
        _live = ObservedObject(wrappedValue: context.runtime.runtime(for: display.key))
        _model = StateObject(wrappedValue: DisplayLiveModel(key: display.key, context: context))
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if runtime.isEffective(.brightness) {
                    LiveBrightnessRow(anchor: nil, live: live, model: model)
                }
                if runtime.isEffective(.ddcControls), model.showsVolume {
                    LiveVolumeRows(live: live, model: model)
                }
                if runtime.isEffective(.resolution), display.isActive, display.mirrorOf == nil {
                    LiveResolutionRow(display: display, anchor: nil, model: model,
                                      revision: runtime.revision(.resolution))
                }
                if runtime.isEffective(.ddcInput) {
                    LiveInputRow(live: live, model: model, revision: runtime.revision(.ddc))
                }
            }
            .padding(.vertical, 2)
        } label: {
            header
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(display.name))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: DisplaysLive.symbol(for: display, config: context.config.value))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(display.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let badge = DisplaysLive.badges(for: display).first {
                Text(badge)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                showMore(display, moreAnchor.view)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .background(ViewAnchorReader(anchor: moreAnchor))
            .help(L("More options for this display"))
            .accessibilityLabel(L("More options for \(display.name)"))
            .modifier(SettingsAnchor(ControlID("displays.panel.more")))
        }
    }
}

/// The floating Displays panel: status rows while they're true, one group per display shown in the menu, and the
/// footer buttons (Identify, Restore All Displays, Settings).
struct DisplaysPanelContent: View, ControlDeclaring {
    typealias Controls = DisplayLiveControlsControls

    let context: DisplaysContext
    let actions: DisplaysPanelActions
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var config: ConfigStore<DisplaysConfig>
    /// B bumps it when the guard or panic state changes (the status rows).
    @ObservedObject private var safetyRevision: ControllerRevision

    init(context: DisplaysContext, actions: DisplaysPanelActions) {
        self.context = context
        self.actions = actions
        _runtime = ObservedObject(wrappedValue: context.runtime)
        _safetyRevision = ObservedObject(wrappedValue: context.runtime.revision(.diagnostics))
        _config = ObservedObject(wrappedValue: context.config)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            status
            let displays = DisplaysLive.ordered(runtime: runtime, menu: config.value.menu, includeHidden: false)
            if displays.isEmpty {
                Text(runtime.displays.isEmpty ? L("No displays are connected.")
                                              : L("Every display is hidden from the menu."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if displays.count > 3 {
                ScrollView { groups(displays) }
                    .frame(height: 480)
            } else {
                groups(displays)
            }
            Divider()
            HStack(spacing: 8) {
                Button(L("Identify")) { actions.identify() }
                    .help(L("Show each display’s number and name"))
                    .modifier(SettingsAnchor(ControlID("displays.panel.identify")))
                Button(L("Restore All Displays")) { actions.restoreAll() }
                    .help(L("Undo Snaptic’s display changes"))
                    .modifier(SettingsAnchor(ControlID("displays.panel.restoreAll")))
                Spacer(minLength: 8)
                Button { actions.settings() } label: {
                    Image(systemName: "gearshape")
                }
                .help(L("Open Displays settings"))
                .accessibilityLabel(L("Displays Settings"))
                .modifier(SettingsAnchor(ControlID("displays.panel.settings")))
            }
        }
        .padding(16)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func groups(_ displays: [DisplayInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(displays) { display in
                DisplayLiveControls(display: display, context: context, showMore: actions.showMore)
                    .id(display.key)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if context.safeMode.isActive {
            StatusRow(L("Safe Mode is on."), style: .warning)
        }
        if runtime.isPanicLatched {
            StatusRow(L("Display automation is paused."), symbol: "pause.circle", actions: [
                StatusAction(title: L("Resume"), control: ControlID("displays.panel.resume")) { actions.resume() },
            ])
        }
        if DisplaysLive.unprotectedReason(context) != nil {
            StatusRow(L("The safety helper stopped."), style: .warning)
        }
    }
}

/// The panel's buttons, wired by OverviewController.
struct DisplaysPanelActions {
    let identify: @MainActor () -> Void
    let restoreAll: @MainActor () -> Void
    let resume: @MainActor () -> Void
    let settings: @MainActor () -> Void
    /// Pops the display's menu content at the "⋯" button (or at the pointer without one).
    let showMore: @MainActor (DisplayInfo, NSView?) -> Void
}

// MARK: - Helpers

/// Small pure-ish helpers the Displays pages and the panel share (kept here so the pages don't depend on the menu
/// builder's internals).
@MainActor enum DisplaysLive {
    /// Displays in the user's menu order (main first when set); hidden ones only with `includeHidden`.
    static func ordered(runtime: DisplaysRuntimeState, menu: MenuConfig, includeHidden: Bool) -> [DisplayInfo] {
        let all = runtime.displays
        let main = all.first(where: \.isMain)?.key
        let order = menu.orderedDisplays(all.map(\.key), main: main, includeHidden: includeHidden)
        return order.compactMap { key in all.first { $0.key == key } }
    }

    /// The user's icon when this macOS has it, else one for the connection.
    static func symbol(for display: DisplayInfo, config: DisplaysConfig?) -> String {
        if let chosen = config?.perDisplay[display.key]?.identity.symbol,
           NSImage(systemSymbolName: chosen, accessibilityDescription: nil) != nil {
            return chosen
        }
        return automaticSymbol(for: display)
    }

    static func automaticSymbol(for display: DisplayInfo) -> String {
        switch display.transport {
        case .builtin: return "laptopcomputer"
        case .airplay: return "airplayvideo"
        case .sidecar: return "ipad.landscape"
        case .snapticVirtual, .foreignVirtual: return "rectangle.dashed"
        case .wired, .displayLink: return "display"
        }
    }

    /// Short state words for a display tile or group ("Main", "Mirroring").
    static func badges(for display: DisplayInfo) -> [String] {
        var badges: [String] = []
        if display.isMain { badges.append(L("Main")) }
        if display.transport == .snapticVirtual || display.transport == .foreignVirtual { badges.append(L("Virtual")) }
        if display.mirrorOf != nil { badges.append(L("Mirroring")) }
        if !display.isOnline || !display.isActive { badges.append(L("Disconnected")) }
        return badges
    }

    /// Why risky changes can't be reverted automatically right now, or nil (PLAN §3.5 "Unprotected").
    static func unprotectedReason(_ ctx: DisplaysContext) -> String? {
        if let reason = ctx.helpers.unavailable {
            return L("Snaptic’s helpers can’t run (\(reason)), so risky display changes can’t be reverted automatically.")
        }
        if ctx.guardClient.isUnprotected {
            return L("The safety helper that reverts risky display changes isn’t running.")
        }
        return nil
    }

    /// The live writer for a context: C's `DisplayLiveController` (latest-wins mailbox per display and control).
    static func makeWriter(_ context: DisplaysContext?) -> DisplayLiveControlling {
        let writer = DisplayLiveController()
        writer.context = context
        return writer
    }
}

/// A weak handle on the AppKit view behind a SwiftUI control, so a menu can pop up at it.
final class ViewAnchor {
    weak var view: NSView?
}

private struct ViewAnchorReader: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
