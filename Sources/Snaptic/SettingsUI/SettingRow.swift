import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Title + optional one-line help + trailing control.
struct SettingRow<Control: View>: View {
    let title: String
    let help: String?
    let anchor: ControlID?
    let isDefault: Bool
    let reset: (() -> Void)?
    let resetGlyph: Bool
    let resetLabel: String?
    let control: Control

    init(_ title: String, help: String? = nil, anchor: ControlID? = nil, isDefault: Bool = true,
         reset: (() -> Void)? = nil, resetGlyph: Bool = false, resetLabel: String? = nil,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.help = help
        self.anchor = anchor
        self.isDefault = isDefault
        self.reset = reset
        self.resetGlyph = resetGlyph
        self.resetLabel = resetLabel
        self.control = control()
    }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(title)
            if let help { Text(help) }
        }
    }
}

/// arrow.counterclockwise, borderless, secondary; visible only while the value isn't the default.
struct ResetButton: View {
    let visible: Bool
    let label: String
    let action: () -> Void

    init(visible: Bool, label: String, action: @escaping () -> Void) {
        self.visible = visible
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(.borderless)
            .opacity(visible ? 1 : 0)
            .disabled(!visible)
            .accessibilityLabel(label)
    }
}
