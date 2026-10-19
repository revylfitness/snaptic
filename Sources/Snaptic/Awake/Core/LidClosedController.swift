import AppKit
import CoreGraphics
import SnapticKit
import SnapticShims

// Lid-closed mode, app side (owner: T-lid-app; PLAN 0.3.1 B3.0, B3.1, B3.3): the single-flight state machine (the only
// writer of `AwakeRuntimeState.lidMode`, lint L16), the journal and beacon, the osascript spawn (one of the two callers
// of `HelperSpawner.spawnAdminScript`, lint L18), verification, the heartbeat and liveness checks, display sleep while
// the lid is shut, and every way the mode ends. SessionController starts and stops it with the session feature
// (`.lidClosed` belongs to the sessions controller) and reports the session events the N19 gate decides on.
//
// What may start it: only `request(_:source:)`, called from a click in Snaptic's own menu, Custom… panel or Settings
// (B2). Nothing persisted carries it: the session's `lidRequested` is runtime-only and set by SessionController alone.

/// A turn-on request (B1): an idle start (a preset, or a Custom… session), or the mode added to the running session.
enum LidRequest: Equatable {
    case preset(StableID)
    case custom(AwakeSessionKind, AwakeSessionOptions)
    case add
}

/// What one heartbeat saw on its queue (B3.3).
struct LidTick: Sendable {
    /// kill(pid, 0) said ESRCH, or the pid now names another process; nil before verify recorded the watchdog.
    var watchdogGone: Bool?
    /// The kernel's SleepDisabled (nil: unreadable).
    var sleepDisabled: Bool?
}

/// The beacon file and its heartbeat (B3.1 step 3, B3.3). The descriptor is touched only on the private queue: the
/// timer's handler refreshes it and its cancel handler closes it, so a reused descriptor number is never touched.
final class LidBeacon: @unchecked Sendable {
    static let periodSeconds: Double = 5
    /// The beacon is refreshed only while the main thread stamped within this long (a hung Snaptic lets it go stale,
    /// and the watchdog turns sleep back on).
    static let mainHungMillis: UInt64 = 10_000

    let directory: String
    let token: String
    private let queue = DispatchQueue(label: "app.snaptic.lid-heartbeat")
    private let lock = NSLock()
    private let fd: Int32
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var watched: (pid: Int32, instance: UInt64)?

    /// Creates `beat-<token>` with O_CREAT|O_EXCL|O_NOFOLLOW (0600) in a directory `LidSystem` checked; nil if it can't.
    init?(directory: String, token: String) {
        guard LidSystem.isToken(token) else { return nil }
        let fd = open(directory + "/beat-" + token, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        self.directory = directory
        self.token = token
        self.fd = fd
    }

    /// From verify on, each beat also checks the watchdog (its pid and the instance recorded at verify).
    func watch(pid: Int32, instance: UInt64) {
        lock.lock(); watched = (pid, instance); lock.unlock()
    }

    /// Every 5 s (0.5 s leeway): refresh the beacon (`futimens`), then read the liveness facts; `onTick` runs on
    /// the private queue.
    func start(_ onTick: @escaping @Sendable (LidTick) -> Void) {
        lock.lock()
        guard timer == nil, !stopped else { lock.unlock(); return }
        let fd = self.fd
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + Self.periodSeconds, repeating: Self.periodSeconds, leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if HostHeartbeat.shared.mainAgeMillis() < Self.mainHungMillis { _ = futimens(fd, nil) }
            onTick(self.read())
        }
        source.setCancelHandler { _ = close(fd) }
        timer = source
        lock.unlock()
        source.resume()
    }

    /// Stops the heartbeat and closes the descriptor (on the queue). Idempotent.
    func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let source = timer
        timer = nil
        lock.unlock()
        if let source {
            source.cancel()
        } else {
            let fd = self.fd
            queue.async { _ = close(fd) }
        }
    }

    /// The liveness facts now (any thread).
    func read() -> LidTick {
        lock.lock()
        let target = watched
        lock.unlock()
        var gone: Bool?
        if let target {
            let alive = kill(target.pid, 0) == 0 || errno != ESRCH
            gone = !alive || SNProcess.instanceID(for: target.pid) != target.instance
        }
        return LidTick(watchdogGone: gone, sleepDisabled: LidSystem.kernelSleepDisabled())
    }
}

