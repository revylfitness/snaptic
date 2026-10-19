import SwiftUI
import SnapticKit

/// The rule editor (owner: G; PLAN 0.3 §4.3 "Rule editor sheet", §2.7, parity minor 5, design M4, r3 product minor 5):
/// On · Name (placeholder: the conditions as a sentence) · "Keep your Mac awake while [all ▾ / any ▾] of these
/// conditions are met" and 1…8 condition rows · Session options (Display; Activity Off / Appear active, because rules
/// never move the pointer) · Timing (Wait before starting / ending) · After I turn it off · Delete Rule… · Cancel /
/// Done. It edits a copy; Done saves it, and the first rule turns rules on (no section switch, design M4).
struct TriggerEditorSheet: View, ControlDeclaring {
    typealias Controls = TriggerEditorSheetControls

    let env: AwakePageEnvironment
    let target: AwakeRuleEditTarget
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sources = AwakePickerSources()
    @ObservedObject private var runtime: AwakeRuntimeState
    @State private var draft: AwakeTrigger?
    @State private var timingOpen = false
    @State private var confirmDelete = false
    /// §4.3: a new rule opens with its condition kind pop-up focused (ux m12).
    @FocusState private var kindFocused: Bool

    init(env: AwakePageEnvironment, target: AwakeRuleEditTarget) {
        self.env = env
        self.target = target
        _runtime = ObservedObject(wrappedValue: env.runtime)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? L("New Rule") : L("Edit Rule"))
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if let rule = Binding($draft) {
                Form {
                    ruleSection(rule)
                    conditionsSection(rule)
                    optionsSection(rule)
                    timingSection(rule)
                }
                .formStyle(.grouped)
            } else {
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                if !isNew {
                    Button(L("Delete Rule…"), role: .destructive) { confirmDelete = true }
                        .modifier(SettingsAnchor(ControlID("awake.rule.delete")))
                }
                Spacer(minLength: 8)
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .modifier(SettingsAnchor(ControlID("awake.rule.cancel")))
                Button(L("Done")) {
                    // A number typed without Return (battery %, idle minutes…) goes into the draft first (ui F2).
                    FocusedField.commit()
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled((draft?.criteria.isEmpty ?? true))
                .modifier(SettingsAnchor(ControlID("awake.rule.done")))
            }
            .padding(16)
        }
        .frame(width: 600)
        .frame(minHeight: 420, idealHeight: 600, maxHeight: 800)
        .defaultFocus($kindFocused, isNew)
        .onAppear {
            load()
            sources.begin(env.context)
            SettingsShell.shared.sheetDidAppear()
            if isNew { kindFocused = true }
        }
        .onDisappear { sources.end() }
        .alert(L("Delete “\(deleteName)”?"), isPresented: $confirmDelete) {
            Button(L("Delete"), role: .destructive) {
                delete()
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Sessions it started end, and it won’t start new ones."))
        }
    }

    /// The rule as its list row names it (its name, or its conditions' summary), stored version first.
    private var deleteName: String {
        let stored = draft.flatMap { d in env.config.value.triggers.triggers.first { $0.id == d.id } }
        return (stored ?? draft)?.displayName(AwakeFormat.text) ?? ""
    }

    // MARK: Sections

    private func ruleSection(_ rule: Binding<AwakeTrigger>) -> some View {
        Section {
            ToggleSetting(L("On"), help: L("Starts and ends sessions by itself while its conditions are met."),
                          isOn: rule.enabled, anchor: ControlID("awake.rule.on"))
            LabeledContent {
                TextField(L("Name"), text: Binding(get: { rule.wrappedValue.name }, set: { text in
                    rule.wrappedValue.name = String(text.prefix(AwakeCriterion.maxNameScalars))
                }), prompt: Text(TriggerEngine.summary(rule.wrappedValue, text: AwakeFormat.text)))
                .labelsHidden()
                .frame(maxWidth: 300)
            } label: {
                Text(L("Name"))
                Text(L("Shown in the rule list and the Awake menu."))
            }
            .modifier(SettingsAnchor(ControlID("awake.rule.name")))
        }
    }

