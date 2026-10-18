import Foundation
import SnapticKit

/// CLI verbs registered by the host, modules and controllers (PLAN §11, §4.10(3)).
/// Dispatch enforces the rules before any handler runs:
/// - only `cliAllowed` verbs are reachable;
/// - protected settings (hooks, actions, CLI, disconnect, auto-disconnect, dim to black,
///   unlocks, allow flags, trust) are never touchable;
/// - `offOnly` verbs can only turn things off;
/// - `skipConfirmation` reaches a trial handler only when the user allowed it;
/// - only `holds: true` verbs get the connection's `ControlHold` and may answer `holding` (0.3 §2.10).
@MainActor final class ControlCommandRegistry {
    /// 0.3 §2.10: handlers also get the connection's peer and, for `holds: true` verbs, its hold.
    typealias Handler = @MainActor (ControlRequest, ControlContext) async -> ControlResponse
    /// The 0.2 one-argument handler; kept through an overload until the step-3 exit.
    typealias LegacyHandler = @MainActor (ControlRequest) async -> ControlResponse

    struct Entry {
        let verb: String
        let policy: ControlPolicy
        let offOnly: Bool
        let cliAllowed: Bool
        /// May keep the connection open with a `holding` reply (§2.10).
        let holds: Bool
        let summary: String
        let handler: Handler
        fileprivate let serial: UInt64
    }

    private var entries: [Entry] = []
    private var serial: UInt64 = 0
    var onChange: (@MainActor () -> Void)?

    init() {}

    /// `offOnly`: the CLI may only turn the thing off (R5.4). `holds`: the handler gets the connection's hold and
    /// may answer `holding` (§2.10). Ends with `lifetime`. A verb registered twice: the newer registration wins.
    func register(_ verb: String, policy: ControlPolicy, offOnly: Bool, cliAllowed: Bool, holds: Bool = false,
                  summary: String, lifetime: Lifetime, _ handler: @escaping Handler) {
        guard !lifetime.isEnded, Self.isValidVerb(verb) else { return }
        serial &+= 1
        let mine = serial
        if entries.contains(where: { $0.verb == verb }) {
            EventLog.shared.record(.control, "Verb \(verb) registered twice; the newer one wins")
            entries.removeAll { $0.verb == verb }
        }
        entries.append(Entry(verb: verb, policy: policy, offOnly: offOnly, cliAllowed: cliAllowed, holds: holds,
                             summary: summary, handler: handler, serial: mine))
        onChange?()
        lifetime.onEnd { [weak self] in
            self?.entries.removeAll { $0.serial == mine }
            self?.onChange?()
        }
    }

    /// The 0.2 form: a one-argument handler, never a hold. Removed at the step-3 exit.
    func register(_ verb: String, policy: ControlPolicy, offOnly: Bool, cliAllowed: Bool, summary: String,
                  lifetime: Lifetime, _ handler: @escaping LegacyHandler) {
        register(verb, policy: policy, offOnly: offOnly, cliAllowed: cliAllowed, holds: false, summary: summary,
                 lifetime: lifetime) { request, _ in await handler(request) }
    }

    /// Registered verbs, sorted.
    var all: [Entry] { entries.sorted { $0.verb < $1.verb } }

    func entry(_ verb: String) -> Entry? { entries.first { $0.verb == verb } }

    /// Lowercase words separated by single spaces ("layout apply", "open-settings").
    static func isValidVerb(_ verb: String) -> Bool {
        let words = verb.split(separator: " ", omittingEmptySubsequences: false)
        return !words.isEmpty && words.count <= KitControl.maxVerbWords && words.allSatisfy { KitControl.isVerbWord(String($0)) }
    }

    // MARK: Dispatch

    /// Runs one request from the control server. `peer` and `hold` describe the connection (the hold reaches the
    /// handler only for `holds: true` verbs); `skipConfirmationAllowed` is the user's "Let commands skip the
    /// confirmation panel" setting.
    func dispatch(_ request: ControlRequest, peer: ControlPeer, hold: ControlHold,
                  skipConfirmationAllowed: Bool) async -> ControlResponse {
        let words = request.verb.split(separator: " ").map(String.init) + request.arguments
        if words.first == "help" { return help(Array(words.dropFirst()), json: request.json) }

        let reachable = entries.filter(\.cliAllowed)
        guard let match = KitControl.match(words, verbs: reachable.map(\.verb)),
              let entry = reachable.first(where: { $0.verb == match.verb }) else {
            return .failure(ControlExit.usage, L("Unknown command. Run “snaptic help” for the list."))
        }
        if let setting = KitControl.protectedSetting(verb: entry.verb, arguments: match.arguments) {
            EventLog.shared.record(.control, "CLI \(entry.verb) refused: protected setting")
            return .failure(ControlExit.refused, L("“") + setting + L("” can't be changed from the command line."))
        }
        if entry.offOnly && KitControl.requestsTurningOn(match.arguments) {
            EventLog.shared.record(.control, "CLI \(entry.verb) refused: off-only")
            return .failure(ControlExit.refused, L("From the command line this can only be turned off."))
        }
        let skip = KitControl.skipsConfirmation(requested: request.skipConfirmation, allowed: skipConfirmationAllowed,
                                                policy: entry.policy)
        let forwarded = ControlRequest(verb: entry.verb, arguments: match.arguments, json: request.json,
                                       skipConfirmation: skip)
        let context = ControlContext(peer: peer, hold: entry.holds ? hold : nil)
        var response = await entry.handler(forwarded, context)
        // Only a hold verb keeps its connection; from any other verb a `holding` reply is an ordinary close.
        if response.holding && !(entry.holds && response.exitCode == ControlExit.ok) { response.holding = false }
        EventLog.shared.record(.control, "CLI \(entry.verb) → \(response.exitCode)" + (skip ? " (no panel)" : "")
                               + (response.holding ? " (holding)" : ""))
        // FIXES-R3 10: with --json every successful reply is JSON.
        return request.json ? KitControl.jsonReply(response) : response
    }

    private func help(_ topic: [String], json: Bool) -> ControlResponse {
        let reachable = entries.filter(\.cliAllowed).sorted { $0.verb < $1.verb }
        let shown: [Entry]
        if topic.isEmpty {
            shown = reachable
        } else {
            let prefix = topic.joined(separator: " ").lowercased()
            shown = reachable.filter { $0.verb == prefix || $0.verb.hasPrefix(prefix + " ") }
            if shown.isEmpty { return .failure(ControlExit.notFound, L("No such command.")) }
        }
        if json {
            let rows = shown.map { ["verb": $0.verb, "summary": $0.summary, "offOnly": $0.offOnly ? "yes" : "no"] }
            let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])) ?? Data("[]".utf8)
            return .ok(String(decoding: data, as: UTF8.self))
        }
        let width = min(28, shown.map(\.verb.count).max() ?? 0)
        var lines = [L("Usage: snaptic [--json] [--yes] <command> [arguments]"), ""]
        for entry in shown {
            let pad = String(repeating: " ", count: max(1, width - entry.verb.count + 2))
            lines.append("  " + entry.verb + pad + entry.summary + (entry.offOnly ? L(" (off only)") : ""))
        }
        lines.append("")
        lines.append(L("Exit codes: 0 ok, 2 usage, 3 not found, 4 refused, 5 unavailable, 6 cancelled."))
        return .ok(lines.joined(separator: "\n"))
    }
}
