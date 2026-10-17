import AppKit
import QuartzCore
import SnapticKit

/// What the user asked for from a PIP window's own context menu.
enum PIPWindowCommand: Equatable {
    case stop
    case togglePause
    case hide
    case toggleClickThrough
    case beginCrop
    case resetCrop
    case toggleTitleBar
    case setLevel(PIPLevel)
    case setOpacity(Double)
}

/// A floating PIP window or a full-screen stream window (PLAN §10). It shows frames
/// it is given, lays them out (crop already applied by the capture; rotation, flips,
/// scaling and underscan here) and reports user interaction through closures. It
/// never captures anything itself.
@MainActor final class PIPWindow: NSObject, NSWindowDelegate {
    enum Mode: Equatable { case floating, fullScreen }

    let mode: Mode
    private let window: PIPNSWindow
    private let content: PIPContentView
    private var configuration: PIPConfiguration
    private var visiblePixels = PIPSize(width: 16, height: 9)
    private var currentFrame: PIPFrame?
    private var frameWork: DispatchWorkItem?
    private var placed = false
    private var closed = false
    private(set) var isOccluded = false
    /// Shown in the context menu (the controller owns the state).
    var isPaused = false

    var onClose: (() -> Void)?
    /// The window moved or resized (debounced): its frame in global points.
    var onFrameChange: ((PIPRect) -> Void)?
    var onOcclusion: ((Bool) -> Void)?
    /// A crop drawn on the window, in normalized source space; nil = cancelled.
    var onCrop: ((PIPRect?) -> Void)?
    /// ⌘-click: the point in the content (normalized, top-left origin).
    var onCommandClick: ((PIPPoint) -> Void)?
    var onCommand: ((PIPWindowCommand) -> Void)?

    init(mode: Mode, configuration: PIPConfiguration) {
        self.mode = mode
        self.configuration = configuration
        let initial = NSRect(x: 0, y: 0, width: 480, height: 270)
        let style: NSWindow.StyleMask = mode == .fullScreen ? [.borderless] : Self.style(for: configuration)
        window = PIPNSWindow(contentRect: initial, styleMask: style, backing: .buffered, defer: false)
        content = PIPContentView(frame: initial)
        super.init()
        content.owner = self
        window.contentView = content
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Best effort only; capture filters exclude Snaptic explicitly (macos-display-apis §11).
        window.sharingType = .none
        window.backgroundColor = .black
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.animationBehavior = .utilityWindow
        window.title = configuration.name
        window.setAccessibilityTitle(configuration.name)
    }

    var windowNumber: Int { window.windowNumber }
    var isVisible: Bool { window.isVisible }
    var screen: NSScreen? { window.screen }

    /// The content area in device pixels.
    var contentPixelSize: PIPSize {
        let size = content.bounds.size
        let scale = Double(window.backingScaleFactor)
        return PIPSize(width: Double(size.width) * scale, height: Double(size.height) * scale)
    }

    // MARK: Configuration

