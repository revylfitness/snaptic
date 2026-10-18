import Foundation

// Event-log text for management transactions (owner: D). TEAMS rule 3: the event log never carries a display
// name, a layout name or other user text. A request's `label` is user-facing (the confirm panel and toasts show
// it, and callers may name the display in it), so the log describes the request by its change kinds instead.

package enum TransactionLogText {
    /// The neutral word for one change kind.
    package static func kind(_ change: DisplayChange) -> String {
        switch change {
        case .mode: return "resolution"
        case .origin: return "arrangement"
        case .mirror: return "mirroring"
        case .enabled: return "connection"
        case .main: return "main display"
        case .rotation: return "rotation"
        case .underscan: return "underscan"
        case .hdr: return "HDR"
        }
    }

    /// "resolution, arrangement x2 on 2 displays": kinds in first-seen order with counts, then the display count.
    /// Built only from enum cases and numbers, so no caller can put a name in it.
    package static func summary(_ changes: [DisplayChange]) -> String {
        guard !changes.isEmpty else { return "no changes" }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for change in changes {
            let k = kind(change)
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
        }
        let kinds = order.map { k -> String in
            let n = counts[k] ?? 1
            return n > 1 ? "\(k) x\(n)" : k
        }.joined(separator: ", ")
        let displays = Set(changes.map(\.displayID)).count
        return "\(kinds) on \(displays) display\(displays == 1 ? "" : "s")"
    }

    /// One log line: "Transaction (trial, automatic): resolution on 1 display: kept".
    package static func line(changes: [DisplayChange], risk: String, automatic: Bool, outcome: String) -> String {
        "Transaction (\(risk)\(automatic ? ", automatic" : "")): \(summary(changes)): \(outcome)"
    }
}
