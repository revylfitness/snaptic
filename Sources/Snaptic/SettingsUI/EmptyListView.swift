import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Empty lists: ContentUnavailableView with the page's own copy.
struct EmptyListView: View {
    let title: String
    let symbol: String
    let text: String?
    let action: StatusAction?

    init(_ title: String, symbol: String, text: String?, action: StatusAction?) {
        self.title = title
        self.symbol = symbol
        self.text = text
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let text { Text(text).foregroundStyle(.secondary) }
            if let action { Button(action.title) { action.action() } }
        }
        .frame(maxWidth: .infinity)
    }
}
