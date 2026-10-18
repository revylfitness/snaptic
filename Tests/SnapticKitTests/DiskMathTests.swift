import XCTest
@testable import SnapticKit

/// DiskMath (PLAN 0.3 §2.8, §6.6).
final class DiskMathTests: XCTestCase {
    func testPerDriverDeltas() throws {
        let prev: [UInt64: UInt64] = [1: 1_000, 2: 0]
        let now: [UInt64: UInt64] = [1: 1_000 + 5_120, 2: 5_120]
        XCTAssertEqual(try XCTUnwrap(DiskMath.throughputKBps(prev: prev, now: now, seconds: 5)), 2, accuracy: 1e-9)
    }

    func testADriverAppearingOrVanishingContributesNothing() throws {
        let prev: [UInt64: UInt64] = [1: 0, 2: 9_999_999]
        let now: [UInt64: UInt64] = [1: 1_024, 3: 88_888_888_888]
        XCTAssertEqual(try XCTUnwrap(DiskMath.throughputKBps(prev: prev, now: now, seconds: 1)), 1, accuracy: 1e-9)
    }

    func testACounterGoingDownCountsZero() throws {
        let prev: [UInt64: UInt64] = [1: 50_000, 2: 0]
        let now: [UInt64: UInt64] = [1: 10, 2: 2_048]
        XCTAssertEqual(try XCTUnwrap(DiskMath.throughputKBps(prev: prev, now: now, seconds: 2)), 1, accuracy: 1e-9)
    }

    func testUnknowns() {
        XCTAssertNil(DiskMath.throughputKBps(prev: [1: 0], now: [1: 5], seconds: 0))
        XCTAssertNil(DiskMath.throughputKBps(prev: [1: 0], now: [1: 5], seconds: .nan))
        XCTAssertNil(DiskMath.throughputKBps(prev: [1: 0], now: [2: 5], seconds: 5))
        XCTAssertNil(DiskMath.throughputKBps(prev: [:], now: [:], seconds: 5))
        XCTAssertEqual(DiskMath.throughputKBps(prev: [1: 7], now: [1: 7], seconds: 5), 0)
    }

    func testSaturatesInsteadOfTrapping() throws {
        let v = try XCTUnwrap(DiskMath.throughputKBps(prev: [1: 0, 2: 0], now: [1: UInt64.max, 2: UInt64.max], seconds: 1))
        XCTAssertEqual(v, Double(UInt64.max) / 1024, accuracy: 1e6)
    }

    func testDriverBytes() {
        XCTAssertNil(DiskMath.driverBytes(read: nil, written: nil))
        XCTAssertEqual(DiskMath.driverBytes(read: 5, written: nil), 5)
        XCTAssertEqual(DiskMath.driverBytes(read: nil, written: 7), 7)
        XCTAssertEqual(DiskMath.driverBytes(read: 5, written: 7), 12)
        XCTAssertEqual(DiskMath.driverBytes(read: UInt64.max, written: 1), UInt64.max)
    }

    func testSeededFuzzIsNonNegative() {
        var rng = SeededGenerator(seed: 0xD15C)
        for _ in 0..<5_000 {
            var prev: [UInt64: UInt64] = [:], now: [UInt64: UInt64] = [:]
            for _ in 0..<Int(rng.next() % 6) { prev[rng.next() % 8] = rng.next() >> (rng.next() % 64) }
            for _ in 0..<Int(rng.next() % 6) { now[rng.next() % 8] = rng.next() >> (rng.next() % 64) }
            if let v = DiskMath.throughputKBps(prev: prev, now: now, seconds: Double(rng.next() % 6)) {
                XCTAssertGreaterThanOrEqual(v, 0)
                XCTAssertFalse(Set(prev.keys).isDisjoint(with: now.keys))
            }
        }
    }
}
