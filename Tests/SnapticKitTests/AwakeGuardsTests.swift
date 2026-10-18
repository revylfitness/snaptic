import XCTest
@testable import SnapticKit

final class AwakeGuardsTests: XCTestCase {
    private func facts(battery: Bool = true, ac: Bool = false, percent: Int? = 50, charging: Bool = false,
                       falling: Bool = false, recovery: Double? = nil, lpm: Bool = false,
                       thermal: ThermalLevel = .nominal, streak: Int = 0) -> PowerFacts {
        PowerFacts(batteryPresent: battery, onAC: ac, percent: percent, charging: charging, falling: falling,
                   lastRecovery: recovery, lowPowerMode: lpm, thermal: thermal, unreadableStreak: streak)
    }

    private func eval(_ f: PowerFacts, previous: PowerFacts? = nil, config: AwakeGuardsConfig = AwakeGuardsConfig(),
                      memory: GuardMemory = GuardMemory(), time: Double = 1_000, active: Bool = true,
                      override: Bool = false) -> (verdict: AwakeGuardVerdict, memory: GuardMemory) {
        AwakeGuards.evaluate(f, previous: previous, config: config, memory: memory, time: time, active: active,
                             overrideBattery: override)
    }

    private var floorOff: AwakeGuardsConfig {
        var c = AwakeGuardsConfig()
        c.batteryFloorEnabled = false
        return c
    }

    // MARK: Discharging (R5-6)

    func testDischarging() {
        XCTAssertFalse(facts(battery: false, ac: false).discharging, "desktop")
        XCTAssertTrue(facts(ac: false).discharging)
        XCTAssertFalse(facts(ac: true).discharging, "AC and not falling")
        XCTAssertTrue(facts(ac: true, falling: true).discharging, "AC but falling: a weak charger")
    }

    // MARK: Floors

