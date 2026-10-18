import SwiftUI
import SnapticKit

/// What the virtual display sheet shows.
enum VirtualEditorTarget: Hashable {
    /// New Virtual Display…: a shape or a recipe.
    case new
    /// Details… for one virtual display.
    case edit(StableID)
}

/// **New Virtual Display…** and a virtual display's **Details…** (owner D; PLAN 0.3 §4.3 Virtual Displays: "the
/// Details sheet replaces the inline editor, Sizes becomes a table with + / −"). New: a shape pop-up and the recipes
/// as tiles. Details: name, aspect ratio, diagonal, HiDPI, portrait, reconnect at launch, HDR modes (with the
/// Experimental `hdrVirtual`), refresh rate, the sizes table, the linked displays, and Delete… (a standard alert).
/// Edits are a draft that Done applies (a connected display reconnects when its shape changed).
struct VirtualDisplayEditorSheet: View, ControlDeclaring {
    typealias Controls = VirtualDisplayEditorSheetControls

    private let env: DisplaysPageEnvironment?
    private let target: VirtualEditorTarget?

    /// The first virtual display's details (or New Virtual Display… when there is none).
    init() {
        env = DisplaysSettingsLookup.environment()
        target = nil
    }

    init(env: DisplaysPageEnvironment, target: VirtualEditorTarget) {
        self.env = env
        self.target = target
    }

    var body: some View {
        if let env {
            let resolved: VirtualEditorTarget = target
                ?? env.config.value.virtualScreens.screens.first.map { VirtualEditorTarget.edit($0.id) }
                ?? VirtualEditorTarget.new
            switch resolved {
            case .new:
                NewVirtualDisplayContent(env: env)
            case .edit(let id):
                VirtualDisplayDetailsContent(env: env, id: id)
            }
        } else {
            AdvancedSheet(L("Virtual Display"), restoreDefaults: nil) {
                Section {
                    StatusRow(L("Turn on Displays to use virtual displays."))
                }
            }
        }
    }
}

// MARK: - New Virtual Display…

private struct NewVirtualDisplayContent: View {
    typealias Controls = VirtualDisplayEditorSheetControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var virtual: ConfigSlice<DisplaysConfig, VirtualConfig>
    @Environment(\.dismiss) private var dismiss
    @State private var presetIndex = 0
    @State private var teleprompterTarget: DisplayKey?

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _virtual = StateObject(wrappedValue: ConfigSlice(env.config, \.virtualScreens))
    }

    private var full: Bool { virtual.value.screens.count >= VirtualConfig.maxScreens }
    private var controller: VirtualController? { env.context?.connectPlanner.virtual }

    var body: some View {
        AdvancedSheet(L("New Virtual Display"), restoreDefaults: nil) {
            if full {
                Section {
                    StatusRow(L("You have \(VirtualConfig.maxScreens) virtual displays, the most Snaptic can make. Delete one to make another."),
                              style: .warning)
                }
            }
            Section {
                PickerSetting(L("Shape"),
                              help: L("A desktop with this aspect ratio and the usual sizes for it."),
                              selection: $presetIndex,
                              options: Recipes.presets.indices.map { PickerOption($0, Recipes.presets[$0].title) },
                              style: .popUp, defaultValue: nil,
                              anchor: ControlID("displays.virtual.editor.shape"))
                ButtonRow(L("Create Virtual Display"), control: ControlID("displays.virtual.editor.create")) {
                    let preset = Recipes.presets[min(max(0, presetIndex), Recipes.presets.count - 1)]
                    if controller?.add(Recipes.spec(preset: preset, soc: ManagedHardware.soc)) == true { dismiss() }
                }
                .disabled(full || controller == nil)
            }
            Section {
                ForEach(RecipeKind.allCases, id: \.self) { kind in
                    recipeTile(kind)
                        .modifier(OptionalSettingsAnchor(kind == RecipeKind.allCases.first
                            ? ControlID("displays.virtual.editor.recipes") : nil))
                }
            } header: {
                Text(L("Recipes"))
            }
        }
    }

    private func recipeTile(_ kind: RecipeKind) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIcon(symbol(kind), tint: .teal, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if kind == .teleprompter {
                    Picker(L("Stream onto"), selection: $teleprompterTarget) {
                        Text(L("Choose a Display")).tag(DisplayKey?.none)
                        ForEach(runtime.displays.filter { $0.isActive && $0.transport != .snapticVirtual }, id: \.key) {
                            Text($0.name).tag(Optional($0.key))
                        }
                    }
                    .frame(maxWidth: 260)
                }
            }
            Spacer(minLength: 8)
            Button(L("Create")) {
                controller?.addRecipe(kind, target: kind == .teleprompter ? teleprompterTarget : nil)
                dismiss()
            }
            .disabled(full || controller == nil || (kind == .teleprompter && teleprompterTarget == nil))
            .accessibilityLabel(L("Create \(kind.title) display"))
        }
    }

    private func symbol(_ kind: RecipeKind) -> String {
        switch kind {
        case .headless: return "macmini"
        case .recording: return "record.circle"
        case .teleprompter: return "text.alignleft"
        case .portrait: return "rectangle.portrait"
        }
    }
}

