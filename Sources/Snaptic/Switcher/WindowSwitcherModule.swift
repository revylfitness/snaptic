import AppKit
import ApplicationServices
import SnapticKit

/// The Window Switcher as a module (PLAN §2.2, §3.3). Wraps SwitcherController, HotkeyTap,
/// WindowManager, ThumbnailStore and AppSettings so start/stop are idempotent and stop
/// reverts everything: the tap is invalidated, ⌘⇥ is given back, focus observers are
/// removed, thumbnails are purged and every timer and observer goes away.
@MainActor final class WindowSwitcherModule: SnapticModule {
    typealias Controls = WindowSwitcherModuleControls
    let id: ModuleID = .windowSwitcher
    let title = L("Window Switcher")
    let symbolName = "rectangle.on.rectangle"
    let summary = L("Switch between windows with ⌥⇥, with thumbnails, search, and window actions.")
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

        controller.onVisibilityChange = { [weak context] visible in context?.hostSignals.switcherVisible = visible }

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
        controller.onVisibilityChange = nil
        context.hostSignals.switcherVisible = false
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

    /// The Window Switcher section (0.3 §5.2), on MenuKit; ids in `WindowSwitcherModuleControls`.
    func menuSection() -> [NSMenuItem] {
        guard let context else { return [] }
        var items: [NSMenuItem] = []
        if !tapIsRunning {
            items.append(MenuKit.action(L("Allow \(PermissionFlow.paneName(.accessibility))…"),
                                        control: ControlID("menu.switcher.grantAccessibility")) {
                context.permissions.presentGuide(.accessibility, reason: L("The window switcher needs it to see its shortcuts."))
            })
        }
        if let first = settings.config.activeShortcuts.first {
            // 0.3 C8: "Switch Windows ⌥⇥" opens the switcher in sticky mode.
            let shown = Self.keyEquivalent(for: first)
            let item = MenuKit.action(L("Switch Windows"), key: shown?.key ?? "", modifiers: shown?.modifiers ?? [],
                                      enabled: tapIsRunning, control: ControlID("menu.switcher.switchWindows")) {
                [weak self] in _ = self?.showStickySwitcher()
            }
            if !tapIsRunning { item.toolTip = L("Waiting for Accessibility access") }
            items.append(item)
        } else {
            // Menu items are Title Case (§5.1, ux m2); the detail is in the tooltip.
            let none = settings.config.shortcuts.isEmpty
            let item = MenuKit.status(none ? L("No Shortcut Set") : L("⌘ Shortcuts Are Turned Off"),
                                      control: ControlID("menu.switcher.noShortcut"))
            item.toolTip = none ? L("Set a shortcut in Window Switcher settings.")
                                : L("Only ⌘ shortcuts are set, and ⌘ shortcuts are turned off.")
            items.append(item)
        }
        items.append(MenuKit.action(L("Gather Windows on This Display"), control: ControlID("menu.switcher.gather")) {
            [weak self] in
            guard let self, let life = self.lifetime else { return }
            self.gatherer?.gather(onto: WindowGatherer.pointerScreen, confirm: false, lifetime: life)
        })
        if settings.config.needsScreenCapture && context.permissions.state(.screenRecording) != .granted {
            items.append(MenuKit.action(L("Turn On Thumbnails…"), control: ControlID("menu.switcher.turnOnThumbnails")) {
                context.permissions.presentGuide(.screenRecording, reason: L("Thumbnails and previews of your windows."))
            })
        }
        return items
    }

    /// The Window Switcher root (H's `SwitcherPages.root`, 0.3 §4.3).
    func settingsRoot() -> SettingsRoot {
        SwitcherPages.root(module: self)
    }

    /// Settings search for the Window Switcher root (R5-13: derived from the control specs whose search root is
    /// this module; the page, its Advanced sheet and its shortcuts sheet).
    func settingsIndex() -> [SettingsSearchEntry] { Self.index }

    private static let index = SettingsIndex.entries(ControlRegistry.tables, root: SettingsRootID.windowSwitcher)

    /// 0.3 C8: opens the switcher in sticky mode with the first shortcut that may act (it stays open until Return,
    /// Esc or a click). False while it can't see keys (no Accessibility yet), without a usable shortcut, or when the
    /// module isn't running.
    @discardableResult
    func showStickySwitcher() -> Bool {
        guard context != nil, tapIsRunning, let shortcut = settings.config.activeShortcuts.first else { return false }
        return controller.openSticky(shortcut)
    }

    /// The shortcut shown beside the item, like a key equivalent (only keys a menu can draw). The status menu is
    /// closed by the time the switcher opens, so the equivalent never fires by itself.
    private static func keyEquivalent(for shortcut: Shortcut) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let key: String
        switch shortcut.keyCode {
        case KeyCode.tab: key = "\t"
        case KeyCode.space: key = " "
        case KeyCode.backtick: key = "`"
        default: return nil
        }
        switch shortcut.modifier {
        case .option: return (key, [.option])
        case .command: return (key, [.command])
        case .control: return (key, [.control])
        }
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
            _ = try context.hotkeys.register(combo, owner: L("Gather Windows on This Display"), lifetime: life) { [weak self] in
                guard let self, let life = self.lifetime else { return }
                // Triggered by a shortcut: confirm first (R5.7).
                self.gatherer?.gather(onto: WindowGatherer.pointerScreen, confirm: true, lifetime: life)
            }
        } catch let error as GlobalHotkeys.RegisterError {
            gatherShortcutProblem = Self.describe(error)
        } catch {
            gatherShortcutProblem = L("The shortcut couldn’t be registered.")
        }
    }

    static func describe(_ error: GlobalHotkeys.RegisterError) -> String {
        switch error {
        case .conflict(let owner): return L("Already used by ") + owner + "."
        case .systemRefused: return L("macOS refused this shortcut; another app may be using it.")
        case .invalid(let message): return message
        case .ended: return L("The shortcut couldn’t be registered.")
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
