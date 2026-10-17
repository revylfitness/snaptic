import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt
import SnapticKit
import SnapticShims

// The display guard helper (owner: B). PLAN §4.5 + R5.2/R5.3: a separate process that
// reverts trials by their deadline, undoes long-armed states when the app dies, handles
// hangs that impair visibility, and restores a visible display when the app can't. It never
// touches AppKit, NSWorkspace, UserDefaults or TCC (lint rule 9); main runs CFRunLoopRun.

enum DisplayGuardMain {
    static func run(_ arguments: [String]) -> Never {
        var core: GuardCore?
        let args = HelperPrologue.run(arguments, kind: .displayGuard, onLine: { line in
            MainActor.assumeIsolated { core?.receive(line) }
        }, onEOF: {
            MainActor.assumeIsolated {
                if let core { core.parentDied() } else { exit(0) }
            }
        })
        HelperPrologue.requireProtocol(args, GuardProtocol.version)
        MainActor.assumeIsolated {
            core = GuardCore(parent: args.parent, journalDir: args.journalDir)
            core?.start()
        }
        CFRunLoopRun()
        exit(0)
    }
}

@MainActor final class GuardCore {
    private struct Trial {
        var undo: [UndoOp]
        var deadline: Double
        var committing: Bool
    }

    private let parent: pid_t
    private let parentStartTime: UInt64
    private let files: JournalFiles?
    private let reader = LayoutReader()
    private let functions = CGConfigFunctions.resolvedForRestore()
    private var canMonitorPanel = false
    private var writer: HelperPipeWriter?

    private var trials: [UInt64: Trial] = [:]
    private var longUndo: [UndoOp] = []
    private var longColorSync = false
    private var dimImpairing = false
    private var classes: [GuardDisplayClass] = []
    private var hang = HangDetector()
    private var hangActed = false
    private var parentKilled = false
    private var noVisibleSince: Double?
    private var noVisibleActed = false
    private var lastReconfigure: Double = 0
    private var reverting = false
    private var queued: [GuardMessage] = []
    private var activity: NSObjectProtocol?
    private var timer: Timer?
    private var refcon: UnsafeMutableRawPointer?
    private var powerPort: io_connect_t = 0
    private var powerNotifier: io_object_t = 0
    private var powerNotifyPort: IONotificationPortRef?
    private var exiting = false

    init(parent: pid_t, journalDir: String?) {
        self.parent = parent
        parentStartTime = SNProcess.startTime(for: parent)
        files = (journalDir ?? JournalFiles.defaultDirectory()).map(JournalFiles.init(directory:))
    }

