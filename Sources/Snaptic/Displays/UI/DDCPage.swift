import SwiftUI

/// The 0.2 "DDCPage" route, kept only while `DisplaysModule.settingsPages()` lists it (removed with that list in the
/// step-3 coordinated merge, PLAN 0.3 §6.2 ✗): it shows the 0.3 page, Hardware Controls (`HardwareControlsPage`).
struct DDCPage: View {
    let env: DisplaysPageEnvironment

    var body: some View {
        HardwareControlsPage(env: env)
    }
}
