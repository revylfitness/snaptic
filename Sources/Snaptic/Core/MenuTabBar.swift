import AppKit
import SnapticKit

// The Snaptic menu's tab bar (owner: T-menu; PLAN 0.3.1 A1–A3). `MenuKit.tabBar(…)` returns an item whose view is
// `MenuTabBarView`: an NSView, not a MenuRowView, so it never draws the selection fill. It hosts a small
// `NSSegmentedControl` (`.selectOne`), inset by `MenuKit.rowInset`, 28 pt tall. Every decision (which tabs, the label
// style, the spoken text) is Kit's `MenuTabs`; this file only draws them.
//
// The segment's action fires at the end of the control's own tracking, the same cell path as the menu's NSSwitch and
// NSSlider rows, and StatusMenu switches the section synchronously in it (no timers, no run-loop perform: N15, L14).
// Mouse and VoiceOver only: the native "Show … Tab" items with ⌘1…⌘n are the keyboard path (A3, parity M4).

/// One tab's names: the full module title (label, accessibility, tooltip) and the short one (A1 fallbacks).
struct MenuTabLabel: Equatable {
    let title: String
    let shortTitle: String
}

/// One segment as the bar draws it; the texts come from `MenuTabs`.
struct MenuTabSegment: Equatable {
    let label: MenuTabLabel
    /// "Displays (⌘2)", "Awake, on (⌘3)".
    let toolTip: String
    /// VoiceOver's help: only the key, "Command-2" (the label already says the rest; r1 U3).
    let accessibilityHelp: String?
    /// The full title, plus ", on" or ", needs attention".
    let accessibilityLabel: String
    /// Shows the 10 pt attention image beside the label.
    let attention: Bool
}

@MainActor final class MenuTabBarView: NSView {
    static let height: CGFloat = 28
    static let attentionSymbol = "exclamationmark.circle"
    static let attentionPointSize: CGFloat = 10
    /// Space between the attention image and the label inside a segment.
    private static let imageGap: CGFloat = 3

    private let segments: [MenuTabSegment]
    private let onSelect: @MainActor (Int) -> Void
    private let control = MenuTabSegmentedControl()
    /// The bar's accessibility help ("Press Command-1 to Command-3 to switch tabs.").
    private let help: String
    /// The style chosen when the bar was built (A1: full, then short at equal widths, then short to fit).
    let labelStyle: MenuTabs.LabelStyle

    /// `width`: the menu's minimum width; the control gets it less `MenuKit.rowInset` on each side.
    init(segments: [MenuTabSegment], selected: Int, width: CGFloat, help: String,
         onSelect: @escaping @MainActor (Int) -> Void) {
        self.segments = segments
        self.onSelect = onSelect
        self.help = help
        let font = Self.font
        let image = Self.attentionImage()
        let imageWidth = image.map { Double($0.size.width + Self.imageGap) } ?? 0
        labelStyle = MenuTabs.labelStyle(
            fullWidths: segments.map { Self.segmentWidth($0.label.title, font: font) },
            shortWidths: segments.map { Self.segmentWidth($0.label.shortTitle, font: font) },
            imageWidth: imageWidth, attention: segments.map(\.attention),
            available: Double(width - 2 * MenuKit.rowInset))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        build(selected: selected, font: font, image: image, imageWidth: CGFloat(imageWidth))
    }

    /// Never decoded from a nib; a decoded view is an empty, inert bar.
    required init?(coder: NSCoder) {
        segments = []
        onSelect = { _ in }
        help = ""
        labelStyle = .fullEqual
        super.init(coder: coder)
    }

    /// The segment shown as selected.
    var selectedIndex: Int { control.selectedSegment }

    /// Shows `index` as selected without calling `onSelect` (a ⌘n switch while the menu stays open).
    func select(_ index: Int) {
        guard segments.indices.contains(index) else { return }
        control.selectedSegment = index
        control.selectionDidChange()
    }

    // MARK: Building

