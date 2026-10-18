import SwiftUI
import SnapticKit

/// Keyboard › Keyboard Shortcuts… (owner: C; PLAN 0.3 §4.3 Keyboard, §4.4 duplicates 5 and 14): one grouped list of
/// every Displays action — Brightness, Color, Volume and contrast, Inputs and power, Resolution (incl. favorites),
/// Arrangement, Picture in Picture, Tools, Custom actions (Kit `DisplayShortcutGroup`) — with a filter field. A
/// shortcut is stored in `keys.shortcuts` (KeysController registers it under the action's title). Restore All
/// Displays is a mirror of its one home, Displays › Advanced › Confirm display changes: it edits `SafetyConfig`
/// through `settingPanicShortcut`, never `keys.shortcuts`. Never presents another sheet.
struct KeyboardShortcutsSheet: View, ControlDeclaring {
    typealias Controls = KeyboardPageControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var keysRevision: ControllerRevision
    @ObservedObject private var safetyRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var shortcuts: ConfigSlice<DisplaysConfig, LossyMap<DisplayActionID, HotkeyCombo>>
    @StateObject private var safety: ConfigSlice<DisplaysConfig, SafetyConfig>
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @State private var filter = ""

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _keysRevision = ObservedObject(wrappedValue: env.runtime.revision(.keys))
        _safetyRevision = ObservedObject(wrappedValue: env.runtime.revision(.diagnostics))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _shortcuts = StateObject(wrappedValue: ConfigSlice(env.config, \.keys.shortcuts))
        _safety = StateObject(wrappedValue: ConfigSlice(env.config, \.safety))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    /// Not in the list: Restore All Displays has its own row (its home is Confirm display changes), and the 0.2
    /// sleep-prevention toggle moved to Awake.
    private static let excluded: Set<DisplayActionID> = [PanicCoordinator.restoreActionID,
                                                         DisplayActionID(rawValue: "d.sleepPreventionToggle")]

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        AdvancedSheet(L("Keyboard Shortcuts"), restoreDefaults: nil) {
            Section {
                TextField(L("Filter"), text: $filter, prompt: Text(L("Filter shortcuts")))
                    .modifier(SettingsAnchor(ControlID("displays.keyboard.shortcuts.list")))
            } footer: {
                Text(L("Shortcuts act on the display the brightness keys change. They work without Accessibility."))
            }
            if let context {
                if !runtime.isEffective(.shortcuts) {
                    CFeatureOffSection(title: L("Keyboard shortcuts"), feature: .shortcuts,
                                       isOn: FeatureGraph.rawState(.shortcuts, in: features.value), context: context,
                                       switcher: switcher)
                }
                groups(context)
            } else {
                CDisplaysOffSection(runtime: runtime, running: host.isRunning(.displays))
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    // MARK: Groups

    private struct Row: Identifiable {
        let action: Action
        var id: DisplayActionID { action.id }
    }

    @ViewBuilder
    private func groups(_ context: DisplaysContext) -> some View {
        let rows = actions(context)
        let restoreAllShown = DisplayShortcutGroup.matches(title: PanicCoordinator.shortcutOwner, group: .tools,
                                                           query: filter)
        if rows.isEmpty && !restoreAllShown {
            Section {
                Text(L("No shortcuts match “\(filter)”.")).foregroundStyle(.secondary)
            }
        }
        ForEach(DisplayShortcutGroup.allCases, id: \.self) { group in
            let members = rows.filter { DisplayShortcutGroup.group(for: $0.action.id.rawValue) == group }
            if !members.isEmpty || (group == .tools && restoreAllShown) {
                Section {
                    ForEach(members) { row in
                        actionRow(context, row.action)
                    }
                    if group == .tools && restoreAllShown {
                        restoreAllRows(context)
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
    }

    /// Registered actions whose feature runs (or that already have a shortcut), filtered and sorted by title.
    private func actions(_ context: DisplaysContext) -> [Row] {
        let stored = shortcuts.value
        return context.actions.all
            .filter { !Self.excluded.contains($0.id) }
            .filter { runtime.isEffective($0.feature) || stored[$0.id] != nil }
            .filter { DisplayShortcutGroup.matches(title: $0.title, group: DisplayShortcutGroup.group(for: $0.id.rawValue),
                                                   query: filter) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { Row(action: $0) }
    }

    private func actionRow(_ context: DisplaysContext, _ action: Action) -> some View {
        let id = action.id
        let config = env.config
        let combo = Binding<HotkeyCombo?>(get: { config.value.keys.shortcuts[id] }, set: { combo in
            guard config.value.keys.shortcuts[id] != combo else { return }
            if let controller = context.mediaKeys.keysController {
                controller.setShortcut(combo, for: id)
            } else {
                config.value.keys.shortcuts[id] = combo
            }
        })
        let help: String?
        if let problem = context.mediaKeys.keysController?.hotkeyProblems[id] {
            help = problem
        } else if !runtime.isEffective(action.feature) {
            help = L("Needs \(DisplaysUIText.title(action.feature)).")
        } else {
            help = nil
        }
        return ShortcutSetting(action.title, help: help, combo: combo, owner: action.title,
                               anchor: ControlID("displays.keyboard.shortcuts.action"))
    }

    // MARK: Restore All Displays (mirror of Confirm display changes)

    @ViewBuilder
    private func restoreAllRows(_ context: DisplaysContext) -> some View {
        let state = safety.value.panicShortcutState
        let config = env.config
        let combo = Binding<HotkeyCombo?>(get: { config.value.safety.panicShortcutShown }, set: { combo in
            let next = config.value.safety.settingPanicShortcut(combo)
            if next != config.value.safety { config.value.safety = next }
        })
        ShortcutSetting(PanicCoordinator.shortcutOwner, help: restoreAllHelp(state, context), combo: combo,
                        owner: PanicCoordinator.shortcutOwner, anchor: ControlID("displays.keyboard.shortcuts.restoreAll"))
        if state != .standard {
            ButtonRow(L("Use Default Shortcut"), control: ControlID("displays.keyboard.shortcuts.useDefaultRestoreAll")) {
                let next = config.value.safety.usingDefaultPanicShortcut()
                if next != config.value.safety { config.value.safety = next }
            }
        }
    }

    private func restoreAllHelp(_ state: PanicShortcutState, _ context: DisplaysContext) -> String {
        if let problem = context.panic.hotkeyProblem { return problem }
        let standard = HotkeyRules.displayString(SafetyConfig.defaultPanicHotkey)
        switch state {
        case .standard:
            return L("Default (\(standard)). Also in Displays › Advanced › Confirm display changes.")
        case .custom:
            return L("If another app uses it, \(standard) works instead. Also in Displays › Advanced.")
        case .off:
            return L("No shortcut. If a display goes dark, use Restore All Displays in the menu.")
        }
    }
}