    func apply(_ c: PIPConfiguration, visiblePixels: PIPSize, targetScreen: NSScreen?) {
        guard !closed else { return }
        configuration = c
        if visiblePixels.width > 0, visiblePixels.height > 0 { self.visiblePixels = visiblePixels }
        window.title = c.name
        window.setAccessibilityTitle(c.name)
        window.alphaValue = CGFloat(c.opacity)
        switch mode {
        case .floating:
            let style = Self.style(for: c)
            if window.styleMask != style { window.styleMask = style }
            window.level = Self.level(c.level)
            window.collectionBehavior = c.level == .aboveAll
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .auxiliary]
                : [.fullScreenAuxiliary, .auxiliary]
            window.ignoresMouseEvents = c.clickThrough
            window.isMovable = !c.lockPosition
            window.hasShadow = c.shadow
            let aspect = NSSize(width: self.visiblePixels.width, height: self.visiblePixels.height)
            if c.lockAspect {
                window.contentAspectRatio = aspect
            } else {
                window.resizeIncrements = NSSize(width: 1, height: 1)
            }
            if !placed {
                place(c)
                placed = true
            } else if c.lockAspect {
                conformToAspect()
            }
        case .fullScreen:
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.hasShadow = false
            if let screen = targetScreen, window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
            placed = true
        }
        content.configuration = c
        content.visiblePixels = self.visiblePixels
        content.mode = mode
        content.backingScale = Double(window.backingScaleFactor)
        content.needsLayout = true
    }

    private static func style(for c: PIPConfiguration) -> NSWindow.StyleMask {
        c.showTitleBar ? [.titled, .closable, .resizable, .fullSizeContentView] : [.borderless, .resizable]
    }

    private static func level(_ level: PIPLevel) -> NSWindow.Level {
        switch level {
        case .normal: return .normal
        case .floating: return .floating
        case .aboveAll: return .statusBar
        }
    }

    /// The saved frame when it is still on a screen; otherwise a corner of the main screen.
    private func place(_ c: PIPConfiguration) {
        if let f = c.windowFrame {
            let rect = NSRect(x: f.x, y: f.y, width: f.width, height: f.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                window.setFrame(rect, display: false)
                return
            }
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let width = min(480, max(160, area.width / 3))
        let height = width * CGFloat(visiblePixels.height / max(visiblePixels.width, 1))
        window.setContentSize(NSSize(width: width, height: height))
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: area.maxX - frame.width - 20, y: area.maxY - frame.height - 20))
    }

    private func conformToAspect() {
        let current = window.contentRect(forFrameRect: window.frame)
        guard current.width > 0, visiblePixels.width > 0 else { return }
        let height = current.width * CGFloat(visiblePixels.height / visiblePixels.width)
        guard abs(height - current.height) > 1 else { return }
        var rect = current
        rect.origin.y += current.height - height
        rect.size.height = height
        window.setFrame(window.frameRect(forContentRect: rect), display: true)
    }

    // MARK: Showing

    func show() {
        guard !closed else { return }
        window.orderFrontRegardless()
    }

    func hide() {
        guard !closed else { return }
        window.orderOut(nil)
    }

    func close() {
        guard !closed else { return }
        closed = true
        frameWork?.cancel()
        frameWork = nil
        currentFrame = nil
        content.clear()
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        onClose = nil
        onFrameChange = nil
        onOcclusion = nil
        onCrop = nil
        onCommandClick = nil
        onCommand = nil
    }

    /// Keeps the frame (and its buffer) until the next one replaces it.
    func display(_ frame: PIPFrame) {
        guard !closed else { return }
        currentFrame = frame
        content.show(frame)
    }

    /// Privacy: lock, sleep and resign clear the last frame.
    func clearFrame() {
        currentFrame = nil
        content.clear()
    }

    func setStatus(_ text: String?) {
        content.setStatus(text)
    }

    func beginCrop() {
        guard mode == .floating, !closed else { return }
        if configuration.clickThrough { window.ignoresMouseEvents = false }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        content.beginCrop()
    }

    // MARK: From the content view

    fileprivate func cropFinished(start: PIPPoint, end: PIPPoint) {
        window.ignoresMouseEvents = configuration.clickThrough
        let crop = PIPGeometry.cropFromDrag(start: start, end: end, current: configuration.crop, rotation: configuration.rotation,
                                            flipHorizontal: configuration.flipHorizontal, flipVertical: configuration.flipVertical)
        onCrop?(crop ?? configuration.crop)
    }

    fileprivate func cropCancelled() {
        window.ignoresMouseEvents = configuration.clickThrough
    }

    fileprivate func commandClicked(at point: PIPPoint) {
        onCommandClick?(point)
    }

    fileprivate func dragWindow(with event: NSEvent) {
        guard mode == .floating, !configuration.lockPosition else { return }
        window.performDrag(with: event)
    }

    fileprivate func contextMenu() -> NSMenu? {
        guard mode == .floating else { return nil }
        let menu = NSMenu()
        let send: (PIPWindowCommand) -> Void = { [weak self] command in self?.onCommand?(command) }
        menu.addItem(PIPWindowMenuItem(L("Stop"), { send(.stop) }))
        menu.addItem(PIPWindowMenuItem(isPaused ? L("Resume") : L("Pause"), { send(.togglePause) }))
        menu.addItem(PIPWindowMenuItem(L("Hide"), { send(.hide) }))
        menu.addItem(.separator())
        menu.addItem(PIPWindowMenuItem(L("Crop…"), { send(.beginCrop) }))
        let reset = PIPWindowMenuItem(L("Reset Crop"), { send(.resetCrop) })
        reset.isEnabled = configuration.crop != nil
        menu.addItem(reset)
        menu.addItem(PIPWindowMenuItem(configuration.showTitleBar ? L("Hide Title Bar") : L("Show Title Bar"), { send(.toggleTitleBar) }))
        menu.addItem(PIPWindowMenuItem(L("Click Through (⌃⌥⌘P turns it off)"), { send(.toggleClickThrough) }))

        let levels = NSMenu()
        for (level, title) in [(PIPLevel.normal, L("Normal")), (.floating, L("Floating")), (.aboveAll, L("Above Everything"))] {
            let item = PIPWindowMenuItem(title, { send(.setLevel(level)) })
            item.state = configuration.level == level ? .on : .off
            levels.addItem(item)
        }
        let levelItem = NSMenuItem(title: L("Window Level"), action: nil, keyEquivalent: "")
        levelItem.submenu = levels
        menu.addItem(levelItem)

        let opacity = NSMenu()
        for value in [1.0, 0.75, 0.5, 0.25] {
            let item = PIPWindowMenuItem("\(Int(value * 100))%", { send(.setOpacity(value)) })
            item.state = abs(configuration.opacity - value) < 0.01 ? .on : .off
            opacity.addItem(item)
        }
        let opacityItem = NSMenuItem(title: L("Opacity"), action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity
        menu.addItem(opacityItem)
        return menu
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard mode == .floating, configuration.snapToQuarters else { return frameSize }
        let proposed = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let snapped = PIPGeometry.snapped(PIPSize(width: Double(proposed.width), height: Double(proposed.height)),
                                          visible: visiblePixelsInPoints())
        return sender.frameRect(forContentRect: NSRect(x: 0, y: 0, width: snapped.width, height: snapped.height)).size
    }

    /// 25% steps are of the source's size in points on this screen.
    private func visiblePixelsInPoints() -> PIPSize {
        let scale = max(Double(window.backingScaleFactor), 1)
        return PIPSize(width: visiblePixels.width / scale, height: visiblePixels.height / scale)
    }

    func windowDidMove(_ notification: Notification) { scheduleFrameReport() }
    func windowDidResize(_ notification: Notification) {
        content.needsLayout = true
        scheduleFrameReport()
    }
    func windowDidChangeBackingProperties(_ notification: Notification) {
        content.backingScale = Double(window.backingScaleFactor)
        content.needsLayout = true
        scheduleFrameReport()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        let occluded = !window.occlusionState.contains(.visible)
        guard occluded != isOccluded else { return }
        isOccluded = occluded
        onOcclusion?(occluded)
    }

    private func scheduleFrameReport() {
        frameWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                let f = self.window.frame
                self.onFrameChange?(PIPRect(x: Double(f.minX), y: Double(f.minY), width: Double(f.width), height: Double(f.height)))
            }
        }
        frameWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

