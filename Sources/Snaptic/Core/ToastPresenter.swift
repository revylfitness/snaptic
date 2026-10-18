import AppKit
import SwiftUI
import SnapticKit

/// An optional button on a toast ("Undo", "Gather"). It can't run after its toast's
/// lifetime ends or after the toast expires.
struct ToastAction {
    let title: String
    let perform: @MainActor () -> Void
}

/// Snaptic's only notices (PLAN §3.3, R5.8, R4C §4.7): a non-activating HUD, one at a
/// time, queued, identical texts merged, 10 s expiry, bound to a Lifetime, announced to
/// VoiceOver. Suppressed while the session is locked or off console (still listed in
/// `recent`, which the menu shows).
@MainActor final class ToastPresenter {
    static let expiry: TimeInterval = 10
    static let plainDuration: TimeInterval = 4
    static let maxQueued = 8
    static let maxRecent = 10

    private struct Pending {
        let id: UInt64
        let message: String
        let action: ToastAction?
        let lifetime: Lifetime?
        /// The lifetime's end handler for this toast, removed once the toast is gone.
        var endToken: UInt64?
        let queuedAt: Date
    }

    private var queue: [Pending] = []
    private var current: Pending?
    private var serial: UInt64 = 0
    private var dismissTimer: Timer?
    private var panel: ToastPanel?
    private let model = ToastModel()

    /// Recent notices, newest last (menu "Recent notices").
    private(set) var recent: [String] = []
    var onRecentChange: (@MainActor () -> Void)?

    init() {}

    /// One at a time, queued; expires after 10 s or when `lifetime` ends.
    func show(_ message: String, action: ToastAction? = nil, lifetime: Lifetime? = nil) {
        if let lifetime, lifetime.isEnded { return }
        let text = TextSanitizer.clean(message, maxScalars: 200)
        guard !text.isEmpty else { return }
        remember(text)
        guard !Self.isSuppressed else { return }
        if current?.message == text || queue.contains(where: { $0.message == text }) { return }
        if queue.count >= Self.maxQueued { release(queue.removeFirst()) }
        serial &+= 1
        var pending = Pending(id: serial, message: text, action: action, lifetime: lifetime, endToken: nil, queuedAt: Date())
        if let lifetime {
            let id = pending.id
            pending.endToken = lifetime.addEndHandler { [weak self] in self?.lifetimeEnded(id) }
        }
        queue.append(pending)
        pump()
    }

    /// Removes every toast (quit, Safe Mode relaunch).
    func dismissAll() {
        queue.forEach(release)
        queue = []
        dismissCurrent(pumpNext: false)
    }

    /// A toast that won't show (again): its lifetime forgets it.
    private func release(_ toast: Pending) {
        toast.lifetime?.removeEndHandler(toast.endToken)
    }

    // MARK: Queue

    private func pump() {
        guard current == nil else { return }
        let now = Date()
        let stale = queue.filter { now.timeIntervalSince($0.queuedAt) >= Self.expiry || ($0.lifetime?.isEnded ?? false) }
        stale.forEach(release)
        queue.removeAll { now.timeIntervalSince($0.queuedAt) >= Self.expiry || ($0.lifetime?.isEnded ?? false) }
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        present(next)
    }

    private func present(_ toast: Pending) {
        current = toast
        model.message = toast.message
        model.actionTitle = toast.action?.title
        model.actionEnabled = toast.action != nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()

        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                .announcement: toast.message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }

        let elapsed = Date().timeIntervalSince(toast.queuedAt)
        let duration = toast.action == nil ? Self.plainDuration : Self.expiry
        let remaining = max(0.5, min(duration, Self.expiry - elapsed))
        dismissTimer?.invalidate()
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissCurrent(pumpNext: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func dismissCurrent(pumpNext: Bool) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let current { release(current) }
        current = nil
        model.actionEnabled = false
        panel?.orderOut(nil)
        if pumpNext {
            // Let the panel disappear before the next one shows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                MainActor.assumeIsolated { self?.pump() }
            }
        }
    }

    private func lifetimeEnded(_ id: UInt64) {
        // The handler already ran; nothing to remove.
        queue.removeAll { $0.id == id }
        if current?.id == id { dismissCurrent(pumpNext: true) }
    }

    private func performAction() {
        guard let toast = current, let action = toast.action else { return }
        let valid = !(toast.lifetime?.isEnded ?? false) && Date().timeIntervalSince(toast.queuedAt) < Self.expiry
        dismissCurrent(pumpNext: true)
        if valid { action.perform() }
    }

    private func remember(_ text: String) {
        recent.append(text)
        if recent.count > Self.maxRecent { recent.removeFirst(recent.count - Self.maxRecent) }
        onRecentChange?()
    }

    func clearRecent() {
        recent = []
        onRecentChange?()
    }

    // MARK: Window

    private func makePanel() -> ToastPanel {
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
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
        let view = ToastView(model: model, onAction: { [weak self] in self?.performAction() },
                             onClose: { [weak self] in self?.dismissCurrent(pumpNext: true) })
        let host = ToastHostingView(rootView: AnyView(view))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    /// Top center of the screen with the pointer, under the menu bar: never where the
    /// confirmation panel (centered) appears.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let area = screen?.visibleFrame else { return }
        let size = NSSize(width: min(460, area.width - 40), height: 56)
        let origin = NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 14)
        panel.setFrame(NSRect(origin: origin, size: size).integral, display: true)
    }

    /// Locked or switched away (fast user switching): notices wait in `recent`.
    static var isSuppressed: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool, !onConsole { return true }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        return false
    }
}

/// Never key, so Return and Esc stay with whatever window has focus (the confirm panel).
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One click on "Undo" is enough even though the panel never becomes key.
private final class ToastHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor private final class ToastModel: ObservableObject {
    @Published var message = ""
    @Published var actionTitle: String?
    @Published var actionEnabled = false
}

private struct ToastView: View {
    @ObservedObject var model: ToastModel
    let onAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.message)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = model.actionTitle {
                Button(title, action: onAction)
                    .disabled(!model.actionEnabled)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Dismiss"))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
