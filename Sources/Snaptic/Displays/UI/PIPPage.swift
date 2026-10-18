import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

/// Picture in Picture settings (PLAN §10): running sessions, saved configurations per
/// source, the configuration editor (window, capture, geometry, full screen, filters),
/// imported LUTs, privacy rules and options.
struct PIPPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var selection: StableID?
    @State private var newPrefix = ""
    @State private var lutMessage: String?
    @State private var importing = false

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    var body: some View {
        Form {
            intro
            if let capture = env.context?.capture {
                PIPRunningSection(capture: capture)
            }
            configurations
            if let id = selection, PIPConfig.entry(id, in: env.config.value) != nil {
                PIPConfigurationEditor(env: env, id: id, onDelete: { selection = nil })
            }
            luts
            privacy
            options
        }
        .formStyle(.grouped)
    }

    // MARK: Intro and permission

    @ViewBuilder
    private var intro: some View {
        Section {
            Label(L("Picture in Picture"), systemImage: "pip").font(.headline)
            Text(L("Show a live copy of a display or a window in a floating window, or stream one display full screen onto another."))
                .foregroundStyle(.secondary)
            if !env.config.value.pip.firstRunAcknowledged {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Before you start")).font(.subheadline.weight(.semibold))
                    Text(L("Snaptic needs Screen Recording to show other displays. macOS asks for it once, and on recent versions asks again about once a month. After you allow it, relaunch Snaptic so the permission takes effect. Window sources are chosen in the system picker each time."))
                        .font(.callout)
                    Button(L("Got It")) { env.config.value.pip.firstRunAcknowledged = true }
                }
                .padding(.vertical, 4)
            }
            if let ctx = env.context {
                let granted = ctx.permissions.state(.screenRecording) == .granted
                LabeledContent(L("Screen Recording")) {
                    if granted {
                        Label(L("Allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(L("Allow Screen Recording…")) {
                            ctx.permissions.presentGuide(.screenRecording, reason: L("Picture in Picture shows the contents of your displays."))
                        }
                    }
                }
            } else {
                Text(L("Turn on Displays to start pictures in picture.")).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Configurations

    @ViewBuilder
    private var configurations: some View {
        let config = env.config.value
        let displays = env.runtime.displays
        let connected = Set(displays.map(\.key))
        ForEach(displays) { display in
            Section(display.name) {
                let saved = config.perDisplay[display.key]?.pip.configurations ?? []
                if saved.isEmpty {
                    Text(L("No saved configurations.")).foregroundStyle(.secondary)
                }
                ForEach(saved) { c in row(c) }
                HStack {
                    Button(L("New Picture in Picture")) { add(.display(display.key), kind: .window) }
                        .disabled(saved.count >= PerDisplayPIP.maxConfigurations)
                    Button(L("New Full-Screen Stream")) { add(.display(display.key), kind: .fullScreen) }
                        .disabled(saved.count >= PerDisplayPIP.maxConfigurations || displays.count < 2)
                }
            }
        }
        Section(L("Windows")) {
            let saved = config.pip.windowConfigurations
            Text(L("A window source is picked with the system picker each time it starts, so it can't start from the command line or automatically."))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(saved) { c in row(c) }
            Button(L("New Window Picture in Picture")) { add(.window, kind: .window) }
                .disabled(saved.count >= PIPConfig.maxWindowConfigurations)
        }
        let offline = config.perDisplay.values.keys
            .filter { !connected.contains($0) && !(config.perDisplay[$0]?.pip.configurations.isEmpty ?? true) }
            .sorted { $0.rawValue < $1.rawValue }
        if !offline.isEmpty {
            Section(L("Displays Not Connected")) {
                ForEach(offline, id: \.self) { key in
                    ForEach(config.perDisplay[key]?.pip.configurations ?? []) { c in row(c) }
                }
            }
        }
    }

    private func row(_ c: PIPConfiguration) -> some View {
        PIPConfigurationRow(configuration: c, summary: summary(c), revision: env.runtime.revision(.pip),
                            capture: env.context?.capture, selection: $selection)
    }

    private func summary(_ c: PIPConfiguration) -> String {
        var parts: [String] = []
        if c.kind == .fullScreen {
            let target = c.target.flatMap { key in env.runtime.displays.first { $0.key == key }?.name } ?? L("no target")
            parts.append(L("Full screen on \(target)"))
        } else {
            parts.append(L("Window"))
        }
        parts.append(c.fps == 0 ? L("display rate") : L("\(c.fps) fps"))
        if c.crop != nil { parts.append(L("cropped")) }
        if !c.filters.isEmpty || c.lutID != nil { parts.append(L("filters")) }
        if c.autoStart { parts.append(L("offers to start")) }
        return parts.joined(separator: " · ")
    }

    private func add(_ source: PIPSourceRef, kind: PIPKind) {
        var name = L("Picture in Picture")
        var c = PIPConfiguration(kind: kind)
        switch source {
        case .display(let key):
            let sourceName = env.runtime.displays.first { $0.key == key }?.name ?? L("Display")
            name = kind == .fullScreen ? L("\(sourceName) stream") : L("\(sourceName) PIP")
            if kind == .fullScreen { c.target = env.runtime.displays.first { $0.key != key }?.key }
        case .window:
            name = L("Window PIP")
        }
        c.name = PIPConfiguration.cleanName(name)
        var value = env.config.value
        if PIPConfig.add(c, source: source, to: &value) {
            env.config.value = value
            selection = c.id
        }
    }

    // MARK: LUTs

    @ViewBuilder
    private var luts: some View {
        Section(L("Color Lookup Tables")) {
            if !env.runtime.isEffective(.pipFilters) {
                Text(L("Filters and LUTs are part of the Filters feature.")).foregroundStyle(.secondary)
                Button(L("Turn On Filters")) { env.enableFeature(.pipFilters) }
            } else {
                let list = env.config.value.pip.luts
                if list.isEmpty {
                    Text(L("Import a 3D .cube LUT (2–128 points per axis) to use it in a configuration's filters."))
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { lut in
                    HStack {
                        Text(lut.name)
                        Text("\(lut.size)³").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Delete")) { deleteLUT(lut.id) }
                    }
                }
                HStack {
                    Button(L("Import .cube…")) { importLUT() }
                        .disabled(importing || list.count >= PIPConfig.maxLUTs)
                    if importing { ProgressView().controlSize(.small) }
                }
                if let lutMessage { Text(lutMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = false
        if let type = UTType(filenameExtension: "cube") { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let id = StableID()
        importing = true
        lutMessage = nil
        let config = env.config
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CubeLUT, CubeLUTError> in
                do {
                    return .success(try PIPLUTStore.importFile(atPath: path, id: id))
                } catch let error as CubeLUTError {
                    return .failure(error)
                } catch {
                    return .failure(.unreadable)
                }
            }.value
            importing = false
            switch result {
            case .success(let lut):
                let name = lut.title.isEmpty ? fallbackName : lut.title
                if let ref = PIPLUTReference(id: id, name: name, size: lut.size).sanitized() {
                    config.value.pip.luts.append(ref)
                }
                lutMessage = L("Imported “\(name)”.")
            case .failure(let error):
                lutMessage = error.message
            }
        }
    }

    private func deleteLUT(_ id: StableID) {
        var value = env.config.value
        PIPConfig.removeLUT(id, from: &value)
        env.config.value = value
        env.context?.capture.controller?.forgetLUT(id)
        Task.detached(priority: .utility) { PIPLUTStore.delete(id) }
    }

    // MARK: Privacy

    @ViewBuilder
    private var privacy: some View {
        Section(L("Privacy")) {
            Text(L("Display captures never include Snaptic itself, Notification Center or the apps below. Browser windows marked as private (Firefox, Edge, Chrome's Incognito title) and untitled browser windows are left out too; Safari doesn't mark private windows, so add Safari here if that matters to you."))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(env.config.value.pip.protectedBundlePrefixes, id: \.self) { prefix in
                HStack {
                    Text(prefix).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button(L("Remove")) { env.config.value.pip.protectedBundlePrefixes.removeAll { $0 == prefix } }
                }
            }
            HStack {
                TextField(L("Bundle identifier, e.g. com.example.app"), text: $newPrefix)
                    .onSubmit(addPrefix)
                Button(L("Add"), action: addPrefix)
                    .disabled(!PIPPrivacy.isValidPrefix(newPrefix.trimmingCharacters(in: .whitespaces)))
            }
            Button(L("Restore Defaults")) { env.config.value.pip.protectedBundlePrefixes = PIPPrivacy.defaultProtectedPrefixes }
        }
    }

    private func addPrefix() {
        let entry = newPrefix.trimmingCharacters(in: .whitespaces)
        guard PIPPrivacy.isValidPrefix(entry) else { return }
        var list = env.config.value.pip.protectedBundlePrefixes
        guard !list.contains(entry), list.count < PIPConfig.maxProtectedPrefixes else { return }
        list.append(entry)
        env.config.value.pip.protectedBundlePrefixes = list
        newPrefix = ""
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        Section(L("Options")) {
            Toggle(L("Pause pictures in picture that are covered"), isOn: global(\.pauseWhenOccluded))
            Toggle(L("⌃⌥⌘P stops full-screen streams and turns click-through off"), isOn: global(\.stopHotkeyEnabled))
            Text(L("Panic (⌃⌥⌘⎋) always stops everything. Locking or sleeping the Mac stops all captures and clears their last frame; windows resume after unlock, and streams ask first."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func global<T>(_ path: WritableKeyPath<PIPConfig, T>) -> Binding<T> {
        let config = env.config
        return Binding(get: { config.value.pip[keyPath: path] }, set: { config.value.pip[keyPath: path] = $0 })
    }
}

/// Running sessions with per-session and bulk controls.
/// One saved configuration. Its Start/Stop state is controller state, so the row observes `revision(.pip)`
/// (0.3 §4.5; the page itself observes only the environment).
private struct PIPConfigurationRow: View {
    let configuration: PIPConfiguration
    let summary: String
    @ObservedObject var revision: ControllerRevision
    let capture: CaptureService?
    @Binding var selection: StableID?

    var body: some View {
        let c = configuration
        let running = capture?.sessions.contains { $0.id == c.id } ?? false
        let controller = capture?.controller
        HStack {
            Image(systemName: c.kind == .fullScreen ? "rectangle.on.rectangle" : "pip")
                .foregroundStyle(running ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading) {
                Text(c.name)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(running ? L("Stop") : L("Start")) {
                if running { controller?.endSession(c.id, reason: nil) } else { controller?.userStart(c.id) }
            }
            .disabled(controller == nil)
            Button(selection == c.id ? L("Done") : L("Edit")) { selection = selection == c.id ? nil : c.id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(c.name)
    }
}

private struct PIPRunningSection: View {
    @ObservedObject var capture: CaptureService

    var body: some View {
        Section(L("Running")) {
            let sessions = capture.sessions
            if sessions.isEmpty {
                Text(L("Nothing is running.")).foregroundStyle(.secondary)
            }
            ForEach(sessions) { info in
                HStack {
                    Image(systemName: info.kind == .fullScreen ? "rectangle.on.rectangle" : "pip")
                    VStack(alignment: .leading) {
                        Text(info.name)
                        Text(info.state.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if info.kind == .window {
                        Button(info.state == .paused ? L("Resume") : L("Pause")) {
                            capture.controller?.setPaused(info.id, info.state != .paused)
                        }
                        Button(info.state == .hidden ? L("Show") : L("Hide")) {
                            capture.controller?.setHidden(info.id, info.state != .hidden)
                        }
                        Button(L("Crop…")) { capture.controller?.beginCrop(info.id) }
                    }
                    Button(L("Stop")) { capture.controller?.endSession(info.id, reason: nil) }
                }
            }
            if !sessions.isEmpty {
                HStack {
                    Button(L("Stop All")) { capture.controller?.stopAll() }
                    let hidden = capture.controller?.allHidden ?? false
                    Button(hidden ? L("Show All") : L("Hide All")) { capture.controller?.setAllHidden(!hidden) }
                    let paused = capture.controller?.allPaused ?? false
                    Button(paused ? L("Resume All") : L("Pause All")) { capture.controller?.setAllPaused(!paused) }
                }
            }
        }
    }
}

/// "Draw Crop on the Window…", enabled while that PIP's window is up (controller state: observes `revision(.pip)`).
private struct PIPDrawCropButton: View {
    let id: StableID
    @ObservedObject var revision: ControllerRevision
    let capture: CaptureService?

    var body: some View {
        let running = capture?.sessions.contains { $0.id == id && $0.kind == .window } ?? false
        Button(L("Draw Crop on the Window…")) { capture?.controller?.beginCrop(id) }
            .disabled(!running)
    }
}

/// Edits one saved configuration in place.
private struct PIPConfigurationEditor: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let id: StableID
    let onDelete: () -> Void
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var entry: PIPEntry? { PIPConfig.entry(id, in: env.config.value) }
    private var c: PIPConfiguration { entry?.configuration ?? PIPConfiguration() }
    private var isDisplaySource: Bool {
        if case .display = entry?.source { return true }
        return false
    }

    var body: some View {
        Section(L("Edit “\(c.name)”")) {
            TextField(L("Name"), text: $name)
                .focused($nameFocused)
                .onSubmit(commitName)
                .onChange(of: nameFocused) { focused in if !focused { commitName() } }
            Picker(L("Show as"), selection: field(\.kind, .window)) {
                Text(L("Floating window")).tag(PIPKind.window)
                Text(L("Full-screen stream")).tag(PIPKind.fullScreen)
            }
            if c.kind == .fullScreen {
                Picker(L("Stream onto"), selection: field(\.target, nil)) {
                    Text(L("Choose…")).tag(DisplayKey?.none)
                    ForEach(targets) { d in Text(d.name).tag(DisplayKey?.some(d.key)) }
                }
            }
            if isDisplaySource {
                Toggle(L("Offer to start when the source display connects"), isOn: field(\.autoStart, false))
                Text(L("Snaptic asks with a notice; it never starts a capture by itself, and never in Safe Mode."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Delete Configuration"), role: .destructive) {
                    env.context?.capture.controller?.endSession(id, reason: nil)
                    var value = env.config.value
                    PIPConfig.remove(id, from: &value)
                    env.config.value = value
                    onDelete()
                }
            }
        }
        .onAppear { name = c.name }
        .onChange(of: id) { _ in name = c.name }

        if c.kind == .window { windowSection }
        captureSection
        geometrySection
        if c.kind == .fullScreen { fullScreenSection }
        filtersSection
    }

    private var targets: [DisplayInfo] {
        var source: DisplayKey?
        if case .display(let key) = entry?.source { source = key }
        return env.runtime.displays.filter { $0.key != source }
    }

    private func commitName() {
        let cleaned = PIPConfiguration.cleanName(name)
        name = cleaned
        guard cleaned != c.name else { return }
        update { $0.name = cleaned }
    }

    // MARK: Sections

    private var windowSection: some View {
        Section(L("Window")) {
            Picker(L("Level"), selection: field(\.level, .floating)) {
                Text(L("Normal")).tag(PIPLevel.normal)
                Text(L("Floating")).tag(PIPLevel.floating)
                Text(L("Above everything")).tag(PIPLevel.aboveAll)
            }
            LabeledContent(L("Opacity")) {
                Slider(value: field(\.opacity, 1), in: PIPConfiguration.opacityRange)
                    .frame(maxWidth: 220)
                    .accessibilityValue("\(Int(c.opacity * 100))%")
                Text("\(Int(c.opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Toggle(L("Click through (⌃⌥⌘P turns it off)"), isOn: field(\.clickThrough, false))
            Toggle(L("Lock position"), isOn: field(\.lockPosition, false))
            Toggle(L("Keep the source's aspect ratio"), isOn: field(\.lockAspect, true))
            Toggle(L("Sharp pixels (integer scaling)"), isOn: field(\.integerScaling, false))
            Toggle(L("Title bar"), isOn: field(\.showTitleBar, true))
            Toggle(L("Snap size to 25% steps"), isOn: field(\.snapToQuarters, false))
            Toggle(L("Shadow"), isOn: field(\.shadow, true))
            Button(L("Reset Window Position")) { update { $0.windowFrame = nil } }
                .disabled(c.windowFrame == nil)
        }
    }

    private var captureSection: some View {
        Section(L("Capture")) {
            Toggle(L("Match the source display's refresh rate"), isOn: Binding(
                get: { c.fps == 0 },
                set: { on in update { $0.fps = on ? 0 : 30 } }))
            if c.fps != 0 {
                LabeledContent(L("Frame rate")) {
                    Slider(value: Binding(get: { Double(c.fps) }, set: { v in update { $0.fps = Int(v.rounded()) } }),
                           in: 1...120, step: 1)
                        .frame(maxWidth: 220)
                        .accessibilityValue("\(c.fps)")
                    Text("\(c.fps) fps").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
            }
            Toggle(L("Show the pointer"), isOn: field(\.showCursor, true))
            if isDisplaySource {
                Toggle(L("⌘-click moves the pointer to that spot on the source"), isOn: field(\.warpOnCommandClick, true))
            }
            LabeledContent(L("Crop")) {
                if let crop = c.crop {
                    Text(L("\(Int(crop.width * 100))% × \(Int(crop.height * 100))% at \(Int(crop.x * 100))%, \(Int(crop.y * 100))%"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("None")).foregroundStyle(.secondary)
                }
            }
            HStack {
                PIPDrawCropButton(id: id, revision: env.runtime.revision(.pip), capture: env.context?.capture)
                Button(L("Reset Crop")) { update { $0.crop = nil } }
                    .disabled(c.crop == nil)
            }
            Text(L("Start the picture in picture, then drag a rectangle over the part you want."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var geometrySection: some View {
        Section(L("Orientation")) {
            Picker(L("Rotate"), selection: field(\.rotation, 0)) {
                Text("0°").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            Toggle(L("Flip horizontally"), isOn: field(\.flipHorizontal, false))
            Toggle(L("Flip vertically (teleprompter)"), isOn: field(\.flipVertical, false))
        }
    }

    private var fullScreenSection: some View {
        Section(L("Full Screen")) {
            Picker(L("Scaling"), selection: field(\.scaling, .fit)) {
                Text(L("Fit")).tag(PIPScaling.fit)
                Text(L("Fill")).tag(PIPScaling.fill)
                Text(L("1:1 pixels")).tag(PIPScaling.oneToOne)
                Text(L("Integer multiple")).tag(PIPScaling.integer)
            }
            LabeledContent(L("Size")) {
                Slider(value: Binding(get: { Double(c.underscanPercent) }, set: { v in update { $0.underscanPercent = Int(v.rounded()) } }),
                       in: 10...200, step: 5)
                    .frame(maxWidth: 220)
                    .accessibilityValue("\(c.underscanPercent)%")
                Text("\(c.underscanPercent)%").monospacedDigit().frame(width: 50, alignment: .trailing)
            }
            Toggle(L("Switch the target to its native mode while streaming"), isOn: field(\.nativeModeWhileStreaming, false))
            Text(L("Asks you to keep the new mode, and restores the previous one when the stream stops. Needs the Resolution feature. Streams onto the only display you can see are refused; ⌃⌥⌘P or panic stops a stream."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var filtersSection: some View {
        Section(L("Filters")) {
            if !env.runtime.isEffective(.pipFilters) {
                Text(L("Filters need the Filters feature.")).foregroundStyle(.secondary)
                Button(L("Turn On Filters")) { env.enableFeature(.pipFilters) }
            } else {
                Picker(L("LUT"), selection: field(\.lutID, nil)) {
                    Text(L("None")).tag(StableID?.none)
                    ForEach(env.config.value.pip.luts) { lut in Text(lut.name).tag(StableID?.some(lut.id)) }
                }
                if c.filters.isEmpty {
                    Text(L("No filters.")).foregroundStyle(.secondary)
                }
                ForEach(Array(c.filters.enumerated()), id: \.offset) { index, filter in
                    filterRow(index, filter)
                }
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
                .disabled(c.filters.count >= PIPConfiguration.maxFilters)
            }
        }
    }

    private func filterRow(_ index: Int, _ filter: FilterInstance) -> some View {
        let descriptor = FilterSpec.descriptor(filter.kind)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(descriptor.title, isOn: Binding(
                    get: { c.filters.indices.contains(index) ? c.filters[index].enabled : false },
                    set: { on in update { if $0.filters.indices.contains(index) { $0.filters[index].enabled = on } } }))
                Spacer()
                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .accessibilityLabel(L("Move up"))
                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == c.filters.count - 1)
                    .accessibilityLabel(L("Move down"))
                Button { update { if $0.filters.indices.contains(index) { $0.filters.remove(at: index) } } } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L("Remove \(descriptor.title)"))
            }
            ForEach(descriptor.parameters, id: \.key) { p in
                LabeledContent(p.title) {
                    Slider(value: Binding(
                        get: { c.filters.indices.contains(index) ? c.filters[index].value(p.key) : p.defaultValue },
                        set: { v in update { if $0.filters.indices.contains(index) { $0.filters[index].values[p.key] = v } } }),
                           in: p.min...p.max)
                        .frame(maxWidth: 220)
                        .accessibilityValue(format(filter.value(p.key), p.unit))
                    Text(format(filter.value(p.key), p.unit)).monospacedDigit().font(.caption).frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    private func format(_ value: Double, _ unit: FilterUnit) -> String {
        switch unit {
        case .degrees: return "\(Int(value.rounded()))°"
        case .kelvin: return "\(Int(value.rounded())) K"
        case .pixels: return String(format: "%.1f px", value)
        case .ev: return String(format: "%+.2f EV", value)
        case .none: return String(format: "%.2f", value)
        }
    }

    private func move(_ index: Int, by offset: Int) {
        update {
            let target = index + offset
            guard $0.filters.indices.contains(index), $0.filters.indices.contains(target) else { return }
            $0.filters.swapAt(index, target)
        }
    }

    // MARK: Bindings

    private func update(_ body: (inout PIPConfiguration) -> Void) {
        var value = env.config.value
        guard PIPConfig.update(id, in: &value, body) else { return }
        env.config.value = value
    }

    private func field<T>(_ path: WritableKeyPath<PIPConfiguration, T>, _ fallback: T) -> Binding<T> {
        let config = env.config
        let id = self.id
        return Binding(
            get: { PIPConfig.entry(id, in: config.value)?.configuration[keyPath: path] ?? fallback },
            set: { newValue in
                var value = config.value
                guard PIPConfig.update(id, in: &value, { $0[keyPath: path] = newValue }) else { return }
                config.value = value
            })
    }
}
