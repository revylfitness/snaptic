import AppKit
import Combine
import SnapticKit

// The app side of the display guard (owner: B). PLAN §4.5, R5.2: spawned on demand through
// HelperSpawner, JSON lines over HelperPipeWriter / LineSplitter, heartbeat from a background
// timer using HostHeartbeat.mainAgeMillis(). Acks within 1 s or the caller refuses the change.
// The parent alone ends the guard: `shutdown` when nothing is armed, else EOF (so the guard
// undoes any long-armed state when the module stops or the app quits).
//
// FIXES-R2 N1/N2: every acknowledged request carries a fresh `seq` and waits in a Kit
// GuardAckTracker under exactly that seq (GuardLinkTests). Each spawned guard is a new
// generation: its lines and its exit are ignored once another guard (or none) took over.
//
// 0.3 §4.5: every change of what Settings shows (running, unprotected, long-armed, can revert rotation and HDR,
// the last problem) bumps `revision(.diagnostics)` once per main-queue turn; a change of the long-armed state also
// re-evaluates the panic shortcut (it stays registered while Snaptic holds such a state).

@MainActor final class DisplayGuardClient: DisplayServiceLifecycle, DiagnosticsContributor {
    static var serviceID: DisplayServiceID { .guardProcess }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?
    /// Kept after deactivate (it outlives module starts) so the last change still reaches open pages.
    private weak var runtime: DisplaysRuntimeState?

    init() {}

    private var handle: HelperHandle? { didSet { noteStatus() } }
    private var ready = false { didSet { noteStatus() } }
    private(set) var canMonitorPanel = false { didSet { noteStatus() } }
    /// Trial ids (a separate counter from request seqs, which the tracker owns).
    private var nextTrialID: UInt64 = 1
    /// Requests waiting for their ack, keyed by seq, per guard generation.
    private var acks = GuardAckTracker<CheckedContinuation<Bool, Never>>()
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
    private(set) var lastFailure: String? { didSet { noteStatus() } }
    /// The guard exited 65 or answered with another protocol version: Snaptic was replaced on
    /// disk. Never respawned until Snaptic restarts (FIXES-R3 5).
    private(set) var restartRequired = false { didSet { noteStatus() } }
    static var restartText: String { L("Restart Snaptic to finish updating.") }

