import SwiftUI
import SnapticKit

/// The 0.2 "Resolution" page id, kept only while `DisplaysModule.settingsPages()` lists it (removed in the step-3
/// coordinated merge): it shows the 0.3 `displays.resolution` page.
struct ResolutionPage: View {
    let env: DisplaysPageEnvironment

    var body: some View {
        ResolutionSections(env: env)
    }
}
