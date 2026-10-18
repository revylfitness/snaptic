import SwiftUI
import SnapticKit

/// A hook's Details… sheet (owner A; PLAN 0.3 §4.3 Automations, §4.8 Automation row): name, When, Display (events of
/// one display), Delay (after-wake events), Program with Choose… and the rule check, Arguments; footer Delete Hook…
/// (standard alert) and Done. Every field writes the stored hook at once (no copy to lose; fixes [UA] B2). Whether
/// the hook runs is the list row's switch.
struct HookEditorSheet: View, ControlDeclaring {
    typealias Controls = HookEditorSheetControls

    let env: DisplaysPageEnvironment
    let hookID: StableID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var automation: ConfigSlice<DisplaysConfig, AutomationConfig>

    init(env: DisplaysPageEnvironment, hookID: StableID) {
        self.env = env
        self.hookID = hookID
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _automation = StateObject(wrappedValue: ConfigSlice(env.config, \.automation))
    }

    /// The stored hook; nil once it was deleted (the sheet then closes).
    private var hook: HookSpec? { automation.value.hooks.first { $0.id == hookID } }

    var body: some View {
        let current = hook ?? HookSpec(id: hookID)
        AdvancedSheet(current.name.isEmpty ? L("Hook") : current.name, restoreDefaults: deleteHook(current),
                      restoreControl: ControlID("displays.automations.hook.delete")) {
            Section {
                TextField(L("Name"), text: field(\.name, fallback: ""),
                          prompt: Text(current.summary(displayName: AutomationText.displayName(current.display, env: env))))
                    .modifier(SettingsAnchor(ControlID("displays.automations.hook.name")))
                PickerSetting(L("When"), help: current.event.help, selection: field(\.event, fallback: .connect),
                              options: HookEvent.allCases.map { PickerOption($0, $0.title) }, style: .popUp,
                              defaultValue: nil, anchor: ControlID("displays.automations.hook.event"))
                if current.event.isPerDisplay {
                    PickerSetting(L("Display"), selection: field(\.display, fallback: nil),
                                  options: displayOptions(current.display), style: .popUp, defaultValue: nil,
                                  anchor: ControlID("displays.automations.hook.display"))
                }
                if current.event == .wakeDelayed {
                    StepperSetting(L("Wait after waking"), value: field(\.delaySeconds, fallback: 10), in: 1...600, step: 1,
                                   defaultValue: 10, format: .seconds,
                                   anchor: ControlID("displays.automations.hook.delay"))
                }
            }
            AutomationCommandSections(command: field(\.command, fallback: CommandSpec()),
                                      programControl: ControlID("displays.automations.hook.program"),
                                      chooseControl: ControlID("displays.automations.hook.choose"),
                                      argumentsControl: ControlID("displays.automations.hook.arguments"))
        }
        .onChange(of: hook == nil) { _, gone in if gone { dismiss() } }
    }

    private func field<V: Equatable>(_ path: WritableKeyPath<HookSpec, V>, fallback: V) -> Binding<V> {
        AutomationEdit.field(env.config, \.hooks, hookID, path, fallback: fallback) { $0.sanitized() }
    }

    /// Any display, the connected displays, and the stored display while it isn't connected.
    private func displayOptions(_ stored: DisplayKey?) -> [PickerOption<DisplayKey?>] {
        var options = [PickerOption<DisplayKey?>(nil, L("Any display"))]
        options += runtime.displays.map { PickerOption(Optional($0.key), $0.name) }
        if let stored, !runtime.displays.contains(where: { $0.key == stored }) {
            let name = AutomationText.displayName(stored, env: env) ?? L("A display that isn’t connected")
            options.append(PickerOption(Optional(stored), L("\(name) (not connected)")))
        }
        return options
    }

    /// Footer leading: Delete Hook… with the standard confirmation.
    private func deleteHook(_ hook: HookSpec) -> RestoreDefaults {
        let store = env.config
        let deletion = AutomationDeletion.hook(hook)
        return RestoreDefaults(title: L("Delete Hook…"), question: deletion.question, message: deletion.message,
                               button: L("Delete"), destructive: true) {
            deletion.perform(store)
        }
    }
}
