import AppKit
import ApplicationServices
import SnapticKit

/// The Window Switcher as a module (PLAN §2.2, §3.3). Wraps SwitcherController, HotkeyTap,
/// WindowManager, ThumbnailStore and AppSettings so start/stop are idempotent and stop
/// reverts everything: the tap is invalidated, ⌘⇥ is given back, focus observers are
/// removed, thumbnails are purged and every timer and observer goes away.
@MainActor final class WindowSwitcherModule: SnapticModule {
    let id: ModuleID = .windowSwitcher
    let title = L("Window Switcher")
    let symbolName = "rectangle.on.rectangle"
    let summary = L("Switch between windows with ⌥⇥, with thumbnails, search and window actions.")
    private(set) var state: ModuleState = .stopped

    let settings = AppSettings.shared
    private let controller = SwitcherController()
    private var tap: HotkeyTap?
    private var context: ModuleContext?
    private var lifetime: Lifetime?
    private var gatherLifetime: Lifetime?
    private(set) var gatherer: WindowGatherer?
    /// Why the gather shortcut couldn't be registered (shown on the Shortcuts page).
    private(set) var gatherShortcutProblem: String?
    private var secureInputTimer: Timer?
    private var privacyTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var lastConfig = Config()

    init() {}

    var isRunning: Bool { context != nil }
    var tapIsRunning: Bool { tap?.isRunning ?? false }

    var requiredPermissions: Set<Permission> {
        var set: Set<Permission> = [.accessibility]
        if settings.config.needsScreenCapture { set.insert(.screenRecording) }
        return set
    }

    // MARK: SnapticModule

    func start(_ context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        let life = context.lifetime.child()
        lifetime = life
        lastConfig = settings.config

        // A slow or frozen app must never stall Snaptic for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), WindowManager.axTimeout)
        gatherer = WindowGatherer(permissions: context.permissions, toasts: context.toasts)

        let tap = HotkeyTap()
        tap.handler = { [weak self] type, event in
            self?.controller.handle(type: type, event: event) ?? false
        }
        tap.onTrustLost = { [weak self] in self?.trustLost() }
        self.tap = tap

        settings.onChange = { [weak self] config in self?.configChanged(config) }
        WindowManager.shared.start()
        if lastConfig.isOn(.thumbnails) { observePrivacyEvents() }

        context.permissions.observe(lifetime: life) { [weak self] permission, granted in
            guard let self, self.context != nil else { return }
            if permission == .accessibility, granted, !self.tapIsRunning { self.startTap() }
            self.context?.requestMenuRebuild()
        }
        startTap()
        watchSecureInput()
        registerGatherShortcut()
        EventLog.shared.record(.switcher, "Window switcher started")
    }

    func stop() {
        guard let context else { return }
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        removePrivacyObservers()
        settings.onChange = nil
        tap?.stop()
        tap = nil
        controller.reset()
        SystemHotkeys.restore()
        WindowManager.shared.stop()
        ThumbnailStore.shared.purge()
        gatherLifetime?.end()
        gatherLifetime = nil
        lifetime?.end()
        lifetime = nil
        gatherer = nil
        gatherShortcutProblem = nil
        self.context = nil
        state = .stopped
        EventLog.shared.record(.switcher, "Window switcher stopped")
        context.requestMenuRebuild()
    }

