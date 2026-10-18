import AppKit
import Combine
import CoreGraphics
import Darwin
import SnapticKit
import SnapticShims

// Session state (owner: B). PLAN §4.9: lock/unlock, sleep/wake, fast user switching.
// Distributed lock notifications only ever *close* the gate; every reopen re-checks
// CGSessionCopyCurrentDictionary (on console, not locked). Also hosts the auth-window
// watcher (R5.7) that overlay and gamma code subscribe to.

/// Thread-safe copy of the gate state for nonisolated readers (media keys, DDC queue).
final class SessionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    func set(_ value: Bool) { lock.lock(); open = value; lock.unlock() }
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
}

enum SessionEvent: Equatable {
    case willSleep, didWake, screensDidSleep, screensDidWake, locked, unlocked, resignedActive, becameActive
}

@MainActor final class SessionGate: DisplayServiceLifecycle, DiagnosticsContributor {
    static var serviceID: DisplayServiceID { .sessionGate }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    init() {}

    /// False while the session is locked, switched out or asleep.
    private(set) var isOpen = true
    /// Nonisolated mirror of `isOpen`.
    let flag = SessionFlag()
    /// Set by DisplaysModule, which fans out to SessionParticipants.
    var onStateChange: (@MainActor (_ isOpen: Bool) -> Void)?

    private(set) var isLocked = false
    private(set) var isAsleep = false
    private(set) var screensAsleep = false
    private(set) var isActiveSession = true
    /// Uptime seconds of the last wake / unlock (ConnectPlanner graces, DDC resume at wake + 3 s).
    private(set) var lastWakeUptime: Double?
    private(set) var lastUnlockUptime: Double?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var eventHandlers: [(UInt64, @MainActor (SessionEvent) -> Void)] = []
    private var serial: UInt64 = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var active = false

