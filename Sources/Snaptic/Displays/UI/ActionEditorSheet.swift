import SwiftUI
import SnapticKit

/// A custom action's Details… sheet (owner A; PLAN 0.3 §4.3 Automations, §4.8 Automation row): name, Program with
/// Choose… and the rule check, Arguments, Shortcut, Allow from the command line (with the command to use), Run Now;
/// footer Delete Action… (standard alert) and Done. Every field writes the stored action at once (fixes [UA] B2).
/// Whether it shows in the menu is the list row's checkbox.
struct ActionEditorSheet: View, ControlDeclaring {
    typealias Controls = ActionEditorSheetControls

    let env: DisplaysPageEnvironment
    let actionID: StableID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var automation: ConfigSlice<DisplaysConfig, AutomationConfig>

    init(env: DisplaysPageEnvironment, actionID: StableID) {
        self.env = env
        self.actionID = actionID
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _automation = StateObject(wrappedValue: ConfigSlice(env.config, \.automation))
    }

    /// The stored action; nil once it was deleted (the sheet then closes).
    private var action: CustomActionSpec? { automation.value.actions.first { $0.id == actionID } }

    var body: some View {
        let current = action ?? CustomActionSpec(id: actionID)
        AdvancedSheet(current.name.isEmpty ? L("Action") : current.name, restoreDefaults: deleteAction(current),
                      restoreControl: ControlID("displays.automations.action.delete")) {
            Section {
                TextField(L("Name"), text: field(\.name, fallback: ""), prompt: Text(L("Required")))
                    .modifier(SettingsAnchor(ControlID("displays.automations.action.name")))
                if current.name.isEmpty {
                    SettingsRowNote(L("Name the action to use it in the menu, with a shortcut, or from the command line."))
                }
            }
            AutomationCommandSections(command: field(\.command, fallback: CommandSpec()),
                                      programControl: ControlID("displays.automations.action.program"),
                                      chooseControl: ControlID("displays.automations.action.choose"),
                                      argumentsControl: ControlID("displays.automations.action.arguments"))
            Section {
                ShortcutSetting(L("Shortcut"), help: L("Runs the action from any app."),
                                combo: field(\.shortcut, fallback: nil), owner: L("Action: ") + current.name,
                                anchor: ControlID("displays.automations.action.shortcut"))
                ToggleSetting(L("Allow from the command line"), help: cliHelp(current),
                              isOn: field(\.cliAllowed, fallback: false),
                              anchor: ControlID("displays.automations.action.cliAllowed"))
            }
            Section {
                ButtonRow(L("Run Now"), help: runHelp(current),
                          control: ControlID("displays.automations.action.runNow")) {
                    run(current)
                }
                .disabled(runHelp(current) != nil)
            }
        }
        .onChange(of: action == nil) { _, gone in if gone { dismiss() } }
    }

    private func field<V: Equatable>(_ path: WritableKeyPath<CustomActionSpec, V>, fallback: V) -> Binding<V> {
        AutomationEdit.field(env.config, \.actions, actionID, path, fallback: fallback) { $0.sanitized() }
    }

    /// The exact command scripts use, once the action has a usable name.
    private func cliHelp(_ action: CustomActionSpec) -> String {
        let name = action.cliName
        guard !name.isEmpty else { return L("Scripts can run it with the `snaptic` command.") }
        return L("Scripts run it with “snaptic action run \(name)”.")
    }

    /// Why Run Now can't run the action yet; nil when it can.
    private func runHelp(_ action: CustomActionSpec) -> String? {
        if !runtime.isEffective(.customActions) { return L("Turn on Custom actions to run it.") }
        if action.name.isEmpty { return L("Name the action to run it.") }
        if action.command.executable.isEmpty { return L("Choose a program to run it.") }
        return nil
    }

    /// Runs it the way its menu item and shortcut do (once a second at most; a problem shows as a toast and on the page).
    private func run(_ action: CustomActionSpec) {
        guard runHelp(action) == nil, let ctx = env.context else { return }
        _ = ctx.actions.perform(DisplayActionID(rawValue: "a.custom." + action.id.rawValue), on: .main)
    }

    /// Footer leading: Delete Action… with the standard confirmation.
    private func deleteAction(_ action: CustomActionSpec) -> RestoreDefaults {
        let store = env.config
        let deletion = AutomationDeletion.action(action)
        return RestoreDefaults(title: L("Delete Action…"), question: deletion.question, message: deletion.message,
                               button: L("Delete"), destructive: true) {
            deletion.perform(store)
        }
    }
}
