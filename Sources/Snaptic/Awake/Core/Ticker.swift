import AppKit
import SnapticKit

// TriggerController's clock (owner: G; PLAN 0.3 §2.7, N15): one one-shot `.common`-mode timer for the next moment a
// rule can change without a source event (a start or end delay running out, a schedule boundary, a suppression or
// "Pause Rules" ending). Schedule boundaries come from Kit as minutes of the week; the next one is turned into a Date
// with Calendar.autoupdatingCurrent (DST-correct) and capped at 15 minutes, so clock and time-zone changes are
// caught even if their notification is missed.

@MainActor final class Ticker {
    /// The longest wait (schedule boundaries are re-checked at least this often).
    static let maxWait: TimeInterval = 15 * 60
    static let minWait: TimeInterval = 0.25

    private var timer: Timer?
    private(set) var fireDate: Date?

    init() {}

    /// Replaces any pending tick. `seconds` is clamped to 0.25 s … 15 min; tolerance 10%.
    func schedule(after seconds: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        cancel()
        let delay = min(max(seconds.isFinite ? seconds : Self.maxWait, Self.minWait), Self.maxWait)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                self?.fireDate = nil
                fire()
            }
        }
        t.tolerance = delay * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        fireDate = Date(timeIntervalSinceNow: delay)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        fireDate = nil
    }

    /// Seconds from `now` until the next schedule boundary (minutes of the week, Sunday 00:00 = 0) in the current
    /// calendar; nil without boundaries.
    static func secondsToNextBoundary(_ boundaries: Set<Int>, now: Date = Date()) -> TimeInterval? {
        guard !boundaries.isEmpty else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        var best: Date?
        for minute in boundaries {
            let m = ((minute % 10_080) + 10_080) % 10_080
            var match = DateComponents()
            match.weekday = m / 1_440 + 1
            match.hour = (m % 1_440) / 60
            match.minute = m % 60
            match.second = 0
            guard let date = calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime) else { continue }
            if best.map({ date < $0 }) ?? true { best = date }
        }
        return best.map { max(0, $0.timeIntervalSince(now)) }
    }
}