@MainActor final class LidClosedController {
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    static let verifyPollNanoseconds: UInt64 = 500_000_000
    /// Polls of the kernel after the watchdog started (10 s).
    static let verifyPolls = 20
    /// "Turning on lid-closed mode…" once verifying took this many polls (2 s).
    static let slowVerifyPolls = 4
    /// B3.1 step 7: the check five seconds after turning on.
    static let recheckNanoseconds: UInt64 = 5_000_000_000
    /// B3.3: turning off waits this long for the kernel to read 0; B3.0: a failed turn-on keeps its journal this long.
    static let stopWaitSeconds: Double = 15
    static let abandonWaitSeconds: Double = 30
    /// B3.3: `pmset displaysleepnow` at most this often (powerd defers it for about 30 s after a wake).
    static let displaySleepIntervalSeconds: Double = 10

    /// A request between its click and `on` (B3.0 `authorizing`, `verifying`).
    private struct Pending {
        let token: String
        let request: LidRequest
        let source: AwakeSessionSource
        /// `.add`: the session the mode joins (gone = superseded).
        let sessionID: StableID?
        let floor: Int
        /// Wall time of the spawn (the watchdog must have started after it), and its continuous time.
        var spawnWall: Double = 0
        var spawnContinuous: Double = 0
    }

    /// The mode while on.
    private struct Active {
        let token: String
        let pid: Int32
        let floor: Int
        /// The original turn-on (continuous); never reset, also when a menu or Settings start keeps the mode (B2).
        let capStart: Double
        var sessionID: StableID?
    }

    private var lifetime: Lifetime?
    private var pending: Pending?
    private var active: Active?
    private var beacon: LidBeacon?
    private var stopPath: LidStopPath?
    private var emergency: EmergencyActions.Token?
    private var activity: NSObjectProtocol?
    private var admin: HelperHandle?
    private var adminOutput: Data?
    /// Consecutive beats that read the kernel's SleepDisabled as 0.
    private var zeroReads = 0
    private var capWarned = false
    private var lastDisplaySleep: Double?
    private var displaySleepRunning = false
    private var screenObserver: NSObjectProtocol?
    /// The session SessionController is replacing keeps the mode (B2 "keep"): its id, until the new one starts.
    private var keepAcross: StableID?
    /// The controller is starting its own session (an idle start that just verified): not a superseding start.
    private var startingOwnSession = false

    init() {}

    // MARK: State

    var mode: AwakeLidMode { context?.runtime.lidMode ?? .off }

    /// The one writer of `runtime.lidMode`. App Nap is held while the state isn't `off` (B3.0), so the heartbeat
    /// and the waits aren't starved.
    private func set(_ mode: AwakeLidMode) {
        if case .off = mode { endActivity() } else { beginActivity() }
        guard let rt = context?.runtime, rt.lidMode != mode else { return }
        rt.lidMode = mode
    }

    /// B3.3 `lidShut`: the mode is on, the lid is closed and no external display is attached. While true the
    /// session's display policy counts as `maySleep` (AwakeArbiterInput) and Snaptic puts the built-in panel to sleep.
    var lidShut: Bool {
        active != nil && context?.runtime.lidClosed == true && !Self.displays().external
    }

    /// The lid row of the menus and the Settings pull-downs (B1).
    var rowState: LidRowState? {
        switch mode {
        case .authorizing: return .authorizing
        case .verifying: return .verifying
        case .stopping: return .stopping
        case .on: return .on
        case .off, .failed: return nil
        }
    }

    // MARK: Lifecycle (SessionController)

    func start(_ context: AwakeContext, lifetime: Lifetime) {
        guard self.lifetime == nil else { return }
        self.context = context
        self.lifetime = lifetime
        // Ahead of the session's own guards (B3.3): SessionController starts this controller before it observes.
        context.power.observe(lifetime) { [weak self] in self?.powerChanged() }
        context.system.observeEvents(lifetime) { [weak self] event in self?.systemEvent(event) }
    }

    /// Module stop or quit: a pending request is abandoned and the mode ends; the stop file is written at once and
    /// the host-level LidRecoveryState finishes the kernel check (this controller is going away).
    func stop(_ reason: AwakeLidEnd) {
        if let p = pending {
            admin?.interrupt()
            abandon(p.token, failure: nil, toast: nil)
        }
        if active != nil { end(reason) }
        tearDown()
        set(.off)
        keepAcross = nil
        lifetime = nil
        context = nil
    }

