import Foundation

// Battery history math (owner: J; PLAN 0.3 R5-6). PowerMonitor keeps the history in memory only, never persisted.

package struct BatteryReading: Equatable, Sendable {
    package var percent: Int
    package var charging: Bool
    /// IOPS kIOPSCurrentKey ("Current"), signed; < 0 = battery discharging.
    package var currentMilliamps: Int?
    /// Continuous clock.
    package var at: Double

    package init(percent: Int, charging: Bool, currentMilliamps: Int?, at: Double) {
        self.percent = percent
        self.charging = charging
        self.currentMilliamps = currentMilliamps
        self.at = at
    }
}

package enum PowerMath {
    package static let fallingWindowSeconds: Double = 600
    package static let maxReadings = 64
    /// The 60 s re-check while `falling` is true, so the flag ages out without a new IOPS notification.
    package static let recheckSeconds: Double = 60

    /// Appends `r` (in time order; a reading with a non-finite instant is ignored), drops readings older than the
    /// window before the newest one but keeps the newest older one as a baseline; ≤ 64 entries.
    package static func appending(_ r: BatteryReading, to history: [BatteryReading]) -> [BatteryReading] {
        var all = history.filter { $0.at.isFinite }
        if r.at.isFinite { all.append(r) }
        guard let newest = all.map(\.at).max() else { return [] }
        // Stable sort: readings at the same instant keep their arrival order.
        all = all.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        let cutoff = newest - fallingWindowSeconds
        var kept: [BatteryReading] = []
        if let baseline = all.last(where: { $0.at < cutoff }) { kept.append(baseline) }
        kept += all.filter { $0.at >= cutoff }
        if kept.count > maxReadings { kept.removeFirst(kept.count - maxReadings) }
        return kept
    }

    /// True iff some event inside the window (a percent decrease between two consecutive readings, or
    /// `currentMilliamps < 0`) has no later reading with `charging == true` or a higher percent than the event's.
    /// Equal consecutive readings never clear it. "Inside the window" = the event's reading is at most
    /// `fallingWindowSeconds` older than `now`. A reading that itself reports charging is a recovery, never an event
    /// (consistent with "a charging reading clears").
    package static func falling(_ history: [BatteryReading], now: Double) -> Bool {
        guard now.isFinite else { return true }
        let cutoff = now - fallingWindowSeconds
        for (i, r) in history.enumerated() where r.at >= cutoff && !r.charging {
            let decrease = i > 0 && r.percent < history[i - 1].percent
            let draining = (r.currentMilliamps ?? 0) < 0
            guard decrease || draining else { continue }
            let recovered = history[(i + 1)...].contains { $0.charging || $0.percent > r.percent }
            if !recovered { return true }
        }
        return false
    }

    /// Continuous instant of the newest reading with `charging == true` or a percent rise over the reading before it;
    /// nil if none.
    package static func lastRecovery(_ history: [BatteryReading]) -> Double? {
        for i in history.indices.reversed() {
            let r = history[i]
            if r.charging || (i > 0 && r.percent > history[i - 1].percent) { return r.at }
        }
        return nil
    }

    /// Percent from IOPS capacities (kIOPSCurrentCapacityKey / kIOPSMaxCapacityKey), 0...100; nil when unreadable.
    package static func percent(current: Int?, max: Int?) -> Int? {
        guard let current, let max, max > 0, current >= 0 else { return nil }
        let p = (Double(current) * 100 / Double(max)).rounded()
        return Int(Swift.min(100, Swift.max(0, p)))
    }
}
