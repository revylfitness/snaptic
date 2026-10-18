import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Rounded-square tile, accessibility hidden.
struct SettingsIcon: View {
    let symbol: String
    let tint: SettingsTint
    let size: CGFloat

    init(_ symbol: String, tint: SettingsTint, size: CGFloat = 20) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(tint.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
