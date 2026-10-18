import AppKit
import SnapticKit

// Hotkeys and CLI verbs (owner: G; PLAN 0.3 §2.10, §3.1, N17, R5-5, R5-10, R5-14). Shortcuts (`shortcuts`) register
// the AwakeActionID combos from `AwakeConfig.shortcuts`; a hotkey start is `.hotkey` (the gate asks before pointer
// movement). The verbs (`commandLine`) parse with Kit's AwakeCommandGrammar and never name apps, holders or rules.
// `awake hold` binds a holder to the client's own connection (the default) or to `--pid N`: the binding is resolved
// here from the server's peer facts, never from the request, and ProcessWatch is armed in SessionController.addHold.

@MainActor final class AwakeAutomation: AwakeFeatureController {
    static var id: AwakeControllerID { .automation }
    /// Weak: controllers never keep the context strongly.
    weak var context: AwakeContext?

    private var lifetime: Lifetime?
    private var hotkeysLifetime: Lifetime?
    private var verbsLifetime: Lifetime?
    private var effective: Set<AwakeFeature> = []
    private var limiter = AwakeRateLimiter()
    /// Connection holds and their held connections (finished with the hold's final line).
    private var connections: [StableID: ControlHold] = [:]
    /// Combos that failed to register (conflict or system refusal), for Settings.
    private(set) var failedShortcuts: Set<AwakeActionID> = []

    init() {}

    // MARK: Hotkeys

    private func registerHotkeys() {
        hotkeysLifetime?.end()
        hotkeysLifetime = nil
        failedShortcuts = []
        guard let ctx = context, let lifetime, effective.contains(.shortcuts) else { return }
        let life = lifetime.child()
        hotkeysLifetime = life
        for action in AwakeActionID.allAwake {
            guard let combo = ctx.config.value.shortcuts[action] else { continue }
            do {
                _ = try ctx.host.hotkeys.register(combo, owner: L("Awake"), lifetime: life) { [weak self] in
                    self?.perform(action)
                }
            } catch {
                failedShortcuts.insert(action)
            }
        }
    }

    /// One hotkey action. Starts are `.hotkey` (the confirmation toast guards pointer movement, R5-1).
    func perform(_ action: AwakeActionID) {
        guard let ctx = context else { return }
        let sessions = ctx.sessions
        switch action {
        case .toggle:
            sessions.toggleDefault(source: .hotkey)
        case .keepDisplayOn:
            guard ctx.runtime.governing.isActive else { return }
            sessions.setKeepDisplayOn(!sessions.keepsDisplayOn)
        case .pauseAutomatic:
            if ctx.triggers.isPaused { ctx.triggers.resume() } else { ctx.triggers.pause(seconds: 3_600) }
        default:
            guard let slot = (1...4).first(where: { AwakeActionID.preset($0) == action }) else { return }
            let presets = ctx.config.value.sessions.presets
            guard slot <= presets.count else { return }
            _ = sessions.startPreset(presets[slot - 1].id, source: .hotkey)
        }
    }

    // MARK: CLI verbs

    private func registerVerbs() {
        verbsLifetime?.end()
        verbsLifetime = nil
        guard let ctx = context, let lifetime, effective.contains(.commandLine) else { return }
        let life = lifetime.child()
        verbsLifetime = life
        let commands = ctx.host.commands
        commands.register("awake status", policy: .read, offOnly: false, cliAllowed: true,
                          summary: L("Show whether Awake is keeping your Mac awake"), lifetime: life) { [weak self] request, _ in
            self?.status(request) ?? Self.unavailable
        }
        commands.register("awake start", policy: .low, offOnly: false, cliAllowed: true,
                          summary: L("Keep your Mac awake for a while (default 1 hour)"), lifetime: life) { [weak self] request, _ in
            self?.startVerb(request) ?? Self.unavailable
        }
        commands.register("awake hold", policy: .low, offOnly: false, cliAllowed: true, holds: true,
                          summary: L("Keep your Mac awake while this command or --pid runs"),
                          lifetime: life) { [weak self] request, context in
            self?.holdVerb(request, context) ?? Self.unavailable
        }
        commands.register("awake preset", policy: .low, offOnly: false, cliAllowed: true,
                          summary: L("Start a session preset by number or name"), lifetime: life) { [weak self] request, _ in
            self?.presetVerb(request) ?? Self.unavailable
        }
        commands.register("awake extend", policy: .low, offOnly: false, cliAllowed: true,
                          summary: L("Add time to the running session"), lifetime: life) { [weak self] request, _ in
            self?.extendVerb(request) ?? Self.unavailable
        }
        commands.register("awake stop", policy: .low, offOnly: true, cliAllowed: true,
                          summary: L("End the running session"), lifetime: life) { [weak self] request, _ in
            self?.stopVerb(request) ?? Self.unavailable
        }
        commands.register("awake pause", policy: .low, offOnly: true, cliAllowed: true,
                          summary: L("Pause rules (default 1 hour)"), lifetime: life) { [weak self] request, _ in
            self?.pauseVerb(request) ?? Self.unavailable
        }
    }

