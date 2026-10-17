import AppKit
import SnapticKit

// Confirmation for DDC writes that can take the picture away (input, KVM, standby).
// Owner: B. R3C §2.2: only this file can mint a PreConfirmToken, bound to display key,
// VCP code, value and a short expiry. "Allow without asking" is stored per display, per
// code+value, in SafetyConfig (protected: never exported, never set by the CLI).

/// Proof that the user confirmed one DDC write. Only this file can mint one (R3C §2.2).
struct PreConfirmToken: Sendable {
    let key: DisplayKey
    let vcp: UInt8
    let value: UInt16?
    let expiresAtUptimeNs: UInt64

    fileprivate init(key: DisplayKey, vcp: UInt8, value: UInt16?, ttlSeconds: Double) {
        self.key = key
        self.vcp = vcp
        self.value = value
        expiresAtUptimeNs = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, ttlSeconds) * 1e9)
    }

    func authorizes(_ key: DisplayKey, _ vcp: UInt8, _ value: UInt16) -> Bool {
        self.key == key && self.vcp == vcp && (self.value ?? value) == value
            && DispatchTime.now().uptimeNanoseconds < expiresAtUptimeNs
    }
}

@MainActor final class PreConfirmPresenter {
    static let tokenTTL: Double = 10
    static let dialogTimeout: Double = 60

    private weak var context: DisplaysContext?
    private var dialog: SafetyDialog?

    init() {}

    /// Called by PanicCoordinator.start (the presenter isn't a refcounted service).
    func attach(_ context: DisplaysContext?) {
        self.context = context
        if context == nil { dialog?.finish(nil) }
    }

    /// Nil if the user declined, the dialog timed out, the session is paused, or another
    /// confirmation is already showing. `allowKey` non-nil offers "Allow without asking"
    /// (only for a concrete value).
    func confirm(key: DisplayKey, vcp: UInt8, value: UInt16?, message: String, allowKey: String?) async -> PreConfirmToken? {
        guard let ctx = context, ctx.sessionGate.isOpen, dialog == nil else { return nil }
        let offerAllow = allowKey != nil && value != nil
        if offerAllow, let v = value, ctx.config.value.safety.preConfirmAllowed[key]?.allows(vcp: vcp, value: v) == true {
            return PreConfirmToken(key: key, vcp: vcp, value: v, ttlSeconds: Self.tokenTTL)
        }
        let target = ctx.registry.info(for: key)
        let screen = NSScreen.screens.first { $0.displayID != target?.desktopID && $0.displayID != target?.hardwareID }
            ?? NSScreen.main ?? NSScreen.screens.first
        let name = target?.name ?? L("this display")
        let d = SafetyDialog(title: L("Change “\(name)”?"), message: message,
                             checkbox: offerAllow ? L("Allow this without asking for this display") : nil,
                             confirmTitle: L("Continue"), cancelTitle: L("Cancel"), timeout: Self.dialogTimeout)
        dialog = d
        let result = await d.run(on: screen)
        dialog = nil
        guard let allowed = result else { return nil }
        if allowed, let v = value {
            var list = ctx.config.value.safety.preConfirmAllowed[key] ?? PreConfirmAllowList()
            if !list.allows(vcp: vcp, value: v) { list.entries.append(PreConfirmAllowList.entry(vcp: vcp, value: v)) }
            ctx.config.value.safety.preConfirmAllowed[key] = list.sanitized()
            EventLog.shared.record(.safety, "A DDC write was allowed without asking for one display")
        }
        return PreConfirmToken(key: key, vcp: vcp, value: value, ttlSeconds: Self.tokenTTL)
    }

    /// Removes "Allow without asking" entries (Safety page).
    func revokeAll(for key: DisplayKey? = nil) {
        guard let ctx = context else { return }
        if let key { ctx.config.value.safety.preConfirmAllowed[key] = nil } else {
            ctx.config.value.safety.preConfirmAllowed = LossyMap()
        }
    }
}

/// A small non-modal, keyboard-accessible confirmation panel. Return and Esc cancel;
/// the confirm button must be clicked or pressed with Space after tabbing to it.
@MainActor final class SafetyDialog: NSObject {
    private let panel: NSPanel
    private let checkbox: NSButton?
    private var continuation: CheckedContinuation<Bool?, Never>?
    private var timer: Timer?
    private let timeout: Double

    init(title: String, message: String, checkbox checkboxTitle: String?, confirmTitle: String, cancelTitle: String,
         timeout: Double) {
        self.timeout = timeout
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        checkbox = checkboxTitle.map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        super.init()
        panel.title = title
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let text = NSTextField(wrappingLabelWithString: message)
        text.preferredMaxLayoutWidth = 380
        let cancel = NSButton(title: cancelTitle, target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\r"
        let escape = NSButton(title: "", target: self, action: #selector(cancelPressed))
        escape.keyEquivalent = "\u{1b}"
        escape.isHidden = true
        let confirm = NSButton(title: confirmTitle, target: self, action: #selector(confirmPressed))
        confirm.setAccessibilityLabel(confirmTitle)
        let buttons = NSStackView(views: [escape, confirm, cancel])
        buttons.orientation = .horizontal
        var rows: [NSView] = [text]
        if let checkbox { rows.append(checkbox) }
        rows.append(buttons)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        panel.contentView = stack
    }

    /// True/false = confirmed (with/without the checkbox); nil = cancelled or timed out.
    func run(on screen: NSScreen?) async -> Bool? {
        await withCheckedContinuation { (c: CheckedContinuation<Bool?, Never>) in
            continuation = c
            panel.layoutIfNeeded()
            if let frame = screen?.visibleFrame {
                let size = panel.frame.size
                panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            } else {
                panel.center()
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: panel.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            let t = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(nil) }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    @objc private func cancelPressed() { finish(nil) }
    @objc private func confirmPressed() { finish(checkbox?.state == .on) }

    func finish(_ result: Bool?) {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        let c = continuation
        continuation = nil
        c?.resume(returning: result)
    }
}
