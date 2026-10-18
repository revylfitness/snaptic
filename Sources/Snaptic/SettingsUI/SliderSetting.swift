import SwiftUI
import SnapticKit

enum SliderCommit: Equatable {
    /// Hardware value through DisplayLiveControlling: latest-wins mailbox (every drag change is written).
    case live
    /// Config-backed: at most hz/s during a drag, final value on release.
    case throttled(hz: Double)
    /// Expensive side effects; `preview` gives live feedback meanwhile.
    case onRelease
}

/// Every slider in Settings (N4). Layout (design M6), trailing cluster after the title:
///   [min symbol] slider (min 140, ideal 200) [max symbol] · 8 · field (widest value of the range, min 48) · 4 ·
///   reset slot 16 (always reserved; empty with `defaultValue: nil`, design m8).
/// When the row is too narrow: the title row (field + reset trailing) above a full-width slider.
/// The field IS the live value: it shows `drag ?? value` with the unit inside ("70%"); typing commits on Return.
/// The drag is local state (§4.5): the slider follows the pointer at once; the binding is written per `commit`, and
/// always once more with the final value on release. Tick marks when ≤ 11 positions; ←/→ and VoiceOver's adjust
/// action move one step (or 1% of a continuous range). `phase` reports drag began/changed/ended (live hardware).
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
    let phase: (@MainActor (DragPhase) -> Void)?
    /// Named positions for a discrete slider over `0...labels.count - 1` (resolution: "1512 × 982").
    let labels: [String]?

    @State private var drag: Double?
    @StateObject private var throttle = SliderThrottle()

    init(_ title: String, help: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double? = nil, defaultValue: Double?, format: ValueFormat,
         minSymbol: String? = nil, maxSymbol: String? = nil,
         commit: SliderCommit = .throttled(hz: 15), preview: (@MainActor (Double) -> Void)? = nil,
         anchor: ControlID? = nil, subordinate: Bool = false, disabledReason: String? = nil,
         phase: (@MainActor (DragPhase) -> Void)? = nil, labels: [String]? = nil) {
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
        self.phase = phase
        self.labels = labels
    }

    var body: some View {
        Group {
            if let disabledReason {
                VStack(alignment: .leading, spacing: 4) {
                    layouts.disabled(true)
                    SettingsRowNote(disabledReason)
                }
            } else {
                layouts
            }
        }
        .padding(.leading, subordinate ? 20 : 0)
        .modifier(ResetContextMenu(reset: defaultValue == nil ? nil : { resetToDefault() }, isDefault: atDefault))
        .modifier(OptionalSettingsAnchor(anchor))
    }

    // MARK: Layout

    private var layouts: some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent {
                HStack(spacing: 0) {
                    sliderWithSymbols
                        .frame(minWidth: 140, idealWidth: 200, maxWidth: 260)
                    Spacer().frame(width: 8)
                    field
                    Spacer().frame(width: 4)
                    reset
                }
            } label: {
                // The help line reports a tiny ideal width, so only the title decides whether the wide layout fits.
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let help {
                        Text(help)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: 0, idealWidth: 1, maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        if let help {
                            Text(help)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    field
                    Spacer().frame(width: 4)
                    reset
                }
                sliderWithSymbols
            }
        }
    }

    private var sliderWithSymbols: some View {
        HStack(spacing: 6) {
            if let minSymbol {
                Image(systemName: minSymbol)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            slider
            if let maxSymbol {
                Image(systemName: maxSymbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var slider: some View {
        let binding = Binding<Double>(get: { shown }, set: { slide(to: $0) })
        Group {
            if ticks != nil, let step = snapStep {
                Slider(value: binding, in: safeRange, step: step) {
                    Text(title)
                } onEditingChanged: { editing($0) }
            } else {
                Slider(value: binding, in: safeRange) {
                    Text(title)
                } onEditingChanged: { editing($0) }
            }
        }
        .labelsHidden()
        .accessibilityLabel(title)
        .accessibilityValue(SettingsFormat.spoken(shown, format, labels: labels))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: write(SliderMath.nudged(shown, direction: 1, range: range, step: snapStep))
            case .decrement: write(SliderMath.nudged(shown, direction: -1, range: range, step: snapStep))
            @unknown default: break
            }
        }
    }

    private var field: some View {
        NumberField(title, value: Binding(get: { shown }, set: { write($0) }), in: range, step: snapStep, format: format,
                    labels: labels)
    }

    private var reset: some View {
        ResetButton(visible: !atDefault, label: resetLabel, tooltip: resetTooltip) { resetToDefault() }
    }

    // MARK: State

    private var shown: Double { drag ?? value.wrappedValue }

    private var ticks: Int? { SliderMath.positions(range: range, step: snapStep) }

    /// Labeled positions are whole indices.
    private var snapStep: Double? { labels == nil ? step : (step ?? 1) }

    /// SwiftUI's slider needs a non-empty range.
    private var safeRange: ClosedRange<Double> {
        range.lowerBound < range.upperBound ? range : range.lowerBound...(range.lowerBound + 1)
    }

    private var atDefault: Bool {
        SliderMath.isDefault(value: shown, default: defaultValue,
                             step: labels == nil ? SliderMath.effectiveStep(step, format: format) : 1)
    }

    private var resetLabel: String {
        guard let d = defaultValue else { return L("Reset \(title)") }
        return L("Reset \(title) to \(SettingsFormat.spoken(d, format, labels: labels))")
    }

    private var resetTooltip: String {
        guard let d = defaultValue else { return L("Reset to Default") }
        return L("Reset to \(SettingsFormat.text(d, format, labels: labels))")
    }

    // MARK: Commit

    private func editing(_ began: Bool) {
        if began {
            throttle.cancel()
            drag = value.wrappedValue
            phase?(.began)
        } else {
            throttle.cancel()
            let last = drag ?? value.wrappedValue
            drag = nil
            write(last)
            phase?(.ended)
        }
    }

    private func slide(to raw: Double) {
        let v = SliderMath.clampSnap(raw, range: range, step: snapStep)
        guard drag != nil else {
            // Keyboard, VoiceOver or a click without a drag: commit at once.
            write(v)
            return
        }
        drag = v
        preview?(v)
        switch commit {
        case .live:
            write(v)
            phase?(.changed)
        case .throttled(let hz):
            let binding = value
            throttle.submit(v, hz: hz) { latest in
                if binding.wrappedValue != latest { binding.wrappedValue = latest }
            }
        case .onRelease:
            break
        }
    }

    private func write(_ raw: Double) {
        let v = SliderMath.clampSnap(raw, range: range, step: snapStep)
        if value.wrappedValue != v { value.wrappedValue = v }
    }

    private func resetToDefault() {
        guard let d = defaultValue else { return }
        throttle.cancel()
        drag = nil
        write(d)
    }
}

/// Rate limit for `.throttled` drags: the first change writes at once, later ones at most `hz` per second, and the
/// last one in a window always lands (trailing edge).
@MainActor final class SliderThrottle: ObservableObject {
    private var lastWrite: TimeInterval = -.infinity
    private var pending: Double?
    private var work: DispatchWorkItem?

    func submit(_ value: Double, hz: Double, write: @escaping @MainActor (Double) -> Void) {
        let rate = hz.isFinite ? min(120, max(1, hz)) : 15
        let interval = 1 / rate
        let now = ProcessInfo.processInfo.systemUptime
        if work == nil && now - lastWrite >= interval {
            lastWrite = now
            pending = nil
            write(value)
            return
        }
        pending = value
        guard work == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.work = nil
                guard let latest = self.pending else { return }
                self.pending = nil
                self.lastWrite = ProcessInfo.processInfo.systemUptime
                write(latest)
            }
        }
        work = item
        let delay = max(0, interval - (now - lastWrite))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        work?.cancel()
        work = nil
        pending = nil
    }
}
