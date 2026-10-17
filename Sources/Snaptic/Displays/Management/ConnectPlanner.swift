import AppKit
import SnapticKit

/// Runs `ConnectPlan` on launch, wake, reconfiguration and session resume (PLAN §4.11, R5.3).
/// Step 1 (visibility) runs at once, also in Safe Mode and while panic-latched. Steps 2–5
/// wait for 3 s of reconfiguration quiet (capped at 10 s), run in two phases (virtuals,
/// re-snapshot, the rest), are rate-limited per plan, and ignore the reconfigurations
/// their own execution causes.
@MainActor final class ConnectPlanner {
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?

    // The D controllers that supply inputs and execute steps. Settings pages reach the
    // running controllers through these (nil while a feature is off).
    private(set) weak var resolution: ResolutionController?
    private(set) weak var arrangement: ArrangementController?
    private(set) weak var panelProps: PanelPropsController?
    private(set) weak var power: PowerController?
    private(set) weak var protection: ProtectionController?
    private(set) weak var layouts: LayoutsController?
    private(set) weak var virtual: VirtualController?
    private(set) weak var smartHiDPI: SmartHiDPIController?

    private var quiet = QuietWindow()
    private var limiter = PlanRateLimiter()
    private var fullTimer: DispatchWorkItem?
    private var graceTimer: DispatchWorkItem?
    private var pendingTriggers: Set<ConnectTrigger> = []
    private var running = false
    private var rerunAfter = false
    private var visibilityRunning = false
    private var visibilityAgain = false
    private var suppressUntil: Double = 0
    private var userChanges = 0
    private var lastSetKey: DisplaySetKey?
    private var lastWakeOrUnlock: Double?
    private var prompted: Set<String> = []
    private var recapturePending = false

    // Diagnostics.
    private var runs = 0
    private var limited = 0
    private var lastRunSteps: [String] = []
    private var lastRunAt: Double?

    /// The id of the plan being executed; automatic requests carry it (B's rate limiter).
    private(set) var currentPlanID: UInt64?
    private var nextPlanID: UInt64 = 0

    /// Last connect, disconnect or wake (uptime seconds), for persisted-choice learning.
    private(set) var lastConnectOrWake: Double?

    init() {}

    func start(_ context: DisplaysContext, lifetime: Lifetime) {
        guard self.context == nil else { return }
        self.context = context
        self.lifetime = lifetime
        lastSetKey = activeSetKey(context)
        context.diagnostics.register(self, section: L("Connect planner"), lifetime: lifetime)
        lifetime.onEnd { [weak self] in self?.stop() }
    }

    func stop() {
        fullTimer?.cancel()
        graceTimer?.cancel()
        fullTimer = nil
        graceTimer = nil
        pendingTriggers = []
        quiet.reset()
        running = false
        rerunAfter = false
        userChanges = 0
        prompted = []
        context = nil
        lifetime = nil
    }

    // MARK: Attachments (registration ends with the controller's lifetime)

    func attach(_ c: ResolutionController, lifetime: Lifetime) { resolution = c; lifetime.onEnd { [weak self] in self?.resolution = nil } }
    func attach(_ c: ArrangementController, lifetime: Lifetime) { arrangement = c; lifetime.onEnd { [weak self] in self?.arrangement = nil } }
    func attach(_ c: PanelPropsController, lifetime: Lifetime) { panelProps = c; lifetime.onEnd { [weak self] in self?.panelProps = nil } }
    func attach(_ c: PowerController, lifetime: Lifetime) { power = c; lifetime.onEnd { [weak self] in self?.power = nil } }
    func attach(_ c: ProtectionController, lifetime: Lifetime) { protection = c; lifetime.onEnd { [weak self] in self?.protection = nil } }
    func attach(_ c: LayoutsController, lifetime: Lifetime) { layouts = c; lifetime.onEnd { [weak self] in self?.layouts = nil } }
    func attach(_ c: VirtualController, lifetime: Lifetime) { virtual = c; lifetime.onEnd { [weak self] in self?.virtual = nil } }
    func attach(_ c: SmartHiDPIController, lifetime: Lifetime) { smartHiDPI = c; lifetime.onEnd { [weak self] in self?.smartHiDPI = nil } }

    // MARK: Signals from controllers

    /// A user-initiated change is in flight (trial panel open): automatic steps wait.
    func beginUserChange() { userChanges += 1 }

