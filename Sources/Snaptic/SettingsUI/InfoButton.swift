import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// (i) popover, 280 pt; never opens a sheet.
struct InfoButton: View {
    let title: String
    let message: String
    @State private var shown = false

    init(_ title: String, message: String) {
        self.title = title
        self.message = message
    }

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel(title)
            .popover(isPresented: $shown) {
                Text(message).padding().frame(width: 280)
            }
    }
}
