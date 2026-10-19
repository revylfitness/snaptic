import AppKit
import Combine
import SnapticKit

// Manual sessions, the hold stack, guards and arbitration (owner: G; PLAN 0.3 §2.4–§2.6, §2.10, §2.12, N17, R5-1,
// R5-4, R5-6, R5-7, R5-10, R5-14). The pure decisions live in Kit (AwakeStartRules, AwakeTurnOff, AwakeReminders,
// AwakeTick, AwakePointerPrompt, AwakeSystemPolicy, AwakeGuards, AwakeArbiter, TaskQuiet); this controller performs
// their effects: the one assertion, toasts, history ends, the snapshot. The only file that assigns `activityGate`
// (lint L16), always through `applying(_:)`.

/// A manual session or a hold that ended.
enum AwakeEndedItem: Equatable { case session(AwakeSession), hold(AwakeHold) }

/// What GuardsController shows for a guard evaluation that doesn't end anything.
enum AwakeGuardNotice: Equatable { case warn(AwakeEndReason), batteryUnreadable }

@MainActor final class SessionController: AwakeFeatureController {
    static var id: AwakeControllerID { .sessions }
    weak var context: AwakeContext?

    private(set) var manual: AwakeSession?
    private(set) var holds: [AwakeHold] = []
    /// The runtime gate (§2.3), assigned only here, always through `applying(_:)`.
    private(set) var activityGate = AwakeActivityGate()
    private(set) var guardMemory = GuardMemory()
    /// untilIdle: seconds of the current quiet run (detail line); nil while busy or for other kinds.
    private(set) var quietFor: Double?
    /// Services the running session and holds need beyond features and rules (§2.1, code M7).
    private(set) var dynamicNeeds: AwakeDynamicNeeds = []
    /// AwakeModule re-applies when the needs change (contract request in the step-2 report).
    var onDynamicNeedsChange: (@MainActor (AwakeDynamicNeeds) -> Void)?
    /// The app picker of a menu is open (dynamic need `apps`).
    var appPickerOpen = false { didSet { if appPickerOpen != oldValue { updateNeeds() } } }

    private var lifetime: Lifetime?
    private var effective: Set<AwakeFeature> = []
    private var restored = false
    private let ends = EventFanout<(AwakeEndedItem, AwakeEndReason)>()
    private let awayEnds = EventFanout<AwakeAwayEnd>()
    private let guardNotices = EventFanout<AwakeGuardNotice>()

    /// Ends with the manual session (its toasts, its watchers, untilIdle sampling).
    private var sessionLifetime: Lifetime?
    /// The session started with no explicit options (a preset with "Use default", or the default): a change of
    /// "Keep the display on" applies to it at once (parity M4).
    private var usesDefaultOptions = false
    private var holdLifetimes: [StableID: Lifetime] = [:]
    private var holderNames: [StableID: String?] = [:]

    private var reminders = AwakeReminders()
    /// The last manual session that ended and why (a start that its own first arbitration ended, N2).
    private var lastFinished: (id: StableID, reason: AwakeEndReason)?
    /// The same for holds (review6 N1): `addHold` answers with the end of a hold its first arbitration ended.
    private var lastRemovedHold: (id: StableID, reason: AwakeEndReason)?
    private var prompt = AwakePointerPrompt()
    private var lastPower: PowerFacts?
    private var wasUnreadable = false
    private var lastGoverning: AwakeGoverning = .inactive
    private var lastWritten: AwakeRuntimeSnapshot?
    /// Continuous instant of the last written stop stamp (the heartbeat, F1).
    private var lastStampAt: Double?
    /// Wall start of the current history segment of a resumed session or hold (F1), persisted in the snapshot.
    private var segmentStarts: [StableID: Double] = [:]
    /// The rule session in the snapshot (review6 N2): fixed when that rule becomes the top candidate, so the
    /// snapshot's content doesn't change between heartbeats.
    private var ruleRecord: (record: AwakeRuleRecord, since: Double)?
    /// Refreshes the stop stamp on its own while the snapshot carries one (review6 code N1): arbitrations alone can be
    /// further apart than `heartbeatSeconds` (an indefinite session or a `--pid` hold has no countdown tick).
    private var heartbeatTimer: Timer?
    /// One more arbitration shortly after a lock or unlock hint (N3: the session dictionary may flip after it).
    private var lockRecheckTimer: Timer?
    private var arbitrating = false
    private var arbitrateAgain = false

    private var quietSince: Double?
    private var discardNextSample = false
    private var offConsoleSince: Double?
    private var lockedSince: Double?

    private var tickTimer: Timer?
    private var verifyTimer: Timer?
    private var lastCLINotice: Double?
    /// keepOnWhileActive governs: IdleSampler is watched so the plan follows the idle limit (F6).
    private var idleWatch: Lifetime?
    /// The side of the idle limit the last plan used (true = user active, display kept on).
    private var idleActiveSide: Bool?
    private var commandLineSink: AnyCancellable?
    /// Start Anyway's toast lives until the next start, Turn Off or module stop (R5-1).
    private var startAnywayLifetime: Lifetime?
    private var turnOffToastLifetime: Lifetime?

    static let verifySeconds: TimeInterval = 300
    static let cliNoticeSeconds: Double = 600
    static let quickExitSeconds: Double = 2
    /// While a session, a `--pid` hold or a rule session is in the snapshot, its stop stamp is refreshed at least
    /// this often (`heartbeatTimer`), so a crash is bounded in History too (F1).
    static let heartbeatSeconds: Double = 240
    static let lockRecheckSeconds: TimeInterval = 1

    init() {}

    // MARK: Starting

