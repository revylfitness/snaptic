import SwiftUI
import SnapticKit

/// The Picture in Picture editor (owner E; PLAN 0.3 §4.3 "Editor = sheet"): one saved configuration, or a new one.
/// Name, Show as, Stream onto and the offer to start; Window (level, opacity, click-through, position, aspect, sharp
/// pixels, title bar, 25% steps, shadow, Reset Window Position); Capture (refresh rate or frames per second, pointer,
/// ⌘-click, crop); Orientation; Full screen (scaling, size, native resolution); Filters (lookup table and a
/// reorderable filter chain). An existing configuration is edited in place, as a running one updates live; a new one
/// is a draft until Add. Opens no other sheet: Delete… is a standard alert.
struct PIPEditorSheet: View, ControlDeclaring {
    typealias Controls = PIPEditorSheetControls

    let env: DisplaysPageEnvironment
    let request: PIPEditorRequest
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var entries: ConfigSlice<DisplaysConfig, [PIPEntry]>
    @StateObject private var luts: ConfigSlice<DisplaysConfig, [PIPLUTReference]>
    @Environment(\.dismiss) private var dismiss
    /// A new configuration's edits (nil until the first one).
    @State private var draft: PIPConfiguration?
    @State private var draftSource: PIPSourceRef?
    /// The name being typed (nil = not editing; a new configuration then uses its default name).
    @State private var typedName: String?
    @FocusState private var nameFocused: Bool
    @State private var confirmingDelete = false

    init(env: DisplaysPageEnvironment, request: PIPEditorRequest) {
        self.env = env
        self.request = request
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _entries = StateObject(wrappedValue: ConfigSlice(env.config, \.pipEditorEntries))
        _luts = StateObject(wrappedValue: ConfigSlice(env.config, \.pip.luts))
    }

    // MARK: Model

    private var isNew: Bool {
        if case .new = request.mode { return true }
        return false
    }

    private var entry: PIPEntry? { entries.value.first { $0.configuration.id == request.id } }

    private var configuration: PIPConfiguration {
        switch request.mode {
        case .edit: return entry?.configuration ?? PIPConfiguration(id: request.id)
        case .new(let initial, _): return draft ?? initial
        }
    }

    private var source: PIPSourceRef {
        switch request.mode {
        case .edit: return entry?.source ?? .window
        case .new(_, let initial): return draftSource ?? initial
        }
    }

    private var isDisplaySource: Bool {
        if case .display = source { return true }
        return false
    }

    private func update(_ body: (inout PIPConfiguration) -> Void) {
        switch request.mode {
        case .edit:
            var value = env.config.value
            guard PIPConfig.update(request.id, in: &value, body) else { return }
            if value != env.config.value { env.config.value = value }
        case .new:
            var c = configuration
            body(&c)
            let name = c.name
            c = c.sanitized()
            c.name = name
            draft = c
        }
    }

