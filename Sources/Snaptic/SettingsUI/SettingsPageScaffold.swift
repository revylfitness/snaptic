import SwiftUI
import SnapticKit

/// Every page's scroll scaffold: a grouped form inside the `ScrollViewReader` that scrolls to a revealed row
/// (code minor 3). Rows register as anchors with `SettingsAnchor`. A reveal whose row isn't on the page (hardware
/// can't do it, so the row is omitted) leaves the page at the top.
struct SettingsPageScaffold<Content: View>: View {
    let route: SettingsRoute
    let content: Content

    init(route: SettingsRoute, @ViewBuilder content: () -> Content) {
        self.route = route
        self.content = content()
    }

    var body: some View {
        SettingsAnchorScroller {
            Form { content }
                .formStyle(.grouped)
        }
    }
}
