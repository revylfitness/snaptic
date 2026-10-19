import SwiftUI
import SnapticKit

/// System Settings–style icon tile: a rounded square in the tint's gradient with a white symbol. Sidebar 20 pt,
/// page header 40 pt, hero header 64 pt. Accessibility hidden (the row's title says what it is).
struct SettingsIcon: View {
    let symbol: String
    let tint: SettingsTint
    let size: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ symbol: String, tint: SettingsTint, size: CGFloat = 20) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(tint.color.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
