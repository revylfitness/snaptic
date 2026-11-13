import AppKit
import ApplicationServices
import os
import SnapticKit

/// One client's hold on the shared window services (PLAN 0.5 §2.3).
struct WindowLease: Equatable {
    let client: ModuleID
}

/// The window services the Window Switcher and Dock Previews share (PLAN 0.5 §2.2, §2.3, H2): the leases, the
/// system-wide AX messaging timeout, `FocusTracker` and `WindowManager`'s recency order, the freshness notifications,
/// the §2.5 purge observers and the live counters. Kit `WindowLeaseLedger` holds the union and the edges; this runs
/// its commands, and Kit `ThumbnailIndex` follows them for the store. With no lease nothing runs: no observer, thread
/// or timer.
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
    /// What each client does when an app it holds `.freshness(pid)` for changes its windows.
    private var windowsChangedHandlers: [ModuleID: @MainActor (pid_t) -> Void] = [:]
    /// Freshness observers for apps `FocusTracker` doesn't host; nil while there are none.
    private var ownFreshness: OwnFreshnessSession?
    /// One one-shot at the ledger's next freshness deadline; nil while nothing lingers.
    private var lingerItem: DispatchWorkItem?
    /// The window focus last moved to, while a lease holds `.recency`.
    private var lastFocused: CGWindowID?

    private init() {}

    /// Live leases (§2.3, §4.22); 0 while every client is stopped.
    var liveLeases: Int { ledger.leases.count }

    /// `FocusTracker`'s AX observers (§2.3, M32); 0 while no lease holds `.recency`.
    var focusObservers: Int { focusTracker.liveObservers }

    /// Freshness `AXObserver`s on their own thread (§2.3, §4.22, M32); 0 while no lease holds `.freshness(pid)` (and
    /// its 2 s linger is over) or `FocusTracker` hosts them.
    var freshnessObservers: Int { ownFreshness?.liveObservers ?? 0 }

    // MARK: Leases

    /// Takes `client`'s lease; one it holds already is updated. `onPurge` runs on each §2.5 purge trigger, before
    /// the store is purged. `onWindowsChanged` runs when an app the lease holds `.freshness(pid)` for opens, closes,
    /// minimizes, restores or retitles a window, at most once per 0.3 s.
    func acquire(_ client: ModuleID, needs: WindowNeeds,
                 onPurge: (@MainActor () -> Void)? = nil,
                 onWindowsChanged: (@MainActor (pid_t) -> Void)? = nil) -> WindowLease {
        purgeHandlers[client] = onPurge
        windowsChangedHandlers[client] = onWindowsChanged
        run(ledger.acquire(client, needs: needs, now: Self.now))
        return WindowLease(client: client)
    }

    func update(_ lease: WindowLease, needs: WindowNeeds) {
        guard ledger.holds(lease.client) else { return }
        run(ledger.update(lease.client, needs: needs, now: Self.now))
    }

    func release(_ lease: WindowLease) {
        purgeHandlers[lease.client] = nil
        windowsChangedHandlers[lease.client] = nil
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
        // The store first: a purge bumps the client's generation (or the epoch), so a capture in flight is dropped,
        // and a client that lost `.thumbnails` gets nothing from then on (X2-11, X2-12).
        ThumbnailStore.shared.apply(commands, ledger: ledger)
        for command in commands {
            switch command {
            case .startServices:
                // A slow or frozen app must never stall Snaptic for long.
                AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.axTimeout)
            case .stopServices:
                break   // the purge observers follow the `.thumbnails` union below
            case .startRecency:
                WindowManager.shared.start()
                focusTracker.onFocus = { [weak self] pid, id in
                    WindowManager.shared.focusChanged(pid: pid, windowID: id)
                    self?.focusMoved(to: id)
                }
                focusTracker.onWindowsChanged = { [weak self] pid in self?.windowsChanged(pid) }
                focusTracker.start()
            case .stopRecency:
                focusTracker.stop()
                WindowManager.shared.stop()
                lastFocused = nil
            case .startFreshness(let pid, .focusTracker):
                focusTracker.startFreshness(pid)
            case .stopFreshness(let pid, .focusTracker):
                focusTracker.stopFreshness(pid)
            case .startFreshness(let pid, .own):
                startOwnFreshness(pid)
            case .stopFreshness(let pid, .own):
                stopOwnFreshness(pid)
            case .purge, .purgeAll:
                break   // the store ran them above
            }
        }
        syncPurgeObservers()
        armLinger()
    }

    /// The window you moved to and the one you left are where things change: both are captured again at the next
    /// batch even while their thumbnails are fresh (§4.9).
    private func focusMoved(to id: CGWindowID) {
        ThumbnailStore.shared.markDirty(Set([id] + (lastFocused.map { [$0] } ?? [])))
        lastFocused = id
    }

    // MARK: Freshness (§2.3, X-9, D2-5)

    private func startOwnFreshness(_ pid: pid_t) {
        if ownFreshness == nil {
            let session = OwnFreshnessSession(onWindowsChanged: { [weak self] pid in self?.windowsChanged(pid) })
            session.start()
            ownFreshness = session
        }
        ownFreshness?.add(pid)
    }

    /// The thread stops with its last observer.
    private func stopOwnFreshness(_ pid: pid_t) {
        guard let session = ownFreshness else { return }
        session.remove(pid)
        if session.isEmpty {
            session.stop()
            ownFreshness = nil
        }
    }

    /// Tells each client whose lease still holds `.freshness(pid)`; nobody hears an app whose need is lingering.
    private func windowsChanged(_ pid: pid_t) {
        for client in ModuleID.allCases where ledger.needs(of: client).contains(.freshness(pid)) {
            windowsChangedHandlers[client]?(pid)
        }
    }

    /// Stops lingering freshness notifications 2 s after their last need dropped: one one-shot at the ledger's next
    /// deadline, re-armed after each edge and none while nothing lingers.
    private func armLinger() {
        lingerItem?.cancel()
        lingerItem = nil
        guard let deadline = ledger.nextDeadline else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.lingerEnded() }
        }
        lingerItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - Self.now), execute: item)
    }

    private func lingerEnded() {
        lingerItem = nil
        run(ledger.tick(now: Self.now))
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

    /// Forget every captured thumbnail when the Mac locks, the displays or the Mac sleep, or the user switches away.
    private func addPurgeObservers() {
        guard purgeTokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification]
        for name in names {
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
        ThumbnailStore.shared.purgeAll()
    }

    /// Screen Recording was found off, at a capture batch or by a permission check (§2.5, M39): the store is purged,
    /// but no client closes; each shows text from then on. Snaptic never asks for the permission here.
    func screenRecordingRevoked() {
        let hadThumbnails = ThumbnailStore.shared.liveEntries > 0
        ThumbnailStore.shared.purgeAll()
        if hadThumbnails { EventLog.shared.record(.permissions, "screenRecording off: thumbnails purged") }
    }

    // MARK: Keyboard layout (PLAN 0.5 §4.12: KBGetLayoutType off the key path)

    private struct LayoutCache {
        var byType: [Int64: UInt32] = [:]
        var pending: Set<Int64> = []
        var retryAt: [Int64: Double] = [:]
        /// The last answer; ANSI (not ISO, 0.4's fallback) until one comes back.
        var last: UInt32 = WindowResults.layoutANSI
        var primed = false
    }

    nonisolated private static let layoutCache = OSAllocatedUnfairLock(uncheckedState: LayoutCache())

    /// The physical layout of one keyboard type (a key event's `.keyboardEventKeyboardType`). A miss starts a lookup
    /// on the probe queue and answers with the last layout seen; no answer is retried after a minute.
    nonisolated static func layout(for keyboardType: Int64) -> UInt32 {
        let now = ProcessInfo.processInfo.systemUptime
        let (hit, start, last) = layoutCache.withLockUnchecked { c -> (UInt32?, Bool, UInt32) in
            if let hit = c.byType[keyboardType] {
                c.last = hit
                return (hit, false, hit)
            }
            guard !c.pending.contains(keyboardType), now >= c.retryAt[keyboardType] ?? 0 else {
                return (nil, false, c.last)
            }
            c.pending.insert(keyboardType)
            return (nil, true, c.last)
        }
        if let hit { return hit }
        if start {
            PrivateWindowAPI.lookUpLayout(keyboardType: keyboardType) { value in
                let done = ProcessInfo.processInfo.systemUptime
                layoutCache.withLockUnchecked { c in
                    c.pending.remove(keyboardType)
                    if let value {
                        c.byType[keyboardType] = value
                        c.last = value
                    } else {
                        c.retryAt[keyboardType] = done + 60
                    }
                }
            }
        }
        return last
    }

    /// Looks up the current keyboard's layout once (`LMGetKbdType`), so the first key press already has it.
    nonisolated static func primeLayout() {
        let prime = layoutCache.withLockUnchecked { c -> Bool in
            defer { c.primed = true }
            return !c.primed
        }
        guard prime else { return }
        PrivateWindowAPI.lookUpKeyboardType { keyboardType in
            if let keyboardType { _ = layout(for: keyboardType) }
        }
    }

    /// The last layout seen, for labels with no key event behind them.
    nonisolated static var lastLayout: UInt32 {
        primeLayout()
        return layoutCache.withLockUnchecked { $0.last }
    }
}

