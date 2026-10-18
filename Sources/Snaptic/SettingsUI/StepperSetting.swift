import SwiftUI
import SnapticKit

/// Small ranges (≤ ~20 values): title (+ help) · typed field with the unit · stepper · reset slot (16 pt, the glyph
/// shows only off the default). Integer values (`Binding<Int>`, "Revert after 15 s") or decimal steps
/// (`Binding<Double>`).
struct StepperSetting: View {
    let title: String
    let help: String?
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double?
    let format: ValueFormat
    let anchor: ControlID?

    /// Bumped when the stepper or Reset sets the value: the field drops text typed without Return (ui F1).
    @State private var discardTyping = 0

    init(_ title: String, help: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         defaultValue: Int?, format: ValueFormat, anchor: ControlID? = nil) {
        let lo = range.lowerBound, hi = range.upperBound
        self.title = title
        self.help = help
        self.value = Binding(get: { Double(value.wrappedValue) },
                             set: { v in
                                 let i = Int(min(Double(hi), max(Double(lo), v.isFinite ? v.rounded() : Double(lo))))
                                 if value.wrappedValue != i { value.wrappedValue = i }
                             })
        self.range = Double(lo)...Double(hi)
        self.step = Double(max(1, step))
        self.defaultValue = defaultValue.map(Double.init)
        self.format = format
        self.anchor = anchor
    }

    init(_ title: String, help: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         defaultValue: Double?, format: ValueFormat, anchor: ControlID? = nil) {
        self.title = title
        self.help = help
        self.value = value
        self.range = range
        self.step = step.isFinite && step > 0 ? step : 1
        self.defaultValue = defaultValue
        self.format = format
        self.anchor = anchor
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                NumberField(title, value: snapped, in: range, step: step, format: format, discardToken: discardTyping)
                Stepper(title, value: stepped, in: range, step: step)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue(SettingsFormat.spoken(value.wrappedValue, format))
                ResetButton(visible: !atDefault, label: resetLabel, tooltip: resetTooltip) { resetToDefault() }
            }
        } label: {
            Text(title)
            if let help { Text(help) }
        }
        .modifier(ResetContextMenu(reset: defaultValue == nil ? nil : { resetToDefault() }, isDefault: atDefault))
        .modifier(OptionalSettingsAnchor(anchor))
    }

    /// Writes clamped and snapped values only when they change.
    private var snapped: Binding<Double> {
        Binding(get: { value.wrappedValue },
                set: { v in
                    let s = SliderMath.clampSnap(v, range: range, step: step)
                    if value.wrappedValue != s { value.wrappedValue = s }
                })
    }

    /// The stepper's own arrows: newer intent than typed-but-not-Returned text.
    private var stepped: Binding<Double> {
        let snapped = snapped
        return Binding(get: { snapped.wrappedValue },
                       set: { v in
                           discardTyping &+= 1
                           snapped.wrappedValue = v
                       })
    }

    private var atDefault: Bool {
        SliderMath.isDefault(value: value.wrappedValue, default: defaultValue, step: step)
    }

    private var resetLabel: String {
        guard let d = defaultValue else { return L("Reset \(title)") }
        return L("Reset \(title) to \(SettingsFormat.spoken(d, format))")
    }

    private var resetTooltip: String {
        guard let d = defaultValue else { return L("Reset to Default") }
        return L("Reset to \(SettingsFormat.text(d, format))")
    }

    private func resetToDefault() {
        guard let d = defaultValue else { return }
        discardTyping &+= 1
        snapped.wrappedValue = d
    }
}
