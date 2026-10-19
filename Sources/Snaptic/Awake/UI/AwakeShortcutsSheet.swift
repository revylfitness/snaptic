import SwiftUI
import SnapticKit

/// Awake › Keyboard Shortcuts… (owner: G; PLAN 0.3 §4.3 "Keyboard", design m2, R5-12): Keep Awake, Keep Display On,
/// Start “<preset>” for the first four sessions, and Pause or Resume Rules (where migration M1 puts the 0.2 display-sleep
/// shortcut). All unbound by default; AwakeAutomation registers them under the owner name "Awake".
struct AwakeShortcutsSheet: View, ControlDeclaring {
    typealias Controls = AwakePageControls

    let env: AwakePageEnvironment
    @StateObject private var sessions: ConfigSlice<AwakeConfig, AwakeSessionsConfig>
    @StateObject private var shortcuts: ConfigSlice<AwakeConfig, LossyMap<AwakeActionID, HotkeyCombo>>

    init(env: AwakePageEnvironment) {
        self.env = env
        _sessions = StateObject(wrappedValue: ConfigSlice(env.config, \.sessions))
        _shortcuts = StateObject(wrappedValue: ConfigSlice(env.config, \.shortcuts))
    }

    var body: some View {
        let presets = Array(sessions.value.presets.prefix(4))
        AdvancedSheet(L("Awake Keyboard Shortcuts"), restoreDefaults: nil) {
            Section {
                ShortcutSetting(L("Keep Awake"), help: L("Starts your default session, or turns Keep Awake off."),
                                combo: combo(.toggle), owner: owner, anchor: ControlID("awake.page.shortcut.toggle"))
                ShortcutSetting(L("Keep Display On"), help: L("Keeps the display on during a session, or lets it sleep."),
                                combo: combo(.keepDisplayOn), owner: owner,
                                anchor: ControlID("awake.page.shortcut.keepDisplayOn"))
            }
            Section {
                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    if let action = AwakeActionID.preset(index + 1) {
                        let title = L("Start ") + AwakeDetail.quoted(preset.title(AwakeFormat.text))
                        if index == 0 {
                            ShortcutSetting(title, help: L("Starts this session."), combo: combo(action), owner: owner,
                                            anchor: ControlID("awake.page.shortcut.preset"))
                        } else {
                            ShortcutSetting(title, help: L("Starts this session."), combo: combo(action), owner: owner)
                        }
                    }
                }
            } header: {
                Text(L("Sessions"))
            } footer: {
                Text(L("The first four sessions in Sessions in the menu, in that order."))
            }
            Section {
                ShortcutSetting(L("Pause or Resume Rules"), help: L("Pauses rules for 1 hour, or resumes them."),
                                combo: combo(.pauseAutomatic), owner: owner,
                                anchor: ControlID("awake.page.shortcut.pauseRules"))
            } footer: {
                Text(L("Shortcuts work in any app while Awake is on."))
            }
        }
    }

    /// The name hotkeys are registered under (AwakeAutomation), so the conflict note names other owners only.
    private var owner: String { L("Awake") }

    private func combo(_ action: AwakeActionID) -> Binding<HotkeyCombo?> {
        let config = env.config
        return Binding(get: { config.value.shortcuts[action] },
                       set: { new in
                           if config.value.shortcuts[action] != new { config.value.shortcuts[action] = new }
                       })
    }
}
