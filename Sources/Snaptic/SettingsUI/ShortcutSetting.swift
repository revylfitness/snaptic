import SwiftUI
import SnapticKit

/// A keyboard shortcut row wrapping `ShortcutRecorder`. A combo another part of Snaptic has registered is refused
/// while recording ("This shortcut is used by Displays."), and a stored combo that lost to another owner shows that
/// owner under the row. `owner` is the name this setting registers its shortcut under.
struct ShortcutSetting: View {
    let title: String
    let help: String?
    let combo: Binding<HotkeyCombo?>
    let owner: String
    let anchor: ControlID?

    init(_ title: String, help: String? = nil, combo: Binding<HotkeyCombo?>, owner: String, anchor: ControlID? = nil) {
        self.title = title
        self.help = help
        self.combo = combo
        self.owner = owner
        self.anchor = anchor
    }

    var body: some View {
        Group {
            if let current = combo.wrappedValue, let message = conflict(current) {
                VStack(alignment: .leading, spacing: 4) {
                    row
                    SettingsRowNote(message)
                }
            } else {
                row
            }
        }
        .modifier(OptionalSettingsAnchor(anchor))
    }

    private var row: some View {
        LabeledContent {
            ShortcutRecorder(combo: combo, validate: { conflict($0) })
        } label: {
            Text(title)
            if let help { Text(help) }
        }
    }

    /// Who else holds this combo, if anyone.
    private func conflict(_ c: HotkeyCombo) -> String? {
        guard let hotkeys = SettingsShell.shared.host?.hotkeys,
              let other = hotkeys.owner(of: c), other != owner else { return nil }
        return L("This shortcut is used by \(other).")
    }
}
