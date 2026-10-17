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

    private init() {}

    func record(_ category: EventCategory, _ message: String) {
        let entry = Entry(date: Date(), category: category, message: String(message.prefix(512)))
        lock.lock(); defer { lock.unlock() }
        ring.append(entry)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
    }

    func recent(_ count: Int) -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return Array(ring.suffix(count))
    }
}
