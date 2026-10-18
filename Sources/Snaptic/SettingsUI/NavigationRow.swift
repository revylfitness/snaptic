import SwiftUI
import SnapticKit

/// Icon tile + title + trailing value + chevron; pushes `route` onto the page's NavigationStack (the shell resolves
/// it through `settingsDestination`). Full-width grouped row, System Settings style.
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
        NavigationLink(value: route) {
            HStack(spacing: 8) {
                SettingsIcon(symbol, tint: tint, size: 20)
                Text(title)
                if let badge { SettingsBadgeView(badge) }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(badge?.spoken(title) ?? title)
        .accessibilityValue(value ?? "")
        .onAppear { SettingsShell.shared.noteTitle(title, for: route) }
        .modifier(OptionalSettingsAnchor(control))
    }
}
