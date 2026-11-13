import AppKit
import ApplicationServices
import SnapticKit
import SnapticShims

/// The Dock observer (lead; PLAN 0.5 §4.8, §4.22, A3): an `AXObserver` on the Dock's `AXList` for
/// `kAXSelectedChildrenChangedNotification`, on its own `ObserverThread`, and the liveness rules that keep it attached.
/// - Main never waits on the Dock (S0-14). Main only resolves the Dock's pid and the running apps, and receives the
///   selection, coalesced to the latest (§2.4).
/// - Liveness (X-17, D2-4, X2-16): KVO on `NSWorkspace.runningApplications` sees the Dock's pid change and
///   `kill(pid, 0)` confirms a pid is gone; every attach tries at once, then the ladder; wake, unlock, session-active
///   and a display change rebuild the observer even with the same pid; the 30 s health check catches a silent death.
/// - Exists only while the module runs and isn't paused (ground rule 1). Nothing it reads is logged; diagnostics get
///   counts and enums only (§4.22).
@MainActor final class DockObserver {
    /// The Dock's selection, on main, coalesced to the latest.
    var onSelection: (@MainActor (DockSelection?) -> Void)?

    private var session: DockObserverSession?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var appsObservation: NSKeyValueObservation?
    private var dockPID: pid_t?
    private var appsChangePending = false

    var isRunning: Bool { session != nil }

    /// What the observer has done since `start()` (§4.22); empty once stopped.
    var stats: DockObserverStats { session?.stats ?? DockObserverStats() }

    func start() {
        guard session == nil else { return }
        let session = DockObserverSession(
            loginUptime: Self.loginUptime(),
            deliver: { [weak self] selection in self?.onSelection?(selection) },
            needsPID: { [weak self] in self?.refreshPID() })
        self.session = session
        dockPID = Self.findDockPID()
        session.start(pid: dockPID, apps: Self.runningApps(), primaryHeight: Self.primaryHeight)

        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: []) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.appsChanged() } }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didWakeNotification)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"))
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
    }

    /// Removes every observer and ends the thread. The `AXObserver` goes on the thread, after any read in flight.
    func stop() {
        guard let session else { return }
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        appsObservation?.invalidate()
        appsObservation = nil
        session.stop()
        self.session = nil
        dockPID = nil
        appsChangePending = false
    }

    /// Try Again (§4.17 state 5): attach at once, with the same Dock or not.
    func retry() {
        guard let session else { return }
        dockPID = Self.findDockPID()
        session.retry(pid: dockPID, apps: Self.runningApps(), primaryHeight: Self.primaryHeight)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        observers.append((center, token))
    }

    /// Wake, unlock, session-active or a display change (D2-4).
    private func rebuild() {
        guard let session else { return }
        dockPID = Self.findDockPID()
        session.rebuild(pid: dockPID, apps: Self.runningApps(), primaryHeight: Self.primaryHeight)
    }

    /// KVO fires once per launch and quit; the work runs once per main-queue turn.
    private func appsChanged() {
        guard session != nil, !appsChangePending else { return }
        appsChangePending = true
        Task { @MainActor [weak self] in self?.flushAppsChange() }
    }

    private func flushAppsChange() {
        appsChangePending = false
        guard let session else { return }
        session.appsChanged(Self.runningApps())
        refreshPID()
    }

    /// The Dock's pid again. A change re-attaches at once (a Dock restart).
    private func refreshPID() {
        guard let session else { return }
        let pid = Self.findDockPID()
        guard pid != dockPID else { return }
        dockPID = pid
        session.dockChanged(pid: pid)
    }

    private static func findDockPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: DockReader.bundleID)
            .filter { !$0.isTerminated && DockObserverSession.isAlive($0.processIdentifier) }
            .map(\.processIdentifier)
            .min()
    }

    /// The apps an item can map to (§4.8 item → app).
    private static func runningApps() -> [DockRunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map { DockRunningApp(pid: $0.processIdentifier, bundlePath: $0.bundleURL?.path,
                                  bundleID: $0.bundleIdentifier, name: $0.localizedName) }
    }

    private static var primaryHeight: Double { Double(Screens.primaryHeight) }

    /// Monotonic seconds at login: `loginwindow`'s start, or Snaptic's own when that can't be read (X2-16).
    private static func loginUptime() -> Double? {
        let loginwindow = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow")
            .first { !$0.isTerminated }
        var started = loginwindow.map { SNProcess.instanceID(for: $0.processIdentifier) } ?? 0
        if started == 0 { started = SNProcess.startTime(for: getpid()) }
        guard started > 0 else { return nil }
        let age = Date().timeIntervalSince1970 - Double(started) / 1_000_000
        guard age >= 0 else { return nil }
        return ProcessInfo.processInfo.systemUptime - age
    }
}