    // State re-sent to a respawned guard.
    private var longUndo: [UndoOp] = [] { didSet { noteStatus() } }
    private var longColorSync = false { didSet { noteStatus() } }
    private var impairment = (dim: false, overlay: false) { didSet { noteStatus() } }
    /// What the pages last saw (0.3 §4.5).
    private var lastStatus: GuardStatus?
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
        runtime = context.runtime
        context.diagnostics.register(self, section: L("Safety helper"), lifetime: lifetime)
        noteStatus()
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
        terminate(sendShutdown: !hadLong, grace: hadLong ? Self.undoGraceSeconds : Self.shutdownGraceSeconds)
        updateActivity()
        noteStatus()
        context = nil
    }

    // MARK: Observability (0.3 §4.5)

    /// Everything Settings and the menu show about the guard.
    private struct GuardStatus: Equatable {
        let alive: Bool
        let unprotected: Bool
        let longArmed: Bool
        let canMonitorPanel: Bool
        let lastFailure: String?
        let restartRequired: Bool
    }

    private func noteStatus() {
        let now = GuardStatus(alive: isAlive, unprotected: isUnprotected, longArmed: hasLongState,
                              canMonitorPanel: canMonitorPanel, lastFailure: lastFailure, restartRequired: restartRequired)
        guard now != lastStatus else { return }
        let longChanged = now.longArmed != lastStatus?.longArmed
        lastStatus = now
        runtime?.revision(.diagnostics).bump()
        if longChanged { context?.panic.updateHotkey() }
    }

    // MARK: Process

    /// Spawns the guard if needed and waits for `ready` (2 s per waiter). The code identity
    /// HelperSpawner checks children against is computed off main; until it exists we wait
    /// asynchronously instead of computing it here (FIXES-R1 B5).
    func ensureRunning() async -> Bool {
        if isAlive { return true }
        guard active, let ctx = context else { return false }
        if restartRequired {
            lastFailure = Self.restartText
            return false
        }
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
                lastFailure = L("The safety helper keeps stopping. Restart Snaptic.")
                return false
            }
            spawnTimes.append(now)
            // FIXES-R3 6: no `--journal-dir ""` (the guard refuses an empty or relative path);
            // without a directory the flag is left out and the guard uses its own default.
            var arguments = ["--protocol", String(GuardProtocol.version)]
            if let dir = JournalFiles.defaultDirectory(), dir.hasPrefix("/") { arguments += ["--journal-dir", dir] }
            // A new generation before the spawn: this guard's lines and exit carry it, and
            // anything still waiting on an earlier guard fails now (N2).
            let generation = newGeneration()
            // `starting` makes concurrent callers wait for `ready` instead of spawning a
            // second guard while this one is being started (and verified).
            starting = true
            let spawned: HelperHandle
            do {
                spawned = try await ctx.helpers.spawn(.displayGuard,
                                                      arguments: arguments,
                                                      onLine: { [weak self] line in self?.receive(line, generation: generation) },
                                                      onExit: { [weak self] status in self?.exited(status, generation: generation) })
            } catch {
                starting = false
                lastFailure = Self.describe(error)
                EventLog.shared.record(.guardProcess, "Guard failed to start")
                resolveReadyWaiters(false)
                return false
            }
            starting = false
            // Stopped, or superseded, or the child already died while it was being started.
            guard active, context === ctx, acks.generation == generation, !spawned.isReaped else {
                spawned.terminate()
                if active { lastFailure = L("Couldn’t start the safety helper.") }
                // Exited before we took the handle: its exit was ignored, so read the status here.
                if let status = spawned.status, HelperExitStatus.isProtocolMismatch(status) { noteRestartRequired() }
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
            lastFailure = L("The safety helper didn’t answer.")
            terminate(sendShutdown: false, grace: Self.unresponsiveGraceSeconds)
        }
        return ok
    }

    /// How long a guard we stopped talking to may take to exit on its own before SIGKILL:
    /// after `shutdown` it exits at once; after EOF it may first undo long-armed state
    /// (quiescence ≤ 8 s + 4 s, then the applies); one that never answered gets a second.
    static let shutdownGraceSeconds = 3.0
    static let undoGraceSeconds = 25.0
    static let unresponsiveGraceSeconds = 1.0

    /// Readable text for a spawn failure (W9: never an enum dump).
    static func describe(_ error: Error) -> String {
        guard let e = error as? HelperSpawnError else { return L("Couldn’t start the safety helper.") }
        switch e {
        case .unavailable(let reason): return reason
        case .unsupportedKind: return L("Couldn’t start the safety helper.")
        case .pipe: return L("Couldn’t connect to the safety helper. Restart Snaptic.")
        case .spawnFailed: return L("macOS couldn’t start the safety helper. Restart Snaptic.")
        case .verificationFailed: return L("The safety helper failed a security check. Restart Snaptic.")
        case .refused(let r): return r.message
        }
    }

    /// Starts a new guard generation: requests waiting on the previous guard fail.
    private func newGeneration() -> UInt64 {
        for w in acks.startGeneration() { w.resume(returning: false) }
        return acks.generation
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
    /// N2: the old guard becomes a stale generation at once (its lines and exit are
    /// ignored) and is killed if it is still running after `grace` seconds.
    private func terminate(sendShutdown: Bool, grace: Double) {
        heartbeat?.cancel()
        heartbeat = nil
        if let h = handle {
            if sendShutdown { send(.shutdown) }
            h.writer?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + grace) {
                MainActor.assumeIsolated {
                    if !h.isReaped { h.terminate() }
                }
            }
        }
        handle = nil
        ready = false
        armedTrials = []
        _ = newGeneration()
        failPending()
        updateActivity()
    }

    private func exited(_ status: Int32, generation: UInt64) {
        // A guard we already let go of (N2): its exit must not tear down its successor.
        guard generation == acks.generation, handle != nil else { return }
        let wasAlive = isAlive
        heartbeat?.cancel()
        heartbeat = nil
        handle = nil
        ready = false
        armedTrials = []
        failPending()
        updateActivity()
        if HelperExitStatus.isProtocolMismatch(status) { noteRestartRequired() }
        if active {
            EventLog.shared.record(.guardProcess, "Guard exited (\(status))")
            if wasAlive { onLost?() }
        }
    }

    private func noteRestartRequired() {
        lastFailure = Self.restartText
        guard !restartRequired else { return }
        restartRequired = true
        EventLog.shared.record(.guardProcess, "Guard speaks another protocol: restart required")
    }

    private func failPending() {
        for w in acks.failAll() { w.resume(returning: false) }
        resolveReadyWaiters(false)
    }

    // MARK: Messages

    /// False when nothing went out: no guard, or the message is out of bounds or longer than
    /// one line the guard can read (FIXES-R3 7: refused here, never truncated there).
    @discardableResult
    private func send(_ m: GuardMessage) -> Bool {
        guard let writer = handle?.writer else { return false }
        guard let data = GuardProtocol.encode(m) else {
            EventLog.shared.record(.guardProcess, "Guard message refused: out of bounds or too large")
            return false
        }
        writer.send(data)
        return true
    }

    private func receive(_ line: Data, generation: UInt64) {
        // Lines from a guard we already let go of (N2) are ignored.
        guard generation == acks.generation, handle != nil, let reply = GuardProtocol.decodeReply(line) else { return }
        switch reply {
        case .ready(let version, let mp):
            guard version == GuardProtocol.version else {
                noteRestartRequired()
                terminate(sendShutdown: true, grace: Self.shutdownGraceSeconds)
                return
            }
            ready = true
            canMonitorPanel = mp
            lastFailure = nil
            resolveReadyWaiters(true)
        case .ack(let seq):
            acks.acknowledge(seq, from: generation)?.resume(returning: true)
        case .reverted(let trial, let applied, let skipped):
            if let trial { armedTrials.remove(trial) }
            updateActivity()
            onReverted?(trial, applied, skipped)
        case .failed:
            EventLog.shared.record(.guardProcess, "Guard reported a protocol error")
        }
    }

    /// Sends the request `make(seq)` builds and waits for `ack(seq)` from this guard, at most
    /// `GuardProtocol.ackTimeoutSeconds`. The waiter is keyed by the seq actually sent (N1).
    private func sendAndWait(_ make: (UInt64) -> GuardMessage) async -> Bool {
        guard isAlive else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let timeout = GuardProtocol.ackTimeoutSeconds
            let seq = acks.begin(c, at: SessionGate.uptime(), timeout: timeout)
            guard send(make(seq)) else {
                // Refused before sending: fail now rather than after the ack timeout.
                acks.timeOut(seq)?.resume(returning: false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                MainActor.assumeIsolated { self?.acks.timeOut(seq)?.resume(returning: false) }
            }
        }
    }

    /// Fresh id for a trial (never reused in this run).
    func makeTrialID() -> UInt64 {
        let id = nextTrialID
        nextTrialID &+= 1
        return id
    }

    func armTrial(_ id: UInt64, undo: [UndoOp], deadlineSeconds: Double) async -> Bool {
        guard await ensureRunning() else { return false }
        armedTrials.insert(id)
        updateActivity()
        let ok = await sendAndWait { .armTrial(id: id, seq: $0, undo: undo, deadlineSeconds: deadlineSeconds) }
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
    /// From the ack on, the guard no longer reverts the trial by deadline or hang.
    func commitIntentAndWait(_ id: UInt64) async -> Bool { await sendAndWait { .commitIntent(id: id, seq: $0) } }
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
        // Nobody waits for this ack; a fresh seq keeps it from answering anyone else.
        send(.long(seq: acks.nextSeq(), undo: undo, restoreColorSync: restoreColorSync))
    }

    /// Like setLong, but waits for the ack (restore transactions, PLAN §4.3 step 5).
    func setLongAndWait(_ undo: [UndoOp], restoreColorSync: Bool) async -> Bool {
        longUndo = undo
        longColorSync = restoreColorSync
        updateActivity()
        if undo.isEmpty && !restoreColorSync && !isAlive { return true }
        guard await ensureRunning() else { return false }
        return await sendAndWait { .long(seq: $0, undo: undo, restoreColorSync: restoreColorSync) }
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
        rows.append(("Requests awaiting ack", "\(acks.pendingCount)"))
        rows.append(("App Nap held off", activity == nil ? "no" : "yes"))
        if isUnprotected { rows.append(("State", "Unprotected — restart Snaptic")) }
        if let f = lastFailure { rows.append(("Last problem", f)) }
        if restartRequired { rows.append(("Respawn", "off until Snaptic restarts")) }
        return rows
    }
}
