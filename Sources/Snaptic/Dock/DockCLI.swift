import Foundation
import SnapticKit

/// What `DockCLI` reads and changes: the module, or `--selftest-controls`' stand-in for the rows it can't reach
/// without starting the module (§4.22).
@MainActor protocol DockCLITarget: AnyObject {
    /// §4.17's facts now. The CLI asks for an on module's (it's registered only while the module is on).
    func pageFacts(killSwitch: Bool, enabled: Bool) -> DockPageFacts
    /// `dock status`'s facts; nil while the module is off.
    func statusFacts() -> DockStatusFacts?
    /// Holds a command pause, never shortening one (G2-12). Its end in Unix seconds; nil when nothing can hold one.
    func pauseByCommand(seconds: Int) -> Double?
    /// Clears a held command pause. False when none was held.
    func resumeCommandPause() -> Bool
}

/// `snaptic dock …` (lead; PLAN 0.5 §4.21, A9).
///
/// - The verbs are registered whenever the module is on (Starting and rows 3 to 9, Safe Mode included) and end with
///   it, so an off or killed module (rows 1 and 2) answers the house "Unknown command", exit 2.
/// - Policies come from `KitControl.dockVerbRules` (status `.read`, pause `.low` and off only, resume `.low`); the
///   registry applies them and refuses `pause on` before the handler (exit 4).
/// - Each verb parses with Kit `DockCommandGrammar`, then takes the verb × state table's step for the row now
///   (`DockCommandGrammar.step(_:facts:)`). This file only applies it: it holds or clears the command pause and
///   formats the reply. Replies carry states, enums and counts, never an app's name (§4.17).
@MainActor final class DockCLI {
    private weak var target: DockCLITarget?
    private var verbsLifetime: Lifetime?

    init(target: DockCLITarget) {
        self.target = target
    }

    nonisolated static let usage = ControlResponse.failure(ControlExit.usage, DockCommandGrammar.usage)
    /// The registry's answer for a verb nothing registered, given too if the module went away mid-request.
    nonisolated static let unknown = ControlResponse.failure(ControlExit.usage,
                                                             L("Unknown command. Run “snaptic help” for the list."))

    /// The three verbs, on a child of `lifetime`; `stop()` or the end of `lifetime` takes them back.
    func registerVerbs(on commands: ControlCommandRegistry, lifetime: Lifetime) {
        verbsLifetime?.end()
        let life = lifetime.child()
        verbsLifetime = life
        for (verb, summary) in DockCommandGrammar.verbs {
            let rule = KitControl.verbRule("dock " + verb)
            commands.register("dock " + verb, policy: rule?.policy ?? .low, offOnly: rule?.offOnly ?? false,
                              cliAllowed: true, summary: summary, lifetime: life) { [weak self] request, _ in
                self?.handle(verb, request) ?? Self.unknown
            }
        }
    }

    func stop() {
        verbsLifetime?.end()
        verbsLifetime = nil
    }

    var isRegistered: Bool { verbsLifetime != nil }

    private func handle(_ verb: String, _ request: ControlRequest) -> ControlResponse {
        guard let command = DockCommandGrammar.parse(verb: verb, args: request.arguments) else { return Self.usage }
        guard let target else { return Self.unknown }
        switch DockCommandGrammar.step(command, facts: target.pageFacts(killSwitch: false, enabled: true)) {
        case .unknownCommand:
            return Self.unknown
        case .refuse(let refusal):
            return .failure(refusal.exitCode, refusal.message { PermissionFlow.paneName($0) })
        case .status(let json):
            guard let facts = target.statusFacts() else { return Self.unknown }
            return .ok(json || request.json ? DockCommandGrammar.statusJSON(facts) : DockCommandGrammar.statusLine(facts))
        case .pause(let seconds):
            guard let end = target.pauseByCommand(seconds: seconds),
                  let reply = DockCommandGrammar.pausedReply(until: end) else { return Self.unknown }
            return .ok(reply)
        case .resume(let cell):
            if cell.clearsPause { _ = target.resumeCommandPause() }
            return .ok(DockCommandGrammar.resumeReply(cell) ?? "")
        }
    }
}
