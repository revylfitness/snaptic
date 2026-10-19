import SwiftUI
import SnapticKit

/// An empty list: `ContentUnavailableView` with the page's own copy and, optionally, the action that fills it
/// ("Save your current arrangement to restore it later." [Save Current Layout…]).
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
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let text { Text(text) }
        } actions: {
            if let action {
                Button(action.title) { action.action() }
                    .modifier(OptionalSettingsAnchor(action.control))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
