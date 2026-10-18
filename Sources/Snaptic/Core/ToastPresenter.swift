import AppKit
import SwiftUI
import SnapticKit

/// An optional button on a toast ("Undo", "Gather"). It can't run after its toast's
/// lifetime ends or after the toast expires. 0.3 (R5-1): extended, not redeclared, so every
/// `ToastAction(title:perform:)` call site keeps compiling.
struct ToastAction {
    let title: String
    let perform: @MainActor () -> Void
    /// R5-1: the bold default button; at most one per toast.
    var isDefault: Bool = false

    init(title: String, isDefault: Bool = false, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.isDefault = isDefault
        self.perform = perform
    }
}

/// Why a toast went away without one of its actions having run (R5-1).
enum ToastDismissal: Equatable, Sendable { case expired, closed, lifetimeEnded, evicted, dismissedAll }

/// Click arming for toasts whose action grants something (security L2, R5-1).
struct ToastClickGuard: Equatable, Sendable {
    /// From the moment the panel shows THIS content (re-armed on every content change).
    var armDelay: TimeInterval = 0.3
    var refuseWhenOverlapped: Bool = true
    static let confirmation = ToastClickGuard()
}

/// Snaptic's only notices (PLAN §3.3, R5.8, R4C §4.7, 0.3 R5-1): a non-activating HUD, one at a time, queued,
/// identical texts merged, 10 s expiry, bound to a Lifetime, announced to VoiceOver. Suppressed while the session
/// is locked or off console, while the screensaver runs and while presenting (a mirror set, or the frontmost app
/// fills a display); suppressed notices still reach Recent Notices (the menu's list) unless `remember` is false.
/// The decisions are Kit's (`ToastQueueModel`, `ToastRules`, `ToastSuppressionFacts`, `ToastClickPolicy`); this
/// class gathers the facts and draws.
@MainActor final class ToastPresenter {
    static let expiry: TimeInterval = ToastRules.expiry
    static let plainDuration: TimeInterval = ToastRules.plainDuration
    static let maxQueued = ToastRules.maxQueued
    static let maxRecent = ToastRules.maxRecent
    /// While toasts wait behind a suppression, the queue is looked at again this often.
    static let retryInterval: TimeInterval = 1
    static let screensaverBundleID = "com.apple.ScreenSaver.Engine"

    /// What a queued toast carries beyond its text (the Kit model holds id, text and times).
    private struct Payload {
        let actions: [ToastAction]
        let defaultIndex: Int?
        let lifetime: Lifetime?
        /// The lifetime's end handler for this toast, removed once the toast is gone.
        var endToken: UInt64?
        let clickGuard: ToastClickGuard?
        let onDismiss: (@MainActor (ToastDismissal) -> Void)?
    }

    private var model = ToastQueueModel()
    private var payloads: [UInt64: Payload] = [:]
    /// When the panel showed its current content (click arming).
    private var shownAt: Double = 0
    private var dismissTimer: Timer?
    private var retryTimer: Timer?
    private var pumpScheduled = false
    private var panel: ToastPanel?
    private var host: ToastHostingView?
    /// Last `com.apple.screensaver.didstart` hint (a hint only suppresses, for at most 10 s).
    private var screensaverHintAt: Double?
    private var observers: [NSObjectProtocol] = []

    /// Recent notices, newest last (menu "Recent Notices").
    private(set) var recent: [String] = []
    var onRecentChange: (@MainActor () -> Void)?

    init() {
        observeHints()
    }

    // MARK: Showing

    /// One at a time, queued; expires after 10 s or when `lifetime` ends.
    func show(_ message: String, action: ToastAction? = nil, lifetime: Lifetime? = nil) {
        show(message, actions: action.map { [$0] } ?? [], lifetime: lifetime)
    }

