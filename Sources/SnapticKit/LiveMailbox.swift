import Foundation

/// The latest-wins mailbox behind live hardware sliders (PLAN 0.3 §4.5, `DisplayLiveControlling`): one slot per
/// (display, control). A drag sends its first value at once, then at most one value per `interval` per slot (the
/// newest value replaces one still waiting); the value that ends a drag (`final`) is always sent at once and
/// clears anything waiting, so the hardware ends on exactly what the user let go of.
package struct LiveMailbox<Key: Hashable> {
    private struct Slot {
        var lastSentAt: Double?
        var interval: Double
        var pending: Double?
    }

    private var slots: [Key: Slot] = [:]

    package init() {}

    /// A slider moved to `value`. Returns the value to send now, or nil when it waits for `nextDeadline`
    /// (or was dropped: a non-finite value never reaches hardware). `interval` is the slot's minimum spacing in
    /// seconds (0 = every value goes at once).
    package mutating func submit(_ value: Double, for key: Key, final: Bool, interval: Double, now: Double) -> Double? {
        var slot = slots[key] ?? Slot(interval: 0)
        slot.interval = interval.isFinite ? max(0, interval) : 0
        guard value.isFinite else {
            // A broken final value still lets the newest real value through.
            if final, let pending = slot.pending {
                slot.pending = nil
                slot.lastSentAt = now
                slots[key] = slot
                return pending
            }
            slots[key] = slot
            return nil
        }
        if final || Self.isOpen(slot, now: now) {
            slot.pending = nil
            slot.lastSentAt = now
            slots[key] = slot
            return value
        }
        slot.pending = value
        slots[key] = slot
        return nil
    }

    /// The earliest time a waiting value may be sent; nil when nothing waits.
    package var nextDeadline: Double? {
        slots.values.compactMap { slot -> Double? in
            guard slot.pending != nil else { return nil }
            return (slot.lastSentAt ?? -.infinity) + slot.interval
        }.min()
    }

    /// Takes every waiting value whose slot is open at `now` (in no particular order; keys are distinct).
    package mutating func due(now: Double) -> [(key: Key, value: Double)] {
        var result: [(key: Key, value: Double)] = []
        for (key, slot) in slots {
            guard let value = slot.pending, Self.isOpen(slot, now: now) else { continue }
            var sent = slot
            sent.pending = nil
            sent.lastSentAt = now
            slots[key] = sent
            result.append((key, value))
        }
        return result
    }

    /// Whether a value waits for `key`.
    package func isWaiting(_ key: Key) -> Bool { slots[key]?.pending != nil }

    /// Forgets every slot (the owner stopped).
    package mutating func removeAll() { slots.removeAll() }

    /// Open when nothing was sent yet, the interval passed, or the clock went backwards.
    private static func isOpen(_ slot: Slot, now: Double) -> Bool {
        guard let last = slot.lastSentAt else { return true }
        return now < last || now - last >= slot.interval
    }
}

/// Read-backs after a live change (PLAN 0.3 §4.5): when a drag ends, the shown value is set to the target at once;
/// for `holdSeconds` a hardware read-back that disagrees with it is ignored, so the slider doesn't snap back while
/// the monitor catches up.
package enum LiveReadback {
    package static let holdSeconds: Double = 1
    /// Read-backs within this of the value set count as agreeing (fractions 0…1).
    package static let tolerance: Double = 0.02

    /// Whether a read-back may replace the shown value. `setValue`/`setAt` describe the user's last change, if any.
    package static func accepts(_ reading: Double, setValue: Double?, setAt: Double?, now: Double) -> Bool {
        guard reading.isFinite else { return false }
        guard let setAt, setAt.isFinite, let setValue, setValue.isFinite else { return true }
        // A clock that went backwards can't prove the hold expired: keep holding until it passes setAt again.
        if now >= setAt, now - setAt >= holdSeconds { return true }
        return abs(reading - setValue) <= tolerance
    }
}
