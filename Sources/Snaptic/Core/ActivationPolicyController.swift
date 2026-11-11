import AppKit
import SnapticKit

/// A window that never holds Snaptic in `.regular` or blocks a demotion: a PIP viewer stays up for hours and needs no
/// menu bar. It still counts while it's key (cropping).
@MainActor protocol ActivationNeutralWindow: AnyObject {}

/// The one owner of Snaptic's activation policy and of activating Snaptic (lead; PLAN 0.4 H9, §4.7, A4). The rule
/// itself is Kit's `IconsActivationRule`; this samples AppKit for it and applies the answer.
///
/// - Settings and onboarding take a `hold` while they're open; Hidden Icons reports `iconsShown(…)`.
/// - Promotion to `.regular` is immediate. Demotion to `.accessory` waits until no reason is held and no Snaptic window
///   is visible or key (a confirm panel, a save panel, Sparkle, an alert), re-checking every 0.25 s meanwhile.
/// - `activate(_:)` is skipped while the Window Switcher panel is open (`switcherPanelOpen`, set by `ModuleHost`).
/// - When the full-menu-bar reason ends, the app that was frontmost at the expand gets focus back, unless another app
///   activated since or Snaptic still shows a window.
///
/// `SnapticEntry`'s launch default and its refusal alert are the only other policy calls (lint L21).
@MainActor final class ActivationPolicyController {
    static let shared = ActivationPolicyController()

    /// Reasons that keep Snaptic `.regular` while they're held.
    enum Hold: String, CaseIterable {
        case settings
        case onboarding
    }

    /// Why Snaptic activates.
    enum Reason: String, CaseIterable {
        case settings
        case onboarding
        case fullBar
        case alert
        case savePanel
        case permissionGuide
        case updater
        case confirm
        case pip
        case awakePanel
        case launch
    }

    /// One held reason. `release()` is idempotent; a token dropped without it stays held.
    @MainActor final class Token {
        let hold: Hold
        fileprivate weak var owner: ActivationPolicyController?
        private(set) var isReleased = false

        fileprivate init(hold: Hold, owner: ActivationPolicyController) {
            self.hold = hold
            self.owner = owner
        }

        func release() {
            guard !isReleased else { return }
            isReleased = true
            owner?.released(self)
        }
    }

    /// The Window Switcher panel is on screen (P-24). `ModuleHost` points it at `HostSignals.switcherVisible`.
    var switcherPanelOpen: () -> Bool = { false }

    /// How long an `activate(_:)` keeps a demotion waiting, so a panel shown right after it isn't demoted under it.
    static let transientHold: TimeInterval = 1
    /// The demotion re-check while windows or a transient reason hold it.
    static let retryInterval: TimeInterval = 0.25

    private var tokens: [ObjectIdentifier: Token] = [:]
    private var transientUntil: TimeInterval = 0
    private var retry: Timer?

    // Hidden Icons (§4.7).
    private var iconsExpanded = false
    private var expandCause: IconsExpandCause = .other
    /// The full-bar reason, decided at the expand (with the Switcher panel's state then) and kept until the collapse.
    private var fullBarHeld = false
    private var remembered: NSRunningApplication?
    private var otherAppActivated = false
    private var activationObserver: NSObjectProtocol?

    init() {}

    // MARK: Reasons

    /// Holds `reason` until the token is released, promoting now.
    func hold(_ reason: Hold) -> Token {
        let token = Token(hold: reason, owner: self)
        tokens[ObjectIdentifier(token)] = token
        update()
        return token
    }

    private func released(_ token: Token) {
        tokens[ObjectIdentifier(token)] = nil
        update()
    }

    private func holding(_ reason: Hold) -> Bool {
        tokens.values.contains { $0.hold == reason }
    }

