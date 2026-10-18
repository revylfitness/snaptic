import XCTest
@testable import SnapticKit

/// PowerMath (PLAN 0.3 R5-6, §6.6). The guard side (the hold and its recovery-only clear) is AwakeGuardsTests (G).
final class PowerMathTests: XCTestCase {
    private func r(_ percent: Int, at: Double, charging: Bool = false, current: Int? = nil) -> BatteryReading {
        BatteryReading(percent: percent, charging: charging, currentMilliamps: current, at: at)
    }

    private func history(_ readings: [BatteryReading]) -> [BatteryReading] {
        readings.reduce([]) { PowerMath.appending($1, to: $0) }
    }

    // MARK: The R5-6 window cases

    func testFiveFourFourFourOneMinuteApartStaysFalling() {
        let h = history([r(5, at: 0), r(4, at: 60), r(4, at: 120), r(4, at: 180)])
        XCTAssertTrue(PowerMath.falling(h, now: 180))
        XCTAssertTrue(PowerMath.falling(h, now: 600))
        XCTAssertNil(PowerMath.lastRecovery(h))
    }

    func testAChargingReadingClearsIt() {
        let h = history([r(5, at: 0), r(4, at: 60), r(4, at: 120, charging: true)])
        XCTAssertFalse(PowerMath.falling(h, now: 120))
        XCTAssertEqual(PowerMath.lastRecovery(h), 120)
    }

    func testAPercentRiseClearsIt() {
        let h = history([r(50, at: 0), r(49, at: 60), r(50, at: 120)])
        XCTAssertFalse(PowerMath.falling(h, now: 120))
        XCTAssertEqual(PowerMath.lastRecovery(h), 120)
    }

    func testEqualReadingsForElevenMinutesAgeFallingOut() {
        var h = history([r(5, at: 0), r(4, at: 60)])
        var t = 60.0
        while t < 60 + 11 * 60 {
            t += 60
            h = PowerMath.appending(r(4, at: t), to: h)
        }
        XCTAssertFalse(PowerMath.falling(h, now: t))
        XCTAssertNil(PowerMath.lastRecovery(h), "equal readings are never a recovery")
        // Without new readings, the 60 s re-check ages it out too.
        let short = history([r(5, at: 0), r(4, at: 60)])
        XCTAssertTrue(PowerMath.falling(short, now: 659))
        XCTAssertFalse(PowerMath.falling(short, now: 661))
    }

    func testEqualReadingsNeverClear() {
        let h = history([r(30, at: 0), r(29, at: 10), r(29, at: 20), r(29, at: 30)])
        XCTAssertTrue(PowerMath.falling(h, now: 30))
    }

    func testNegativeCurrentOnACWithEqualPercentsSetsFalling() {
        let h = history([r(80, at: 0, current: 0), r(80, at: 60, current: -350), r(80, at: 120, current: -340)])
        XCTAssertTrue(PowerMath.falling(h, now: 120))
        let positive = history([r(80, at: 0, current: 500), r(80, at: 60, current: 450)])
        XCTAssertFalse(PowerMath.falling(positive, now: 60))
    }

    func testNegativeCurrentClearedByALaterChargingReading() {
        let h = history([r(80, at: 0, current: -300), r(80, at: 60, charging: true, current: 900)])
        XCTAssertFalse(PowerMath.falling(h, now: 60))
    }

    func testRiseBelowTheEventLevelDoesNotClearALaterDrop() {
        // 50 → 48 (event) → 49: higher than 48, clears that event. 49 → 47 (new event) stays.
        let h = history([r(50, at: 0), r(48, at: 60), r(49, at: 120), r(47, at: 180)])
        XCTAssertTrue(PowerMath.falling(h, now: 180))
        XCTAssertEqual(PowerMath.lastRecovery(h), 120)
    }

    func testEmptyAndSingleHistories() {
        XCTAssertFalse(PowerMath.falling([], now: 0))
        XCTAssertFalse(PowerMath.falling([r(50, at: 0)], now: 0))
        XCTAssertTrue(PowerMath.falling([r(50, at: 0, current: -1)], now: 0))
        XCTAssertTrue(PowerMath.falling([r(50, at: 0)], now: .nan), "a broken clock fails safe")
    }

    // MARK: appending

    func testAppendingKeepsOneBaselineOlderThanTheWindow() {
        let h = history([r(9, at: 0), r(8, at: 100), r(7, at: 200), r(7, at: 900)])
        XCTAssertEqual(h.map(\.at), [200, 900])
        XCTAssertTrue(PowerMath.falling(history([r(9, at: 0), r(8, at: 400), r(8, at: 900)]), now: 900),
                      "the 9 → 8 drop at 400 is inside the window relative to its own reading")
    }

    func testAppendingCapsAt64() {
        var h: [BatteryReading] = []
        for i in 0..<200 { h = PowerMath.appending(r(50, at: Double(i)), to: h) }
        XCTAssertEqual(h.count, PowerMath.maxReadings)
        XCTAssertEqual(h.last?.at, 199)
    }

    func testAppendingSortsAndDropsNonFiniteInstants() {
        var h = PowerMath.appending(r(50, at: 100), to: [])
        h = PowerMath.appending(r(51, at: 50), to: h)
        XCTAssertEqual(h.map(\.at), [50, 100])
        h = PowerMath.appending(r(40, at: .nan), to: h)
        XCTAssertEqual(h.map(\.at), [50, 100])
        XCTAssertEqual(PowerMath.appending(r(1, at: .infinity), to: []), [])
    }

    // MARK: percent

    func testPercentFromCapacities() {
        XCTAssertEqual(PowerMath.percent(current: 50, max: 100), 50)
        XCTAssertEqual(PowerMath.percent(current: 4_000, max: 5_000), 80)
        XCTAssertEqual(PowerMath.percent(current: 120, max: 100), 100)
        XCTAssertNil(PowerMath.percent(current: 10, max: 0))
        XCTAssertNil(PowerMath.percent(current: nil, max: 100))
        XCTAssertNil(PowerMath.percent(current: -1, max: 100))
    }

    // MARK: Fuzz

    func testSeededFuzzKeepsInvariants() {
        var rng = SeededGenerator(seed: 0xBA77)
        for _ in 0..<500 {
            var h: [BatteryReading] = []
            var t = 0.0
            var level = 100
            for _ in 0..<Int(rng.next() % 120) {
                t += Double(rng.next() % 300)
                switch rng.next() % 4 {
                case 0: level = max(0, level - 1)
                case 1: level = min(100, level + 1)
                default: break
                }
                let current: Int? = rng.next() % 3 == 0 ? nil : Int(rng.next() % 2_000) - 1_000
                let reading = r(level, at: t, charging: rng.next() % 5 == 0, current: current)
                h = PowerMath.appending(reading, to: h)
                XCTAssertLessThanOrEqual(h.count, PowerMath.maxReadings)
                XCTAssertEqual(h.last, reading)
                XCTAssertEqual(h.map(\.at), h.map(\.at).sorted())
                XCTAssertLessThanOrEqual(h.filter { $0.at < t - PowerMath.fallingWindowSeconds }.count, 1)
                if let rec = PowerMath.lastRecovery(h) { XCTAssertTrue(h.contains { $0.at == rec }) }
                // A charging newest reading always clears falling.
                if reading.charging { XCTAssertFalse(PowerMath.falling(h, now: t)) }
            }
        }
    }
}
