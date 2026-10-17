import AppKit
import Combine
import CoreGraphics
import SnapticKit
import SnapticShims

// Every layout change goes through here (owner: B). PLAN §4.3 + R5.2: serialized; prepare →
// snapshot inside the queue → skip-equal → risk = max(caller, classifier) → invariants →
// CAS undo → journal + guard ack for trial/restore → apply (HDR, rotation, re-resolved modes,
// CG batches by scope) → trial panel → Keep (re-apply with final scope, never skipping) or
// Revert (CAS, single undo order). Also keeps the guard's long-armed set current.

@MainActor final class DisplayTransactionQueue: DisplayServiceLifecycle, DiagnosticsContributor {
    static var serviceID: DisplayServiceID { .transactions }
    static var privateSymbols: [PrivateSymbol] {
        [.cgsConfigureDisplayEnabled, .mpDisplay, .cgsGetNumberOfDisplayModes, .cgsGetDisplayModeDescription,
         .cgsGetCurrentDisplayMode, .cgsConfigureDisplayMode]
    }
    weak var context: DisplaysContext?

    /// The scope trials apply with (one switchable constant, PLAN §4.3, R2C §5.3).
    static let trialScope: ConfigScope = .forSession
    static let keepSuppressSeconds = 2.5
    static let settleSeconds = 2.0
    static let settleCapSeconds = 5.0
    static let recentModeWindow = 60.0

    init() {}

    private struct PendingTrial {
        let id: UInt64
        let undo: [UndoOp]
        let changes: [DisplayChange]
        var revertedExternally = false
    }

    private var active = false
    private var running = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var pending: PendingTrial?
    private let panel = ConfirmPanel()
    private var journal: RevertJournal?
    private var limiter = RateLimiter()
    private var countedPlans: [UInt64] = []
    private(set) var suppressAutomaticUntil: Double = 0
    private var recentModes: [(at: Double, op: UndoOp)] = []
    private var reportObservers: [(UInt64, @MainActor (TransactionReport) -> Void)] = []
    private var panelObservers: [(UInt64, @MainActor (Bool) -> Void)] = []
    private var serial: UInt64 = 0
    private(set) var lastReports: [TransactionReport] = []
    private var longArmWork: DispatchWorkItem?
    private var lifetime: Lifetime?

    var isBusy: Bool { running || !waiting.isEmpty }
    var hasPendingTrial: Bool { pending != nil }
    var isConfirmPanelVisible: Bool { panel.isShowing }
    var isSuppressingAutomatic: Bool { SessionGate.uptime() < suppressAutomaticUntil }
    var permanentJournalCount: Int { journal?.permanentCount ?? 0 }
    var hasSessionJournal: Bool { journal?.hasSessionJournal ?? false }