    /// Activates Snaptic for `reason`, unless the Window Switcher panel is open. `ignoringOtherApps` keeps the old
    /// forced activation where a site had it (a safety panel must come forward over the current app).
    func activate(_ reason: Reason, ignoringOtherApps: Bool = false) {
        var f = IconsActivationFacts()
        f.switcherPanelOpen = switcherPanelOpen()
        guard IconsActivationRule.mayActivate(f) else { return }
        if ignoringOtherApps {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate()
        }
        transientUntil = ProcessInfo.processInfo.systemUptime + Self.transientHold
        if NSApp.activationPolicy() == .regular { update() }
    }

    // MARK: Hidden Icons

    /// Hidden Icons' icons are shown (expanded, or calibrating on the way to a collapse) or hidden. `cause` and
    /// `fullBarOnExpand` matter on the transition to shown; a collapse that fails keeps reporting `shown`.
    func iconsShown(_ shown: Bool, cause: IconsExpandCause, fullBarOnExpand: Bool) {
        let wasHeld = fullBarHeld
        if shown, !iconsExpanded {
            expandCause = cause
            var f = IconsActivationFacts()
            f.fullBarOnExpand = fullBarOnExpand
            f.expanded = true
            f.expandCause = cause
            f.switcherPanelOpen = switcherPanelOpen()
            fullBarHeld = IconsActivationRule.fullBar(f)
        } else if !shown {
            fullBarHeld = false
        }
        iconsExpanded = shown
        if fullBarHeld, !wasHeld {
            beginFullBar()
        } else if wasHeld, !fullBarHeld {
            endFullBar()
        }
    }

    private func beginFullBar() {
        let front = NSWorkspace.shared.frontmostApplication
        remembered = front?.processIdentifier == getpid() ? nil : front
        otherAppActivated = false
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid) }
        }
        update()
        activate(.fullBar, ignoringOtherApps: true)
    }

    private func appActivated(_ pid: pid_t?) {
        guard let pid, pid != getpid(), pid != remembered?.processIdentifier else { return }
        otherAppActivated = true
    }

    private func endFullBar() {
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = nil
        let f = facts()
        let app = remembered
        remembered = nil
        let back = IconsActivationRule.reactivateRemembered(
            hadRemembered: app.map { !$0.isTerminated } ?? false, otherAppActivatedSinceExpand: otherAppActivated, f)
        // Focus goes back before the demotion, so the menu bar passes straight to that app.
        if back, let app, NSApp.isActive { app.activate(options: []) }
        transientUntil = 0
        update()
    }

    // MARK: The policy

    private func facts() -> IconsActivationFacts {
        var f = IconsActivationFacts()
        f.settingsOpen = holding(.settings)
        f.onboardingOpen = holding(.onboarding)
        // The full-bar reason was decided at the expand; the Switcher's state then is already in it.
        f.fullBarOnExpand = fullBarHeld
        f.expanded = iconsExpanded
        f.expandCause = expandCause
        f.snapticWindowVisible = Self.snapticWindowVisible()
        f.snapticWindowKey = NSApp.keyWindow != nil
        f.otherReasonHeld = ProcessInfo.processInfo.systemUptime < transientUntil
        return f
    }

    private func update() {
        let f = facts()
        let current: IconsAppPolicy = NSApp.activationPolicy() == .regular ? .regular : .accessory
        let next = IconsActivationRule.next(current: current, f)
        if next != current {
            NSApp.setActivationPolicy(next == .regular ? .regular : .accessory)
        }
        let waiting = next == .regular && !IconsActivationRule.wantsRegular(f)
        waiting ? scheduleRetry() : cancelRetry()
    }

    private func scheduleRetry() {
        guard retry == nil else { return }
        let timer = Timer(timeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        retry = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelRetry() {
        retry?.invalidate()
        retry = nil
    }

    // MARK: Windows

    /// A Snaptic window a person is looking at: visible, titled, not minimized, not a PIP viewer.
    static func snapticWindowVisible() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized && window.styleMask.contains(.titled)
                && !(window is ActivationNeutralWindow)
        }
    }
}