    func start() {
        let groups = PrivateSymbolResolver.verifyMonitorPanel()
        canMonitorPanel = groups.contains("rotation") && groups.contains("hdr")
        writer = HelperPipeWriter(duplicating: 1, onBroken: {})
        let p = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        if CGDisplayRegisterReconfigurationCallback(Self.reconfigure, p) == .success { refcon = p } else {
            Unmanaged<CallbackTarget<GuardCore>>.fromOpaque(p).release()
        }
        registerPower()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Messages

    func receive(_ line: Data) {
        guard let message = GuardProtocol.decodeMessage(line) else {
            reply(.failed("bad message"))
            return
        }
        if reverting {
            if queued.count < 256 { queued.append(message) }
            return
        }
        handle(message)
    }

    private func handle(_ message: GuardMessage) {
        let now = SessionGate.uptime()
        switch message {
        case .hello:
            reply(.ready(protocolVersion: GuardProtocol.version, canMonitorPanel: canMonitorPanel))
        case .armTrial(let id, let undo, let deadline):
            trials[id] = Trial(undo: undo, deadline: now + deadline, committing: false)
            updateActivity()
            reply(.ack(id: id))
        case .extend(let id, let seconds):
            if var t = trials[id], !t.committing {
                t.deadline = min(t.deadline + seconds, now + GuardProtocol.maxDeadlineSeconds)
                trials[id] = t
            }
            reply(.ack(id: id))
        case .commitIntent(let id):
            trials[id]?.committing = true
            reply(.ack(id: id))
        case .commit(let id), .disarm(let id):
            trials[id] = nil
            updateActivity()
            reply(.ack(id: id))
        case .long(let id, let undo, let colorSync):
            longUndo = undo
            longColorSync = colorSync
            updateActivity()
            reply(.ack(id: id))
        case .impairment(let dim, let overlay):
            dimImpairing = dim || overlay
        case .busy(let seconds):
            hang.busy(seconds: seconds, at: now)
        case .classification(let list):
            classes = list
        case .heartbeat(let age):
            hang.heartbeat(mainAgeMillis: age, at: now)
        case .shutdown:
            shutdown()
        }
    }

    private func reply(_ r: GuardReply) {
        guard let data = GuardProtocol.encode(r) else { return }
        writer?.send(data)
    }

    // MARK: Timer: deadlines, hangs, no visible display

    private func tick() {
        guard !reverting, !exiting else { return }
        guard SessionGate.readSession().onConsole else { return }      // off console: do nothing
        let now = SessionGate.uptime()

        // Trial deadlines (with or without a hung or long-armed parent).
        for (id, t) in trials where !t.committing && now >= t.deadline {
            revertTrial(id, reason: "deadline")
        }
        for (id, t) in trials where t.committing && now >= t.deadline + 60 { trials[id] = nil }

        // Hang: only armed trials and long-armed states that impair visibility (R5.2).
        let impairing = longUndo.contains { $0.stage == .enable } || longColorSync || dimImpairing
        if let hung = hang.hangSeconds(at: now), !trials.isEmpty || impairing {
            for (id, t) in trials where !t.committing { revertTrial(id, reason: "hang") }
            if impairing && !hangActed {
                hangActed = true
                EventLog.shared.record(.guardProcess, "Parent hung: restoring visibility")
                applyOps(longUndo.filter { $0.stage == .enable } + unmirrorOpsForDeadHosts())
                if longColorSync { CGDisplayRestoreColorSyncSettings() }
            }
            if hung >= GuardProtocol.killParentAfterSeconds, dimImpairing, !parentKilled,
               parentStartTime != 0, SNProcess.startTime(for: parent) == parentStartTime {
                parentKilled = true
                EventLog.shared.record(.guardProcess, "Parent hung with the screen dimmed: stopping it")
                kill(parent, SIGKILL)
            }
        } else if hang.hangSeconds(at: now) == nil {
            hangActed = false
        }

        // No visible display (R5.3): only while the parent's heartbeat is stale.
        let s = snapshot()
        if Invariants.visible(s).isEmpty && !s.entries.isEmpty {
            if noVisibleSince == nil { noVisibleSince = now }
            if !noVisibleActed, hang.isHeartbeatStale(at: now),
               now - (noVisibleSince ?? now) >= GuardProtocol.noVisiblePersistSeconds {
                noVisibleActed = true
                EventLog.shared.record(.guardProcess, "No visible display: re-enabling")
                applyOps(longUndo.filter { $0.stage == .enable })
                killOrphanedHosts(in: s)
            }
        } else {
            noVisibleSince = nil
            noVisibleActed = false
        }
    }

    /// The live layout with what the parent told us (Snaptic virtuals, headless).
    private func snapshot() -> LayoutSnapshot {
        var overlay = LayoutReader.Overlay()
        for c in classes where c.transport == .snapticVirtual {
            overlay.transports[c.id] = .snapticVirtual
            if c.weak { overlay.headless.insert(c.id) }
        }
        for c in classes where c.transport != .snapticVirtual { overlay.transports[c.id] = c.transport }
        return reader.read(overlay)
    }

    private func revertTrial(_ id: UInt64, reason: String) {
        guard let t = trials[id] else { return }
        trials[id] = nil
        let r = applyOps(t.undo)
        EventLog.shared.record(.guardProcess, "Trial reverted (\(reason)): \(r.applied) applied, \(r.skipped) skipped")
        reply(.reverted(trial: id, applied: r.applied, skipped: r.skipped))
        updateActivity()
    }

    @discardableResult
    private func applyOps(_ ops: [UndoOp]) -> (applied: Int, skipped: Int) {
        guard !ops.isEmpty else { return (0, 0) }
        reverting = true
        defer {
            reverting = false
            let pending = queued
            queued = []
            for m in pending { handle(m) }
        }
        let overlay = snapshotOverlay()
        return JournalApplier.apply(ops, reader: reader, overlay: overlay, functions: functions,
                                    canMonitorPanel: canMonitorPanel, settle: { [weak self] in self?.waitQuiet(cap: $0) })
    }

    private func snapshotOverlay() -> LayoutReader.Overlay {
        var o = LayoutReader.Overlay()
        for c in classes { o.transports[c.id] = c.transport }
        return o
    }

    /// Un-mirror ops (from the long set) whose Snaptic host has already died.
    private func unmirrorOpsForDeadHosts() -> [UndoOp] {
        let dead = Set(classes.filter { c in
            guard let pid = c.hostPID else { return false }
            return kill(pid, 0) == -1 && errno == ESRCH
        }.map(\.id))
        return longUndo.filter { op in
            guard op.stage == .unmirror, case .display(let src?) = op.expected else { return false }
            return dead.contains(src)
        }
    }

    /// Kills Snaptic hosts whose virtual no physical display mirrors (start-time checked).
    private func killOrphanedHosts(in s: LayoutSnapshot) {
        for c in classes where c.transport == .snapticVirtual && !c.weak {
            guard let pid = c.hostPID, let start = c.hostStartTime, pid > 1 else { continue }
            let mirrored = s.entries.contains { $0.mirrorOf == c.id && $0.isPhysical }
            guard !mirrored, SNProcess.startTime(for: pid) == start else { continue }
            kill(pid, SIGKILL)
            EventLog.shared.record(.guardProcess, "Stopped an orphaned virtual-display host")
        }
    }

    // MARK: Parent death

    func parentDied() {
        guard !exiting else { return }
        exiting = true
        timer?.invalidate()
        // Off console: wait until the user is back before touching displays.
        while !SessionGate.readSession().onConsole { _ = CFRunLoopRunInMode(.defaultMode, 1, false) }
        let claimed = JournalModel.claimedName(pid: getpid())
        let haveJournal = files?.claim(JournalModel.sessionFileName, as: claimed) ?? false
        let armed = trials.filter { !$0.value.committing }
        if !armed.isEmpty {
            waitQuiet(quiet: GuardProtocol.quiescenceQuietSeconds, cap: GuardProtocol.quiescenceCapSeconds)
            for (_, t) in armed.sorted(by: { $0.key > $1.key }) { applyOps(t.undo) }
            resolvePermanent(Set(armed.keys))
        }
        let longOps = longUndo.filter { $0.stage == .enable || $0.stage == .unmirror }
        if !longOps.isEmpty {
            waitQuiet(quiet: 1, cap: 4)
            applyOps(longOps)
        }
        if longColorSync { CGDisplayRestoreColorSyncSettings() }
        if haveJournal { files?.remove(claimed) }
        EventLog.shared.record(.guardProcess, "Parent exited; guard done")
        finishAndExit()
    }

    /// Removes reverted trials' MonitorPanel steps from permanent.json (the app is gone).
    private func resolvePermanent(_ ids: Set<UInt64>) {
        guard let files, let data = files.read(JournalModel.permanentFileName),
              var p = JournalModel.decodePermanent(data) else { return }
        for id in ids { p.resolve(trial: id) }
        if p.isEmpty { files.remove(JournalModel.permanentFileName) } else if let d = JournalModel.encode(p) {
            files.write(d, to: JournalModel.permanentFileName)
        }
    }

    private func shutdown() {
        exiting = true
        finishAndExit()
    }

    private func finishAndExit() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        if let p = refcon {
            CGDisplayRemoveReconfigurationCallback(Self.reconfigure, p)
            Unmanaged<CallbackTarget<GuardCore>>.fromOpaque(p).release()
            refcon = nil
        }
        _ = writer?.flush(timeout: .milliseconds(300))
        exit(0)
    }

