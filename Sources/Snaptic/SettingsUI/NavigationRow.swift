import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Icon tile + title + trailing value + chevron.
struct NavigationRow: View {
    let title: String
    let symbol: String
    let tint: SettingsTint
    let value: String?
    let route: SettingsRoute
    let badge: SettingsBadge?
    /// R5-13.
    let control: ControlID?

    init(_ title: String, symbol: String, tint: SettingsTint, value: String? = nil, route: SettingsRoute,
         badge: SettingsBadge? = nil, control: ControlID? = nil) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.value = value
        self.route = route
        self.badge = badge
        self.control = control
    }

    var body: some View {
        HStack {
            SettingsIcon(symbol, tint: tint)
            Text(title)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
    }
}
