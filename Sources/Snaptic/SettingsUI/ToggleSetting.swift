import SwiftUI
import SnapticKit

/// A switch row: title (+ badge) and an optional one-sentence help that describes the on state. Row switches keep
/// the grouped form's default (small) size; only the page header switch is `.regular` (design B2). A subordinate row
/// is indented 20 pt and shown by the caller only while its parent is on; it is never a smaller control.
/// Precondition missing → the switch is disabled, its help stays, and `disabledReason` + `fix` show as a note under
/// the row. Hardware can't do it → the caller omits the row.
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
        Group {
            if let disabledReason {
                VStack(alignment: .leading, spacing: 4) {
                    toggle.disabled(true)
                    SettingsRowNote(disabledReason, fix: fix)
                }
            } else {
                toggle
            }
        }
        .padding(.leading, subordinate ? 20 : 0)
        .modifier(OptionalSettingsAnchor(anchor))
    }

    private var toggle: some View {
        Toggle(isOn: isOn) {
            titleText
            if let help { Text(help) }
        }
        .accessibilityLabel(title)
        .accessibilityHint(help ?? "")
    }

    private var titleText: Text {
        guard let badge else { return Text(title) }
        return Text(title) + Text("  ") + badge.text
    }
}
