import SwiftUI
import SnapticKit

/// Displays › Advanced › **Confirm display changes** (owner: B; PLAN 0.3 §4.3 Advanced group 2, §4.4 duplicates 1
/// and 2, §4.6 M6). One section for a grouped `Form`: F's Advanced sheet composes it as `ConfirmChangesSection(env:)`
/// (`ConfirmChangesSection()` finds the environment through the shell); until phase 3b removes the 0.2 page list the
/// Safety page shows it too.
///
/// Live updates (§4.5): settings come from a `ConfigSlice` of `safety`, so other Displays writes don't re-render it;
/// the pause status and the shortcut's registration come from `revision(.diagnostics)`, which PanicCoordinator and
/// the guard client bump. No timers, no `objectWillChange` pokes.
struct ConfirmChangesSection: View, ControlDeclaring {
    typealias Controls = ConfirmChangesSectionControls
    private let env: DisplaysPageEnvironment?

    /// The Displays module's page environment, found through the Settings shell.
    init() {
        env = (SettingsShell.shared.host?.module(.displays) as? DisplaysModule)?.pageEnvironment
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env {
            ConfirmChangesContent(env: env)
        } else {
            Section(L("Confirm display changes")) {
                StatusRow(L("Displays settings aren’t available right now."), style: .warning)
            }
        }
    }
}

private struct ConfirmChangesContent: View {
    typealias Controls = ConfirmChangesSectionControls
    let env: DisplaysPageEnvironment
    @StateObject private var safety: ConfigSlice<DisplaysConfig, SafetyConfig>
    @ObservedObject private var revision: ControllerRevision

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _safety = StateObject(wrappedValue: ConfigSlice(env.config, \.safety))
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.diagnostics))
    }

    var body: some View {
        Section {
            if env.runtime.isPanicLatched {
                StatusRow(L("Display automation is paused."), symbol: "pause.circle.fill", actions: [
                    StatusAction(title: L("Resume Display Automation"),
                                 control: ControlID("displays.advanced.confirm.resume")) { [env] in
                        env.context?.panic.resume()
                    },
                ])
            }
            PickerSetting(L("Confirm resolution changes"),
                          selection: SettingsBinding.store(env.config, \.safety.confirmResolution),
                          options: [
                              PickerOption(ConfirmResolutionChanges.newModesOnly, L("For new resolutions"),
                                           help: L("Asks for a resolution you haven’t kept on that display before.")),
                              PickerOption(ConfirmResolutionChanges.always, L("For every change"),
                                           help: L("Asks every time a resolution changes.")),
                              PickerOption(ConfirmResolutionChanges.neverForPublic, L("Only for hidden resolutions"),
                                           help: L("Asks only for resolutions macOS doesn’t list itself.")),
                          ],
                          defaultValue: .newModesOnly,
                          anchor: ControlID("displays.advanced.confirm.resolution"))
            StepperSetting(L("Revert after"), help: L("Without an answer, the change is undone after this time."),
                           value: SettingsBinding.store(env.config, \.safety.confirmSeconds),
                           in: SafetyConfig.confirmSecondsRange, defaultValue: SafetyConfig.defaultConfirmSeconds,
                           format: .seconds, anchor: ControlID("displays.advanced.confirm.revertAfter"))
            ToggleSetting(L("Tell me when displays were restored"),
                          help: L("After Snaptic quits unexpectedly, a notice says which changes were undone."),
                          isOn: SettingsBinding.store(env.config, \.safety.announceRecovery),
                          anchor: ControlID("displays.advanced.confirm.announceRecovery"))
            shortcutRows
            allowedRows
        } header: {
            Text(L("Confirm display changes"))
        } footer: {
            Text(L("Risky changes ask “Keep this change?” on every display. Esc or no answer undoes them, even if Snaptic stops responding."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Restore All Displays shortcut (M6: the 0.2 fields with their 0.2 meanings)

    private var shortcut: Binding<HotkeyCombo?> {
        let store = env.config
        return Binding(get: { store.value.safety.panicShortcutShown },
                       set: { combo in
                           let next = store.value.safety.settingPanicShortcut(combo)
                           if next != store.value.safety { store.value.safety = next }
                       })
    }

    @ViewBuilder private var shortcutRows: some View {
        let state = safety.value.panicShortcutState
        ShortcutSetting(L("Restore All Displays"), help: shortcutHelp(state), combo: shortcut,
                        owner: PanicCoordinator.shortcutOwner,
                        anchor: ControlID("displays.advanced.confirm.shortcut"))
        if let note = registrationNote(state) {
            SettingsRowNote(note)
        }
        if state != .standard {
            ButtonRow(L("Use Default Shortcut"),
                      help: L("Back to \(HotkeyRules.displayString(SafetyConfig.defaultPanicHotkey))."), subordinate: true,
                      control: ControlID("displays.advanced.confirm.useDefaultShortcut")) { [env] in
                let next = env.config.value.safety.usingDefaultPanicShortcut()
                if next != env.config.value.safety { env.config.value.safety = next }
            }
        }
    }

    private func shortcutHelp(_ state: PanicShortcutState) -> String {
        let standard = HotkeyRules.displayString(SafetyConfig.defaultPanicHotkey)
        let fallback = HotkeyRules.displayString(SafetyConfig.fallbackPanicHotkey)
        switch state {
        case .standard:
            return L("Default (\(standard)). If another app uses it, \(fallback) works instead.")
        case .custom:
            return L("If another app uses it, \(standard) works instead.")
        case .off:
            return L("No shortcut. If a display goes dark, use Restore All Displays in the menu.")
        }
    }

    /// Why the shortcut that works differs from the one shown, while Displays runs.
    private func registrationNote(_ state: PanicShortcutState) -> String? {
        guard let panic = env.context?.panic else { return nil }
        if let problem = panic.hotkeyProblem { return problem }
        if state == .off, let registered = panic.registeredHotkey {
            return L("\(HotkeyRules.displayString(registered)) still works while Snaptic keeps a display off, mirrored, or dimmed.")
        }
        return nil
    }

    // MARK: Allowed without asking (the single list; §4.4 duplicate 2)

    @ViewBuilder private var allowedRows: some View {
        let allowed = safety.value.preConfirmAllowed.values
        let keys = allowed.keys.sorted { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
        LabeledContent {
            Text(keys.isEmpty ? L("None") : keys.count == 1 ? L("1 display") : L("\(keys.count) displays"))
                .foregroundStyle(.secondary)
        } label: {
            Text(L("Allowed without asking"))
            Text(L("Input and power changes you chose not to confirm again."))
        }
        .modifier(SettingsAnchor(ControlID("displays.advanced.confirm.allowedWithoutAsking")))
        ForEach(keys, id: \.self) { key in
            let list = allowed[key] ?? PreConfirmAllowList()
            LabeledContent {
                Button(L("Ask Again")) { [env] in
                    env.config.value.safety.preConfirmAllowed[key] = nil
                }
                .accessibilityLabel(L("Ask again for \(displayName(key))"))
                .accessibilityIdentifier(ControlID("displays.advanced.confirm.askAgain").rawValue)
            } label: {
                Text(displayName(key))
                Text(list.descriptions.joined(separator: ", "))
            }
            .padding(.leading, 20)
        }
    }

    private func displayName(_ key: DisplayKey) -> String {
        if let info = env.runtime.displays.first(where: { $0.key == key }) { return info.name }
        let identity = env.config.value.perDisplay[key]?.identity
        return identity?.customName ?? identity?.lastKnownName ?? L("A display that isn’t connected")
    }
}
