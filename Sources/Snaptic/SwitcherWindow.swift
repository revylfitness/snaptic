import AppKit
import SwiftUI

/// A borderless panel that never takes focus away from the app you're in.
final class SnapticPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a thumbnail work even though the panel isn't key.
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SwitcherWindow {
    private let panel: SnapticPanel

    var level: NSWindow.Level { panel.level }

    init(rootView: AnyView) {
        let panel = SnapticPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Keep window titles and thumbnails out of screen shares and recordings.
        panel.sharingType = .none

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        background.material = .popover          // follows light / dark mode
        background.blendingMode = .behindWindow
        background.state = .active              // stay translucent even though we're not the active app
        background.maskImage = SwitcherWindow.roundedMask(radius: 18)
        background.autoresizingMask = [.width, .height]

        let host = FirstMouseHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)

        panel.contentView = background
        self.panel = panel
    }

    func setFrame(size: CGSize, centeredIn area: CGRect) {
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size).integral, display: true)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Shows the selected window full-size, in place, just under the switcher.
@MainActor
final class PreviewOverlay {
    private let panel: NSPanel
    private let imageView: NSImageView

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.sharingType = .none

        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView

        self.panel = panel
        self.imageView = imageView
    }

    func show(image: NSImage, frame: NSRect, below level: NSWindow.Level) {
        panel.level = NSWindow.Level(rawValue: level.rawValue - 1)
        imageView.image = image
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        imageView.image = nil
    }
}
