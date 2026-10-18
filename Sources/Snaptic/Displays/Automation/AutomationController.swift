import AppKit
import Combine
import SnapticKit

/// Hooks and custom actions (PLAN §11). Hooks run on display connect/disconnect (hard and
/// soft), Mac sleep and wake (optionally delayed); custom actions become actions, menu
/// items, shortcuts and, when the user allows it per action, CLI commands. FeatureGraph
/// keeps both off in Safe Mode, and hooks off while panic-latched; panic kills running
/// commands.
@MainActor final class AutomationController: DisplayFeatureController, PanicParticipant, DiagnosticsContributor {
    static var id: DisplayControllerID { .automation }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Only `automation` (0.3 §4.5): feature changes arrive through `effectiveFeaturesDidChange`.
    static var observedSections: Set<DisplaysConfigSection> { [.automation] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?

    private var lifetime: Lifetime?
    private var hooksLifetime: Lifetime?
    private var actionsLifetime: Lifetime?
    private var effective: Set<DisplayFeature> = []
    private var known: [DisplayKey: DisplayInfo] = [:]
    private var sinks: [AnyCancellable] = []
    private var tokens: [NSObjectProtocol] = []
    private var actionThrottle = HookThrottle(interval: 1)
    /// The custom actions' menu items (R5-13), registered while custom actions run.
    private var actionMenu: AutomationMenuItems?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        switch feature {
        case .hooks, .customActions:
            if let reason = context.helpers.unavailable { return .unavailable(reason) }
            return .available
        default:
            return .unavailable(L("Not part of automation"))
        }
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime == nil else { return }
        self.context = context
        self.lifetime = lifetime
        context.registerPanic(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Automation"), lifetime: lifetime)
        apply(effective)
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        apply(effective)
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        guard old.automation.actions != new.automation.actions, actionsLifetime != nil else { return }
        stopActions()
        startActions()
    }

    func stop() {
        stopHooks()
        stopActions()
        context?.spawner.stopAll()
        lifetime = nil
        effective = []
        context = nil
    }

    func panicRestore() {
        context?.spawner.stopAll()
    }

    private func apply(_ new: Set<DisplayFeature>) {
        let old = effective
        effective = new
        if new.contains(.hooks) && !old.contains(.hooks) { startHooks() }
        if !new.contains(.hooks) && old.contains(.hooks) { stopHooks() }
        if new.contains(.customActions) && !old.contains(.customActions) { startActions() }
        if !new.contains(.customActions) && old.contains(.customActions) { stopActions() }
    }

    // MARK: Hooks

    private func startHooks() {
        guard let ctx = context, let lifetime, hooksLifetime == nil else { return }
        let life = lifetime.child()
        hooksLifetime = life
        known = Dictionary(ctx.registry.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        ctx.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in MainActor.assumeIsolated { self?.displaysChanged(displays) } }
            .store(in: &sinks)
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(.sleep, display: nil) }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        life.onEnd { [weak self] in self?.removeHookObservers() }
    }

    private func stopHooks() {
        hooksLifetime?.end()
        hooksLifetime = nil
    }

    private func removeHookObservers() {
        sinks.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = []
        known = [:]
    }

    /// Hard events: a display appears or disappears. Soft: it stays online but goes
    /// inactive (or back).
    private func displaysChanged(_ displays: [DisplayInfo]) {
        let now = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for (key, info) in now {
            if let before = known[key] {
                if before.isActive && !info.isActive { fire(.softDisconnect, display: info) }
                if !before.isActive && info.isActive { fire(.softConnect, display: info) }
            } else {
                fire(.connect, display: info)
            }
        }
        for (key, info) in known where now[key] == nil { fire(.disconnect, display: info) }
        known = now
    }