    /// R5-1: up to 2 actions. Returns false when nothing was presented or queued (suppressed, merged with an
    /// identical text, empty, or lifetime already ended). With `remember: false` the toast never reaches Recent
    /// Notices. `onDismiss` runs exactly once, on main, when the toast goes away without one of its actions having
    /// run; it never runs for a toast this returned false for.
    @discardableResult
    func show(_ message: String, actions: [ToastAction], lifetime: Lifetime? = nil, remember: Bool = true,
              clickGuard: ToastClickGuard? = nil, onDismiss: (@MainActor (ToastDismissal) -> Void)? = nil) -> Bool {
        if let lifetime, lifetime.isEnded { return false }
        let text = TextSanitizer.clean(message, maxScalars: ToastRules.maxScalars)
        let plan = ToastRules.normalizedActions(isDefault: actions.map(\.isDefault))
        let kept = Array(actions.prefix(plan.count))
        let offer = model.offer(text, hasActions: !kept.isEmpty, now: Self.now(), suppressed: {
            self.suppressionFacts().isSuppressed
        })
        if remember && offer.addsToRecent { addRecent(text) }
        guard case .queued(let id, let evicted) = offer else { return false }
        var payload = Payload(actions: kept, defaultIndex: plan.defaultIndex, lifetime: lifetime, endToken: nil,
                              clickGuard: clickGuard, onDismiss: onDismiss)
        if let lifetime {
            payload.endToken = lifetime.addEndHandler { [weak self] in self?.lifetimeEnded(id) }
        }
        payloads[id] = payload
        if let evicted { finish(evicted, .evicted) }
        pump()
        return true
    }

    /// A Recent Notices entry without a toast (a migration note, an end Awake reports in its menu too).
    func addRecentNotice(_ message: String) {
        addRecent(TextSanitizer.clean(message, maxScalars: ToastRules.maxScalars))
    }

