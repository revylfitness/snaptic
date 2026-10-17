import SwiftUI
import SnapticKit

/// Keys & Shortcuts (PLAN §8.1, §8.2): brightness and volume keys (policy, target,
/// modifiers, steps, "also let macOS handle it"), the Accessibility permission and tap
/// status, per-display key settings, custom shortcuts for every registered display
/// action, and the ten input slots.
struct KeysPage: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var selected: DisplayKey?
    @State private var filter = ""

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            permissionSection
            brightnessSection
            volumeSection
            if let key = selectedKey, env.runtime.isEffective(.brightnessKeys) || env.runtime.isEffective(.volumeKeys) {
                Section(L("Per display")) {
                    CDisplayPicker(env: env, selection: $selected)
                    perDisplayRows(key)
                }
            }
            modifiersSection
            shortcutsSection
            slotsSection
        }
        .formStyle(.grouped)
    }

    private var selectedKey: DisplayKey? {
        let online = env.runtime.displays.filter(\.isOnline)
        if let selected, online.contains(where: { $0.key == selected }) { return selected }
        return online.first(where: \.isMain)?.key ?? online.first?.key
    }

    private var keysController: KeysController? { env.context?.mediaKeys.keysController }

    // MARK: Permission

    @ViewBuilder
    private var permissionSection: some View {
        if let ctx = env.context, env.runtime.isEffective(.brightnessKeys) || env.runtime.isEffective(.volumeKeys) {
            Section(L("Permission")) {
                let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
                let pane = os >= 27 ? L("Device Control and Data Access") : L("Accessibility")
                let granted = ctx.permissions.state(.accessibility) == .granted
                LabeledContent(pane) { Text(granted ? L("Granted") : L("Not granted")) }
                LabeledContent(L("Media keys")) {
                    Text((keysController?.tapRunning ?? false) ? L("Listening") : L("Not listening"))
                }
                HStack {
                    if !granted {
                        Button(L("Grant Access…")) {
                            ctx.permissions.request(.accessibility,
                                                    reason: L("Snaptic needs this to use the brightness and volume keys with your displays."),
                                                    lifetime: ctx.lifetime)
                        }
                    }
                    Button(L("Try Again")) {
                        ctx.permissions.refresh()
                        keysController?.retryTap()
                        env.objectWillChange.send()
                    }
                }
                Text(L("Brightness and volume keys need \(pane). After granting it, macOS may need Snaptic to relaunch."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Brightness keys

    @ViewBuilder
    private var brightnessSection: some View {
        Section(L("Brightness keys")) {
            CFeatureNote(env: env, feature: .brightnessKeys)
            if env.runtime.isEffective(.brightnessKeys) {
                Picker(L("Use them"), selection: CBind.global(env, \.keys.brightnessPolicy)) {
                    ForEach(KeyPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(L("Also let macOS handle brightness keys"), isOn: CBind.global(env, \.keys.brightnessAlsoSystem))
                Picker(L("Keys change"), selection: CBind.global(env, \.keys.target)) {
                    ForEach(KeyTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Stepper(value: CBind.global(env, \.keys.steps), in: KeysConfig.stepRange) {
                    LabeledContent(L("Steps")) { Text(String(env.config.value.keys.steps)) }
                }
                Stepper(value: CBind.global(env, \.keys.fineSteps), in: KeysConfig.fineStepRange) {
                    LabeledContent(L("Fine steps (⌥⇧)")) { Text(String(env.config.value.keys.fineSteps)) }
                }
                Toggle(L("F14 and F15 change brightness"), isOn: CBind.global(env, \.keys.alternateKeys))
                if env.runtime.isEffective(.xdr) {
                    Text(L("With extra brightness on a display, brightness up at 100% and down above 100% always go to Snaptic, built-in displays included."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Volume keys

    @ViewBuilder
    private var volumeSection: some View {
        Section(L("Volume keys")) {
            CFeatureNote(env: env, feature: .volumeKeys)
            if env.runtime.isEffective(.volumeKeys) {
                Picker(L("Send volume to a monitor"), selection: CBind.global(env, \.keys.volumePolicy)) {
                    ForEach(VolumePolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(L("Also let macOS handle volume keys"), isOn: CBind.global(env, \.keys.volumeAlsoSystem))
                Toggle(L("Also let macOS handle the mute key"), isOn: CBind.global(env, \.keys.muteAlsoSystem))
                Text(L("Only monitors that report a volume control (VCP 62) take the volume keys."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func perDisplayRows(_ key: DisplayKey) -> some View {
        Toggle(L("Keys change this display"), isOn: CBind.display(env, key, \.keys.keysEnabled))
        if env.runtime.isEffective(.volumeKeys) {
            Toggle(L("Show the volume OSD"), isOn: CBind.display(env, key, \.keys.showVolumeOSD))
            LabeledContent(L("Sound output name")) {
                TextField(L("Same as the display"), text: Binding(
                    get: { env.config.value.perDisplay[key]?.keys.audioDeviceName ?? "" },
                    set: { CBind.display(env, key, \.keys.audioDeviceName).wrappedValue = $0.isEmpty ? nil : String($0.prefix(64)) }))
                    .frame(maxWidth: 220)
            }
            Text(L("Used by “When the sound output is the display” if the output's name differs from the display's."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var modifiersSection: some View {
        if env.runtime.isEffective(.brightnessKeys) || env.runtime.isEffective(.volumeKeys) {
            Section(L("Modifiers")) {
                ForEach([(L("⌥⇧"), L("Fine steps")), (L("⇧"), L("This display only (skip sync)")),
                         (L("⌃"), L("Built-in display only")), (L("⌃⌘"), L("External displays only")),
                         (L("⇧⌘"), L("Every display except the one with the pointer")),
                         (L("⌥ + brightness"), L("Open Brightness settings")),
                         (L("⌘ + brightness down"), L("Mirror or unmirror the display"))], id: \.0) { combo, meaning in
                    LabeledContent(meaning) { Text(combo).monospaced() }
                }
            }
        }
    }

    // MARK: Shortcuts

    private func shortcut(_ id: DisplayActionID) -> Binding<HotkeyCombo?> {
        Binding(get: { env.config.value.keys.shortcuts[id] },
                set: { combo in
                    if let controller = keysController {
                        controller.setShortcut(combo, for: id)
                    } else {
                        env.config.value.keys.shortcuts[id] = combo
                    }
                })
    }

    private func conflict(_ combo: HotkeyCombo, excluding id: DisplayActionID) -> String? {
        if combo.keyCode == 107 || combo.keyCode == 113, combo.carbonModifiers == 0, env.config.value.keys.alternateKeys {
            return L("F14 and F15 are used for brightness.")
        }
        guard let other = env.config.value.keys.shortcuts.values.first(where: { $0.key != id && $0.value == combo })?.key else {
            return nil
        }
        let title = env.context?.actions.action(other)?.title ?? other.rawValue
        return L("Already used by “\(title)”.")
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        Section(L("Shortcuts")) {
            CFeatureNote(env: env, feature: .shortcuts)
            if env.runtime.isEffective(.shortcuts), let ctx = env.context {
                TextField(L("Filter"), text: $filter)
                let actions = ctx.actions.all
                    .filter { env.runtime.isEffective($0.feature) || env.config.value.keys.shortcuts[$0.id] != nil }
                    .filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                ForEach(actions, id: \.id) { action in
                    shortcutRow(action)
                }
                if actions.isEmpty { Text(L("No actions match.")).foregroundStyle(.secondary) }
                Text(L("Shortcuts act on the display chosen under “Keys change”. They work without Accessibility, also in password fields."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(_ action: Action) -> some View {
        LabeledContent {
            HStack {
                ShortcutRecorder(combo: shortcut(action.id), validate: { conflict($0, excluding: action.id) })
                if env.config.value.keys.shortcuts[action.id] != nil {
                    Button { shortcut(action.id).wrappedValue = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Remove shortcut for \(action.title)"))
                }
            }
        } label: {
            VStack(alignment: .leading) {
                Text(action.title)
                if let problem = keysController?.hotkeyProblems[action.id] {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else if !env.runtime.isEffective(action.feature) {
                    Text(L("Needs \(DisplaysUIText.title(action.feature))")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Input slots

    private func slots() -> Binding<[InputSlot]> {
        Binding(get: { env.config.value.keys.inputSlots },
                set: { env.config.value.keys.inputSlots = Array($0.prefix(KeysConfig.maxSlots)) })
    }

    @ViewBuilder
    private var slotsSection: some View {
        Section(L("Input slots")) {
            CFeatureNote(env: env, feature: .ddcInput)
            if env.runtime.isEffective(.ddcInput) {
                let list = slots()
                ForEach(Array(list.wrappedValue.enumerated()), id: \.offset) { index, slot in
                    slotRow(list, index, slot)
                }
                if list.wrappedValue.count < KeysConfig.maxSlots {
                    Button(L("Add Slot")) { list.wrappedValue = list.wrappedValue + [InputSlot()] }
                }
                Text(L("Give each slot a shortcut above (“Input Slot 1”…). A slot without a display switches the display chosen under “Keys change”."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func slotRow(_ list: Binding<[InputSlot]>, _ index: Int, _ slot: InputSlot) -> some View {
        HStack {
            Text(L("Slot \(index + 1)")).frame(width: 56, alignment: .leading)
            Picker(L("Display"), selection: Binding(get: { slot.display }, set: { value in
                update(list, index) { $0.display = value }
            })) {
                Text(L("Target display")).tag(DisplayKey?.none)
                ForEach(env.runtime.displays.filter { !$0.isBuiltin }) { d in
                    Text(TextSanitizer.clean(d.name, maxScalars: 64)).tag(Optional(d.key))
                }
            }
            .labelsHidden()
            Picker(L("Input"), selection: Binding(get: { slot.value }, set: { value in update(list, index) { $0.value = value } })) {
                ForEach(slotInputs(slot), id: \.self) { value in Text(VCPPolicy.inputName(value)).tag(value) }
            }
            .labelsHidden()
            Toggle(L("LG"), isOn: Binding(get: { slot.lgAlt }, set: { value in update(list, index) { $0.lgAlt = value } }))
                .toggleStyle(.checkbox)
                .help(L("Use LG's alternate input command"))
            Button { list.wrappedValue = list.wrappedValue.enumerated().filter { $0.offset != index }.map(\.element) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Remove slot \(index + 1)"))
        }
    }

    private func slotInputs(_ slot: InputSlot) -> [UInt16] {
        var values = DisplaysUIText.commonInputs
        if let key = slot.display, let listed = env.context?.ddc.cachedCapabilities(key)?.inputSources, !listed.isEmpty {
            values = listed.map { $0 & 0xFF }
        }
        if !values.contains(slot.value) { values.append(slot.value) }
        return Array(Set(values)).sorted()
    }

    private func update(_ list: Binding<[InputSlot]>, _ index: Int, _ body: (inout InputSlot) -> Void) {
        var l = list.wrappedValue
        guard l.indices.contains(index) else { return }
        body(&l[index])
        list.wrappedValue = l
    }
}