    // MARK: Requests (B1, B2)

    /// A direct user action in Snaptic's UI asks for the mode. Settings requests check the focus guard here.
    func request(_ request: LidRequest, source: AwakeSessionSource) {
        guard let ctx = context, lifetime != nil, case .off = mode, ctx.runtime.isEffective(.lidClosed) else { return }
        let mayStart = source != .settings || SettingsShell.shared.mayStart()
        var running: AwakeSession?
        if request == .add {
            guard case .manual(let s) = ctx.runtime.governing, s.id == ctx.sessions.manual?.id else { return }
            running = s
        }
        guard AwakeLidGate.decide(source: source, mayStart: mayStart, event: .request(running: running?.source))
                == .allowed, LidSystem.hasLid() else { return }
        let facts = ctx.power.facts
        let discharging = facts?.discharging ?? false
        let floor = AwakeLidPolicy.floor(awakeGuards: ctx.config.value.guards)
        if let refusal = AwakeLidPolicy.startRefusal(batteryPercent: discharging ? facts?.percent : nil,
                                                     discharging: discharging, floor: floor,
                                                     thermalSerious: (facts?.thermal ?? .nominal) >= .serious,
                                                     overrideGuards: running?.overrideGuards ?? false,
                                                     translocated: PermissionFlow.isTranslocated,
                                                     recovery: ctx.host.lidRecovery?.recovery ?? .nothing) {
            refuse(refusal)
            return
        }
        let token = LidSystem.newToken()
        pending = Pending(token: token, request: request, source: source, sessionID: running?.id, floor: floor)
        zeroReads = 0
        capWarned = false
        set(.authorizing(token: token))
        Task { @MainActor [weak self] in await self?.authorize(token) }
    }

    /// "✓ Keep Awake with the Lid Closed": off without a password.
    func turnOff() {
        guard active != nil else { return }
        end(.user)
    }

    private func refuse(_ refusal: AwakeLidRefusal) {
        guard let ctx = context else { return }
        if refusal == .leftover {
            ctx.host.toasts.show(refusal.text, actions: [
                ToastAction(title: L("Turn Sleep Back On…")) { [weak recovery = ctx.host.lidRecovery] in
                    recovery?.turnSleepBackOn()
                },
                ToastAction(title: L("Open Awake Settings…")) { [weak self] in
                    self?.context?.host.openSettings(SettingsRoute(SettingsRootID.awake))
                },
            ])
        } else {
            ctx.host.toasts.show(refusal.text)
        }
    }

    // MARK: Turning on (B3.1)