    /// Removes every toast (quit, Safe Mode relaunch).
    func dismissAll() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        let ids = model.removeAll()
        hidePanel()
        ids.forEach { finish($0, .dismissedAll) }
    }

    func clearRecent() {
        recent = []
        onRecentChange?()
    }

    // MARK: Queue

    /// Shows the next toast when nothing shows and nothing suppresses; while one waits behind a suppression, looks
    /// again every second (it expires 10 s after it was queued).
    private func pump() {
        guard model.current == nil else { return }
        let next = model.next(now: Self.now(), suppressed: { self.suppressionFacts().isSuppressed })
        if let entry = next.presented { present(entry) }
        // After `present`, so a dismissal handler that shows a toast only queues it.
        next.expired.forEach { finish($0, .expired) }
        if model.current == nil && !model.queue.isEmpty { scheduleRetry() }
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: Self.retryInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryTimer = nil
                self?.pump()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    /// The next toast shows after the last one has faded.
    private func schedulePump() {
        guard !pumpScheduled else { return }
        pumpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                self?.pumpScheduled = false
                self?.pump()
            }
        }
    }

    /// Ends a toast that is no longer showing or waiting: its lifetime forgets it, then its handler runs.
    private func finish(_ id: UInt64, _ reason: ToastDismissal?) {
        guard let payload = payloads.removeValue(forKey: id) else { return }
        payload.lifetime?.removeEndHandler(payload.endToken)
        if let reason { payload.onDismiss?(reason) }
    }

    /// Takes the showing toast down. `reason` nil: one of its actions runs (no dismissal handler).
    private func dismissCurrent(_ reason: ToastDismissal?) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let entry = model.finishCurrent() else { return }
        hidePanel()
        schedulePump()
        finish(entry.id, reason)
    }

    private func lifetimeEnded(_ id: UInt64) {
        // The handler already ran; `finish` removing it again is harmless.
        if model.removeQueued(id) {
            finish(id, .lifetimeEnded)
        } else if model.current?.id == id {
            dismissCurrent(.lifetimeEnded)
        }
    }

    private func runAction(_ index: Int) {
        guard let entry = model.current, let payload = payloads[entry.id], payload.actions.indices.contains(index)
        else { return }
        let now = Self.now()
        if let clickGuard = payload.clickGuard {
            let overlapped = clickGuard.refuseWhenOverlapped && isPanelOverlapped()
            // Ignored, not queued (security L2).
            guard ToastClickPolicy.accepts(armDelay: clickGuard.armDelay, shownAt: shownAt, now: now,
                                           overlapped: overlapped) else { return }
        }
        if payload.lifetime?.isEnded ?? false { return dismissCurrent(.lifetimeEnded) }
        if ToastRules.isExpired(queuedAt: entry.queuedAt, now: now) { return dismissCurrent(.expired) }
        dismissCurrent(nil)
        payload.actions[index].perform()
    }

    private func addRecent(_ text: String) {
        let updated = ToastRules.appendingRecent(text, to: recent)
        guard updated != recent else { return }
        recent = updated
        onRecentChange?()
    }

    // MARK: Suppression (read at the moment of use; notifications are only hints)

    private func suppressionFacts() -> ToastSuppressionFacts {
        var facts = ToastSuppressionFacts()
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            facts.offConsole = (session["kCGSSessionOnConsoleKey"] as? Bool) == false
            facts.locked = (session["CGSSessionScreenIsLocked"] as? Bool) == true
        }
        let front = NSWorkspace.shared.frontmostApplication
        facts.screensaverFrontmost = front?.bundleIdentifier == Self.screensaverBundleID
        facts.screensaverHintAge = screensaverHintAt.map { Self.now() - $0 }
        guard !facts.isSuppressed else { return facts }
        facts.mirroring = Self.anyDisplayMirrored()
        if let front, front.processIdentifier != getpid() {
            facts.frontmostCoversDisplay = Self.frontmostCoversDisplay(pid: front.processIdentifier)
        }
        return facts
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func anyDisplayMirrored() -> Bool {
        onlineDisplays().contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    /// The frontmost app has an on-screen, normal-level window covering a whole display (bounds and owner PID only,
    /// no Screen Recording).
    private static func frontmostCoversDisplay(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let windows: [ScreenRect] = list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) > 0,
                  let bounds = Self.bounds(info) else { return nil }
            return bounds
        }
        guard !windows.isEmpty else { return false }
        let displays = onlineDisplays().map { id -> ScreenRect in
            let r = CGDisplayBounds(id)
            return ScreenRect(x: r.origin.x, y: r.origin.y, width: r.width, height: r.height)
        }
        return ToastGeometry.anyCovers(windows: windows, displays: displays)
    }

    private static func bounds(_ info: [String: Any]) -> ScreenRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
        return ScreenRect(x: r.origin.x, y: r.origin.y, width: r.width, height: r.height)
    }

    /// Another process's visible window lies over the panel (CG global coordinates). Fails closed.
    private func isPanelOverlapped() -> Bool {
        guard let panel, panel.isVisible, panel.windowNumber > 0,
              let primary = NSScreen.screens.first?.frame.height else { return true }
        let f = panel.frame
        let rect = ToastGeometry.cgRect(cocoaX: f.origin.x, y: f.origin.y, width: f.width, height: f.height,
                                        primaryHeight: primary)
        let list = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, CGWindowID(panel.windowNumber))
            as? [[String: Any]]
        let above = list?.compactMap { info -> ToastWindowAbove? in
            guard let bounds = Self.bounds(info) else { return nil }
            return ToastWindowAbove(bounds: bounds, alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                                    ownerPID: (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
        }
        return ToastClickPolicy.isOverlapped(panel: rect, above: above, ownPID: getpid())
    }

    /// Lock, screensaver and session hints take the showing toast down at once (fail safe: its actions can't be
    /// clicked behind a lock); what waits shows again once the facts allow.
    private func observeHints() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screensaver.didstart"),
                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensaverHintAt = Self.now()
                self?.suppressionBegan()
            }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screensaver.didstop"),
                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensaverHintAt = nil
                self?.pump()
            }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suppressionBegan() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suppressionBegan() }
        })
    }

    private func suppressionBegan() {
        guard model.current != nil else { return }
        dismissCurrent(.expired)
    }

    // MARK: Window

    private func present(_ entry: ToastQueueModel.Entry) {
        let payload = payloads[entry.id]
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let area = Self.targetArea()
        let width = min(ToastMetrics.width, max(240, area.width - 40))
        let content = ToastContent(
            message: entry.text, width: width,
            items: (payload?.actions ?? []).enumerated().map { index, action in
                ToastContent.Item(index: index, title: action.title, isDefault: index == payload?.defaultIndex)
            })
        let view = AnyView(ToastView(content: content, onAction: { [weak self] in self?.runAction($0) },
                                     onClose: { [weak self] in self?.dismissCurrent(.closed) }))
        host?.rootView = view
        // Height for this text at this width (up to 3 lines).
        let fitted = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 400)).height
        let size = NSSize(width: width, height: min(max(52, ceil(fitted)), 160))
        let origin = NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 12)
        panel.setFrame(NSRect(origin: origin, size: size).integral, display: true)
        panel.invalidateShadow()
        // Re-armed for this content (R5-1).
        shownAt = Self.now()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                .announcement: entry.text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }

        let duration = ToastRules.displayDuration(hasActions: entry.hasActions, queuedAt: entry.queuedAt, now: Self.now())
        dismissTimer?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissCurrent(.expired) }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A toast that showed meanwhile keeps the panel.
                guard let self, self.model.current == nil else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    private func makePanel() -> ToastPanel {
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: ToastMetrics.width, height: 56),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.sharingType = .none

        // A semantic material (design-spec §5); NSVisualEffectView turns opaque under Reduce Transparency itself.
        // The mask rounds the blur, and with it the window shadow.
        let effect = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: ToastMetrics.cornerRadius)
        effect.autoresizingMask = [.width, .height]

        let host = ToastHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect
        self.host = host
        return panel
    }

    /// The visible frame of the screen with the pointer: the toast shows at its top center, under the menu bar,
    /// never where the confirmation panel (centered) appears.
    private static func targetArea() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    /// A stretchable rounded-rectangle mask for the effect view.
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

    /// Continuous and counts sleep, so a toast queued before sleeping has expired after it.
    private static func now() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

