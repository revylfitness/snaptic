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
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []
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
        terminate(sendShutdown: !hadLong)
        context = nil
    }

    // MARK: Process

    /// Spawns the guard if needed and waits for `ready` (1 s).
    func ensureRunning() async -> Bool {
        if isAlive { return true }
        guard active, let ctx = context else { return false }
        if handle == nil {
            let now = SessionGate.uptime()
            spawnTimes = spawnTimes.filter { now - $0 < 600 }
            guard spawnTimes.count < 3 else {
                lastFailure = L("The safety helper keeps stopping")
                return false
            }
            spawnTimes.append(now)
            let dir = JournalFiles.defaultDirectory() ?? ""
            do {
                handle = try ctx.helpers.spawn(.displayGuard,
                                               arguments: ["--protocol", String(GuardProtocol.version), "--journal-dir", dir],
                                               onLine: { [weak self] line in self?.receive(line) },
                                               onExit: { [weak self] status in self?.exited(status) })
            } catch {
                lastFailure = (error as? HelperSpawnError).map { "\($0)" } ?? L("Couldn't start the safety helper")
                EventLog.shared.record(.guardProcess, "Guard failed to start")
                return false
            }
            ready = false
            send(.hello(protocolVersion: GuardProtocol.version, build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"))
            startHeartbeat()
        }
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            readyWaiters.append(c)
            DispatchQueue.main.asyncAfter(deadline: .now() + GuardProtocol.ackTimeoutSeconds * 2) { [weak self] in
                MainActor.assumeIsolated { self?.resolveReadyWaiters(self?.ready ?? false) }
            }
        }
        if ok {
            // Restore what a previous guard protected.
            if hasLongState { _ = await setLongAndWait(longUndo, restoreColorSync: longColorSync) }
            send(.impairment(dimToBlack: impairment.dim, overlayBelowFloor: impairment.overlay))
            if !classes.isEmpty { send(.classification(classes)) }
        } else if handle != nil && !ready {
            lastFailure = L("The safety helper didn't answer")
            terminate(sendShutdown: false)
        }
        return ok
    }

    private func resolveReadyWaiters(_ ok: Bool) {
        let list = readyWaiters
        readyWaiters = []
        list.forEach { $0.resume(returning: ok) }
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

    private func terminate(sendShutdown: Bool) {
        heartbeat?.cancel()
        heartbeat = nil
        if let h = handle {
            if sendShutdown { send(.shutdown) }
            _ = h.writer?.flush(timeout: .milliseconds(500))
            h.writer?.close()
        }
        handle = nil
        ready = false
        failPending()
    }

    private func exited(_ status: Int32) {
        let wasAlive = isAlive
        heartbeat?.cancel()
        heartbeat = nil
        handle = nil
        ready = false
        failPending()
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
        return await sendAndWait { _ in .armTrial(id: id, undo: undo, deadlineSeconds: deadlineSeconds) }
    }

    func extend(_ id: UInt64, seconds: Double) { send(.extend(id: id, seconds: seconds)) }
    func commitIntent(_ id: UInt64) { send(.commitIntent(id: id)) }
    func commitIntentAndWait(_ id: UInt64) async -> Bool { await sendAndWait { _ in .commitIntent(id: id) } }
    func commit(_ id: UInt64) { send(.commit(id: id)) }
    func disarm(_ id: UInt64) { send(.disarm(id: id)) }

    /// Replaces the long-armed set (fire and forget; the state is kept for respawns).
    func setLong(_ undo: [UndoOp], restoreColorSync: Bool) {
        longUndo = undo
        longColorSync = restoreColorSync
        guard isAlive else { return }
        let id = nextID
        nextID &+= 1
        send(.long(id: id, undo: undo, restoreColorSync: restoreColorSync))
    }

    /// Like setLong, but waits for the ack (restore transactions, PLAN §4.3 step 5).
    func setLongAndWait(_ undo: [UndoOp], restoreColorSync: Bool) async -> Bool {
        longUndo = undo
        longColorSync = restoreColorSync
        if undo.isEmpty && !restoreColorSync && !isAlive { return true }
        guard await ensureRunning() else { return false }
        return await sendAndWait { id in .long(id: id, undo: undo, restoreColorSync: restoreColorSync) }
    }

    /// Dim states that let the guard stop a hung app after 30 s.
    func setImpairment(dimToBlack: Bool, overlayBelowFloor: Bool) {
        guard impairment.dim != dimToBlack || impairment.overlay != overlayBelowFloor else { return }
        impairment = (dim: dimToBlack, overlay: overlayBelowFloor)
        send(.impairment(dimToBlack: dimToBlack, overlayBelowFloor: overlayBelowFloor))
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
        if isUnprotected { rows.append(("State", "Unprotected — restart Snaptic")) }
        if let f = lastFailure { rows.append(("Last problem", f)) }
        return rows
    }
}
