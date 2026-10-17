import Foundation

/// Diagnostics contributors (lead). Never include serial numbers, EDID bytes,
/// window titles, app names or key codes (PLAN §4.10(2)).
@MainActor final class DiagnosticsRegistry {
    private struct Entry { let serial: UInt64; let section: String; weak var contributor: (any DiagnosticsContributor)? }
    private var entries: [Entry] = []
    private var serial: UInt64 = 0

    init() {}

    func register(_ contributor: any DiagnosticsContributor, section: String, lifetime: Lifetime) {
        guard !lifetime.isEnded else { return }
        serial &+= 1
        let mine = serial
        entries.append(Entry(serial: mine, section: section, contributor: contributor))
        lifetime.onEnd { [weak self] in self?.entries.removeAll { $0.serial == mine || $0.contributor == nil } }
    }

    /// (section, rows) in registration order.
    func collect() -> [(section: String, rows: [(String, String)])] {
        entries.compactMap { entry in
            guard let c = entry.contributor else { return nil }
            return (entry.section, c.diagnostics())
        }
    }
}