    private func authorize(_ token: String) async {
        // 1. Preflight: the kernel (IORegistry) and the stored preference; IPC, so off main.
        let (kernel, preference) = await Self.offMain {
            (LidSystem.kernelSleepDisabled(), OtherAssertionsReader.sleepDisabledPreference())
        }
        guard var p = pending, p.token == token, let ctx = context else { return }
        guard let kernel else { return abandon(token, failure: .verify, toast: Self.couldNotTurnOn) }
        if kernel || preference {
            // Someone else's setting: never touched. The session starts or continues without the mode.
            abandon(token, failure: nil, toast: Self.alreadyOff)
            startWithoutMode(p)
            return
        }
        // 2. The journal (one slot, 0600, atomic).
        let now = AwakeModule.clockNow()
        let journal = AwakeLidJournal(token: token, bootSessionUUID: now.bootSession, startedAtWall: now.wall,
                                      startedAtContinuous: now.continuous, floor: p.floor)
        guard LidJournalStore.write(journal) else { return abandon(token, failure: .beacon, toast: Self.couldNotTurnOn) }
        // 3. The beacon directory, the beacon and the heartbeat (it runs while the dialog waits, too).
        guard let dir = LidSystem.beaconDirectory(), LidSystem.prepareBeaconDirectory(dir) else {
            return abandon(token, failure: .beacon, toast: Self.couldNotTurnOn)
        }
        LidSystem.clearBeacons(dir)
        guard let beacon = LidBeacon(directory: dir, token: token) else {
            return abandon(token, failure: .beacon, toast: Self.couldNotTurnOn)
        }
        self.beacon = beacon
        let target = CallbackTarget(self)
        beacon.start { tick in
            DispatchQueue.main.async { MainActor.assumeIsolated { target.target?.tick(token, tick) } }
        }
        // Quit, even with main hung: the signal path writes the stop file.
        if let path = LidStopPath(dir: dir, token: token) {
            stopPath = path
            emergency = EmergencyActions.shared.add("lid-closed mode") { path.touch() }
        }
        // 4. The fixed script with validated arguments; the prompt names the floor.
        guard let args = LidWatchdog.Arguments.validated(uid: getuid(), pid: getpid(), token: token,
                                                         capSeconds: LidWatchdog.capSeconds, floor: p.floor, dir: dir),
              let script = LidWatchdog.startScript(args, prompt: LidWatchdog.promptText(floor: p.floor)) else {
            return abandon(token, failure: .args, toast: Self.couldNotTurnOn)
        }
        p.spawnWall = Date().timeIntervalSince1970
        p.spawnContinuous = AwakeModule.clockNow().continuous
        pending = p
        adminOutput = nil
        let handle: HelperHandle
        do {
            handle = try await ctx.host.spawner.spawnAdminScript(script, onLine: { [weak self] line in
                guard let self, self.pending?.token == token, self.adminOutput == nil else { return }
                self.adminOutput = line
            }, onExit: { [weak self] status in
                self?.adminExited(token, status: status)
            })
        } catch {
            return abandon(token, failure: .spawn, toast: Self.couldNotTurnOn)
        }
        guard pending?.token == token else {
            handle.interrupt()   // superseded while osascript was being checked
            return
        }
        if !handle.isReaped { admin = handle }
    }

    /// 5. osascript's result.
    private func adminExited(_ token: String, status: Int32) {
        let timedOut = admin?.timedOut ?? false
        admin = nil
        let output = adminOutput.map { String(decoding: $0, as: UTF8.self) } ?? ""
        adminOutput = nil
        guard let p = pending, p.token == token, case .authorizing = mode else { return }
        let elapsed = AwakeModule.clockNow().continuous - p.spawnContinuous
        if timedOut || elapsed >= HelperSpawner.adminTimeoutSeconds {
            return abandon(token, failure: .timeout, toast: Self.couldNotTurnOn)
        }
        switch LidWatchdog.parseResult(output) {
        case .launched(let pid):
            Task { @MainActor [weak self] in await self?.verify(token, pid: pid) }
        case .canceled:
            abandon(token, failure: nil, toast: nil)
        case .failed(3):
            abandon(token, failure: nil, toast: Self.alreadyOff)
            startWithoutMode(p)
        case .failed(64):
            abandon(token, failure: .args, toast: Self.couldNotTurnOn)
        case .failed:
            abandon(token, failure: .spawn, toast: Self.couldNotTurnOn)
        }
    }

    /// 6. The watchdog is root's and started after the spawn; then the kernel must read 1 within 10 s.
    private func verify(_ token: String, pid: Int32) async {
        guard let p = pending, p.token == token else { return }
        set(.verifying(token: token, pid: pid))
        let instance = SNProcess.instanceID(for: pid)
        guard instance != 0, SNProcess.realUID(for: pid) == 0, Double(instance) >= p.spawnWall * 1_000_000 else {
            return abandon(token, failure: .verify, toast: Self.couldNotTurnOn)
        }
        if var journal = LidJournalStore.read(), journal.token == token {
            journal.pid = pid
            journal.instanceID = instance
            LidJournalStore.write(journal)
        }
        beacon?.watch(pid: pid, instance: instance)
        for poll in 1...Self.verifyPolls {
            try? await Task.sleep(nanoseconds: Self.verifyPollNanoseconds)
            guard pending?.token == token else { return }   // superseded meanwhile
            if LidSystem.kernelSleepDisabled() == true {
                turnedOn(token, pid: pid)
                return
            }
            if poll == Self.slowVerifyPolls { context?.host.toasts.show(L("Turning on lid-closed mode…")) }
        }
        abandon(token, failure: .verify, toast: Self.couldNotTurnOn)
    }

