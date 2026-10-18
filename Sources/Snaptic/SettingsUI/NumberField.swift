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
/// The field follows its value whenever the user hasn't typed (also while focused), and a commit writes only what the
/// user typed since the last sync (`TypedFieldState`): blur never writes stale text over a slider drag, a stepper
/// click or a change made elsewhere. The row bumps `discardToken` when its own slider, stepper or Reset sets the value:
/// text typed without Return is then dropped (review round 2 ui F1).
struct NumberField: View {
    let accessibilityTitle: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    let format: ValueFormat
    let width: CGFloat?
    /// Named positions ("1512 × 982"): values are indices, typed text matches a label.
    let labels: [String]?
    /// Changed by the owning row when its own control sets the value (`TypedFieldState.discardTyping`).
    let discardToken: Int

    @State private var edit = TypedFieldState()
    @FocusState private var focused: Bool

    /// `width` nil = derived from `SliderMath.widestText(range:step:format:)` (design m7).
    init(_ accessibilityTitle: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double?,
         format: ValueFormat, width: CGFloat? = nil, labels: [String]? = nil, discardToken: Int = 0) {
        self.accessibilityTitle = accessibilityTitle
        self.labels = labels
        self.discardToken = discardToken
        self.value = value
        self.range = range
        self.step = step
        self.format = format
        self.width = width
    }

    var body: some View {
        TextField(accessibilityTitle, text: Binding(get: { edit.text }, set: { edit.edit($0) }))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: fieldWidth)
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { edit.revert(display: display) }
            .onKeyPress(.upArrow) {
                nudge(1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                nudge(-1)
                return .handled
            }
            .onAppear { edit.revert(display: display) }
            .onChange(of: display) { _, newValue in
                edit.sync(display: newValue)
            }
            .onChange(of: discardToken) { _, _ in
                edit.discardTyping(display: display)
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    edit.sync(display: display)
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

    private func shown(_ v: Double) -> String { SettingsFormat.text(v, format, labels: labels) }

    private func commit() {
        let range = range, step = snapStep, format = format, labels = labels
        let result = edit.commit(display: display,
                                 parse: { text in
                                     SettingsFormat.parse(text, format, labels: labels)
                                         .map { SliderMath.clampSnap($0, range: range, step: step) }
                                 },
                                 format: { shown($0) })
        switch result {
        case .none: break
        case .invalid: NSSound.beep()
        case .write(let v):
            if v != value.wrappedValue { value.wrappedValue = v }
            settleNextTurn()
        }
    }

    /// The binding may store something else than what was written (clamped back to the old value: the display doesn't
    /// change, so `onChange(of: display)` never fires); show the stored value once the write has landed.
    private func settleNextTurn() {
        let value = value, format = format, labels = labels, edit = $edit
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                edit.wrappedValue.settle(display: SettingsFormat.text(value.wrappedValue, format, labels: labels))
            }
        }
    }

    private func nudge(_ direction: Int) {
        let range = range, step = snapStep, format = format, labels = labels
        let v = edit.nudge(value: value.wrappedValue,
                           parse: { SettingsFormat.parse($0, format, labels: labels) },
                           step: { SliderMath.nudged($0, direction: direction, range: range, step: step) },
                           format: { shown($0) })
        if v != value.wrappedValue { value.wrappedValue = v }
        settleNextTurn()
    }
}