    func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?,
               source: AwakeSessionSource, overrideGuards: Bool) -> Result<AwakeSession, AwakeRefusal> {
        start(kind, options: options, presetID: presetID, source: source, overrideGuards: overrideGuards,
              preset: presetID.flatMap { context?.config.value.sessions.preset($0) })
    }

    func startPreset(_ id: StableID, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        guard let ctx = context else { return .failure(.unavailable(.featureOff)) }
        let sessions = ctx.config.value.sessions
        let preset = sessions.preset(id) ?? (sessions.defaultPreset.id == id ? sessions.defaultPreset : nil)
        guard let preset else { return .failure(.invalid) }
        return startPresetValue(preset, source: source)
    }

    func startDefault(source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        guard let ctx = context else { return .failure(.unavailable(.featureOff)) }
        return startPresetValue(ctx.config.value.sessions.defaultPreset, source: source)
    }

    private func startPresetValue(_ preset: AwakePreset, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        let p = preset.sanitized()
        var until: Double?
        if case .untilTime(let h, let m) = p.kind { until = AwakeFormat.nextUnix(hour: h, minute: m) }
        guard var kind = p.kind.sessionKind(untilUnixTime: until) else { return .failure(.invalid) }
        if source == .commandLine {
            if case .indefinite = kind { return .failure(.notAllowedFromCLI) }
            kind = AwakeStartRules.cliCapped(kind)
        }
        return start(kind, options: nil, presetID: p.id, source: source, overrideGuards: false, preset: p)
    }

    private func start(_ kind: AwakeSessionKind, options: AwakeSessionOptions?, presetID: StableID?,
                       source: AwakeSessionSource, overrideGuards: Bool,
                       preset: AwakePreset?) -> Result<AwakeSession, AwakeRefusal> {
        guard let ctx = context, lifetime != nil, restored, effective.contains(.sessions) else {
            return .failure(.unavailable(.featureOff))
        }
        let now = AwakeModule.clockNow()
        if let refusal = AwakeStartRules.refusal(kind: kind, source: source, current: manual, now: now) {
            return .failure(refusal)
        }
        if case .whileApp(let bundleID, _) = kind, !AwakeFormat.isRunning(bundleID) { return .failure(.invalid) }

        // Guards apply to every start; Start Anyway (UI only) skips the user floor and Low Power Mode.
        let ui = source.isDirectUserAction
        let override = overrideGuards && ui
        if let facts = ctx.power.facts {
            let (verdict, _) = AwakeGuards.evaluate(facts, previous: lastPower, config: ctx.config.value.guards,
                                                    memory: guardMemory, time: now.continuous, active: false,
                                                    overrideBattery: override)
            if case .end(let reason) = verdict {
                if ui { offerStartAnyway(reason, facts: facts, kind: kind, options: options, presetID: presetID, source: source) }
                return .failure(.guardActive(reason))
            }
        }

        let resolved: AwakeSessionOptions
        let followsDefaults: Bool
        if let options {
            resolved = clamped(options)
            followsDefaults = false
        } else {
            resolved = ctx.config.value.sessions.effectiveOptions(for: kind, preset: preset,
                                                                  effective: ctx.runtime.effectiveFeatures)
            followsDefaults = preset?.options == nil
        }
        let gateEvent: AwakeActivityGate.Event
        switch source {
        case .menu, .settings: gateEvent = .uiStart
        case .hotkey: gateEvent = .hotkeyStart
        case .commandLine, .launch, .rule: gateEvent = .otherStart
        }

        startAnywayLifetime?.end()
        turnOffToastLifetime?.end()
        if let old = manual {
            let replacedTaskBound = old.kind.isTaskBound
            finishManual(.replaced, notify: false, arbitrateAfter: false)
            activityGate = activityGate.applying(.replaced)
            if replacedTaskBound && ui {
                ctx.host.toasts.show(L("Replaced ") + AwakeDetail.quoted(taskTitle(old)) + ".")
            }
        }

        var session = AwakeClock.start(kind, options: resolved, presetID: presetID, source: source, now: now,
                                       id: StableID())
        session.overrideGuards = override
        manual = session
        // After finishManual(.replaced), which resets it for the old session (F7).
        usesDefaultOptions = followsDefaults
        let life = (lifetime ?? ctx.host.lifetime).child()
        sessionLifetime = life
        activityGate = activityGate.applying(gateEvent)
        reminders = AwakeReminders()
        if ui { guardMemory = guardMemory.clearingAssertionHold() }
        quietFor = nil
        quietSince = nil
        EventLog.shared.record(AwakeLogEvent.sessionStarted(kind.historyKind))
        if case .whileApp(let bundleID, _) = kind {
            ctx.config.value.sessions = ctx.config.value.sessions.notingRecentApp(bundleID)
        }
        if source == .commandLine { announceCommandLine(now) }
        watch(session, life: life)
        arbitrate()
        guard let running = manual, running.id == session.id else {
            // Ended inside its own first arbitration (N2): the reply names that end.
            if let last = lastFinished, last.id == session.id { return .failure(.endedAtStart(last.reason)) }
            return .failure(.invalid)
        }
        return .success(running)
    }

    /// Options passed in explicitly (CLI `--display-may-sleep`, Settings' Custom panel) clamped like a preset's.
    private func clamped(_ options: AwakeSessionOptions) -> AwakeSessionOptions {
        var o = options.sanitized()
        let all = context?.runtime.effectiveFeatures ?? []
        if !all.contains(.activity) {
            o.activity = .off
        } else if o.activity == .nudge, !all.contains(.pointerNudge) {
            o.activity = .declare
        }
        return o
    }

    // MARK: Holds (N17)

    /// CLI `awake hold`: the binding was resolved server-side by AwakeAutomation; ProcessWatch is armed here and a
    /// failed arm refuses `.invalid`.
    func addHold(_ binding: HoldBinding, capSeconds: Int) -> Result<AwakeHold, AwakeRefusal> {
        guard let ctx = context, let lifetime, restored, effective.contains(.sessions) else {
            return .failure(.unavailable(.featureOff))
        }
        guard holds.count < AwakeHold.maxHolds else {
            EventLog.shared.record(AwakeLogEvent.holdRefused)
            return .failure(.holdLimit)
        }
        let now = AwakeModule.clockNow()
        if let facts = ctx.power.facts {
            let (verdict, _) = AwakeGuards.evaluate(facts, previous: lastPower, config: ctx.config.value.guards,
                                                    memory: guardMemory, time: now.continuous, active: false,
                                                    overrideBattery: false)
            if case .end(let reason) = verdict { return .failure(.guardActive(reason)) }
        }
        let hold = AwakeClock.hold(binding, capSeconds: capSeconds, now: now, id: StableID())
        let life = lifetime.child()
        let id = hold.id
        let armed = ctx.process.watch(pid: binding.pid, startTime: binding.startTime, lifetime: life) { [weak self] in
            self?.endHold(id, .processExited)
        }
        guard armed else {
            life.end()
            EventLog.shared.record(AwakeLogEvent.holdRefused)
            return .failure(.invalid)
        }
        holds.append(hold)
        holdLifetimes[id] = life
        holderNames[id] = ctx.process.holderName(for: binding.pid)
        EventLog.shared.record(AwakeLogEvent.holdStarted)
        announceCommandLine(now)
        arbitrate()
        guard holds.contains(where: { $0.id == id }) else {
            // Ended inside its own first arbitration (the assertion couldn't be created, review6 N1): the client
            // gets that end and exits instead of waiting on a hold that no longer exists.
            if let last = lastRemovedHold, last.id == id { return .failure(.endedAtStart(last.reason)) }
            return .failure(.invalid)
        }
        return .success(hold)
    }

    func endHold(_ id: StableID, _ reason: AwakeEndReason) {
        guard removeHold(id, reason) else { return }
        arbitrate()
    }

    /// A hold whose holding reply the server refused (held-pool limit, R5-5): it never took effect, so it leaves no
    /// history entry, no end toast and no final line (the client already got the refusal).
    func withdrawHold(_ id: StableID) {
        guard let index = holds.firstIndex(where: { $0.id == id }) else { return }
        holds.remove(at: index)
        holdLifetimes.removeValue(forKey: id)?.end()
        holderNames.removeValue(forKey: id)
        segmentStarts.removeValue(forKey: id)
        EventLog.shared.record(AwakeLogEvent.holdRefused)
        arbitrate()
    }

    /// "End Command-Line Holds" (R5-10): each client gets "Awake hold ended in Snaptic." and exits 0.
    func endAllHolds(_ reason: AwakeEndReason) {
        guard !holds.isEmpty else { return }
        for h in holds { _ = removeHold(h.id, reason) }
        arbitrate()
    }

    /// The holder name for local UI ("Terminal"); nil = the command line.
    func holderName(_ id: StableID) -> String? { holderNames[id] ?? nil }

    @discardableResult
    private func removeHold(_ id: StableID, _ reason: AwakeEndReason) -> Bool {
        guard let index = holds.firstIndex(where: { $0.id == id }) else { return false }
        let hold = holds.remove(at: index)
        lastRemovedHold = (id, reason)
        holdLifetimes.removeValue(forKey: id)?.end()
        let now = AwakeModule.clockNow()
        if reason == .processExited, now.continuous - hold.startedContinuous < Self.quickExitSeconds {
            context?.host.toasts.show(L("Awake stopped: the process it was holding for already ended."))
        }
        EventLog.shared.record(AwakeLogEvent.sessionEnded(reason))
        ends.fire((.hold(hold), reason))
        holderNames.removeValue(forKey: id)
        segmentStarts.removeValue(forKey: id)
        return true
    }

    // MARK: Changing and ending

    /// Manual only.
    func extend(by seconds: Int, source: AwakeSessionSource) -> Result<AwakeSession, AwakeRefusal> {
        guard let m = manual else { return .failure(.invalid) }
        let now = AwakeModule.clockNow()
        guard let extended = AwakeClock.extended(m, by: seconds, now: now) else { return .failure(.invalid) }
        manual = extended
        activityGate = activityGate.applying(.unchanged)
        arbitrate()
        return .success(extended)
    }

    /// Mid-session display toggle: the governing manual session's option, or (for a rule session) an override that
    /// lasts until that rule session ends.
    func setKeepDisplayOn(_ on: Bool) {
        guard let ctx = context else { return }
        let display: AwakeDisplayPolicy = on ? .keepOn : .maySleep
        switch AwakeArbiter.governing(manual: manual, top: ctx.triggers.top, holds: holds) {
        case .manual:
            manual?.options.display = display
            usesDefaultOptions = false
        case .trigger:
            ctx.triggers.setDisplayOverride(display)
        case .holds, .inactive:
            return
        }
        activityGate = activityGate.applying(.unchanged)
        arbitrate()
    }

    /// Whether the governing session keeps the display on (✓ Keep Display On).
    var keepsDisplayOn: Bool {
        switch context?.runtime.governing ?? .inactive {
        case .manual(let s): return s.options.display != .maySleep
        case .trigger(let t): return t.options.display != .maySleep
        case .holds, .inactive: return false
        }
    }

    /// User Turn Off (switch header, Turn Off Keep Awake, status row, `awake.toggle`): ends what governs, then says
    /// what still keeps the Mac awake (R5-10).
    func turnOff(source: AwakeSessionSource) {
        guard let ctx = context else { return }
        startAnywayLifetime?.end()
        turnOffToastLifetime?.end()
        switch AwakeTurnOff.target(AwakeArbiter.governing(manual: manual, top: ctx.triggers.top, holds: holds)) {
        case .nothing:
            return
        case .manual:
            finishManual(.user, notify: false)
        case .trigger(let id):
            ctx.triggers.manualEnd(id)
        case .holds:
            endAllHolds(.user)
        }
        let after = AwakeArbiter.governing(manual: manual, top: ctx.triggers.top, holds: holds)
        guard let notice = AwakeTurnOff.notice(after: after), let lifetime else { return }
        let life = lifetime.child()
        turnOffToastLifetime = life
        switch notice {
        case .rules(let ruleID):
            let name = ctx.config.value.triggers.triggers.first { $0.id == ruleID }?.displayName(AwakeFormat.text) ?? ""
            ctx.host.toasts.show(L("Rules can still keep your Mac awake."), actions: [
                ToastAction(title: L("Turn Off ") + AwakeDetail.quoted(name), isDefault: true) { [weak self] in
                    self?.context?.triggers.manualEnd(ruleID)
                },
                ToastAction(title: L("Pause Rules")) { [weak self] in
                    self?.context?.triggers.pause(seconds: 3_600)
                },
            ], lifetime: life)
        case .holds:
            let names = holds.map { holderNames[$0.id] ?? nil }
            ctx.host.toasts.show(AwakeHolderText.stillKeeping(names), actions: [
                ToastAction(title: L("End Command-Line Holds")) { [weak self] in self?.endAllHolds(.user) },
            ], lifetime: life)
        }
    }

    /// The manual session; a rule session is ended through TriggerController.manualEnd.
    func end(_ reason: AwakeEndReason) {
        guard let ctx = context else { return }
        if manual != nil {
            finishManual(reason)
        } else if let top = ctx.triggers.top {
            ctx.triggers.manualEnd(top.id)
        }
    }

    /// The Keep Awake hotkey: on with the default preset, off = Turn Off.
    func toggleDefault(source: AwakeSessionSource) {
        guard let ctx = context else { return }
        if AwakeArbiter.governing(manual: manual, top: ctx.triggers.top, holds: holds).isActive {
            turnOff(source: source)
        } else {
            _ = startDefault(source: source)
        }
    }

    // MARK: Activity gate (ActivityController)

    /// Pointer movement would act now and the gate is `askOnFirstUse`: the confirmation toast (R5-1).
    func requestPointerConfirmation() {
        guard let ctx = context, let session = manual, activityGate.pointer == .askOnFirstUse, !prompt.isShowing,
              let life = sessionLifetime else { return }
        let sessionID = session.id
        let shown = ctx.host.toasts.show(L("Move the pointer to keep apps active?"), actions: [
            ToastAction(title: L("Allow"), isDefault: true) { [weak self] in self?.answerPointer(allow: true) },
            ToastAction(title: L("Not Now")) { [weak self] in self?.answerPointer(allow: false) },
        ], lifetime: life, remember: false, clickGuard: .confirmation, onDismiss: { [weak self] _ in
            self?.answerPointer(allow: false)
        })
        if let event = prompt.offered(session: sessionID, shown: shown) {
            activityGate = activityGate.applying(event)
        }
        ctx.runtime.pointerConfirmation = prompt.isShowing
    }

    private func answerPointer(allow: Bool) {
        let event = allow ? prompt.allowed(governingManual: manual?.id) : prompt.declined(governingManual: manual?.id)
        if let event { activityGate = activityGate.applying(event) }
        context?.runtime.pointerConfirmation = prompt.isShowing
    }

    /// Activity acted (applies `.acted(now:)`).
    func noteActivityActed(now: Double) {
        activityGate = activityGate.applying(.acted(now: now))
    }

    /// Stop on the first-nudge notice of a menu or Settings start: declare only for this session.
    func declinePointer() {
        activityGate = activityGate.applying(.confirmDeclined)
    }

    // MARK: Restore (§2.1 start order)

    /// Called once from AwakeModule.start, after every needed service is active and before the first arbitrate():
    /// the snapshot was sanitized (other boots, bounds); here pids are re-verified, guards evaluated with live facts,
    /// `source` kept, and the gate gets `.restore`. The stored snapshot is read once, here (its stop stamp bounds
    /// every history end it owes, F1), and never again.
    func restore(_ snapshot: AwakeRuntimeSnapshot) {
        guard let ctx = context, let lifetime, !restored else { return }
        restored = true
        activityGate = activityGate.applying(.restore)
        guardMemory = snapshot.guardMemory
        ctx.triggers.restore(suppressions: snapshot.suppressions.values, pausedUntil: snapshot.pausedUntil)
        let now = AwakeModule.clockNow()
        let behavior = ctx.config.value.sessions.behavior
        let resume = behavior.resumeAfterRestart
        let stored = ctx.state.value

        if var m = snapshot.manual {
            m.overrideGuards = false
            var drop: AwakeEndReason?
            if case .whileApp(let bundleID, _) = m.kind, !AwakeFormat.isRunning(bundleID) { drop = .appQuit }
            if drop == nil, let facts = ctx.power.facts {
                let (verdict, memory) = AwakeGuards.evaluate(facts, previous: nil, config: ctx.config.value.guards,
                                                             memory: guardMemory, time: now.continuous, active: true,
                                                             overrideBattery: false)
                guardMemory = memory
                lastPower = facts
                if case .end(let reason) = verdict { drop = reason }
            }
            if !resume {
                // A quit with resume off recorded the session and left it out of the snapshot; one still here was
                // left by a crash (F1). A snapshot from before stop stamps was written by a quit: recorded already.
                EventLog.shared.record(AwakeLogEvent.restoreDropped)
                if stored.sanitized().stop != nil {
                    awayEnds.fire(stored.restoreEnd(.session(m), reason: .moduleStopped, now: now))
                }
            } else if let reason = drop {
                EventLog.shared.record(AwakeLogEvent.restoreDropped)
                awayEnds.fire(stored.restoreEnd(.session(m), reason: reason, now: now))
                if AwakeEndText.isInterruption(reason) { ctx.runtime.lastEnd = AwakeLastEnd(reason: reason, at: Date()) }
            } else {
                manual = m
                resumeSegment(.session(m), stored: stored, snapshot: snapshot, now: now)
                reminders = snapshot.reminders
                usesDefaultOptions = Self.followsDefaults(m, sessions: ctx.config.value.sessions,
                                                          effective: ctx.runtime.effectiveFeatures)
                let life = lifetime.child()
                sessionLifetime = life
                watch(m, life: life)
            }
        }
        // Ran out while Snaptic wasn't running, or never resumed because the Mac restarted (`.reboot`): recorded at
        // their end, never after Snaptic stopped (F1, F5b).
        for end in stored.awayEnds(now: now, resume: resume) { awayEnds.fire(end) }
        // A rule session a crash cut short (review6 N2); the rule starts a new one if it still holds.
        if let end = stored.ruleEnd(now: now) { awayEnds.fire(end) }
        // R5-14(a): holds need the Awake feature and the host's command line (General) on.
        let commandLineOn = ctx.runtime.isEffective(.commandLine) && ctx.host.signals.commandLineEnabled
        for hold in snapshot.holds {
            guard effective.contains(.sessions), commandLineOn else {
                awayEnds.fire(stored.restoreEnd(.hold(hold), reason: .commandLineOff, now: now))
                continue
            }
            let life = lifetime.child()
            let id = hold.id
            let armed = ctx.process.watch(pid: hold.binding.pid, startTime: hold.binding.startTime, lifetime: life) { [weak self] in
                self?.endHold(id, .processExited)
            }
            if armed, holds.count < AwakeHold.maxHolds {
                holds.append(hold)
                holdLifetimes[id] = life
                holderNames[id] = ctx.process.holderName(for: hold.binding.pid)
                resumeSegment(.hold(hold), stored: stored, snapshot: snapshot, now: now)
            } else {
                life.end()
                awayEnds.fire(stored.restoreEnd(.hold(hold), reason: .processExited, now: now))
            }
        }
        startAtLaunchIfNeeded()
        evaluateGuards()
        arbitrate()
    }

    /// A resumed item after a real gap: the part before it is its own history entry and the item's history
    /// continues from now (time Snaptic wasn't running isn't counted, F1); after a short gap the segment goes on.
    private func resumeSegment(_ item: AwakeAwayEnd.Item, stored: AwakeRuntimeSnapshot, snapshot: AwakeRuntimeSnapshot,
                               now: ClockNow) {
        if let before = stored.resumedSegment(item, now: now) {
            awayEnds.fire(before)
            segmentStarts[item.id] = now.wall
        } else if let start = snapshot.segmentStarts[item.id] {
            segmentStarts[item.id] = start
        }
    }

    /// Where the history entry of a running session or hold starts: its start, or where its resume began (F1).
    func historyStart(_ id: StableID, startedAt: Double) -> Double {
        AwakeRuntimeSnapshot.segmentStart(stored: segmentStarts[id], startedAt: startedAt)
    }

    /// Whether a restored session uses the default options: its preset says "Use default", or (no preset: a CLI or
    /// launch start without explicit options) its options are the defaults for its kind (F7).
    static func followsDefaults(_ m: AwakeSession, sessions: AwakeSessionsConfig, effective: Set<AwakeFeature>) -> Bool {
        if let id = m.presetID {
            let preset = sessions.preset(id) ?? (sessions.defaultPreset.id == id ? sessions.defaultPreset : nil)
            return preset.map { $0.options == nil } ?? false
        }
        return m.options == sessions.effectiveOptions(for: m.kind, preset: nil, effective: effective)
    }

    /// Advanced "Start at launch": a preset started once per process (`HostSignals.launchSessionStarted`).
    private func startAtLaunchIfNeeded() {
        guard let ctx = context, !ctx.host.signals.launchSessionStarted else { return }
        ctx.host.signals.launchSessionStarted = true
        guard manual == nil, let id = ctx.config.value.sessions.behavior.startAtLaunch else { return }
        _ = startPreset(id, source: .launch)
    }

    // MARK: Observers

    /// Every manual-session and hold end, after the end and before arbitration.
    func observeEnds(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeEndedItem, AwakeEndReason) -> Void) {
        ends.add(lifetime) { handler($0.0, $0.1) }
    }

    /// A history entry restore owes: a session or `--pid` hold from the snapshot that isn't carried on (ran out,
    /// the Mac restarted, a guard, resume off after a crash...) or the part of a resumed one before the gap (F1).
    func observeAwayEnds(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeAwayEnd) -> Void) {
        awayEnds.add(lifetime, handler)
    }

    /// Guard warnings and the unreadable-battery notice (GuardsController's toasts).
    func observeGuardNotices(_ lifetime: Lifetime, _ handler: @escaping @MainActor (AwakeGuardNotice) -> Void) {
        guardNotices.add(lifetime, handler)
    }

    // MARK: Guards (§2.6)

    /// One evaluation with live facts: on every power change (critical heat and the hard floor are evaluated here,
    /// whatever any feature says) and on GuardsController's re-check timer.
    func evaluateGuards() {
        guard let ctx = context, lifetime != nil, restored, let facts = ctx.power.facts else { return }
        let now = AwakeModule.clockNow()
        let governing = AwakeArbiter.governing(manual: manual, top: ctx.triggers.top, holds: holds)
        let (verdict, memory) = AwakeGuards.evaluate(facts, previous: lastPower, config: ctx.config.value.guards,
                                                     memory: guardMemory, time: now.continuous,
                                                     active: governing.isActive,
                                                     overrideBattery: manual?.overrideGuards ?? false)
        lastPower = facts
        let holdChanged = memory.holding != guardMemory.holding
        guardMemory = memory
        ctx.runtime.power = facts
        switch verdict {
        case .end(let reason):
            if manual != nil { finishManual(reason, arbitrateAfter: false) }
            if !holds.isEmpty { for h in holds { _ = removeHold(h.id, reason) } }
            if case .trigger = governing, AwakeEndText.isInterruption(reason) {
                ctx.runtime.lastEnd = AwakeLastEnd(reason: reason, at: Date())
            }
        case .warn(let reason):
            guardNotices.fire(.warn(reason))
        case .allow:
            break
        }
        let unreadable = AwakeGuards.batteryUnreadable(facts)
        if unreadable && !wasUnreadable { guardNotices.fire(.batteryUnreadable) }
        wasUnreadable = unreadable
        if holdChanged { ctx.triggers.requestStep() }
        arbitrate()
    }

    // MARK: Arbitration

    /// Synchronous: expiries, the governing source, the plan and the one assertion, the gate's governing events,
    /// the runtime state, the tick, reminders, the snapshot and the dynamic needs. Re-entrant calls run once more
    /// after the current one.
    func arbitrate() {
        // §2.1: nothing arbitrates before restore(_:) ran (AwakeModule calls it right after the first apply).
        guard context != nil, lifetime != nil, restored else { return }
        if arbitrating {
            arbitrateAgain = true
            return
        }
        arbitrating = true
        defer { arbitrating = false }
        var rounds = 0
        repeat {
            arbitrateAgain = false
            arbitrateOnce()
            rounds += 1
        } while arbitrateAgain && rounds < 8
    }

    private func arbitrateOnce() {
        guard let ctx = context else { return }
        var now = AwakeModule.clockNow()

        // Expiry is checked on every arbitration (ticks never drive correctness alone).
        if let m = manual, AwakeClock.isExpired(m, now: now) { finishManual(.timeUp, arbitrateAfter: false) }
        for h in holds where h.remaining(now: now) <= 0 { _ = removeHold(h.id, .timeUp) }
        if let m = manual, case .whileApp(let bundleID, _) = m.kind, !AwakeFormat.isRunning(bundleID) {
            finishManual(.appQuit, arbitrateAfter: false)
        }

        // Session facts at the moment of use (security M2).
        let facts = ctx.system.sessionFacts()
        if facts.onConsole { offConsoleSince = nil } else if offConsoleSince == nil { offConsoleSince = now.continuous }
        if facts.locked { if lockedSince == nil { lockedSince = now.continuous } } else { lockedSince = nil }
        let behavior = ctx.config.value.sessions.behavior
        // Off-console and locked time count from max(since, the session's start) (lead decision, review6 F1).
        if let m = manual, let reason = AwakeSystemPolicy.end(behavior: behavior, onConsole: facts.onConsole,
                                                               offConsoleSince: offConsoleSince, locked: facts.locked,
                                                               lockedSince: lockedSince,
                                                               sessionStart: m.startedContinuous, now: now.continuous) {
            finishManual(reason, arbitrateAfter: false)
        }

        now = AwakeModule.clockNow()
        let governing = AwakeArbiter.governing(manual: manual, top: ctx.triggers.top, holds: holds)
        var idle: Double?
        if let options = governing.options, options.display == .keepOnWhileActive {
            idle = ctx.idle.realIdleSeconds()
            idleActiveSide = idle.map { $0 < Double(options.displayIdleMinutes) * 60 }
        } else {
            idleActiveSide = nil
        }
        let input = AwakeArbiterInput(governing: governing, screenLocked: facts.locked, consoleActive: facts.onConsole,
                                      realIdleSeconds: idle, keepDisplayOnWhileLocked: behavior.keepDisplayOnWhileLocked,
                                      driveAliveWriting: ctx.runtime.isEffective(.driveAlive) && ctx.driveAlive.isWriting,
                                      guardsHold: guardMemory.blocksTriggers(at: now.continuous),
                                      sessionEnd: AwakeArbiter.sessionEnd(governing, now: now))
        let plan = AwakeArbiter.plan(input)
        if !ctx.assertions.apply(plan, now: now) {
            assertionFailed(governing, now: now)
            return
        }
        if plan.type != .off, guardMemory.assertionFailures > 0 { guardMemory = guardMemory.clearingAssertionHold() }

        // The gate's governing events (R5-7). A start after a long quiet gap resets the cap even when no arbitration
        // ran during the gap (F3).
        if !lastGoverning.isActive && governing.isActive {
            activityGate = activityGate.applying(.governingStarted(now: now.continuous))
        }
        if case .manual = lastGoverning {
            switch governing {
            case .trigger, .holds: activityGate = activityGate.applying(.takeover)
            case .manual, .inactive: break
            }
        }
        if lastGoverning.isActive && !governing.isActive { activityGate = activityGate.applying(.governingEnded(now: now.continuous)) }
        if !governing.isActive { activityGate = activityGate.applying(.nothingGoverned(now: now.continuous)) }

        publish(governing, now: now)
        let flipped = governing.isActive != lastGoverning.isActive
        lastGoverning = governing
        updateIdleWatch(governing)
        if flipped {
            ctx.host.requestStatusPlan()
            if !governing.isActive, NSWorkspace.shared.isVoiceOverEnabled {
                NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                     userInfo: [.announcement: L("Awake turned off."),
                                                .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
        remind(now)
        scheduleTick(now, facts: facts, behavior: behavior)
        scheduleVerify(plan.type != .off)
        persist(now)
        updateNeeds()
    }

    private func publish(_ governing: AwakeGoverning, now: ClockNow) {
        guard let ctx = context else { return }
        let r = ctx.runtime
        if r.governing != governing { r.governing = governing }
        if r.holds != holds { r.holds = holds }
        let summary = AwakeHolderText.summary(holds.map { holderNames[$0.id] ?? nil })
        if r.holderSummary != summary { r.holderSummary = summary }
        let remaining = manual.flatMap { AwakeClock.remaining($0, now: now) }.map { max(0, $0) }
        if r.remaining != remaining { r.remaining = remaining }
        let type = ctx.assertions.current.type
        if r.assertion != type { r.assertion = type }
        if r.guardHold != guardMemory.holding { r.guardHold = guardMemory.holding }
        if r.pointerConfirmation != prompt.isShowing { r.pointerConfirmation = prompt.isShowing }
        let lid = ctx.system.lidWillSleep
        if r.lidWillSleep != lid { r.lidWillSleep = lid }
        if let end = r.lastEnd, Date().timeIntervalSince(end.at) > 12 * 3_600 { r.lastEnd = nil }
    }

    /// A failed create: a manual session ends `.assertionFailed` with its toast; a rule gets an assertion hold with
    /// backoff (one toast per hold); holds end.
    private func assertionFailed(_ governing: AwakeGoverning, now: ClockNow) {
        guard let ctx = context else { return }
        switch governing {
        case .manual:
            finishManual(.assertionFailed, arbitrateAfter: false)
        case .trigger:
            // One toast per hold: the first failure, or the first after the previous hold ran out (F4).
            let first = guardMemory.assertionHoldUntil.map { now.continuous >= $0 } ?? true
            guardMemory = guardMemory.recordingAssertionFailure(now: now.continuous)
            if first { ctx.host.toasts.show(L("Snaptic couldn’t keep your Mac awake. Try again, or restart Snaptic.")) }
            ctx.triggers.requestStep()
        case .holds:
            // Every hold ends, with the toast a manual session gets (the Mac isn't held any more, review6 N1).
            for h in holds { _ = removeHold(h.id, .assertionFailed) }
            if let text = AwakeEndText.toast(.assertionFailed, floor: floorForText(), appName: nil, lockedHours: nil) {
                ctx.host.toasts.show(text)
            }
        case .inactive:
            break
        }
        arbitrateAgain = true
    }

    /// Ends the manual session: history and held connections first (observers), then its toast and last-end line.
    private func finishManual(_ reason: AwakeEndReason, notify: Bool = true, arbitrateAfter: Bool = true) {
        guard let ctx = context, let s = manual else { return }
        manual = nil
        lastFinished = (s.id, reason)
        sessionLifetime?.end()
        sessionLifetime = nil
        prompt.reset()
        quietSince = nil
        quietFor = nil
        usesDefaultOptions = false
        activityGate = activityGate.applying(.ended)
        EventLog.shared.record(AwakeLogEvent.sessionEnded(reason))
        ends.fire((.session(s), reason))
        segmentStarts.removeValue(forKey: s.id)
        if notify {
            let appName: String?
            if case .whileApp(let bundleID, _) = s.kind { appName = AwakeFormat.appName(bundleID) } else { appName = nil }
            if let text = AwakeEndText.toast(reason, floor: floorForText(), appName: appName,
                                             lockedHours: ctx.config.value.sessions.behavior.endAfterLockedHours) {
                ctx.host.toasts.show(text)
            }
        }
        if AwakeEndText.isInterruption(reason) { ctx.runtime.lastEnd = AwakeLastEnd(reason: reason, at: Date()) }
        if arbitrateAfter { arbitrate() } else { arbitrateAgain = true }
    }

    /// The floor a battery text names: the hard floor when below it, else the user floor in effect.
    func floorForText() -> Int {
        guard let ctx = context else { return AwakeGuards.hardFloorPercent }
        if let p = (lastPower ?? ctx.power.facts)?.percent, p < AwakeGuards.hardFloorPercent { return AwakeGuards.hardFloorPercent }
        return ctx.config.value.guards.effectiveFloor
    }

    /// "While Xcode is running", "Until downloads and tasks finish".
    func taskTitle(_ s: AwakeSession) -> String {
        switch s.kind {
        case .whileApp(let bundleID, _): return L("While ") + (AwakeFormat.appName(bundleID) ?? L("the app")) + L(" is running")
        case .untilIdle: return L("Until downloads and tasks finish")
        case .indefinite, .duration, .until: return ""
        }
    }

    // MARK: Session watchers

    /// Per-kind watchers bound to the session's lifetime: app quits (whileApp) and untilIdle sampling (R5-4).
    private func watch(_ session: AwakeSession, life: Lifetime) {
        guard let ctx = context else { return }
        switch session.kind {
        case .whileApp:
            let center = NSWorkspace.shared.notificationCenter
            let token = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                           queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.arbitrate() }
            }
            life.onEnd { center.removeObserver(token) }
        case .untilIdle:
            ctx.cpu.requestTaskSampling(life)
            ctx.network.requestTaskSampling(life)
            ctx.cpu.observe(life) { [weak self] in self?.taskSample() }
            discardNextSample = true
        case .indefinite, .duration, .until:
            break
        }
    }

    private func taskSample() {
        guard let ctx = context, let m = manual, case .untilIdle(let spec, _) = m.kind else { return }
        let now = AwakeModule.clockNow()
        if discardNextSample {
            discardNextSample = false
            quietSince = nil
            quietFor = nil
            return
        }
        let sample = TaskActivitySample(topProcessPercent: ctx.cpu.topProcessPercent, newProcesses: ctx.cpu.newProcesses,
                                        totalCPUPercent: ctx.cpu.totalPercent, diskKBps: ctx.disk.kBps,
                                        networkKBps: ctx.network.throughputKBps)
        let step = TaskQuiet.step(quietSince: quietSince, sample: sample, now: now.continuous,
                                  started: m.startedContinuous, spec: spec)
        quietSince = step.quietSince
        quietFor = TaskQuiet.quietFor(quietSince: step.quietSince, now: now.continuous)
        if step.finished { finishManual(.tasksFinished) }
    }

    /// A wake resets the quiet window and discards the first delta after it (code R2-M10).
    private func systemEvent(_ event: SystemEvent) {
        guard let ctx = context else { return }
        switch event {
        case .willSleep:
            if manual != nil, ctx.config.value.sessions.behavior.endOnSystemSleep { finishManual(.systemSleep) }
        case .didWake:
            quietSince = nil
            quietFor = nil
            discardNextSample = true
            arbitrate()
            verifyAssertion()
        case .lockHint, .unlockHint:
            arbitrate()
            scheduleLockRecheck()
        case .clockChanged, .timeZoneChanged, .dayChanged, .sessionResigned, .sessionBecameActive,
             .screensDidWake, .screensDidSleep, .lidChanged, .screensaverStarted, .screensaverStopped:
            arbitrate()
        case .lowPowerModeChanged, .thermalChanged:
            break   // PowerMonitor publishes the new facts; evaluateGuards runs from its observer
        }
    }

    /// N3: loginwindow's lock notification may arrive before the session dictionary shows the lock; one more plan a
    /// second later follows the dictionary either way (no change, no effect).
    private func scheduleLockRecheck() {
        lockRecheckTimer?.invalidate()
        let timer = Timer(timeInterval: Self.lockRecheckSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lockRecheckTimer = nil
                self?.arbitrate()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        lockRecheckTimer = timer
    }

    private func verifyAssertion() {
        guard let ctx = context else { return }
        arbitrate()
        let now = AwakeModule.clockNow()
        if !ctx.assertions.verify(now: now) {
            assertionFailed(lastGoverning, now: now)
            arbitrate()
        }
    }

    // MARK: Ticks, reminders, notices

    private func scheduleTick(_ now: ClockNow, facts: SessionFacts, behavior: AwakeBehavior) {
        tickTimer?.invalidate()
        tickTimer = nil
        var next = AwakeTick.next(manual: manual, holds: holds, reminders: reminders, now: now)
        if let m = manual, let check = AwakeSystemPolicy.nextCheck(behavior: behavior, onConsole: facts.onConsole,
                                                                    offConsoleSince: offConsoleSince, locked: facts.locked,
                                                                    lockedSince: lockedSince,
                                                                    sessionStart: m.startedContinuous, now: now.continuous) {
            next = min(next ?? AwakeTick.maximum, max(check, AwakeTick.minimum))
        }
        guard let delay = next else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.arbitrate() }
        }
        // A hold's cap is its end: at most 1 s late (N2); countdown ticks may drift more.
        let holdEnds = holds.contains { abs($0.remaining(now: now) - delay) < 1 }
        timer.tolerance = holdEnds ? min(delay * 0.1, 1) : min(delay * 0.1, 30)
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    /// While keepOnWhileActive governs, every IdleSampler read (5 s) re-plans when the idle limit was crossed (F6).
    private func updateIdleWatch(_ governing: AwakeGoverning) {
        guard let ctx = context, let life = lifetime else { return }
        guard governing.options?.display == .keepOnWhileActive else {
            idleWatch?.end()
            idleWatch = nil
            return
        }
        guard idleWatch == nil else { return }
        let watch = life.child()
        idleWatch = watch
        ctx.idle.requestFastSampling(watch)
        ctx.idle.observe(watch) { [weak self] in self?.idleSampled() }
    }

    private func idleSampled() {
        guard let ctx = context, let options = lastGoverning.options, options.display == .keepOnWhileActive,
              let idle = ctx.idle.realIdleSeconds() else { return }
        let active = idle < Double(options.displayIdleMinutes) * 60
        if active != idleActiveSide { arbitrate() }
    }

    private func scheduleVerify(_ active: Bool) {
        if !active {
            verifyTimer?.invalidate()
            verifyTimer = nil
            return
        }
        guard verifyTimer == nil else { return }
        let timer = Timer(timeInterval: Self.verifySeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifyAssertion() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        verifyTimer = timer
    }

    private func remind(_ now: ClockNow) {
        guard let ctx = context, let life = sessionLifetime, let reminder = reminders.due(manual, now: now) else { return }
        switch reminder {
        case .fiveMinutes:
            ctx.host.toasts.show(L("Awake ends in 5 minutes."), actions: [
                ToastAction(title: L("Add 1 Hour"), isDefault: true) { [weak self] in
                    _ = self?.extend(by: 3_600, source: .menu)
                },
            ], lifetime: life)
        case .eightHours:
            ctx.host.toasts.show(L("Awake has kept your Mac awake for 8 hours."), actions: [
                ToastAction(title: L("Turn Off")) { [weak self] in self?.turnOff(source: .menu) },
                ToastAction(title: L("Keep Going"), isDefault: true) {},
            ], lifetime: life)
        }
    }

    /// "Awake was started from the command line." at most once per 10 minutes (§3.1).
    private func announceCommandLine(_ now: ClockNow) {
        guard let ctx = context else { return }
        if let last = lastCLINotice, now.continuous - last < Self.cliNoticeSeconds { return }
        lastCLINotice = now.continuous
        ctx.host.toasts.show(L("Awake was started from the command line."))
    }

    /// The guard refusal toast with Start Anyway (battery and Low Power Mode above the hard floor only; never heat,
    /// never the hard floor). Its lifetime ends at the next start, Turn Off or module stop.
    private func offerStartAnyway(_ reason: AwakeEndReason, facts: PowerFacts, kind: AwakeSessionKind,
                                  options: AwakeSessionOptions?, presetID: StableID?, source: AwakeSessionSource) {
        guard let ctx = context, let lifetime else { return }
        let text = AwakeEndText.refusal(reason, floor: floorForText())
        let overridable = (reason == .batteryLow || reason == .lowPowerMode)
            && !(facts.discharging && (facts.percent ?? 0) < AwakeGuards.hardFloorPercent)
        startAnywayLifetime?.end()
        guard overridable else {
            ctx.host.toasts.show(text)
            return
        }
        let life = lifetime.child()
        startAnywayLifetime = life
        ctx.host.toasts.show(text, actions: [
            ToastAction(title: L("Start Anyway")) { [weak self] in
                guard let self else { return }
                // R5-8: the guard toast's re-start of a Settings start checks the focus guard too (security N-1).
                if source == .settings, !SettingsShell.shared.mayStart() { return }
                _ = self.start(kind, options: options, presetID: presetID, source: source, overrideGuards: true,
                               preset: presetID.flatMap { self.context?.config.value.sessions.preset($0) })
            },
        ], lifetime: life, remember: false, clickGuard: .confirmation)
    }

    // MARK: Snapshot and needs

    /// On change only (and for the heartbeat while the snapshot carries a stamp), always a whole snapshot built
    /// from memory (never read back). `heartbeat`: the heartbeat timer fired, so the stamp is refreshed whatever
    /// else changed.
    private func persist(_ now: ClockNow, heartbeat: Bool = false) {
        guard let ctx = context, restored else { return }
        let snapshot = currentSnapshot(now, manual: manual, clean: false)
        let stamped = snapshot.stop != nil
        let due = heartbeat || lastStampAt.map { now.continuous - $0 >= Self.heartbeatSeconds } ?? true
        let heartbeatDue = stamped && due
        guard snapshot.content != lastWritten?.content || heartbeatDue else { return }
        lastWritten = snapshot
        lastStampAt = stamped ? now.continuous : nil
        ctx.state.value = snapshot
        scheduleHeartbeat(stamped)
    }

    /// One-shot, re-armed by every stamped write, so the stamp is never older than `heartbeatSeconds` (plus the
    /// timer's tolerance) while Snaptic runs; cancelled when the snapshot carries no stamp.
    private func scheduleHeartbeat(_ stamped: Bool) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        guard stamped else { return }
        let timer = Timer(timeInterval: Self.heartbeatSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.heartbeatTimer = nil
                self?.persist(AwakeModule.clockNow(), heartbeat: true)
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    /// The snapshot of the running state; a stop stamp only while a session, a `--pid` hold or (not at a clean quit,
    /// which records it) a rule session is in it (F1, review6 N2).
    private func currentSnapshot(_ now: ClockNow, manual: AwakeSession?, clean: Bool) -> AwakeRuntimeSnapshot {
        let triggers = context?.triggers
        let rule = clean ? nil : governingRule(now)
        let carried = manual != nil || holds.contains { $0.binding.isProcess } || rule != nil
        return AwakeRuntimeSnapshot(bootSession: now.bootSession, manual: manual, holds: holds,
                                    suppressions: triggers?.suppressions ?? [:], pausedUntil: triggers?.pausedUntil,
                                    guardMemory: guardMemory,
                                    stop: carried ? AwakeStopStamp(wall: now.wall, continuous: now.continuous, clean: clean) : nil,
                                    rule: rule, segmentStarts: segmentStarts, reminders: reminders)
    }

    /// The top rule candidate as a record: its wall start is computed once per rule session (TriggerController
    /// records the same start when it ends).
    private func governingRule(_ now: ClockNow) -> AwakeRuleRecord? {
        guard let top = context?.triggers.top else {
            ruleRecord = nil
            return nil
        }
        if let r = ruleRecord, r.record.triggerID == top.id, r.since == top.since { return r.record }
        let record = AwakeRuleRecord(triggerID: top.id, startWall: now.wall - max(0, now.continuous - top.since))
        ruleRecord = (record, top.since)
        return record
    }

    private func updateNeeds() {
        var needs: AwakeDynamicNeeds = []
        if let m = manual {
            switch m.kind {
            case .untilIdle: needs.insert(.taskQuiet)
            case .whileApp: needs.insert(.apps)
            case .indefinite, .duration, .until: break
            }
        }
        if lastGoverning.options?.display == .keepOnWhileActive { needs.insert(.idle) }
        if !holds.isEmpty { needs.insert(.process) }
        if appPickerOpen { needs.insert(.apps) }
        guard needs != dynamicNeeds else { return }
        dynamicNeeds = needs
        onDynamicNeedsChange?(needs)
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard self.lifetime == nil else { return }   // idempotent
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.power.observe(lifetime) { [weak self] in self?.evaluateGuards() }
        context.system.observeEvents(lifetime) { [weak self] event in self?.systemEvent(event) }
        context.assertions.onTimeout = { [weak self] in self?.verifyAssertion() }
        lifetime.onEnd { [weak context] in context?.assertions.onTimeout = nil }
        // R5-14(a): General › Command-line control turned off ends every hold, connection and `--pid` alike.
        commandLineSink = context.host.signals.$commandLineEnabled
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.endAllHolds(.commandLineOff) } }
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {
        self.effective = effective
        arbitrate()
    }

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {
        if old.guards != new.guards { evaluateGuards() }
        if usesDefaultOptions, old.sessions.defaultOptions.display != new.sessions.defaultOptions.display
            || old.sessions.defaultOptions.displayIdleMinutes != new.sessions.defaultOptions.displayIdleMinutes {
            manual?.options.display = new.sessions.defaultOptions.display
            manual?.options.displayIdleMinutes = new.sessions.defaultOptions.displayIdleMinutes
        }
        arbitrate()
    }

    /// Synchronous: every assertion released, the session and holds end `.moduleStopped` (history and held
    /// connections were already settled by their own controllers, which stop first), the gate resets.
    func stop() {
        guard let ctx = context else { return }
        tickTimer?.invalidate()
        tickTimer = nil
        verifyTimer?.invalidate()
        verifyTimer = nil
        startAnywayLifetime?.end()
        turnOffToastLifetime?.end()
        commandLineSink = nil
        lockRecheckTimer?.invalidate()
        lockRecheckTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        idleWatch?.end()
        idleWatch = nil
        idleActiveSide = nil
        if restored, ctx.host.signals.isTerminating {
            // Quit: the last snapshot carries the exact stop (F1). With resume off the session was recorded by
            // History just now and is left out; `--pid` holds are always kept for the relaunch.
            let keep = ctx.config.value.sessions.behavior.resumeAfterRestart ? manual : nil
            ctx.state.value = currentSnapshot(AwakeModule.clockNow(), manual: keep, clean: true)
        }
        let session = manual
        let stack = holds
        manual = nil
        holds = []
        sessionLifetime?.end()
        sessionLifetime = nil
        for life in holdLifetimes.values { life.end() }
        holdLifetimes = [:]
        holderNames = [:]
        if let s = session { ends.fire((.session(s), .moduleStopped)) }
        for h in stack { ends.fire((.hold(h), .moduleStopped)) }
        ctx.assertions.releaseAll()
        activityGate = activityGate.applying(.moduleStop)
        prompt.reset()
        reminders = AwakeReminders()
        lastGoverning = .inactive
        lastWritten = nil
        lastStampAt = nil
        segmentStarts = [:]
        ruleRecord = nil
        lastFinished = nil
        lastRemovedHold = nil
        restored = false
        quietSince = nil
        quietFor = nil
        dynamicNeeds = []
        lifetime = nil
        context = nil
    }
}
