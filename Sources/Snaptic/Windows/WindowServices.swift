import AppKit
import ApplicationServices
import SnapticKit

/// One client's hold on the shared window services (PLAN 0.5 §2.3).
struct WindowLease: Equatable {
    let client: ModuleID
}

/// The window services the Window Switcher and Dock Previews share (PLAN 0.5 §2.2, §2.3, H2): the leases, the
/// system-wide AX messaging timeout, `FocusTracker` and `WindowManager`'s recency order, the §2.5 purge observers and
/// the live counters. Kit `WindowLeaseLedger` holds the union and the edges; this runs its commands. With no lease
/// nothing runs: no observer, thread or timer.
@MainActor final class WindowServices {
    static let shared = WindowServices()

    /// Seconds Snaptic waits for any app to answer an Accessibility request.
    nonisolated static let axTimeout: Float = 0.15

    private var ledger = WindowLeaseLedger()
    private let focusTracker = FocusTracker()
    /// What each client does on a §2.5 purge trigger before the store is purged (the switcher closes).
    private var purgeHandlers: [ModuleID: @MainActor () -> Void] = [:]
    private var purgeTokens: [NSObjectProtocol] = []
    private var distributedPurgeTokens: [NSObjectProtocol] = []

    private init() {}

    /// Live leases (§2.3, §4.22); 0 while every client is stopped.
    var liveLeases: Int { ledger.leases.count }

    /// `FocusTracker`'s AX observers (§2.3, M32); 0 while no lease holds `.recency`.
    var focusObservers: Int { focusTracker.liveObservers }

    // MARK: Leases

    /// Takes `client`'s lease; one it holds already is updated. `onPurge` runs on each §2.5 purge trigger, before
    /// the store is purged.
    func acquire(_ client: ModuleID, needs: WindowNeeds,
                 onPurge: (@MainActor () -> Void)? = nil) -> WindowLease {
        purgeHandlers[client] = onPurge
        run(ledger.acquire(client, needs: needs, now: Self.now))
        return WindowLease(client: client)
    }

    func update(_ lease: WindowLease, needs: WindowNeeds) {
        guard ledger.holds(lease.client) else { return }
        run(ledger.update(lease.client, needs: needs, now: Self.now))
    }

    func release(_ lease: WindowLease) {
        purgeHandlers[lease.client] = nil
        run(ledger.release(lease.client, now: Self.now))
    }

    /// Re-registers focus tracking for every app (after Accessibility is granted). Nothing while no lease holds
    /// `.recency`.
    func refreshRecency() {
        focusTracker.observeAll()
    }

    // MARK: Shared privacy settings (§4.10, D2-1)

    // The switcher `Config` keeps them in `SnapticConfig.v1`. `ModuleHost` loads `AppSettings.shared` whether or not
    // the switcher runs, so both modules read them here.

    var protectPrivateWindows: Bool { AppSettings.shared.config.protectPrivateWindows }
    var protectedApps: [String] { AppSettings.shared.config.privateBundleIDs }
    /// The apps whose windows are never captured: the protected apps while protection is on.
    var captureBlockedBundleIDs: [String] { protectPrivateWindows ? protectedApps : [] }

    // MARK: Commands

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private func run(_ commands: [WindowLeaseCommand]) {
        var purged = false
        for command in commands {
            switch command {
            case .startServices:
                // A slow or frozen app must never stall Snaptic for long.
                AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.axTimeout)
            case .stopServices:
                break   // the purge observers follow the `.thumbnails` union below
            case .startRecency:
                WindowManager.shared.start()
                focusTracker.onFocus = { pid, id in WindowManager.shared.focusChanged(pid: pid, windowID: id) }
                focusTracker.start()
            case .stopRecency:
                focusTracker.stop()
                WindowManager.shared.stop()
            case .startFreshness, .stopFreshness:
                break   // A1b: no client asks for `.freshness(pid)` yet
            case .purge, .purgeAll:
                // One store and one client until A1b, so a client purge is the whole store. Purging bumps the
                // generation, so a capture in flight is dropped.
                if !purged { ThumbnailStore.shared.purge() }
                purged = true
            }
        }
        syncPurgeObservers()
    }

    // MARK: Purge observers (§2.5)

    /// Registered while a live lease holds `.thumbnails`: without it nothing is kept (its loss purges), and the
    /// switcher with thumbnails off registers what 0.4 does.
    private func syncPurgeObservers() {
        if ledger.union.contains(.thumbnails) {
            addPurgeObservers()
        } else {
            removePurgeObservers()
        }
    }

    /// Forget every captured thumbnail when the Mac locks, the displays sleep or the user switches away.
    private func addPurgeObservers() {
        guard purgeTokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            purgeTokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.purgeTriggered() }
            })
        }
        distributedPurgeTokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeTriggered() }
        })
    }

    private func removePurgeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for token in purgeTokens { workspace.removeObserver(token) }
        purgeTokens = []
        for token in distributedPurgeTokens { DistributedNotificationCenter.default().removeObserver(token) }
        distributedPurgeTokens = []
    }

    private func purgeTriggered() {
        for client in ModuleID.allCases where ledger.holds(client) { purgeHandlers[client]?() }
        ThumbnailStore.shared.purge()
    }
}

// MARK: - Window-level focus tracking

private let focusChangedCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon, let id = PrivateWindowAPI.windowID(of: element) else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    // Runs on the observer thread. The box is retained until the session has removed
    // every observer, and its target is weak (a weak load is atomic).
    Unmanaged<CallbackTarget<FocusSession>>.fromOpaque(refcon).takeUnretainedValue().target?
        .deliver(pid: pid, windowID: id)
}

