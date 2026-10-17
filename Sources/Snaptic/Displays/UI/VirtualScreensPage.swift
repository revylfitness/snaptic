import SwiftUI
import SnapticKit

/// Virtual Screens & HiDPI (PLAN §9.2–§9.5): create from presets or recipes, edit,
/// connect, associations, bulk actions, behavior, Smart HiDPI.
struct VirtualScreensPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var presetIndex = 0
    @State private var teleprompterTarget: DisplayKey?
    @State private var editing: VirtualScreenSpec?
    @State private var confirmDiscard = false

    private var controller: VirtualController? { env.context?.connectPlanner.virtual }
    private var screens: [VirtualScreenSpec] { env.config.value.virtualScreens.screens }
    private var physical: [DisplayInfo] {
        env.runtime.displays.filter { $0.transport == .builtin || $0.transport == .wired || $0.isSmartHiDPIPair }
    }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            screensSection
            if env.runtime.isEffective(.virtualScreens), let c = controller {
                createSection(c)
                bulkSection(c)
                behaviorSection
            }
            SmartHiDPISection(env: env, displays: physical)
        }
        .formStyle(.grouped)
        .sheet(item: Binding(get: { editing.map(EditingBox.init) }, set: { editing = $0?.spec })) { box in
            VirtualScreenEditor(env: env, draft: box.spec) { saved in
                controller?.update(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
        .confirmationDialog(L("Discard all virtual screens?"), isPresented: $confirmDiscard) {
            Button(L("Discard All"), role: .destructive) { controller?.discardAll() }
        }
    }

    @ViewBuilder private var screensSection: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .virtualScreens, title: L("Virtual screens"))
            if env.context == nil {
                ManagementOffNotice()
            } else if screens.isEmpty {
                Text(L("No virtual screens yet.")).foregroundStyle(.secondary)
            }
            ForEach(Array(screens.enumerated()), id: \.element.id) { index, s in
                VirtualScreenRow(env: env, spec: s, index: index, onEdit: { editing = s })
            }
            if let ctx = env.context {
                let used = ctx.virtualHosts.totalBackingBytes
                let budget = SoCCaps.maxBackingBytes(ram: ManagedHardware.ram)
                ManagementNote(L("Graphics memory for virtual screens: \(ManagementText.bytes(used)) of \(ManagementText.bytes(budget)). Each screen runs a small helper process."))
            }
        } header: {
            Text(L("Virtual screens"))
        }
    }

    private func createSection(_ c: VirtualController) -> some View {
        Section {
            HStack {
                Picker(L("Shape"), selection: $presetIndex) {
                    ForEach(Array(Recipes.presets.enumerated()), id: \.offset) { i, p in Text(p.title).tag(i) }
                }
                Button(L("Create")) {
                    let preset = Recipes.presets[min(max(0, presetIndex), Recipes.presets.count - 1)]
                    _ = c.add(Recipes.spec(preset: preset, soc: ManagedHardware.soc))
                }
                .disabled(screens.count >= VirtualConfig.maxScreens)
            }
            ForEach(RecipeKind.allCases, id: \.self) { kind in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        ManagementNote(kind.summary)
                    }
                    Spacer()
                    if kind == .teleprompter {
                        Picker(L("Onto"), selection: $teleprompterTarget) {
                            Text(L("Choose…")).tag(DisplayKey?.none)
                            ForEach(env.runtime.displays, id: \.key) { d in Text(d.name).tag(Optional(d.key)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    }
                    Button(L("Create")) { c.addRecipe(kind, target: kind == .teleprompter ? teleprompterTarget : nil) }
                        .disabled(screens.count >= VirtualConfig.maxScreens)
                        .accessibilityLabel(L("Create \(kind.title) screen"))
                }
            }
        } header: {
            Text(L("New virtual screen"))
        } footer: {
            ManagementNote(L("Up to \(VirtualConfig.maxScreens) virtual screens."))
        }
    }

    private func bulkSection(_ c: VirtualController) -> some View {
        Section(L("All virtual screens")) {
            HStack {
                Button(L("Connect All")) { c.connectAll() }
                Button(L("Disconnect All")) { c.disconnectAll() }
                Button(L("Reconnect All")) { c.reconnectAll() }
                Button(L("Disassociate All")) { c.disassociateAll() }
                Spacer()
                Button(L("Discard All…"), role: .destructive) { confirmDiscard = true }
            }
            .disabled(screens.isEmpty)
        }
    }

    private var behaviorSection: some View {
        Section(L("Behavior")) {
            Toggle(L("Restore the arrangement after a virtual screen connects"),
                   isOn: ManagementBindings.config(env, \.virtualScreens.restoreLayoutAfterConnect))
            Toggle(L("Reconnect virtual screens after wake"), isOn: ManagementBindings.config(env, \.virtualScreens.reconnectAfterWake))
            Toggle(L("Disconnect on lock and reconnect on return"), isOn: ManagementBindings.config(env, \.virtualScreens.disconnectOnLock))
        }
    }
}