private let dockCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let destroyed = (notification as String) == kAXUIElementDestroyedNotification
    // Runs on the session's thread; the box outlives the observer, and its target is weak.
    Unmanaged<CallbackTarget<DockObserverSession>>.fromOpaque(refcon).takeUnretainedValue().target?
        .notified(destroyed: destroyed)
}

/// The thread side of `DockObserver`: the `AXObserver`, the reads, the ladder, the back-off and the health check.
/// State marked `thread` is touched on `thread` only; the stats and the pending selection are under `stateLock`.
private final class DockObserverSession: @unchecked Sendable {
    private let thread = ObserverThread()
    private let deliverHandler: @MainActor (DockSelection?) -> Void
    private let needsPID: @MainActor () -> Void
    private let loginUptime: Double?
    private var box: Unmanaged<CallbackTarget<DockObserverSession>>?   // set on main, released on `thread`

    // `thread`
    private var pid: pid_t?
    private var apps: [DockRunningApp] = []
    private var primaryHeight: Double = 0
    private var reader: DockReader?
    private var observer: AXObserver?
    /// Bumped by every fresh attach, so an older ladder's or check's steps drop out.
    private var generation = 0
    private var ladderRunning = false
    /// The selected child last read and delivered (the health check's "last one notified").
    private var lastNotified: AXUIElement?
    private var lastDelivered: DockSelection?
    private var readScheduled = false
    private var retriedAfterTimeout = false
    private var backoff = DockReadBackoff()

    private let stateLock = NSLock()
    private var stopped = false
    private var statsValue = DockObserverStats()
    private var pending: DockSelection?
    private var deliveryScheduled = false

    init(loginUptime: Double?, deliver: @escaping @MainActor (DockSelection?) -> Void,
         needsPID: @escaping @MainActor () -> Void) {
        self.loginUptime = loginUptime
        deliverHandler = deliver
        self.needsPID = needsPID
    }

    var stats: DockObserverStats {
        stateLock.lock(); defer { stateLock.unlock() }
        return statsValue
    }

    /// `kill(pid, 0)`: false only when the pid is gone.
    static func isAlive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: Main

    @MainActor func start(pid: pid_t?, apps: [DockRunningApp], primaryHeight: Double) {
        box = Unmanaged.passRetained(CallbackTarget(self))
        thread.name = "Snaptic Dock observer"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.waitUntilReady()
        onThread { [weak self] in
            guard let self else { return }
            self.update(pid: pid, apps: apps, primaryHeight: primaryHeight)
            self.attachNow()
            self.scheduleHealthCheck()
        }
    }

    @MainActor func dockChanged(pid: pid_t?) {
        onThread { [weak self] in
            guard let self, pid != self.pid else { return }
            self.pid = pid
            self.detach()
            self.attachNow()
        }
    }

    @MainActor func rebuild(pid: pid_t?, apps: [DockRunningApp], primaryHeight: Double) {
        onThread { [weak self] in
            guard let self else { return }
            self.updateStats { $0.didRebuild() }
            self.update(pid: pid, apps: apps, primaryHeight: primaryHeight)
            self.detach()
            self.attachNow(checks: DockReattachLadder.rebuildChecks)
        }
    }

    @MainActor func retry(pid: pid_t?, apps: [DockRunningApp], primaryHeight: Double) {
        onThread { [weak self] in
            guard let self else { return }
            self.update(pid: pid, apps: apps, primaryHeight: primaryHeight)
            self.detach()
            self.attachNow()
        }
    }

