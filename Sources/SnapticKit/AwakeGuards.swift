import Foundation

// Guards (owner: G; PLAN 0.3 §2.6, N10, R5-6, R5-13). PowerMath and BatteryReading (J) live in PowerMath.swift;
// `falling` and `lastRecovery` arrive here already computed.

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
    /// Consecutive reads (PowerMonitor, `PowerMath.unreadableStreak`) that found the latched battery without a
    /// percent; 0 after a readable read and on desktops. `AwakeGuards.unreadableReadsToConfirm` of them make the
    /// battery unreadable (§2.6).
    package var unreadableStreak: Int

    /// Battery present AND (not on AC OR falling within the window): a weak adapter that reports AC while the battery
    /// drains counts as discharging (R5-6).
    package var discharging: Bool { batteryPresent && (!onAC || falling) }

    package init(batteryPresent: Bool, onAC: Bool, percent: Int?, charging: Bool, falling: Bool, lastRecovery: Double?,
                 lowPowerMode: Bool, thermal: ThermalLevel, unreadableStreak: Int = 0) {
        self.batteryPresent = batteryPresent
        self.onAC = onAC
        self.percent = percent
        self.charging = charging
        self.falling = falling
        self.lastRecovery = lastRecovery
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
        self.unreadableStreak = unreadableStreak
    }
}

package struct AwakeGuardsConfig: ConfigModel {
    package static let floorRange: ClosedRange<Int> = 5...50
    package static let floorStep = 5

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

    /// The floor clamped to 5...50 and snapped to the nearest step of 5 (ties round up, the stricter side).
    package func sanitized() -> AwakeGuardsConfig {
        var c = self
        let clamped = AwakeMath.clamp(batteryFloor, Self.floorRange)
        let snapped = ((clamped + Self.floorStep / 2) / Self.floorStep) * Self.floorStep
        c.batteryFloor = AwakeMath.clamp(snapped, Self.floorRange)
        return c
    }

    /// Import rule (security M7): every field may only become stricter than `current`.
    package func monotonic(over current: AwakeGuardsConfig) -> AwakeGuardsConfig {
        let mine = sanitized(), base = current.sanitized()
        var c = base
        c.batteryFloorEnabled = base.batteryFloorEnabled || mine.batteryFloorEnabled
        c.batteryFloor = max(base.batteryFloor, mine.batteryFloor)
        c.endOnAdapterDisconnect = base.endOnAdapterDisconnect || mine.endOnAdapterDisconnect
        c.endOnLowPowerMode = base.endOnLowPowerMode || mine.endOnLowPowerMode
        return c
    }

    /// The floor battery rules use: the user floor when enabled, else the hard floor.
    package var effectiveFloor: Int { batteryFloorEnabled ? sanitized().batteryFloor : AwakeGuards.hardFloorPercent }
}