/// `sheet(item:)` needs Identifiable.
private struct EditingBox: Identifiable {
    let spec: VirtualScreenSpec
    var id: String { spec.id.rawValue }
}

private struct VirtualScreenRow: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let spec: VirtualScreenSpec
    let index: Int
    let onEdit: () -> Void

    var body: some View {
        let c = env.context?.connectPlanner.virtual
        let live = c?.isLive(spec.id) ?? false
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name)
                ManagementNote(summary)
            }
            Spacer()
            Toggle(L("Connected"), isOn: Binding(get: { live }, set: { _ in c?.toggle(spec.id) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(c == nil || c?.isBusy(spec.id) == true)
                .accessibilityLabel(L("Connect \(spec.name)"))
            Button(L("Edit…"), action: onEdit)
            Button(L("Delete"), role: .destructive) { c?.remove(spec.id) }
                .accessibilityLabel(L("Delete \(spec.name)"))
        }
    }

    private var summary: String {
        var parts = ["\(spec.aspectWidth):\(spec.aspectHeight)", String(format: "%.1f\"", spec.sizeInches),
                     spec.hiDPI ? "HiDPI" : L("Standard"), L("\(spec.modes.count) sizes")]
        if spec.headlessPrimary { parts.append(L("Headless")) }
        if spec.recreateOnLaunch { parts.append(L("Reconnects at launch")) }
        if !spec.associations.isEmpty { parts.append(L("\(spec.associations.count) association(s)")) }
        if index < 8 { parts.append(L("Action \(index + 1)")) }
        return parts.joined(separator: " · ")
    }
}

/// Editing a copy; Save replaces the spec (a live screen reconnects if its shape changed).
private struct VirtualScreenEditor: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State var draft: VirtualScreenSpec
    @State private var sizesText = ""
    @State private var refreshHz = 60.0
    let onSave: (VirtualScreenSpec) -> Void
    let onCancel: () -> Void

    init(env: DisplaysPageEnvironment, draft: VirtualScreenSpec, onSave: @escaping (VirtualScreenSpec) -> Void,
         onCancel: @escaping () -> Void) {
        _env = ObservedObject(wrappedValue: env)
        _draft = State(initialValue: draft)
        _sizesText = State(initialValue: draft.modes.map { "\($0.width)x\($0.height)" }.joined(separator: "\n"))
        _refreshHz = State(initialValue: draft.modes.first.map { Double($0.refreshMilliHz) / 1000 } ?? 60)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Edit Virtual Screen")).font(.headline)
            Form {
                TextField(L("Name"), text: $draft.name)
                HStack {
                    Text(L("Aspect ratio"))
                    TextField(L("Width"), value: $draft.aspectWidth, format: .number).frame(width: 60)
                    Text(":")
                    TextField(L("Height"), value: $draft.aspectHeight, format: .number).frame(width: 60)
                    Button(L("Fill Sizes")) {
                        let ladder = VirtualScreenSpec.ladder(aspectWidth: draft.aspectWidth, aspectHeight: draft.aspectHeight,
                                                              hiDPI: draft.hiDPI, soc: ManagedHardware.soc, portrait: draft.portrait)
                        sizesText = ladder.map { "\($0.width)x\($0.height)" }.joined(separator: "\n")
                    }
                }
                HStack {
                    Text(L("Diagonal (inches)"))
                    TextField(L("Inches"), value: $draft.sizeInches, format: .number).frame(width: 70)
                }
                Toggle(L("HiDPI"), isOn: $draft.hiDPI)
                Toggle(L("Portrait"), isOn: $draft.portrait)
                Toggle(L("Reconnect at launch"), isOn: $draft.recreateOnLaunch)
                if env.runtime.isEffective(.hdrVirtual) { Toggle(L("HDR modes"), isOn: $draft.hdr) }
                HStack {
                    Text(L("Refresh rate (Hz)"))
                    TextField(L("Hz"), value: $refreshHz, format: .number).frame(width: 60)
                }
                VStack(alignment: .leading) {
                    Text(L("Sizes in points, one per line (the first is used when connecting)"))
                    TextEditor(text: $sizesText).font(.body.monospaced()).frame(minHeight: 100)
                }
                AssociationsEditor(env: env, associations: $draft.associations)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Save")) { onSave(finished()) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
    }

    private func finished() -> VirtualScreenSpec {
        var s = draft
        let hz = Int(((refreshHz.isFinite ? refreshHz : 60) * 1000).rounded())
        var modes: [VirtualMode] = []
        for line in sizesText.split(whereSeparator: \.isNewline) {
            let parts = line.lowercased().split(whereSeparator: { $0 == "x" || $0 == "×" || $0 == " " }).compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            modes.append(VirtualMode(width: parts[0], height: parts[1], hiDPI: s.hiDPI, refreshMilliHz: hz))
        }
        s.modes = modes
        return s.sanitized(soc: ManagedHardware.soc)
    }
}

