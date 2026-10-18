import AppKit
import SwiftUI
import SnapticKit

/// Window Switcher › More Shortcuts… (H; PLAN 0.3 §4.3, design m12): every switcher shortcut after the primary
/// one, each with its own options and Delete Shortcut; Add Shortcut (up to `Config.maxShortcuts`); and the Gather
/// Windows shortcut. Opened from the page's More Shortcuts… row.
struct SwitcherShortcutsSheet: View, ControlDeclaring {
    typealias Controls = SwitcherShortcutsSheetControls
    @ObservedObject var settings: AppSettings
    let module: WindowSwitcherModule

    private var others: [Shortcut] { Array(settings.config.shortcuts.dropFirst()) }

    var body: some View {
        AdvancedSheet(L("More Shortcuts"), restoreDefaults: nil) {
            if others.isEmpty {
                Section {
                    EmptyListView(L("No Other Shortcuts"), symbol: "keyboard",
                                  text: L("Add a shortcut that shows only the active app, uses another style, or lists every Space."),
                                  action: nil)
                }
            }
            ForEach(others) { shortcut in
                ExtraShortcutSection(settings: settings, id: shortcut.id)
            }
            Section {
                ButtonRow(L("Add Shortcut"), symbol: "plus", control: ControlID("switcher.shortcuts.add")) { add() }
                    .disabled(settings.config.shortcuts.count >= Config.maxShortcuts)
            }
            Section {
                ShortcutSetting(L("Gather windows"),
                                help: L("Moves every window onto the display under the pointer. Snaptic asks first."),
                                combo: SwitcherBinding.config(settings, \.gatherShortcut), owner: L("Gather windows"),
                                anchor: ControlID("switcher.shortcuts.gather"))
                if let problem = module.gatherShortcutProblem {
                    SettingsRowNote(problem)
                }
            } header: {
                Text(L("Gather windows"))
            } footer: {
                Text(L("Needs Accessibility. The menu's Gather Windows on This Display does the same without asking."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Adds the first modifier and key pair that isn't taken (⌥`, ⌘⇥, …), showing all windows as icons.
    private func add() {
        let shortcuts = settings.config.shortcuts
        guard shortcuts.count < Config.maxShortcuts else { return }
        let preferred: [(ModifierKey, Int)] = [
            (.option, KeyCode.tab), (.option, KeyCode.backtick), (.command, KeyCode.tab), (.command, KeyCode.backtick),
            (.option, KeyCode.space), (.control, KeyCode.backtick),
        ]
        let candidates = preferred + Keys.choices.filter { $0.code != KeyCode.tab }.map { (ModifierKey.option, $0.code) }
        for (modifier, key) in candidates {
            let shortcut = Shortcut(modifier: modifier, keyCode: key, scope: .allWindows, style: .icons)
            if !shortcuts.contains(where: { $0.sameKeys(as: shortcut) }) {
                settings.config.shortcuts.append(shortcut)
                return
            }
        }
    }
}

/// One additional shortcut: its keys and options, a note when it can't act, and Delete Shortcut… (asks first).
private struct ExtraShortcutSection: View {
    @ObservedObject var settings: AppSettings
    let id: UUID
    @State private var confirmingDelete = false

    private var thumbnailsOn: Bool { settings.config.isOn(.thumbnails) }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L("Shortcut")) {
                    ShortcutKeysPicker(settings: settings, id: id)
                }
                if let note = SwitcherBinding.note(settings, id: id) {
                    SettingsRowNote(note)
                }
            }
            .modifier(SettingsAnchor(ControlID("switcher.shortcuts.list")))
            PickerSetting(L("Show"), selection: SwitcherBinding.shortcut(settings, id: id, \.scope),
                          options: SwitcherBinding.scopeOptions, style: .popUp, defaultValue: nil)
            PickerSetting(L("Style"), selection: SwitcherBinding.style(settings, id: id),
                          options: SwitcherBinding.styleOptions(thumbnailsOn: thumbnailsOn), style: .segmented,
                          defaultValue: nil)
            PickerSetting(L("Windows from"), selection: SwitcherBinding.spaces(settings, id: id),
                          options: SwitcherBinding.spacesOptions, style: .popUp,
                          defaultValue: nil)
            ToggleSetting(L("Include minimized and hidden windows"),
                          isOn: SwitcherBinding.shortcut(settings, id: id, \.includeMinimized))
            ToggleSetting(L("Include apps with no open windows"),
                          isOn: SwitcherBinding.windowless(settings, id: id))
            ToggleSetting(L("One entry per app"), help: L("Lists each app once, with its most recent window."),
                          isOn: SwitcherBinding.shortcut(settings, id: id, \.oneWindowPerApp))
            ButtonRow(L("Delete Shortcut…"), role: .destructive, control: ControlID("switcher.shortcuts.delete")) {
                confirmingDelete = true
            }
            .alert(L("Delete “\(title)”?"), isPresented: $confirmingDelete) {
                Button(L("Delete"), role: .destructive) { settings.config.shortcuts.removeAll { $0.id == id } }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("This shortcut and its options are removed."))
            }
        } header: {
            Text(title)
        }
    }

    private var title: String {
        guard let index = SwitcherBinding.index(settings, id: id) else { return "" }
        return settings.config.shortcuts[index].displayName
    }
}