// MARK: - Window-level focus tracking

private let focusChangedCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    // Runs on the observer thread. The box is retained until the session has removed
    // every observer, and its target is weak (a weak load is atomic).
    let session = Unmanaged<CallbackTarget<FocusSession>>.fromOpaque(refcon).takeUnretainedValue().target
    guard (notification as String) == kAXFocusedWindowChangedNotification else {
        // One of the freshness notifications this observer hosts (§2.3, D2-5).
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        session?.freshnessChanged(pid)
        return
    }
    guard let id = PrivateWindowAPI.windowID(of: element) else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    session?.deliver(pid: pid, windowID: id)
}

/// Watches every app for "focused window changed", so the switcher's order
/// reflects the windows you actually used, not just which app was in front.
/// Restartable: each start() builds a new session (thread, observers, refcon box);
/// stop() removes every observer and ends the thread. `WindowServices` runs it while a
/// lease holds `.recency` (§2.3), and it hosts the freshness notifications meanwhile (D2-5).
@MainActor final class FocusTracker {
    /// Delivered on the main thread. Set before `start()`.
    var onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?
    /// A hosted app's windows changed; delivered on the main thread, at most once per 0.3 s per app. Set before
    /// `start()`.
    var onWindowsChanged: (@MainActor (pid_t) -> Void)?