    // MARK: Lifecycle

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        self.lifetime = lifetime
        journal = RevertJournal()
        context.guardClient.onReverted = { [weak self] trial, _, _ in
            guard let self, let p = self.pending, trial == p.id else { return }
            self.pending?.revertedExternally = true
            self.panel.dismiss(.revert)
        }
        context.guardClient.onLost = { [weak self] in
            guard let self else { return }
            if self.pending != nil { self.panel.dismiss(.revert) }
            if context.guardClient.isUnprotected {
                context.toasts.show(L("Snaptic's safety helper stopped. Restart Snaptic to stay protected."))
            }
        }
        context.sessionGate.observeEvents(lifetime: lifetime) { [weak self] event in
            switch event {
            case .willSleep, .resignedActive, .locked, .screensDidSleep:
                self?.revertPendingTrial(reason: L("The Mac went to sleep or was locked."))
            default: break
            }
        }
        context.diagnostics.register(self, section: L("Transactions"), lifetime: lifetime)
        layoutFactsChanged()
    }

    func deactivate() {
        guard active else { return }
        // A pending trial resolves as Revert, synchronously (stop() is sync, PLAN §3.3).
        if let p = pending, let ctx = context {
            pending?.revertedExternally = true
            _ = applyUndoNow(p.undo, ctx: ctx)
            ctx.guardClient.disarm(p.id)
            journal?.clearSession()
            journal?.resolvePermanent(trial: p.id)
        }
        panel.dismiss(.revert)
        active = false
        longArmWork?.cancel()
        longArmWork = nil
        let w = waiting
        waiting = []
        w.forEach { $0.resume() }
        context?.guardClient.onReverted = nil
        context?.guardClient.onLost = nil
        context = nil
        lifetime = nil
    }

    // MARK: Observers

    /// Every finished transaction (D's protection / persisted choice learn from these).
    func observe(lifetime: Lifetime, _ handler: @escaping @MainActor (TransactionReport) -> Void) {
        guard !lifetime.isEnded else { return }
        serial &+= 1
        let mine = serial
        reportObservers.append((mine, handler))
        lifetime.onEnd { [weak self] in self?.reportObservers.removeAll { $0.0 == mine } }
    }

    /// The confirm panel shows (true) or hides (false): C raises host dimming to ≥ 30 % meanwhile.
    func observePanel(lifetime: Lifetime, _ handler: @escaping @MainActor (Bool) -> Void) {
        guard !lifetime.isEnded else { return }
        serial &+= 1
        let mine = serial
        panelObservers.append((mine, handler))
        lifetime.onEnd { [weak self] in self?.panelObservers.removeAll { $0.0 == mine } }
    }

    // MARK: Submit

    func submit(_ request: TransactionRequest) async -> TransactionOutcome {
        guard active else { return .failed(L("Displays are turned off.")) }
        // A user request while a trial waits resolves that trial as Revert first (PLAN §4.3).
        if !request.automatic, pending != nil {
            revertPendingTrial(reason: L("A new display change was requested."))
            context?.toasts.show(L("The previous display change was reverted."))
        }
        if running {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiting.append(c) }
        } else {
            running = true
        }
        let outcome = await execute(request)
        if waiting.isEmpty { running = false } else { waiting.removeFirst().resume() }
        return outcome
    }

    /// Resolves a pending trial as Revert (sleep, lock, quit, new request, panic).
    @discardableResult
    func revertPendingTrial(reason: String) -> Bool {
        guard pending != nil else { return false }
        panel.dismiss(.revert)
        EventLog.shared.record(.transaction, "Pending trial reverted (\(reason))")
        return true
    }

    private func execute(_ req: TransactionRequest) async -> TransactionOutcome {
        guard active, let ctx = context else { return .failed(L("Displays are turned off.")) }
        let visibilityOnly = !req.changes.isEmpty && req.changes.allSatisfy(\.isVisibilityRestoring)

        if !ctx.sessionGate.isOpen {
            return req.automatic ? .busy : .failed(L("Display changes wait until the Mac is unlocked and awake."))
        }
        if req.automatic && !visibilityOnly {
            if ctx.panic.isLatched { return .busy }
            if isSuppressingAutomatic { return .busy }
            if !consumeRate(req, ctx: ctx) { return .busy }
        }
        if let prepare = req.prepare {
            do { try await prepare() } catch { return .failed(L("Couldn't prepare the change.")) }
            guard active else { return .failed(L("Displays are turned off.")) }
        }
        guard let before = ctx.registry.snapshot() else { return .failed(L("Displays are turned off.")) }

        // Captured displays (games, presentations) are never reconfigured (PLAN §4.4).
        for id in Set(req.changes.map(\.displayID)) where CGDisplayIsCaptured(id) != 0 {
            return .failed(L("Another app has taken over this display."))
        }
        let changes = req.changes.filter { !Self.isAlreadyApplied($0, in: before) }
        if changes.isEmpty {
            report(req, before: before, risk: req.risk, outcome: .applied)
            return .applied
        }
        // MonitorPanel changes need a helper that can revert them (R5.2).
        for c in changes where c.isMonitorPanel {
            guard ctx.privateAPI.monitorPanelSupports(Self.monitorPanelGroup(c)) else {
                return .failed(L("This macOS version doesn't let Snaptic change that."))
            }
        }

        // Risk = max(caller, classifier). A restore re-establishes a state the user kept: it
        // stays restore (journaled, long-armed, invariant-checked, no panel).
        let classified = RiskClassifier.classify(changes, current: before, facts: { [weak self] id in
            self?.modeFacts(id, ctx: ctx) ?? ModeFacts()
        }, setting: ctx.config.value.safety.confirmResolution)
        let risk: TransactionRisk = req.risk == .restore ? .restore : max(req.risk, TransactionRisk(classified))

        if risk == .trial, changes.contains(where: \.isMonitorPanel) {
            guard await ctx.guardClient.ensureRunning(), ctx.guardClient.canMonitorPanel else {
                return .failed(L("Safety helper can't revert this."))
            }
        }

        // Invariants on the predicted layout.
        let predicted = Invariants.predict(before, applying: changes)
        let needsLong = !Invariants.requiredLongArm(predicted).reasons.subtracting(Invariants.requiredLongArm(before).reasons).isEmpty
        var guardOK = true
        if needsLong || risk != .low { guardOK = await ctx.guardClient.ensureRunning() }
        let invariantContext = InvariantContext(guardAvailable: guardOK, dimToBlack: [],
                                                unattended: risk == .restore || req.automatic)
        let violations = Invariants.violations(before: before, changes: changes, context: invariantContext)
        if !violations.isEmpty {
            EventLog.shared.record(.transaction, "Refused \(changes.count) changes: \(violations.count) invariants")
            report(req, before: before, risk: risk, outcome: .refused(violations))
            return .refused(violations)
        }

        let undo = UndoPlanner.undo(for: changes, before: before)
        let trialID = ctx.guardClient.makeTrialID()

        // Protection before applying (fail closed).
        switch risk {
        case .trial:
            guard journal?.writeSession(undo: undo, restoreColorSync: false, trialID: trialID, live: before) == true,
                  journal?.addPermanent(trial: trialID, ops: undo) == true else {
                return .failed(L("Couldn't save the undo information."))
            }
            let deadline = GuardProtocol.trialDeadline(panelSeconds: Double(ctx.config.value.safety.confirmSeconds))
            guard await ctx.guardClient.armTrial(trialID, undo: undo, deadlineSeconds: deadline) else {
                journal?.clearSession()
                journal?.resolvePermanent(trial: trialID)
                return .failed(L("Safety helper unavailable."))
            }
        case .restore:
            let long = Invariants.requiredLongArm(predicted)
            guard journal?.writeSession(undo: UndoPlanner.merge(long.undo, undo), restoreColorSync: long.restoreColorSync,
                                        trialID: nil, live: before) == true else {
                return .failed(L("Couldn't save the undo information."))
            }
            if !long.isEmpty {
                guard await ctx.guardClient.setLongAndWait(long.undo, restoreColorSync: long.restoreColorSync) else {
                    journal?.clearSession()
                    return .failed(L("Safety helper unavailable."))
                }
            }
        case .low:
            if needsLong {
                let long = Invariants.requiredLongArm(predicted)
                guard await ctx.guardClient.setLongAndWait(long.undo, restoreColorSync: long.restoreColorSync) else {
                    return .failed(L("Safety helper unavailable."))
                }
            }
        }

        // Apply.
        let scopeFor: (DisplayChange) -> ConfigScope = { [weak self] c in
            guard risk != .trial else { return Self.trialScope }
            return self?.finalScope(for: c, request: req, ctx: ctx) ?? .forSession
        }
        let applied = await applyStaged(changes, scope: scopeFor, ctx: ctx)
        if let failure = applied.failure {
            _ = applyUndoNow(undo, ctx: ctx)
            if risk == .trial { ctx.guardClient.disarm(trialID) }
            journal?.clearSession()
            journal?.resolvePermanent(trial: trialID)
            layoutFactsChanged()
            EventLog.shared.record(.transaction, "Apply failed and was undone")
            report(req, before: before, risk: risk, outcome: .failed(failure))
            return .failed(failure)
        }
        noteApplied(changes, undo: undo, ctx: ctx)

        switch risk {
        case .low, .restore:
            if risk == .low { journal?.clearSession() }
            layoutFactsChanged()
            report(req, before: before, risk: risk, outcome: .applied)
            return .applied
        case .trial:
            let outcome = await runTrial(trialID, changes: changes, undo: undo, req: req, ctx: ctx)
            report(req, before: before, risk: risk, outcome: outcome)
            return outcome
        }
    }

    // MARK: Trial

    private func runTrial(_ id: UInt64, changes: [DisplayChange], undo: [UndoOp], req: TransactionRequest,
                          ctx: DisplaysContext) async -> TransactionOutcome {
        pending = PendingTrial(id: id, undo: undo, changes: changes)
        await settle(changes.map(\.displayID), ctx: ctx)
        let seconds = Double(ctx.config.value.safety.confirmSeconds)
        panelObservers.forEach { $0.1(true) }
        let result: ConfirmResult
        if pending?.revertedExternally == true || !active {
            result = .revert
        } else {
            result = await panel.present(label: req.label, seconds: seconds, interactive: req.interactive) { [weak self] in
                guard let snap = self?.context?.registry.snapshot() else { return [] }
                return Invariants.panelHosts(snap)
            }
        }
        panelObservers.forEach { $0.1(false) }
        let external = pending?.revertedExternally ?? true
        pending = nil

        if result == .keep, active, context != nil {
            _ = await ctx.guardClient.commitIntentAndWait(id)
            // Re-apply with the final scope and never skip (R5.2): that's what makes it stick.
            let cg = changes.filter { !$0.isMonitorPanel }
            let (permanent, session) = CGConfig.keepBatches(cg)
            ctx.guardClient.busy(seconds: 5)
            let virtualsOnline = ctx.registry.cachedSnapshot()?.entries.contains { $0.transport == .snapticVirtual } ?? false
            let permScope: ConfigScope = virtualsOnline && !permanent.allSatisfy({ Self.isPhysicalMode($0, ctx: ctx) })
                ? .forSession : .permanently
            let functions = cgFunctions(ctx)
            let hidden = hiddenModes(for: cg, ctx: ctx)
            if !permanent.isEmpty { _ = CGConfig.apply(permanent, scope: permScope, functions: functions, hiddenModes: hidden) }
            if !session.isEmpty { _ = CGConfig.apply(session, scope: .forSession, functions: functions, hiddenModes: hidden) }
            rememberKept(changes, ctx: ctx)
            if let afterKeep = req.afterKeep { await afterKeep() }
            ctx.guardClient.commit(id)
            journal?.clearSession()
            journal?.resolvePermanent(trial: id)
            suppressAutomaticUntil = SessionGate.uptime() + Self.keepSuppressSeconds
            layoutFactsChanged()
            EventLog.shared.record(.transaction, "Trial kept")
            return .kept
        }

        // Revert, timeout, sleep, quit, resign, guard EOF.
        if !external { _ = await revertStaged(undo, ctx: ctx) }
        if let afterRevert = req.afterRevert { await afterRevert() }
        ctx.guardClient.disarm(id)
        journal?.clearSession()
        journal?.resolvePermanent(trial: id)
        suppressAutomaticUntil = SessionGate.uptime() + Self.keepSuppressSeconds
        layoutFactsChanged()
        let why = result == .timeout ? L("No confirmation, so the change was reverted.") : L("The change was reverted.")
        EventLog.shared.record(.transaction, result == .timeout ? "Trial timed out" : "Trial reverted")
        return .reverted(why)
    }

    /// Waits until the changed displays are active again and the layout has been quiet for
    /// 2 s (capped at 5 s), so the countdown starts on a visible screen.
    private func settle(_ ids: [UInt32], ctx: DisplaysContext) async {
        let start = SessionGate.uptime()
        while SessionGate.uptime() - start < Self.settleCapSeconds {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard active, pending?.revertedExternally != true else { return }
            let snap = ctx.registry.snapshot()
            let allShown = ids.allSatisfy { id in snap?.entry(id).map { $0.isEnabled } ?? true }
            if allShown && ctx.registry.quietSeconds() >= Self.settleSeconds && !ctx.registry.isReconfiguring { return }
        }
    }

    // MARK: Apply

    private struct ApplyResult { var failure: String? }

    /// HDR → quiet → rotation (poll ≤ 10 s) → quiet → CG batches (modes re-resolved) by scope.
    private func applyStaged(_ changes: [DisplayChange], scope: (DisplayChange) -> ConfigScope,
                             ctx: DisplaysContext) async -> ApplyResult {
        let hdr = changes.filter { if case .hdr = $0 { return true } else { return false } }
        let underscan = changes.filter { if case .underscan = $0 { return true } else { return false } }
        let rotation = changes.filter { if case .rotation = $0 { return true } else { return false } }
        for c in hdr + underscan {
            guard CGConfig.applyMonitorPanel(c) else { return ApplyResult(failure: L("The display refused the change.")) }
        }
        if !hdr.isEmpty { await waitQuiet(ctx, quiet: 1.5, cap: 8) }
        for c in rotation {
            guard case .rotation(let id, let degrees) = c, CGConfig.applyMonitorPanel(c) else {
                return ApplyResult(failure: L("The display refused the change."))
            }
            let target = Invariants.normalizedRotation(degrees)
            let start = SessionGate.uptime()
            while Invariants.normalizedRotation(Int(CGDisplayRotation(id).rounded())) != target {
                if SessionGate.uptime() - start > 10 { return ApplyResult(failure: L("The display didn't rotate.")) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        if !rotation.isEmpty { await waitQuiet(ctx, quiet: 1, cap: 6) }

        let cg = changes.filter { !$0.isMonitorPanel }
        guard !cg.isEmpty else { return ApplyResult() }
        let functions = cgFunctions(ctx)
        let hidden = hiddenModes(for: cg, ctx: ctx)
        var groups: [(ConfigScope, [DisplayChange])] = []
        for c in cg {
            let s = scope(c)
            if let i = groups.firstIndex(where: { $0.0 == s }) { groups[i].1.append(c) } else { groups.append((s, [c])) }
        }
        // Permanent batch first (modes, origins, main), then the session batch (mirrors, disable).
        groups.sort { $0.0 == .permanently && $1.0 != .permanently }
        for (s, batch) in groups {
            ctx.guardClient.busy(seconds: 5)
            let r = CGConfig.apply(batch, scope: s, functions: functions, hiddenModes: hidden)
            if !r.ok {
                EventLog.shared.record(.transaction, "CG configure failed: \(r.failures.first ?? "?")")
                return ApplyResult(failure: L("macOS refused the display change."))
            }
        }
        return ApplyResult()
    }

    /// Staged CAS revert with settling between stages.
    private func revertStaged(_ undo: [UndoOp], ctx: DisplaysContext) async -> (applied: Int, skipped: Int) {
        var applied = 0, skipped = 0
        let functions = cgFunctions(ctx)
        for (stage, ops) in UndoPlanner.stages(undo) {
            guard let live = ctx.registry.snapshot() else { break }
            let pendingOps = stage == .monitorPanel ? JournalApplier.monitorPanelPending(ops, live: live)
                                                    : UndoPlanner.pending(ops, live: live)
            skipped += ops.count - pendingOps.count
            let changes = pendingOps.compactMap(UndoPlanner.change(for:))
            guard !changes.isEmpty else { continue }
            if stage == .monitorPanel {
                for c in changes { if CGConfig.applyMonitorPanel(c) { applied += 1 } else { skipped += 1 } }
            } else {
                ctx.guardClient.busy(seconds: 5)
                let r = CGConfig.apply(changes, scope: .forSession, functions: functions, hiddenModes: hiddenModes(for: changes, ctx: ctx))
                if r.ok { applied += r.applied } else { skipped += changes.count }
            }
            noteApplied(changes, undo: [], ctx: ctx)
            await waitQuiet(ctx, quiet: 1, cap: stage == .monitorPanel ? 6 : 4)
        }
        return (applied, skipped)
    }

    /// Synchronous CAS undo (deactivate/quit and failed applies): no settling.
    private func applyUndoNow(_ undo: [UndoOp], ctx: DisplaysContext) -> Int {
        var applied = 0
        let functions = cgFunctions(ctx)
        for (stage, ops) in UndoPlanner.stages(undo) {
            guard let live = ctx.registry.snapshot() else { break }
            let pendingOps = stage == .monitorPanel ? JournalApplier.monitorPanelPending(ops, live: live)
                                                    : UndoPlanner.pending(ops, live: live)
            let changes = pendingOps.compactMap(UndoPlanner.change(for:))
            if stage == .monitorPanel {
                for c in changes where CGConfig.applyMonitorPanel(c) { applied += 1 }
            } else if !changes.isEmpty {
                let r = CGConfig.apply(changes, scope: .forSession, functions: functions)
                applied += r.applied
            }
            noteApplied(changes, undo: [], ctx: ctx)
        }
        return applied
    }

    private func waitQuiet(_ ctx: DisplaysContext, quiet: Double, cap: Double) async {
        let start = SessionGate.uptime()
        try? await Task.sleep(nanoseconds: 300_000_000)
        while SessionGate.uptime() - start < cap {
            if ctx.registry.quietSeconds() >= quiet { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Bookkeeping after changes went out: Snaptic-disabled displays, recent modes (panic).
    private func noteApplied(_ changes: [DisplayChange], undo: [UndoOp], ctx: DisplaysContext) {
        let now = SessionGate.uptime()
        for c in changes {
            if case .enabled(let id, let on) = c, let fp = ctx.registry.sessionFingerprint(of: id) {
                ctx.registry.setDisabledBySnaptic(fp, !on)
            }
        }
        for op in undo where op.property == .mode { recentModes.append((now, op)) }
        recentModes.removeAll { now - $0.at > Self.recentModeWindow }
    }

    // MARK: Helpers

    private func cgFunctions(_ ctx: DisplaysContext) -> CGConfigFunctions {
        CGConfigFunctions(configureEnabled: ctx.privateAPI.function(.cgsConfigureDisplayEnabled, as: CGConfigFunctions.EnableFn.self),
                          configureCGSMode: ctx.runtime.isEffective(.hiddenModes)
                              ? ctx.privateAPI.function(.cgsConfigureDisplayMode, as: CGConfigFunctions.CGSModeFn.self) : nil)
    }

    /// CGS lists for displays whose requested mode isn't public (only with `hiddenModes`).
    private func hiddenModes(for changes: [DisplayChange], ctx: DisplaysContext) -> [UInt32: [DisplayModeDescriptor]] {
        guard ctx.runtime.isEffective(.hiddenModes) else { return [:] }
        var out: [UInt32: [DisplayModeDescriptor]] = [:]
        for c in changes {
            guard case .mode(let id, let ref) = c, out[id] == nil,
                  DisplayModeDescriptor.resolve(ref, in: DisplayModes.list(id)) == nil,
                  let list = DisplayModes.hiddenList(id, api: ctx.privateAPI) else { continue }
            out[id] = list
        }
        return out
    }

    private func modeFacts(_ id: UInt32, ctx: DisplaysContext) -> ModeFacts {
        let modes = DisplayModes.list(id)
        let kept = ctx.registry.key(forDisplayID: id).flatMap { ctx.config.value.safety.keptModes[$0]?.modes } ?? []
        let known = RiskClassifier.knownGood(modes: modes, current: DisplayModes.current(id)?.ref,
                                             isBuiltin: CGDisplayIsBuiltin(id) != 0, kept: Set(kept))
        return ModeFacts(knownGood: known, publicModes: Set(modes.map(\.ref)))
    }

    private func rememberKept(_ changes: [DisplayChange], ctx: DisplaysContext) {
        var value = ctx.config.value
        var changed = false
        for c in changes {
            guard case .mode(let id, let ref) = c, let key = ctx.registry.key(forDisplayID: id) else { continue }
            var kept = value.safety.keptModes[key] ?? KeptModes()
            kept.remember(ref)
            value.safety.keptModes[key] = kept
            changed = true
        }
        if changed { ctx.config.value = value }
    }

    private func finalScope(for c: DisplayChange, request: TransactionRequest, ctx: DisplaysContext) -> ConfigScope {
        guard c.keepScope == .permanently, request.finalScope == .permanently else { return .forSession }
        // R5.2: automatic re-applies use .forSession while Snaptic virtuals are online.
        if request.automatic,
           ctx.registry.cachedSnapshot()?.entries.contains(where: { $0.transport == .snapticVirtual }) == true {
            return .forSession
        }
        return .permanently
    }

    private static func isPhysicalMode(_ c: DisplayChange, ctx: DisplaysContext) -> Bool {
        guard case .mode(let id, _) = c else { return false }
        return ctx.registry.cachedSnapshot()?.entry(id)?.isPhysical ?? true
    }

    private static func monitorPanelGroup(_ c: DisplayChange) -> String {
        switch c {
        case .rotation: return "rotation"
        case .hdr: return "hdr"
        case .underscan: return "underscan"
        default: return ""
        }
    }

    /// Skip-equal (R5.2 trial apply): the live value already equals the target.
    static func isAlreadyApplied(_ c: DisplayChange, in s: LayoutSnapshot) -> Bool {
        guard let e = s.entry(c.displayID) else { return false }
        switch c {
        case .mode(_, let m): return e.mode.map { $0 == m || $0.sameShape(as: m) } ?? false
        case .origin(_, let x, let y): return e.x == x && e.y == y
        case .mirror(_, let source): return e.mirrorOf == source
        case .enabled(_, let on): return e.isEnabled == on
        case .main(let id): return s.mainID == id
        case .rotation(_, let d): return e.rotation == Invariants.normalizedRotation(d)
        case .underscan(_, let v): return e.underscan.map { abs($0 - v) < 0.001 } ?? false
        case .hdr(_, let on): return e.hdrEnabled == on
        }
    }

    private func consumeRate(_ req: TransactionRequest, ctx: DisplaysContext) -> Bool {
        if let plan = req.planID, countedPlans.contains(plan) { return true }
        let fps = Set(req.changes.map(\.displayID)).compactMap { ctx.registry.sessionFingerprint(of: $0) }
        guard limiter.consume(displays: fps, at: SessionGate.uptime()) else {
            EventLog.shared.record(.transaction, "Automatic plan rate-limited")
            return false
        }
        if let plan = req.planID {
            countedPlans.append(plan)
            if countedPlans.count > 64 { countedPlans.removeFirst() }
        }
        return true
    }

    private func report(_ req: TransactionRequest, before: LayoutSnapshot, risk: TransactionRisk, outcome: TransactionOutcome) {
        let r = TransactionReport(label: req.label, changes: req.changes, before: before, risk: risk,
                                  automatic: req.automatic, outcome: outcome, at: SessionGate.uptime())
        lastReports.append(r)
        if lastReports.count > 10 { lastReports.removeFirst() }
        for (_, h) in reportObservers { h(r) }
    }

    // MARK: Long-arm state (invariant 4), kept current from every layout change

    /// Called by the registry after each rebuild and dim report (debounced).
    func layoutFactsChanged() {
        guard active else { return }
        longArmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.longArmWork = nil
                self?.updateLongArm()
            }
        }
        longArmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func updateLongArm() {
        guard active, let ctx = context, let snap = ctx.registry.snapshot() else { return }
        let req = Invariants.requiredLongArm(snap)
        let vis = Invariants.visibility(snap)
        let classes = snap.entries.map { e -> GuardDisplayClass in
            let host = e.transport == .snapticVirtual ? ctx.virtualHosts.host(for: e.id) : nil
            return GuardDisplayClass(id: e.id, transport: e.transport, strong: vis[e.id] == .strong,
                                     weak: vis[e.id] == .weak, hostPID: host?.pid, hostStartTime: host?.startTime)
        }
        if req.isEmpty {
            if ctx.guardClient.hasLongState { ctx.guardClient.setLong([], restoreColorSync: false) }
            ctx.guardClient.setImpairment(dimToBlack: false, overlayBelowFloor: false)
            if ctx.guardClient.isAlive { ctx.guardClient.classification(classes) }
            return
        }
        ctx.guardClient.setLong(req.undo, restoreColorSync: req.restoreColorSync)
        ctx.guardClient.setImpairment(dimToBlack: req.reasons.contains(.dimToBlack),
                                      overlayBelowFloor: req.reasons.contains(.overlayBelowFloor))
        ctx.guardClient.classification(classes)
        if !ctx.guardClient.isAlive {
            let guardClient = ctx.guardClient
            lifetime?.spawn { _ = await guardClient.ensureRunning() }
        }
    }

    // MARK: Panic support

    /// Reverts modes Snaptic set in the last 60 s (CAS), clears their known-good entries,
    /// and re-enables displays Snaptic disabled. Bypasses rate limits. Returns ops applied.
    @discardableResult
    func panicRevert() -> Int {
        guard let ctx = context else { return 0 }
        revertPendingTrial(reason: L("Restore All Displays"))
        let now = SessionGate.uptime()
        let modes = recentModes.filter { now - $0.at <= Self.recentModeWindow }.map(\.op)
        recentModes = []
        var ops = UndoPlanner.merge([], modes)
        if let snap = ctx.registry.snapshot() {
            // Re-enable every display Snaptic disabled (foreign, AirPlay, DisplayLink and Sidecar untouched).
            for e in snap.entries where e.disabledBySnaptic && !e.isEnabled && e.isPhysical {
                ops.append(UndoOp(displayID: e.id, fingerprint: e.fingerprint, property: .enabled,
                                  restore: .bool(true), expected: .bool(false)))
            }
        }
        var value = ctx.config.value
        for op in modes {
            guard case .mode(let m) = op.expected, let key = ctx.registry.key(forDisplayID: op.displayID) else { continue }
            value.safety.keptModes[key]?.forget(m)
        }
        if value != ctx.config.value { ctx.config.value = value }
        let applied = applyUndoNow(ops, ctx: ctx)
        layoutFactsChanged()
        return applied
    }

    // MARK: Diagnostics

    func diagnostics() -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Queue", isBusy ? "busy" : "idle"),
            ("Pending trial", pending == nil ? "none" : "waiting for Keep"),
            ("Session journal", hasSessionJournal ? "present" : "none"),
            ("Permanent-ops journal", "\(permanentJournalCount) ops"),
            ("Automatic suppressed", isSuppressingAutomatic ? "yes" : "no"),
        ]
        for r in lastReports.suffix(5) {
            let outcome: String
            switch r.outcome {
            case .applied: outcome = "applied"
            case .kept: outcome = "kept"
            case .reverted: outcome = "reverted"
            case .refused(let v): outcome = "refused (\(v.count))"
            case .busy: outcome = "busy"
            case .failed: outcome = "failed"
            }
            rows.append(("Recent", "\(r.changes.count) changes, \(r.automatic ? "automatic" : "user"), \(outcome)"))
        }
        return rows
    }
}