    // MARK: Lifecycle

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification) { $0.handle(.willSleep) }
        observe(ws, NSWorkspace.didWakeNotification) { $0.handle(.didWake) }
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.handle(.screensDidSleep) }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.handle(.screensDidWake) }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.handle(.resignedActive) }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0.handle(.becameActive) }
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, Notification.Name("com.apple.screenIsLocked")) { $0.handle(.locked) }
        observe(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.handle(.unlocked) }
        let s = Self.readSession()
        isLocked = s.locked
        isActiveSession = s.onConsole
        recompute()
        context.diagnostics.register(self, section: L("Session"), lifetime: lifetime)
    }

    func deactivate() {
        guard active else { return }
        active = false
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        authWatcher.stopAll()
        resumeWaiters()
        context = nil
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (SessionGate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: Events

    /// Subscribes to raw session events until `lifetime` ends.
    func observeEvents(lifetime: Lifetime, _ handler: @escaping @MainActor (SessionEvent) -> Void) {
        guard !lifetime.isEnded else { return }
        serial &+= 1
        let mine = serial
        eventHandlers.append((mine, handler))
        lifetime.onEnd { [weak self] in self?.eventHandlers.removeAll { $0.0 == mine } }
    }

    private func handle(_ event: SessionEvent) {
        let now = Self.uptime()
        switch event {
        case .willSleep: isAsleep = true
        case .didWake:
            isAsleep = false
            lastWakeUptime = now
        case .screensDidSleep: screensAsleep = true
        case .screensDidWake: screensAsleep = false
        case .locked: isLocked = true
        case .unlocked, .becameActive, .resignedActive: break
        }
        // Reopening is never trusted to a notification: re-read the session dictionary.
        let s = Self.readSession()
        isActiveSession = s.onConsole
        if event == .locked || s.locked { isLocked = true } else if event == .unlocked || !s.locked {
            if isLocked { lastUnlockUptime = now }
            isLocked = s.locked
        }
        if event == .resignedActive { isActiveSession = false }
        for (_, h) in eventHandlers { h(event) }
        recompute()
    }

    private func recompute() {
        let open = isActiveSession && !isLocked && !isAsleep
        flag.set(open)
        guard open != isOpen else { return }
        isOpen = open
        EventLog.shared.record(.safety, open ? "Session open" : "Session paused")
        onStateChange?(open)
        if open { resumeWaiters() }
    }

    func waitUntilOpen() async {
        if isOpen || !active { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }

    private func resumeWaiters() {
        let list = waiters
        waiters = []
        list.forEach { $0.resume() }
    }

    /// Fresh check for resume-like actions (capture, XDR, dim on lock): on console and unlocked.
    func sessionAllowsResume() -> Bool {
        let s = Self.readSession()
        return s.onConsole && !s.locked
    }

    nonisolated static func readSession() -> (onConsole: Bool, locked: Bool) {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return (true, false) }
        let onConsole = (dict[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue ?? true
        let locked = (dict["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
        return (onConsole, locked)
    }

    nonisolated static func uptime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    func diagnostics() -> [(String, String)] {
        [("Session", isOpen ? "open" : "paused"), ("Locked", isLocked ? "yes" : "no"),
         ("Asleep", isAsleep ? "yes" : "no"), ("On console", isActiveSession ? "yes" : "no"),
         ("Auth-window watch", authWatcher.isRunning ? (authWatcher.isSuppressing ? "suppressing" : "watching") : "off")]
    }

    // MARK: Authentication windows (R5.7)

    let authWatcher = AuthWindowWatcher()

    /// Watches for system authentication windows while `lifetime` lasts (start it while dim
    /// to black or overlay alpha > 0.5 is active). `onChange(true)`: order out full-screen
    /// overlays and raise gamma dim-to-black to ≥ 30 %; `onChange(false)`: restore.
    func watchAuthWindows(lifetime: Lifetime, onChange: @escaping @MainActor (_ suppress: Bool) -> Void) {
        authWatcher.add(lifetime: lifetime, gate: self, onChange: onChange)
    }
}

/// Polls CGWindowListCopyWindowInfo (owner PID, alpha, bounds; never titles) at 2 Hz, and
/// every 2 s during an episode, plus on app activation.
@MainActor final class AuthWindowWatcher {
    private var handlers: [(UInt64, @MainActor (Bool) -> Void)] = []
    private var serial: UInt64 = 0
    private var timer: Timer?
    private var activation: NSObjectProtocol?
    private var episode = AuthEpisode()
    private weak var gate: SessionGate?
    /// Owner paths by pid, valid only for the process instance with that start time; pids
    /// absent from the latest window list are dropped (FIXES-R1 B6: pids are reused).
    private struct CachedPath {
        let startTime: UInt64
        let path: String
    }
    private var pathCache: [pid_t: CachedPath] = [:]

    var isRunning: Bool { timer != nil }
    var isSuppressing: Bool { episode.isSuppressing }

    init() {}

    func add(lifetime: Lifetime, gate: SessionGate, onChange: @escaping @MainActor (Bool) -> Void) {
        guard !lifetime.isEnded else { return }
        self.gate = gate
        serial &+= 1
        let mine = serial
        handlers.append((mine, onChange))
        lifetime.onEnd { [weak self] in
            guard let self else { return }
            self.handlers.removeAll { $0.0 == mine }
            if self.handlers.isEmpty { self.stopAll() }
        }
        if episode.isSuppressing { onChange(true) }
        start()
    }

    func stopAll() {
        timer?.invalidate()
        timer = nil
        if let a = activation { NSWorkspace.shared.notificationCenter.removeObserver(a) }
        activation = nil
        if episode.isSuppressing {
            episode = AuthEpisode()
            for (_, h) in handlers { h(false) }
        }
        episode = AuthEpisode()
        pathCache = [:]
    }

    private func start() {
        guard timer == nil else { return }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        schedule(0.5)
        check()
    }

    private func schedule(_ interval: Double) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        guard timer != nil else { return }
        let locked = SessionGate.readSession().locked
        let present = AuthProcesses.authWindowPresent(Self.windows(cache: &pathCache), screens: Self.screens(),
                                                      sessionLocked: locked)
        let before = episode.isSuppressing
        if episode.update(present: present, at: SessionGate.uptime()) {
            EventLog.shared.record(.overlay, episode.isSuppressing ? "Auth window: dimming suspended" : "Auth window gone")
            for (_, h) in handlers { h(episode.isSuppressing) }
        }
        if before != episode.isSuppressing { schedule(episode.nextCheck(base: 0.5)) }
    }

    private static func screens() -> [ScreenRect] {
        CGDirectDisplayID.online().filter(\.isActive).map {
            let b = CGDisplayBounds($0)
            return ScreenRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height)
        }
    }

    private static func windows(cache: inout [pid_t: CachedPath]) -> [WindowSample] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            cache = [:]
            return []
        }
        var out: [WindowSample] = []
        var seen: [pid_t: CachedPath] = [:]
        for w in list.prefix(1000) {
            guard let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid > 0,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let entry: CachedPath
            if let known = seen[pid] {
                entry = known
            } else {
                entry = ownerPath(pid, cached: cache[pid])
                seen[pid] = entry
            }
            guard !entry.path.isEmpty else { continue }
            out.append(WindowSample(ownerPath: entry.path, alpha: alpha, x: rect.origin.x, y: rect.origin.y,
                                    width: rect.width, height: rect.height, layer: layer))
        }
        cache = seen
        return out
    }

    /// The executable path of the process instance `pid` names right now. A cached path is
    /// reused only when the start time still matches; a fresh read is bracketed by two
    /// start-time reads so a pid reused in between yields no path (the window is skipped).
    private static func ownerPath(_ pid: pid_t, cached: CachedPath?) -> CachedPath {
        let start = SNProcess.startTime(for: pid)
        guard start != 0 else { return CachedPath(startTime: 0, path: "") }
        if let cached, cached.startTime == start { return cached }
        let path = processPath(pid) ?? ""
        guard SNProcess.startTime(for: pid) == start else { return CachedPath(startTime: 0, path: "") }
        return CachedPath(startTime: start, path: path)
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }
}