    @MainActor func appsChanged(_ apps: [DockRunningApp]) {
        onThread { [weak self] in self?.apps = apps }
    }

    /// Removes the observer, releases the refcon box and ends the thread.
    @MainActor func stop() {
        stateLock.lock()
        let already = stopped
        stopped = true
        stateLock.unlock()
        guard !already else { return }
        let box = self.box
        thread.cancel()
        thread.perform {
            self.detach(deliverNil: false)
            box?.release()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    @MainActor private func flush() {
        stateLock.lock()
        let selection = pending
        deliveryScheduled = false
        let stopped = self.stopped
        stateLock.unlock()
        guard !stopped else { return }
        deliverHandler(selection)
    }

    // MARK: Thread

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

    private func after(_ delay: Double, _ block: @escaping @Sendable () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.onThread(block)
        }
    }

    private func updateStats(_ change: (inout DockObserverStats) -> Void) {
        stateLock.lock()
        change(&statsValue)
        stateLock.unlock()
    }

    private func update(pid: pid_t?, apps: [DockRunningApp], primaryHeight: Double) {
        self.pid = pid
        self.apps = apps
        self.primaryHeight = primaryHeight
    }

    private func askForPID() {
        let ask = needsPID
        Task { @MainActor in ask() }
    }

    /// A fresh attach: now, then the ladder while it fails (X-17). `checks`: after a rebuild, look at the list again.
    private func attachNow(checks: [Double] = []) {
        generation += 1
        let gen = generation
        attempt(gen, step: 0)
        for delay in checks {
            after(delay) { [weak self] in self?.verify(gen) }
        }
    }

    private func attempt(_ gen: Int, step: Int) {
        guard gen == generation, observer == nil else { return }
        if attach() {
            ladderRunning = false
            return
        }
        let now = Self.now
        let delay = DockReattachLadder.delay(attempt: step, sinceLogin: loginUptime.map { now - $0 })
        ladderRunning = delay != nil
        updateStats { $0.attachFailed(now: now, ladderEnded: delay == nil) }
        guard let delay else { return }
        after(delay) { [weak self] in self?.attempt(gen, step: step + 1) }
    }

    /// One attach: a fresh `AXObserver` on the list, then the current selection read and delivered.
    private func attach() -> Bool {
        guard observer == nil else { return true }
        guard let box, let pid, Self.isAlive(pid) else {
            askForPID()
            return false
        }
        let reader: DockReader
        if let current = self.reader, current.pid == pid {
            reader = current
        } else {
            reader = DockReader(pid: pid)
        }
        guard case .value(let list) = reader.findList() else { return false }
        var created: AXObserver?
        guard AXObserverCreate(pid, dockCallback, &created) == .success, let observer = created else { return false }
        let refcon = box.toOpaque()
        guard AXObserverAddNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString,
                                        refcon) == .success else {
            CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(observer))
            return false
        }
        // Best effort: a destroyed list re-attaches at once instead of at the next check.
        AXObserverAddNotification(observer, list, kAXUIElementDestroyedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.reader = reader
        self.observer = observer
        lastNotified = nil
        updateStats { $0.didAttach(pid: pid) }
        reader.readListFrame(primaryHeight: primaryHeight, now: Self.now)
        readSelection()
        return true
    }

