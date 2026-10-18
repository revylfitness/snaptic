import XCTest
@testable import SnapticKit

final class LiveMailboxTests: XCTestCase {
    private let k = "dell.brightness"

    func testFirstValueGoesAtOnceThenWaitsForTheInterval() {
        var box = LiveMailbox<String>()
        XCTAssertEqual(box.submit(0.5, for: k, final: false, interval: 0.05, now: 10), 0.5)
        XCTAssertNil(box.submit(0.6, for: k, final: false, interval: 0.05, now: 10.01))
        XCTAssertTrue(box.isWaiting(k))
        XCTAssertEqual(box.nextDeadline ?? 0, 10.05, accuracy: 1e-9)
        XCTAssertTrue(box.due(now: 10.04).isEmpty)
        let due = box.due(now: 10.05)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.value, 0.6)
        XCTAssertNil(box.nextDeadline)
    }

    func testNewestValueReplacesTheWaitingOne() {
        var box = LiveMailbox<String>()
        _ = box.submit(0.1, for: k, final: false, interval: 0.05, now: 0)
        XCTAssertNil(box.submit(0.2, for: k, final: false, interval: 0.05, now: 0.01))
        XCTAssertNil(box.submit(0.3, for: k, final: false, interval: 0.05, now: 0.02))
        XCTAssertEqual(box.due(now: 0.06).map { $0.value }, [0.3])
    }

    func testFinalAlwaysGoesAndClearsTheWaitingValue() {
        var box = LiveMailbox<String>()
        _ = box.submit(0.1, for: k, final: false, interval: 0.05, now: 0)
        _ = box.submit(0.2, for: k, final: false, interval: 0.05, now: 0.01)
        XCTAssertEqual(box.submit(0.25, for: k, final: true, interval: 0.05, now: 0.02), 0.25)
        XCTAssertFalse(box.isWaiting(k))
        XCTAssertTrue(box.due(now: 1).isEmpty)
        // Even a final equal to what was just sent goes again (the service skips equal writes).
        XCTAssertEqual(box.submit(0.25, for: k, final: true, interval: 0.05, now: 0.021), 0.25)
    }

    func testZeroIntervalSendsEveryValue() {
        var box = LiveMailbox<String>()
        for i in 0..<10 {
            XCTAssertEqual(box.submit(Double(i) / 10, for: k, final: false, interval: 0, now: Double(i) * 0.001), Double(i) / 10)
        }
    }

    func testSlotsAreIndependent() {
        var box = LiveMailbox<String>()
        XCTAssertEqual(box.submit(0.1, for: "a", final: false, interval: 1, now: 0), 0.1)
        XCTAssertEqual(box.submit(0.2, for: "b", final: false, interval: 1, now: 0), 0.2)
        XCTAssertNil(box.submit(0.3, for: "a", final: false, interval: 1, now: 0.5))
        XCTAssertFalse(box.isWaiting("b"))
        XCTAssertEqual(box.due(now: 1).map { $0.key }, ["a"])
    }

    func testNonFiniteValuesNeverGoOut() {
        var box = LiveMailbox<String>()
        XCTAssertNil(box.submit(.nan, for: k, final: false, interval: 0, now: 0))
        XCTAssertNil(box.submit(.infinity, for: k, final: true, interval: 0, now: 0))
        _ = box.submit(0.4, for: k, final: false, interval: 1, now: 1)
        _ = box.submit(0.5, for: k, final: false, interval: 1, now: 1.1)
        // A broken final flushes the newest real value instead.
        XCTAssertEqual(box.submit(.nan, for: k, final: true, interval: 1, now: 1.2), 0.5)
        XCTAssertFalse(box.isWaiting(k))
    }

    func testClockGoingBackwardsOpensTheSlot() {
        var box = LiveMailbox<String>()
        _ = box.submit(0.1, for: k, final: false, interval: 1, now: 100)
        XCTAssertEqual(box.submit(0.2, for: k, final: false, interval: 1, now: 50), 0.2)
    }

    func testBadIntervalsAreTreatedAsZero() {
        var box = LiveMailbox<String>()
        _ = box.submit(0.1, for: k, final: false, interval: -3, now: 0)
        XCTAssertEqual(box.submit(0.2, for: k, final: false, interval: .nan, now: 0), 0.2)
    }

    func testRemoveAllForgetsSlots() {
        var box = LiveMailbox<String>()
        _ = box.submit(0.1, for: k, final: false, interval: 1, now: 0)
        _ = box.submit(0.2, for: k, final: false, interval: 1, now: 0.1)
        box.removeAll()
        XCTAssertNil(box.nextDeadline)
        XCTAssertEqual(box.submit(0.3, for: k, final: false, interval: 1, now: 0.2), 0.3)
    }

    /// Seeded fuzz: sends are spaced by the interval (finals excepted), nothing waits after a final, and once the
    /// mailbox drains the hardware holds the newest value of every slot (latest wins, nothing lost at the end).
    func testFuzzLatestWinsAndSpacing() {
        for seed in UInt64(1)...40 {
            var rng = SeededGenerator(seed: seed)
            var box = LiveMailbox<Int>()
            var now = 0.0
            var lastSent: [Int: (time: Double, final: Bool)] = [:]
            var hardware: [Int: Double] = [:]
            var newest: [Int: Double] = [:]
            let interval = 0.05
            func record(_ key: Int, _ value: Double, final: Bool) {
                if let last = lastSent[key], !final {
                    XCTAssertGreaterThanOrEqual(now - last.time + 1e-9, interval, "seed \(seed)")
                }
                lastSent[key] = (now, final)
                hardware[key] = value
            }
            for _ in 0..<400 {
                now += Double(rng.next() % 40) / 1000
                for item in box.due(now: now) { record(item.key, item.value, final: false) }
                let key = Int(rng.next() % 3)
                let value = Double(rng.next() % 1001) / 1000
                let final = rng.next() % 9 == 0
                newest[key] = value
                if let sent = box.submit(value, for: key, final: final, interval: interval, now: now) {
                    XCTAssertEqual(sent, value)
                    record(key, sent, final: final)
                }
                if final { XCTAssertFalse(box.isWaiting(key), "seed \(seed)") }
                if let deadline = box.nextDeadline { XCTAssertGreaterThan(deadline + 1e-9, now, "seed \(seed)") }
            }
            while let deadline = box.nextDeadline {
                now = max(now, deadline)
                for item in box.due(now: now) { record(item.key, item.value, final: false) }
            }
            XCTAssertEqual(hardware, newest, "seed \(seed)")
        }
    }

    // MARK: Read-back hold

    func testReadbackIsIgnoredWhileItDisagreesWithinTheHold() {
        XCTAssertFalse(LiveReadback.accepts(0.30, setValue: 0.70, setAt: 10, now: 10.5))
        XCTAssertTrue(LiveReadback.accepts(0.71, setValue: 0.70, setAt: 10, now: 10.5))
        XCTAssertTrue(LiveReadback.accepts(0.30, setValue: 0.70, setAt: 10, now: 11))
        XCTAssertTrue(LiveReadback.accepts(0.30, setValue: nil, setAt: nil, now: 11))
        XCTAssertFalse(LiveReadback.accepts(.nan, setValue: nil, setAt: nil, now: 11))
        // A clock that went backwards keeps holding.
        XCTAssertFalse(LiveReadback.accepts(0.30, setValue: 0.70, setAt: 10, now: 5))
        XCTAssertTrue(LiveReadback.accepts(0.30, setValue: .nan, setAt: 10, now: 10.1))
    }
}