    func menuSection() -> [NSMenuItem] {
        guard let context else { return [] }
        var items: [NSMenuItem] = []
        if !tapIsRunning {
            items.append(ClosureMenuItem(title: L("Grant Accessibility Access…")) {
                context.permissions.presentGuide(.accessibility, reason: L("The window switcher needs it to see its shortcuts."))
            })
        }
        if settings.config.needsScreenCapture && context.permissions.state(.screenRecording) != .granted {
            items.append(ClosureMenuItem(title: L("Enable Thumbnails (Screen Recording)…")) {
                context.permissions.presentGuide(.screenRecording, reason: L("Thumbnails and previews of your windows."))
            })
        }
        let hint: String
        if let first = settings.config.activeShortcuts.first {
            hint = tapIsRunning ? L("Press ") + first.displayName + L(" to switch windows") : L("Waiting for Accessibility access")
        } else if settings.config.shortcuts.isEmpty {
            hint = L("No shortcuts set")
        } else {
            hint = L("Only ⌘ shortcuts are set, and ⌘ shortcuts are turned off")
        }
        let hintItem = NSMenuItem(title: hint, action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        items.append(hintItem)
        items.append(ClosureMenuItem(title: L("Gather Windows on This Display")) { [weak self] in
            guard let self, let life = self.lifetime else { return }
            self.gatherer?.gather(onto: WindowGatherer.pointerScreen, confirm: false, lifetime: life)
        })
        return items
    }

    func settingsPages() -> [SettingsPage] {
        SwitcherPages.pages(module: self)
    }

    /// Opens the permission guide (Settings pages).
    func presentPermission(_ permission: Permission) {
        context?.permissions.presentGuide(permission)
    }

    // MARK: Tap

    private func startTap() {
        guard let tap, let context, let lifetime else { return }
        if tap.start() {
            state = .running
            applySystemHotkeys()
            WindowManager.shared.refreshFocusTracking()
        } else {
            // Without Accessibility only PermissionFlow runs (PLAN §2.2).
            state = .degraded(L("Needs ") + PermissionFlow.paneName(.accessibility) + L(" access"))
            applySystemHotkeys()
            context.permissions.request(.accessibility,
                                        reason: L("The window switcher needs it to see its shortcuts and switch windows."),
                                        lifetime: lifetime)
        }
        context.requestMenuRebuild()
    }

    private func trustLost() {
        controller.cancel()
        applySystemHotkeys()
        startTap()   // fails while untrusted: degraded, and PermissionFlow takes over
    }

    /// Only take over ⌘⇥ once Snaptic can actually see key presses.
    private func applySystemHotkeys() {
        SystemHotkeys.apply(tapIsRunning ? settings.config.activeShortcuts : [])
    }

    /// While an app holds Secure Event Input (password fields, Terminal's Secure Keyboard
    /// Entry) Snaptic can't see keys, so ⌘⇥ goes back to macOS.
    private func watchSecureInput() {
        secureInputTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.context != nil else { return }
                let secure = PrivateAPIs.isSecureInputEnabled
                let blind = secure || !(self.tap?.isEnabled ?? false) || !Permissions.accessibility
                SystemHotkeys.setSuspended(blind)
                if blind { self.controller.cancel() }
            }
        }
        timer.tolerance = 0.1
        // Keep checking during menus and modal panels too.
        RunLoop.main.add(timer, forMode: .common)
        secureInputTimer = timer
    }

    // MARK: Settings changes

    private func configChanged(_ config: Config) {
        guard let context else { return }
        let old = lastConfig
        lastConfig = config
        applySystemHotkeys()
        if old.isOn(.thumbnails) != config.isOn(.thumbnails) {
            if config.isOn(.thumbnails) {
                observePrivacyEvents()
            } else {
                removePrivacyObservers()
                ThumbnailStore.shared.purge()
            }
        }
        if config.needsScreenCapture && !old.needsScreenCapture, let lifetime,
           context.permissions.state(.screenRecording) != .granted {
            context.permissions.request(.screenRecording, reason: L("Thumbnails and previews of your windows."),
                                        lifetime: lifetime)
        }
        if old.gatherShortcut != config.gatherShortcut { registerGatherShortcut() }
        if old.disabledFeatures != config.disabledFeatures || old.shortcuts != config.shortcuts {
            controller.cancel()
        }
        context.requestMenuRebuild()
    }

    private func registerGatherShortcut() {
        gatherLifetime?.end()
        gatherLifetime = nil
        gatherShortcutProblem = nil
        guard let context, let lifetime, let combo = settings.config.gatherShortcut else { return }
        let life = lifetime.child()
        gatherLifetime = life
        do {
            _ = try context.hotkeys.register(combo, owner: L("Gather windows"), lifetime: life) { [weak self] in
                guard let self, let life = self.lifetime else { return }
                // Triggered by a shortcut: confirm first (R5.7).
                self.gatherer?.gather(onto: WindowGatherer.pointerScreen, confirm: true, lifetime: life)
            }
        } catch let error as GlobalHotkeys.RegisterError {
            gatherShortcutProblem = Self.describe(error)
        } catch {
            gatherShortcutProblem = L("The shortcut couldn't be registered.")
        }
    }

    static func describe(_ error: GlobalHotkeys.RegisterError) -> String {
        switch error {
        case .conflict(let owner): return L("Already used by ") + owner + "."
        case .systemRefused: return L("macOS refused this shortcut; another app may be using it.")
        case .invalid(let message): return message
        case .notBuilt, .ended: return L("The shortcut couldn't be registered.")
        }
    }

    // MARK: Privacy

    /// Forget every captured thumbnail when the Mac locks, sleeps or switches user.
    private func observePrivacyEvents() {
        guard privacyTokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            privacyTokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.controller.cancel()
                    ThumbnailStore.shared.purge()
                }
            })
        }
        distributedTokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.cancel()
                ThumbnailStore.shared.purge()
            }
        })
    }

    private func removePrivacyObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for token in privacyTokens { workspace.removeObserver(token) }
        privacyTokens = []
        for token in distributedTokens { DistributedNotificationCenter.default().removeObserver(token) }
        distributedTokens = []
    }
}