    private func conditionsSection(_ rule: Binding<AwakeTrigger>) -> some View {
        let count = rule.wrappedValue.criteria.count
        return Section {
            HStack(spacing: 6) {
                Text(L("Keep your Mac awake while"))
                Picker(L("All or any"), selection: rule.match) {
                    Text(L("all")).tag(TriggerMatch.all)
                    Text(L("any")).tag(TriggerMatch.any)
                }
                .labelsHidden()
                .fixedSize()
                Text(L("of these conditions are met"))
                Spacer(minLength: 0)
            }
            .modifier(SettingsAnchor(ControlID("awake.rule.match")))
            ForEach(Array(0..<count), id: \.self) { (index: Int) in
                CriterionEditors(entry: entryBinding(rule, index), sources: sources,
                                 remove: removal(rule, index, count: count), anchored: index == 0,
                                 focus: index == 0 && isNew ? $kindFocused : nil)
            }
            HStack {
                Spacer()
                Button {
                    addCondition(rule)
                } label: {
                    Label(L("Add Condition"), systemImage: "plus")
                }
                .disabled(count >= AwakeTrigger.maxCriteria)
                .help(count >= AwakeTrigger.maxCriteria ? L("A rule can have up to 8 conditions.") : L("Adds another condition."))
                .modifier(SettingsAnchor(ControlID("awake.rule.condition.add")))
            }
        } header: {
            Text(L("Conditions"))
                .modifier(SettingsAnchor(ControlID("awake.rule.conditions")))
        }
    }

    private func optionsSection(_ rule: Binding<AwakeTrigger>) -> some View {
        Section {
            PickerSetting(L("Display"), help: L("When the display may turn off while this rule keeps your Mac awake."),
                          selection: rule.options.display, options: [
                              PickerOption(AwakeDisplayPolicy.keepOn, L("Keep On")),
                              PickerOption(AwakeDisplayPolicy.maySleep, L("Can Turn Off")),
                              PickerOption(AwakeDisplayPolicy.keepOnWhileActive, L("Keep On Until Idle")),
                          ], style: .popUp, defaultValue: AwakeSessionOptions().display,
                          anchor: ControlID("awake.rule.display"))
            if rule.wrappedValue.options.display == .keepOnWhileActive {
                StepperSetting(L("Turn the display off after"), help: L("Minutes without keyboard or mouse input."),
                               value: rule.options.displayIdleMinutes, in: AwakeSessionOptions.displayIdleMinutesRange,
                               defaultValue: AwakeSessionOptions().displayIdleMinutes, format: .minutes)
                    .padding(.leading, 20)
            }
            if runtime.isEffective(.activity) {
                PickerSetting(L("Activity"), help: L("Rules can keep you from appearing away, but never move the pointer."),
                              selection: Binding(get: { rule.wrappedValue.options.activity == .off ? AwakeActivityMode.off : .declare },
                                                 set: { rule.wrappedValue.options.activity = $0 }),
                              options: [
                                  PickerOption(AwakeActivityMode.off, L("Off")),
                                  PickerOption(AwakeActivityMode.declare, L("Appear Active")),
                              ], style: .popUp, defaultValue: AwakeActivityMode.off,
                              anchor: ControlID("awake.rule.activity"))
            }
        } header: {
            Text(L("Session options"))
        }
    }

    private func timingSection(_ rule: Binding<AwakeTrigger>) -> some View {
        Section {
            DisclosureGroup(L("Timing"), isExpanded: $timingOpen) {
                PickerSetting(L("Wait before starting"), help: L("The conditions must hold this long before a session starts."),
                              selection: rule.startDelaySeconds,
                              options: delayOptions(rule.wrappedValue.startDelaySeconds), style: .popUp,
                              defaultValue: nil, anchor: ControlID("awake.rule.startDelay"))
                PickerSetting(L("Wait before ending"), help: L("Keeps the session through short gaps in the conditions."),
                              selection: rule.endDelaySeconds,
                              options: delayOptions(rule.wrappedValue.endDelaySeconds), style: .popUp,
                              defaultValue: AwakeTrigger.defaultEndDelaySeconds, anchor: ControlID("awake.rule.endDelay"))
            }
            .modifier(SettingsRevealExpansion([ControlID("awake.rule.startDelay"), ControlID("awake.rule.endDelay")],
                                              isExpanded: $timingOpen))
            PickerSetting(L("After I turn it off"),
                          help: L("When this rule may start a session again after you turn its session off."),
                          selection: rule.resumeAfterManualEndMinutes, options: resumeOptions(rule.wrappedValue),
                          style: .popUp, defaultValue: Optional<Int?>.some(nil),
                          anchor: ControlID("awake.rule.resume"))
        }
    }