    /// The user change finished. `changed`: something was applied or kept, so protection
    /// takes it as the new desired state once things are quiet.
    func endUserChange(changed: Bool) {
        userChanges = max(0, userChanges - 1)
        if changed {
            suppressUntil = max(suppressUntil, managementUptime() + ConnectPlan.quietSeconds + 1)
            recapturePending = true
            scheduleFull(after: ConnectPlan.quietSeconds + 1.1)
        }
    }

    /// Seconds since the last wake or unlock (for Smart HiDPI grace and learning).
    var secondsSinceWakeOrUnlock: Double? {
        let gate = context.flatMap { [$0.sessionGate.lastWakeUptime, $0.sessionGate.lastUnlockUptime].compactMap { $0 }.max() }
        let last = [lastWakeOrUnlock, gate].compactMap { $0 }.max()
        return last.map { managementUptime() - $0 }
    }

    private func beginPlan() {
        nextPlanID &+= 1
        currentPlanID = nextPlanID
    }

    // MARK: Triggers

    func trigger(_ trigger: ConnectTrigger) {
        guard let ctx = context else { return }
        let now = managementUptime()
        switch trigger {
        case .wake, .sessionResume:
            lastWakeOrUnlock = now
            lastConnectOrWake = now
            prompted = []
        case .launch:
            lastConnectOrWake = now
        case .reconfigure:
            if activeSetKey(ctx) != lastSetKey { lastConnectOrWake = now }
        }
        runVisibilitySoon()
        if trigger == .reconfigure && now < suppressUntil { return }
        pendingTriggers.insert(trigger)
        quiet.note(now)
        if let due = quiet.dueIn(now: now) { scheduleFull(after: due) }
    }

