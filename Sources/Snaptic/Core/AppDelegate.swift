import AppKit
import ApplicationServices
import SnapticKit
import SnapticShims

/// App startup and shutdown (PLAN §3.2 startup order; step 13 moved into DisplaysModule).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launch: AppLaunchOptions
    // Toasts exist before startup step 7 (journal-recovery notice).
    private let toasts = ToastPresenter()
    private let relauncher = Relauncher()
    private lazy var permissions = PermissionFlow(relauncher: relauncher)
    private let spawner = HelperSpawner()
    private var host: ModuleHost?
    private var safeMode = SafeModeState.off
    private var signalSources: [DispatchSourceSignal] = []
    private var lock = InstanceLock()
    private var lockRetry: Timer?
    private var didFinishStartup = false

    init(launch: AppLaunchOptions) {
        self.launch = launch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        // Startup step 3: the instance lock, fail-closed. A relaunch waits for the old copy.
        switch lock.acquire() {
        case .acquired:
            continueStartup()
        case .busy(let holder):
            if launch.relaunchFrom != nil {
                // The old instance is quitting: retry every 100 ms for up to 10 s (R3C §5.5).
                waitForLock(seconds: 10) { [weak self] in
                    guard let self else { return }
                    self.lockHolderDialog(holder: self.lock.holderPID())
                }
            } else {
                lockHolderDialog(holder: holder)
            }
        case .failed(let reason):
            failClosed(reason)
        }
    }

    /// Steps 4–12, once the lock is ours.
    private func continueStartup() {
        guard !didFinishStartup else { return }
        didFinishStartup = true
        lockRetry?.invalidate()
        lockRetry = nil

        // 4. Give back ⌘⇥ if a previous run died holding it.
        SystemHotkeys.recoverFromPreviousRun()
        // 5. Launch stability; 6. Safe Mode.
        let unstable = LaunchStability.evaluate()
        safeMode = SafeMode.detect(argument: launch.safeMode, unstableLaunches: unstable)
        if safeMode.isActive { EventLog.shared.record(.safety, "Started in Safe Mode") }
        // 7. Undo unfinished display changes from a previous run (runs in Safe Mode too).
        let recovery = RevertJournal.recoverAtLaunch(safeMode: safeMode)
        if let message = recovery.message { toasts.show(message) }
        // 8. Signals: give ⌘⇥ back and run emergency actions even if main is hung.
        handleTerminationSignals()
        // 9. Heartbeat (also the hang guard's beat) and helper preparation.
        HotkeyGuard.shared.start()
        HostHeartbeat.shared.start {
            if HotkeyGuard.shared.beat() { SystemHotkeys.reassert() }
        }
        // Helpers' code identity and canary run off main; modules start once that finished
        // (a few milliseconds), so their first helper spawn doesn't fail as "still
        // starting". Bounded: after 2 s modules start anyway and early spawns fail fast.
        spawner.whenPrepared { [weak self] _ in self?.startModules() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.startModules() }
        }
    }

    /// Steps 10–12, once helper preparation finished (or took too long).
    private func startModules() {
        guard host == nil else { return }
        // 10. The control server arrives with step 2 (ModulesConfig.commandLine).
        // 11. Modules; 12. status items.
        let host = ModuleHost(safeMode: safeMode, toasts: toasts, permissions: permissions, spawner: spawner,
                              relauncher: relauncher)
        self.host = host
        host.bootstrap()

        if safeMode.isActive {
            toasts.show(L("Snaptic started in Safe Mode. Display automation is paused."),
                        action: ToastAction(title: L("Leave")) { [weak self] in
                            self?.relauncher.relaunch(reason: "leave safe mode")
                        })
        }
        // Nothing in the menu bar (everything hidden): show Settings. A first launch gets
        // onboarding instead (shown by the host).
        if !host.modulesStore.value.needsOnboarding && !host.statusMenu.hasVisibleItem {
            host.openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        host?.shutdown()
        SystemHotkeys.restore()
        HotkeyGuard.shared.releaseAll()
        toasts.dismissAll()
        if didFinishStartup { LaunchStability.markCleanQuit() }
        lock.release()
    }

    /// Relaunching Snaptic (or clicking it in Finder while it runs) opens Settings, so
    /// every function stays reachable when menu bar icons are hidden (PLAN §1.1 item 4).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        host?.openSettings()
        return false
    }

    // MARK: Instance lock

    private func waitForLock(seconds: TimeInterval, then onTimeout: @escaping @MainActor () -> Void) {
        let deadline = Date().addingTimeInterval(seconds)
        lockRetry?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                switch self.lock.acquire() {
                case .acquired:
                    timer.invalidate()
                    self.continueStartup()
                case .busy:
                    if Date() > deadline {
                        timer.invalidate()
                        self.lockRetry = nil
                        onTimeout()
                    }
                case .failed(let reason):
                    timer.invalidate()
                    self.failClosed(reason)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        lockRetry = timer
    }

    /// Who holds the lock, and "Quit the other copy" only when that process passes our
    /// designated requirement (R5.7).
    private func lockHolderDialog(holder: pid_t?) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Snaptic is already running")
        var detail = L("Another copy of Snaptic holds its lock, so this one won't start.")
        var canQuitOther = false
        if let pid = holder, pid > 0, kill(pid, 0) == 0 {
            let path = SNProcess.path(for: pid).map { TextSanitizer.clean($0, maxScalars: 300) } ?? L("unknown path")
            detail += "\n\n" + L("Process ") + String(pid) + "\n" + path
            if let requirement = try? SNProcess.designatedRequirementOfSelf() {
                canQuitOther = SNProcess.process(pid, satisfies: requirement)
            }
        }
        alert.informativeText = detail
        if canQuitOther { alert.addButton(withTitle: L("Quit the other copy")) }
        alert.addButton(withTitle: canQuitOther ? L("Cancel") : L("OK"))
        let response = alert.runModal()
        if canQuitOther, response == .alertFirstButtonReturn, let pid = holder {
            NSRunningApplication(processIdentifier: pid)?.terminate()
            waitForLock(seconds: 10) { [weak self] in
                self?.failClosed(L("The other copy didn't quit."))
            }
        } else {
            exit(0)
        }
    }

    private func failClosed(_ reason: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Snaptic couldn't start")
        alert.informativeText = reason
        alert.runModal()
        exit(1)
    }

    // MARK: Signals

    /// `kill` / `pkill` / logout skip the normal quit path unless we catch the signal;
    /// quitting normally gives ⌘⇥ back to macOS and reverts display changes.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            // Handled off the main thread, so ⌘⇥ comes back even if Snaptic is hung.
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                HotkeyGuard.shared.releaseAll()
                EmergencyActions.shared.runAll()
                DispatchQueue.main.async { NSApp.terminate(nil) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Main menu (shown while Settings makes the app regular)

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Snaptic")
        appMenu.addItem(ClosureMenuItem(title: L("About Snaptic")) { [weak self] in
            self?.host?.openSettings(page: GeneralPages.aboutID)
        })
        appMenu.addItem(.separator())
        appMenu.addItem(ClosureMenuItem(title: L("Settings…"), keyEquivalent: ",") { [weak self] in
            self?.host?.openSettings()
        })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide Snaptic"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L("Quit Snaptic"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

/// The single-instance lock (PLAN §3.2 step 3): an exclusive flock on a regular file we
/// own under the account's Application Support folder. It records the holder's pid for
/// the lock-holder dialog. Fail-closed: if the lock can't be checked, Snaptic doesn't run.
struct InstanceLock {
    enum Outcome {
        case acquired
        case busy(holder: pid_t?)
        case failed(String)
    }

    private var fd: Int32 = -1

    mutating func acquire() -> Outcome {
        if fd >= 0 { return .acquired }
        guard let folder = AccountPaths.supportDirectory() else {
            return .failed(L("Snaptic can't use its folder in ~/Library/Application Support."))
        }
        let path = folder + "/instance.lock"
        // Never follow a symlink planted at this path; only lock a regular file we own.
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NOCTTY, 0o600)
        guard fd >= 0 else { return .failed(L("Snaptic can't open its lock file at ") + path) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
            close(fd)
            return .failed(L("Snaptic's lock file isn't a regular file you own: ") + path)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            let holder = Self.readPID(fd)
            close(fd)
            guard error == EWOULDBLOCK else { return .failed(L("Snaptic can't lock ") + path) }
            return .busy(holder: holder)
        }
        _ = ftruncate(fd, 0)
        let text = String(getpid()) + "\n"
        text.withCString { pointer in _ = pwrite(fd, pointer, strlen(pointer), 0) }
        self.fd = fd
        return .acquired
    }

    /// The pid recorded by the current holder, if the file names a live process.
    func holderPID() -> pid_t? {
        guard let folder = AccountPaths.supportDirectory() else { return nil }
        let fd = open(folder + "/instance.lock", O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return Self.readPID(fd)
    }

    mutating func release() {
        guard fd >= 0 else { return }
        _ = flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    private static func readPID(_ fd: Int32) -> pid_t? {
        var buffer = [UInt8](repeating: 0, count: 32)
        let n = buffer.withUnsafeMutableBytes { raw in pread(fd, raw.baseAddress, raw.count, 0) }
        guard n > 0 else { return nil }
        let text = String(decoding: buffer[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return KitArgs.parsePID(text)
    }
}
