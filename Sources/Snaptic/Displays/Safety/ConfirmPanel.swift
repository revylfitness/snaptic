import AppKit
import SnapticKit

// "Keep this change?" (owner: B). PLAN §4.4: on every panel host (every visible display and
// every mirror source), level .screenSaver + 2, all Spaces and full-screen, key only for
// UI-triggered changes, keys live after 1 s (Return / ⌘K keep, Esc reverts), uptime
// countdown, VoiceOver announcement every 5 s. Follows screen changes while it shows.

enum ConfirmResult: Equatable {
    case keep, revert, timeout
}

@MainActor final class ConfirmPanel: NSObject {
    static let keyDelay: Double = 1
    static let announceEvery: Double = 5

    private var windows: [UInt32: ConfirmWindow] = [:]
    private var continuation: CheckedContinuation<ConfirmResult, Never>?
    private var timer: Timer?
    private var deadline: Double = 0
    private var shownAt: Double = 0
    private var lastAnnounce: Double = 0
    private var label = ""
    private var interactive = false
    private var hostProvider: (@MainActor () -> Set<UInt32>)?
    private var screenObserver: NSObjectProtocol?

    override init() { super.init() }

    var isShowing: Bool { continuation != nil }

    /// Shows the panel on `hosts()` (re-evaluated when screens change) until a choice or the
    /// countdown ends. Returns `.timeout` when time runs out.
    func present(label: String, seconds: Double, interactive: Bool,
                 hosts: @escaping @MainActor () -> Set<UInt32>) async -> ConfirmResult {
        if isShowing { finish(.revert) }
        return await withCheckedContinuation { (c: CheckedContinuation<ConfirmResult, Never>) in
            continuation = c
            self.label = label
            self.interactive = interactive
            hostProvider = hosts
            shownAt = SessionGate.uptime()
            deadline = shownAt + seconds
            lastAnnounce = 0
            layoutWindows()
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layoutWindows() }
            }
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            tick()
        }
    }

    /// Ends the panel from outside (sleep, session resign, quit, guard loss, a new request).
    func dismiss(_ result: ConfirmResult) { finish(result) }

    private func layoutWindows() {
        guard isShowing else { return }
        let hosts = hostProvider?() ?? []
        var targets: [UInt32: NSScreen] = [:]
        for id in hosts { if let s = NSScreen.screen(for: id) { targets[id] = s } }
        if targets.isEmpty, let any = NSScreen.main ?? NSScreen.screens.first, let id = any.displayID { targets[id] = any }
        for (id, w) in windows where targets[id] == nil {
            w.orderOut(nil)
            windows[id] = nil
        }
        for (id, screen) in targets {
            let w = windows[id] ?? ConfirmWindow(owner: self)
            windows[id] = w
            w.place(on: screen)
            w.orderFrontRegardless()
        }
        if interactive {
            let mouse = NSEvent.mouseLocation
            let key = windows.values.first { $0.screen.map { NSMouseInRect(mouse, $0.frame, false) } ?? false } ?? windows.values.first
            NSApp.activate(ignoringOtherApps: true)
            key?.makeKey()
        }
        tick()
    }

    private func tick() {
        guard isShowing else { return }
        let now = SessionGate.uptime()
        let remaining = max(0, deadline - now)
        let keysLive = now - shownAt >= Self.keyDelay
        let text = L("Keep this change? Reverting in \(Int(remaining.rounded(.up))) s.")
        for w in windows.values { w.update(title: label, countdown: text, enabled: keysLive) }
        if now - lastAnnounce >= Self.announceEvery {
            lastAnnounce = now
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: "\(label). \(text)",
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        if remaining <= 0 { finish(.timeout) }
    }

    fileprivate func choose(_ result: ConfirmResult) {
        guard isShowing, SessionGate.uptime() - shownAt >= Self.keyDelay else { return }
        finish(result)
    }

    private func finish(_ result: ConfirmResult) {
        timer?.invalidate()
        timer = nil
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
        for w in windows.values { w.orderOut(nil) }
        windows = [:]
        hostProvider = nil
        let c = continuation
        continuation = nil
        c?.resume(returning: result)
    }
}

/// One panel window; keyboard handling lives here so ⌘K and Esc work while it is key.
@MainActor private final class ConfirmWindow: NSPanel {
    private weak var owner: ConfirmPanel?
    private let titleField = NSTextField(labelWithString: "")
    private let countdownField = NSTextField(labelWithString: "")
    private let keepButton: NSButton
    private let revertButton: NSButton

    init(owner: ConfirmPanel) {
        self.owner = owner
        keepButton = NSButton(title: L("Keep"), target: nil, action: nil)
        revertButton = NSButton(title: L("Revert"), target: nil, action: nil)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 130),
                   styleMask: [.titled, .nonactivatingPanel, .hudWindow, .utilityWindow], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        title = L("Snaptic")
        keepButton.target = self
        keepButton.action = #selector(keepPressed)
        keepButton.keyEquivalent = "\r"
        revertButton.target = self
        revertButton.action = #selector(revertPressed)
        revertButton.keyEquivalent = "\u{1b}"
        titleField.font = .boldSystemFont(ofSize: 14)
        titleField.lineBreakMode = .byTruncatingTail
        countdownField.setAccessibilityRole(.staticText)
        let buttons = NSStackView(views: [revertButton, keepButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [titleField, countdownField, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        contentView = stack
        setAccessibilityLabel(L("Keep display change"))
    }

    override var canBecomeKey: Bool { true }

    func place(on screen: NSScreen) {
        let f = screen.frame
        let size = frame.size
        setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
    }

    func update(title: String, countdown: String, enabled: Bool) {
        titleField.stringValue = title
        countdownField.stringValue = countdown
        keepButton.isEnabled = enabled
        revertButton.isEnabled = enabled
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "k" {
            owner?.choose(.keep)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { owner?.choose(.revert) }

    @objc private func keepPressed() { owner?.choose(.keep) }
    @objc private func revertPressed() { owner?.choose(.revert) }
}
