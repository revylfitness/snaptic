import Foundation
import SnapticKit

/// `snaptic icons …` and the Show or Hide Hidden Icons shortcut (lead; PLAN 0.4 §4.14, A9).
///
/// - The verbs are registered only while the module runs, so an off module answers the house "Unknown command".
/// - Policies come from `KitControl.iconsVerbRules` (status `.read`, the rest `.low`); the registry applies them.
/// - `show`, `hide` and `toggle` go through the intent queue from `.cli`, which never asks first (§4.0). A collapse is
///   awaited, so a refusal answers with its line and exit 5.
/// - Replies carry an engine, a state and counts, never an app's name or bundle id (§4.15).
/// - The shortcut toggles from `.shortcut` (debounced in the queue) and re-registers when it changes.
@MainActor final class IconsCLI {
    private weak var module: IconsModule?
    private var verbsLifetime: Lifetime?
    private var shortcutLifetime: Lifetime?
    private var registeredShortcut: HotkeyCombo?
    private weak var context: ModuleContext?

    init(module: IconsModule) {
        self.module = module
    }

    nonisolated static let usage = ControlResponse.failure(ControlExit.usage,
                                                           L("Usage error. Run “snaptic help icons”."))
    private static let unavailable = ControlResponse.failure(IconsCLIRefusal.unavailable.exitCode,
                                                             IconsCLIRefusal.unavailable.message)

    func start(_ context: ModuleContext) {
        self.context = context
        registerVerbs(on: context.commands, lifetime: context.lifetime)
        shortcutChanged()
    }

    func stop() {
        verbsLifetime?.end()
        verbsLifetime = nil
        shortcutLifetime?.end()
        shortcutLifetime = nil
        registeredShortcut = nil
        context = nil
    }

    // MARK: Verbs

    /// The four verbs, on a child of `lifetime` (`--selftest-controls` runs them against a stopped module).
    func registerVerbs(on commands: ControlCommandRegistry, lifetime: Lifetime) {
        verbsLifetime?.end()
        let life = lifetime.child()
        verbsLifetime = life
        for (verb, summary) in IconsCommandGrammar.verbs {
            let rule = KitControl.verbRule("icons " + verb)
            commands.register("icons " + verb, policy: rule?.policy ?? .low, offOnly: false, cliAllowed: true,
                              summary: summary, lifetime: life) { [weak self] request, _ in
                await self?.handle(verb, request) ?? Self.unavailable
            }
        }
    }

    private func handle(_ verb: String, _ request: ControlRequest) async -> ControlResponse {
        guard let module, let parsed = IconsCommandGrammar.parse(verb: verb, args: request.arguments) else {
            return Self.usage
        }
        let facts = module.cliFacts()
        guard let command = parsed.command else {
            guard case .status(let json) = parsed else { return Self.usage }
            return .ok(json || request.json ? IconsCommandGrammar.statusJSON(facts)
                                            : IconsCommandGrammar.statusLine(facts))
        }
        if let refusal = IconsCLIRules.refusal(state: facts.state, collapsed: module.engineState.isCollapsed) {
            return .failure(refusal.exitCode, refusal.message)
        }
        let result: IconsCollapseResult? = await withCheckedContinuation { continuation in
            var resumed = false
            module.perform(command, from: .cli) { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }
        }
        guard let result else { return .ok() }
        if let failure = IconsCLIRules.failure(after: result, statusText: module.statusText()) {
            return .failure(failure.exit, failure.message)
        }
        return .ok()
    }

    // MARK: Shortcut

    /// Registers `IconsConfig.shortcut` (unset by default) when it changed; a conflict or a refused combo leaves it
    /// unregistered (the Settings row shows the conflict).
    func shortcutChanged() {
        guard let context, let module else { return }
        let combo = module.config.value.shortcut
        guard combo != registeredShortcut || (combo != nil && shortcutLifetime == nil) else { return }
        shortcutLifetime?.end()
        shortcutLifetime = nil
        registeredShortcut = combo
        guard let combo else { return }
        let life = context.lifetime.child()
        do {
            _ = try context.hotkeys.register(combo, owner: IconsPageRules.shortcutName, lifetime: life) { [weak self] in
                self?.module?.perform(.toggle, from: .shortcut)
            }
            shortcutLifetime = life
        } catch {
            life.end()
            EventLog.shared.record(.icons, "Icons: shortcut not registered")
        }
    }
}