/// Persisted in the snapshot (same boot only).
package struct GuardMemory: Codable, Equatable, Sendable {
    /// Consecutive reads with no percent on a latched battery, as of the last evaluation (the facts' read streak,
    /// so re-evaluating the same read never counts twice); ≥ `AwakeGuards.unreadableReadsToConfirm` = unreadable.
    package var unreadableReads: Int = 0
    /// Blocks trigger starts until cleared.
    package var holding: AwakeEndReason? = nil
    /// Continuous clock.
    package var heldSince: Double? = nil
    package var warnedSerious: Bool = false
    /// Continuous; §2.4 backoff.
    package var assertionHoldUntil: Double? = nil
    package var assertionFailures: Int = 0
    /// Continuous instant the thermal level last dropped to fair or below while a thermal hold exists.
    package var coolSince: Double? = nil
    /// Low Power Mode was on at the last evaluation (the "Awake keeps running." notice fires on the turn-on).
    package var lowPowerSeen: Bool = false

    package init() {}

    private enum CodingKeys: String, CodingKey {
        case unreadableReads, holding, heldSince, warnedSerious, assertionHoldUntil, assertionFailures, coolSince,
             lowPowerSeen
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
        coolSince = c.lossy(.coolSince, nil)
        lowPowerSeen = c.lossy(.lowPowerSeen, false)
    }

    /// Values clamped to what the guards can produce (a snapshot is outside input).
    package func sanitized() -> GuardMemory {
        var m = self
        m.unreadableReads = AwakeMath.clamp(unreadableReads, 0...1_000)
        m.assertionFailures = AwakeMath.clamp(assertionFailures, 0...1_000)
        if let h = heldSince, !h.isFinite { m.heldSince = nil }
        if let a = assertionHoldUntil, !a.isFinite { m.assertionHoldUntil = nil }
        if let c = coolSince, !c.isFinite { m.coolSince = nil }
        switch holding {
        case .batteryLow?, .thermal?, .lowPowerMode?, .adapterDisconnected?, nil: break
        default: m.holding = nil
        }
        if m.holding == nil { m.heldSince = nil }
        if m.holding != nil && m.heldSince == nil { m.heldSince = 0 }
        if m.holding != .thermal { m.coolSince = nil }
        return m
    }

    /// At load: same boot keeps the holds (they only block rule starts, the strict direction; the next `evaluate`
    /// recomputes them from live facts) but recounts unreadable reads; a boot mismatch resets everything except
    /// `warnedSerious` (the continuous clock restarted).
    package func reloaded(sameBoot: Bool) -> GuardMemory {
        if sameBoot {
            var m = sanitized()
            m.unreadableReads = 0
            return m
        }
        var m = GuardMemory()
        m.warnedSerious = warnedSerious
        return m
    }

    /// R5-13: one more failed assertion create (backoff 30 s → 2 min → 10 min).
    package func recordingAssertionFailure(now: Double) -> GuardMemory {
        var m = self
        m.assertionFailures = min(AwakeMath.adding(assertionFailures, 1), 1_000)
        m.assertionHoldUntil = now + AwakeGuards.assertionBackoffSeconds(failures: m.assertionFailures)
        return m
    }

    /// R5-13: a successful create or a user start clears the assertion hold.
    package func clearingAssertionHold() -> GuardMemory {
        var m = self
        m.assertionFailures = 0
        m.assertionHoldUntil = nil
        return m
    }

    /// Rule starts are blocked now: a guard hold, or an assertion hold that hasn't run out.
    package func blocksTriggers(at time: Double) -> Bool {
        if holding != nil { return true }
        if let until = assertionHoldUntil, time < until { return true }
        return false
    }
}

package enum AwakeGuardVerdict: Equatable, Sendable { case allow, end(AwakeEndReason), warn(AwakeEndReason) }

/// Why activity and Drive Alive are stopped by the guards (`AwakeGuards.backgroundBlock`).
package enum AwakeBackgroundBlock: Equatable, Sendable { case heat, batteryUnreadable, batteryLow }

