import SwiftUI
import SnapticKit

/// The 0.2 "Automation" page id (`displays.automation`), still listed by `DisplaysModule.settingsPages()` until the
/// step-3b merge removes that list; it shows the 0.3 page, Displays › Automations (`AutomationsPage`). This file is
/// deleted with the list (PLAN 0.3 §6.2 ✗).
struct AutomationPage: View {
    let env: DisplaysPageEnvironment

    var body: some View {
        AutomationsPage(env: env)
    }
}