    private static var font: NSFont { NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)) }

    /// A 10 pt template `exclamationmark.circle`; its meaning is spoken through the segment's label, not the image.
    private static func attentionImage() -> NSImage? {
        guard let base = NSImage(systemSymbolName: attentionSymbol, accessibilityDescription: nil) else { return nil }
        let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: attentionPointSize, weight: .regular))
            ?? base
        image.isTemplate = true
        return image
    }

    /// A segment's width with `label` and no image: a one-segment control's own size, padding included.
    private static func segmentWidth(_ label: String, font: NSFont) -> Double {
        let probe = NSSegmentedControl(labels: [label], trackingMode: .selectOne, target: nil, action: nil)
        probe.controlSize = .small
        probe.font = font
        probe.segmentDistribution = .fit
        return Double(probe.intrinsicContentSize.width)
    }

    private func build(selected: Int, font: NSFont, image: NSImage?, imageWidth: CGFloat) {
        control.segmentCount = segments.count
        control.trackingMode = .selectOne
        control.controlSize = .small
        control.font = font
        control.segmentStyle = .automatic
        control.segmentDistribution = labelStyle.fillsEqually ? .fillEqually : .fit
        var weights: [CGFloat] = []
        for (index, segment) in segments.enumerated() {
            let text = labelStyle.usesShortTitles ? segment.label.shortTitle : segment.label.title
            control.setLabel(text, forSegment: index)
            control.setToolTip(segment.toolTip, forSegment: index)
            if segment.attention, let image {
                control.setImage(image, forSegment: index)
                control.setImageScaling(.scaleNone, forSegment: index)
            }
            let width = CGFloat(Self.segmentWidth(text, font: font)) + (segment.attention ? imageWidth : 0)
            weights.append(width)
        }
        control.tabSegments = segments
        // Equal segments share the width evenly; fitted ones in proportion to their content (accessibility frames).
        control.segmentWeights = labelStyle.fillsEqually ? Array(repeating: 1, count: segments.count) : weights
        if segments.indices.contains(selected) { control.selectedSegment = selected }
        control.target = self
        control.action = #selector(changed(_:))
        control.container = self
        // The bar, not the control, is the tab group (r1 U8): the control and its cell stay out of the tree.
        control.setAccessibilityElement(false)
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)

        var constraints = [control.centerYAnchor.constraint(equalTo: centerYAnchor)]
        if labelStyle.fillsEqually {
            constraints += [
                control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuKit.rowInset),
                control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuKit.rowInset),
            ]
        } else {
            // Fitted segments keep their own widths, centered; at worst they shrink to the insets and truncate.
            constraints += [
                control.centerXAnchor.constraint(equalTo: centerXAnchor),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: MenuKit.rowInset),
                control.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuKit.rowInset),
            ]
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        NSLayoutConstraint.activate(constraints)
    }

    @objc private func changed(_ sender: NSSegmentedControl) {
        control.selectionDidChange()
        let index = sender.selectedSegment
        guard segments.indices.contains(index) else { return }
        onSelect(index)
    }

    // MARK: Accessibility (r1 U8)

    // The bar is the tab group: "Menu tabs", with one tab button per segment ("tab 2 of 3"). A plain NSView's
    // NSAccessibility overrides are always what AppKit asks, whereas NSSegmentedControl may answer through its cell,
    // whose own segment elements speak the drawn (short) label with no ", on" or ", needs attention" (A1). HW-25.

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }
    override func accessibilityLabel() -> String? { MenuTabs.barLabel }
    override func accessibilityHelp() -> String? { help }
    override func accessibilityChildren() -> [Any]? { control.tabElements }
    override func accessibilityTabs() -> [Any]? { control.tabElements }
    override func accessibilitySelectedChildren() -> [Any]? { control.selectedTabElements }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        if let element = control.tabElement(at: point) { return element }
        return self
    }
}

/// The segmented control and its segment elements. AppKit's own segment elements speak the visible label (a short
/// title when the full ones don't fit), while A1 wants the full title, plus ", on" or ", needs attention". Each element
/// is a tab button (VoiceOver: "Displays, selected, tab 2 of 3") that VO-Space selects through the control's own
/// action. The bar (`container`) serves them; the control and its cell are ignored, and whichever of them AppKit asks
/// still answers with these elements, never AppKit's own (r1 U8, HW-25).
@MainActor private final class MenuTabSegmentedControl: NSSegmentedControl {
    override class var cellClass: AnyClass? {
        get { MenuTabSegmentedCell.self }
        set {}
    }