/// Borderless windows need this to take key (crop drawing, Esc).
private final class PIPNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PIPWindowMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire() { handler() }
}

/// Draws the frame with rotation, flips and scaling; handles crop drawing and clicks.
private final class PIPContentView: NSView {
    weak var owner: PIPWindow?
    var configuration = PIPConfiguration()
    var visiblePixels = PIPSize(width: 16, height: 9)
    var mode: PIPWindow.Mode = .floating
    var backingScale: Double = 2

    private let frameLayer = CALayer()
    private let cropLayer = CAShapeLayer()
    private let statusLabel = NSTextField(labelWithString: "")
    private var contentRect = CGRect.zero
    private var cropping = false
    private var dragStart: CGPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        frameLayer.contentsGravity = .resize
        frameLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(frameLayer)
        cropLayer.fillColor = NSColor.systemYellow.withAlphaComponent(0.15).cgColor
        cropLayer.strokeColor = NSColor.systemYellow.cgColor
        cropLayer.lineWidth = 2
        cropLayer.lineDashPattern = [6, 4]
        cropLayer.isHidden = true
        layer?.addSublayer(cropLayer)
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        statusLabel.shadow = {
            let s = NSShadow()
            s.shadowColor = .black
            s.shadowBlurRadius = 3
            return s
        }()
        addSubview(statusLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L("Picture in Picture"))
    }

    required init?(coder: NSCoder) { return nil }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let bounds = PIPSize(width: Double(self.bounds.width), height: Double(self.bounds.height))
        let r: PIPRect
        if mode == .fullScreen {
            r = PIPGeometry.contentRect(contentPixels: visiblePixels, in: bounds, scaling: configuration.scaling,
                                        underscanPercent: configuration.underscanPercent, backingScale: backingScale)
        } else {
            r = PIPGeometry.contentRect(contentPixels: visiblePixels, in: bounds, scaling: .fit, underscanPercent: 100,
                                        backingScale: backingScale)
        }
        let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        contentRect = rect
        let quarter = configuration.isQuarterTurn
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.setAffineTransform(.identity)
        frameLayer.bounds = CGRect(x: 0, y: 0, width: quarter ? rect.height : rect.width, height: quarter ? rect.width : rect.height)
        frameLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        // Clockwise as seen; flips apply before the rotation (PIPGeometry.sourcePoint).
        let angle = -CGFloat(configuration.rotation) * .pi / 180
        let transform = CGAffineTransform(rotationAngle: angle)
            .scaledBy(x: configuration.flipHorizontal ? -1 : 1, y: configuration.flipVertical ? -1 : 1)
        frameLayer.setAffineTransform(transform)
        let nearest = configuration.integerScaling
            || (mode == .fullScreen && (configuration.scaling == .integer || configuration.scaling == .oneToOne))
        frameLayer.magnificationFilter = nearest ? .nearest : .linear
        frameLayer.minificationFilter = nearest ? .nearest : .linear
        frameLayer.contentsScale = CGFloat(backingScale)
        cropLayer.frame = self.bounds
        CATransaction.commit()
        let labelSize = statusLabel.fittingSize
        statusLabel.frame = NSRect(x: (self.bounds.width - labelSize.width) / 2, y: (self.bounds.height - labelSize.height) / 2,
                                   width: labelSize.width, height: labelSize.height)
    }

    func show(_ frame: PIPFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.contents = frame.surface
        // The frame's rect is top-left based; layer unit space is bottom-left on macOS.
        let r = frame.contentRect
        frameLayer.contentsRect = CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
        CATransaction.commit()
        if !statusLabel.isHidden, !cropping { setStatus(nil) }
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.contents = nil
        CATransaction.commit()
    }

    func setStatus(_ text: String?) {
        statusLabel.stringValue = text ?? ""
        statusLabel.isHidden = text == nil
        if let text { setAccessibilityValue(text) }
        needsLayout = true
    }

    func beginCrop() {
        cropping = true
        dragStart = nil
        setStatus(L("Drag to crop · Esc cancels"))
        window?.makeFirstResponder(self)
    }

    private func endCrop() {
        cropping = false
        dragStart = nil
        cropLayer.isHidden = true
        setStatus(nil)
    }

    /// Normalized (top-left origin) position in the content.
    private func normalized(_ p: CGPoint) -> PIPPoint? {
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }
        let x = min(max((p.x - contentRect.minX) / contentRect.width, 0), 1)
        let y = min(max(1 - (p.y - contentRect.minY) / contentRect.height, 0), 1)
        return PIPPoint(x: Double(x), y: Double(y))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if cropping {
            dragStart = p
            drawCrop(from: p, to: p)
            return
        }
        if event.modifierFlags.contains(.command), configuration.warpOnCommandClick, contentRect.contains(p),
           let n = normalized(p) {
            owner?.commandClicked(at: n)
            return
        }
        owner?.dragWindow(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard cropping, let start = dragStart else { return }
        drawCrop(from: start, to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard cropping, let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        if let a = normalized(start), let b = normalized(end) { owner?.cropFinished(start: a, end: b) }
        endCrop()
    }

    override func keyDown(with event: NSEvent) {
        if cropping, event.keyCode == 53 {
            endCrop()
            owner?.cropCancelled()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        cropping ? nil : owner?.contextMenu()
    }

    private func drawCrop(from a: CGPoint, to b: CGPoint) {
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            .intersection(contentRect)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cropLayer.isHidden = rect.isNull
        cropLayer.path = rect.isNull ? nil : CGPath(rect: rect, transform: nil)
        CATransaction.commit()
    }
}