final class ProfileMenuOrderTests: XCTestCase {
    func testCurrentPreviousThenRecentWithoutRepeats() {
        let rows = ProfileMenuOrder.rows(current: "a", previous: "b", recent: ["a", "c", "b", "d", "e"])
        XCTAssertEqual(rows, ["a", "b", "c", "d"])
    }

    func testAtMostFiveRowsAndThreeRecent() {
        let rows = ProfileMenuOrder.rows(current: "a", previous: "b", recent: ["c", "d", "e", "f"])
        XCTAssertEqual(rows, ["a", "b", "c", "d", "e"])
        XCTAssertLessThanOrEqual(rows.count, ProfileMenuOrder.rowLimit)
    }

    func testUnavailableProfilesAreSkippedButCurrentStays() {
        let rows = ProfileMenuOrder.rows(current: "gone", previous: "x", recent: ["y", "z"]) { $0 != "gone" && $0 != "y" }
        XCTAssertEqual(rows, ["gone", "x", "z"])
    }

    func testRememberingMovesToFrontAndCaps() {
        var recent: [String] = []
        for p in ["a", "b", "c", "a", "d"] { recent = ProfileMenuOrder.remembering(p, in: recent) }
        XCTAssertEqual(recent, ["d", "a", "c"])
        XCTAssertEqual(ProfileMenuOrder.remembering("x", in: []), ["x"])
    }

    func testNoPreviousNoRecent() {
        XCTAssertEqual(ProfileMenuOrder.rows(current: 1, previous: nil, recent: []), [1])
    }
}
