import SwiftUI
import SnapticKit

/// Title + optional one-line help (the grouped form renders the second `Text` as the subtitle) + trailing control.
/// Reset: a glyph only for continuous values (`resetGlyph: true`); every row with `reset` also gets the context
/// menu "Reset to Default" (design M6). Either commits the focused typed field before resetting, so the reset wins.
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
            HStack(spacing: 4) {
                control
                if resetGlyph {
                    ResetButton(visible: reset != nil && !isDefault, label: resetLabel ?? L("Reset \(title) to Default")) {
                        // A typed-but-not-Returned value in the row's field is written first, so the reset comes
                        // last and wins; otherwise Done or the blur would write the typing back over it (review7
                        // ui-ux F2).
                        FocusedField.commit()
                        reset?()
                    }
                }
            }
        } label: {
            Text(title)
            if let help { Text(help) }
        }
        .modifier(ResetContextMenu(reset: reset, isDefault: isDefault))
        .modifier(OptionalSettingsAnchor(anchor))
    }
}

/// arrow.counterclockwise 11 pt, borderless, secondary; always reserves 16 pt; fades 0.15 s (instant with Reduce
/// Motion). Tooltip "Reset to 50%", AX label "Reset Contrast to 50 percent". Hidden rows take no clicks, focus or
/// VoiceOver.
struct ResetButton: View {
    let visible: Bool
    let label: String
    let tooltip: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(visible: Bool, label: String, action: @escaping () -> Void) {
        self.init(visible: visible, label: label, tooltip: L("Reset to Default"), action: action)
    }

    init(visible: Bool, label: String, tooltip: String, action: @escaping () -> Void) {
        self.visible = visible
        self.label = label
        self.tooltip = tooltip
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
        .help(tooltip)
        .accessibilityLabel(label)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .disabled(!visible)
        .accessibilityHidden(!visible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: visible)
    }
}

/// "Reset to Default" in the row's context menu, disabled at the default; nothing without a reset action.
struct ResetContextMenu: ViewModifier {
    let reset: (() -> Void)?
    let isDefault: Bool

    func body(content: Content) -> some View {
        if let reset {
            content.contextMenu {
                Button(L("Reset to Default")) {
                    FocusedField.commit()
                    reset()
                }
                    .disabled(isDefault)
            }
        } else {
            content
        }
    }
}

/// Why a control is disabled, and the fix ("Needs Accessibility." [Open Accessibility Settings…]), as a footnote
/// right under the row (§4.2 States).
struct SettingsRowNote: View {
    let text: String
    let fix: StatusAction?

    init(_ text: String, fix: StatusAction? = nil) {
        self.text = text
        self.fix = fix
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fix {
                Button(fix.title) { fix.action() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .modifier(OptionalSettingsAnchor(fix.control))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}
