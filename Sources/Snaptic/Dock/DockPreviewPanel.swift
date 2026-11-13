import AppKit
import SwiftUI
import SnapticKit

/// The Dock preview panel (PLAN 0.5 §4.3, §4.7): a non-activating `SnapticPanel` set up like the switcher's.
/// - It never becomes key or main, joins every Space and sits over full-screen apps (M14). It stays out of screen
///   shares and recordings (`sharingType = .none`).
/// - Level `.statusBar`: above the Dock, below menus, so the Dock's own menu is never covered (M36). Provisional
///   (S0-6).
/// - It fades in and out over 0.15 s (§4.7); a fade-out that a new show interrupts never orders the panel out.
/// - A tracking area reports the pointer entering, leaving and moving inside it (`onPointer`), for the policy's
///   `panelEntered`, `panelExited` and `pointerMovedInPanel`.
/// - The controller creates it only while a preview is shown and releases it after the fade-out (ground rule).
@MainActor
final class DockPreviewPanel {
    /// §4.7: the fade in and out.
    static let fade: Double = 0.15
    static let cornerRadius: CGFloat = 14

    private let panel: SnapticPanel
    private let tracker: DockPanelTrackingView
    /// Bumped by each show and hide, so a finished fade-out from before a show leaves the panel up.
    private var fadeGeneration = 0
    /// Ordered front and not fading out.
    private(set) var isShown = false

    /// The window number our own window reads leave out (§4.3).
    var windowNumber: Int { panel.windowNumber }
    var frame: CGRect { panel.frame }

    init(rootView: AnyView, onPointer: @escaping @MainActor () -> Void) {
        let initial = NSRect(x: 0, y: 0, width: 320, height: 200)
        let panel = SnapticPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        // Window titles and thumbnails stay out of screen shares and recordings.
        panel.sharingType = .none
        panel.alphaValue = 0

        let tracker = DockPanelTrackingView(frame: initial)
        tracker.onPointer = onPointer
        tracker.autoresizingMask = [.width, .height]

        let background = NSVisualEffectView(frame: initial)
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        background.autoresizingMask = [.width, .height]
        tracker.addSubview(background)

        let host = FirstMouseHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = initial
        host.autoresizingMask = [.width, .height]
        tracker.addSubview(host)

        panel.contentView = tracker
        self.panel = panel
        self.tracker = tracker
    }

    /// Cocoa coordinates. The frame is used as given, so the policy's corridor matches the panel exactly.
    func place(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// Orders the panel front and fades it in. Nothing happens if it's already shown.
    func show() {
        guard !isShown else { return }
        isShown = true
        fadeGeneration += 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 1
        }
    }

    /// Fades the panel out and orders it out; `done` runs once it's gone, unless a show came first.
    func hide(_ done: @escaping @MainActor () -> Void) {
        guard isShown else {
            done()
            return
        }
        isShown = false
        fadeGeneration += 1
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeGeneration == generation else { return }
                self.panel.orderOut(nil)
                done()
            }
        })
    }

    /// Gone at once, with no fade (the module stopped).
    func close() {
        isShown = false
        fadeGeneration += 1
        tracker.onPointer = nil
        panel.alphaValue = 0
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

/// The panel's content view: its tracking area reports the pointer while the app isn't active. The controller reads
/// where the pointer is from `NSEvent.mouseLocation`, so enter, exit and move all go to one handler.
private final class DockPanelTrackingView: NSView {
    var onPointer: (@MainActor () -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onPointer?() }
    override func mouseExited(with event: NSEvent) { onPointer?() }
    override func mouseMoved(with event: NSEvent) { onPointer?() }
}