    private func field<T>(_ path: WritableKeyPath<PIPConfiguration, T>) -> Binding<T> {
        Binding(get: { configuration[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }

    private var defaultName: String {
        let config = env.config.value
        let c = configuration
        return PIPSettingsText.defaultName(
            sourceName: PIPPageText.sourceName(source, runtime: runtime, config: config),
            kind: c.kind,
            targetName: c.target.map { PIPPageText.displayName($0, runtime: runtime, config: config) })
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if !isNew && entry == nil {
                Form {
                    Section {
                        StatusRow(L("This Picture in Picture was deleted."))
                    }
                }
                .formStyle(.grouped)
            } else {
                SettingsAnchorScroller {
                    Form {
                        generalSection
                        if configuration.kind == .window { windowSection }
                        captureSection
                        orientationSection
                        if configuration.kind == .fullScreen { fullScreenSection }
                        filtersSection
                    }
                    .formStyle(.grouped)
                }
            }
            Divider()
            footer
        }
        .frame(width: 520)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: 760)
        .onAppear { SettingsShell.shared.sheetDidAppear() }
        .onExitCommand { close() }
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
        .alert(L("Delete “\(configuration.name)”?"), isPresented: $confirmingDelete) {
            Button(L("Delete"), role: .destructive) { delete() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("It stops first if it’s running."))
        }
    }

    private var title: String {
        switch request.mode {
        case .edit: return configuration.name
        case .new(let initial, _): return initial.kind == .fullScreen ? L("New Stream") : L("New Picture in Picture")
        }
    }

    // MARK: General

    @ViewBuilder private var generalSection: some View {
        let c = configuration
        Section {
            if isNew {
                PickerSetting(L("Source"), selection: sourceBinding, options: sourceOptions, style: .popUp,
                              defaultValue: nil, anchor: ControlID("displays.pip.editor.source"))
            }
            TextField(text: nameBinding, prompt: Text(isNew ? defaultName : c.name)) {
                Text(L("Name"))
            }
            .focused($nameFocused)
            .onSubmit(commitName)
            .modifier(SettingsAnchor(ControlID("displays.pip.editor.name")))
            PickerSetting(L("Show as"), selection: field(\.kind), options: [
                PickerOption(PIPKind.window, L("Floating window"), help: L("A window you can move and resize.")),
                PickerOption(PIPKind.fullScreen, L("Full-screen stream"), help: L("Fills another display.")),
            ], style: .radio, defaultValue: nil, anchor: ControlID("displays.pip.editor.showAs"))
            if c.kind == .fullScreen {
                PickerSetting(L("Stream onto"), selection: field(\.target), options: targetOptions, style: .popUp,
                              defaultValue: nil, anchor: ControlID("displays.pip.editor.target"))
            }
            if isDisplaySource {
                ToggleSetting(L("Offer to start when the display connects"),
                              help: L("Snaptic asks first. It never starts a capture by itself or in Safe Mode."),
                              isOn: field(\.autoStart), anchor: ControlID("displays.pip.editor.autoStart"))
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { typedName ?? (isNew ? "" : configuration.name) }, set: { typedName = $0 })
    }

    /// Saves the typed name (cleaned; empty = the default name for a new one, unchanged for a saved one).
    private func commitName() {
        guard let typed = typedName else { return }
        if isNew {
            let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { typedName = nil }
            return
        }
        typedName = nil
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleaned = PIPConfiguration.cleanName(trimmed)
        if cleaned != configuration.name { update { $0.name = cleaned } }
    }

    private var sourceBinding: Binding<PIPSourceRef> {
        Binding(get: { source }, set: { new in
            draftSource = new
            // A stream can't go onto its own source.
            if case .display(let key) = new, configuration.target == key {
                update { $0.target = PIPPageText.connected(runtime).first { $0.key != key }?.key }
            }
        })
    }

    private var sourceOptions: [PickerOption<PIPSourceRef>] {
        let config = env.config.value
        var options = [PickerOption(PIPSourceRef.window, L("Choose a Window When It Starts"),
                                    enabled: PIPSettingsText.canAdd(source: .window, in: config))]
        for d in PIPPageText.connected(runtime) {
            options.append(PickerOption(PIPSourceRef.display(d.key), d.name,
                                        enabled: PIPSettingsText.canAdd(source: .display(d.key), in: config)))
        }
        return options
    }

    private var targetOptions: [PickerOption<DisplayKey?>] {
        var sourceKey: DisplayKey?
        if case .display(let key) = source { sourceKey = key }
        var options = [PickerOption<DisplayKey?>(nil, L("Choose a Display"))]
        let config = env.config.value
        var keys = PIPPageText.connected(runtime).map(\.key).filter { $0 != sourceKey }
        if let current = configuration.target, !keys.contains(current), current != sourceKey { keys.append(current) }
        for key in keys {
            options.append(PickerOption<DisplayKey?>(key, PIPPageText.displayName(key, runtime: runtime, config: config)))
        }
        return options
    }

    // MARK: Window

    private var windowSection: some View {
        let c = configuration
        return Section(L("Window")) {
            PickerSetting(L("Level"), selection: field(\.level), options: [
                PickerOption(PIPLevel.normal, L("Normal")),
                PickerOption(PIPLevel.floating, L("Floating")),
                PickerOption(PIPLevel.aboveAll, L("Above Everything")),
            ], style: .popUp, defaultValue: PIPConfiguration().level, anchor: ControlID("displays.pip.editor.level"))
            SliderSetting(L("Opacity"), value: field(\.opacity), in: PIPConfiguration.opacityRange, step: 0.05,
                          defaultValue: PIPConfiguration().opacity, format: .percent(of: 1),
                          anchor: ControlID("displays.pip.editor.opacity"))
            ToggleSetting(L("Click through"), help: L("Clicks go to the window underneath. ⌃⌥⌘P turns this off."),
                          isOn: field(\.clickThrough), anchor: ControlID("displays.pip.editor.clickThrough"))
            ToggleSetting(L("Lock position"), help: L("The window can’t be moved or resized."),
                          isOn: field(\.lockPosition), anchor: ControlID("displays.pip.editor.lockPosition"))
            ToggleSetting(L("Keep the aspect ratio"), help: L("Resizing keeps the source’s proportions."),
                          isOn: field(\.lockAspect), anchor: ControlID("displays.pip.editor.lockAspect"))
            ToggleSetting(L("Sharp pixels"), help: L("Scales by whole numbers, without smoothing."),
                          isOn: field(\.integerScaling), anchor: ControlID("displays.pip.editor.integerScaling"))
            ToggleSetting(L("Title bar"), isOn: field(\.showTitleBar),
                          anchor: ControlID("displays.pip.editor.showTitleBar"))
            ToggleSetting(L("Snap size to 25% steps"), help: L("Resizing stops at a quarter, half, and full size."),
                          isOn: field(\.snapToQuarters), anchor: ControlID("displays.pip.editor.snapToQuarters"))
            ToggleSetting(L("Shadow"), isOn: field(\.shadow), anchor: ControlID("displays.pip.editor.shadow"))
            ButtonRow(L("Reset Window Position"), help: L("Opens it next time where a new window would open."),
                      control: ControlID("displays.pip.editor.resetPosition")) {
                update { $0.windowFrame = nil }
            }
            .disabled(c.windowFrame == nil)
        }
    }

    // MARK: Capture

    @ViewBuilder private var captureSection: some View {
        let c = configuration
        Section(L("Capture")) {
            ToggleSetting(L("Match the display’s refresh rate"),
                          help: L("Up to 120 frames per second, as fast as the source changes."),
                          isOn: Binding(get: { configuration.fps == 0 },
                                        set: { on in update { $0.fps = on ? 0 : PIPConfiguration().fps } }),
                          anchor: ControlID("displays.pip.editor.matchRefresh"))
            if c.fps != 0 {
                SliderSetting(L("Frames per second"), value: fpsBinding,
                              in: Double(PIPConfiguration.fpsRange.lowerBound)...Double(PIPConfiguration.fpsRange.upperBound),
                              step: 1, defaultValue: Double(PIPConfiguration().fps), format: .plain(digits: 0),
                              anchor: ControlID("displays.pip.editor.fps"), subordinate: true)
            }
            ToggleSetting(L("Show the pointer"), isOn: field(\.showCursor),
                          anchor: ControlID("displays.pip.editor.showCursor"))
            if isDisplaySource {
                ToggleSetting(L("⌘-click moves the pointer there"),
                              help: L("Command-click in the picture to jump to that spot on the source display."),
                              isOn: field(\.warpOnCommandClick),
                              anchor: ControlID("displays.pip.editor.warpOnCommandClick"))
            }
            if let capture = env.context?.capture {
                PIPCropRow(id: request.id, crop: c.crop, isWindow: c.kind == .window, capture: capture,
                           reset: { update { $0.crop = nil } })
            }
        }
    }

    private var fpsBinding: Binding<Double> {
        Binding(get: { Double(configuration.fps) },
                set: { v in
                    let fps = Int(v.rounded())
                    update { $0.fps = max(PIPConfiguration.fpsRange.lowerBound, fps) }
                })
    }

    // MARK: Orientation

    private var orientationSection: some View {
        Section(L("Orientation")) {
            PickerSetting(L("Rotation"), selection: field(\.rotation), options: [
                PickerOption(0, L("0°")), PickerOption(90, L("90°")), PickerOption(180, L("180°")),
                PickerOption(270, L("270°")),
            ], style: .segmented, defaultValue: 0, anchor: ControlID("displays.pip.editor.rotation"))
            ToggleSetting(L("Flip horizontally"), isOn: field(\.flipHorizontal),
                          anchor: ControlID("displays.pip.editor.flipHorizontal"))
            ToggleSetting(L("Flip vertically"), help: L("For a teleprompter, together with a horizontal flip."),
                          isOn: field(\.flipVertical), anchor: ControlID("displays.pip.editor.flipVertical"))
        }
    }

    // MARK: Full screen

    private var fullScreenSection: some View {
        let resolutionOn = runtime.isEffective(.resolution)
        return Section {
            PickerSetting(L("Scaling"), selection: field(\.scaling), options: [
                PickerOption(PIPScaling.fit, L("Fit")),
                PickerOption(PIPScaling.fill, L("Fill")),
                PickerOption(PIPScaling.oneToOne, L("1:1 Pixels")),
                PickerOption(PIPScaling.integer, L("Whole Multiples")),
            ], style: .popUp, defaultValue: PIPConfiguration().scaling, anchor: ControlID("displays.pip.editor.scaling"))
            SliderSetting(L("Size"), help: L("Below 100% leaves a black border around the picture."),
                          value: SettingsBinding.double(field(\.underscanPercent), in: PIPConfiguration.underscanRange),
                          in: Double(PIPConfiguration.underscanRange.lowerBound)...Double(PIPConfiguration.underscanRange.upperBound),
                          step: 5, defaultValue: Double(PIPConfiguration().underscanPercent), format: .percent(of: 100),
                          anchor: ControlID("displays.pip.editor.size"))
            ToggleSetting(L("Use the native resolution while streaming"),
                          help: L("Switches the target display while the stream runs, then switches it back."),
                          isOn: field(\.nativeModeWhileStreaming), anchor: ControlID("displays.pip.editor.nativeMode"),
                          disabledReason: resolutionOn ? nil : L("Needs Resolution control in Displays › Advanced."))
        } header: {
            Text(L("Full screen"))
        } footer: {
            Text(L("Snaptic won’t stream onto the only display you can see. ⌃⌥⌘P or Restore All Displays stops a stream."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Filters

    @ViewBuilder private var filtersSection: some View {
        let c = configuration
        Section {
            if !runtime.isEffective(.pipFilters) {
                SettingsRowNote(L("Filters are off."),
                                fix: StatusAction(title: L("Turn On Filters"),
                                                  control: ControlID("displays.pip.editor.turnOnFilters")) {
                                    env.enableFeature(.pipFilters)
                                })
            } else {
                PickerSetting(L("Color lookup table"), help: luts.value.isEmpty
                                  ? L("Import one on the Picture in Picture page.") : nil,
                              selection: field(\.lutID), options: lutOptions, style: .popUp, defaultValue: nil,
                              anchor: ControlID("displays.pip.editor.lut"))
                    .disabled(luts.value.isEmpty && c.lutID == nil)
                if c.filters.isEmpty {
                    Text(L("No filters. Filters apply from top to bottom."))
                        .foregroundStyle(.secondary)
                } else {
                    ReorderableList(filterItems, onDelete: { item in removeFilter(item.id) }) { item in
                        PIPFilterRow(item: item, value: { key in filterValue(item.id, key) },
                                     setEnabled: { on in setFilter(item.id) { $0.enabled = on } },
                                     setValue: { key, v in setFilter(item.id) { $0.values[key] = v } },
                                     remove: { removeFilter(item.id) })
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    Menu(L("Add Filter")) {
                        ForEach(FilterCategory.allCases, id: \.self) { category in
                            Section(category.title) {
                                ForEach(FilterSpec.kinds(in: category), id: \.self) { kind in
                                    Button(FilterSpec.descriptor(kind).title) {
                                        update { $0.filters.append(FilterInstance(kind: kind)) }
                                    }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(c.filters.count >= PIPConfiguration.maxFilters)
                    .modifier(SettingsAnchor(ControlID("displays.pip.editor.addFilter")))
                }
            }
        } header: {
            Text(L("Filters"))
                .modifier(SettingsAnchor(ControlID("displays.pip.editor.filters")))
        }
    }

    private var lutOptions: [PickerOption<StableID?>] {
        var options = [PickerOption<StableID?>(nil, L("None"))]
        for lut in luts.value { options.append(PickerOption<StableID?>(lut.id, lut.name)) }
        return options
    }

    /// The chain as identifiable rows (position = id); writing it back stores the new order.
    private var filterItems: Binding<[PIPFilterItem]> {
        Binding(get: { configuration.filters.enumerated().map { PIPFilterItem(id: $0.offset, filter: $0.element) } },
                set: { items in update { $0.filters = items.map(\.filter) } })
    }

    private func filterValue(_ index: Int, _ key: String) -> Double {
        let filters = configuration.filters
        return filters.indices.contains(index) ? filters[index].value(key) : 0
    }

    private func setFilter(_ index: Int, _ body: @escaping (inout FilterInstance) -> Void) {
        update { c in
            guard c.filters.indices.contains(index) else { return }
            body(&c.filters[index])
        }
    }

    private func removeFilter(_ index: Int) {
        update { c in
            guard c.filters.indices.contains(index) else { return }
            c.filters.remove(at: index)
        }
    }

    // MARK: Footer

    private var footer: some View {
        let refusal = isNew ? PIPSettingsText.addRefusal(configuration, source: source, in: env.config.value) : nil
        return HStack(spacing: 8) {
            if isNew {
                if let refusal {
                    Text(refusal)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Add")) { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(refusal != nil)
            } else {
                if entry != nil {
                    Button(configuration.kind == .fullScreen ? L("Delete Stream…") : L("Delete Picture in Picture…"), role: .destructive) {
                        confirmingDelete = true
                    }
                        .modifier(SettingsAnchor(ControlID("displays.pip.editor.delete")))
                }
                Spacer(minLength: 8)
                Button(L("Done")) { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func close() {
        FocusedField.commit()
        commitName()
        dismiss()
    }

    private func add() {
        FocusedField.commit()
        var c = configuration
        let typed = (typedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        c.name = PIPConfiguration.cleanName(typed.isEmpty ? defaultName : typed)
        var value = env.config.value
        guard PIPSettingsText.addRefusal(c, source: source, in: value) == nil,
              PIPConfig.add(c, source: source, to: &value) else { return }
        env.config.value = value
        dismiss()
    }

    private func delete() {
        env.context?.capture.controller?.endSession(request.id, reason: nil)
        var value = env.config.value
        if PIPConfig.remove(request.id, from: &value) { env.config.value = value }
        dismiss()
    }
}

fileprivate extension DisplaysConfig {
    /// Every saved configuration with its source (the editor's slice).
    var pipEditorEntries: [PIPEntry] { PIPConfig.entries(in: self) }
}

/// One filter of the chain, by position.
private struct PIPFilterItem: Identifiable {
    let id: Int
    let filter: FilterInstance
}

/// A filter: its on/off checkbox and remove button, then its values (while it's on).
private struct PIPFilterRow: View {
    let item: PIPFilterItem
    let value: (String) -> Double
    let setEnabled: (Bool) -> Void
    let setValue: (String, Double) -> Void
    let remove: () -> Void

    var body: some View {
        let descriptor = FilterSpec.descriptor(item.filter.kind)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(descriptor.title, isOn: Binding(get: { item.filter.enabled }, set: { setEnabled($0) }))
                    .toggleStyle(.checkbox)
                Spacer(minLength: 8)
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(L("Remove \(descriptor.title)"))
                .accessibilityLabel(L("Remove \(descriptor.title)"))
            }
            if item.filter.enabled {
                ForEach(descriptor.parameters, id: \.key) { p in
                    let style = p.sliderStyle
                    SliderSetting(style.title, value: Binding(get: { value(p.key) }, set: { setValue(p.key, $0) }),
                                  in: p.min...p.max, step: style.step, defaultValue: p.defaultValue,
                                  format: style.format, subordinate: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Crop: the current rectangle, Draw Crop… (on the running window) and Reset. Observes the sessions, so Draw Crop…
/// turns on as soon as the picture in picture starts.
private struct PIPCropRow: View, ControlDeclaring {
    typealias Controls = PIPEditorSheetControls

    let id: StableID
    let crop: PIPRect?
    let isWindow: Bool
    @ObservedObject var capture: CaptureService
    let reset: () -> Void

    var body: some View {
        let running = capture.sessions.contains { $0.id == id && $0.kind == .window }
        SettingRow(L("Crop"),
                   help: running || !isWindow ? PIPSettingsText.crop(crop)
                       : PIPSettingsText.crop(crop) + " · " + L("Start it to draw a crop on its window."),
                   anchor: ControlID("displays.pip.editor.crop"),
                   isDefault: crop == nil, reset: reset) {
            HStack(spacing: 8) {
                Button(L("Draw Crop…")) { capture.controller?.beginCrop(id) }
                    .disabled(!running)
                Button(L("Reset")) { reset() }
                    .disabled(crop == nil)
            }
        }
    }
}
