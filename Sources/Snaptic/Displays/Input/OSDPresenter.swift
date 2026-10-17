import AppKit
import Combine
import SnapticKit
import SnapticShims

/// VoiceOver announcements of value changes. Independent of the `osd` feature: they're
/// made whenever VoiceOver is running (PLAN §3.7).
enum VoiceOverAnnouncer {
    @MainActor static func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, !text.isEmpty else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        return String(Int((max(0, fraction) * 100).rounded())) + "%"
    }
}

/// The OSD (PLAN §8.3): Snaptic's own HUD by default (always on 26+), the system OSD as an
/// option on 14/15, style and position from settings, shown on the affected, active or
/// main display. The broadcast (§4.10(2)) posts only {kind, value, max}, ≤ 10/s, never
/// while the session is locked.
@MainActor final class OSDPresenter: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .osd }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?
    /// The running OSD controller, for the OSD page.
    weak var controller: OSDController?

    /// Distributed notification name of the OSD broadcast (documented in the README).
    static let broadcastName = Notification.Name("app.snaptic.osd")
    static let broadcastInterval: TimeInterval = 0.1

    /// Set by OSDController (feature `osd`); when false only broadcasts and announcements happen.
    var isEnabled = true
    /// Set by OSDController (feature `osdBroadcast`).
    var broadcastEnabled = false

    private var huds: [UInt32: OSDHUDWindow] = [:]
    private var lastBroadcast: TimeInterval = 0
    private var pendingBroadcast: (OSDKind, Double, Double)?
    private var broadcastWork: DispatchWorkItem?

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) { self.context = context }

    func deactivate() {
        huds.values.forEach { $0.hide() }
        huds.removeAll()
        broadcastWork?.cancel()
        broadcastWork = nil
        pendingBroadcast = nil
        context = nil
    }

    func hideAll() { huds.values.forEach { $0.hide() } }

    // MARK: API

    func show(_ kind: OSDKind, value: Double, max: Double, on desktopID: UInt32) {
        show(kind, value: value, max: max, on: desktopID, detail: nil)
    }

    /// `detail`: optional second line (nits, "XDR paused", the display name).
    func show(_ kind: OSDKind, value: Double, max: Double, on desktopID: UInt32, detail: String?) {
        let v = value.isFinite ? value : 0
        let m = max.isFinite && max > 0 ? max : 1
        broadcast(kind, v, m)
        guard isEnabled, let context else { return }
        let config = context.config.value.keys
        let fraction = Swift.min(1, Swift.max(0, v / m))
        let overflow = v > m ? v / m - 1 : 0
        var valueText = VoiceOverAnnouncer.percent(v / m)
        if kind == .mute { valueText = v > 0 ? L("Muted") : L("Unmuted") }
        let content = OSDHUDWindow.Content(symbol: Self.symbol(kind, value: v, max: m), fraction: kind == .mute ? nil : fraction,
                                           overflow: overflow, valueText: valueText,
                                           detail: config.osdShowNits ? detail : (kind == .xdr ? detail : nil), title: nil,
                                           accessibilityText: valueText)
        if config.osdNative, SNOSD.isAvailable(), let image = Self.nativeImage(kind, value: v) {
            let filled = UInt32((fraction * 16).rounded())
            if SNOSD.show(image: image, display: target(desktopID), filled: filled, total: 16, locked: false) { return }
        }
        present(content, on: target(desktopID))
    }

    func show(_ kind: OSDKind, text: String, on desktopID: UInt32) {
        guard isEnabled, context != nil else { return }
        let content = OSDHUDWindow.Content(symbol: Self.symbol(kind, value: 1, max: 1), fraction: nil, valueText: nil,
                                           detail: nil, title: TextSanitizer.clean(text, maxScalars: 64),
                                           accessibilityText: text)
        present(content, on: target(desktopID))
    }

    // MARK: Internals

    /// The display to show on (affected, active or main).
    private func target(_ affected: UInt32) -> UInt32 {
        guard let context else { return affected }
        switch context.config.value.keys.osdTarget {
        case .affected:
            if let source = context.registry.info(desktopID: affected)?.mirrorOf { return source }
            return affected
        case .active:
            return NSScreen.main?.displayID ?? affected
        case .main:
            return CGMainDisplayID()
        }
    }

    private func present(_ content: OSDHUDWindow.Content, on id: UInt32) {
        guard let context, let screen = NSScreen.screen(for: id) ?? NSScreen.main else { return }
        let keys = context.config.value.keys
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let key = screen.displayID ?? id
        let hud = huds[key] ?? OSDHUDWindow()
        huds[key] = hud
        // One HUD on screen at a time per display; other displays' HUDs stay as they are.
        hud.show(content, style: keys.effectiveOSDStyle(osMajor: os), position: keys.effectiveOSDPosition(osMajor: os),
                 on: screen, anchor: Self.statusItemAnchor(on: screen), showValue: keys.osdShowValue)
    }

    /// Our status item's frame on `screen`, when it can be found and is plausible; the HUD
    /// falls back to top-right otherwise (on 27 hidden items can't be detected).
    static func statusItemAnchor(on screen: NSScreen) -> NSRect? {
        let candidates = NSApp.windows.filter { window in
            String(describing: type(of: window)).contains("StatusBarWindow") && window.isVisible
                && window.frame.height <= 60 && window.frame.width <= 200
                && abs(window.frame.maxY - screen.frame.maxY) < 4 && screen.frame.intersects(window.frame)
        }
        return candidates.max { $0.frame.minX < $1.frame.minX }?.frame
    }

    private func broadcast(_ kind: OSDKind, _ value: Double, _ max: Double) {
        guard broadcastEnabled, let context, context.sessionGate.isOpen, !context.sessionGate.isLocked else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastBroadcast >= Self.broadcastInterval {
            post(kind, value, max)
            return
        }
        // ≤ 10/s: keep the latest and send it when the window opens.
        pendingBroadcast = (kind, value, max)
        guard broadcastWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.broadcastWork = nil
                if let p = self.pendingBroadcast {
                    self.pendingBroadcast = nil
                    self.post(p.0, p.1, p.2)
                }
            }
        }
        broadcastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.broadcastInterval, execute: work)
    }

    private func post(_ kind: OSDKind, _ value: Double, _ max: Double) {
        lastBroadcast = ProcessInfo.processInfo.systemUptime
        // Closed enum + two numbers only: no names, titles or identifiers.
        let info: [String: Any] = ["kind": kind.rawValue, "value": (value * 1000).rounded() / 1000,
                                   "max": (max * 1000).rounded() / 1000]
        DistributedNotificationCenter.default().postNotificationName(Self.broadcastName, object: nil, userInfo: info,
                                                                     deliverImmediately: true)
    }

    static func symbol(_ kind: OSDKind, value: Double, max: Double) -> String {
        switch kind {
        case .brightness: return value / max < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .contrast: return "circle.lefthalf.filled"
        case .volume:
            let f = value / max
            if f <= 0 { return "speaker.fill" }
            return f < 0.34 ? "speaker.wave.1.fill" : (f < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        case .mute: return value > 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .xdr: return "sun.max.circle.fill"
        case .resolution: return "rectangle.arrowtriangle.2.outward"
        case .layout: return "rectangle.3.group"
        case .nightShift: return "moon.fill"
        case .input: return "rectangle.connected.to.line.below"
        }
    }

    private static func nativeImage(_ kind: OSDKind, value: Double) -> SNOSDImage? {
        switch kind {
        case .brightness: return .brightness
        case .volume: return value > 0 ? .volume : .muted
        case .mute: return value > 0 ? .muted : .volume
        default: return nil
        }
    }
}
