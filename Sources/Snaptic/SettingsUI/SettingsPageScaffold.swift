import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Each page's scroll scaffold owns its ScrollViewReader; anchors register here.
struct SettingsPageScaffold<Content: View>: View {
    let route: SettingsRoute
    let content: Content

    init(route: SettingsRoute, @ViewBuilder content: () -> Content) {
        self.route = route
        self.content = content()
    }

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}
