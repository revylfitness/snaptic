import Foundation

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 R5-6 (kind S): safe returns.

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
    /// Appends `r`, drops readings older than the window but keeps the newest older one; ≤ 64 entries. Stub: [r].
    package static func appending(_ r: BatteryReading, to history: [BatteryReading]) -> [BatteryReading] { [r] }
    /// Stub: true (fail-safe: the battery rules apply).
    package static func falling(_ history: [BatteryReading], now: Double) -> Bool { true }
    /// Stub: nil.
    package static func lastRecovery(_ history: [BatteryReading]) -> Double? { nil }
}