private struct AssociationsEditor: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @Binding var associations: [VirtualAssociation]
    @State private var newTarget: DisplayKey?

    var body: some View {
        Section(L("Associations")) {
            ForEach(associations.indices, id: \.self) { i in
                HStack {
                    Text(name(associations[i].target))
                    Picker(L("Connect"), selection: $associations[i].autoConnect) {
                        Text(L("Manually")).tag(VirtualAutoConnect.never)
                        Text(L("While connected")).tag(VirtualAutoConnect.whilePresent)
                        Text(L("While disconnected")).tag(VirtualAutoConnect.whileAbsent)
                    }
                    Picker(L("Show"), selection: $associations[i].presentation) {
                        Text(L("Nothing")).tag(VirtualPresentation.none)
                        Text(L("Mirror onto it")).tag(VirtualPresentation.mirror)
                        Text(L("Stream onto it")).tag(VirtualPresentation.stream)
                        Text(L("Flipped stream")).tag(VirtualPresentation.flippedStream)
                    }
                    Button(L("Remove")) { associations.remove(at: i) }
                }
            }
            HStack {
                Picker(L("Add association"), selection: $newTarget) {
                    Text(L("Choose a display…")).tag(DisplayKey?.none)
                    ForEach(env.runtime.displays.filter { d in !associations.contains { $0.target == d.key } }, id: \.key) { d in
                        Text(d.name).tag(Optional(d.key))
                    }
                }
                Button(L("Add")) {
                    if let t = newTarget { associations.append(VirtualAssociation(target: t)) }
                    newTarget = nil
                }
                .disabled(newTarget == nil)
            }
            ManagementNote(L("Mirroring onto another display and starting streams always ask first."))
        }
    }

    private func name(_ key: DisplayKey) -> String {
        env.runtime.displays.first { $0.key == key }?.name
            ?? env.config.value.perDisplay[key]?.identity.customName ?? L("Disconnected display")
    }
}

/// Smart HiDPI per physical display: toggle, size, HDR, limitations.
private struct SmartHiDPISection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let displays: [DisplayInfo]

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .smartHiDPI, title: L("Smart HiDPI"))
            if env.runtime.isEffective(.smartHiDPI), let c = env.context?.connectPlanner.smartHiDPI {
                ForEach(displays, id: \.key) { d in
                    let active = c.isActive(d.key)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(L("Smart HiDPI on \(d.name)"), isOn: Binding(get: { active }, set: { _ in c.toggle(d.key) }))
                            .disabled(c.isBusy(d.key))
                        if let pair = c.pairs[d.key] {
                            let options = c.modeOptions(d.key)
                            Picker(L("Size"), selection: Binding(get: { pair.mode }, set: { c.setMode(d.key, $0) })) {
                                ForEach(options, id: \.self) { m in Text(m.label).tag(m) }
                                if !options.contains(pair.mode) { Text(pair.mode.label).tag(pair.mode) }
                            }
                            if env.runtime.isEffective(.hdrVirtual) {
                                Toggle(L("HDR (PQ) virtual modes"), isOn: Binding(get: { pair.hdr }, set: { v in
                                    var p = pair
                                    p.hdr = v
                                    env.config.value.virtualScreens.smartHiDPI[d.key] = p
                                }))
                            }
                            if pair.limitToInitial { ManagementNote(L("HiDPI check failed once: sizes are limited to the first one.")) }
                        }
                    }
                }
                if let error = c.lastError { ManagementNote(error) }
            }
        } header: {
            Text(L("Smart HiDPI"))
        } footer: {
            ManagementNote(L("Renders a 2× virtual screen and mirrors it onto the display for sharper text. Limits: no HDCP video, no HDR without HDR modes, the pointer follows the virtual screen's refresh, and it costs GPU time and memory. Turning it on is a trial."))
        }
    }
}
