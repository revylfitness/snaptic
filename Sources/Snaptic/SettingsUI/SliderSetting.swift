import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

enum SliderCommit: Equatable {
    /// Hardware value through DisplayLiveControlling: latest-wins mailbox.
    case live
    /// Config-backed: at most hz/s during a drag, final value on release.
    case throttled(hz: Double)
    /// Expensive side effects; `preview` gives live feedback meanwhile.
    case onRelease
}

/// Every slider in Settings (N4).
struct SliderSetting: View {
    let title: String
    let help: String?
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    let defaultValue: Double?
    let format: ValueFormat
    let minSymbol: String?
    let maxSymbol: String?
    let commit: SliderCommit
    let preview: (@MainActor (Double) -> Void)?
    let anchor: ControlID?
    let subordinate: Bool
    let disabledReason: String?

    init(_ title: String, help: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double? = nil, defaultValue: Double?, format: ValueFormat,
         minSymbol: String? = nil, maxSymbol: String? = nil,
         commit: SliderCommit = .throttled(hz: 15), preview: (@MainActor (Double) -> Void)? = nil,
         anchor: ControlID? = nil, subordinate: Bool = false, disabledReason: String? = nil) {
        self.title = title
        self.help = help
        self.value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.format = format
        self.minSymbol = minSymbol
        self.maxSymbol = maxSymbol
        self.commit = commit
        self.preview = preview
        self.anchor = anchor
        self.subordinate = subordinate
        self.disabledReason = disabledReason
    }

    var body: some View {
        LabeledContent(title) {
            Slider(value: value, in: range)
                .frame(minWidth: 140, idealWidth: 200)
        }
        .disabled(disabledReason != nil)
        .padding(.leading, subordinate ? 20 : 0)
    }
}
