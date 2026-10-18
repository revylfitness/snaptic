import AppKit
import SnapticKit

/// The switch header row (PLAN 0.3 §5.1, consistency m13), built by `MenuKit.switchHeader`: bold title on the
/// leading edge, a small `NSSwitch` on the trailing edge (as in the Wi-Fi menu) and up to two secondary lines.
/// AppKit only; no fills. Its height is fixed when the menu opens (26, 40 or 54 pt) and kept while it is open: an
/// update with a different number of lines shows what fits and reports the change, so the owner rebuilds the menu
/// in `menuDidClose`. Mouse only: the same action always exists as a native item (parity M4).
@MainActor final class MenuSwitchHeaderView: MenuRowView {
    static let maxLines = 2
    static func height(lines: Int) -> CGFloat { 26 + 14 * CGFloat(min(max(lines, 0), maxLines)) }

    private(set) var title: String
    private(set) var isOn: Bool
    private(set) var detail: [String]
    /// The number of secondary lines this view was laid out for (fixed while the menu is open).
    let lineCapacity: Int

    private let onToggle: @MainActor (Bool) -> Void
    private let titleLabel: NSTextField
    private let toggle = NSSwitch()
    private var lines: [NSTextField] = []

    init(title: String, isOn: Bool, detail: [String], onToggle: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.title = title
        self.isOn = isOn
        self.detail = Array(detail.prefix(Self.maxLines))
        self.onToggle = onToggle
        lineCapacity = min(detail.count, Self.maxLines)
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuKit.width, height: Self.height(lines: lineCapacity)))
        build()
    }

    /// Never decoded from a nib; a decoded view is an empty, inert row.
    required init?(coder: NSCoder) {
        title = ""
        isOn = false
        detail = []
        onToggle = { _ in }
        lineCapacity = 0
        titleLabel = NSTextField(labelWithString: "")
        super.init(coder: coder)
    }

    private func build() {
        titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityElement(false)   // the switch carries the label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = #selector(switched(_:))
        toggle.setAccessibilityLabel(title)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuKit.rowInset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuKit.rowInset),
            toggle.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])

        var above: NSView = titleLabel
        for index in 0..<lineCapacity {
            let line = NSTextField(labelWithString: detail[index])
            line.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
            line.textColor = .secondaryLabelColor
            line.lineBreakMode = .byTruncatingTail
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuKit.rowInset),
                line.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuKit.rowInset),
                line.topAnchor.constraint(equalTo: above.bottomAnchor, constant: 0),
            ])
            lines.append(line)
            above = line
        }
        updateAccessibility()
    }

    /// Updates the row while its menu is open. Returns false when the new detail has a different number of lines
    /// than the row was laid out for (the owner then rebuilds after the menu closes).
    @discardableResult
    func update(isOn: Bool, detail: [String]) -> Bool {
        let wanted = Array(detail.prefix(Self.maxLines))
        self.isOn = isOn
        self.detail = wanted
        toggle.state = isOn ? .on : .off
        for (index, line) in lines.enumerated() {
            line.stringValue = index < wanted.count ? wanted[index] : ""
        }
        updateAccessibility()
        return wanted.count == lineCapacity
    }

    override func highlightDidChange(_ highlighted: Bool) {
        titleLabel.textColor = textColor(.labelColor)
        for line in lines { line.textColor = textColor(.secondaryLabelColor) }
    }

    private func updateAccessibility() {
        let shown = detail.prefix(lineCapacity).filter { !$0.isEmpty }
        toggle.setAccessibilityHelp(shown.isEmpty ? nil : shown.joined(separator: ". "))
    }

    @objc private func switched(_ sender: NSSwitch) {
        let on = sender.state == .on
        isOn = on
        onToggle(on)
    }
}