    private var session: FocusSession?

    var isRunning: Bool { session != nil }

    /// AX observers registered now (§2.3, M32).
    var liveObservers: Int { session?.liveObservers ?? 0 }

    func start() {
        guard session == nil else { return }
        let session = FocusSession(onFocus: onFocus, onWindowsChanged: onWindowsChanged)
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

    /// Adds the five freshness notifications for `pid` to its observer (§2.3).
    func startFreshness(_ pid: pid_t) {
        session?.startFreshness(pid)
    }

    func stopFreshness(_ pid: pid_t) {
        session?.stopFreshness(pid)
    }
}

private final class FocusSession: @unchecked Sendable {
    private let onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?
    private let onWindowsChanged: (@MainActor (pid_t) -> Void)?
    private let thread = ObserverThread()
    private var observers: [pid_t: (observer: AXObserver, app: AXUIElement)] = [:]   // only touched on `thread`
    // Freshness (§2.3, D2-5), only touched on `thread`: the apps asked for, their registrations, and the apps
    // observed only because freshness asked (not regular apps), whose observer goes with the freshness.
    private var freshnessPIDs: Set<pid_t> = []
    private var freshness: [pid_t: FreshnessRegistration] = [:]
    private var freshnessOnly: Set<pid_t> = []
    private var notificationTokens: [NSObjectProtocol] = []                         // main only
    private var box: Unmanaged<CallbackTarget<FocusSession>>?                        // set on main, released on `thread`
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private let stateLock = NSLock()
    private var stopped = false
    private var pending: (pid: pid_t, windowID: CGWindowID)?
    private var observerCount = 0   // `observers.count`, under `stateLock`

