import AppKit
import SwiftUI
import SnapticKit

/// Displays › Automations (owner A; PLAN 0.3 §4.3 sub-page table): the event hooks and custom actions. Each section
/// starts with its feature switch, then its list (rows: Enabled or Show in menu, a summary, Details…) and its Add…
/// button; a row's Details… sheet edits the stored item directly (fixes [UA] B2). No Advanced sheet, so Restore
/// Automations Defaults… sits in the page footer. Budget: 2 settings + 2 lists + 2 buttons = 6 (§4.3 counts).
/// Config is read through slices and live state from the runtime and the automation revision (§4.5), so the page
/// doesn't depend on `DisplaysPageEnvironment` forwarding every config change.
struct AutomationsPage: View, ControlDeclaring {
    typealias Controls = AutomationsPageControls

    static let title = L("Automations")
    static let summary = L("Run a program when displays change.")
    static let symbol = "gearshape.2.fill"
    static let tint = SettingsTint.orange
    static let route = SettingsRoute(Controls.surface)

    let env: DisplaysPageEnvironment

    var body: some View {
        AutomationsContent(env: env)
    }
}

/// The editor sheet a row opened: which list, which item, and the item as it was created when the row is new
/// (closing the sheet with nothing changed then removes it again).
struct AutomationEditTarget: Identifiable {
    enum Kind { case hook, action }
    let kind: Kind
    let itemID: StableID
    var newHook: HookSpec? = nil
    var newAction: CustomActionSpec? = nil

    var id: String { itemID.rawValue }

    /// The shell's sheet id (`SettingsShell.sheetBinding`): the editor table's surface.
    var sheetID: String {
        switch kind {
        case .hook: return HookEditorSheetControls.surface
        case .action: return ActionEditorSheetControls.surface
        }
    }
}