// MARK: - Details…

private struct VirtualDisplayDetailsContent: View {
    typealias Controls = VirtualDisplayEditorSheetControls

    let env: DisplaysPageEnvironment
    let id: StableID
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var virtual: ConfigSlice<DisplaysConfig, VirtualConfig>
    /// The edits, loaded when the sheet appears (no `State(initialValue:)` copies, L7).
    @State private var draft: VirtualScreenSpec?
    @State private var newWidth: Double = 1920
    @State private var newHeight: Double = 1080
    @State private var newLink: DisplayKey?

    init(env: DisplaysPageEnvironment, id: StableID) {
        self.env = env
        self.id = id
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _virtual = StateObject(wrappedValue: ConfigSlice(env.config, \.virtualScreens))
    }

    private var stored: VirtualScreenSpec? { virtual.value.screen(id) }
    private var controller: VirtualController? { env.context?.connectPlanner.virtual }

    var body: some View {
        AdvancedSheet(stored?.name ?? L("Virtual Display"), restoreDefaults: deleteButton,
                      restoreControl: ControlID("displays.virtual.editor.delete")) {
            if draft != nil, stored != nil {
                form
            } else if stored == nil {
                Section {
                    StatusRow(L("This virtual display isn’t there anymore."))
                }
            }
        }
        .onAppear { if draft == nil { draft = stored } }
        .onDisappear { save() }
    }

    /// The sheet's leading footer button: Delete… with its confirmation.
    private var deleteButton: RestoreDefaults? {
        guard let stored, let controller else { return nil }
        let id = id
        return RestoreDefaults(title: L("Delete…"), question: L("Delete “\(stored.name)”?"),
                               message: L("It disconnects, and its sizes and linked displays are deleted."),
                               button: L("Delete"), destructive: true) {
            controller.remove(id)
        }
    }

    /// A binding into the draft.
    private func field<V>(_ path: WritableKeyPath<VirtualScreenSpec, V>, fallback: V) -> Binding<V> {
        Binding(get: { draft?[keyPath: path] ?? fallback }, set: { value in draft?[keyPath: path] = value })
    }

