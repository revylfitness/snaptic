import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let controller = SwitcherController()
    private let tap = HotkeyTap()
    private let settingsWindow = SettingsWindowController()
    private var retryTimer: Timer?
    private var secureInputTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var notificationTokens: [NSObjectProtocol] = []

    private var instanceLock: Int32 = -1

    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies would install two taps and fight over ⌘⇥. An exclusive
        // file lock (released automatically when the process exits) is
        // race-free, unlike checking the list of running apps.
        guard acquireInstanceLock() else {
            explainInstanceLockFailure()
            exit(0)
        }

        // A slow or frozen app must never stall Snaptic for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), WindowManager.axTimeout)

        SystemHotkeys.recoverFromPreviousRun()
        handleTerminationSignals()
        setUpStatusItem()
        WindowManager.shared.start()
        observePrivacyEvents()

        AppSettings.shared.onChange = { [weak self] _ in
            self?.applySystemHotkeys()
        }

        tap.handler = { [weak self] type, event in
            self?.controller.handle(type: type, event: event) ?? false
        }

        let firstLaunch = !UserDefaults.standard.bool(forKey: "SnapticDidLaunchBefore")
        UserDefaults.standard.set(true, forKey: "SnapticDidLaunchBefore")

        if !Permissions.accessibility { Permissions.promptAccessibility() }
        if !Permissions.screenRecording && AppSettings.shared.config.needsScreenCapture {
            Permissions.requestScreenRecording()
        }
        startTap()
        watchSecureInput()

        if firstLaunch || !Permissions.accessibility {
            settingsWindow.show()
        }
    }

    private func acquireInstanceLock() -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = support.appendingPathComponent("Snaptic", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("instance.lock").path
        // Never follow a symlink planted at this path, and only lock a regular
        // file this user owns.
        let fd = Darwin.open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NOCTTY, 0o600)
        guard fd >= 0 else { return true }   // can't lock; better to run than not
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
            Darwin.close(fd)
            return true
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            return false
        }
        instanceLock = fd
        return true
    }

    /// Quietly step aside for a running copy; otherwise say why we can't start.
    private func explainInstanceLockFailure() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let anotherCopy = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains { $0.processIdentifier != ownPID }
        guard !anotherCopy else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Snaptic couldn't start"
        alert.informativeText = "Another process is holding Snaptic's lock file (~/Library/Application Support/Snaptic/instance.lock). Quit any other copy of Snaptic and try again."
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemHotkeys.restore()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    /// Only take over ⌘⇥ once Snaptic can actually see key presses.
    private func applySystemHotkeys() {
        SystemHotkeys.apply(tap.isRunning ? AppSettings.shared.config.shortcuts : [])
    }

    /// `kill` / `pkill` / logout skip the normal quit path unless we catch the
    /// signal; quitting normally gives ⌘⇥ back to macOS.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            // Handled off the main thread, so ⌘⇥ comes back even if Snaptic is hung.
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                HotkeyGuard.shared.releaseAll()
                DispatchQueue.main.async { NSApp.terminate(nil) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
            }
            source.resume()
            signalSources.append(source)
        }
        HotkeyGuard.shared.start()
    }

    /// While an app holds Secure Event Input (password fields, Terminal's
    /// Secure Keyboard Entry) Snaptic can't see keys, so hand ⌘⇥ back to macOS.
    private func watchSecureInput() {
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Heartbeat for the hang guard; take ⌘⇥ back if it stepped in.
                if HotkeyGuard.shared.beat() { SystemHotkeys.reassert() }
                let secure = PrivateAPIs.isSecureInputEnabled
                // Whenever Snaptic can't see key presses, ⌘⇥ goes back to macOS.
                let blind = secure || !self.tap.isEnabled || !Permissions.accessibility
                SystemHotkeys.setSuspended(blind)
                if blind { self.controller.cancel() }
            }
        }
        // Keep beating during menus and modal panels too, so the hang guard
        // doesn't mistake a settings dialog for a frozen app.
        if let secureInputTimer { RunLoop.main.add(secureInputTimer, forMode: .common) }
    }

    /// Forget every captured thumbnail when the Mac locks, sleeps or switches user.
    private func observePrivacyEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            notificationTokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.controller.cancel()
                    ThumbnailStore.shared.purge()
                }
            })
        }
        notificationTokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.cancel()
                ThumbnailStore.shared.purge()
            }
        })
    }

    /// The event tap can only be created once Accessibility access is granted,
    /// so keep retrying quietly until it is.
    private func startTap() {
        if tap.start() {
            applySystemHotkeys()
            WindowManager.shared.refreshFocusTracking()
            return
        }
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                if Permissions.accessibility, self.tap.start() {
                    timer.invalidate()
                    self.retryTimer = nil
                    self.applySystemHotkeys()
                    WindowManager.shared.refreshFocusTracking()
                }
            }
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Snaptic")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !Permissions.accessibility {
            menu.addItem(withTitle: "Grant Accessibility Access…", action: #selector(openAccessibility), keyEquivalent: "")
                .target = self
        }
        if !Permissions.screenRecording {
            menu.addItem(withTitle: "Enable Thumbnails (Screen Recording)…", action: #selector(openScreenRecording), keyEquivalent: "")
                .target = self
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }

        let hintTitle: String
        if let first = AppSettings.shared.config.shortcuts.first {
            hintTitle = tap.isRunning ? "Press \(first.displayName) to switch windows" : "Waiting for Accessibility access"
        } else {
            hintTitle = "No shortcuts set"
        }
        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Snaptic", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func openScreenRecording() { Permissions.openScreenRecordingSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
