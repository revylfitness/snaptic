import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

struct ToggleSetting: View {
    let title: String
    let help: String?
    let isOn: Binding<Bool>
    let subordinate: Bool
    let anchor: ControlID?
    let badge: SettingsBadge?
    let disabledReason: String?
    let fix: StatusAction?

    init(_ title: String, help: String? = nil, isOn: Binding<Bool>, subordinate: Bool = false,
         anchor: ControlID? = nil, badge: SettingsBadge? = nil, disabledReason: String? = nil, fix: StatusAction? = nil) {
        self.title = title
        self.help = help
        self.isOn = isOn
        self.subordinate = subordinate
        self.anchor = anchor
        self.badge = badge
        self.disabledReason = disabledReason
        self.fix = fix
    }

    var body: some View {
        Toggle(isOn: isOn) {
            Text(title)
            if let help { Text(help) }
        }
        .disabled(disabledReason != nil)
        .padding(.leading, subordinate ? 20 : 0)
    }
}
