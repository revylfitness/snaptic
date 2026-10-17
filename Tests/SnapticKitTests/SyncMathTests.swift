import XCTest
@testable import SnapticKit

final class SyncMathTests: XCTestCase {
    func testAbsoluteWithOffsetClamps() {
        XCTAssertEqual(SyncMath.target(source: 0.5, previousSource: nil, targetCurrent: 0.2, offset: 0.1, mode: .absolute), 0.6,
                       accuracy: 1e-12)
        XCTAssertEqual(SyncMath.target(source: 0.95, previousSource: nil, targetCurrent: 0, offset: 0.2, mode: .absolute), 1)
        XCTAssertEqual(SyncMath.target(source: 0.05, previousSource: nil, targetCurrent: 0, offset: -0.2, mode: .absolute), 0)
    }

    func testDeltaFollowsTheChange() {
        XCTAssertEqual(SyncMath.target(source: 0.6, previousSource: 0.5, targetCurrent: 0.3, offset: 0, mode: .delta), 0.4,
                       accuracy: 1e-12)
        XCTAssertEqual(SyncMath.target(source: 0.6, previousSource: nil, targetCurrent: 0.3, offset: 0, mode: .delta), 0.3,
                       accuracy: 1e-12)
        XCTAssertEqual(SyncMath.target(source: .nan, previousSource: 0.5, targetCurrent: 0.3, offset: 0, mode: .delta), 0.3)
    }

    func testDeadband() {
        let state = SyncTargetState(lastWritten: 0.5, lastWriteAt: 0)
        XCTAssertFalse(SyncMath.shouldWrite(0.51, state: state, now: 100, isDDC: false))
        XCTAssertTrue(SyncMath.shouldWrite(0.53, state: state, now: 100, isDDC: false))
        XCTAssertNil(SyncMath.nextWriteTime(0.51, state: state, now: 100, isDDC: true))
    }

    func testDDCWritesAtLeastThreeSecondsApart() {
        var state = SyncTargetState()
        XCTAssertTrue(SyncMath.shouldWrite(0.4, state: state, now: 10, isDDC: true))
        SyncMath.didWrite(0.4, state: &state, now: 10)
        XCTAssertFalse(SyncMath.shouldWrite(0.6, state: state, now: 11, isDDC: true))
        XCTAssertTrue(SyncMath.shouldWrite(0.6, state: state, now: 11, isDDC: false), "gamma/overlay targets aren't limited")
        XCTAssertEqual(SyncMath.nextWriteTime(0.6, state: state, now: 11, isDDC: true), 13)
        XCTAssertTrue(SyncMath.shouldWrite(0.6, state: state, now: 13, isDDC: true))
    }

    func testManualChangePausesTenSeconds() {
        let state = SyncTargetState(lastManualAt: 50)
        XCTAssertTrue(SyncMath.isPaused(state, now: 55))
        XCTAssertFalse(SyncMath.shouldWrite(0.9, state: state, now: 59.9, isDDC: false))
        XCTAssertEqual(SyncMath.nextWriteTime(0.9, state: state, now: 55, isDDC: false), 60)
        XCTAssertTrue(SyncMath.shouldWrite(0.9, state: state, now: 60, isDDC: false))
        XCTAssertFalse(SyncMath.isPaused(state, now: 49), "a clock going backwards doesn't pause forever")
    }

    func testFuzzedTargetsStayInRange() {
        var rng = SeededGenerator(seed: 0x5157)
        for _ in 0..<2_000 {
            func r() -> Double { Double(rng.next() % 2_001) / 1_000 - 0.5 }
            let mode: SyncMode = rng.next() % 2 == 0 ? .absolute : .delta
            let v = SyncMath.target(source: r(), previousSource: r(), targetCurrent: r(), offset: r(), mode: mode)
            XCTAssertTrue((0...1).contains(v))
        }
    }
}
