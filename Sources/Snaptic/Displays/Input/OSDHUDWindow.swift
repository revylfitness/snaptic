import AppKit
import SnapticKit

/// Snaptic's own OSD HUD (PLAN §8.3, macos27.md): one non-activating panel per screen at
/// `.screenSaver + 2`, on every Space, click-through, excluded from capture, with an
/// active `NSVisualEffectView`. Classic is the big square; Rounded is the 27.2-style
/// capsule with a 16-segment bar. Fades after 1.2 s (no animation with Reduce Motion).
@MainActor final class OSDHUDWindow: NSObject {
    struct Content: Equatable {
        var symbol: String
        /// 0…1 of the bar; nil hides the bar (text-only OSDs).
        var fraction: Double?
        /// Above 1 for XDR: the part beyond 100% is drawn brighter.
        var overflow: Double = 0
        var valueText: String?
        var detail: String?
        var title: String?
        var accessibilityText: String
    }

    static let segments = 16
    static let visibleFor: TimeInterval = 1.2

    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private let icon = NSImageView()
    private let bar = SegmentBar()
    private let valueLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private(set) var style: OSDStyle = .classic

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        icon.contentTintColor = .labelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.textColor = .labelColor
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.alignment = .center
        detailLabel.textColor = .secondaryLabelColor
        for v in [icon, bar, valueLabel, detailLabel] as [NSView] { effect.addSubview(v) }
        panel.contentView = effect
        panel.setAccessibilityElement(false)
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows `content` at `position` on `screen`. `anchor` is the status item frame (screen
    /// coordinates) for the under-the-icon position.
    func show(_ content: Content, style: OSDStyle, position: OSDPosition, on screen: NSScreen, anchor: NSRect?,
              showValue: Bool) {
        self.style = style
        let image = NSImage(systemSymbolName: content.symbol, accessibilityDescription: nil)
        icon.image = image
        bar.fraction = content.fraction ?? 0
        bar.overflow = content.overflow
        bar.isHidden = content.fraction == nil
        valueLabel.stringValue = showValue ? (content.valueText ?? "") : ""
        valueLabel.isHidden = !showValue || content.valueText == nil
        detailLabel.stringValue = content.detail ?? content.title ?? ""
        detailLabel.isHidden = detailLabel.stringValue.isEmpty
        layout(style: style)
        panel.setFrameOrigin(origin(for: panel.frame.size, position: position, screen: screen, anchor: anchor))
        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.fade() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.orderOut(nil)
    }

    private func fade() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideWork == nil || self.panel.alphaValue < 0.05 else { return }
                self.panel.orderOut(nil)
            }
        })
        hideWork = nil
    }

    private func layout(style: OSDStyle) {
        switch style {
        case .classic:
            let size = NSSize(width: 200, height: 200)
            panel.setContentSize(size)
            effect.frame = NSRect(origin: .zero, size: size)
            effect.layer?.cornerRadius = 18
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            icon.frame = NSRect(x: 50, y: 78, width: 100, height: 90)
            bar.frame = NSRect(x: 22, y: 34, width: 156, height: 8)
            valueLabel.frame = NSRect(x: 20, y: 46, width: 160, height: 22)
            detailLabel.frame = NSRect(x: 10, y: 12, width: 180, height: 16)
        case .rounded:
            let size = NSSize(width: 300, height: 56)
            panel.setContentSize(size)
            effect.frame = NSRect(origin: .zero, size: size)
            effect.layer?.cornerRadius = 28
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            icon.frame = NSRect(x: 14, y: 14, width: 30, height: 28)
            let hasDetail = !detailLabel.isHidden
            bar.frame = NSRect(x: 52, y: hasDetail ? 30 : 24, width: 186, height: 8)
            valueLabel.frame = NSRect(x: 240, y: 17, width: 52, height: 22)
            detailLabel.frame = NSRect(x: 52, y: 8, width: 186, height: 16)
            detailLabel.alignment = .left
        }
        if style == .classic { detailLabel.alignment = .center }
        bar.needsDisplay = true
    }

    private func origin(for size: NSSize, position: OSDPosition, screen: NSScreen, anchor: NSRect?) -> NSPoint {
        let visible = screen.visibleFrame
        let frame = screen.frame
        let margin: CGFloat = 12
        switch position {
        case .underIcon:
            if let anchor, frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)), anchor.height <= 60 {
                var x = anchor.midX - size.width / 2
                x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
                return NSPoint(x: x, y: anchor.minY - size.height - 6)
            }
            fallthrough
        case .topRight:
            return NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        case .topCenter:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - margin)
        case .center:
            return NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        case .bottomCenter:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + frame.height * 0.12)
        }
    }
}

/// 16-segment value bar.
private final class SegmentBar: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var overflow: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let n = OSDHUDWindow.segments
        let gap: CGFloat = 2
        let w = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let filled = fraction * Double(n)
        for i in 0..<n {
            let rect = NSRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            path.fill()
            let amount = min(1, max(0, filled - Double(i)))
            if amount > 0 {
                let part = NSRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(amount), height: rect.height)
                (overflow > 0 ? NSColor.systemYellow : NSColor.labelColor).withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: part, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }
}