    init(onFocus: (@MainActor (pid_t, CGWindowID) -> Void)?, onWindowsChanged: (@MainActor (pid_t) -> Void)?) {
        self.onFocus = onFocus
        self.onWindowsChanged = onWindowsChanged
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

    @MainActor func startFreshness(_ pid: pid_t) {
        onThread {
            self.freshnessPIDs.insert(pid)
            if self.observers[pid] != nil {
                self.addFreshness(pid)
            } else {
                self.observe(pid, attempt: 0, forFreshness: true)
            }
        }
    }

    @MainActor func stopFreshness(_ pid: pid_t) {
        onThread {
            self.freshnessPIDs.remove(pid)
            self.freshness.removeValue(forKey: pid)?.remove()
            if self.freshnessOnly.contains(pid) { self.stopObserving(pid) }
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

    // Runs on `thread`. `forFreshness`: asked for by `.freshness(pid)` rather than as a regular app.
    private func observe(_ pid: pid_t, attempt: Int, forFreshness: Bool = false) {
        if observers[pid] != nil {
            if !forFreshness { freshnessOnly.remove(pid) }
            return
        }
        guard pid != ownPID, let box, !forFreshness || freshnessPIDs.contains(pid) else { return }
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
                self?.onThread { self?.observe(pid, attempt: attempt + 1, forFreshness: forFreshness) }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = (observer, app)
        if forFreshness { freshnessOnly.insert(pid) }
        if freshnessPIDs.contains(pid) { addFreshness(pid) }
        countObservers()
    }

    // Runs on `thread`.
    private func addFreshness(_ pid: pid_t) {
        guard freshness[pid] == nil, let entry = observers[pid], let box else { return }
        let registration = FreshnessRegistration(observer: entry.observer, app: entry.app, refcon: box.toOpaque())
        registration.add()
        freshness[pid] = registration
    }

    /// Runs on `thread` (the AX callback). The first notification since the last report reads the windows again
    /// and reports 0.3 s later; the rest fold into it.
    fileprivate func freshnessChanged(_ pid: pid_t) {
        guard let registration = freshness[pid], registration.markChanged() else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + FreshnessRegistration.settleDelay) { [weak self] in
            self?.onThread { self?.settleFreshness(pid) }
        }
    }

    // Runs on `thread`.
    private func settleFreshness(_ pid: pid_t) {
        guard let registration = freshness[pid] else { return }
        registration.settle()
        let handler = onWindowsChanged
        Task { @MainActor in handler?(pid) }
    }

    // Runs on `thread`.
    private func stopObserving(_ pid: pid_t) {
        freshness.removeValue(forKey: pid)?.remove()
        freshnessOnly.remove(pid)
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

// MARK: - Freshness (§2.3, X-9, D2-5)

/// The five freshness notifications for one app, on an observer its host owns: window created, miniaturized,
/// deminiaturized and title changed on the app element, and destroyed on each window the last read returned
/// (D2-18). Only touched on the host's observer thread.
private final class FreshnessRegistration {
    /// Notifications are folded together for this long; then the windows are read again and the change is reported
    /// once (`windowsChanged(pid)`, §2.4).
    static let settleDelay: Double = 0.3
    private static let appNotifications = [kAXWindowCreatedNotification, kAXWindowMiniaturizedNotification,
                                           kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification]

    private let observer: AXObserver
    private let app: AXUIElement
    private let refcon: UnsafeMutableRawPointer
    private var windows: Set<AXUIElement> = []
    private var changePending = false

    init(observer: AXObserver, app: AXUIElement, refcon: UnsafeMutableRawPointer) {
        self.observer = observer
        self.app = app
        self.refcon = refcon
    }

    func add() {
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        readWindows()
    }

    func remove() {
        for name in Self.appNotifications {
            AXObserverRemoveNotification(observer, app, name as CFString)
        }
        for window in windows {
            AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString)
        }
        windows = []
    }

    /// True for the first notification since the last `settle()`.
    func markChanged() -> Bool {
        guard !changePending else { return false }
        changePending = true
        return true
    }

    func settle() {
        changePending = false
        readWindows()
    }

    /// Destroyed is registered on exactly the windows this read returns, so the registrations never outgrow the
    /// app's window list (D2-18).
    private func readWindows() {
        let read = Set(AX.elements(app, kAXWindowsAttribute))
        for window in windows.subtracting(read) {
            AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString)
        }
        for window in read.subtracting(windows) {
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        windows = read
    }
}

private let freshnessCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    // Runs on the session's thread; the box outlives every observer, and its target is weak.
    Unmanaged<CallbackTarget<OwnFreshnessSession>>.fromOpaque(refcon).takeUnretainedValue().target?.changed(pid)
}

/// The freshness notifications for apps `FocusTracker` doesn't host (no lease holds `.recency`): one `AXObserver` per
/// app on one `ObserverThread`, which stops with its last observer (§2.3, D2-5). Nothing runs while no lease holds
/// `.freshness(pid)`.
private final class OwnFreshnessSession: @unchecked Sendable {
    private let onWindowsChanged: @MainActor (pid_t) -> Void
    private let thread = ObserverThread()
    private var observers: [pid_t: (observer: AXObserver, registration: FreshnessRegistration)] = [:]   // `thread`
    private var box: Unmanaged<CallbackTarget<OwnFreshnessSession>>?   // set on main, released on `thread`
    private var pids: Set<pid_t> = []                                    // main only
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private let stateLock = NSLock()
    private var stopped = false
    private var observerCount = 0   // `observers.count`, under `stateLock`

    init(onWindowsChanged: @escaping @MainActor (pid_t) -> Void) {
        self.onWindowsChanged = onWindowsChanged
    }

    var liveObservers: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return observerCount
    }

    @MainActor var isEmpty: Bool { pids.isEmpty }

    @MainActor func start() {
        box = Unmanaged.passRetained(CallbackTarget(self))
        thread.name = "Snaptic window freshness"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.waitUntilReady()
    }

    @MainActor func add(_ pid: pid_t) {
        pids.insert(pid)
        onThread { self.register(pid) }
    }

    @MainActor func remove(_ pid: pid_t) {
        pids.remove(pid)
        onThread { self.unregister(pid) }
    }

    /// Removes every observer, releases the refcon box and ends the thread.
    @MainActor func stop() {
        stateLock.lock()
        let already = stopped
        stopped = true
        stateLock.unlock()
        guard !already else { return }
        pids = []
        let box = self.box
        thread.cancel()
        thread.perform {
            for pid in Array(self.observers.keys) { self.unregister(pid) }
            box?.release()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    private func onThread(_ block: @escaping () -> Void) {
        guard !isStopped else { return }
        thread.perform { [weak self] in
            guard let self, !self.isStopped else { return }
            block()
        }
    }

    // Runs on `thread`.
    private func countObservers() {
        let count = observers.count
        stateLock.lock()
        observerCount = count
        stateLock.unlock()
    }

    // Runs on `thread`.
    private func register(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ownPID, let box else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, freshnessCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowServices.axTimeout)
        let registration = FreshnessRegistration(observer: observer, app: app, refcon: box.toOpaque())
        registration.add()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = (observer, registration)
        countObservers()
    }

    // Runs on `thread`.
    private func unregister(_ pid: pid_t) {
        guard let entry = observers.removeValue(forKey: pid) else { return }
        entry.registration.remove()
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
        countObservers()
    }

    /// Runs on `thread` (the AX callback). The first notification since the last report reads the windows again
    /// and reports 0.3 s later; the rest fold into it.
    fileprivate func changed(_ pid: pid_t) {
        guard let registration = observers[pid]?.registration, registration.markChanged() else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + FreshnessRegistration.settleDelay) { [weak self] in
            self?.onThread { self?.settle(pid) }
        }
    }

    // Runs on `thread`.
    private func settle(_ pid: pid_t) {
        guard let registration = observers[pid]?.registration else { return }
        registration.settle()
        let handler = onWindowsChanged
        Task { @MainActor in handler(pid) }
    }
}
