import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Wraps ShortcutRecorder; shows conflicts by owner.
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
        LabeledContent(title) {
            ShortcutRecorder(combo: combo)
        }
    }
}