    var tabSegments: [MenuTabSegment] = [] {
        didSet { elements = tabSegments.indices.map { MenuTabSegmentElement(owner: self, index: $0) } }
    }
    /// Relative segment widths, for the elements' frames.
    var segmentWeights: [CGFloat] = []
    /// The tab bar: the elements' accessibility parent.
    weak var container: NSView?
    private var elements: [MenuTabSegmentElement] = []

    var tabElements: [Any] { elements }

    var selectedTabElements: [Any] { elements.indices.contains(selectedSegment) ? [elements[selectedSegment]] : [] }

    /// The element under a screen point, if any.
    func tabElement(at point: NSPoint) -> Any? {
        elements.first { $0.accessibilityFrame().contains(point) }
    }

    /// The segment's rectangle in this view's coordinates, from the relative widths.
    func segmentRect(_ index: Int) -> NSRect {
        guard segmentWeights.indices.contains(index) else { return .zero }
        let total = segmentWeights.reduce(0, +)
        guard total > 0 else { return .zero }
        let leading = segmentWeights[..<index].reduce(0, +)
        let x = bounds.minX + bounds.width * leading / total
        return NSRect(x: x, y: bounds.minY, width: bounds.width * segmentWeights[index] / total, height: bounds.height)
    }

    /// VO-Space on a segment: select it and send the action, exactly as a click does.
    func selectFromAccessibility(_ index: Int) -> Bool {
        guard tabSegments.indices.contains(index), isEnabled else { return false }
        if selectedSegment != index {
            selectedSegment = index
            sendAction(action, to: target)
        }
        return true
    }

    /// Tells VoiceOver which tab is now selected.
    func selectionDidChange() {
        NSAccessibility.post(element: container ?? self, notification: .selectedChildrenChanged)
        for element in elements { NSAccessibility.post(element: element, notification: .valueChanged) }
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { elements }
    override func accessibilitySelectedChildren() -> [Any]? { selectedTabElements }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        if let element = tabElement(at: point) { return element }
        return container ?? self
    }
}

/// The control's cell, for the path where AppKit serves the control's accessibility through it: ignored, with the
/// control's elements as its children. It changes nothing else (no drawing or tracking overrides).
@MainActor private final class MenuTabSegmentedCell: NSSegmentedCell {
    private var owner: MenuTabSegmentedControl? { controlView as? MenuTabSegmentedControl }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { owner?.tabElements }
    override func accessibilitySelectedChildren() -> [Any]? { owner?.selectedTabElements }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let owner else { return nil }
        if let element = owner.tabElement(at: point) { return element }
        return owner.container ?? owner
    }
}

@MainActor private final class MenuTabSegmentElement: NSAccessibilityElement {
    /// AXTabButton (NSAccessibilityTabButtonSubrole, which the SDK doesn't import as a `Subrole` member): what
    /// NSTabView's tabs report, so VoiceOver says "tab 2 of 3".
    private static let tabButton = NSAccessibility.Subrole(rawValue: "AXTabButton")

    private weak var owner: MenuTabSegmentedControl?
    private let index: Int

    init(owner: MenuTabSegmentedControl, index: Int) {
        self.owner = owner
        self.index = index
        super.init()
    }

    private var segment: MenuTabSegment? {
        guard let owner, owner.tabSegments.indices.contains(index) else { return nil }
        return owner.tabSegments[index]
    }

    private var isSelected: Bool { owner?.selectedSegment == index }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { Self.tabButton }
    override func accessibilityLabel() -> String? { segment?.accessibilityLabel }
    override func accessibilityHelp() -> String? { segment?.accessibilityHelp }
    override func accessibilityValue() -> Any? { NSNumber(value: isSelected ? 1 : 0) }
    override func isAccessibilitySelected() -> Bool { isSelected }
    override func isAccessibilityEnabled() -> Bool { owner?.isEnabled ?? false }
    override func accessibilityParent() -> Any? { owner?.container ?? owner }

    override func accessibilityFrame() -> NSRect {
        guard let owner else { return .zero }
        return NSAccessibility.screenRect(fromView: owner, rect: owner.segmentRect(index))
    }

    override func accessibilityPerformPress() -> Bool { owner?.selectFromAccessibility(index) ?? false }
}