    private func delayOptions(_ current: Int) -> [PickerOption<Int>] {
        AwakeTrigger.choices(AwakeTrigger.delayChoices, including: current).map {
            PickerOption($0, AwakeTrigger.delayTitle($0, titleCase: true))
        }
    }

    private func resumeOptions(_ rule: AwakeTrigger) -> [PickerOption<Int?>] {
        var values = AwakeTrigger.resumeChoices
        if let current = rule.resumeAfterManualEndMinutes, !values.contains(current) { values.append(current) }
        return values.map { (minutes: Int?) -> PickerOption<Int?> in
            guard let minutes else { return PickerOption(nil, L("Resume When the Conditions Are Next Met")) }
            let span = minutes % 60 == 0 ? AwakeCountdown.unit(minutes / 60, L("Hour"), L("Hours"))
                                         : AwakeCountdown.unit(minutes, L("Minute"), L("Minutes"))
            return PickerOption(minutes, L("Resume After ") + span)
        }
    }

    // MARK: Conditions

    private func entryBinding(_ rule: Binding<AwakeTrigger>, _ index: Int) -> Binding<AwakeCriterionEntry> {
        Binding(get: {
            let list = rule.wrappedValue.criteria
            return list.indices.contains(index) ? list[index] : AwakeCriterionEntry(.display(.anyExternal))
        }, set: { entry in
            guard rule.wrappedValue.criteria.indices.contains(index) else { return }
            rule.wrappedValue.criteria[index] = entry
        })
    }

    /// The row's − button; nil for the last condition.
    private func removal(_ rule: Binding<AwakeTrigger>, _ index: Int, count: Int) -> (@MainActor () -> Void)? {
        guard count > 1 else { return nil }
        return { removeCondition(rule, index) }
    }

    private func addCondition(_ rule: Binding<AwakeTrigger>) {
        guard rule.wrappedValue.criteria.count < AwakeTrigger.maxCriteria else { return }
        let used = Set(rule.wrappedValue.criteria.map { AwakeCriterionChoice($0.criterion) })
        let next = AwakeCriterionChoice.allCases.first { !used.contains($0) && $0.defaultCriterion != nil } ?? .power
        guard let criterion = sources.firstCriterion(next) else { return }
        rule.wrappedValue.criteria.append(AwakeCriterionEntry(criterion))
    }

    private func removeCondition(_ rule: Binding<AwakeTrigger>, _ index: Int) {
        guard rule.wrappedValue.criteria.count > 1, rule.wrappedValue.criteria.indices.contains(index) else { return }
        rule.wrappedValue.criteria.remove(at: index)
    }

    // MARK: Load and save

    private func load() {
        guard draft == nil else { return }
        switch target {
        case .existing(let id):
            draft = env.config.value.triggers.triggers.first { $0.id == id }
            if draft == nil { dismiss() }
        case .new(let id):
            draft = AwakeTrigger.new(id: id, criterion: nil)
        }
    }

    /// Done: replaces the rule by id (or appends a new one, ≤ 32) and turns rules on.
    private func save() {
        guard let draft else { return }
        let rule = draft.savedFromEditor(wasNew: isNew)
        var config = env.config.value
        if let i = config.triggers.triggers.firstIndex(where: { $0.id == rule.id }) {
            config.triggers.triggers[i] = rule
        } else if config.triggers.triggers.count < AwakeTrigger.maxTriggers {
            config.triggers.triggers.append(rule)
        } else {
            return
        }
        if config.features[.triggers] != true { config.features[.triggers] = true }
        if config != env.config.value { env.config.value = config }
    }

    private func delete() {
        guard case .existing(let id) = target else { return }
        var config = env.config.value
        config.triggers.triggers.removeAll { $0.id == id }
        if config != env.config.value { env.config.value = config }
    }
}
