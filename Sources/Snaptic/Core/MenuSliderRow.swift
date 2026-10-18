import AppKit
import Combine
import SnapticKit

/// A slider row (PLAN 0.3 §5.1): a plain AppKit view, 300 × 30 — leading 16 pt template symbol in the image column,
/// an `NSSlider` (.regular) on the text column and a trailing value label (40 pt, monospaced digits, secondary
/// label color). Values follow live changes while the menu is open (`bind(to:)`, delivered on the main queue, which
/// runs in the menu's event-tracking mode too) and never fight a drag. `discrete` sliders snap to whole steps and
/// commit on `.ended` only (resolution).
///
/// Phases: `.began` on mouse down, `.changed` while tracking, `.ended` after the slider's tracking loop returns;
/// each scroll-wheel step (with "Scroll over a slider to adjust it") and each change made without a drag
/// (VoiceOver increment/decrement, keyboard) delivers a `.changed` + `.ended` pair.
@MainActor final class MenuSliderRow: NSMenuItem {
    /// "Scroll over a slider to adjust it" (Menu Bar page); the host sets it from `MenuConfig.scrollAdjustsSliders`.
    static var scrollToAdjust = true

    static let height: CGFloat = 30
    static let valueWidth: CGFloat = 40

    private let onChange: @MainActor (Double, DragPhase) -> Void
    private var sink: AnyCancellable?
    private let rowView: MenuSliderRowView?
    let range: ClosedRange<Double>
    let format: ValueFormat
    let discrete: Bool
    /// The current value; nil = unknown (slider disabled, value "—").
    private(set) var value: Double?
    /// Custom value text, e.g. "1512 × 982" for a discrete resolution index.
    private let customText: (@MainActor (Double) -> String)?

    /// Never decoded from a nib: a decoded row is disabled, with no view and no handler; it never traps.
    required init(coder: NSCoder) {
        onChange = { _, _ in }
        rowView = nil
        range = 0...1
        format = .percent(of: 1)
        discrete = false
        customText = nil
        super.init(coder: coder)
        isEnabled = false
    }

    /// `valueText`: the value label's text instead of `format`'s (a discrete slider over an index list shows the
    /// entry, "1512 × 982"); `widestValueText` sizes the label so the longest entry fits (40–120 pt).
    init(title: String, symbol: String, value: Double?, range: ClosedRange<Double>, format: ValueFormat,
         discrete: Bool = false, valueText: (@MainActor (Double) -> String)? = nil, widestValueText: String? = nil,
         control: ControlID? = nil,
         onChange: @escaping @MainActor (Double, DragPhase) -> Void) {
        self.onChange = onChange
        customText = valueText
        let safeRange = Self.safeRange(range)
        self.range = safeRange
        self.format = format
        self.discrete = discrete
        let view = MenuSliderRowView(title: title, symbol: symbol, range: safeRange, discrete: discrete)
        rowView = view
        super.init(title: title, action: nil, keyEquivalent: "")
        if let control { identifier = NSUserInterfaceItemIdentifier(control.rawValue) }
        self.view = view
        view.onPhase = { [weak self] v, phase in self?.sliderMoved(v, phase) }
        if let widestValueText { view.fitValue(widestValueText) }
        setValue(value)
    }

    /// Live updates while the menu is open; ignored during a drag.
    func bind(to publisher: AnyPublisher<Double?, Never>) {
        sink = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in MainActor.assumeIsolated { self?.setValue(v) } }
    }

    /// nil → slider disabled, value "—". Ignored while the user drags.
    func setValue(_ v: Double?) {
        guard let rowView, !rowView.isTracking else { return }
        let clamped = v.flatMap { $0.isFinite ? min(range.upperBound, max(range.lowerBound, $0)) : nil }
        value = clamped
        rowView.show(clamped, text: valueText(clamped), spoken: spokenText(clamped))
    }

    private func sliderMoved(_ v: Double, _ phase: DragPhase) {
        let snapped = discrete ? v.rounded() : v
        value = snapped
        rowView?.show(snapped, text: valueText(snapped), spoken: spokenText(snapped), moveSlider: false)
        if discrete && phase == .changed { return }   // commits on release only
        onChange(snapped, phase)
    }

    // MARK: Text

    private static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    func valueText(_ v: Double?) -> String {
        guard let v else { return "—" }
        if let customText { return customText(v) }
        let text = SliderMath.format(v, format, decimalSeparator: Self.decimalSeparator)
        return text.isEmpty ? Self.fallbackText(v, format) : text
    }

    private func spokenText(_ v: Double?) -> String {
        guard let v else { return L("Unknown") }
        if let customText { return customText(v) }
        let text = SliderMath.spoken(v, format, decimalSeparator: Self.decimalSeparator)
        return text.isEmpty ? valueText(v) : text
    }

    /// Used only while SliderMath returns nothing (it is H's; this keeps the row readable on its own).
    static func fallbackText(_ v: Double, _ format: ValueFormat) -> String {
        switch format {
        case .percent(let of):
            guard of > 0 else { return "—" }
            return String(Int((v / of * 100).rounded())) + "%"
        case .seconds: return String(Int(v.rounded())) + " s"
        case .minutes: return String(Int(v.rounded())) + " min"
        case .hertz: return String(Int(v.rounded())) + " Hz"
        case .points: return String(Int(v.rounded())) + " pt"
        case .nits: return String(Int(v.rounded())) + " nits"
        case .kelvin: return String(Int(v.rounded())) + " K"
        case .plain(let digits):
            let d = min(max(digits, 0), 3)
            if d == 0 { return String(Int(v.rounded())) }
            let scale = pow(10, Double(d))
            let whole = Int((abs(v) * scale).rounded())
            let sign = v < 0 && whole != 0 ? "-" : ""
            let fraction = String(whole % Int(scale))
            return sign + String(whole / Int(scale)) + decimalSeparator
                + String(repeating: "0", count: d - fraction.count) + fraction
        }
    }

    /// A finite, non-empty range (a broken contributor range never reaches NSSlider).
    private static func safeRange(_ r: ClosedRange<Double>) -> ClosedRange<Double> {
        guard r.lowerBound.isFinite, r.upperBound.isFinite else { return 0...1 }
        return r.upperBound > r.lowerBound ? r : r.lowerBound...(r.lowerBound + 1)
    }
}

