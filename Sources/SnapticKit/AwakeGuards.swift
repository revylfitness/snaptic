import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.6 + R5-6 + R5-13 (kind S): safe returns;
// the lossy decoders are real. PowerMath and BatteryReading (J) live in PowerMath.swift.

package enum ThermalLevel: Int, Codable, Sendable, Comparable {
    case nominal, fair, serious, critical
    package static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

package struct PowerFacts: Equatable, Sendable {
    /// Latched for the process lifetime (r3 security M3).
    package var batteryPresent: Bool
    package var onAC: Bool
    /// nil = unreadable.
    package var percent: Int?
    package var charging: Bool
    /// R5-6: PowerMath.falling over a 10-min window.
    package var falling: Bool
    /// R5-6: newest reading with charging or a percent rise (continuous).
    package var lastRecovery: Double?
    package var lowPowerMode: Bool
    package var thermal: ThermalLevel

    /// Battery present AND (not on AC OR falling within the window). Stub: true (fail-safe for guards).
    package var discharging: Bool { true }

    package init(batteryPresent: Bool, onAC: Bool, percent: Int?, charging: Bool, falling: Bool, lastRecovery: Double?,
                 lowPowerMode: Bool, thermal: ThermalLevel) {
        self.batteryPresent = batteryPresent
        self.onAC = onAC
        self.percent = percent
        self.charging = charging
        self.falling = falling
        self.lastRecovery = lastRecovery
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
    }
}

package struct AwakeGuardsConfig: ConfigModel {
    /// true ("When the battery is low"); off leaves the 5% hard floor.
    package var batteryFloorEnabled: Bool
    /// 20; 5...50, step 5.
    package var batteryFloor: Int
    package var endOnAdapterDisconnect: Bool
    package var endOnLowPowerMode: Bool

    package init() {
        batteryFloorEnabled = true
        batteryFloor = 20
        endOnAdapterDisconnect = false
        endOnLowPowerMode = false
    }

    private enum CodingKeys: String, CodingKey { case batteryFloorEnabled, batteryFloor, endOnAdapterDisconnect, endOnLowPowerMode }

    /// Lossy per field (R5-3).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AwakeGuardsConfig()
        batteryFloorEnabled = c.lossy(.batteryFloorEnabled, d.batteryFloorEnabled)
        batteryFloor = c.lossy(.batteryFloor, d.batteryFloor)
        endOnAdapterDisconnect = c.lossy(.endOnAdapterDisconnect, d.endOnAdapterDisconnect)
        endOnLowPowerMode = c.lossy(.endOnLowPowerMode, d.endOnLowPowerMode)
    }

    package func sanitized() -> AwakeGuardsConfig { self }

    /// Import rule (security M7): every field may only become stricter than `current`. Stub: `current`.
    package func monotonic(over current: AwakeGuardsConfig) -> AwakeGuardsConfig { current }
}

/// Persisted in the snapshot (same boot only).
package struct GuardMemory: Codable, Equatable, Sendable {
    package var unreadableReads: Int = 0
    package var holding: AwakeEndReason? = nil
    /// Continuous clock.
    package var heldSince: Double? = nil
    package var warnedSerious: Bool = false
    /// Continuous; §2.4 backoff.
    package var assertionHoldUntil: Double? = nil
    package var assertionFailures: Int = 0

    package init() {}

    private enum CodingKeys: String, CodingKey {
        case unreadableReads, holding, heldSince, warnedSerious, assertionHoldUntil, assertionFailures
    }

    /// Lossy per field (rule 9).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unreadableReads = c.lossy(.unreadableReads, 0)
        holding = c.lossy(.holding, nil)
        heldSince = c.lossy(.heldSince, nil)
        warnedSerious = c.lossy(.warnedSerious, false)
        assertionHoldUntil = c.lossy(.assertionHoldUntil, nil)
        assertionFailures = c.lossy(.assertionFailures, 0)
    }

    /// At load: on a boot mismatch everything except `warnedSerious` resets. Stub: a fresh value.
    package func reloaded(sameBoot: Bool) -> GuardMemory { GuardMemory() }

    /// R5-13: one more failed assertion create (backoff 30 s → 2 min → 10 min). Stub: unchanged.
    package func recordingAssertionFailure(now: Double) -> GuardMemory { self }

    /// R5-13: a successful create or a user start clears the assertion hold. Stub: unchanged.
    package func clearingAssertionHold() -> GuardMemory { self }
}

package enum AwakeGuardVerdict: Equatable, Sendable { case allow, end(AwakeEndReason), warn(AwakeEndReason) }

package enum AwakeGuards {
    /// Fixed floor (N10): not stored, not exported, no kill switch.
    package static let hardFloorPercent = 5
    package static let hysteresisPercent = 5
    package static let thermalCooldownSeconds: Double = 600

    /// Stub: allow, memory unchanged.
    package static func evaluate(_ now: PowerFacts, previous: PowerFacts?, config: AwakeGuardsConfig,
                                 memory: GuardMemory, time: Double, active: Bool,
                                 overrideBattery: Bool) -> (verdict: AwakeGuardVerdict, memory: GuardMemory) {
        (.allow, memory)
    }

    /// Drive Alive and activity may run only if this is true. Stub: false (safe).
    package static func allowsBackgroundWork(_ now: PowerFacts, config: AwakeGuardsConfig, memory: GuardMemory) -> Bool {
        false
    }

    /// R5-13: 1 → 30, 2 → 120, ≥ 3 → 600 seconds. Stub: 600.
    package static func assertionBackoffSeconds(failures: Int) -> Double { 600 }
}
