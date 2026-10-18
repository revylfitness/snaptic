import AppKit
import Combine
import SnapticKit

// The app side of the display guard (owner: B). PLAN §4.5, R5.2: spawned on demand through
// HelperSpawner, JSON lines over HelperPipeWriter / LineSplitter, heartbeat from a background
// timer using HostHeartbeat.mainAgeMillis(). Acks within 1 s or the caller refuses the change.
// The parent alone ends the guard: `shutdown` when nothing is armed, else EOF (so the guard
// undoes any long-armed state when the module stops or the app quits).

@MainActor final class DisplayGuardClient: DisplayServiceLifecycle, DiagnosticsContributor {
    static var serviceID: DisplayServiceID { .guardProcess }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    init() {}

    private var handle: HelperHandle?
    private var ready = false
    private(set) var canMonitorPanel = false
    private var nextID: UInt64 = 1
    private var acks: [UInt64: CheckedContinuation<Bool, Never>] = [:]
    /// Each waiter has its own timeout (FIXES-R1 B5): an old waiter's timer never resolves a
    /// newer waiter of a freshly spawned guard.
    private var readyWaiters: [UInt64: CheckedContinuation<Bool, Never>] = [:]
    private var waiterSerial: UInt64 = 0
    private var timedOutWaiters: Set<UInt64> = []
    /// Waiting (asynchronously) for HelperSpawner's identity before the first spawn.
    private var starting = false
    /// Trials armed in the guard (keeps App Nap away while any exist).
    private var armedTrials: Set<UInt64> = []
    private var activity: NSObjectProtocol?
    private var heartbeat: DispatchSourceTimer?
    private var active = false
    private var spawnTimes: [Double] = []
    private(set) var lastFailure: String?

    // State re-sent to a respawned guard.
    private var longUndo: [UndoOp] = []
    private var longColorSync = false
    private var impairment = (dim: false, overlay: false)
    private var classes: [GuardDisplayClass] = []

    /// The guard reverted a trial on its own (deadline or hang): (trial id, applied, skipped).
    var onReverted: (@MainActor (UInt64?, Int, Int) -> Void)?
    /// The guard died or became unreachable.
    var onLost: (@MainActor () -> Void)?

    var isAlive: Bool { handle != nil && ready }
    var pid: Int32? { handle?.pid }
    /// Long-armed state exists but no guard protects it ("Unprotected — restart Snaptic").
    var isUnprotected: Bool { !isAlive && (!longUndo.isEmpty || longColorSync || impairment.dim || impairment.overlay) }
    var hasLongState: Bool { !longUndo.isEmpty || longColorSync }

