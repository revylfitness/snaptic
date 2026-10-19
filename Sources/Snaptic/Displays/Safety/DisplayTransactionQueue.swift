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
// 0.3 §4.5: a trial appearing or ending and every journal change bump `revision(.diagnostics)` (Display
// Information shows "Pending confirmation" and the undo journal; the menu shows Restore All while pending).

@MainActor final class DisplayTransactionQueue: DisplayServiceLifecycle, DiagnosticsContributor {
    static var serviceID: DisplayServiceID { .transactions }
    static var privateSymbols: [PrivateSymbol] {
        [.cgsConfigureDisplayEnabled, .mpDisplay, .cgsGetNumberOfDisplayModes, .cgsGetDisplayModeDescription,
         .cgsConfigureDisplayMode]
    }
    weak var context: DisplaysContext?

    /// The scope trials apply with (one switchable constant, PLAN §4.3, R2C §5.3).
    static let trialScope: ConfigScope = .forSession
    static let keepSuppressSeconds = 2.5
    static let settleSeconds = 2.0
    static let settleCapSeconds = 5.0
    static let recentModeWindow = 60.0

    init() {}

    /// One armed trial, from the guard arm until Keep or Revert finished. Its lifecycle
    /// (Kit `TrialLifecycle`) decides every step; outside events only request a revert.
    private struct PendingTrial {
        /// Queue-local and unique across activations (a stale task never matches).
        let token: UInt64
        let id: UInt64
        let undo: [UndoOp]
        let changes: [DisplayChange]
        let before: LayoutSnapshot
        var life = TrialLifecycle()
        /// Something may already have reached the displays.
        var applied = false
        /// The Keep batches went out (and the kept modes were remembered).
        var keepWritten = false
        /// Those batches wrote modes, origins and main `.permanently`: a revert must write
        /// them back permanently too (FIXES-R2 N4).
        var keptPermanently = false
    }

    private var active = false
    /// Bumped by activate/deactivate: work started under an older epoch touches nothing.
    private var epoch: UInt64 = 0
    private var running = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var pending: PendingTrial? {
        didSet { if (oldValue == nil) != (pending == nil) { noteStatus() } }
    }
    private var trialSerial: UInt64 = 0
    private var supersession = TrialSupersession()
    /// How `stop()` resolved the last trial it interrupted (for that trial's own task).
    private var stopped: (token: UInt64, end: TrialEnd)?
    private let panel = ConfirmPanel()
    private var journal: RevertJournal?
    /// The long-armed undo the session journal holds right now (nil = no long-arm journal).
    private var journaledLong: [UndoOp]?
    /// Set at activation: the first sync removes whatever an earlier run may have left.
    private var journalMayBeStale = false
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
    /// Kept after deactivate (it outlives module starts) so the last change still reaches open pages.
    private weak var runtime: DisplaysRuntimeState?
    private var lastStatus: QueueStatus?

    var isBusy: Bool { running || !waiting.isEmpty }
    var hasPendingTrial: Bool { pending != nil }
    var isSuppressingAutomatic: Bool { SessionGate.uptime() < suppressAutomaticUntil }
    var permanentJournalCount: Int { journal?.permanentCount ?? 0 }
    var hasSessionJournal: Bool { journal?.hasSessionJournal ?? false }

