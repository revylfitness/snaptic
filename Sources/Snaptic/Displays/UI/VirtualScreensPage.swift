import SwiftUI
import SnapticKit

/// The 0.2 "Virtual Screens & HiDPI" page id, kept only while `DisplaysModule.settingsPages()` lists it (removed in
/// the step-3 coordinated merge): it shows the 0.3 Virtual Displays page.
struct VirtualScreensPage: View {
    let env: DisplaysPageEnvironment

    var body: some View {
        VirtualDisplaysPage(env: env)
    }
}
