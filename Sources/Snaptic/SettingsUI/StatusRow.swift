import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

struct StatusAction {
    let title: String
    let action: @MainActor () -> Void
    /// R5-13.
    var control: ControlID? = nil

    init(title: String, control: ControlID? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.control = control
        self.action = action
    }
}

enum StatusStyle { case info, warning, error }

struct StatusRow: View {
    let text: String
    let symbol: String?
    let style: StatusStyle
    let actions: [StatusAction]

    init(_ text: String, symbol: String? = nil, style: StatusStyle = .info, actions: [StatusAction] = []) {
        self.text = text
        self.symbol = symbol
        self.style = style
        self.actions = actions
    }

    var body: some View {
        HStack {
            if let symbol { Image(systemName: symbol) }
            Text(text)
            Spacer()
            ForEach(actions.indices, id: \.self) { i in
                Button(actions[i].title) { actions[i].action() }
            }
        }
    }
}
