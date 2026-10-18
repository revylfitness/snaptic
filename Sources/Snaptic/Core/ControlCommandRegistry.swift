import Foundation
import SnapticKit

/// CLI verbs registered by the host, modules and controllers (PLAN §11, §4.10(3)).
/// Dispatch enforces the rules before any handler runs:
/// - retired 0.2 verbs (`KitControl.retiredVerbs`) get their pointer with exit 2 before lookup and are never listed;
/// - only `cliAllowed` verbs are reachable;
/// - protected settings (hooks, actions, CLI, disconnect, auto-disconnect, dim to black,
///   unlocks, allow flags, trust) are never touchable;
/// - `offOnly` verbs can only turn things off;
/// - `skipConfirmation` reaches a trial handler only when the user allowed it;
/// - only `holds: true` verbs get the connection's `ControlHold` and may answer `holding` (0.3 §2.10);
/// - verbs with a `KitControl.verbRule` (the Awake verbs) get the host's policy, off-only and hold rules whatever
///   the module passed, and `awake start`/`hold`/`stop`/`extend` share one 1/s window (0.3 §3.1, security L3);
///   their requests are only counted, never logged with a time (security S-4).
@MainActor final class ControlCommandRegistry {
    /// 0.3 §2.10: handlers also get the connection's peer and, for `holds: true` verbs, its hold.
    typealias Handler = @MainActor (ControlRequest, ControlContext) async -> ControlResponse

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
    /// The shared window of the session verbs (`ControlVerbRule.sessionLimited`).
    private var sessionRate = ControlRateWindow(limit: KitControl.sessionVerbsPerSecond, window: 1)
    /// The clock of that window, in seconds (the controls self-test drives it).
    var now: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }

    init() {}

    /// `offOnly`: the CLI may only turn the thing off (R5.4). `holds`: the handler gets the connection's hold and
    /// may answer `holding` (§2.10). Ends with `lifetime`. A verb registered twice: the newer registration wins.
    func register(_ verb: String, policy: ControlPolicy, offOnly: Bool, cliAllowed: Bool, holds: Bool = false,
                  summary: String, lifetime: Lifetime, _ handler: @escaping Handler) {
        guard !lifetime.isEnded, Self.isValidVerb(verb) else { return }
        var policy = policy, offOnly = offOnly, holds = holds
        if let rule = KitControl.verbRule(verb) {
            if rule.policy != policy || rule.offOnly != offOnly || rule.holds != holds {
                EventLog.shared.record(.control, "Verb \(verb) registered with other rules; the host's rules apply")
            }
            policy = rule.policy
            offOnly = rule.offOnly
            holds = rule.holds
        }
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
        // R5-12: a retired 0.2 verb gets its pointer before lookup, whatever is registered.
        if let retired = KitControl.retiredVerb(words) {
            EventLog.shared.record(.control, "CLI \(retired.verb) refused: retired")
            return .failure(ControlExit.usage, retired.message)
        }

        let reachable = entries.filter(\.cliAllowed)
        guard let match = KitControl.match(words, verbs: reachable.map(\.verb)),
              let entry = reachable.first(where: { $0.verb == match.verb }) else {
            return .failure(ControlExit.usage, L("Unknown command. Run “snaptic help” for the list."))
        }
        if let setting = KitControl.protectedSetting(verb: entry.verb, arguments: match.arguments) {
            note(entry.verb, .refusedProtected, "CLI \(entry.verb) refused: protected setting")
            return .failure(ControlExit.refused, L("“") + setting + L("” can't be changed from the command line."))
        }
        if entry.offOnly && KitControl.requestsTurningOn(match.arguments) {
            note(entry.verb, .refusedOffOnly, "CLI \(entry.verb) refused: off-only")
            return .failure(ControlExit.refused, L("From the command line this can only be turned off."))
        }
        if KitControl.verbRule(entry.verb)?.sessionLimited == true, !sessionRate.allow(now: now()) {
            note(entry.verb, .refusedRate, "CLI \(entry.verb) refused: rate")
            return .failure(ControlExit.unavailable, L("Too many Awake requests; wait a second and try again."))
        }
        let skip = KitControl.skipsConfirmation(requested: request.skipConfirmation, allowed: skipConfirmationAllowed,
                                                policy: entry.policy)
        let forwarded = ControlRequest(verb: entry.verb, arguments: match.arguments, json: request.json,
                                       skipConfirmation: skip)
        let context = ControlContext(peer: peer, hold: entry.holds ? hold : nil)
        var response = await entry.handler(forwarded, context)
        // Only a hold verb keeps its connection; from any other verb a `holding` reply is an ordinary close.
        if response.holding && !(entry.holds && response.exitCode == ControlExit.ok) { response.holding = false }
        note(entry.verb, ControlVerbOutcome(exitCode: response.exitCode, holding: response.holding),
             "CLI \(entry.verb) → \(response.exitCode)" + (skip ? " (no panel)" : "") + (response.holding ? " (holding)" : ""))
        // FIXES-R3 10: with --json every successful reply is JSON.
        return request.json ? KitControl.jsonReply(response) : response
    }

    /// Security S-4: a verb with a host rule (the Awake verbs) is only counted, under a fixed key with no time, so
    /// the exported `.control` log keeps no timeline of when scripts kept the Mac awake; other verbs get a line.
    private func note(_ verb: String, _ outcome: ControlVerbOutcome, _ line: @autoclosure () -> String) {
        if let key = KitControl.counterKey(verb: verb, outcome: outcome) {
            EventLog.shared.count(key)
        } else {
            EventLog.shared.record(.control, line())
        }
    }

    private func help(_ topic: [String], json: Bool) -> ControlResponse {
        // Retired verbs are never listed (R5-12), even if something registered one.
        let reachable = entries.filter { $0.cliAllowed && KitControl.retiredVerb([$0.verb]) == nil }
            .sorted { $0.verb < $1.verb }
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
