import AppKit
import Combine
import Darwin
import SnapticKit

/// Click-through overlay windows (PLAN §6.3): dim, EDR (XDR A), redraw nudge, menu-bar
/// strip, rounded corners and identify. All are excluded from capture (`sharingType =
/// .none`), except on displays whose driver captures the screen (DisplayLink, AirPlay,
/// Sidecar, foreign virtual), where `.readOnly` keeps the dimming visible on the device (R5.8).
@MainActor final class OverlayService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .overlays }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    /// Dim alpha cap unless dim to black is allowed for that overlay.
    static let maxDimAlpha = 0.92

    private final class Entry {
        let token: OverlayToken
        let window: NSWindow
        var alpha: Double = 0
        var allowBlack = false
        var color: NSColor = .black

        init(token: OverlayToken, window: NSWindow) {
            self.token = token
            self.window = window
        }
    }

    private var entries: [UInt64: Entry] = [:]
    private var nextID: UInt64 = 0
    private var authHidden = false
    private var observers: [NSObjectProtocol] = []

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutAll() }
        })
    }

    func deactivate() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        removeAll()
        authHidden = false
        context = nil
    }

    // MARK: API

    func add(_ kind: OverlayKind, on desktopID: UInt32) -> OverlayToken? {
        guard context != nil else { return nil }
        nextID &+= 1
        let token = OverlayToken(id: nextID, kind: kind, desktopID: desktopID)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1
        window.animationBehavior = .none
        switch kind {
        case .menuBarStrip:
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        default:
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        }
        window.sharingType = sharingType(for: desktopID)
        let entry = Entry(token: token, window: window)
        entries[token.id] = entry
        switch kind {
        case .menuBarStrip:
            window.backgroundColor = .black
            entry.alpha = 1
        case .roundedCorners:
            entry.alpha = 1
        default:
            window.backgroundColor = NSColor.black.withAlphaComponent(0)
        }
        layout(entry)
        return token
    }

    /// Dim/strip opacity 0…1. Dim overlays cap at 0.92 unless dim to black is allowed.
    func update(_ token: OverlayToken, alpha: Double) {
        guard let entry = entries[token.id] else { return }
        var a = alpha.isFinite ? min(1, max(0, alpha)) : 0
        if token.kind == .dim, !entry.allowBlack { a = min(a, Self.maxDimAlpha) }
        entry.alpha = a
        applyAppearance(entry)
    }

    /// Allows a dim overlay to reach full black (dim to black with another visible display).
    func setAllowsBlack(_ token: OverlayToken, _ allow: Bool) {
        guard let entry = entries[token.id] else { return }
        entry.allowBlack = allow
        update(token, alpha: entry.alpha)
    }

    func setColor(_ token: OverlayToken, _ color: NSColor) {
        guard let entry = entries[token.id] else { return }
        entry.color = color
        applyAppearance(entry)
    }

    /// Custom content (EDR layer, corner masks, identify label). Sized to the window.
    func setContentView(_ view: NSView, for token: OverlayToken) {
        guard let entry = entries[token.id] else { return }
        view.frame = NSRect(origin: .zero, size: entry.window.frame.size)
        view.autoresizingMask = [.width, .height]
        entry.window.contentView = view
        applyAppearance(entry)
    }

    func contentView(for token: OverlayToken) -> NSView? { entries[token.id]?.window.contentView }

    func screen(for token: OverlayToken) -> NSScreen? { entries[token.id]?.window.screen }

    func remove(_ token: OverlayToken) {
        guard let entry = entries.removeValue(forKey: token.id) else { return }
        entry.window.orderOut(nil)
        entry.window.contentView = nil
    }

    func removeAll() {
        for entry in entries.values {
            entry.window.orderOut(nil)
            entry.window.contentView = nil
        }
        entries.removeAll()
    }

    /// Removes every overlay of one kind (panic participants use this).
    func removeAll(kind: OverlayKind) {
        for (id, entry) in entries where entry.token.kind == kind {
            entry.window.orderOut(nil)
            entry.window.contentView = nil
            entries[id] = nil
        }
    }

    var tokens: [OverlayToken] { entries.values.map(\.token) }

    /// Strongest dim on screen (0…1), for the "overlay dim below 30%" long-arm rule.
    var strongestDim: Double {
        entries.values.filter { $0.token.kind == .dim }.map(\.alpha).max() ?? 0
    }

    /// While an authentication window is on screen, every full-screen overlay is ordered out (R5.7).
    func setAuthenticationHidden(_ hidden: Bool) {
        guard authHidden != hidden else { return }
        authHidden = hidden
        for entry in entries.values { applyAppearance(entry) }
    }

    // MARK: Layout

    private func sharingType(for desktopID: UInt32) -> NSWindow.SharingType {
        switch context?.registry.info(desktopID: desktopID)?.transport {
        case .displayLink?, .airplay?, .sidecar?, .foreignVirtual?:
            return .readOnly
        default:
            return .none
        }
    }

    /// Overlays on a mirror set go on the desktop (source) display.
    private func screenID(for desktopID: UInt32) -> UInt32 {
        if let source = context?.registry.info(desktopID: desktopID)?.mirrorOf { return source }
        return desktopID.mirrorSource ?? desktopID
    }

    private func layoutAll() {
        for entry in entries.values {
            entry.window.sharingType = sharingType(for: entry.token.desktopID)
            layout(entry)
        }
    }

    private func layout(_ entry: Entry) {
        guard let screen = NSScreen.screen(for: screenID(for: entry.token.desktopID)) else {
            entry.window.orderOut(nil)
            return
        }
        var frame = screen.frame
        if entry.token.kind == .menuBarStrip {
            let reserved = screen.frame.maxY - screen.visibleFrame.maxY
            let notch = screen.safeAreaInsets.top
            let height = max(reserved, notch)
            guard height > 0 else {
                // The menu bar auto-hides on this display: no strip.
                entry.window.orderOut(nil)
                return
            }
            frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        } else if entry.token.kind == .nudge {
            frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
        }
        entry.window.setFrame(frame, display: false)
        entry.window.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        applyAppearance(entry)
    }

    private func applyAppearance(_ entry: Entry) {
        let kind = entry.token.kind
        let fullScreen = kind == .dim || kind == .edr || kind == .roundedCorners
        if authHidden && fullScreen {
            entry.window.orderOut(nil)
            return
        }
        guard NSScreen.screen(for: screenID(for: entry.token.desktopID)) != nil else {
            entry.window.orderOut(nil)
            return
        }
        switch kind {
        case .dim:
            entry.window.backgroundColor = entry.color.withAlphaComponent(CGFloat(entry.alpha))
            if entry.alpha <= 0.001 {
                entry.window.orderOut(nil)
                return
            }
        case .menuBarStrip, .identify:
            entry.window.backgroundColor = entry.color.withAlphaComponent(CGFloat(entry.alpha))
        case .nudge:
            entry.window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        case .edr, .roundedCorners:
            entry.window.backgroundColor = .clear
        }
        if kind == .menuBarStrip, entry.window.frame.height <= 0 { return }
        entry.window.orderFrontRegardless()
    }
}

