import SwiftUI
import SnapticKit

/// The 0.2 Diagnostics page id ("displays.diagnostics"), kept until the step-3 exit removes `settingsPages()`: it
/// shows Display Information, which replaces it (PLAN 0.3 §4.3, §6.2 ✗).
struct DiagnosticsPage: View {
    let env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        DisplayInformationPage(env: env)
    }
}
