import SwiftUI
import SnapticKit

/// The 0.2 "Protection & Layouts" page id, kept only while `DisplaysModule.settingsPages()` lists it (removed in the
/// step-3 coordinated merge): it shows the 0.3 Saved Layouts page.
struct ProtectionLayoutsPage: View {
    let env: DisplaysPageEnvironment

    var body: some View {
        SavedLayoutsPage(env: env)
    }
}
