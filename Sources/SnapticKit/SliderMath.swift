import Foundation

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 (kind S): safe returns. H implements the
// hand-written formatting and parsing (N12) in step 1.

/// Units and scaling for display, typing and VoiceOver.
package enum ValueFormat: Equatable, Sendable {
    /// Shows 0…`of` as 0–100% (`.percent(of: 1)`).
    case percent(of: Double)
    case seconds, minutes, hertz, points, nits, kelvin
    case plain(digits: Int)
}

package enum SliderMath {
    /// Clamped to `range` and snapped to `step` (when given). Stub: clamped only.
    package static func clampSnap(_ value: Double, range: ClosedRange<Double>, step: Double?) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
    /// Half-step tolerance. Stub: exact comparison.
    package static func isDefault(value: Double, default defaultValue: Double?, step: Double?) -> Bool {
        defaultValue == value
    }
    /// Hand-formatted with the unit inside the text ("70%", "60 Hz"). Stub: "".
    package static func format(_ value: Double, _ format: ValueFormat, decimalSeparator: String) -> String { "" }
    /// Accepts "70", "70 %", "70%", "1,5 s" with ",". Stub: nil.
    package static func parse(_ text: String, _ format: ValueFormat, decimalSeparator: String) -> Double? { nil }
    /// VoiceOver text ("70 percent"). Stub: "".
    package static func spoken(_ value: Double, _ format: ValueFormat, decimalSeparator: String) -> String { "" }
    /// The widest formatted value of the range (field width). Stub: "".
    package static func widestText(range: ClosedRange<Double>, step: Double?, format: ValueFormat) -> String { "" }
}