    private func turnedOn(_ token: String, pid: Int32) {
        guard let p = pending, p.token == token, let ctx = context else { return }
        pending = nil
        let now = AwakeModule.clockNow()
        active = Active(token: token, pid: pid, floor: p.floor, capStart: now.continuous, sessionID: p.sessionID)
        set(.on(token: token, pid: pid, until: AwakeLidPolicy.until(sessionEnd: nil, capStart: now.continuous)))
        ctx.runtime.lastLidEnd = nil
        EventLog.shared.record(AwakeLogEvent.lidOn)
        switch p.request {
        case .add:
            guard let id = p.sessionID, ctx.sessions.manual?.id == id else { return end(.sessionEnded) }
            ctx.sessions.setLidRequested(true, for: id)
        case .preset, .custom:
            let replacing: Bool
            switch ctx.runtime.governing {
            case .manual, .trigger: replacing = true
            case .holds, .inactive: replacing = false
            }
            startingOwnSession = true
            let result = ctx.sessions.startWithLid(p.request, source: p.source)
            startingOwnSession = false
            switch result {
            case .success(let s):
                active?.sessionID = s.id
                if replacing { ctx.host.toasts.show(L("Replaced the running session.")) }
            case .failure:
                // The session's own refusal toast shows; the mode goes straight to stopping.
                return end(.sessionEnded)
            }
        }
        updateUntil()
        announce(L("Keeping your Mac awake with the lid closed."))
        observeScreens()
        ctx.sessions.arbitrate()
        maySleepDisplay()
        // 7. Five seconds later: an app that turned sleep back on at once (it reads 0 twice) ends the mode.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.recheckNanoseconds)
            guard let self, self.active?.token == token else { return }
            guard LidSystem.kernelSleepDisabled() == false else { return }
            try? await Task.sleep(nanoseconds: Self.verifyPollNanoseconds)
            guard self.active?.token == token, LidSystem.kernelSleepDisabled() == false else { return }
            self.end(.otherApp)
        }
    }

    /// Sleep was already off (someone else's): an idle request still starts its session, without the mode.
    private func startWithoutMode(_ p: Pending) {
        guard let ctx = context else { return }
        switch p.request {
        case .add: break
        case .preset, .custom:
            startingOwnSession = true
            _ = ctx.sessions.startWithLid(p.request, source: p.source, lid: false)
            startingOwnSession = false
        }
    }

    /// Every exit from `authorizing` or `verifying` other than into `on` (B3.0): the stop file, the heartbeat stopped,
    /// the journal kept until the kernel reads 0 (still 1 after 30 s: the leftover rows); one toast at most.
    private func abandon(_ token: String, failure: AwakeLidFailStage?, toast: String?) {
        guard let p = pending, p.token == token else { return }
        pending = nil
        // A stop file only matters once osascript may run, which needs the beacon first.
        if let dir = beacon?.directory { LidSystem.requestStop(dir: dir, token: token) }
        tearDown()
        if let recovery = context?.host.lidRecovery {
            recovery.watch(token: token, seconds: Self.abandonWaitSeconds)
        } else if LidSystem.kernelSleepDisabled() == false {
            LidJournalStore.remove(token: token)
        }
        if let failure {
            EventLog.shared.record(AwakeLogEvent.lidFailed(failure))
            set(.failed(failure))
        }
        if let toast { context?.host.toasts.show(toast) }
        set(.off)
    }

    /// A manual start or Turn Off while an idle start is pending supersedes it, silently (B3.0).
    private func supersede() {
        guard let p = pending else { return }
        admin?.interrupt()
        abandon(p.token, failure: nil, toast: nil)
    }

    // MARK: While on (B3.3)

    private func tick(_ token: String, _ t: LidTick) {
        guard let a = active, a.token == token else { return }
        if t.watchdogGone == true {
            end(.watchdogLost, leftover: t.sleepDisabled != false)
            return
        }
        if t.sleepDisabled == false {
            zeroReads += 1
            if zeroReads >= 2 { return end(.otherApp) }
        } else {
            zeroReads = 0
        }
        let now = AwakeModule.clockNow().continuous
        if now >= a.capStart + Double(LidWatchdog.capSeconds) { return end(.cap) }
        if !capWarned, case .on(_, _, let until) = mode,
           AwakeLidPolicy.capWarningDue(until: until, sessionEnd: sessionEnd(), now: now) {
            capWarned = true
            context?.host.toasts.show(L("Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep."))
        }
        maySleepDisplay()
    }

    /// Battery at or below the floor while discharging, or `serious` heat: the mode ends first (B3.3), then the
    /// lid-shut rule; the session's own guards follow in SessionController.
    private func powerChanged() {
        guard let a = active, let facts = context?.power.facts else { return }
        if facts.discharging, let percent = facts.percent, percent <= a.floor {
            end(.battery)
        } else if facts.thermal >= .serious {
            end(.heat)
        }
    }

    private func systemEvent(_ event: SystemEvent) {
        guard let a = active else { return }
        switch event {
        case .didWake:
            // Sleep is blocked while on; a wake anyway re-reads everything now.
            if let beacon { tick(a.token, beacon.read()) }
        case .lidChanged, .screensDidWake:
            maySleepDisplay()
        default:
            break
        }
    }

    /// The governing session's continuous end (nil: none, or no session yet).
    private func sessionEnd() -> Double? {
        guard let ctx = context, let id = active?.sessionID, let s = ctx.sessions.manual, s.id == id else { return nil }
        return AwakeArbiter.sessionEnd(.manual(s), now: AwakeModule.clockNow())
    }

    /// `until` = the earlier of the session's end and capStart + 24 h (B2 "keep" recomputes it).
    private func updateUntil() {
        guard let a = active else { return }
        set(.on(token: a.token, pid: a.pid, until: AwakeLidPolicy.until(sessionEnd: sessionEnd(), capStart: a.capStart)))
    }

    // MARK: Display while the lid is shut (B3.3)

    /// `pmset displaysleepnow` as the user, at most every 10 s, while `lidShut` and the built-in panel isn't asleep
    /// (offline counts as unknown and still runs). Single flight in the spawner and here.
    private func maySleepDisplay() {
        guard lidShut, !displaySleepRunning, let spawner = context?.host.spawner else { return }
        let now = AwakeModule.clockNow().continuous
        if let last = lastDisplaySleep, now - last < Self.displaySleepIntervalSeconds { return }
        if Self.displays().builtInAsleep == true { return }
        lastDisplaySleep = now
        displaySleepRunning = true
        Task { @MainActor [weak self] in
            do {
                _ = try await spawner.spawnTool(LidWatchdog.displaySleepArgv) { [weak self] _ in
                    self?.displaySleepRunning = false
                }
            } catch {
                self?.displaySleepRunning = false
            }
        }
    }

    /// Any online display that isn't built in, and whether the built-in one sleeps (nil: not online).
    private static func displays() -> (external: Bool, builtInAsleep: Bool?) {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return (false, nil) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return (false, nil) }
        var external = false
        var asleep: Bool?
        for id in ids.prefix(Int(count)) {
            if CGDisplayIsBuiltin(id) != 0 { asleep = CGDisplayIsAsleep(id) != 0 } else { external = true }
        }
        return (external, asleep)
    }

    private func observeScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.context?.sessions.arbitrate()
                self?.maySleepDisplay()
            }
        }
    }

    // MARK: Session events (SessionController; the N19 gate decides)

    /// Before any manual start that isn't this controller's own: a pending idle start is superseded.
    func manualStartWillBegin() {
        guard !startingOwnSession, let p = pending, p.request != .add else { return }
        supersede()
    }

    /// Turn Off (whatever governs): a pending idle start is superseded; a running mode ends with its session.
    func turnOffWillBegin() {
        guard let p = pending, p.request != .add else { return }
        supersede()
    }

    /// The running session `old` is being replaced by a start from `source`. True: the mode carries over to the new
    /// session (a menu, or a Settings start that passed the focus guard; the watchdog is untouched).
    func replacing(_ old: AwakeSession, by source: AwakeSessionSource) -> Bool {
        guard !startingOwnSession, let a = active, a.sessionID == old.id else { return false }
        guard AwakeLidGate.decide(source: source, mayStart: true, event: .replaced(by: source)) == .keep else {
            return false
        }
        keepAcross = old.id
        return true
    }

    /// The new session of a kept replacement.
    func sessionStarted(_ session: AwakeSession) {
        guard keepAcross != nil, active != nil, session.lidRequested else { return }
        keepAcross = nil
        active?.sessionID = session.id
        updateUntil()
    }

    /// The manual session ended (SessionController.finishManual).
    func sessionEnded(_ session: AwakeSession, reason: AwakeEndReason) {
        if let p = pending, p.sessionID == session.id { supersede() }
        guard let a = active, a.sessionID == session.id else { return }
        if keepAcross == session.id { return }
        end(reason == .replaced ? .replaced : .sessionEnded)
    }

    /// The session's end moved (Add Time): `until` follows.
    func sessionChanged() {
        if active != nil { updateUntil() }
    }

    /// A rule or the holds took over from the manual session (B2: end).
    func takenOver() {
        if active != nil { end(.replaced) }
    }

    /// The feature turned off, or its kill switch applies (B2: end).
    func featureOff() {
        supersede()
        if active != nil { end(.featureOff) }
    }

    // MARK: Ending (B3.3 "Turning off")

    private func end(_ reason: AwakeLidEnd, leftover: Bool = false) {
        guard let a = active, let ctx = context else { return }
        active = nil
        let rt = ctx.runtime
        let shut = rt.lidClosed == true
        if let dir = beacon?.directory { LidSystem.requestStop(dir: dir, token: a.token) }
        tearDown()
        set(.stopping(token: a.token))
        EventLog.shared.record(AwakeLogEvent.lidOff(reason))
        let quitting = reason == .quit || reason == .moduleStopped || reason == .safeMode
        // A session SessionController is ending or replacing re-plans after this returns; never re-plan in the middle
        // of its own change (or while the module stops).
        let sessionsOwnEnd = reason == .sessionEnded || reason == .replaced
        if !quitting, let id = a.sessionID { ctx.sessions.setLidRequested(false, for: id, arbitrate: !sessionsOwnEnd) }
        switch reason {
        case .cap, .battery, .heat, .otherApp, .watchdogLost:
            rt.lastLidEnd = AwakeLastLidEnd(reason: reason, at: Date())
        case .user, .sessionEnded, .replaced, .quit, .safeMode, .featureOff, .moduleStopped:
            break
        }
        if !quitting {
            switch reason {
            case .battery: ctx.host.toasts.show(L("Lid-closed mode turned off at \(a.floor)% battery."))
            case .heat: ctx.host.toasts.show(L("Lid-closed mode turned off because your Mac got hot."))
            case .otherApp: ctx.host.toasts.show(L("Another app turned sleep back on, so lid-closed mode stopped."))
            default: break
            }
            announce(L("Lid-closed mode turned off."))
            if !sessionsOwnEnd, let id = a.sessionID, ctx.sessions.manual?.id == id,
               AwakeLidPolicy.endsSession(lidShut: shut, lidWillSleep: rt.lidWillSleep, reason: reason) {
                ctx.sessions.endLidSession(id)
            } else if reason == .cap {
                ctx.host.toasts.show(L("Lid-closed mode turned off after 24 hours. Awake is still on; your Mac sleeps if you close the lid."))
            }
            if !sessionsOwnEnd { ctx.sessions.arbitrate() }
        }
        let token = a.token
        guard let recovery = ctx.host.lidRecovery else { return set(.off) }
        if leftover {
            // The watchdog is gone and sleep is still off: nobody will turn it back on.
            recovery.markLeftover()
            set(.off)
        } else if quitting {
            recovery.watch(token: token, seconds: Self.abandonWaitSeconds)
            set(.off)
        } else {
            recovery.watch(token: token, seconds: Self.stopWaitSeconds) { [weak self] _ in
                guard let self, self.mode.token == token else { return }
                self.set(.off)
            }
        }
    }

    // MARK: Helpers

    /// The heartbeat, the emergency action, the screen observer and App Nap's hold go; nothing is written.
    private func tearDown() {
        beacon?.stop()
        beacon = nil
        if let emergency { EmergencyActions.shared.remove(emergency) }
        emergency = nil
        stopPath = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        lastDisplaySleep = nil
        zeroReads = 0
    }

    /// B3.0: App Nap must not starve the heartbeat while the mode isn't off.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Snaptic lid-closed mode")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    static let couldNotTurnOn = L("Snaptic couldn’t turn on lid-closed mode. Try again.")
    static let alreadyOff = L("Sleep is already turned off for this Mac by another app or command, so it stays awake with the lid closed.")
}