    // MARK: Quiescence and power

    private static let reconfigure: CGDisplayReconfigurationCallBack = { _, _, refcon in
        guard let refcon else { return }
        let box = Unmanaged<CallbackTarget<GuardCore>>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { box.target?.lastReconfigure = SessionGate.uptime() }
    }

    /// Pumps the run loop until no reconfiguration for `quiet` seconds, at most `cap`.
    private func waitQuiet(quiet: Double = 1, cap: Double) {
        let start = SessionGate.uptime()
        while true {
            let now = SessionGate.uptime()
            if now - start >= cap { return }
            if now - start >= 0.3 && now - lastReconfigure >= quiet { return }
            _ = CFRunLoopRunInMode(.defaultMode, 0.1, false)
        }
    }

    private func updateActivity() {
        let armed = !trials.isEmpty || !longUndo.isEmpty || longColorSync
        if armed && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                            reason: "Snaptic display safety")
        } else if !armed, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    private static let powerCallback: IOServiceInterestCallback = { refcon, _, messageType, argument in
        guard let refcon else { return }
        let box = Unmanaged<CallbackTarget<GuardCore>>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { box.target?.power(messageType, argument) }
    }

    private func registerPower() {
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        var notifier: io_object_t = 0
        let port = IORegisterForSystemPower(box, &powerNotifyPort, Self.powerCallback, &notifier)
        guard port != 0, let notify = powerNotifyPort else {
            Unmanaged<CallbackTarget<GuardCore>>.fromOpaque(box).release()
            return
        }
        powerPort = port
        powerNotifier = notifier
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notify).takeUnretainedValue(), .commonModes)
    }

    private func power(_ message: natural_t, _ argument: UnsafeMutableRawPointer?) {
        switch message {
        case 0xE000_0270, 0xE000_0280:                  // kIOMessageCanSystemSleep, kIOMessageSystemWillSleep
            IOAllowPowerChange(powerPort, Int(bitPattern: argument))
        case 0xE000_0300, 0xE000_0320:                  // kIOMessageSystemHasPoweredOn, WillPowerOn
            hang.didWake(at: SessionGate.uptime())
        default:
            break
        }
    }
}
