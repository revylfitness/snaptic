import SwiftUI
import SnapticKit

/// 520 wide, ≤ 25 controls, grouped form; footer: Restore Defaults… leading (with its confirmation), Done = Return
/// trailing; Esc closes. Never presents another sheet. Search results that live here open it (the page binds the
/// sheet to `SettingsShell.sheetBinding(_:)`) and highlight their row once it has appeared.
struct AdvancedSheet<Content: View>: View {
    let title: String
    let restoreDefaults: RestoreDefaults?
    let content: Content
    /// R5-13: the footer button's search anchor ("general.advanced.resetAll").
    let restoreControl: ControlID?
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    init(_ title: String, restoreDefaults: RestoreDefaults?, @ViewBuilder content: () -> Content) {
        self.init(title, restoreDefaults: restoreDefaults, restoreControl: nil, content: content)
    }

    init(_ title: String, restoreDefaults: RestoreDefaults?, restoreControl: ControlID?,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.restoreDefaults = restoreDefaults
        self.restoreControl = restoreControl
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            SettingsAnchorScroller {
                Form { content }
                    .formStyle(.grouped)
            }
            Divider()
            HStack(spacing: 8) {
                if let restoreDefaults {
                    Button(restoreDefaults.title, role: restoreDefaults.destructive ? .destructive : nil) {
                        restoreDefaults.press { confirming = true }
                    }
                    .modifier(OptionalSettingsAnchor(restoreControl))
                }
                Spacer(minLength: 8)
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(minHeight: 320, idealHeight: 480, maxHeight: 720)
        .modifier(RestoreDefaultsConfirmation(isPresented: $confirming, restore: restoreDefaults))
        .onAppear { SettingsShell.shared.sheetDidAppear() }
        .onExitCommand { dismiss() }
    }
}
