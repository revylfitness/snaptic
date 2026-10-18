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

    // MARK: Latest-value throttle (OSD broadcast, FIXES-R3 9)

    func testThrottleSendsFirstValueAtOnceAndCoalesces() {
        var t = LatestValueThrottle(interval: 0.25)
        XCTAssertEqual(t.offer(at: 10), .sendNow)
        XCTAssertEqual(t.offer(at: 10.0625), .schedule(seconds: 0.1875))
        XCTAssertEqual(t.offer(at: 10.125), .coalesced)
        XCTAssertEqual(t.timerFired(at: 10.25), .sendNow)
        XCTAssertFalse(t.hasPending)
        XCTAssertNil(t.timerFired(at: 10.5), "no timer outstanding")
    }

    /// The R3 bug: an immediate send must clear the waiting value, so the old timer can't send
    /// a stale value right after a newer one.
    func testImmediateSendClearsThePendingValue() {
        var t = LatestValueThrottle(interval: 0.25)
        XCTAssertEqual(t.offer(at: 0), .sendNow)
        XCTAssertEqual(t.offer(at: 0.125), .schedule(seconds: 0.125))
        // The timer is late; a new value arrives once the window is open.
        XCTAssertEqual(t.offer(at: 0.375), .sendNow)
        XCTAssertFalse(t.hasPending)
        XCTAssertFalse(t.isScheduled)
        XCTAssertNil(t.timerFired(at: 0.5), "the stale timer sends nothing")
    }

    func testEarlyTimerIsRearmed() {
        var t = LatestValueThrottle(interval: 0.25)
        _ = t.offer(at: 1)
        _ = t.offer(at: 1.0625)
        XCTAssertEqual(t.timerFired(at: 1.125), .schedule(seconds: 0.125))
        XCTAssertEqual(t.timerFired(at: 1.25), .sendNow)
    }

    func testResetDropsTheWaitingValue() {
        var t = LatestValueThrottle(interval: 0.1)
        _ = t.offer(at: 1)
        _ = t.offer(at: 1.01)
        t.reset()
        XCTAssertNil(t.timerFired(at: 1.2))
    }

    /// Fuzz: random offers, timers firing when due (sometimes late, sometimes early): sends
    /// are never closer than the interval, never out of order, and the last value is sent.
    func testThrottleFuzz() {
        var rng = SeededGenerator(seed: 0x05D)
        for _ in 0..<300 {
            var t = LatestValueThrottle(interval: 0.1)
            var now = 0.0
            var timer: Double?
            var latest = -1
            var pending = -1
            var sent: [(at: Double, value: Int)] = []
            func apply(_ d: LatestValueThrottle.Decision?, value: Int?) {
                switch d {
                case .sendNow?:
                    timer = nil
                    sent.append((now, value ?? pending))
                    pending = -1
                case .schedule(let s)?:
                    XCTAssertGreaterThan(s, 0)
                    // Timers fire up to 20 ms late or 1 ms early.
                    let jitter = Double(rng.next() % 21) / 1000 - 0.001
                    timer = now + s + jitter
                    if let value { pending = value }
                case .coalesced?:
                    if let value { pending = value }
                case nil:
                    break
                }
            }
            for i in 0..<60 {
                now += Double(rng.next() % 80) / 1000
                while let due = timer, due <= now {
                    let saved = now
                    now = due
                    timer = nil
                    apply(t.timerFired(at: now), value: nil)
                    now = saved
                }
                latest = i
                apply(t.offer(at: now), value: i)
            }
            while let due = timer {
                now = max(now, due)
                timer = nil
                apply(t.timerFired(at: now), value: nil)
            }
            XCTAssertEqual(sent.last?.value, latest, "the last value always goes out")
            for (a, b) in zip(sent, sent.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.at - a.at, 0.1 - 1e-9, "≤ 10 per second")
                XCTAssertGreaterThan(b.value, a.value, "never an older value after a newer one")
            }
        }
    }
}
