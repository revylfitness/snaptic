import XCTest
@testable import SnapticKit

final class RateLimiterTests: XCTestCase {
    func testGlobalInterval() {
        var r = RateLimiter()
        XCTAssertTrue(r.consume(displays: ["a"], at: 100))
        XCTAssertFalse(r.consume(displays: ["b"], at: 101))
        XCTAssertEqual(r.retryAfter(displays: ["b"], at: 101), 1, accuracy: 1e-9)
        XCTAssertTrue(r.consume(displays: ["b"], at: 102))
    }

    func testPerDisplayWindow() {
        var r = RateLimiter()
        XCTAssertTrue(r.consume(displays: ["a"], at: 0))
        XCTAssertTrue(r.consume(displays: ["a"], at: 10))
        XCTAssertTrue(r.consume(displays: ["a"], at: 20))
        XCTAssertFalse(r.consume(displays: ["a"], at: 30), "three per display per 60 s")
        XCTAssertTrue(r.consume(displays: ["b"], at: 30), "other displays are independent")
        XCTAssertEqual(r.retryAfter(displays: ["a"], at: 32), 28, accuracy: 1e-9)
        XCTAssertTrue(r.consume(displays: ["a"], at: 61))
    }

    func testVisibilityRestoreBypassesAndIsNotCounted() {
        var r = RateLimiter()
        for t in 0..<10 { XCTAssertTrue(r.consume(displays: ["a"], at: Double(t), kind: .visibilityRestore)) }
        XCTAssertTrue(r.consume(displays: ["a"], at: 10))
        XCTAssertTrue(r.allows(displays: ["a"], at: 10.5, kind: .visibilityRestore))
        XCTAssertFalse(r.allows(displays: ["a"], at: 10.5))
    }

    func testDuplicatesInOnePlanCountOnce() {
        var r = RateLimiter(globalInterval: 0, perDisplayLimit: 3, perDisplayWindow: 60)
        XCTAssertTrue(r.consume(displays: ["a", "a", "a"], at: 0))
        XCTAssertTrue(r.consume(displays: ["a"], at: 1))
        XCTAssertTrue(r.consume(displays: ["a"], at: 2))
        XCTAssertFalse(r.consume(displays: ["a"], at: 3))
    }

    func testFuzzNeverExceedsLimits() throws {
        var rng = SeededGenerator(seed: 0x4A7E)
        var r = RateLimiter()
        var t = 0.0
        var accepted: [(Double, String)] = []
        for _ in 0..<5000 {
            t += Double(rng.next() % 3000) / 1000
            let d = ["a", "b", "c"][Int(rng.next() % 3)]
            if r.consume(displays: [d], at: t) { accepted.append((t, d)) }
        }
        for (i, (time, d)) in accepted.enumerated() {
            if i > 0 { XCTAssertGreaterThanOrEqual(time - accepted[i - 1].0, 2 - 1e-9) }
            let window = accepted.filter { $0.1 == d && $0.0 <= time && time - $0.0 < 60 }
            XCTAssertLessThanOrEqual(window.count, 3)
        }
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(RateLimiter.self, from: data), r)
    }
}