    // MARK: Lifecycle

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        epoch &+= 1
        self.context = context
        self.lifetime = lifetime
        runtime = context.runtime
        journal = RevertJournal()
        journal?.onChange = { [weak self] in self?.noteStatus() }
        journaledLong = nil
        journalMayBeStale = true
        context.guardClient.onReverted = { [weak self] trial, _, _ in
            guard let self, var p = self.pending, trial == p.id else { return }
            p.life.guardDidRevert()
            self.pending = p
            self.panel.dismiss(.revert)
        }
        context.guardClient.onLost = { [weak self] in
            guard let self else { return }
            self.requestTrialRevert(.guardLost, log: "safety helper lost")
            if context.guardClient.isUnprotected {
                context.toasts.show(L("Snaptic’s safety helper stopped. Restart Snaptic to stay protected."))
            }
        }
        context.sessionGate.observeEvents(lifetime: lifetime) { [weak self] event in
            switch event {
            case .willSleep, .resignedActive, .locked, .screensDidSleep:
                self?.requestTrialRevert(.session, log: "sleep or lock")
            default: break
            }
        }
        context.diagnostics.register(self, section: L("Transactions"), lifetime: lifetime)
        layoutFactsChanged()
    }

    /// Synchronous (PLAN §3.3): a pending trial resolves now (undone, or committed when the
    /// user's Keep was underway), displays Snaptic disabled are re-enabled (FIXES-R1 B5), and
    /// the session journal is cleared. The trial's own task wakes up and touches nothing.
    func deactivate() {
        guard active else { return }
        if var p = pending, let ctx = context {
            let action = p.life.stop()
            if let end = p.life.end { stopped = (p.token, end) }
            switch action {
            case .undo:
                _ = applyUndoNow(p.undo, permanent: p.keptPermanently, ctx: ctx)
                if p.keepWritten { forgetKept(p.changes, ctx: ctx) }
                ctx.guardClient.disarm(p.id)
                EventLog.shared.record(.transaction, "Pending trial reverted (Displays stopped)")
            case .commit:
                // FIXES-R2 N6: the user chose Keep, so Displays stopping finishes the Keep the
                // same way the trial task would have: Keep batches, kept modes remembered
                // (config persists them), commit. Never reverted, never left half-kept.
                if !p.keepWritten { writeKeep(&p, ctx: ctx) }
                ctx.guardClient.commit(p.id)
                EventLog.shared.record(.transaction, "Trial kept (Displays stopped during Keep)")
            case .none:
                break
            }
            journal?.resolvePermanent(trial: p.id)
        }
        pending = nil
        if panel.isShowing {
            panel.dismiss(.revert)
            panelObservers.forEach { $0.1(false) }
        }
        // FIXES-R1 B5: don't leave this to a controller's Task, which submit refuses from now on.
        if let ctx = context {
            let ops = reenableOps(ctx)
            if !ops.isEmpty {
                let n = applyUndoNow(ops, permanent: false, ctx: ctx)
                EventLog.shared.record(.transaction, "Re-enabled \(n) displays Snaptic disconnected")
            }
        }
        journal?.clearSession()
        journaledLong = nil
        active = false
        epoch &+= 1
        running = false
        longArmWork?.cancel()
        longArmWork = nil
        let w = waiting
        waiting = []
        w.forEach { $0.resume() }
        context?.guardClient.onReverted = nil
        context?.guardClient.onLost = nil
        context = nil
        lifetime = nil
        noteStatus()
    }

    // MARK: Observability (0.3 §4.5)

    private struct QueueStatus: Equatable {
        let pending: Bool
        let sessionJournal: Bool
        let permanentOps: Int
    }

    private func noteStatus() {
        let now = QueueStatus(pending: pending != nil, sessionJournal: hasSessionJournal, permanentOps: permanentJournalCount)
        guard now != lastStatus else { return }
        lastStatus = now
        runtime?.revision(.diagnostics).bump()
    }

    private func isCurrent(_ epoch: UInt64) -> Bool { active && epoch == self.epoch }

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
        let epoch = self.epoch
        let ticket = supersession.ticket(user: !request.automatic)
        // A user request resolves an earlier trial as Revert first (PLAN §4.3), in whatever
        // phase it is (FIXES-R1 B1): it never waits out that trial's countdown.
        if !request.automatic, let p = pending, requestTrialRevert(.newRequest, log: "new request"), p.applied {
            context?.toasts.show(L("The previous display change was reverted."))
        }
        if running {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiting.append(c) }
            guard isCurrent(epoch) else { return .failed(L("Displays are turned off.")) }
        } else {
            running = true
        }
        let outcome = await execute(request, ticket: ticket, epoch: epoch)
        if isCurrent(epoch) {
            if waiting.isEmpty {
                running = false
                layoutFactsChanged()
            } else {
                waiting.removeFirst().resume()
            }
        }
        return outcome
    }

    /// Resolves a pending trial as Revert (sleep, lock, quit, new request, panic), in any
    /// phase before Keep; panic also overrides a Keep in progress. False when none counted.
    @discardableResult
    private func requestTrialRevert(_ cause: TrialRevertReason, log: String) -> Bool {
        guard var p = pending else { return false }
        guard p.life.requestRevert(cause) else { return false }
        pending = p
        // The panel may not be up yet (arming, applying, settling): the trial task checks
        // the lifecycle at every step, so the request isn't lost (FIXES-R1 B1).
        if panel.isShowing { panel.dismiss(.revert) }
        EventLog.shared.record(.transaction, "Pending trial revert requested (\(cause.rawValue): \(log))")
        return true
    }

    private func execute(_ req: TransactionRequest, ticket: UInt64, epoch: UInt64) async -> TransactionOutcome {
        guard isCurrent(epoch), let ctx = context else { return .failed(L("Displays are turned off.")) }
        let off = TransactionOutcome.failed(L("Displays are turned off."))
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
            do { try await prepare() } catch { return .failed(L("Couldn’t prepare the change.")) }
            guard isCurrent(epoch) else { return off }
        }
        guard let before = ctx.registry.snapshot() else { return off }

        // Captured displays (games, presentations) are never reconfigured (PLAN §4.4).
        for id in Set(req.changes.map(\.displayID)) where Self.isCaptured(id) {
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
                return .failed(L("This macOS version doesn’t let Snaptic change that."))
            }
        }

        // Risk = max(caller, classifier). A restore re-establishes a state the user kept: it
        // stays restore (journaled, long-armed, invariant-checked, no panel).
        let classified = RiskClassifier.classify(changes, current: before, facts: { [weak self] id in
            self?.modeFacts(id, ctx: ctx) ?? ModeFacts()
        }, setting: ctx.config.value.safety.confirmResolution)
        let risk: TransactionRisk = req.risk == .restore ? .restore : max(req.risk, TransactionRisk(classified))

        if risk == .trial, changes.contains(where: \.isMonitorPanel) {
            let ok = await ctx.guardClient.ensureRunning()
            guard isCurrent(epoch) else { return off }
            guard ok, ctx.guardClient.canMonitorPanel else { return .failed(L("Safety helper can’t revert this.")) }
        }

        // Invariants on the predicted layout.
        let predicted = Invariants.predict(before, applying: changes)
        let needsLong = !Invariants.requiredLongArm(predicted).reasons.subtracting(Invariants.requiredLongArm(before).reasons).isEmpty
        var guardOK = true
        if needsLong || risk != .low {
            guardOK = await ctx.guardClient.ensureRunning()
            guard isCurrent(epoch) else { return off }
        }
        let invariantContext = InvariantContext(guardAvailable: guardOK, dimToBlack: [],
                                                unattended: risk == .restore || req.automatic)
        let violations = Invariants.violations(before: before, changes: changes, context: invariantContext)
        if !violations.isEmpty {
            EventLog.shared.record(.transaction, "Refused \(changes.count) changes: \(violations.count) invariants")
            // W9: the same text ManagedTransactions shows (identical toasts merge), with a way out.
            if violations.first == .guardNotArmed { offerRestart(L("Safety helper unavailable"), req: req, ctx: ctx) }
            report(req, before: before, risk: risk, outcome: .refused(violations))
            return .refused(violations)
        }

        let undo = UndoPlanner.undo(for: changes, before: before)
        // FIXES-R3 7: more undo steps than one guard message carries can't be protected.
        if undo.count > GuardProtocol.maxUndoOps {
            EventLog.shared.record(.transaction, "Refused \(undo.count) undo steps: over the guard's limit")
            return .failed(L("Too many display changes at once."))
        }
        if risk == .trial {
            let outcome = await runTrial(req, changes: changes, undo: undo, before: before, ticket: ticket, ctx: ctx)
            if isCurrent(epoch) { report(req, before: before, risk: risk, outcome: outcome) }
            return outcome
        }

        // Protection before applying (fail closed).
        let long = Invariants.requiredLongArm(predicted)
        if risk == .restore {
            // FIXES-R1 B2: journal a restore only when it leaves something to undo after a crash.
            if !long.undo.isEmpty {
                let ops = UndoPlanner.merge(long.undo, undo)
                guard journal?.writeSession(undo: ops, restoreColorSync: long.restoreColorSync, trialID: nil,
                                            live: before) == true else {
                    return .failed(L("Couldn’t save the undo information."))
                }
                journaledLong = ops
            }
            if !long.isEmpty {
                let ok = await ctx.guardClient.setLongAndWait(long.undo, restoreColorSync: long.restoreColorSync)
                guard isCurrent(epoch) else { return off }
                guard ok else {
                    clearJournal()
                    layoutFactsChanged()
                    return guardUnavailable(req, ctx: ctx)
                }
            }
        } else if needsLong {
            let ok = await ctx.guardClient.setLongAndWait(long.undo, restoreColorSync: long.restoreColorSync)
            guard isCurrent(epoch) else { return off }
            guard ok else { return guardUnavailable(req, ctx: ctx) }
        }

        // Apply (CG only: MonitorPanel changes that aren't already applied are trials).
        let scopeFor: (DisplayChange) -> ConfigScope = { [weak self] c in
            self?.finalScope(for: c, request: req, ctx: ctx) ?? .forSession
        }
        let applied = await applyStaged(changes, scope: scopeFor, ctx: ctx, onStage: { _ in }, shouldStop: { [weak self] in
            self?.isCurrent(epoch) != true
        })
        guard isCurrent(epoch) else { return off }
        if let failure = applied.failure ?? (applied.stopped ? L("Displays are turned off.") : nil) {
            _ = applyUndoNow(undo, permanent: false, ctx: ctx)
            clearJournal()
            layoutFactsChanged()
            EventLog.shared.record(.transaction, "Apply failed and was undone")
            report(req, before: before, risk: risk, outcome: .failed(failure))
            return .failed(failure)
        }
        noteApplied(changes, undo: undo, ctx: ctx)
        // The session journal now follows the long-armed set (updateLongArm).
        layoutFactsChanged()
        report(req, before: before, risk: risk, outcome: .applied)
        return .applied
    }

    // MARK: Trial

    /// Arm → apply → settle → panel → Keep or Revert, each step gated by the lifecycle
    /// (FIXES-R1 B1/B4). Exactly one of the Keep/Revert endings runs, once.
    private func runTrial(_ req: TransactionRequest, changes: [DisplayChange], undo: [UndoOp], before: LayoutSnapshot,
                          ticket: UInt64, ctx: DisplaysContext) async -> TransactionOutcome {
        // A newer user request arrived before anything went out: skip this one entirely.
        if supersession.isSuperseded(ticket) {
            EventLog.shared.record(.transaction, "Trial skipped: a newer request replaced it")
            return .reverted(Self.message(for: .newRequest))
        }
        trialSerial &+= 1
        let token = trialSerial
        let trialID = ctx.guardClient.makeTrialID()
        pending = PendingTrial(token: token, id: trialID, undo: undo, changes: changes, before: before)

        // Protection before applying (fail closed): journal, permanent ops, guard arm.
        // The journal also carries what is long-armed right now, so a crash mid-trial still
        // re-enables displays Snaptic disconnected earlier (merge keeps the oldest restore).
        let journalOps = UndoPlanner.merge(Invariants.requiredLongArm(before).undo, undo)
        guard journal?.writeSession(undo: journalOps, restoreColorSync: false, trialID: trialID, live: before) == true,
              journal?.addPermanent(trial: trialID, ops: undo) == true else {
            journal?.clearSession()
            journal?.resolvePermanent(trial: trialID)
            journaledLong = nil
            pending = nil
            layoutFactsChanged()
            return .failed(L("Couldn’t save the undo information."))
        }
        journaledLong = nil
        let panelSeconds = Double(ctx.config.value.safety.confirmSeconds)
        let armed = await ctx.guardClient.armTrial(trialID, undo: undo,
                                                   deadlineSeconds: GuardProtocol.trialDeadline(panelSeconds: panelSeconds))
        guard isTrialCurrent(token) else { return stoppedOutcome(token) }
        guard armed else {
            ctx.guardClient.disarm(trialID)
            journal?.clearSession()
            journal?.resolvePermanent(trial: trialID)
            pending = nil
            layoutFactsChanged()
            return guardUnavailable(req, ctx: ctx)
        }

        // Apply, with the trial scope; stops between stages when a revert is requested.
        switch step(token, { $0.advance(to: .applying) }) {
        case .abandon: return stoppedOutcome(token)
        case .revert(let why): return await revertTrial(token, why, req: req, ctx: ctx)
        case .proceed: break
        }
        pending?.applied = true
        // N8: each stage that may take a while first moves the guard's deadline past itself.
        let guardClient = ctx.guardClient
        let applied = await applyStaged(changes, scope: { _ in Self.trialScope }, ctx: ctx, onStage: { cap in
            guardClient.extend(trialID, seconds: cap + 10)
        }, shouldStop: { [weak self] in
            self?.trialShouldStop(token) ?? true
        })
        if let failure = applied.failure {
            EventLog.shared.record(.transaction, "Trial apply failed; reverting")
            switch step(token, { $0.applyFailed() }) {
            case .abandon: return stoppedOutcome(token)
            case .revert(let why):
                let outcome = await revertTrial(token, why, req: req, ctx: ctx)
                if why == .applyFailed, case .reverted = outcome { return .failed(failure) }
                return outcome
            case .proceed: return .failed(failure)
            }
        }
        if !applied.stopped { noteApplied(changes, undo: undo, ctx: ctx) }

        // Settle (≤ 5 s) so the countdown starts on a visible screen; the guard deadline
        // was set before the apply, so move it past the settle first.
        switch step(token, { $0.advance(to: .settling) }) {
        case .abandon: return stoppedOutcome(token)
        case .revert(let why): return await revertTrial(token, why, req: req, ctx: ctx)
        case .proceed: break
        }
        ctx.guardClient.extend(trialID, seconds: Self.settleCapSeconds + 10)
        await settle(changes.map(\.displayID), ctx: ctx, token: token)

        // The panel. FIXES-R1 B4: the guard deadline becomes now + panel + 10 s right before it shows.
        switch step(token, { $0.advance(to: .confirming) }) {
        case .abandon: return stoppedOutcome(token)
        case .revert(let why): return await revertTrial(token, why, req: req, ctx: ctx)
        case .proceed: break
        }
        let choice: TrialPanelChoice
        if let skipped = TrialPanelChoice.withoutPanel(skipConfirmation: req.skipConfirmation, automatic: req.automatic) {
            // FIXES-R3 1: `--yes` the user allowed: keep now. The guard is armed and the
            // journal written exactly as for a panel trial; Keep commits intent as usual.
            EventLog.shared.record(.transaction, "Trial confirmed from the command line (no panel)")
            choice = skipped
        } else {
            ctx.guardClient.extend(trialID, seconds: GuardProtocol.panelExtension(panelSeconds: panelSeconds))
            panelObservers.forEach { $0.1(true) }
            let result = await panel.present(label: req.label, seconds: panelSeconds, interactive: req.interactive) { [weak self] in
                guard let snap = self?.context?.registry.snapshot() else { return [] }
                return Invariants.panelHosts(snap)
            }
            if isTrialCurrent(token) { panelObservers.forEach { $0.1(false) } }
            switch result {
            case .keep: choice = .keep
            case .revert: choice = .revert
            case .timeout: choice = .timeout
            }
        }
        switch step(token, { $0.panelClosed(choice) }) {
        case .abandon: return stoppedOutcome(token)
        case .revert(let why): return await revertTrial(token, why, req: req, ctx: ctx)
        case .proceed: break
        }
        return await keepTrial(token, req: req, ctx: ctx)
    }

    /// Keep: commit intent, re-apply with the final scope (never skipping, R5.2), afterKeep.
    /// Panic or a guard revert arriving meanwhile still turns it into a revert.
    private func keepTrial(_ token: UInt64, req: TransactionRequest, ctx: DisplaysContext) async -> TransactionOutcome {
        guard let id = pending?.id, pending?.token == token else { return stoppedOutcome(token) }
        _ = await ctx.guardClient.commitIntentAndWait(id)
        switch step(token, { $0.checkpoint() }) {
        case .abandon: return stoppedOutcome(token)
        case .revert(let why): return await revertTrial(token, why, req: req, ctx: ctx)
        case .proceed: break
        }
        guard var p = pending, p.token == token else { return stoppedOutcome(token) }
        writeKeep(&p, ctx: ctx)
        pending = p
        if let afterKeep = req.afterKeep {
            await afterKeep()
        }
        switch step(token, { $0.finishKeep() }) {
        case .abandon:
            return stoppedOutcome(token)
        case .revert(let why):
            forgetKept(p.changes, ctx: ctx)
            return await revertTrial(token, why, req: req, ctx: ctx)
        case .proceed:
            break
        }
        // N5: the journal and the guard's long-armed set cover the kept layout before the
        // guard forgets the trial (the pipe is ordered: `long` is handled before `commit`).
        handOverToLongArm(Invariants.predict(p.before, applying: p.changes), ctx: ctx)
        ctx.guardClient.commit(p.id)
        journal?.resolvePermanent(trial: p.id)
        pending = nil
        suppressAutomaticUntil = SessionGate.uptime() + Self.keepSuppressSeconds
        layoutFactsChanged()
        EventLog.shared.record(.transaction, "Trial kept")
        return .kept
    }

    /// The single revert ending: staged CAS undo (a no-op for whatever the guard or panic
    /// already undid), afterRevert, disarm, journals.
    private func revertTrial(_ token: UInt64, _ why: TrialRevertReason, req: TransactionRequest,
                             ctx: DisplaysContext) async -> TransactionOutcome {
        guard let p = pending, p.token == token else { return stoppedOutcome(token) }
        // Our own staged undo is underway: keep the guard's deadline from racing it (its
        // hang rule still covers a stall here).
        if !p.life.guardReverted { ctx.guardClient.extend(p.id, seconds: 30) }
        let guardClient = ctx.guardClient
        let trialID = p.id
        let guardReverted = p.life.guardReverted
        _ = await revertStaged(p.undo, permanent: p.keptPermanently, ctx: ctx, onStage: { cap in
            if !guardReverted { guardClient.extend(trialID, seconds: cap + 10) }
        }, shouldStop: { [weak self] in self?.isTrialCurrent(token) != true })
        guard isTrialCurrent(token) else { return stoppedOutcome(token) }
        if let afterRevert = req.afterRevert {
            await afterRevert()
            guard isTrialCurrent(token) else { return stoppedOutcome(token) }
        }
        _ = step(token) { $0.finishRevert() ? .proceed : .abandon }
        // N5: whatever the restored layout still needs long-armed is journaled and handed to
        // the guard before it forgets the trial.
        handOverToLongArm(ctx.registry.snapshot() ?? p.before, ctx: ctx)
        ctx.guardClient.disarm(p.id)
        journal?.resolvePermanent(trial: p.id)
        pending = nil
        suppressAutomaticUntil = SessionGate.uptime() + Self.keepSuppressSeconds
        layoutFactsChanged()
        EventLog.shared.record(.transaction, "Trial reverted (\(why.rawValue))")
        return .reverted(Self.message(for: why))
    }

    private func isTrialCurrent(_ token: UInt64) -> Bool { active && pending?.token == token }

    /// The trial task should stop what it's doing and come back to a checkpoint.
    private func trialShouldStop(_ token: UInt64) -> Bool {
        guard isTrialCurrent(token), let p = pending else { return true }
        return p.life.isRevertRequested
    }

    /// Runs one lifecycle transition on the pending trial `token` (`.abandon` if it's gone).
    private func step(_ token: UInt64, _ body: (inout TrialLifecycle) -> TrialStep) -> TrialStep {
        guard active, var p = pending, p.token == token else { return .abandon }
        let result = body(&p.life)
        pending = p
        return result
    }

    /// What a trial's task returns after `deactivate()` resolved it.
    private func stoppedOutcome(_ token: UInt64) -> TransactionOutcome {
        if let s = stopped, s.token == token, s.end == .kept { return .kept }
        return .reverted(L("Displays were turned off, so the change was reverted."))
    }

    static func message(for reason: TrialRevertReason) -> String {
        switch reason {
        case .timeout: return L("No confirmation, so the change was reverted.")
        case .newRequest: return L("A newer display change replaced this one.")
        case .session: return L("The Mac went to sleep or was locked, so the change was reverted.")
        case .panic: return L("Restore All Displays reverted the change.")
        case .guardReverted: return L("The safety helper reverted the change.")
        case .guardLost: return L("The safety helper stopped, so the change was reverted.")
        case .applyFailed: return L("The display refused the change.")
        case .stopped: return L("Displays were turned off, so the change was reverted.")
        case .user: return L("The change was reverted.")
        }
    }

    /// The Keep batches (final scope, never skipping, R5.2) and the kept modes remembered.
    /// Synchronous, so `deactivate()` can finish a Keep the trial task didn't get to (N6).
    private func writeKeep(_ p: inout PendingTrial, ctx: DisplaysContext) {
        let cg = p.changes.filter { !$0.isMonitorPanel }
        let (permanent, session) = CGConfig.keepBatches(cg)
        ctx.guardClient.busy(seconds: 5)
        let virtualsOnline = ctx.registry.cachedSnapshot()?.entries.contains { $0.transport == .snapticVirtual } ?? false
        let permScope: ConfigScope = virtualsOnline && !permanent.allSatisfy({ Self.isPhysicalMode($0, ctx: ctx) })
            ? .forSession : .permanently
        let functions = cgFunctions(ctx)
        let hidden = hiddenModes(for: cg, ctx: ctx)
        if !permanent.isEmpty {
            // Marked before the call: a partial permanent write must be undone permanently too.
            if permScope == .permanently { p.keptPermanently = true }
            _ = CGConfig.apply(permanent, scope: permScope, functions: functions, hiddenModes: hidden)
        }
        if !session.isEmpty { _ = CGConfig.apply(session, scope: .forSession, functions: functions, hiddenModes: hidden) }
        rememberKept(p.changes, ctx: ctx)
        p.keepWritten = true
    }

    /// FIXES-R2 N5: before the guard forgets a trial (commit / disarm), the session journal
    /// and the guard's long-armed set already describe what `layout` needs, so there is no
    /// moment where a crash leaves a disabled display or a mirror without a way back.
    private func handOverToLongArm(_ layout: LayoutSnapshot, ctx: DisplaysContext) {
        let long = Invariants.requiredLongArm(layout)
        if long.undo.isEmpty {
            clearJournal()
        } else if journal?.writeSession(undo: long.undo, restoreColorSync: long.restoreColorSync, trialID: nil,
                                        live: layout) == true {
            journaledLong = long.undo
        } else {
            // The trial's journal would undo the result at the next launch: never leave it.
            clearJournal()
        }
        if !long.isEmpty || ctx.guardClient.hasLongState {
            ctx.guardClient.setLong(long.undo, restoreColorSync: long.restoreColorSync)
        }
    }

    /// W9: the guard couldn't be reached. The text says why; a user request also gets a toast
    /// with "Restart Snaptic" (ManagedTransactions shows the same text, and identical toasts merge).
    private func guardUnavailable(_ req: TransactionRequest, ctx: DisplaysContext) -> TransactionOutcome {
        let text = ctx.guardClient.lastFailure.map { L("Safety helper unavailable: \($0)") } ?? L("Safety helper unavailable.")
        offerRestart(text, req: req, ctx: ctx)
        return .failed(text)
    }

    private func offerRestart(_ text: String, req: TransactionRequest, ctx: DisplaysContext) {
        guard !req.automatic, let lifetime else { return }
        let relauncher = ctx.relauncher
        ctx.toasts.show(text, action: ToastAction(title: L("Restart Snaptic"), perform: {
            relauncher.relaunch(reason: "safety helper unavailable")
        }), lifetime: lifetime)
    }

    private func clearJournal() {
        journal?.clearSession()
        journaledLong = nil
    }

    /// Waits until the changed displays are active again and the layout has been quiet for
    /// 2 s (capped at 5 s), so the countdown starts on a visible screen.
    /// Returns early when a revert is requested (FIXES-R1 B1: checked on every pass).
    private func settle(_ ids: [UInt32], ctx: DisplaysContext, token: UInt64) async {
        let start = SessionGate.uptime()
        while SessionGate.uptime() - start < Self.settleCapSeconds {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if trialShouldStop(token) { return }
            let snap = ctx.registry.snapshot()
            let allShown = ids.allSatisfy { id in snap?.entry(id).map { $0.isEnabled } ?? true }
            if allShown && ctx.registry.quietSeconds() >= Self.settleSeconds && !ctx.registry.isReconfiguring { return }
        }
    }

    // MARK: Apply

    private struct ApplyResult {
        var failure: String?
        /// `shouldStop` said so between stages: the rest wasn't applied.
        var stopped = false
    }

    /// HDR → quiet → rotation (poll ≤ 10 s) → quiet → CG batches (modes re-resolved) by scope.
    /// `shouldStop` is asked after every await, so a revert request (or Displays stopping)
    /// keeps the remaining stages from going out.
    /// `onStage(cap)` runs before each stage that may take up to `cap` seconds (N8: a trial
    /// extends the guard's deadline there).
    private func applyStaged(_ changes: [DisplayChange], scope: (DisplayChange) -> ConfigScope,
                             ctx: DisplaysContext, onStage: (Double) -> Void, shouldStop: () -> Bool) async -> ApplyResult {
        let hdr = changes.filter { if case .hdr = $0 { return true } else { return false } }
        let underscan = changes.filter { if case .underscan = $0 { return true } else { return false } }
        let rotation = changes.filter { if case .rotation = $0 { return true } else { return false } }
        for c in hdr + underscan {
            guard CGConfig.applyMonitorPanel(c) else { return ApplyResult(failure: L("The display refused the change.")) }
        }
        if !hdr.isEmpty {
            onStage(8)
            await waitQuiet(ctx, quiet: 1.5, cap: 8)
            if shouldStop() { return ApplyResult(stopped: true) }
        }
        if !rotation.isEmpty { onStage(10 + 6) }
        for c in rotation {
            guard case .rotation(let id, let degrees) = c, CGConfig.applyMonitorPanel(c) else {
                return ApplyResult(failure: L("The display refused the change."))
            }
            let target = Invariants.normalizedRotation(degrees)
            let start = SessionGate.uptime()
            while Invariants.normalizedRotation(Int(CGDisplayRotation(id).rounded())) != target {
                if SessionGate.uptime() - start > 10 { return ApplyResult(failure: L("The display didn’t rotate.")) }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if shouldStop() { return ApplyResult(stopped: true) }
            }
        }
        if !rotation.isEmpty {
            await waitQuiet(ctx, quiet: 1, cap: 6)
            if shouldStop() { return ApplyResult(stopped: true) }
        }

        let cg = changes.filter { !$0.isMonitorPanel }
        guard !cg.isEmpty else { return ApplyResult() }
        onStage(5)
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

    /// Staged CAS revert with settling between stages. Stops when `shouldStop` (Displays
    /// stopped: `deactivate()` already undid everything synchronously).
    /// `permanent`: the trial's Keep already wrote modes, origins and main `.permanently`,
    /// so the revert writes those back `.permanently` as well, even where the live value is
    /// already restored for the session (FIXES-R2 N4). Everything else stays CAS, `.forSession`.
    private func revertStaged(_ undo: [UndoOp], permanent: Bool, ctx: DisplaysContext, onStage: (Double) -> Void,
                              shouldStop: () -> Bool) async -> (applied: Int, skipped: Int) {
        var applied = 0, skipped = 0
        let functions = cgFunctions(ctx)
        for (stage, ops) in UndoPlanner.stages(undo) {
            if shouldStop() { break }
            guard let live = ctx.registry.snapshot() else { break }
            let pendingOps = Self.pendingUndo(stage, ops, live: live, permanent: permanent)
            skipped += ops.count - pendingOps.count
            guard !pendingOps.isEmpty else { continue }
            let cap: Double = stage == .monitorPanel ? 6 : 4
            onStage(cap + 5)
            if stage == .monitorPanel {
                let changes = pendingOps.compactMap(UndoPlanner.change(for:))
                for c in changes { if CGConfig.applyMonitorPanel(c) { applied += 1 } else { skipped += 1 } }
                noteApplied(changes, undo: [], ctx: ctx)
            } else {
                for (scope, batch) in Self.undoBatches(pendingOps, permanent: permanent) {
                    let changes = batch.compactMap(UndoPlanner.change(for:))
                    guard !changes.isEmpty else { continue }
                    ctx.guardClient.busy(seconds: 5)
                    let r = CGConfig.apply(changes, scope: scope, functions: functions, hiddenModes: hiddenModes(for: changes, ctx: ctx))
                    if r.ok { applied += r.applied } else { skipped += changes.count }
                    noteApplied(changes, undo: [], ctx: ctx)
                }
            }
            await waitQuiet(ctx, quiet: 1, cap: cap)
        }
        return (applied, skipped)
    }

    /// Synchronous CAS undo (deactivate/quit and failed applies): no settling. `permanent`
    /// as in `revertStaged`.
    private func applyUndoNow(_ undo: [UndoOp], permanent: Bool, ctx: DisplaysContext) -> Int {
        var applied = 0
        let functions = cgFunctions(ctx)
        for (stage, ops) in UndoPlanner.stages(undo) {
            guard let live = ctx.registry.snapshot() else { break }
            let pendingOps = Self.pendingUndo(stage, ops, live: live, permanent: permanent)
            if stage == .monitorPanel {
                let changes = pendingOps.compactMap(UndoPlanner.change(for:))
                for c in changes where CGConfig.applyMonitorPanel(c) { applied += 1 }
                noteApplied(changes, undo: [], ctx: ctx)
            } else {
                for (scope, batch) in Self.undoBatches(pendingOps, permanent: permanent) {
                    let changes = batch.compactMap(UndoPlanner.change(for:))
                    guard !changes.isEmpty else { continue }
                    let r = CGConfig.apply(changes, scope: scope, functions: functions)
                    applied += r.applied
                    noteApplied(changes, undo: [], ctx: ctx)
                }
            }
        }
        return applied
    }

    private static func pendingUndo(_ stage: UndoStage, _ ops: [UndoOp], live: LayoutSnapshot, permanent: Bool) -> [UndoOp] {
        if stage == .monitorPanel { return JournalApplier.monitorPanelPending(ops, live: live) }
        return permanent ? UndoPlanner.pendingAfterPermanentKeep(ops, live: live) : UndoPlanner.pending(ops, live: live)
    }

    /// One CG batch per scope: after a permanent Keep, modes/origins/main go `.permanently`
    /// (first, like the Keep), the rest `.forSession`.
    private static func undoBatches(_ ops: [UndoOp], permanent: Bool) -> [(ConfigScope, [UndoOp])] {
        guard permanent else { return [(.forSession, ops)] }
        let perm = ops.filter(\.isPermanentOnKeep)
        let session = ops.filter { !$0.isPermanentOnKeep }
        return [(.permanently, perm), (.forSession, session)].filter { !$0.1.isEmpty }
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

    /// A Keep that panic (or the guard) overturned: its modes aren't known-good after all.
    private func forgetKept(_ changes: [DisplayChange], ctx: DisplaysContext) {
        var value = ctx.config.value
        for c in changes {
            guard case .mode(let id, let ref) = c, let key = ctx.registry.key(forDisplayID: id) else { continue }
            value.safety.keptModes[key]?.forget(ref)
        }
        if value != ctx.config.value { ctx.config.value = value }
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

    /// A display is captured when another process covers it with a window at or above the
    /// shielding level (CGDisplayIsCaptured is unavailable in the SDK).
    static func isCaptured(_ id: UInt32) -> Bool {
        let bounds = CGDisplayBounds(id)
        guard bounds.width > 0, let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let shield = Int(CGShieldingWindowLevel())
        let me = getpid()
        for w in list.prefix(1000) {
            guard let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, layer >= shield,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != me,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            if rect.contains(bounds) { return true }
        }
        return false
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
        syncLongJournal(req, live: snap)
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

    /// FIXES-R1 B2: with no trial pending or transaction running, the session journal holds
    /// exactly the long-armed undo (written when it changes, removed when nothing is armed),
    /// so a journal is never replayed at the next launch for a state that no longer exists.
    private func syncLongJournal(_ req: LongArmRequirement, live: LayoutSnapshot) {
        guard pending == nil, !running, waiting.isEmpty, let journal else { return }
        if req.undo.isEmpty {
            if journaledLong != nil || journalMayBeStale {
                journal.clearSession()
                journaledLong = nil
                journalMayBeStale = false
            }
        } else if journaledLong != req.undo {
            if journal.writeSession(undo: req.undo, restoreColorSync: req.restoreColorSync, trialID: nil, live: live) {
                journaledLong = req.undo
                journalMayBeStale = false
            }
        }
    }

    /// Re-enable ops for every display Snaptic disabled (foreign, AirPlay, DisplayLink and
    /// Sidecar untouched).
    private func reenableOps(_ ctx: DisplaysContext) -> [UndoOp] {
        guard let snap = ctx.registry.snapshot() else { return [] }
        return snap.entries.filter { $0.disabledBySnaptic && !$0.isEnabled && $0.isPhysical }.map { e in
            UndoOp(displayID: e.id, fingerprint: e.fingerprint, property: .enabled, restore: .bool(true), expected: .bool(false))
        }
    }

    // MARK: Panic support

    /// Reverts modes Snaptic set in the last 60 s (CAS), clears their known-good entries,
    /// and re-enables displays Snaptic disabled. Bypasses rate limits. Returns ops applied.
    @discardableResult
    func panicRevert() -> Int {
        guard let ctx = context else { return 0 }
        // Any phase, even a Keep being written: panic never ends with the trial kept (FIXES-R1 B1).
        requestTrialRevert(.panic, log: "Restore All Displays")
        let now = SessionGate.uptime()
        let modes = recentModes.filter { now - $0.at <= Self.recentModeWindow }.map(\.op)
        recentModes = []
        let ops = UndoPlanner.merge([], modes) + reenableOps(ctx)
        var value = ctx.config.value
        for op in modes {
            guard case .mode(let m) = op.expected, let key = ctx.registry.key(forDisplayID: op.displayID) else { continue }
            value.safety.keptModes[key]?.forget(m)
        }
        if value != ctx.config.value { ctx.config.value = value }
        let applied = applyUndoNow(ops, permanent: false, ctx: ctx)
        layoutFactsChanged()
        return applied
    }

    // MARK: Diagnostics

    func diagnostics() -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Queue", isBusy ? "busy" : "idle"),
            ("Pending trial", pending.map { "\($0.life.phase)" } ?? "none"),
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