    /// The old observer is invalidated and its run-loop source removed (§4.8).
    private func detach(deliverNil: Bool = true) {
        if let observer {
            if let list = reader?.list {
                AXObserverRemoveNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString)
                AXObserverRemoveNotification(observer, list, kAXUIElementDestroyedNotification as CFString)
            }
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
            self.observer = nil
            updateStats { $0.didDetach() }
        }
        lastNotified = nil
        readScheduled = false
        if deliverNil, lastDelivered != nil { publish(nil) }
    }

    /// The AX callback. One read is queued at a time, and it reads the selection as it is then, so a burst of
    /// notifications costs one read per queue turn and ends on the latest selection.
    fileprivate func notified(destroyed: Bool) {
        guard observer != nil else { return }
        if destroyed {
            detach()
            attachNow()
            return
        }
        retriedAfterTimeout = false
        scheduleRead()
    }

    private func scheduleRead() {
        guard !readScheduled else { return }
        readScheduled = true
        let wait = backoff.wait(now: Self.now)
        if wait > 0 {
            after(wait) { [weak self] in self?.readSelection() }
        } else {
            onThread { [weak self] in self?.readSelection() }
        }
    }

    private func readSelection() {
        readScheduled = false
        guard observer != nil, let reader else { return }
        if backoff.wait(now: Self.now) > 0 {
            scheduleRead()
            return
        }
        switch reader.selectedChild() {
        case .value(let child):
            guard !Self.same(child, lastNotified) else {
                retriedAfterTimeout = false
                return
            }
            guard let child else {
                lastNotified = nil
                publish(nil)
                return
            }
            switch reader.selection(of: child, apps: apps, primaryHeight: primaryHeight, now: Self.now) {
            case .value(let selection):
                lastNotified = child
                retriedAfterTimeout = false
                publish(selection)
            case .timedOut:
                readTimedOut(retry: true)
            case .invalid, .failed:
                lastNotified = child
                publish(nil)
            }
        case .timedOut:
            readTimedOut(retry: true)
        case .invalid:
            // The list is gone (a display change can rebuild it under the same pid).
            detach()
            attachNow()
        case .failed:
            break
        }
    }

    /// Feeds the back-off (§4.8: three timeouts in 10 s wait 1 s); a selection read is tried once more after it.
    private func readTimedOut(retry: Bool) {
        backoff.timedOut(now: Self.now)
        let slow = backoff.slowCount
        updateStats { $0.dockSlow = slow }
        guard retry, !retriedAfterTimeout else { return }
        retriedAfterTimeout = true
        scheduleRead()
    }

    private func publish(_ selection: DockSelection?) {
        lastDelivered = selection
        stateLock.lock()
        statsValue.didRead(selection)
        pending = selection
        let schedule = !deliveryScheduled
        deliveryScheduled = true
        stateLock.unlock()
        guard schedule else { return }
        Task { @MainActor [weak self] in self?.flush() }
    }

    private static func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return CFEqual(a, b)
        default: return false
        }
    }

    /// After a rebuild: a list that went invalid re-attaches; a live one has its frame read again.
    private func verify(_ gen: Int) {
        guard gen == generation, observer != nil, let reader else { return }
        if case .invalid = reader.selectedChild() {
            detach()
            attachNow()
        } else {
            reader.readListFrame(primaryHeight: primaryHeight, now: Self.now)
        }
    }

    private func scheduleHealthCheck() {
        after(DockReattachLadder.healthInterval) { [weak self] in
            guard let self else { return }
            self.healthCheck()
            self.scheduleHealthCheck()
        }
    }

    /// Every 30 s (§4.8, D2-4): a gone pid asks main for the Dock again; not attached (the ladder ended), one more
    /// attach; attached, the list and the pointer are read once for a silent death.
    private func healthCheck() {
        guard let pid, Self.isAlive(pid) else {
            detach()
            askForPID()
            return
        }
        guard observer != nil, let reader else {
            guard !ladderRunning else { return }
            generation += 1
            attempt(generation, step: Int.max)
            return
        }
        // A read already queued would make a live observer look dead.
        guard !readScheduled else { return }
        var listValid = true
        var selectionSame = true
        switch reader.selectedChild() {
        case .value(let child): selectionSame = Self.same(child, lastNotified)
        case .invalid: listValid = false
        case .timedOut:
            readTimedOut(retry: false)
            return
        case .failed:
            return
        }
        let pointer = CGEvent(source: nil).map {
            DockGeometry.cocoaPoint(fromAX: DockPoint(x: Double($0.location.x), y: Double($0.location.y)),
                                    primaryHeight: primaryHeight)
        }
        let verdict = DockHealthRules.verdict(listValid: listValid, pointer: pointer, lastDockFrame: reader.listFrame,
                                              selectionSame: selectionSame)
        guard verdict == .silentDeath else { return }
        updateStats { $0.didSilentReattach() }
        detach()
        attachNow()
    }
}
