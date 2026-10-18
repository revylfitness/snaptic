import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Commits on Return and blur; clamps and snaps to step; Esc reverts; unit inside the text.
struct NumberField: View {
    let accessibilityTitle: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    let format: ValueFormat
    let width: CGFloat?

    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat? = nil) {
        self.accessibilityTitle = accessibilityTitle
        self.value = value
        self.range = range
        self.step = step
        self.format = format
        self.width = width
    }

    var body: some View {
        TextField(accessibilityTitle, value: value, format: .number)
            .labelsHidden()
            .frame(width: width ?? 64)
    }
}
