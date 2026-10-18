import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Small integer ranges: label + NumberField + Stepper + reset slot.
struct StepperSetting: View {
    let title: String
    let help: String?
    let value: Binding<Int>
    let range: ClosedRange<Int>
    let step: Int
    let defaultValue: Int?
    let format: ValueFormat
    let anchor: ControlID?

    init(_ title: String, help: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         defaultValue: Int?, format: ValueFormat, anchor: ControlID? = nil) {
        self.title = title
        self.help = help
        self.value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.format = format
        self.anchor = anchor
    }

    var body: some View {
        Stepper(value: value, in: range, step: step) {
            Text(title)
        }
    }
}