/// Never key, so Return and Esc stay with whatever window has focus (the confirm panel), and a guarded toast has no
/// keyboard path (R5-1).
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One click on "Undo" is enough even though the panel never becomes key.
private final class ToastHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private enum ToastMetrics {
    static let width: CGFloat = 400
    static let cornerRadius: CGFloat = 12
}

private struct ToastContent {
    struct Item: Identifiable {
        let index: Int
        let title: String
        let isDefault: Bool
        var id: Int { index }
    }

    let message: String
    let width: CGFloat
    let items: [Item]
}

/// A notification-style banner: symbol, text (up to 3 lines), the buttons in reading order with the default one
/// last and prominent, and a close button. System text styles and semantic colors only (design-spec §5).
private struct ToastView: View {
    let content: ToastContent
    let onAction: (Int) -> Void
    let onClose: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(content.message)
                .font(.body)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !content.items.isEmpty {
                HStack(spacing: 8) {
                    ForEach(ordered) { button in
                        if button.isDefault {
                            Button(button.title) { onAction(button.index) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button(button.title) { onAction(button.index) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .fixedSize()
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Dismiss"))
            .accessibilityLabel(L("Dismiss"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: content.width, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: ToastMetrics.cornerRadius, style: .circular)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 1 : 0.5)
        }
        // The panel is never key: draw the controls as active anyway, like a system banner.
        .environment(\.controlActiveState, .key)
        .accessibilityElement(children: .contain)
    }

    /// The default button goes last (trailing), the macOS order.
    private var ordered: [ToastContent.Item] {
        content.items.filter { !$0.isDefault } + content.items.filter(\.isDefault)
    }
}