    func testDesktopSkipsBatteryRules() {
        XCTAssertEqual(eval(facts(battery: false, percent: nil)).verdict, .allow)
        XCTAssertEqual(eval(facts(battery: false, percent: 1)).verdict, .allow)
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(battery: false, percent: nil), config: AwakeGuardsConfig(),
                                                       memory: GuardMemory()))
    }

    func testUserFloorEndsWhileDischargingAndStartAnywayOverrides() {
        let low = facts(percent: 19)
        let r = eval(low)
        XCTAssertEqual(r.verdict, .end(.batteryLow))
        XCTAssertEqual(r.memory.holding, .batteryLow)
        XCTAssertEqual(r.memory.heldSince, 1_000)
        let overridden = eval(low, override: true)
        XCTAssertEqual(overridden.verdict, .allow)
        XCTAssertEqual(overridden.memory.holding, .batteryLow, "rules stay held even when the user overrides")
        XCTAssertEqual(eval(facts(percent: 20)).verdict, .allow, "at the floor is fine")
        XCTAssertEqual(eval(facts(ac: true, percent: 10)).verdict, .allow, "on AC and not falling")
        XCTAssertEqual(eval(facts(percent: 10), config: floorOff).verdict, .allow, "floor off")
    }

    func testHardFloorAlwaysEndsWhileDischarging() {
        for config in [AwakeGuardsConfig(), floorOff] {
            for override in [false, true] {
                XCTAssertEqual(eval(facts(percent: 4), config: config, override: override).verdict, .end(.batteryLow))
                XCTAssertEqual(eval(facts(ac: true, percent: 4, falling: true), config: config, override: override).verdict,
                               .end(.batteryLow), "a weak adapter doesn't help")
            }
        }
        XCTAssertEqual(eval(facts(ac: true, percent: 4)).verdict, .allow, "charging normally")
        XCTAssertEqual(eval(facts(percent: 5), config: floorOff).verdict, .allow)
    }

    func testWeakChargerFiveFourFourFourKeepsTheHold() {
        // R5-6: on AC, readings 5, 4, 4, 4 one minute apart: PowerMath reports falling for the whole window.
        var m = GuardMemory()
        var verdicts: [AwakeGuardVerdict] = []
        for (i, p) in [5, 4, 4, 4].enumerated() {
            let r = eval(facts(ac: true, percent: p, falling: true), config: floorOff, memory: m, time: Double(i) * 60)
            verdicts.append(r.verdict)
            m = r.memory
        }
        XCTAssertEqual(verdicts, [.allow, .end(.batteryLow), .end(.batteryLow), .end(.batteryLow)])
        XCTAssertEqual(m.holding, .batteryLow)
        // Equal readings for 11 minutes age `falling` out: no more ends, but the hold stays until a recovery.
        let aged = eval(facts(ac: true, percent: 4, falling: false), config: floorOff, memory: m, time: 900)
        XCTAssertEqual(aged.verdict, .allow)
        XCTAssertEqual(aged.memory.holding, .batteryLow)
        XCTAssertTrue(aged.memory.blocksTriggers(at: 900))
        // A charging reading after the hold began clears it.
        let charging = eval(facts(ac: true, percent: 4, charging: true, recovery: 960), config: floorOff,
                            memory: aged.memory, time: 960)
        XCTAssertEqual(charging.verdict, .allow)
        XCTAssertNil(charging.memory.holding)
        XCTAssertNil(charging.memory.heldSince)
    }

    func testHoldClearsAtFloorPlusFiveOrARecoveryOnly() {
        var m = eval(facts(percent: 18), time: 100).memory
        XCTAssertEqual(m.holding, .batteryLow)
        // Back above the floor but below floor + 5, no recovery reported: still held.
        m = eval(facts(ac: true, percent: 24), memory: m, time: 200).memory
        XCTAssertEqual(m.holding, .batteryLow)
        // A recovery that happened before the hold doesn't count.
        m = eval(facts(ac: true, percent: 24, recovery: 50), memory: m, time: 300).memory
        XCTAssertEqual(m.holding, .batteryLow)
        // floor + 5 clears.
        XCTAssertNil(eval(facts(ac: true, percent: 25), memory: m, time: 400).memory.holding)
        // A rise after the hold clears.
        XCTAssertNil(eval(facts(ac: true, percent: 21, recovery: 350), memory: m, time: 400).memory.holding)
        // With the floor off, the hard floor's +5 applies.
        let hard = eval(facts(percent: 3), config: floorOff, time: 10).memory
        XCTAssertEqual(eval(facts(ac: true, percent: 9), config: floorOff, memory: hard, time: 20).memory.holding, .batteryLow)
        XCTAssertNil(eval(facts(ac: true, percent: 10), config: floorOff, memory: hard, time: 20).memory.holding)
    }

    func testRecoveryWhileStillDischargingBelowTheFloorReHolds() {
        let m = eval(facts(percent: 15), time: 100).memory
        // Charging was reported at 150, then unplugged: still below the floor, so a new hold starts now.
        let r = eval(facts(percent: 15, recovery: 150), memory: m, time: 200)
        XCTAssertEqual(r.verdict, .end(.batteryLow))
        XCTAssertEqual(r.memory.heldSince, 200)
    }

    // MARK: Unreadable battery (r3 security M3)

    func testMissingBatteryEntryAfterLatchIsUnreadableNotADesktop() {
        let c = AwakeGuardsConfig()
        // §2.6 (review6 F2): one unreadable read is a blip: nothing stops and no toast is due.
        let once = facts(battery: true, percent: nil, streak: 1)
        let first = eval(once)
        XCTAssertEqual(first.verdict, .allow, "sessions continue")
        XCTAssertEqual(first.memory.unreadableReads, 1)
        XCTAssertFalse(AwakeGuards.batteryUnreadable(once, memory: first.memory))
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(once, config: c, memory: first.memory))
        XCTAssertNil(AwakeGuards.backgroundBlock(once, config: c))
        // Re-evaluating the same read (a re-check timer, a settings change) never confirms it.
        let again = eval(once, memory: first.memory).memory
        XCTAssertEqual(again.unreadableReads, 1)
        XCTAssertFalse(AwakeGuards.batteryUnreadable(once, memory: again))
        // The second consecutive read confirms it: background work stops (as at 0%) and the toast is due.
        let twice = facts(battery: true, percent: nil, streak: 2)
        let m = eval(twice, memory: again).memory
        XCTAssertEqual(m.unreadableReads, 2)
        XCTAssertTrue(AwakeGuards.batteryUnreadable(twice, memory: m))
        XCTAssertFalse(AwakeGuards.allowsBackgroundWork(twice, config: c, memory: m))
        XCTAssertEqual(AwakeGuards.backgroundBlock(twice, config: c), .batteryUnreadable)
        XCTAssertEqual(eval(twice, memory: m).verdict, .allow, "no session end for an unreadable battery")
        let longer = facts(battery: true, percent: nil, streak: 7)
        XCTAssertTrue(AwakeGuards.batteryUnreadable(longer, memory: eval(longer, memory: m).memory), "stays while it lasts")
        // One readable reading clears it.
        let readable = eval(facts(percent: 80), memory: m).memory
        XCTAssertEqual(readable.unreadableReads, 0)
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(percent: 80), config: c, memory: readable))
        // Stale memory never blocks a readable battery.
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(percent: 80), config: c, memory: m))
        XCTAssertFalse(AwakeGuards.batteryUnreadable(facts(percent: 80), memory: m))
        XCTAssertFalse(AwakeGuards.batteryUnreadable(facts(battery: false, percent: nil, streak: 0), memory: m), "desktop")
    }

    /// The toast fires on the false → true edge of `batteryUnreadable` over a sequence of reads (SessionController's
    /// `wasUnreadable`): once per streak, never for a lone blip, again after a readable read ends a streak.
    func testUnreadableToastOncePerStreak() {
        let reads: [Int?] = [80, nil, 80, nil, nil, nil, nil, 70, nil, 60, nil, nil]
        var streak = 0
        var memory = GuardMemory()
        var was = false
        var toasts: [Int] = []
        for (i, percent) in reads.enumerated() {
            streak = PowerMath.unreadableStreak(previous: streak, batteryLatched: true, percent: percent)
            let f = facts(percent: percent, streak: streak)
            memory = eval(f, memory: memory).memory
            // Evaluated twice per read on purpose (a re-check): it must not move the edge.
            memory = eval(f, memory: memory).memory
            let now = AwakeGuards.batteryUnreadable(f, memory: memory)
            if now && !was { toasts.append(i) }
            was = now
        }
        XCTAssertEqual(toasts, [4, 11])
    }

    func testBackgroundBlockReasons() {
        let c = AwakeGuardsConfig()
        XCTAssertNil(AwakeGuards.backgroundBlock(facts(percent: 80), config: c))
        XCTAssertEqual(AwakeGuards.backgroundBlock(facts(percent: 10), config: c), .batteryLow)
        XCTAssertEqual(AwakeGuards.backgroundBlock(facts(battery: false, thermal: .critical), config: c), .heat)
        XCTAssertEqual(AwakeGuards.backgroundBlock(facts(percent: nil, thermal: .critical), config: c), .heat)
        XCTAssertNil(AwakeGuards.backgroundBlock(facts(battery: false, percent: nil), config: c))
    }

    // MARK: Adapter, Low Power Mode, heat

    func testAdapterDisconnect() {
        var c = AwakeGuardsConfig()
        c.endOnAdapterDisconnect = true
        let plugged = facts(ac: true, percent: 80)
        let r = eval(facts(ac: false, percent: 80), previous: plugged, config: c)
        XCTAssertEqual(r.verdict, .end(.adapterDisconnected))
        XCTAssertEqual(r.memory.holding, .adapterDisconnected)
        XCTAssertEqual(eval(facts(ac: false, percent: 80), previous: plugged).verdict, .allow, "option off")
        XCTAssertEqual(eval(facts(ac: false, percent: 80), previous: facts(ac: false), config: c).verdict, .allow,
                       "no transition")
        XCTAssertEqual(eval(facts(ac: false, percent: 80), previous: plugged, config: c, active: false).verdict, .allow)
        // Plugging back in clears the hold.
        XCTAssertNil(eval(plugged, config: c, memory: r.memory).memory.holding)
    }

    func testLowPowerMode() {
        var c = AwakeGuardsConfig()
        c.endOnLowPowerMode = true
        let r = eval(facts(lpm: true), config: c)
        XCTAssertEqual(r.verdict, .end(.lowPowerMode))
        XCTAssertEqual(r.memory.holding, .lowPowerMode)
        XCTAssertEqual(eval(facts(lpm: true), config: c, override: true).verdict, .allow, "Start Anyway")
        XCTAssertNil(eval(facts(lpm: false), config: c, memory: r.memory).memory.holding)
        // Without the option: one notice when it turns on, then nothing.
        let notice = eval(facts(lpm: true))
        XCTAssertEqual(notice.verdict, .warn(.lowPowerMode))
        XCTAssertEqual(eval(facts(lpm: true), memory: notice.memory).verdict, .allow)
        XCTAssertEqual(eval(facts(lpm: true), active: false).verdict, .allow)
    }

    func testSeriousWarnsOncePerEpisodeWithoutEnding() {
        let first = eval(facts(thermal: .serious))
        XCTAssertEqual(first.verdict, .warn(.thermal))
        XCTAssertTrue(first.memory.warnedSerious)
        XCTAssertEqual(eval(facts(thermal: .serious), memory: first.memory).verdict, .allow)
        let cooled = eval(facts(thermal: .fair), memory: first.memory).memory
        XCTAssertFalse(cooled.warnedSerious)
        XCTAssertEqual(eval(facts(thermal: .serious), memory: cooled).verdict, .warn(.thermal), "a new episode")
    }

    func testCriticalEndsWithEveryConfigAndHoldsForTenMinutes() {
        var strict = AwakeGuardsConfig()
        strict.endOnLowPowerMode = true
        for config in [AwakeGuardsConfig(), floorOff, strict] {
            for override in [false, true] {
                for active in [false, true] {
                    XCTAssertEqual(eval(facts(battery: false, thermal: .critical), config: config, active: active,
                                        override: override).verdict, .end(.thermal))
                }
            }
        }
        var m = eval(facts(thermal: .critical), time: 0).memory
        XCTAssertEqual(m.holding, .thermal)
        m = eval(facts(thermal: .fair), memory: m, time: 100).memory
        XCTAssertEqual(m.coolSince, 100)
        XCTAssertEqual(AwakeGuards.holdClearsAt(m), 700)
        m = eval(facts(thermal: .fair), memory: m, time: 699).memory
        XCTAssertEqual(m.holding, .thermal)
        // Heating up again restarts the cooldown.
        m = eval(facts(thermal: .serious), memory: m, time: 650).memory
        XCTAssertNil(m.coolSince)
        m = eval(facts(thermal: .nominal), memory: m, time: 660).memory
        XCTAssertEqual(eval(facts(thermal: .nominal), memory: m, time: 1_259).memory.holding, .thermal)
        let cleared = eval(facts(thermal: .nominal), memory: m, time: 1_260).memory
        XCTAssertNil(cleared.holding)
        XCTAssertNil(AwakeGuards.holdClearsAt(cleared))
    }

    func testThermalHoldIsNotReplacedByABatteryHold() {
        let hot = eval(facts(thermal: .critical), time: 0).memory
        let r = eval(facts(percent: 10, thermal: .fair), memory: hot, time: 10)
        XCTAssertEqual(r.verdict, .end(.batteryLow))
        XCTAssertEqual(r.memory.holding, .thermal)
    }

    // MARK: Background work

    func testAllowsBackgroundWork() {
        let c = AwakeGuardsConfig()
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(percent: 50), config: c, memory: GuardMemory()))
        XCTAssertFalse(AwakeGuards.allowsBackgroundWork(facts(percent: 19), config: c, memory: GuardMemory()))
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(percent: 19), config: floorOff, memory: GuardMemory()))
        XCTAssertFalse(AwakeGuards.allowsBackgroundWork(facts(percent: 4), config: floorOff, memory: GuardMemory()))
        XCTAssertFalse(AwakeGuards.allowsBackgroundWork(facts(ac: true, percent: 4, falling: true), config: floorOff,
                                                        memory: GuardMemory()))
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(ac: true, percent: 4), config: floorOff, memory: GuardMemory()))
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(percent: nil, streak: 1), config: c, memory: GuardMemory()),
                      "one unreadable read is a blip")
        XCTAssertFalse(AwakeGuards.allowsBackgroundWork(facts(percent: nil, streak: 2), config: c, memory: GuardMemory()))
        XCTAssertFalse(AwakeGuards.allowsBackgroundWork(facts(battery: false, thermal: .critical), config: c,
                                                        memory: GuardMemory()))
        XCTAssertTrue(AwakeGuards.allowsBackgroundWork(facts(thermal: .serious), config: c, memory: GuardMemory()))
    }

    // MARK: Config

    func testConfigSanitizeAndMonotonic() {
        var c = AwakeGuardsConfig()
        c.batteryFloor = 2
        XCTAssertEqual(c.sanitized().batteryFloor, 5)
        c.batteryFloor = 99
        XCTAssertEqual(c.sanitized().batteryFloor, 50)
        c.batteryFloor = 22
        XCTAssertEqual(c.sanitized().batteryFloor, 20)
        c.batteryFloor = 23
        XCTAssertEqual(c.sanitized().batteryFloor, 25)
        XCTAssertEqual(AwakeGuardsConfig().sanitized(), AwakeGuardsConfig())

        var current = AwakeGuardsConfig()
        current.batteryFloor = 30
        var hostile = floorOff
        hostile.batteryFloor = 5
        let merged = hostile.monotonic(over: current)
        XCTAssertTrue(merged.batteryFloorEnabled)
        XCTAssertEqual(merged.batteryFloor, 30)
        var stricter = AwakeGuardsConfig()
        stricter.batteryFloor = 40
        stricter.endOnAdapterDisconnect = true
        stricter.endOnLowPowerMode = true
        let tightened = stricter.monotonic(over: current)
        XCTAssertEqual(tightened.batteryFloor, 40)
        XCTAssertTrue(tightened.endOnAdapterDisconnect)
        XCTAssertTrue(tightened.endOnLowPowerMode)
        XCTAssertEqual(floorOff.effectiveFloor, AwakeGuards.hardFloorPercent)
        XCTAssertEqual(AwakeGuardsConfig().effectiveFloor, 20)
    }

    // MARK: Memory

    func testMemoryDecodeAndReload() throws {
        let m = try JSONDecoder().decode(GuardMemory.self, from: Data(
            #"{"holding":"batteryLow","heldSince":12,"warnedSerious":true,"unreadableReads":3,"assertionFailures":"x"}"#.utf8))
        XCTAssertEqual(m.holding, .batteryLow)
        XCTAssertEqual(m.assertionFailures, 0)
        let same = m.reloaded(sameBoot: true)
        XCTAssertEqual(same.holding, .batteryLow)
        XCTAssertEqual(same.heldSince, 12)
        XCTAssertEqual(same.unreadableReads, 0, "recounted from live reads")
        let other = m.reloaded(sameBoot: false)
        var expected = GuardMemory()
        expected.warnedSerious = true
        XCTAssertEqual(other, expected)
        // A hold that isn't a guard reason is dropped; a hold without a start gets one.
        var odd = GuardMemory()
        odd.holding = .user
        XCTAssertNil(odd.sanitized().holding)
        odd.holding = .lowPowerMode
        odd.heldSince = nil
        XCTAssertEqual(odd.sanitized().heldSince, 0)
        XCTAssertEqual(try JSONDecoder().decode(GuardMemory.self, from: JSONEncoder().encode(same)), same)
    }

    func testAssertionBackoff() {
        XCTAssertEqual(AwakeGuards.assertionBackoffSeconds(failures: 0), 0)
        XCTAssertEqual(AwakeGuards.assertionBackoffSeconds(failures: 1), 30)
        XCTAssertEqual(AwakeGuards.assertionBackoffSeconds(failures: 2), 120)
        XCTAssertEqual(AwakeGuards.assertionBackoffSeconds(failures: 3), 600)
        XCTAssertEqual(AwakeGuards.assertionBackoffSeconds(failures: 99), 600)
        var m = GuardMemory().recordingAssertionFailure(now: 100)
        XCTAssertEqual(m.assertionFailures, 1)
        XCTAssertEqual(m.assertionHoldUntil, 130)
        XCTAssertTrue(m.blocksTriggers(at: 129))
        XCTAssertFalse(m.blocksTriggers(at: 130))
        m = m.recordingAssertionFailure(now: 200).recordingAssertionFailure(now: 400)
        XCTAssertEqual(m.assertionHoldUntil, 1_000)
        m = m.clearingAssertionHold()
        XCTAssertEqual(m.assertionFailures, 0)
        XCTAssertNil(m.assertionHoldUntil)
        XCTAssertFalse(m.blocksTriggers(at: 0))
    }

    // MARK: Fuzz

    func testGuardFuzzInvariants() {
        var rng = SeededGenerator(seed: 0x6A2D)
        func bool() -> Bool { rng.next() % 2 == 0 }
        var memory = GuardMemory()
        var previous: PowerFacts?
        var streak = 0
        var t = 0.0
        for _ in 0..<50_000 {
            var config = AwakeGuardsConfig()
            config.batteryFloorEnabled = bool()
            config.batteryFloor = Int(rng.next() % 70) - 5
            config.endOnAdapterDisconnect = bool()
            config.endOnLowPowerMode = bool()
            let percent: Int? = rng.next() % 10 == 0 ? nil : Int(rng.next() % 101)
            let present = rng.next() % 5 != 0
            // PowerMonitor's read streak (§2.6: two consecutive unreadable reads make the battery unreadable).
            streak = PowerMath.unreadableStreak(previous: streak, batteryLatched: present, percent: percent)
            let f = PowerFacts(batteryPresent: present, onAC: bool(), percent: percent, charging: bool(),
                               falling: bool(), lastRecovery: bool() ? t - Double(rng.next() % 600) : nil,
                               lowPowerMode: rng.next() % 4 == 0,
                               thermal: ThermalLevel(rawValue: Int(rng.next() % 4)) ?? .nominal, unreadableStreak: streak)
            let override = bool(), active = bool()
            t += Double(rng.next() % 120)
            let r = AwakeGuards.evaluate(f, previous: previous, config: config, memory: memory, time: t, active: active,
                                         overrideBattery: override)
            let floor = config.sanitized()
            // Critical heat always ends.
            if f.thermal == .critical { XCTAssertEqual(r.verdict, .end(.thermal)) }
            // The hard floor always ends while discharging, whatever the config and override.
            if f.thermal != .critical, f.discharging, let p = f.percent, p < AwakeGuards.hardFloorPercent {
                XCTAssertEqual(r.verdict, .end(.batteryLow))
            }
            // Desktops never end for battery reasons.
            if !f.batteryPresent {
                XCTAssertNotEqual(r.verdict, .end(.batteryLow))
                XCTAssertNotEqual(r.verdict, .end(.adapterDisconnected))
            }
            // Without the user floor, the hard floor and heat are the only battery/thermal ends.
            if case .end(.batteryLow) = r.verdict, let p = f.percent {
                XCTAssertTrue(f.discharging)
                XCTAssertTrue(p < AwakeGuards.hardFloorPercent || (floor.batteryFloorEnabled && p < floor.batteryFloor && !override))
            }
            // Override never skips the hard floor or heat, and only matters for battery and LPM.
            if case .end(.lowPowerMode) = r.verdict { XCTAssertFalse(override) }
            // Background work is never allowed where a session would end for the hard floor or heat.
            let background = AwakeGuards.allowsBackgroundWork(f, config: config, memory: r.memory)
            if f.thermal == .critical { XCTAssertFalse(background) }
            if f.discharging, let p = f.percent, p < AwakeGuards.hardFloorPercent { XCTAssertFalse(background) }
            let confirmed = f.batteryPresent && f.percent == nil && streak >= AwakeGuards.unreadableReadsToConfirm
            if confirmed { XCTAssertFalse(background) }
            XCTAssertEqual(background, AwakeGuards.backgroundBlock(f, config: config) == nil)
            XCTAssertEqual(AwakeGuards.batteryUnreadable(f, memory: r.memory), confirmed && f.thermal != .critical)
            XCTAssertEqual(r.memory.unreadableReads, f.batteryPresent && f.percent == nil ? streak : 0)
            // Memory stays sane.
            XCTAssertEqual(r.memory.holding == nil, r.memory.heldSince == nil)
            if let h = r.memory.holding {
                XCTAssertTrue([.batteryLow, .thermal, .lowPowerMode, .adapterDisconnected].contains(h))
            }
            if f.thermal == .critical { XCTAssertEqual(r.memory.holding, .thermal) }
            memory = r.memory
            previous = f
        }
    }
}