private struct AutomationsContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    /// Bumped by the spawner (last problem, running commands) and the controller.
    @ObservedObject private var revision: ControllerRevision
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var automation: ConfigSlice<DisplaysConfig, AutomationConfig>
    /// The open editor sheet's target; presented through the shell (`sheetBinding`), so a search reveal or a page
    /// change closes it like every other Settings sheet. Kept until `onDismiss` has run.
    @State private var opened: AutomationEditTarget?
    @ObservedObject private var shell: SettingsShell

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.automation))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _automation = StateObject(wrappedValue: ConfigSlice(env.config, \.automation))
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
    }

    var body: some View {
        SettingsPageScaffold(route: AutomationsPage.route) {
            SettingsPageHeader(AutomationsPage.title, summary: AutomationsPage.summary, symbol: AutomationsPage.symbol,
                               tint: AutomationsPage.tint)
            statusSection
            hooksSection
            actionsSection
            PageFooterButtons(advanced: nil, help: AutomationsPage.route, restoreDefaults: restoreDefaults,
                              restoreControl: ControlID("displays.automations.restore"))
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
        .sheet(isPresented: sheetPresented, onDismiss: dropUntouchedNewItem) {
            if let target = opened {
                switch target.kind {
                case .hook: HookEditorSheet(env: env, hookID: target.itemID)
                case .action: ActionEditorSheet(env: env, actionID: target.itemID)
                }
            }
        }
    }

    // MARK: Status

    /// Why programs don't run right now, and the last refusal; each only while true (§4.2 States).
    @ViewBuilder private var statusSection: some View {
        let ctx = env.context
        let safeMode = ctx?.safeMode.isActive ?? false
        let problem = ctx?.spawner.lastProblem
        if safeMode || runtime.isPanicLatched || problem != nil || switcher.notice != nil {
            Section {
                if safeMode {
                    StatusRow(L("Hooks and custom actions don’t run in Safe Mode."), symbol: "lifepreserver")
                }
                if runtime.isPanicLatched, let ctx {
                    StatusRow(L("Display automation is paused, so hooks and actions don’t run."),
                              symbol: "pause.circle.fill", actions: [
                        StatusAction(title: L("Resume Display Automation"),
                                     control: ControlID("displays.automations.status.resume")) {
                            _ = ctx.actions.perform(PanicCoordinator.resumeActionID, on: .all)
                        },
                    ])
                }
                if let problem, let ctx {
                    StatusRow(problem, style: .warning, actions: [
                        StatusAction(title: L("Clear"), control: ControlID("displays.automations.status.clearProblem")) {
                            ctx.spawner.clearProblem()
                        },
                    ])
                }
                if let notice = switcher.notice {
                    StatusRow(notice)
                }
            }
        }
    }

    // MARK: Event hooks

    private var hooks: [HookSpec] { automation.value.hooks }

    @ViewBuilder private var hooksSection: some View {
        Section {
            ToggleSetting(L("Event hooks"), help: Self.hooksHelp,
                          isOn: switcher.binding([.hooks], title: L("Event hooks")),
                          anchor: ControlID("displays.automations.hooks"),
                          disabledReason: switcher.unavailableReason([.hooks]))
            if hooks.isEmpty {
                EmptyListView(L("No Hooks"), symbol: "bolt.horizontal",
                              text: L("Run a program when a display connects or disconnects, or when your Mac sleeps or wakes."),
                              action: StatusAction(title: L("Add Hook…"),
                                                   control: ControlID("displays.automations.addHook")) { addHook() })
                    .modifier(SettingsAnchor(ControlID("displays.automations.hookList")))
            } else {
                ReorderableList(listBinding(\.hooks), onEdit: { edit(hook: $0) }, onDelete: { delete(hook: $0) }) { hook in
                    hookRow(hook, first: hook.id == hooks.first?.id)
                }
                ButtonRow(L("Add Hook…"), control: ControlID("displays.automations.addHook")) { addHook() }
                    .disabled(hooks.count >= AutomationConfig.maxHooks)
            }
        } footer: {
            Text(L("Programs run without Snaptic’s permissions, with a minimal environment (SNAPTIC_EVENT, SNAPTIC_DISPLAY_NAME, SNAPTIC_DISPLAY_KEY), and stop after 30 seconds."))
        }
    }

    private static let hooksHelp = L("Runs a program when displays change, or when your Mac sleeps or wakes.")

    private func hookRow(_ hook: HookSpec, first: Bool) -> some View {
        let summary = hook.summary(displayName: AutomationText.displayName(hook.display, env: env))
        let title = hook.name.isEmpty ? summary : hook.name
        let subtitle = hook.name.isEmpty ? AutomationText.programLine(hook.command) : summary
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(L("Details…")) { edit(hook: hook) }
                .accessibilityLabel(L("Details for \(title)"))
                .modifier(OptionalSettingsAnchor(first ? ControlID("displays.automations.hookDetails") : nil))
            Toggle(L("Run \(title)"), isOn: hookEnabled(hook.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .help(L("Run this hook"))
                .modifier(OptionalSettingsAnchor(first ? ControlID("displays.automations.hookEnabled") : nil))
        }
    }

    private func hookEnabled(_ id: StableID) -> Binding<Bool> {
        AutomationEdit.field(env.config, \.hooks, id, \.enabled, fallback: false) { $0.sanitized() }
    }

    private func addHook() {
        guard hooks.count < AutomationConfig.maxHooks else { return }
        let hook = HookSpec(enabled: true, event: .connect)
        turnOnWithFirstItem(.hooks, title: L("Event hooks"), wasEmpty: hooks.isEmpty)
        env.config.value.automation.hooks.append(hook)
        open(AutomationEditTarget(kind: .hook, itemID: hook.id, newHook: hook))
    }

    private func edit(hook: HookSpec) {
        open(AutomationEditTarget(kind: .hook, itemID: hook.id))
    }

    private func delete(hook: HookSpec) {
        env.config.value.automation.hooks.removeAll { $0.id == hook.id }
    }

    // MARK: Custom actions

    private var actions: [CustomActionSpec] { automation.value.actions }

    @ViewBuilder private var actionsSection: some View {
        Section {
            ToggleSetting(L("Custom actions"), help: Self.actionsHelp,
                          isOn: switcher.binding([.customActions], title: L("Custom actions")),
                          anchor: ControlID("displays.automations.actions"),
                          disabledReason: switcher.unavailableReason([.customActions]))
            if actions.isEmpty {
                EmptyListView(L("No Actions"), symbol: "play.rectangle",
                              text: L("Run your own program from the Displays menu, with a shortcut, or from the command line."),
                              action: StatusAction(title: L("Add Action…"),
                                                   control: ControlID("displays.automations.addAction")) { addAction() })
                    .modifier(SettingsAnchor(ControlID("displays.automations.actionList")))
            } else {
                ReorderableList(listBinding(\.actions), onEdit: { edit(action: $0) },
                                onDelete: { delete(action: $0) }) { action in
                    actionRow(action, first: action.id == actions.first?.id)
                }
                ButtonRow(L("Add Action…"), control: ControlID("displays.automations.addAction")) { addAction() }
                    .disabled(actions.count >= AutomationConfig.maxActions)
            }
        } footer: {
            Text(L("Checked actions appear in the Displays menu under Actions, in this order. Shortcuts are also listed in Keyboard › Keyboard Shortcuts."))
        }
    }

    private static let actionsHelp = L("Your own programs in the menu and as shortcuts.")

    private func actionRow(_ action: CustomActionSpec, first: Bool) -> some View {
        let title = action.name.isEmpty ? L("Untitled action") : action.name
        return HStack(spacing: 10) {
            Toggle(L("Show \(title) in the menu"), isOn: showInMenu(action.id))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(L("Show in the Displays menu"))
                .disabled(action.name.isEmpty)
                .modifier(OptionalSettingsAnchor(first ? ControlID("displays.automations.actionShowInMenu") : nil))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(action.name.isEmpty ? Color.secondary : Color.primary)
                Text(AutomationText.actionLine(action))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(L("Details…")) { edit(action: action) }
                .accessibilityLabel(L("Details for \(title)"))
                .modifier(OptionalSettingsAnchor(first ? ControlID("displays.automations.actionDetails") : nil))
        }
    }

    private func showInMenu(_ id: StableID) -> Binding<Bool> {
        AutomationEdit.field(env.config, \.actions, id, \.showInMenu, fallback: false) { $0.sanitized() }
    }

    private func addAction() {
        guard actions.count < AutomationConfig.maxActions else { return }
        let action = CustomActionSpec(showInMenu: true)
        turnOnWithFirstItem(.customActions, title: L("Custom actions"), wasEmpty: actions.isEmpty)
        env.config.value.automation.actions.append(action)
        open(AutomationEditTarget(kind: .action, itemID: action.id, newAction: action))
    }

    private func edit(action: CustomActionSpec) {
        open(AutomationEditTarget(kind: .action, itemID: action.id))
    }

    private func delete(action: CustomActionSpec) {
        env.config.value.automation.actions.removeAll { $0.id == action.id }
    }

    // MARK: Shared

    /// The whole list, for reordering (one config write per move).
    private func listBinding<E: Equatable>(_ list: WritableKeyPath<AutomationConfig, [E]>) -> Binding<[E]> {
        let store = env.config
        return Binding(get: { store.value.automation[keyPath: list] },
                       set: { new in
                           if store.value.automation[keyPath: list] != new { store.value.automation[keyPath: list] = new }
                       })
    }

    /// Adding the first item while its switch is off turns the switch on (like Awake's first rule), so the new hook
    /// or action works once it has a program.
    private func turnOnWithFirstItem(_ feature: DisplayFeature, title: String, wasEmpty: Bool) {
        guard wasEmpty, !FeatureGraph.rawState(feature, in: features.value),
              switcher.unavailableReason([feature]) == nil else { return }
        switcher.binding([feature], title: title).wrappedValue = true
    }

    private func open(_ target: AutomationEditTarget) {
        opened = target
        shell.openSheet = target.sheetID
    }

    /// Open while the shell's sheet is the opened target's editor.
    private var sheetPresented: Binding<Bool> {
        guard let id = opened?.sheetID else { return .constant(false) }
        return shell.sheetBinding(id)
    }

    /// A row added with Add… and closed without a change is removed again, so Cancel-like closing leaves nothing
    /// behind.
    private func dropUntouchedNewItem() {
        guard let target = opened else { return }
        opened = nil
        var value = env.config.value
        if let new = target.newHook, value.automation.hooks.first(where: { $0.id == target.itemID }) == new {
            value.automation.hooks.removeAll { $0.id == target.itemID }
        } else if let new = target.newAction,
                  value.automation.actions.first(where: { $0.id == target.itemID }) == new {
            value.automation.actions.removeAll { $0.id == target.itemID }
        } else {
            return
        }
        env.config.value = value
    }

    private var restoreDefaults: RestoreDefaults {
        let store = env.config
        return RestoreDefaults(title: L("Restore Automations Defaults…"),
                               question: L("Restore Automations settings to their defaults?"),
                               message: L("Every event hook and custom action is deleted. Your other Snaptic settings stay as they are."),
                               button: L("Delete All"), destructive: true) {
            store.value = store.value.restoringDefaults(scope: .automations)
        }
    }
}

// MARK: - Shared with the editor sheets

/// Bindings into one stored hook or action, by id. Each write is one config write of the sanitized item; a write
/// to an item that was deleted meanwhile is dropped.
@MainActor enum AutomationEdit {
    static func field<E: Identifiable & Equatable, V: Equatable>(
        _ store: ConfigStore<DisplaysConfig>, _ list: WritableKeyPath<AutomationConfig, [E]>, _ id: E.ID,
        _ path: WritableKeyPath<E, V>, fallback: V, sanitize: @escaping (E) -> E
    ) -> Binding<V> {
        Binding(get: { store.value.automation[keyPath: list].first { $0.id == id }?[keyPath: path] ?? fallback },
                set: { newValue in
                    var value = store.value
                    guard let index = value.automation[keyPath: list].firstIndex(where: { $0.id == id }) else { return }
                    var item = value.automation[keyPath: list][index]
                    guard item[keyPath: path] != newValue else { return }
                    item[keyPath: path] = newValue
                    value.automation[keyPath: list][index] = sanitize(item)
                    store.value = value
                })
    }
}

/// Row and sheet text that isn't a control label.
@MainActor enum AutomationText {
    /// The name of a hook's display: connected, then remembered, then a short key; nil for "any display".
    static func displayName(_ key: DisplayKey?, env: DisplaysPageEnvironment) -> String? {
        guard let key else { return nil }
        if let online = env.runtime.displays.first(where: { $0.key == key }) { return online.name }
        let identity = env.config.value.perDisplay[key]?.identity
        return identity?.customName ?? identity?.lastKnownName ?? L("Display \(DiagnosticsText.shortKey(key))")
    }

    /// "Runs dock.sh" or "No program chosen".
    static func programLine(_ command: CommandSpec) -> String {
        let name = command.programName
        return name.isEmpty ? L("No program chosen") : L("Runs \(name)")
    }

    /// "Runs dim.sh · ⌃⌥D · Command line".
    static func actionLine(_ action: CustomActionSpec) -> String {
        var parts = [programLine(action.command)]
        if let combo = action.shortcut { parts.append(HotkeyRules.displayString(combo)) }
        if action.cliAllowed { parts.append(L("Command line")) }
        return parts.joined(separator: " · ")
    }
}

/// The program and its arguments, as two form sections of an editor sheet: the path field with Choose… and the
/// live rule check (§4.10(1), run off main after a short pause while typing), then one field per argument (≤ 8).
/// The sheet passes its own control ids (lint L15: literals stay in the file that names the table).
struct AutomationCommandSections: View {
    let command: Binding<CommandSpec>
    let programControl: ControlID
    let chooseControl: ControlID
    let argumentsControl: ControlID
    /// The last finished path check: it walks the file system, so it runs off main.
    @State private var checked: PathCheck?

    private struct PathCheck: Equatable {
        let path: String
        let refusal: HookRefusal?
    }

    var body: some View {
        Section {
            TextField(L("Program"), text: executable, prompt: Text(verbatim: "/usr/local/bin/tool"))
                .font(.system(.body, design: .monospaced))
                .modifier(SettingsAnchor(programControl))
            ButtonRow(L("Choose…"), help: L("Pick the program in Finder."), control: chooseControl) { choose() }
            checkRow
        } header: {
            Text(L("Program"))
        } footer: {
            Text(L("A program or script file with its full path. It runs directly, never through a shell."))
        }
        .task(id: command.wrappedValue.executable) { await check(command.wrappedValue.executable) }

        Section {
            ForEach(Array(command.wrappedValue.arguments.indices), id: \.self) { index in
                HStack(spacing: 6) {
                    TextField(L("Argument \(index + 1)"), text: argument(index))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                    Button {
                        removeArgument(index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Remove this argument"))
                    .accessibilityLabel(L("Remove argument \(index + 1)"))
                }
            }
            ButtonRow(L("Add Argument"), help: command.wrappedValue.arguments.isEmpty ? L("No arguments.") : nil) {
                addArgument()
            }
            .disabled(command.wrappedValue.arguments.count >= KitHookPolicy.maxArguments)
            .modifier(SettingsAnchor(argumentsControl))
        } header: {
            Text(L("Arguments"))
        } footer: {
            Text(L("Passed to the program as they are, at most \(KitHookPolicy.maxArguments)."))
        }
    }

    /// "This program can run." or why not, for the current path only.
    @ViewBuilder private var checkRow: some View {
        let path = command.wrappedValue.executable
        if !path.isEmpty {
            if let checked, checked.path == path {
                if let refusal = checked.refusal ?? KitHookPolicy.checkArguments(command.wrappedValue.arguments) {
                    StatusRow(refusal.message, style: .error)
                } else {
                    StatusRow(L("This program can run."), symbol: "checkmark.circle.fill")
                }
            } else {
                StatusRow(L("Checking the program…"), symbol: "hourglass")
            }
        }
    }

    /// Longer paths than the policy allows are refused as you type, never cut.
    private var executable: Binding<String> {
        Binding(get: { command.wrappedValue.executable },
                set: { path in
                    guard path.utf8.count <= KitHookPolicy.maxPathBytes, path != command.wrappedValue.executable else { return }
                    command.wrappedValue.executable = path
                })
    }

    private func argument(_ index: Int) -> Binding<String> {
        Binding(get: { command.wrappedValue.arguments.indices.contains(index) ? command.wrappedValue.arguments[index] : "" },
                set: { text in
                    var c = command.wrappedValue
                    guard c.arguments.indices.contains(index), c.arguments[index] != text else { return }
                    c.arguments[index] = text
                    command.wrappedValue = c
                })
    }

    private func addArgument() {
        var c = command.wrappedValue
        guard c.arguments.count < KitHookPolicy.maxArguments else { return }
        c.arguments.append("")
        command.wrappedValue = c
    }

    private func removeArgument(_ index: Int) {
        var c = command.wrappedValue
        guard c.arguments.indices.contains(index) else { return }
        c.arguments.remove(at: index)
        command.wrappedValue = c
    }

    /// Re-checked when the path changes (after a short pause while typing); a newer path cancels the older check.
    private func check(_ path: String) async {
        guard !path.isEmpty else { return }
        if checked != nil { try? await Task.sleep(nanoseconds: 250_000_000) }
        guard !Task.isCancelled else { return }
        let refusal = await Task.detached(priority: .userInitiated) { HelperSpawner.checkExecutable(path) }.value
        guard !Task.isCancelled else { return }
        checked = PathCheck(path: path, refusal: refusal)
    }

    /// A standard open panel in its own window (never a sheet on the editor sheet, §1.5).
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = L("Choose")
        panel.message = L("Choose the program to run.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executable.wrappedValue = url.path
    }
}
