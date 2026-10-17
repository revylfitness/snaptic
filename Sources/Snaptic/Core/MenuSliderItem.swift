import AppKit
import SnapticKit

/// A menu item hosting a real slider (PLAN §3.5): accessible, keyboard-adjustable, and
/// optionally adjusted by scrolling over it. Values are 0…1 unless `range` says otherwise.
/// Contributors update it in place with `setValue` while the menu is open; it never
/// fights a drag in progress.
@MainActor final class MenuSliderItem: NSMenuItem {
    /// "Scroll on a slider to adjust" (General → Menu); set by the host.
    static var scrollToAdjust = true
    static let width: CGFloat = 270
    static let height: CGFloat = 30

    private let onChange: @MainActor (Double) -> Void
    private let slider: ScrollSlider
    private let container: NSView

    var range: ClosedRange<Double> = 0...1 {
        didSet {
            slider.minValue = range.lowerBound
            slider.maxValue = range.upperBound
        }
    }

    init(title: String, symbol: String?, value: Double, onChange: @escaping @MainActor (Double) -> Void) {
        self.onChange = onChange
        slider = ScrollSlider(value: value, minValue: 0, maxValue: 1, target: nil, action: nil)
        container = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        super.init(title: title, action: nil, keyEquivalent: "")

        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.setAccessibilityLabel(title)
        slider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(slider)

        var leading = container.leadingAnchor
        var leadingInset: CGFloat = 20
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            icon.contentTintColor = .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.setAccessibilityElement(false)
            container.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
            ])
            leading = icon.trailingAnchor
            leadingInset = 6
        }
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leading, constant: leadingInset),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }

    required init(coder: NSCoder) {
        onChange = { _ in }
        slider = ScrollSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
        container = NSView(frame: .zero)
        super.init(coder: coder)
    }

    /// Updates the slider in place (the menu may be open). Ignored during a drag.
    func setValue(_ value: Double) {
        guard value.isFinite, !slider.isDragging else { return }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        if abs(slider.doubleValue - clamped) > 0.0005 { slider.doubleValue = clamped }
    }

    var value: Double { slider.doubleValue }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let type = NSApp.currentEvent?.type
        slider.isDragging = type == .leftMouseDragged || type == .leftMouseDown
        if type == .leftMouseUp { slider.isDragging = false }
        onChange(sender.doubleValue)
    }
}

/// Scrolling over the slider adjusts it (when enabled); mouse-up always ends a drag.
private final class ScrollSlider: NSSlider {
    var isDragging = false

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        super.mouseDown(with: event)   // tracks until mouse-up
        isDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard MenuSliderItem.scrollToAdjust, isEnabled else {
            super.scrollWheel(with: event)
            return
        }
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard delta != 0 else { return }
        let span = maxValue - minValue
        let step = span * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04) * Double(delta)
        let natural = event.isDirectionInvertedFromDevice ? -1.0 : 1.0
        doubleValue = min(maxValue, max(minValue, doubleValue + step * natural))
        sendAction(action, to: target)
    }
}
