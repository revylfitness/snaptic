import SwiftUI
import SnapticKit

/// An in-form push button on a row of its own, trailing ("Keyboard Shortcuts…", "Display Details…"), as in
/// System Settings › Keyboard.
struct ButtonRow: View {
    let title: String
    let symbol: String?
    let action: @MainActor () -> Void
    /// R5-13.
    let control: ControlID?

    init(_ title: String, symbol: String? = nil, control: ControlID? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.symbol = symbol
        self.control = control
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                action()
            } label: {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .modifier(OptionalSettingsAnchor(control))
        }
    }
}
