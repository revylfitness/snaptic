import Foundation
import SnapticKit

/// In-memory ring buffer for diagnostics. Never store serial numbers, EDID bytes,
/// window titles, app names or key codes here (PLAN §4.10(2)).
final class EventLog: @unchecked Sendable {
    struct Entry: Sendable {
        let date: Date
        let category: EventCategory
        let message: String
    }

    static let shared = EventLog()

    private let lock = NSLock()
    private var ring: [Entry] = []
    private let capacity = 500
    private var counts: [String: Int] = [:]

    private init() {}

    func record(_ category: EventCategory, _ message: String) {
        let entry = Entry(date: Date(), category: category, message: String(message.prefix(512)))
        lock.lock(); defer { lock.unlock() }
        ring.append(entry)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
    }

    /// The only writer of the Awake category (0.3 §3.6, lint L9): a closed event with a fixed text. Counted cases
    /// only bump their counter (no timestamp, so the log keeps no activity timeline); the error cases go into the ring,
    /// and the lid's also bump a counter (0.3.4, `AwakeLogEvent.counterKey`).
    func record(_ event: AwakeLogEvent) {
        if !event.isCounted { record(EventCategory.awake, event.text) }
        // The keys are fixed per case (`counterKey`), so the map stays as small as the enum.
        if let key = event.counterKey { count(key) }
    }

    /// Bumps a fixed counter (security S-4: `KitControl.counterKey` for the Awake verbs) instead of a timestamped
    /// ring line. Keys come only from closed sets, so the map stays small.
    func count(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        counts[key] = min((counts[key] ?? 0), Int.max - 1) + 1
    }

    /// Awake event counts per counted case's text, for `AwakeDiagnostics` (no timestamps).
    var awakeCounts: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return counts
    }

    func recent(_ count: Int) -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return Array(ring.suffix(count))
    }
}