package enum AwakeGuards {
    /// Fixed floor (N10): not stored, not exported, no kill switch.
    package static let hardFloorPercent = 5
    package static let hysteresisPercent = 5
    package static let thermalCooldownSeconds: Double = 600
    /// §2.6: two consecutive reads with no percent on a latched battery make it unreadable (one is a blip; PowerMonitor
    /// re-reads within 60 s after the first, `PowerMath.needsRecheck`).
    package static let unreadableReadsToConfirm = 2

    /// One evaluation (§2.6, R5-6). The verdict says what the facts allow: `.end(r)` ends what runs (`active`) or
    /// refuses a start; `.warn(r)` asks for a one-time notice while active (serious heat, Low Power Mode turning on).
    /// Order: critical heat (never overridable), the 5% hard floor while discharging (never overridable), the user
    /// floor while discharging, adapter disconnect (a transition while active), Low Power Mode; Start Anyway
    /// (`overrideBattery`) skips only the user floor and Low Power Mode. Desktops (battery never latched) skip the
    /// battery rules. `memory.holding` blocks rule starts and clears only by its own rule: battery at floor + 5 or a
    /// recovery after the hold began (never on equal readings), Low Power Mode off, adapter back, or 10 min at fair
    /// heat or below.
    package static func evaluate(_ now: PowerFacts, previous: PowerFacts?, config: AwakeGuardsConfig,
                                 memory: GuardMemory, time: Double, active: Bool,
                                 overrideBattery: Bool) -> (verdict: AwakeGuardVerdict, memory: GuardMemory) {
        let config = config.sanitized()
        var m = memory.sanitized()
        let t = time.isFinite ? time : 0

        // Unreadable battery accounting: the read streak, not a count of evaluations (a re-check or a settings change
        // re-evaluates the same read).
        m.unreadableReads = now.batteryPresent && now.percent == nil ? AwakeMath.clamp(now.unreadableStreak, 0...1_000) : 0

        // Heat episode bookkeeping.
        if now.thermal <= .fair {
            m.warnedSerious = false
            if m.holding == .thermal && m.coolSince == nil { m.coolSince = t }
        } else if m.holding == .thermal {
            m.coolSince = nil
        }

        // Clear holds whose condition is over (each by its own rule).
        if let held = m.holding {
            var clear = false
            switch held {
            case .batteryLow:
                if !now.batteryPresent {
                    clear = true
                } else if let p = now.percent, p >= config.effectiveFloor + hysteresisPercent {
                    clear = true
                } else if let rec = now.lastRecovery, rec.isFinite, rec > (m.heldSince ?? 0) {
                    clear = true
                }
            case .lowPowerMode:
                clear = !now.lowPowerMode || !config.endOnLowPowerMode
            case .adapterDisconnected:
                clear = now.onAC || !now.batteryPresent
            case .thermal:
                if let cool = m.coolSince, now.thermal <= .fair, t - cool >= thermalCooldownSeconds { clear = true }
            default:
                clear = true
            }
            if clear {
                m.holding = nil
                m.heldSince = nil
                m.coolSince = nil
            }
        }

        func hold(_ reason: AwakeEndReason) {
            // Thermal is the strongest hold; otherwise the newest reason replaces an older one.
            if m.holding == .thermal && reason != .thermal { return }
            if m.holding != reason {
                m.holding = reason
                m.heldSince = t
                m.coolSince = nil
            }
        }

        let lpmTurnedOn = now.lowPowerMode && !m.lowPowerSeen
        m.lowPowerSeen = now.lowPowerMode

        if now.thermal == .critical {
            hold(.thermal)
            return (.end(.thermal), m)
        }
        let battery = now.batteryPresent && now.discharging
        if battery, let p = now.percent, p < hardFloorPercent {
            hold(.batteryLow)
            return (.end(.batteryLow), m)
        }
        if battery, config.batteryFloorEnabled, let p = now.percent, p < config.batteryFloor {
            hold(.batteryLow)
            if !overrideBattery { return (.end(.batteryLow), m) }
        }
        if config.endOnAdapterDisconnect, now.batteryPresent, !now.onAC, previous?.onAC == true {
            hold(.adapterDisconnected)
            if active { return (.end(.adapterDisconnected), m) }
        }
        if config.endOnLowPowerMode && now.lowPowerMode {
            hold(.lowPowerMode)
            if !overrideBattery { return (.end(.lowPowerMode), m) }
        }
        if active && now.thermal == .serious && !m.warnedSerious {
            m.warnedSerious = true
            return (.warn(.thermal), m)
        }
        if active && lpmTurnedOn && !config.endOnLowPowerMode {
            return (.warn(.lowPowerMode), m)
        }
        return (.allow, m)
    }

    /// Why Drive Alive and activity may not run now, or nil (security M1): critical heat, a latched battery whose
    /// level can't be read twice in a row (treated as 0%, §2.6; a single unreadable read is a blip and blocks
    /// nothing), and discharging below the hard floor or the enabled user floor.
    package static func backgroundBlock(_ now: PowerFacts, config: AwakeGuardsConfig) -> AwakeBackgroundBlock? {
        let config = config.sanitized()
        if now.thermal == .critical { return .heat }
        guard now.batteryPresent else { return nil }
        guard let p = now.percent else {
            return now.unreadableStreak >= unreadableReadsToConfirm ? .batteryUnreadable : nil
        }
        if now.discharging {
            if p < hardFloorPercent { return .batteryLow }
            if config.batteryFloorEnabled && p < config.batteryFloor { return .batteryLow }
        }
        return nil
    }

    /// Drive Alive and activity may run only if this is true: `backgroundBlock` is nil. (`memory` is kept for the
    /// callers; the decision needs only the live facts, which carry the read streak.)
    package static func allowsBackgroundWork(_ now: PowerFacts, config: AwakeGuardsConfig, memory: GuardMemory) -> Bool {
        backgroundBlock(now, config: config) == nil
    }

    /// The battery is latched and has been unreadable for two reads in a row: the same read that stops activity and
    /// Drive Alive, so the one toast (SessionController shows it on the false → true edge: once per streak) explains
    /// the stop (§2.6, review6 awake F2).
    package static func batteryUnreadable(_ now: PowerFacts, memory: GuardMemory) -> Bool {
        backgroundBlock(now, config: AwakeGuardsConfig()) == .batteryUnreadable
    }

    /// When a thermal hold can clear (continuous), for GuardsController's re-check timer; nil when none is pending.
    package static func holdClearsAt(_ memory: GuardMemory) -> Double? {
        guard memory.holding == .thermal, let cool = memory.coolSince else { return nil }
        return cool + thermalCooldownSeconds
    }

    /// R5-13: 1 → 30, 2 → 120, ≥ 3 → 600 seconds (0 before any failure).
    package static func assertionBackoffSeconds(failures: Int) -> Double {
        switch failures {
        case ..<1: return 0
        case 1: return 30
        case 2: return 120
        default: return 600
        }
    }
}