    private func didWake() {
        fire(.wake, display: nil)
        guard let ctx = context, let life = hooksLifetime else { return }
        for hook in ctx.config.value.automation.hooks(for: .wakeDelayed, display: nil) {
            let id = hook.id
            DispatchQueue.main.asyncAfter(deadline: .now() + hook.delaySeconds) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !life.isEnded, let ctx = self.context,
                          let current = ctx.config.value.automation.hooks.first(where: { $0.id == id }),
                          current.enabled, current.event == .wakeDelayed else { return }
                    self.run(current, event: .wakeDelayed, display: nil)
                }
            }
        }
    }

    private func fire(_ event: HookEvent, display: DisplayInfo?) {
        guard let ctx = context, hooksLifetime != nil, event != .wakeDelayed else { return }
        for hook in ctx.config.value.automation.hooks(for: event, display: display?.key) {
            run(hook, event: event, display: display)
        }
    }

    private func run(_ hook: HookSpec, event: HookEvent, display: DisplayInfo?) {
        guard let ctx = context else { return }
        let environment = KitHookPolicy.environment(event: event, displayName: display?.name, displayKey: display?.key)
        // A refusal is kept in SpawnerService.lastProblem for Displays › Automations.
        let spawner = ctx.spawner
        let command = hook.command
        let key = hook.id.rawValue + "." + event.rawValue
        hooksLifetime?.spawn { _ = await spawner.run(command, environment: environment, throttleKey: key) }
    }

    // MARK: Custom actions

    private static func actionID(_ spec: CustomActionSpec) -> DisplayActionID {
        DisplayActionID(rawValue: "a.custom." + spec.id.rawValue)
    }

    private func startActions() {
        guard let ctx = context, let lifetime, actionsLifetime == nil else { return }
        let life = lifetime.child()
        actionsLifetime = life
        for spec in ctx.config.value.automation.actions where !spec.name.isEmpty {
            let id = spec.id
            ctx.actions.register(Action(id: Self.actionID(spec), title: spec.name, feature: .customActions,
                                        cliAllowed: spec.cliAllowed) { [weak self] _ in self?.runAction(id) },
                                 lifetime: life)
            if let combo = spec.shortcut {
                _ = try? ctx.hotkeys.register(combo, owner: L("Action: ") + spec.name, lifetime: life) { [weak self] in
                    self?.runAction(id)
                }
            }
        }
        let items = AutomationMenuItems(context: ctx)
        items.controller = self
        actionMenu = items
        ctx.menus.register(items, lifetime: life)
        ctx.commands.register("action list", policy: .read, offOnly: false, cliAllowed: true,
                              summary: L("List the custom actions the command line may run"), lifetime: life) { [weak self] request, _ in
            self?.listActions(json: request.json) ?? .failure(ControlExit.unavailable, L("Custom actions are off."))
        }
        ctx.commands.register("action run", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Run a custom action: action run <name>"), lifetime: life) { [weak self] request, _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Custom actions are off.")) }
            return await self.runActionFromCLI(request)
        }
    }

    private func stopActions() {
        actionsLifetime?.end()
        actionsLifetime = nil
        actionMenu = nil
    }

    /// Runs a custom action (its menu item, hotkey or action), at most once a second each; only while custom
    /// actions run.
    func runAction(_ id: StableID) {
        guard let ctx = context, actionsLifetime != nil,
              let spec = ctx.config.value.automation.actions.first(where: { $0.id == id }) else { return }
        guard actionThrottle.allow(id.rawValue, now: ProcessInfo.processInfo.systemUptime) else { return }
        let environment = ["PATH": KitHookPolicy.searchPath, "SNAPTIC_EVENT": "action"]
        actionsLifetime?.spawn { [weak self] in
            guard let problem = await ctx.spawner.run(spec.command, environment: environment, throttleKey: nil),
                  let life = self?.actionsLifetime else { return }
            ctx.toasts.show(spec.name + ": " + problem, lifetime: life)
        }
    }

    private func listActions(json: Bool) -> ControlResponse {
        guard let ctx = context else { return .failure(ControlExit.unavailable, L("Custom actions are off.")) }
        let names = ctx.config.value.automation.actions.filter(\.cliAllowed).map(\.cliName).filter { !$0.isEmpty }
        if json {
            let data = (try? JSONSerialization.data(withJSONObject: names)) ?? Data("[]".utf8)
            return .ok(String(decoding: data, as: UTF8.self))
        }
        return .ok(names.isEmpty ? L("No actions are allowed from the command line.") : names.joined(separator: "\n"))
    }

    private func runActionFromCLI(_ request: ControlRequest) async -> ControlResponse {
        guard let ctx = context else { return .failure(ControlExit.unavailable, L("Custom actions are off.")) }
        guard let name = request.arguments.first else { return .failure(ControlExit.usage, L("Usage: action run <name>")) }
        guard let spec = ctx.config.value.automation.action(cliName: name) else {
            return .failure(ControlExit.notFound, L("No such action."))
        }
        // Only actions the user marked "Allow from the command line" (R5.4).
        guard spec.cliAllowed else { return .failure(ControlExit.refused, L("This action isn't allowed from the command line.")) }
        let environment = ["PATH": KitHookPolicy.searchPath, "SNAPTIC_EVENT": "action"]
        if let problem = await ctx.spawner.run(spec.command, environment: environment, throttleKey: "cli." + spec.id.rawValue) {
            return .failure(ControlExit.unavailable, problem)
        }
        return .ok()
    }

    // MARK: DiagnosticsContributor

    /// Counts and states only: no paths, arguments or names.
    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [] }
        let automation = ctx.config.value.automation
        return [
            (L("Hooks"), hooksLifetime == nil ? L("off") : String(automation.hooks.filter(\.enabled).count) + L(" enabled")),
            (L("Custom actions"), actionsLifetime == nil ? L("off")
                : String(automation.actions.count) + L(" (") + String(automation.actions.filter(\.cliAllowed).count)
                    + L(" allowed from the CLI)")),
            (L("Commands running"), String(ctx.spawner.runningCount)),
            (L("Helpers"), ctx.helpers.unavailable ?? L("available")),
            (L("Last problem"), ctx.spawner.lastProblem == nil ? L("none") : L("see Displays › Automations")),
        ]
    }
}