    @ViewBuilder private var form: some View {
        if let spec = draft {
            Section {
                SettingRow(L("Name"), anchor: ControlID("displays.virtual.editor.name")) {
                    TextField(L("Name"), text: field(\.name, fallback: ""))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(maxWidth: 240)
                }
                SettingRow(L("Aspect ratio"), help: L("Width to height, such as 16:10."),
                           anchor: ControlID("displays.virtual.editor.aspect")) {
                    HStack(spacing: 4) {
                        NumberField(L("Aspect width"), value: intField(\.aspectWidth),
                                    in: 1...Double(VirtualScreenSpec.maxAspectComponent), step: 1, format: .plain(digits: 0))
                        Text(verbatim: ":").accessibilityHidden(true)
                        NumberField(L("Aspect height"), value: intField(\.aspectHeight),
                                    in: 1...Double(VirtualScreenSpec.maxAspectComponent), step: 1, format: .plain(digits: 0))
                    }
                }
                SettingRow(L("Diagonal"), help: L("The size macOS assumes, in inches; it sets how large text looks."),
                           anchor: ControlID("displays.virtual.editor.diagonal")) {
                    HStack(spacing: 4) {
                        NumberField(L("Diagonal in inches"), value: field(\.sizeInches, fallback: 27),
                                    in: VirtualScreenSpec.minSizeInches...VirtualScreenSpec.maxSizeInches, step: 0.1,
                                    format: .plain(digits: 1))
                        Text(L("in")).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                ToggleSetting(L("HiDPI"), help: L("Draws text and images at twice the detail, like a Retina display."),
                              isOn: Binding(get: { draft?.hiDPI ?? true }, set: { on in
                                  if let d = draft { draft = VirtualSpecEdit.settingHiDPI(d, on) }
                              }),
                              anchor: ControlID("displays.virtual.editor.hiDPI"))
                ToggleSetting(L("Portrait"), help: L("Taller than wide."),
                              isOn: field(\.portrait, fallback: false),
                              anchor: ControlID("displays.virtual.editor.portrait"))
                ToggleSetting(L("Connect when Snaptic opens"),
                              help: L("Brings this display back after Snaptic or your Mac restarts."),
                              isOn: field(\.recreateOnLaunch, fallback: false),
                              anchor: ControlID("displays.virtual.editor.reconnect"))
                if runtime.isEffective(.hdrVirtual) {
                    ToggleSetting(L("HDR modes"), help: L("Offers HDR (PQ) modes on this display."),
                                  isOn: field(\.hdr, fallback: false),
                                  anchor: ControlID("displays.virtual.editor.hdr"), badge: .experimental)
                }
                PickerSetting(L("Refresh rate"),
                              selection: Binding(get: { VirtualSpecEdit.refreshMilliHz(draft ?? spec) }, set: { hz in
                                  if let d = draft { draft = VirtualSpecEdit.settingRefresh(d, milliHz: hz) }
                              }),
                              options: VirtualSpecEdit.refreshOptions(spec).map {
                                  PickerOption($0, SettingsFormat.text(Double($0) / 1000, .hertz))
                              },
                              style: .popUp, defaultValue: VirtualSpecEdit.defaultRefreshMilliHz,
                              anchor: ControlID("displays.virtual.editor.refresh"))
            }
            sizesSection(spec)
            linksSection(spec)
        }
    }

    private func intField(_ path: WritableKeyPath<VirtualScreenSpec, Int>) -> Binding<Double> {
        Binding(get: { Double(draft?[keyPath: path] ?? 1) }, set: { value in
            guard value.isFinite else { return }
            draft?[keyPath: path] = Int(min(Double(VirtualScreenSpec.maxAspectComponent), max(1, value.rounded())))
        })
    }

    // MARK: Sizes (a table with + / −)

    private func sizesSection(_ spec: VirtualScreenSpec) -> some View {
        Section {
            ForEach(Array(spec.modes.enumerated()), id: \.offset) { index, mode in
                LabeledContent {
                    Button {
                        if let d = draft { draft = VirtualSpecEdit.removingSize(d, at: index) }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(spec.modes.count <= 1)
                    .help(L("Remove This Size"))
                    .accessibilityLabel(L("Remove \(mode.width) × \(mode.height)"))
                } label: {
                    Text(verbatim: "\(mode.width) × \(mode.height)")
                    if index == 0 { Text(L("Used when it connects")) }
                }
                .modifier(OptionalSettingsAnchor(index == 0 ? ControlID("displays.virtual.editor.sizes") : nil))
            }
            HStack(spacing: 4) {
                NumberField(L("New width"), value: $newWidth, in: Double(VirtualScreenSpec.minModeDimension)...16384, step: 2,
                            format: .points)
                Text(verbatim: "×").accessibilityHidden(true)
                NumberField(L("New height"), value: $newHeight, in: Double(VirtualScreenSpec.minModeDimension)...16384,
                            step: 2, format: .points)
                Spacer(minLength: 8)
                Button {
                    // The size being typed is written first: the click leaves the field focused (review round 3 ui F1).
                    FocusedField.commit()
                    if let d = draft { draft = VirtualSpecEdit.addingSize(d, width: Int(newWidth), height: Int(newHeight)) }
                } label: {
                    Image(systemName: "plus")
                }
                .help(L("Add This Size"))
                .accessibilityLabel(L("Add size"))
                .modifier(SettingsAnchor(ControlID("displays.virtual.editor.addSize")))
            }
            ButtonRow(L("Fill Sizes"), help: L("Replaces the list with the usual sizes for this shape."),
                      control: ControlID("displays.virtual.editor.fillSizes")) {
                if let d = draft { draft = VirtualSpecEdit.fillingSizes(d, soc: ManagedHardware.soc) }
            }
        } header: {
            Text(L("Sizes"))
        } footer: {
            Text(L("In points. The first size is used when the display connects."))
        }
    }

    // MARK: Linked displays (associations)

    private func linksSection(_ spec: VirtualScreenSpec) -> some View {
        Section {
            ForEach(Array(spec.associations.enumerated()), id: \.offset) { index, link in
                linkRows(index, link: link)
            }
            let candidates = runtime.displays.filter { d in
                d.transport != .snapticVirtual && !spec.associations.contains { $0.target == d.key }
            }
            if !candidates.isEmpty {
                HStack(spacing: 8) {
                    Picker(L("Link a display"), selection: $newLink) {
                        Text(L("Choose a Display")).tag(DisplayKey?.none)
                        ForEach(candidates, id: \.key) { Text($0.name).tag(Optional($0.key)) }
                    }
                    Button(L("Link")) {
                        if let key = newLink { draft?.associations.append(VirtualAssociation(target: key)) }
                        newLink = nil
                    }
                    .disabled(newLink == nil)
                }
                .modifier(SettingsAnchor(ControlID("displays.virtual.editor.addLink")))
            }
        } header: {
            Text(L("Linked displays"))
        } footer: {
            Text(L("Connects this virtual display when another one connects or disconnects, and can show it there. Mirroring and streams always ask first."))
        }
    }

    @ViewBuilder private func linkRows(_ index: Int, link: VirtualAssociation) -> some View {
        let name = DisplaysSettingsLookup.name(link.target, env: env)
        LabeledContent {
            Button {
                if draft?.associations.indices.contains(index) == true { draft?.associations.remove(at: index) }
            } label: {
                Image(systemName: "minus")
            }
            .help(L("Unlink"))
            .accessibilityLabel(L("Unlink \(name)"))
        } label: {
            Text(name)
        }
        .modifier(OptionalSettingsAnchor(index == 0 ? ControlID("displays.virtual.editor.links") : nil))
        PickerSetting(L("Connect"),
                      selection: linkField(index, \.autoConnect, fallback: VirtualAutoConnect.never),
                      options: [
                          PickerOption(VirtualAutoConnect.never, L("Only when I choose")),
                          PickerOption(VirtualAutoConnect.whilePresent, L("While \(name) is connected")),
                          PickerOption(VirtualAutoConnect.whileAbsent, L("While \(name) isn’t connected")),
                      ],
                      style: .popUp, defaultValue: nil, subordinate: true)
        PickerSetting(L("Show it on \(name)"),
                      selection: linkField(index, \.presentation, fallback: VirtualPresentation.none),
                      options: [
                          PickerOption(VirtualPresentation.none, L("Don’t Show")),
                          PickerOption(VirtualPresentation.mirror, L("Mirror")),
                          PickerOption(VirtualPresentation.stream, L("Stream")),
                          PickerOption(VirtualPresentation.flippedStream, L("Stream Flipped")),
                      ],
                      style: .popUp, defaultValue: nil, subordinate: true)
    }

    private func linkField<V>(_ index: Int, _ path: WritableKeyPath<VirtualAssociation, V>, fallback: V) -> Binding<V> {
        Binding(get: {
            guard let d = draft, d.associations.indices.contains(index) else { return fallback }
            return d.associations[index][keyPath: path]
        }, set: { value in
            guard draft?.associations.indices.contains(index) == true else { return }
            draft?.associations[index][keyPath: path] = value
        })
    }

    /// Done (or closing the sheet) applies the edits; a connected display reconnects when its shape changed.
    private func save() {
        // Done already committed; this covers the sheet closing another way with a field still being typed in.
        FocusedField.commit()
        guard let draft, let controller, let stored, draft != stored else { return }
        controller.update(draft)
    }
}
