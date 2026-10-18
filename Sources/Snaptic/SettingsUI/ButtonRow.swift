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
    /// One line saying what the button does, leading, with the button trailing ("Copies a Terminal command…").
    let help: String?
    /// Indented 20 pt under its parent switch, shown by the caller only while the parent is on.
    let subordinate: Bool

    init(_ title: String, symbol: String? = nil, control: ControlID? = nil, action: @escaping @MainActor () -> Void) {
        self.init(title, help: nil, symbol: symbol, control: control, action: action)
    }

    init(_ title: String, help: String?, subordinate: Bool = false, symbol: String? = nil, control: ControlID? = nil,
         action: @escaping @MainActor () -> Void) {
        self.title = title
        self.symbol = symbol
        self.control = control
        self.action = action
        self.help = help
        self.subordinate = subordinate
    }

    var body: some View {
        HStack(spacing: 8) {
            if let help {
                Text(help)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            .fixedSize()
            .accessibilityHint(help ?? "")
            .modifier(OptionalSettingsAnchor(control))
        }
        .padding(.leading, subordinate ? 20 : 0)
    }
}