    // MARK: Lifecycle

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        context.diagnostics.register(self, section: L("Safety helper"), lifetime: lifetime)
    }

    func deactivate() {
        guard active else { return }
        active = false
        let hadLong = hasLongState
        longUndo = []
        longColorSync = false
        impairment = (dim: false, overlay: false)
        classes = []
        armedTrials = []
        terminate(sendShutdown: !hadLong)
        updateActivity()
        context = nil
    }

    // MARK: Process

    /// Spawns the guard if needed and waits for `ready` (2 s per waiter). The code identity
    /// HelperSpawner checks children against is computed off main; until it exists we wait
    /// asynchronously instead of computing it here (FIXES-R1 B5).
    func ensureRunning() async -> Bool {
        if isAlive { return true }
        guard active, let ctx = context else { return false }
        if handle == nil && !starting {
            if !ctx.helpers.isReady && ctx.helpers.unavailable == nil {
                starting = true
                ctx.helpers.prepare()
                let deadline = SessionGate.uptime() + Self.prepareWaitSeconds
                while active, !ctx.helpers.isReady, ctx.helpers.unavailable == nil, SessionGate.uptime() < deadline {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                starting = false
                guard active, context != nil else {
                    resolveReadyWaiters(false)
                    return false
                }
                if isAlive { return true }
                guard ctx.helpers.isReady else {
                    lastFailure = ctx.helpers.unavailable ?? L("The safety helper is still starting")
                    resolveReadyWaiters(false)
                    return false
                }
            }
        }
        if handle == nil && !starting {
            let now = SessionGate.uptime()
            spawnTimes = spawnTimes.filter { now - $0 < 600 }
            guard spawnTimes.count < 3 else {
                lastFailure = L("The safety helper keeps stopping")
                return false
            }
            spawnTimes.append(now)
            let dir = JournalFiles.defaultDirectory() ?? ""
            // The spawner verifies the suspended child off main; `starting` makes concurrent
            // callers wait for `ready` instead of spawning a second guard meanwhile.
            starting = true
            let spawned: HelperHandle
            do {
                spawned = try await ctx.helpers.spawn(.displayGuard,
                                                      arguments: ["--protocol", String(GuardProtocol.version), "--journal-dir", dir],
                                                      onLine: { [weak self] line in self?.receive(line) },
                                                      onExit: { [weak self] status in self?.exited(status) })
            } catch {
                starting = false
                lastFailure = (error as? HelperSpawnError).map { "\($0)" } ?? L("Couldn't start the safety helper")
                EventLog.shared.record(.guardProcess, "Guard failed to start")
                resolveReadyWaiters(false)
                return false
            }
            starting = false
            // Stopped (or the child already died) while it was being verified.
            guard active, context === ctx, !spawned.isReaped else {
                spawned.terminate()
                if active { lastFailure = L("Couldn't start the safety helper") }
                resolveReadyWaiters(false)
                return false
            }
            handle = spawned
            ready = false
            send(.hello(protocolVersion: GuardProtocol.version, build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"))
            startHeartbeat()
        }
        if isAlive { return true }
        waiterSerial &+= 1
        let token = waiterSerial
        let timeout = GuardProtocol.ackTimeoutSeconds * 2 + (starting ? Self.prepareWaitSeconds : 0)
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            readyWaiters[token] = c
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let mine = self.readyWaiters.removeValue(forKey: token) else { return }
                    if !self.ready { self.timedOutWaiters.insert(token) }
                    mine.resume(returning: self.ready)
                }
            }
        }
        let timedOut = timedOutWaiters.remove(token) != nil
        if ok {
            // Restore what a previous guard protected.
            if hasLongState { _ = await setLongAndWait(longUndo, restoreColorSync: longColorSync) }
            send(.impairment(dimToBlack: impairment.dim, overlayBelowFloor: impairment.overlay))
            if !classes.isEmpty { send(.classification(classes)) }
        } else if timedOut && handle != nil && !ready {
            lastFailure = L("The safety helper didn't answer")
            terminate(sendShutdown: false)
        }
        return ok
    }

    static let prepareWaitSeconds = 5.0

    private func resolveReadyWaiters(_ ok: Bool) {
        let list = readyWaiters
        readyWaiters = [:]
        list.values.forEach { $0.resume(returning: ok) }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        guard let writer = handle?.writer else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "app.snaptic.guard-heartbeat", qos: .userInitiated))
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        t.setEventHandler {
            let age = HostHeartbeat.shared.mainAgeMillis()
            if let data = GuardProtocol.encode(.heartbeat(mainAgeMillis: age)) { writer.send(data, isHeartbeat: true) }
        }
        t.resume()
        heartbeat = t
    }

    /// Never blocks main (FIXES-R1 B5): `close()` drains queued lines on the writer's own
    /// queue before closing. If the app exits before they're written, the guard sees EOF,
    /// which undoes exactly what `shutdown` would have left alone (nothing armed) or what
    /// it must undo anyway (long-armed state), and CAS makes any repeated undo a no-op.
    private func terminate(sendShutdown: Bool) {
        heartbeat?.cancel()
        heartbeat = nil
        if let h = handle {
            if sendShutdown { send(.shutdown) }
            h.writer?.close()
        }
        handle = nil
        ready = false
        armedTrials = []
        failPending()
        updateActivity()
    }

    private func exited(_ status: Int32) {
        let wasAlive = isAlive
        heartbeat?.cancel()
        heartbeat = nil
        handle = nil
        ready = false
        armedTrials = []
        failPending()
        updateActivity()
        if active {
            EventLog.shared.record(.guardProcess, "Guard exited (\(status))")
            if wasAlive { onLost?() }
        }
    }

    private func failPending() {
        let pending = acks
        acks = [:]
        pending.values.forEach { $0.resume(returning: false) }
        resolveReadyWaiters(false)
    }

    // MARK: Messages

    private func send(_ m: GuardMessage) {
        guard let writer = handle?.writer, let data = GuardProtocol.encode(m) else { return }
        writer.send(data)
    }

    private func receive(_ line: Data) {
        guard let reply = GuardProtocol.decodeReply(line) else { return }
        switch reply {
        case .ready(let version, let mp):
            guard version == GuardProtocol.version else {
                lastFailure = L("Restart Snaptic to finish updating")
                terminate(sendShutdown: true)
                return
            }
            ready = true
            canMonitorPanel = mp
            lastFailure = nil
            resolveReadyWaiters(true)
        case .ack(let id):
            acks.removeValue(forKey: id)?.resume(returning: true)
        case .reverted(let trial, let applied, let skipped):
            if let trial { armedTrials.remove(trial) }
            updateActivity()
            onReverted?(trial, applied, skipped)
        case .failed:
            EventLog.shared.record(.guardProcess, "Guard reported a protocol error")
        }
    }

    private func sendAndWait(_ make: (UInt64) -> GuardMessage) async -> Bool {
        guard isAlive else { return false }
        let id = nextID
        nextID &+= 1
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            acks[id] = c
            send(make(id))
            DispatchQueue.main.asyncAfter(deadline: .now() + GuardProtocol.ackTimeoutSeconds) { [weak self] in
                MainActor.assumeIsolated { self?.acks.removeValue(forKey: id)?.resume(returning: false) }
            }
        }
    }

    /// Fresh id for a trial.
    func makeTrialID() -> UInt64 {
        let id = nextID
        nextID &+= 1
        return id
    }

    func armTrial(_ id: UInt64, undo: [UndoOp], deadlineSeconds: Double) async -> Bool {
        guard await ensureRunning() else { return false }
        armedTrials.insert(id)
        updateActivity()
        let ok = await sendAndWait { _ in .armTrial(id: id, undo: undo, deadlineSeconds: deadlineSeconds) }
        if !ok {
            armedTrials.remove(id)
            updateActivity()
        }
        return ok
    }

    /// The trial's deadline becomes at least now + `seconds` (GuardProtocol.extendedDeadline).
    func extend(_ id: UInt64, seconds: Double) {
        send(.extend(id: id, seconds: min(max(seconds, 0), GuardProtocol.maxExtendSeconds)))
    }
    func commitIntent(_ id: UInt64) { send(.commitIntent(id: id)) }
    func commitIntentAndWait(_ id: UInt64) async -> Bool { await sendAndWait { _ in .commitIntent(id: id) } }
    func commit(_ id: UInt64) {
        armedTrials.remove(id)
        updateActivity()
        send(.commit(id: id))
    }
    func disarm(_ id: UInt64) {
        armedTrials.remove(id)
        updateActivity()
        send(.disarm(id: id))
    }

    /// Replaces the long-armed set (fire and forget; the state is kept for respawns).
    func setLong(_ undo: [UndoOp], restoreColorSync: Bool) {
        longUndo = undo
        longColorSync = restoreColorSync
        updateActivity()
        guard isAlive else { return }
        let id = nextID
        nextID &+= 1
        send(.long(id: id, undo: undo, restoreColorSync: restoreColorSync))
    }

    /// Like setLong, but waits for the ack (restore transactions, PLAN §4.3 step 5).
    func setLongAndWait(_ undo: [UndoOp], restoreColorSync: Bool) async -> Bool {
        longUndo = undo
        longColorSync = restoreColorSync
        updateActivity()
        if undo.isEmpty && !restoreColorSync && !isAlive { return true }
        guard await ensureRunning() else { return false }
        return await sendAndWait { id in .long(id: id, undo: undo, restoreColorSync: restoreColorSync) }
    }

    /// Dim states that let the guard stop a hung app after 30 s.
    func setImpairment(dimToBlack: Bool, overlayBelowFloor: Bool) {
        guard impairment.dim != dimToBlack || impairment.overlay != overlayBelowFloor else { return }
        impairment = (dim: dimToBlack, overlay: overlayBelowFloor)
        updateActivity()
        send(.impairment(dimToBlack: dimToBlack, overlayBelowFloor: overlayBelowFloor))
    }

    /// FIXES-R1 B5: while a trial or a long-armed/impairing state exists, hold an activity so
    /// App Nap can't starve the main thread and the heartbeat (the guard would think we hung).
    private func updateActivity() {
        let needed = active && (!armedTrials.isEmpty || hasLongState || impairment.dim || impairment.overlay)
        if needed && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Snaptic display safety")
        } else if !needed, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    /// Announces a main-thread stall (CG configure); capped at 10 s by the guard.
    func busy(seconds: Double) { send(.busy(seconds: seconds)) }

    func classification(_ classes: [GuardDisplayClass]) {
        guard classes != self.classes else { return }
        self.classes = classes
        send(.classification(classes))
    }

    func diagnostics() -> [(String, String)] {
        var rows: [(String, String)] = [("Guard", isAlive ? "running" : "not running")]
        if let pid { rows.append(("Guard pid", "\(pid)")) }
        rows.append(("MonitorPanel in guard", canMonitorPanel ? "yes" : "no"))
        rows.append(("Long-armed ops", "\(longUndo.count)\(longColorSync ? " + ColorSync" : "")"))
        rows.append(("Armed trials", "\(armedTrials.count)"))
        rows.append(("App Nap held off", activity == nil ? "no" : "yes"))
        if isUnprotected { rows.append(("State", "Unprotected — restart Snaptic")) }
        if let f = lastFailure { rows.append(("Last problem", f)) }
        return rows
    }
}
