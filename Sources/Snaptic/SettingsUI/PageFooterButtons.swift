import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// "Restore <scope> Defaults…" ("Restore Awake Defaults…").
struct RestoreDefaults {
    let scopeName: String
    let destructive: Bool
    let action: @MainActor () -> Void

    var title: String { L("Restore \(scopeName) Defaults…") }
}

/// Page footer: trailing Advanced… and (?) only; Restore Defaults leading only on pages without an Advanced sheet.
struct PageFooterButtons: View {
    let advanced: (() -> Void)?
    let help: SettingsRoute?
    let restoreDefaults: RestoreDefaults?
    /// R5-13.
    let advancedControl: ControlID?
    let restoreControl: ControlID?

    init(advanced: (() -> Void)?, help: SettingsRoute?, restoreDefaults: RestoreDefaults? = nil,
         advancedControl: ControlID? = nil, restoreControl: ControlID? = nil) {
        self.advanced = advanced
        self.help = help
        self.restoreDefaults = restoreDefaults
        self.advancedControl = advancedControl
        self.restoreControl = restoreControl
    }

    var body: some View {
        HStack {
            if let restoreDefaults {
                Button(restoreDefaults.title) { restoreDefaults.action() }
            }
            Spacer()
            if let advanced {
                Button(L("Advanced…")) { advanced() }
            }
        }
    }
}
