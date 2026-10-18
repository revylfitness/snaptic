import AppKit
import SwiftUI
import SnapticKit

/// Number formatting inputs read once from the system (N12).
enum SettingsFormat {
    /// The decimal separator Settings fields show and accept (plus ".").
    static let decimalSeparator: String = Locale.current.decimalSeparator ?? "."

    static func text(_ value: Double, _ format: ValueFormat) -> String {
        SliderMath.format(value, format, decimalSeparator: decimalSeparator)
    }

    static func spoken(_ value: Double, _ format: ValueFormat) -> String {
        SliderMath.spoken(value, format, decimalSeparator: decimalSeparator)
    }

    /// The same with named positions (`labels` non-nil: values are indices).
    static func text(_ value: Double, _ format: ValueFormat, labels: [String]?) -> String {
        labels.map { SliderLabels.text(value, $0) } ?? text(value, format)
    }

    static func spoken(_ value: Double, _ format: ValueFormat, labels: [String]?) -> String {
        labels.map { SliderLabels.spoken(value, $0) } ?? spoken(value, format)
    }

    static func parse(_ text: String, _ format: ValueFormat, labels: [String]?) -> Double? {
        labels.map { SliderLabels.parse(text, $0) } ?? SliderMath.parse(text, format, decimalSeparator: decimalSeparator)
    }
}

/// Field widths from the widest value of a range (design m7): small system font with monospaced digits, plus the
/// rounded border's insets; at least 48 pt.
@MainActor enum SettingsFieldMetrics {
    private static var cache: [String: CGFloat] = [:]

    static func width(for text: String) -> CGFloat {
        if let w = cache[text] { return w }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        let width = max(48, ceil(measured + 14))
        if cache.count < 256 { cache[text] = width }
        return width
    }
}

/// A typed value with its unit inside the text ("70%", "15 min"). Commits on Return and when focus leaves; clamps
/// and snaps to `step`; Esc reverts; ↑/↓ move one step. Focus selects all. Invalid text beeps and reverts.
struct NumberField: View {
    let accessibilityTitle: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    let format: ValueFormat
    let width: CGFloat?
    /// Named positions ("1512 × 982"): values are indices, typed text matches a label.
    let labels: [String]?

    @State private var text = ""
    @FocusState private var focused: Bool

    /// `width` nil = derived from `SliderMath.widestText(range:step:format:)` (design m7).
    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat? = nil, labels: [String]? = nil) {
        self.accessibilityTitle = accessibilityTitle
        self.labels = labels
        self.value = value
        self.range = range
        self.step = step
        self.format = format
        self.width = width
    }

    var body: some View {
        TextField(accessibilityTitle, text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: fieldWidth)
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { text = display }
            .onKeyPress(.upArrow) {
                nudge(1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                nudge(-1)
                return .handled
            }
            .onAppear { text = display }
            .onChange(of: display) { _, newValue in
                if !focused { text = newValue }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            _ = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    }
                } else {
                    commit()
                }
            }
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(SettingsFormat.spoken(value.wrappedValue, format, labels: labels))
    }

    private var display: String { SettingsFormat.text(value.wrappedValue, format, labels: labels) }

    private var fieldWidth: CGFloat {
        width ?? SettingsFieldMetrics.width(for: labels.map(SliderLabels.widest)
            ?? SliderMath.widestText(range: range, step: step, format: format))
    }

    /// Labels are indices: they always snap to whole positions.
    private var snapStep: Double? {
        labels == nil ? step : (step ?? 1)
    }

    private func commit() {
        // Unchanged text never writes: the shown value is rounded, the stored one may not be.
        guard text != display else { return }
        guard let parsed = SettingsFormat.parse(text, format, labels: labels) else {
            NSSound.beep()
            text = display
            return
        }
        let v = SliderMath.clampSnap(parsed, range: range, step: snapStep)
        if v != value.wrappedValue { value.wrappedValue = v }
        text = SettingsFormat.text(v, format, labels: labels)
    }

    private func nudge(_ direction: Int) {
        let base = SettingsFormat.parse(text, format, labels: labels) ?? value.wrappedValue
        let v = SliderMath.nudged(base, direction: direction, range: range, step: snapStep)
        if v != value.wrappedValue { value.wrappedValue = v }
        text = SettingsFormat.text(v, format, labels: labels)
    }
}
