import Foundation
import SnapticKit

/// CLI verbs registered by modules and controllers (PLAN §11). The control server that
/// serves them arrives with step 2; registrations already record and end with their
/// lifetime, so modules can wire their verbs now.
@MainActor final class ControlCommandRegistry {
    typealias Handler = @MainActor (ControlRequest) async -> ControlResponse

    struct Entry {
        let verb: String
        let policy: ControlPolicy
        let offOnly: Bool
        let cliAllowed: Bool
        let summary: String
        let handler: Handler
        fileprivate let serial: UInt64
    }

    private var entries: [Entry] = []
    private var serial: UInt64 = 0

    init() {}

    /// `offOnly`: the CLI may only turn the thing off (R5.4). Ends with `lifetime`.
    /// A verb registered twice: the newer registration wins.
    func register(_ verb: String, policy: ControlPolicy, offOnly: Bool, cliAllowed: Bool, summary: String,
                  lifetime: Lifetime, _ handler: @escaping Handler) {
        guard !lifetime.isEnded, Self.isValidVerb(verb) else { return }
        serial &+= 1
        let mine = serial
        if entries.contains(where: { $0.verb == verb }) {
            EventLog.shared.record(.control, "Verb \(verb) registered twice; the newer one wins")
            entries.removeAll { $0.verb == verb }
        }
        entries.append(Entry(verb: verb, policy: policy, offOnly: offOnly, cliAllowed: cliAllowed, summary: summary,
                             handler: handler, serial: mine))
        lifetime.onEnd { [weak self] in self?.entries.removeAll { $0.serial == mine } }
    }

    /// Registered verbs, sorted.
    var all: [Entry] { entries.sorted { $0.verb < $1.verb } }

    func entry(_ verb: String) -> Entry? { entries.first { $0.verb == verb } }

    /// Lowercase words separated by single spaces or dashes ("layout apply", "open-settings").
    static func isValidVerb(_ verb: String) -> Bool {
        let utf8 = verb.utf8
        guard !utf8.isEmpty, utf8.count <= 48, utf8.first != 0x20, utf8.last != 0x20 else { return false }
        return utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D || $0 == 0x20 }
    }
}