    private static let unavailable = ControlResponse.failure(ControlExit.unavailable, L("Awake isn't running."))
    private static let usage = ControlResponse.failure(ControlExit.usage, L("Usage error. Run “snaptic help awake”."))

    private func refused(_ r: AwakeRefusal) -> ControlResponse { .failure(r.exitCode, r.text) }

    private func command(_ verb: String, _ request: ControlRequest) -> AwakeCommand? {
        AwakeCommandGrammar.parse(verb: verb, args: request.arguments)
    }

    /// `start`, `hold`, `stop` and `extend` share one request per second (security L3).
    private func rateLimited() -> Bool { !limiter.allow(now: AwakeModule.clockNow().continuous) }

    private func status(_ request: ControlRequest) -> ControlResponse {
        guard let ctx = context, case .status(let json)? = command("status", request) else { return Self.usage }
        let facts = AwakeStatusFacts(governing: ctx.runtime.governing, holds: ctx.sessions.holds,
                                     now: AwakeModule.clockNow())
        return .ok(json || request.json ? AwakeCommandGrammar.statusJSON(facts) : AwakeCommandGrammar.statusLine(facts))
    }

    private func startVerb(_ request: ControlRequest) -> ControlResponse {
        guard let ctx = context, case .start(let duration, let maySleep)? = command("start", request) else { return Self.usage }
        if rateLimited() { return refused(.rateLimited) }
        var until: Double?
        if case .untilClock(let h, let m)? = duration { until = AwakeFormat.nextUnix(hour: h, minute: m) }
        guard let kind = AwakeStartRules.cliKind(duration, untilUnix: until) else { return refused(.invalid) }
        var options: AwakeSessionOptions?
        if maySleep {
            var o = ctx.config.value.sessions.effectiveOptions(for: kind, preset: nil, effective: ctx.runtime.effectiveFeatures)
            o.display = .maySleep
            options = o
        }
        switch ctx.sessions.start(kind, options: options, presetID: nil, source: .commandLine, overrideGuards: false) {
        case .success(let s): return .ok(startedText(s))
        case .failure(let r): return refused(r)
        }
    }

    private func presetVerb(_ request: ControlRequest) -> ControlResponse {
        guard let ctx = context, case .preset(let selector)? = command("preset", request) else { return Self.usage }
        if rateLimited() { return refused(.rateLimited) }
        let presets = ctx.config.value.sessions.presets
        let preset: AwakePreset?
        switch selector {
        case .index(let n): preset = n >= 1 && n <= presets.count ? presets[n - 1] : nil
        case .name(let name):
            let wanted = name.lowercased()
            preset = presets.first { $0.title(AwakeFormat.text).lowercased() == wanted }
        }
        guard let preset else { return .failure(ControlExit.notFound, L("No such preset.")) }
        switch ctx.sessions.startPreset(preset.id, source: .commandLine) {
        case .success(let s): return .ok(startedText(s))
        case .failure(let r): return refused(r)
        }
    }

    private func extendVerb(_ request: ControlRequest) -> ControlResponse {
        guard let ctx = context, case .extend(let seconds)? = command("extend", request) else { return Self.usage }
        if rateLimited() { return refused(.rateLimited) }
        switch ctx.sessions.extend(by: seconds, source: .commandLine) {
        case .success(let s): return .ok(startedText(s))
        case .failure(let r): return refused(r)
        }
    }

    private func stopVerb(_ request: ControlRequest) -> ControlResponse {
        guard let ctx = context, case .stop? = command("stop", request) else { return Self.usage }
        if rateLimited() { return refused(.rateLimited) }
        if ctx.sessions.manual != nil || ctx.triggers.top != nil {
            ctx.sessions.end(.user)
            return .ok(L("Awake session ended."))
        }
        return .ok(L("No session is running."))
    }

    private func pauseVerb(_ request: ControlRequest) -> ControlResponse {
        guard let ctx = context, case .pause(let seconds)? = command("pause", request) else { return Self.usage }
        ctx.triggers.pause(seconds: Double(seconds ?? 3_600))
        let until = ctx.triggers.pausedUntil.map { AwakeCommandGrammar.isoUTC($0) ?? "" } ?? ""
        return .ok(L("Rules are paused until ") + until + ".")
    }

    /// "Keeping your Mac awake until 2026-10-18T17:30:00Z." (ISO, UTC: no locale, no names).
    private func startedText(_ s: AwakeSession) -> String {
        let now = AwakeModule.clockNow()
        guard let end = AwakeClock.endWall(s, now: now), let iso = AwakeCommandGrammar.isoUTC(end) else {
            return L("Keeping your Mac awake.")
        }
        return L("Keeping your Mac awake until ") + iso + "."
    }

    // MARK: awake hold

