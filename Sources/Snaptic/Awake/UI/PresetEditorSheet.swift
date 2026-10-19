import SwiftUI
import SnapticKit

/// The Sessions sheet (owner: G; PLAN 0.3 §4.3 "Sessions sheet", R5-11, parity minor 6): the sessions the Keep Awake
/// button, Start Session › and the preset shortcuts offer, in order. Rows reorder by drag or Move Up / Move Down;
/// each has an Options disclosure (name, kind, length or time, At most and thresholds for task sessions, display,
/// activity). Edits apply at once; the page's Default session pop-up chooses the default (no ★).
struct PresetEditorSheet: View, ControlDeclaring {
    typealias Controls = PresetEditorSheetControls

    let env: AwakePageEnvironment
    @StateObject private var sessions: ConfigSlice<AwakeConfig, AwakeSessionsConfig>
    @ObservedObject private var runtime: AwakeRuntimeState
    @State private var expanded: StableID?
    @State private var deleting: StableID?

    init(env: AwakePageEnvironment) {
        self.env = env
        _sessions = StateObject(wrappedValue: ConfigSlice(env.config, \.sessions))
        _runtime = ObservedObject(wrappedValue: env.runtime)
    }

    var body: some View {
        AdvancedSheet(L("Sessions"), restoreDefaults: restore, restoreControl: ControlID("awake.sessions.restore")) {
            listSection
            addSection
        }
        .alert(deletingTitle, isPresented: deletingShown) {
            Button(L("Delete"), role: .destructive) { confirmDelete() }
            Button(L("Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(L("It’s removed from Keep Awake, the Awake menu, and its shortcut."))
        }
    }

    private var listSection: some View {
        let presets: [AwakePreset] = sessions.value.presets
        let canDelete = presets.count > 1
        let onEdit: (AwakePreset) -> Void = { preset in expanded = preset.id }
        var onDelete: ((AwakePreset) -> Void)?
        if canDelete {
            onDelete = { (preset: AwakePreset) in deleting = preset.id }
        }
        return Section {
            ReorderableList(SettingsBinding.store(env.config, \.sessions.presets), onEdit: onEdit,
                            onDelete: onDelete, deleteAsks: true) { (preset: AwakePreset) -> PresetRow in
                row(preset, first: presets.first?.id, canDelete: canDelete)
            }
        } header: {
            Text(L("Sessions in the menu"))
                .modifier(SettingsAnchor(ControlID("awake.sessions.list")))
        } footer: {
            Text(L("Keep Awake and Start Session list these in this order. Drag to reorder."))
        }
    }

    private func row(_ preset: AwakePreset, first: StableID?, canDelete: Bool) -> PresetRow {
        let id = preset.id
        let expandedBinding = Binding<Bool>(get: { expanded == id }, set: { on in expanded = on ? id : nil })
        var delete: (@MainActor () -> Void)?
        if canDelete {
            delete = { deleting = id }
        }
        return PresetRow(env: env, id: id, preset: preset, defaults: sessions.value, effective: runtime.effectiveFeatures,
                         isExpanded: expandedBinding, delete: delete, revealsHere: id == first)
    }

    private var addSection: some View {
        let count = sessions.value.presets.count
        return Section {
            ButtonRow(L("Add Session"), help: addHelp(count), symbol: "plus", control: ControlID("awake.sessions.add")) {
                addPreset()
            }
            .disabled(count >= AwakeSessionsConfig.maxPresets)
        }
    }

    /// "Delete “For 1 Hour”?" (ux nit 8: named, as PIP and Forget do).
    private var deletingTitle: String {
        let preset = deleting.flatMap { id in sessions.value.presets.first { $0.id == id } }
        guard let preset else { return L("Delete this session?") }
        return L("Delete ") + AwakeDetail.quoted(preset.title(AwakeFormat.text)) + "?"
    }

    private var deletingShown: Binding<Bool> {
        Binding<Bool>(get: { deleting != nil }, set: { shown in if !shown { deleting = nil } })
    }

    private func addPreset() {
        let id = StableID()
        guard let next = env.config.value.sessions.addingPreset(id: id) else { return }
        env.config.value.sessions = next
        expanded = id
    }

    private func confirmDelete() {
        if let id = deleting {
            env.config.value.sessions = env.config.value.sessions.removingPreset(id)
            if expanded == id { expanded = nil }
        }
        deleting = nil
    }

    private func addHelp(_ count: Int) -> String {
        count >= AwakeSessionsConfig.maxPresets ? L("You can have up to 12 sessions.") : L("Adds a 1-hour session you can change.")
    }

    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(title: L("Restore Default Sessions…"), question: L("Restore the default sessions?"),
                               message: L("Your own sessions are removed, and the default session is Until Turned Off again."),
                               button: L("Restore Defaults"), destructive: true) {
            let next = config.value.sessions.restoringDefaultPresets()
            if next != config.value.sessions { config.value.sessions = next }
        }
    }
}

// MARK: - One session

/// "Use default" or an explicit value of a session's options (nil options = both default).
private enum OptionChoice<V: Hashable>: Hashable {
    case useDefault
    case value(V)
}

private struct PresetRow: View {
    let env: AwakePageEnvironment
    let id: StableID
    let preset: AwakePreset
    let defaults: AwakeSessionsConfig
    let effective: Set<AwakeFeature>
    let isExpanded: Binding<Bool>
    let delete: (@MainActor () -> Void)?
    /// The first row opens when search reveals one of the per-session rows.
    let revealsHere: Bool

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            fields
        } label: {
            rowLabel
        }
        .modifier(SettingsRevealExpansion(revealsHere ? Self.revealIDs : [], isExpanded: isExpanded))
    }

    private var rowLabel: some View {
        HStack {
            Text(preset.title(AwakeFormat.text))
            Spacer(minLength: 8)
            if preset.id == defaults.defaultPreset.id {
                Text(L("Default")).foregroundStyle(.secondary)
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(L("Name")) {
                TextField(L("Name"), text: name, prompt: Text(preset.kind.title(AwakeFormat.text)))
                    .labelsHidden()
                    .frame(maxWidth: 220)
            }
            .modifier(SettingsAnchor(ControlID("awake.sessions.name")))
            PickerSetting(L("Kind"), selection: kindChoice, options: [
                PickerOption(AwakePresetKindChoice.indefinite, L("Until Turned Off")),
                PickerOption(AwakePresetKindChoice.duration, L("For a Duration")),
                PickerOption(AwakePresetKindChoice.untilTime, L("Until a Time")),
                PickerOption(AwakePresetKindChoice.untilIdle, L("Until Downloads and Tasks Finish")),
            ], style: .popUp, defaultValue: nil, anchor: ControlID("awake.sessions.kind"))
            kindFields
            PickerSetting(L("Display"), help: L("When the display may turn off during this session."),
                          selection: display, options: displayOptions, style: .popUp,
                          defaultValue: OptionChoice<AwakeDisplayPolicy>.useDefault,
                          anchor: ControlID("awake.sessions.display"))
            if displayPolicy == .keepOnWhileActive {
                StepperSetting(L("Turn the display off after"),
                               help: L("Minutes without keyboard or mouse input."),
                               value: idleMinutes, in: AwakeSessionOptions.displayIdleMinutesRange,
                               defaultValue: AwakeSessionOptions().displayIdleMinutes, format: .minutes)
                    .padding(.leading, 20)
            }
            if effective.contains(.activity) {
                PickerSetting(L("Activity"), help: L("Whether this session also keeps you from appearing away."),
                              selection: activity, options: activityOptions, style: .popUp,
                              defaultValue: OptionChoice<AwakeActivityMode>.useDefault,
                              anchor: ControlID("awake.sessions.activity"))
            }
            if let delete {
                HStack {
                    Spacer()
                    Button(L("Delete Session…"), role: .destructive) { delete() }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static let revealIDs = [
        ControlID("awake.sessions.name"), ControlID("awake.sessions.kind"), ControlID("awake.sessions.duration"),
        ControlID("awake.sessions.untilTime"), ControlID("awake.sessions.atMost"), ControlID("awake.sessions.thresholds"),
        ControlID("awake.sessions.display"), ControlID("awake.sessions.activity"),
    ]

    // MARK: Kind

    @ViewBuilder private var kindFields: some View {
        switch preset.kind {
        case .indefinite:
            EmptyView()
        case .duration(let seconds):
            durationFields(seconds) { new in update { $0.kind = .duration(seconds: new) } }
        case .untilTime(let hour, let minute):
            DatePicker(L("Ends at"), selection: Binding(get: { Self.date(hour: hour, minute: minute) }, set: { date in
                let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
                update { $0.kind = .untilTime(hour: c.hour ?? 17, minute: c.minute ?? 0) }
            }), displayedComponents: .hourAndMinute)
            .modifier(SettingsAnchor(ControlID("awake.sessions.untilTime")))
        case .untilIdle(let spec, let cap):
            PickerSetting(L("At most"), help: L("Ends the session after this long even if there is still activity."),
                          selection: Binding(get: { cap.map { $0 / 3_600 } ?? 0 }, set: { hours in
                              update { $0.kind = .untilIdle(spec, maxSeconds: hours > 0 ? hours * 3_600 : nil) }
                          }),
                          options: Self.atMostOptions,
                          style: .popUp, defaultValue: 0, anchor: ControlID("awake.sessions.atMost"))
            ThresholdsDisclosure(spec: spec) { new in update { $0.kind = .untilIdle(new, maxSeconds: cap) } }
        }
    }

    /// No limit, 1, 2, 4, 8, 12 hours (0 = No limit).
    private static var atMostOptions: [PickerOption<Int>] {
        var out: [PickerOption<Int>] = [PickerOption(0, L("No Limit"))]
        for hours in AwakePresetKind.atMostHours {
            out.append(PickerOption(hours, AwakeCountdown.unit(hours, L("Hour"), L("Hours"))))
        }
        return out
    }

    /// Hours and minutes (5-minute steps), at least 1 minute and at most 30 days together.
    @ViewBuilder private func durationFields(_ seconds: Int, apply: @escaping @MainActor (Int) -> Void) -> some View {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        StepperSetting(L("Hours"), value: Binding(get: { hours }, set: { h in apply(Self.total(hours: h, minutes: minutes)) }),
                       in: 0...(AwakeClock.maxSessionSeconds / 3_600 - 1), defaultValue: nil, format: .plain(digits: 0),
                       anchor: ControlID("awake.sessions.duration"))
        StepperSetting(L("Minutes"), value: Binding(get: { minutes }, set: { m in apply(Self.total(hours: hours, minutes: m)) }),
                       in: 0...59, step: 5, defaultValue: nil, format: .minutes)
    }

    private static func total(hours: Int, minutes: Int) -> Int {
        AwakeMath.clamp(hours * 3_600 + minutes * 60, AwakeClock.durationRange)
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var c = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        return Calendar.autoupdatingCurrent.date(from: c) ?? Date()
    }

    // MARK: Bindings

    /// Writes one preset by id (the list may have moved since the row was built).
    private func update(_ change: (inout AwakePreset) -> Void) {
        var sessions = env.config.value.sessions
        guard let i = sessions.presets.firstIndex(where: { $0.id == id }) else { return }
        var p = sessions.presets[i]
        change(&p)
        guard p != sessions.presets[i] else { return }
        sessions.presets[i] = p
        env.config.value.sessions = sessions
    }

    private var name: Binding<String> {
        Binding(get: { preset.name ?? "" }, set: { text in
            let trimmed = String(text.prefix(AwakePreset.maxNameScalars))
            update { $0.name = trimmed.trimmingCharacters(in: .whitespaces).isEmpty ? nil : trimmed }
        })
    }

    private var kindChoice: Binding<AwakePresetKindChoice> {
        Binding(get: { preset.kind.choice }, set: { choice in update { $0.kind = $0.kind.switched(to: choice) } })
    }

    // MARK: Display and activity

    private var displayPolicy: AwakeDisplayPolicy { (preset.options ?? defaults.defaultOptions).display }

    private var displayOptions: [PickerOption<OptionChoice<AwakeDisplayPolicy>>] {
        let fallback = defaults.defaultDisplayPolicy(for: preset.kind)
        return [
            PickerOption(.useDefault, L("Default (") + Self.displayTitle(fallback) + ")"),
            PickerOption(.value(.keepOn), Self.displayTitle(.keepOn)),
            PickerOption(.value(.maySleep), Self.displayTitle(.maySleep)),
            PickerOption(.value(.keepOnWhileActive), Self.displayTitle(.keepOnWhileActive)),
        ]
    }

    private static func displayTitle(_ p: AwakeDisplayPolicy) -> String {
        switch p {
        case .keepOn: return L("Keep On")
        case .maySleep: return L("Can Turn Off")
        case .keepOnWhileActive: return L("Keep On Until Idle")
        }
    }

    private var display: Binding<OptionChoice<AwakeDisplayPolicy>> {
        let defaults = self.defaults
        return Binding(get: { preset.options.map { OptionChoice.value($0.display) } ?? OptionChoice.useDefault }, set: { choice in
            update { p in
                switch choice {
                case .useDefault: p.options = nil
                case .value(let policy):
                    var o = p.options ?? defaults.defaultOptions
                    o.display = policy
                    p.options = o
                }
            }
        })
    }

    private var idleMinutes: Binding<Int> {
        let defaults = self.defaults
        return Binding(get: { (preset.options ?? defaults.defaultOptions).displayIdleMinutes }, set: { m in
            update { p in
                var o = p.options ?? defaults.defaultOptions
                o.displayIdleMinutes = m
                p.options = o
            }
        })
    }

    private var activityOptions: [PickerOption<OptionChoice<AwakeActivityMode>>] {
        var out: [PickerOption<OptionChoice<AwakeActivityMode>>] = [
            PickerOption(.useDefault, L("Default")),
            PickerOption(.value(.off), L("Off")),
            PickerOption(.value(.declare), L("Appear Active")),
        ]
        if effective.contains(.pointerNudge) {
            out.append(PickerOption(.value(.nudge), L("Move the Pointer Slightly")))
        }
        return out
    }

    private var activity: Binding<OptionChoice<AwakeActivityMode>> {
        let defaults = self.defaults
        return Binding(get: { preset.options.map { OptionChoice.value($0.activity) } ?? OptionChoice.useDefault }, set: { choice in
            update { p in
                switch choice {
                case .useDefault: p.options = nil
                case .value(let mode):
                    var o = p.options ?? defaults.defaultOptions
                    o.activity = mode
                    p.options = o
                }
            }
        })
    }
}

/// "Thresholds" of a task session: what counts as activity, and how long it must be quiet.
private struct ThresholdsDisclosure: View {
    let spec: UntilIdleSpec
    let apply: @MainActor (UntilIdleSpec) -> Void
    @State private var open = false

    var body: some View {
        DisclosureGroup(L("Thresholds"), isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                StepperSetting(L("Busiest app above"), help: L("CPU use of the busiest process, where 100% is one core."),
                               value: field(\.topProcessPercent), in: UntilIdleSpec.topProcessRange, step: 10,
                               defaultValue: UntilIdleSpec().topProcessPercent, format: .percent(of: 100))
                StepperSetting(L("New processes"), help: L("Processes started in the last 10 seconds, as in a build."),
                               value: field(\.newProcesses), in: UntilIdleSpec.newProcessesRange,
                               defaultValue: UntilIdleSpec().newProcesses, format: .plain(digits: 0))
                StepperSetting(L("Total CPU above"), help: L("CPU use of the whole Mac."),
                               value: field(\.totalCPUPercent), in: UntilIdleSpec.totalCPURange,
                               defaultValue: UntilIdleSpec().totalCPUPercent, format: .percent(of: 100))
                StepperSetting(L("Disk activity above (KB/s)"),
                               help: L("Disk activity counts every app, including Spotlight."),
                               value: field(\.diskKBps), in: UntilIdleSpec.diskRange, step: 256,
                               defaultValue: UntilIdleSpec().diskKBps, format: .plain(digits: 0))
                StepperSetting(L("Network activity above (KB/s)"), help: L("Downloads and uploads together."),
                               value: field(\.networkKBps), in: UntilIdleSpec.networkRange, step: 10,
                               defaultValue: UntilIdleSpec().networkKBps, format: .plain(digits: 0))
                StepperSetting(L("Quiet for"), help: L("Ends the session after this long without activity."),
                               value: Binding(get: { spec.quietSeconds / 60 },
                                              set: { m in apply(with(\.quietSeconds, m * 60)) }),
                               in: (UntilIdleSpec.quietRange.lowerBound / 60)...(UntilIdleSpec.quietRange.upperBound / 60),
                               defaultValue: UntilIdleSpec().quietSeconds / 60, format: .minutes)
            }
            .padding(.vertical, 4)
        }
        .modifier(SettingsAnchor(ControlID("awake.sessions.thresholds")))
        .modifier(SettingsRevealExpansion([ControlID("awake.sessions.thresholds")], isExpanded: $open))
    }

    private func field(_ path: WritableKeyPath<UntilIdleSpec, Int>) -> Binding<Int> {
        Binding(get: { spec[keyPath: path] }, set: { v in apply(with(path, v)) })
    }

    private func with(_ path: WritableKeyPath<UntilIdleSpec, Int>, _ value: Int) -> UntilIdleSpec {
        var s = spec
        s[keyPath: path] = value
        return s.sanitized()
    }
}