/// The row's view: symbol, slider and value label, with the shared highlight (MenuRowView).
@MainActor final class MenuSliderRowView: MenuRowView {
    var onPhase: (@MainActor (Double, DragPhase) -> Void)?
    var isTracking: Bool { slider.isTracking }

    private let icon: NSImageView
    private let slider: RowSlider
    private let label: NSTextField
    private let title: String
    private var valueWidth: NSLayoutConstraint?

    init(title: String, symbol: String, range: ClosedRange<Double>, discrete: Bool) {
        self.title = title
        icon = NSImageView()
        slider = RowSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound,
                           target: nil, action: nil)
        label = NSTextField(labelWithString: "—")
        super.init(frame: NSRect(x: 0, y: 0, width: MenuKit.width, height: MenuSliderRow.height))

        icon.image = MenuKit.symbolImage(symbol)
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        slider.controlSize = .regular
        slider.isContinuous = true
        slider.discrete = discrete
        if discrete {
            let steps = Int((range.upperBound - range.lowerBound).rounded())
            slider.numberOfTickMarks = min(max(steps + 1, 2), 64)
            slider.allowsTickMarkValuesOnly = steps + 1 <= 64
            slider.tickMarkPosition = .below
        }
        slider.target = self
        slider.action = #selector(moved(_:))
        slider.setAccessibilityLabel(title)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.onPhase = { [weak self] value, phase in self?.onPhase?(value, phase) }
        addSubview(slider)

        label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.setAccessibilityElement(false)   // the slider's value says it
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuKit.rowInset),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            slider.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuKit.rowInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let width = label.widthAnchor.constraint(equalToConstant: MenuSliderRow.valueWidth)
        width.isActive = true
        valueWidth = width
    }

    /// Widens the value label so `text` fits (40–120 pt; the slider gives up the space).
    func fitValue(_ text: String) {
        let font = label.font ?? NSFont.menuFont(ofSize: 0)
        let measured = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
        valueWidth?.constant = min(120, max(MenuSliderRow.valueWidth, measured))
    }

    required init?(coder: NSCoder) {
        title = ""
        icon = NSImageView()
        slider = RowSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
        label = NSTextField(labelWithString: "")
        super.init(coder: coder)
    }

    /// Shows a value (nil disables the slider). `moveSlider: false` while the user moves it.
    func show(_ value: Double?, text: String, spoken: String, moveSlider: Bool = true) {
        label.stringValue = text
        slider.isEnabled = value != nil
        if moveSlider, let value, abs(slider.doubleValue - value) > 0.0005 { slider.doubleValue = value }
        slider.setAccessibilityValueDescription(spoken)
        setAccessibilityLabel(title + ", " + text)
    }

    override func highlightDidChange(_ highlighted: Bool) {
        label.textColor = textColor(.secondaryLabelColor)
        icon.contentTintColor = textColor(.secondaryLabelColor)
    }

    @objc private func moved(_ sender: NSSlider) {
        // During a drag: `.changed` (mouse down and the end of the drag report their own phases). A change with no
        // drag (VoiceOver increment/decrement, arrow keys) is one whole step, like a scroll step: `.changed` then
        // `.ended`, so it is applied (a discrete slider commits it) and the label and spoken value follow (ux M1).
        // Scroll steps set the value directly and never come through here.
        if slider.isTracking {
            onPhase?(sender.doubleValue, .changed)
        } else {
            onPhase?(sender.doubleValue, .changed)
            onPhase?(sender.doubleValue, .ended)
        }
    }
}

/// Reports drag phases around NSSlider's own tracking loop, and adjusts by scrolling when allowed.
@MainActor private final class RowSlider: NSSlider {
    var onPhase: (@MainActor (Double, DragPhase) -> Void)?
    var discrete = false
    private(set) var isTracking = false
    private var scrollAccumulator: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return super.mouseDown(with: event) }
        isTracking = true
        onPhase?(doubleValue, .began)
        super.mouseDown(with: event)   // tracks until mouse-up
        isTracking = false
        onPhase?(doubleValue, .ended)
    }

    override func scrollWheel(with event: NSEvent) {
        guard MenuSliderRow.scrollToAdjust, isEnabled, !isTracking else {
            super.scrollWheel(with: event)
            return
        }
        let raw = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        let delta = event.isDirectionInvertedFromDevice ? -raw : raw
        guard delta != 0 else { return }
        let span = maxValue - minValue
        let next: Double
        if discrete {
            // One whole step per notch (precise devices accumulate about 8 pt per step).
            scrollAccumulator += event.hasPreciseScrollingDeltas ? delta / 8 : delta
            guard abs(scrollAccumulator) >= 1 else { return }
            let steps = scrollAccumulator.rounded(.towardZero)
            scrollAccumulator -= steps
            next = (doubleValue + Double(steps)).rounded()
        } else {
            next = doubleValue + span * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04) * Double(delta)
        }
        let clamped = min(maxValue, max(minValue, next))
        guard clamped != doubleValue else { return }
        doubleValue = clamped
        onPhase?(clamped, .changed)
        onPhase?(clamped, .ended)
    }
}