/// Watches every app for "focused window changed", so the switcher's order
/// reflects the windows you actually used, not just which app was in front.
/// Restartable: each start() builds a new session (thread, observers, refcon box);
/// stop() removes every observer and ends the thread. `WindowServices` runs it while a
/// lease holds `.recency` (§2.3).
@MainActor final class FocusTracker {
    /// Delivered on the main thread. Set before `start()`.
    var onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?

    private var session: FocusSession?

    var isRunning: Bool { session != nil }

    /// AX observers registered now (§2.3, M32).
    var liveObservers: Int { session?.liveObservers ?? 0 }

    func start() {
        guard session == nil else { return }
        let session = FocusSession(onFocus: onFocus)
        session.start()
        self.session = session
    }

    func stop() {
        session?.stop()
        session = nil
    }

    /// (Re)registers every running app. Harmless for apps already observed.
    func observeAll() {
        session?.observeAll()
    }
}

private final class FocusSession: @unchecked Sendable {
    private let onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?
    private let thread = ObserverThread()
    private var observers: [pid_t: (observer: AXObserver, app: AXUIElement)] = [:]   // only touched on `thread`
    private var notificationTokens: [NSObjectProtocol] = []                         // main only
    private var box: Unmanaged<CallbackTarget<FocusSession>>?                        // set on main, released on `thread`
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private let stateLock = NSLock()
    private var stopped = false
    private var pending: (pid: pid_t, windowID: CGWindowID)?
    private var observerCount = 0   // `observers.count`, under `stateLock`

    init(onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?) {
        self.onFocus = onFocus
    }

    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    var liveObservers: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return observerCount
    }

    // Runs on `thread`.
    private func countObservers() {
        let count = observers.count
        stateLock.lock()
        observerCount = count
        stateLock.unlock()
    }

    @MainActor func start() {
        box = Unmanaged.passRetained(CallbackTarget(self))
        thread.name = "Snaptic focus tracking"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.waitUntilReady()

        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let pid = Self.pid(from: note) else { return }
            self.onThread {
                self.observe(pid, attempt: 0)
                self.reportFocusedWindow(of: pid)
            }
        })
        notificationTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let pid = Self.pid(from: note) else { return }
            self.onThread { self.observe(pid, attempt: 0) }
        })
        notificationTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let pid = Self.pid(from: note) else { return }
            self.onThread { self.stopObserving(pid) }
        })

        observeAll()
    }

    /// Removes every observer, releases the refcon box and ends the thread.
    @MainActor func stop() {
        stateLock.lock()
        let already = stopped
        stopped = true
        pending = nil
        stateLock.unlock()
        guard !already else { return }

        let center = NSWorkspace.shared.notificationCenter
        for token in notificationTokens { center.removeObserver(token) }
        notificationTokens = []

        // The box stays set: blocks still queued check `stopped` before using it, and the
        // block below (queued last) releases it.
        let box = self.box
        thread.cancel()
        thread.perform {
            for pid in Array(self.observers.keys) { self.stopObserving(pid) }
            self.observers = [:]
            self.countObservers()
            box?.release()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    @MainActor func observeAll() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { $0.processIdentifier }
        onThread {
            // Drop observers of processes that are gone (NSRunningApplication.isTerminated
            // can lag by seconds on macOS 27, leaking observers under churn).
            for pid in Array(self.observers.keys) where kill(pid, 0) != 0 && errno == ESRCH {
                self.stopObserving(pid)
            }
            for pid in pids { self.observe(pid, attempt: 0) }
        }
    }

    private func onThread(_ block: @escaping () -> Void) {
        guard !isStopped else { return }
        thread.perform { [weak self] in
            guard let self, !self.isStopped else { return }
            block()
        }
    }

    private static func pid(from note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    /// Coalesced: a flood of focus notifications (e.g. from a hostile app)
    /// costs the main thread at most one hop at a time, with the latest value.
    fileprivate func deliver(pid: pid_t, windowID: CGWindowID) {
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); return }
        let alreadyScheduled = pending != nil
        pending = (pid, windowID)
        stateLock.unlock()
        guard !alreadyScheduled else { return }

        let handler = onFocus
        Task { @MainActor in
            let latest = self.takePending()
            if let latest { handler?(latest.pid, latest.windowID) }
        }
    }

    /// Synchronous on purpose: locks are never held across an `await`.
    private func takePending() -> (pid: pid_t, windowID: CGWindowID)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { return nil }
        let latest = pending
        pending = nil
        return latest
    }

    // Runs on `thread`.
    private func observe(_ pid: pid_t, attempt: Int) {
        guard observers[pid] == nil, pid != ownPID, let box else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, focusChangedCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowServices.axTimeout)
        guard AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString,
                                        box.toOpaque()) == .success else {
            // Apps that just launched often aren't ready yet; try again shortly.
            let delays: [Double] = [0.3, 1.0, 3.0]
            guard attempt < delays.count else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
                self?.onThread { self?.observe(pid, attempt: attempt + 1) }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = (observer, app)
        countObservers()
    }

    // Runs on `thread`.
    private func stopObserving(_ pid: pid_t) {
        guard let entry = observers.removeValue(forKey: pid) else { return }
        AXObserverRemoveNotification(entry.observer, entry.app, kAXFocusedWindowChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
        countObservers()
    }

    // Runs on `thread`.
    private func reportFocusedWindow(of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowServices.axTimeout)
        guard let window = AX.element(app, kAXFocusedWindowAttribute),
              let id = PrivateWindowAPI.windowID(of: window) else { return }
        deliver(pid: pid, windowID: id)
    }
}
