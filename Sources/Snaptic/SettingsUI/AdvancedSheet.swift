import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// 520 wide, ≤ 25 controls, Done = Return trailing; Restore Defaults… leading in its footer.
struct AdvancedSheet<Content: View>: View {
    let title: String
    let restoreDefaults: RestoreDefaults?
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, restoreDefaults: RestoreDefaults?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.restoreDefaults = restoreDefaults
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Form { content }.formStyle(.grouped)
            HStack {
                if let restoreDefaults {
                    Button(restoreDefaults.title) { restoreDefaults.action() }
                }
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520)
    }
}