    private func scheduleFull(after seconds: Double) {
        fullTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fullTimerFired() }
        }
        fullTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds), execute: work)
    }

    private func fullTimerFired() {
        fullTimer = nil
        guard let ctx = context, let life = lifetime else { return }
        if running { rerunAfter = true; return }
        if userChanges > 0 || ctx.transactions.isBusy || ctx.transactions.hasPendingTrial {
            scheduleFull(after: 1)
            return
        }
        let triggers = pendingTriggers
        pendingTriggers = []
        quiet.reset()
        running = true
        life.spawn { [weak self] in
            await self?.runFull(triggers)
            guard let self else { return }
            self.running = false
            if self.rerunAfter {
                self.rerunAfter = false
                self.scheduleFull(after: ConnectPlan.quietSeconds)
            }
        }
    }

    // MARK: Step 1

    private func runVisibilitySoon() {
        guard let life = lifetime else { return }
        if visibilityRunning { visibilityAgain = true; return }
        visibilityRunning = true
        life.spawn { [weak self] in
            guard let self else { return }
            repeat {
                self.visibilityAgain = false
                await self.runVisibility()
            } while self.visibilityAgain && self.context != nil
            self.visibilityRunning = false
        }
    }

    private func runVisibility() async {
        guard let ctx = context else { return }
        let inputs = gather(ctx, trigger: .reconfigure, phase: .virtuals, setChanged: false)
        let steps = ConnectPlan.visibilitySteps(inputs)
        if !steps.isEmpty {
            EventLog.shared.record(.planner, "Visibility restore: \(steps.count) step(s)")
            beginPlan()
            for step in steps { await execute(step, ctx: ctx) }
            currentPlanID = nil
        }
        scheduleGraceCheck(inputs)
    }

    /// Orphaned hosts are torn down when their grace ends, even without a new event.
    private func scheduleGraceCheck(_ inputs: ConnectInputs) {
        graceTimer?.cancel()
        graceTimer = nil
        let anyVisible = inputs.displays.contains { $0.strong || $0.weak }
        let grace = ConnectPlan.grace(secondsSinceWakeOrUnlock: inputs.secondsSinceWakeOrUnlock, anyVisible: anyVisible)
        let remaining = inputs.hosts.compactMap { h -> Double? in
            guard h.isLive, let missing = h.physicalMissingSeconds, missing < grace else { return nil }
            return grace - missing
        }.min()
        guard let wait = remaining else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.runVisibilitySoon() }
        }
        graceTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.05, execute: work)
    }

    // MARK: Steps 2–5

    private func runFull(_ triggers: Set<ConnectTrigger>) async {
        guard let ctx = context else { return }
        let started = managementUptime()
        runs += 1
        lastRunAt = started
        let trigger: ConnectTrigger = triggers.contains(.launch) ? .launch : triggers.contains(.wake) ? .wake
            : triggers.contains(.sessionResume) ? .sessionResume : .reconfigure
        let setKey = activeSetKey(ctx)
        let setChanged = setKey != lastSetKey
        lastSetKey = setKey
        if setChanged { prompted = [] }
        var counted = false
        var executed: [String] = []
        beginPlan()
        defer { currentPlanID = nil }

        if recapturePending && userChanges == 0 {
            recapturePending = false
            protection?.recaptureAfterSnapticChange()
        }

        for phase in [ConnectPhase.virtuals, .rest] {
            guard let ctx = context else { return }
            if phase == .rest { await power?.refreshExternalPower() }
            let inputs = gather(ctx, trigger: trigger, phase: phase, setChanged: setChanged)
            let steps = ConnectPlan.plan(inputs: inputs)
            let actionable = steps.filter { !$0.isVisibilityRestore && !$0.isPrompt }
            if !actionable.isEmpty && !counted {
                let keys = Set(actionable.flatMap(\.keys))
                guard limiter.allow(keys: keys, now: managementUptime()) else {
                    limited += 1
                    EventLog.shared.record(.planner, "Plan rate-limited")
                    // Visibility steps still run.
                    for s in steps where s.isVisibilityRestore { await execute(s, ctx: ctx) }
                    break
                }
                counted = true
            }
            for step in steps {
                guard context != nil else { return }
                await execute(step, ctx: ctx)
                executed.append(Self.describe(step))
            }
            if phase == .virtuals && steps.contains(where: { if case .createVirtual = $0 { return true }; return false }) {
                // Re-snapshot: let the registry see the new displays.
                ctx.registry.refresh()
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        lastRunSteps = executed
        if !executed.isEmpty {
            // Our own reconfigurations are ignored for the run plus quiet + 1 s.
            suppressUntil = max(suppressUntil, managementUptime() + ConnectPlan.quietSeconds + 1)
            EventLog.shared.record(.planner, "Plan (\(trigger.rawValue)): \(executed.count) step(s) in "
                                   + String(format: "%.1f s", managementUptime() - started))
        }
    }

    // MARK: Inputs

    private func activeSetKey(_ ctx: DisplaysContext) -> DisplaySetKey? {
        DisplaySetKey(keys: Set(ctx.registry.displays.filter { $0.isActive || $0.isOnline }.map(\.key)))
    }

    private func gather(_ ctx: DisplaysContext, trigger: ConnectTrigger, phase: ConnectPhase, setChanged: Bool) -> ConnectInputs {
        var inputs = ConnectInputs(trigger: trigger, phase: phase, effective: ctx.runtime.effectiveFeatures,
                                   safeMode: ctx.safeMode.isActive, panicLatch: ctx.panic.isLatched,
                                   secondsSinceWakeOrUnlock: secondsSinceWakeOrUnlock, displaySetChanged: setChanged,
                                   displays: planDisplays(ctx))
        smartHiDPI?.contribute(to: &inputs)
        virtual?.contribute(to: &inputs)
        guard phase == .rest else { return inputs }
        layouts?.contribute(to: &inputs)
        protection?.contribute(to: &inputs)
        resolution?.contribute(to: &inputs)
        power?.contribute(to: &inputs)
        return inputs
    }

    func planDisplays(_ ctx: DisplaysContext) -> [PlanDisplay] {
        let displays = ctx.registry.displays
        let disabled = power?.disabledKeys ?? []
        return displays.map { d in
            let modes = ManagedModes.modes(for: d.desktopID).map(\.ref)
            let mirror = d.mirrorOf.flatMap { src in displays.first { $0.desktopID == src || $0.hardwareID == src }?.key }
            let dim = (ctx.brightness.value(for: d.key) ?? 1) < 0.08
            return PlanDisplay(key: d.key, transport: d.transport, isBuiltin: d.isBuiltin, isActive: d.isActive, isMain: d.isMain,
                               strong: d.isStronglyVisible, weak: d.isWeaklyVisible,
                               mode: d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref,
                               availableModes: modes, disabledBySnaptic: disabled.contains(d.key),
                               dimmedBelowFloor: dim && d.isActive, x: Int32(d.bounds.origin.x.rounded()),
                               y: Int32(d.bounds.origin.y.rounded()), rotation: d.rotation, mirrorOf: mirror)
        }
    }

    // MARK: Execution

    private func execute(_ step: PlanStep, ctx: DisplaysContext) async {
        switch step {
        case .reenable(let k):
            await power?.reenable([k], automatic: true)
        case .raiseFloor(let k):
            ctx.brightness.set(0.15, for: k, source: .restore)
        case .destroyHost(let id, let reason):
            EventLog.shared.record(.planner, "Host teardown (\(reason.rawValue))")
            await ctx.virtualHosts.destroy(specID: id)
        case .moveMain(let k):
            guard let d = ManagedDisplays.info(ctx, key: k), !d.isMain else { return }
            _ = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Move the main display"), risk: .restore,
                                                                      changes: [.main(d.desktopID)], finalScope: .forSession,
                                                                      automatic: true))
        case .createVirtual(let id, let purpose):
            switch purpose {
            case .smartHiDPI(let physical): await smartHiDPI?.reestablish(specID: id, physical: physical)
            case .virtualScreen: await virtual?.connectAutomatically(id)
            }
        case .rebind(let id, let physical):
            await smartHiDPI?.rebind(specID: id, physical: physical)
        case .promptMirror(let id, let target):
            prompt("mirror:\(id.rawValue):\(target.rawValue)") { [weak self] in
                if self?.smartHiDPI?.owns(id) == true {
                    self?.smartHiDPI?.promptRebind(specID: id, physical: target)
                } else {
                    self?.virtual?.promptMirror(id, onto: target)
                }
            }
        case .promptStream(let id, let target, let flipped):
            prompt("stream:\(id.rawValue):\(target.rawValue)") { [weak self] in
                self?.virtual?.promptStream(id, onto: target, flipped: flipped)
            }
        case .applyLayout(let id):
            await layouts?.applyAutomatically(id)
        case .promptLayout(let id):
            prompt("layout:\(id.rawValue)") { [weak self] in self?.layouts?.promptApply(id) }
        case .protect(let deltas):
            await protection?.apply(deltas)
        case .promptRestore(let deltas):
            prompt("restore:\(deltas.map(\.key.rawValue).joined())") { [weak self] in self?.protection?.promptRestore(deltas) }
        case .restoreMode(let k, let m):
            await resolution?.restorePersisted(k, mode: m)
        case .promptRestoreMode(let k, let m):
            prompt("mode:\(k.rawValue)") { [weak self] in self?.resolution?.promptRestorePersisted(k, mode: m) }
        case .disconnectBuiltin(let k):
            await power?.autoDisconnect(k)
        }
    }

    /// Prompts show once per connect episode (reset when the display set changes or on wake).
    private func prompt(_ key: String, _ show: () -> Void) {
        guard prompted.insert(key).inserted else { return }
        show()
    }

    static func describe(_ step: PlanStep) -> String {
        switch step {
        case .reenable: return "reenable"
        case .raiseFloor: return "raiseFloor"
        case .destroyHost(_, let r): return "destroyHost(\(r.rawValue))"
        case .moveMain: return "moveMain"
        case .createVirtual: return "createVirtual"
        case .rebind: return "rebind"
        case .promptMirror: return "promptMirror"
        case .promptStream: return "promptStream"
        case .applyLayout: return "applyLayout"
        case .promptLayout: return "promptLayout"
        case .protect(let d): return "protect(\(d.count))"
        case .promptRestore: return "promptRestore"
        case .restoreMode: return "restoreMode"
        case .promptRestoreMode: return "promptRestoreMode"
        case .disconnectBuiltin: return "disconnectBuiltin"
        }
    }
}

extension ConnectPlanner: DiagnosticsContributor {
    func diagnostics() -> [(String, String)] {
        var rows: [(String, String)] = [
            (L("Plans run"), String(runs)),
            (L("Plans rate-limited"), String(limited)),
            (L("Last plan steps"), lastRunSteps.isEmpty ? L("none") : lastRunSteps.joined(separator: ", ")),
            (L("Automatic steps paused"), (context.map(managementAutomationPaused) ?? false) ? L("Yes (Safe Mode or paused)") : L("No")),
        ]
        if let at = lastRunAt { rows.append((L("Last plan"), String(format: L("%.0f s ago"), managementUptime() - at))) }
        return rows
    }
}