struct OverlayToken: Hashable, Sendable {
    let id: UInt64
    let kind: OverlayKind
    let desktopID: UInt32
}

/// Watches for system authentication windows (PLAN §4.10(10), R5.7). Best effort: polls
/// `CGWindowListCopyWindowInfo` at 2 Hz while enabled, and on app activation; while an
/// authentication window is present it re-checks every 2 s, for at most 60 s per episode.
@MainActor final class AuthWindowWatcher {
    /// Called with true when an authentication window appears, false when it goes away
    /// (or the 60 s episode cap ends).
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var isPresent = false
    private var timer: Timer?
    private var episodeStart: TimeInterval?
    private var episodeExpired = false
    private var activationObserver: NSObjectProtocol?

    static let pollInterval: TimeInterval = 0.5
    static let episodeInterval: TimeInterval = 2
    static let episodeLimit: TimeInterval = 60

    /// Full paths under /System; basenames of the processes that draw authentication UI.
    static let processNames: Set<String> = [
        "SecurityAgent", "coreautha", "UserNotificationCenter", "universalAccessAuthWarn", "CoreServicesUIAgent",
        "AuthenticationServicesAgent", "loginwindow",
    ]

    init() {}

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }

    private func start() {
        schedule(Self.pollInterval)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activationObserver = nil
        episodeStart = nil
        episodeExpired = false
        if isPresent {
            isPresent = false
            onChange?(false)
        }
    }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = interval / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        guard isEnabled else { return }
        let found = Self.authenticationWindowOnScreen()
        let now = ProcessInfo.processInfo.systemUptime
        if found {
            if episodeStart == nil {
                episodeStart = now
                episodeExpired = false
                schedule(Self.episodeInterval)
            }
            if let start = episodeStart, now - start > Self.episodeLimit, !episodeExpired {
                episodeExpired = true
                isPresent = false
                onChange?(false)
                return
            }
            if !isPresent && !episodeExpired {
                isPresent = true
                EventLog.shared.record(.overlay, "Authentication window on screen; overlays ordered out")
                onChange?(true)
            }
        } else if episodeStart != nil {
            episodeStart = nil
            episodeExpired = false
            schedule(Self.pollInterval)
            if isPresent {
                isPresent = false
                onChange?(false)
            }
        }
    }

    static func isSessionLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Matches window owners by full executable path (under /System) and process name.
    static func authenticationWindowOnScreen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let locked = isSessionLocked()
        var checked: [Int32: Bool] = [:]
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.01 else { continue }
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                guard bounds.width > 1, bounds.height > 1 else { continue }
                let onAnyScreen = NSScreen.screens.contains { screen in
                    // CG window bounds use a top-left origin; compare against CG display bounds.
                    guard let id = screen.displayID else { return false }
                    return CGDisplayBounds(id).intersects(bounds)
                }
                guard onAnyScreen else { continue }
            }
            if let cached = checked[pid] {
                if cached { return true }
                continue
            }
            let match = isAuthProcess(pid: pid, sessionLocked: locked)
            checked[pid] = match
            if match { return true }
        }
        return false
    }

    private static func isAuthProcess(pid: Int32, sessionLocked: Bool) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return false }
        let path = String(cString: buffer)
        guard path.hasPrefix("/System/") else { return false }
        let name = (path as NSString).lastPathComponent
        guard processNames.contains(name) else { return false }
        if name == "loginwindow" { return sessionLocked }
        return true
    }
}