    private func holdVerb(_ request: ControlRequest, _ control: ControlContext) -> ControlResponse {
        guard let ctx = context, case .hold(let pid, let maxSeconds)? = command("hold", request) else { return Self.usage }
        if rateLimited() { return refused(.rateLimited) }
        let cap = maxSeconds ?? AwakeClock.holdDefaultCapSeconds
        if let pid {
            // --pid N: a same-user process the caller names; the reply closes the connection at once.
            guard pid > 1, let facts = ctx.process.facts(pid), facts.uid == getuid() else { return refused(.invalid) }
            switch ctx.sessions.addHold(.process(pid: pid, startTime: facts.startTime), capSeconds: cap) {
            case .success: return .ok(AwakeCommandGrammar.holdReply(pid: pid, capSeconds: cap))
            case .failure(let r): return refused(r)
            }
        }
        // Default: the client's own connection and process (peer facts from the server, best effort; the
        // connection's EOF is the authoritative end).
        guard let hold = control.hold, !hold.isClosed, control.peer.pid > 1, let start = control.peer.startTime,
              control.peer.uid == getuid() else {
            return .failure(AwakeRefusal.invalid.exitCode, L("Snaptic couldn't identify the caller."))
        }
        switch ctx.sessions.addHold(.connection(pid: control.peer.pid, startTime: start), capSeconds: cap) {
        case .success(let added):
            let id = added.id
            connections[id] = hold
            hold.onClose { [weak self, weak hold] in
                guard let self else { return }
                self.connections[id] = nil
                if hold?.closeReason == .server {
                    // The control server stopped (command-line control turned off): every hold ends (R5-14).
                    self.context?.sessions.endAllHolds(.commandLineOff)
                } else {
                    self.context?.sessions.endHold(id, .processExited)
                }
            }
            return .holding(AwakeCommandGrammar.holdReply(pid: nil, capSeconds: cap))
        case .failure(.invalid):
            return .failure(AwakeRefusal.invalid.exitCode, L("Snaptic couldn't identify the caller."))
        case .failure(let r):
            return refused(r)
        }
    }

    /// A hold ended in Snaptic: its client prints the final line and exits (0, or 5 when Snaptic quit).
    private func holdEnded(_ item: AwakeEndedItem, _ reason: AwakeEndReason) {
        guard case .hold(let h) = item, let connection = connections.removeValue(forKey: h.id) else { return }
        connection.finish(finalLine(reason))
    }

    private func finalLine(_ reason: AwakeEndReason) -> ControlResponse {
        switch reason {
        case .user: return .ok(L("Awake hold ended in Snaptic."))
        case .timeUp: return .ok(L("Awake hold ended: time is up."))
        case .processExited: return .ok(L("Awake hold ended: the process exited."))
        case .commandLineOff: return .ok(L("Command-line control was turned off."))
        case .moduleStopped:
            if context?.host.signals.isTerminating ?? true { return .failure(ControlExit.unavailable, L("Snaptic quit.")) }
            return .ok(L("Awake was turned off."))
        default:
            let floor = context?.sessions.floorForText() ?? AwakeGuards.hardFloorPercent
            return .ok(L("Awake hold ended: ") + AwakeEndText.phrase(reason, floor: floor, appName: nil, lockedHours: nil) + ".")
        }
    }

    /// Every held connection gets its final line now (module stop, or the feature turned off).
    private func finishAll(_ response: ControlResponse) {
        let all = connections
        connections = [:]
        for hold in all.values { hold.finish(response) }
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.sessions.observeEnds(lifetime) { [weak self] item, reason in self?.holdEnded(item, reason) }
        registerHotkeys()
        registerVerbs()
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {
        let old = self.effective
        self.effective = effective
        if old.contains(.shortcuts) != effective.contains(.shortcuts) { registerHotkeys() }
        if old.contains(.commandLine) != effective.contains(.commandLine) {
            if !effective.contains(.commandLine) {
                // R5-14: every hold of both forms ends before `process` deactivates.
                context?.sessions.endAllHolds(.commandLineOff)
            }
            registerVerbs()
        }
    }

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {
        if old.shortcuts != new.shortcuts || old.sessions.presets.map(\.id) != new.sessions.presets.map(\.id) {
            registerHotkeys()
        }
    }

    /// Module stop: held connections get "Awake was turned off." (exit 0) or, when Snaptic quits, "Snaptic quit."
    /// (exit 5). When only the automation features went away, the holds end `.commandLineOff` first.
    func stop() {
        guard let ctx = context else { return }
        let moduleStopping = ctx.runtime.isEffective(.commandLine) || ctx.runtime.isEffective(.shortcuts)
        if moduleStopping {
            finishAll(ctx.host.signals.isTerminating ? .failure(ControlExit.unavailable, L("Snaptic quit."))
                                                     : .ok(L("Awake was turned off.")))
        } else {
            ctx.sessions.endAllHolds(.commandLineOff)
            finishAll(.ok(L("Command-line control was turned off.")))
        }
        hotkeysLifetime?.end()
        verbsLifetime?.end()
        hotkeysLifetime = nil
        verbsLifetime = nil
        lifetime = nil
        context = nil
    }
}
