import AppKit
import SwiftUI
import SnapticKit

/// Displays → Automation (PLAN §11): event hooks and custom actions. Every command is an
/// executable with fixed arguments; the path rules of §4.10(1) are checked as you type.
struct AutomationPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    private var automation: AutomationConfig { env.config.value.automation }

    var body: some View {
        Form {
            Section {
                Text(L("Hooks run a program when a display connects or disconnects, or when your Mac sleeps or wakes. Custom actions are programs you start from the menu, a shortcut, or (if you allow it) the command line."))
                    .foregroundStyle(.secondary)
                Text(L("Programs run without Snaptic's permissions, with a minimal environment (SNAPTIC_EVENT, SNAPTIC_DISPLAY_NAME, SNAPTIC_DISPLAY_KEY), and are stopped after 30 seconds. They never run in Safe Mode or while display automation is paused."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let problem = env.context?.spawner.lastProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            hooksSection
            actionsSection
        }
        .formStyle(.grouped)
    }

    // MARK: Hooks

    @ViewBuilder
    private var hooksSection: some View {
        Section {
            if !env.runtime.isEffective(.hooks) {
                featureOff(.hooks, L("Hooks are off."))
            }
            ForEach(automation.hooks) { hook in
                DisclosureGroup {
                    HookEditor(hook: hook, displays: env.runtime.displays,
                               onChange: { updated in updateHook(updated) },
                               onDelete: { env.config.value.automation.hooks.removeAll { $0.id == hook.id } })
                } label: {
                    HStack {
                        Image(systemName: hook.enabled ? "bolt.fill" : "bolt.slash").foregroundStyle(.secondary)
                        Text(hook.name.isEmpty ? L("Untitled hook") : hook.name)
                        Spacer()
                        Text(hook.event.title).foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            Button {
                env.config.value.automation.hooks.append(HookSpec(name: L("New hook"), enabled: false))
            } label: {
                Label(L("Add Hook"), systemImage: "plus")
            }
            .disabled(automation.hooks.count >= AutomationConfig.maxHooks)
        } header: {
            Text(L("Hooks"))
        }
    }

    private func updateHook(_ hook: HookSpec) {
        guard let index = env.config.value.automation.hooks.firstIndex(where: { $0.id == hook.id }) else { return }
        env.config.value.automation.hooks[index] = hook.sanitized()
    }

    // MARK: Actions

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if !env.runtime.isEffective(.customActions) {
                featureOff(.customActions, L("Custom actions are off."))
            }
            ForEach(automation.actions) { action in
                DisclosureGroup {
                    ActionEditor(action: action,
                                 onChange: { updated in updateAction(updated) },
                                 onRun: { _ = env.context?.actions.perform(DisplayActionID(rawValue: "a.custom." + action.id.rawValue),
                                                                       on: .main) },
                                 onDelete: { env.config.value.automation.actions.removeAll { $0.id == action.id } })
                } label: {
                    HStack {
                        Image(systemName: "play.circle").foregroundStyle(.secondary)
                        Text(action.name.isEmpty ? L("Untitled action") : action.name)
                        Spacer()
                        if action.cliAllowed { Text(L("CLI")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Button {
                env.config.value.automation.actions.append(CustomActionSpec(name: L("New action")))
            } label: {
                Label(L("Add Custom Action"), systemImage: "plus")
            }
            .disabled(automation.actions.count >= AutomationConfig.maxActions)
        } header: {
            Text(L("Custom actions"))
        }
    }

    private func updateAction(_ action: CustomActionSpec) {
        guard let index = env.config.value.automation.actions.firstIndex(where: { $0.id == action.id }) else { return }
        env.config.value.automation.actions[index] = action.sanitized()
    }

    private func featureOff(_ feature: DisplayFeature, _ text: String) -> some View {
        HStack {
            Text(text).foregroundStyle(.secondary)
            Spacer()
            if case .unavailable(let reason)? = env.runtime.availability[feature] {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(L("Turn On")) { env.enableFeature(feature) }
            }
        }
    }
}

// MARK: - Editors

/// Executable path, arguments (one per line) and the live rule check.
private struct CommandEditor: View {
    @Binding var command: CommandSpec
    @State private var argumentsText: String

    init(command: Binding<CommandSpec>) {
        _command = command
        _argumentsText = State(initialValue: command.wrappedValue.arguments.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L("Program (full path)"), text: $command.executable)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button(L("Choose…")) { choose() }
            }
            Text(L("Arguments, one per line (at most 8):")).font(.caption)
            TextEditor(text: $argumentsText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 54)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: argumentsText) {
                    command.arguments = argumentsText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                }
            if !command.executable.isEmpty {
                if let refusal = HelperSpawner.checkExecutable(command.executable) ?? KitHookPolicy.checkArguments(command.arguments) {
                    Label(refusal.message, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
                } else {
                    Label(L("This program can run."), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        command.executable = url.path
    }
}

private struct HookEditor: View {
    @State private var hook: HookSpec
    let displays: [DisplayInfo]
    let onChange: (HookSpec) -> Void
    let onDelete: () -> Void

    init(hook: HookSpec, displays: [DisplayInfo], onChange: @escaping (HookSpec) -> Void, onDelete: @escaping () -> Void) {
        _hook = State(initialValue: hook)
        self.displays = displays
        self.onChange = onChange
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Name"), text: $hook.name).textFieldStyle(.roundedBorder)
            Toggle(L("Enabled"), isOn: $hook.enabled)
            Picker(L("When"), selection: $hook.event) {
                ForEach(HookEvent.allCases, id: \.self) { event in Text(event.title).tag(event) }
            }
            if hook.event.isPerDisplay {
                Picker(L("Display"), selection: $hook.display) {
                    Text(L("Any display")).tag(DisplayKey?.none)
                    ForEach(displays) { display in Text(display.name).tag(DisplayKey?.some(display.key)) }
                    if let key = hook.display, !displays.contains(where: { $0.key == key }) {
                        Text(L("A display that isn't connected")).tag(DisplayKey?.some(key))
                    }
                }
            }
            if hook.event == .wakeDelayed {
                Stepper(value: $hook.delaySeconds, in: 1...600, step: 5) {
                    Text(L("Delay: ") + String(Int(hook.delaySeconds)) + L(" s"))
                }
            }
            CommandEditor(command: $hook.command)
            HStack {
                Spacer()
                Button(L("Delete Hook"), role: .destructive, action: onDelete)
            }
        }
        .onChange(of: hook) { onChange(hook) }
    }
}

private struct ActionEditor: View {
    @State private var action: CustomActionSpec
    let onChange: (CustomActionSpec) -> Void
    let onRun: () -> Void
    let onDelete: () -> Void

    init(action: CustomActionSpec, onChange: @escaping (CustomActionSpec) -> Void, onRun: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        _action = State(initialValue: action)
        self.onChange = onChange
        self.onRun = onRun
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Name"), text: $action.name).textFieldStyle(.roundedBorder)
            Toggle(L("Show in the menu"), isOn: $action.showInMenu)
            Toggle(L("Allow from the command line"), isOn: $action.cliAllowed)
            if action.cliAllowed && !action.cliName.isEmpty {
                Text("snaptic action run " + action.cliName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent {
                ShortcutRecorder(combo: $action.shortcut)
            } label: {
                Text(L("Shortcut"))
            }
            CommandEditor(command: $action.command)
            HStack {
                Button(L("Run Now"), action: onRun)
                Spacer()
                Button(L("Delete Action"), role: .destructive, action: onDelete)
            }
        }
        .onChange(of: action) { onChange(action) }
    }
}
