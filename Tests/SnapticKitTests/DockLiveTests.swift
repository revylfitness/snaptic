import XCTest
@testable import SnapticKit

/// 0.5 §4.22, P3-2: Dock Previews' live counters, the `dock live` line and every increment matched by a decrement.
final class DockLiveTests: XCTestCase {
    func testTheZeroLine() {
        let live = DockLive()
        XCTAssertEqual(live.launchLine(leases: 0),
                       "selftest-launch: dock live observer=0 clickTap=0 keys=0 panel=0 timers=0 leases=0")
        XCTAssertTrue(live.launchProblems(leases: 0).isEmpty)
        XCTAssertTrue(live.isBalanced)
    }

    func testTheLineCarriesEachCountAndTheLeases() {
        var live = DockLive()
        live.increment(.observer)
        live.increment(.timers)
        live.increment(.timers)
        live.increment(.keys)
        XCTAssertEqual(live.launchLine(leases: 2),
                       "selftest-launch: dock live observer=1 clickTap=0 keys=1 panel=0 timers=2 leases=2")
    }

    func testTheKeysAreInTheirFixedOrder() {
        XCTAssertEqual(DockLiveCounter.allCases.map(\.rawValue), ["observer", "clickTap", "keys", "panel", "timers"])
        let keys = DockLive().launchLine(leases: 0)
            .dropFirst("selftest-launch: dock live ".count)
            .split(separator: " ")
            .map { $0.split(separator: "=")[0] }
        XCTAssertEqual(keys, ["observer", "clickTap", "keys", "panel", "timers", "leases"])
    }

    func testEveryIncrementMatchedByADecrementIsBalanced() {
        var live = DockLive()
        for counter in DockLiveCounter.allCases {
            for _ in 0..<3 { live.increment(counter) }
            XCTAssertEqual(live[counter], 3, counter.rawValue)
            XCTAssertFalse(live.isBalanced)
        }
        // Torn down in a different order from the one they were made in.
        for counter in DockLiveCounter.allCases.reversed() {
            for _ in 0..<3 { live.decrement(counter) }
            XCTAssertEqual(live[counter], 0, counter.rawValue)
        }
        XCTAssertTrue(live.isBalanced)
        XCTAssertEqual(live, DockLive())
        XCTAssertTrue(live.launchProblems(leases: 0).isEmpty)
    }

    func testAnUnmatchedDecrementIsCountedAndNeverGoesNegative() {
        var live = DockLive()
        live.decrement(.panel)
        XCTAssertEqual(live[.panel], 0)
        XCTAssertEqual(live.underflows, 1)
        XCTAssertFalse(live.isBalanced)
        XCTAssertEqual(live.launchLine(leases: 0),
                       "selftest-launch: dock live observer=0 clickTap=0 keys=0 panel=0 timers=0 leases=0")
        XCTAssertEqual(live.launchProblems(leases: 0).count, 1)

        live.increment(.panel)
        XCTAssertEqual(live[.panel], 1, "an earlier underflow doesn't swallow a later increment")
        live.decrement(.panel)
        XCTAssertEqual(live[.panel], 0)
        XCTAssertEqual(live.underflows, 1)
    }

    func testProblemsNameEachNonzeroCountAndTheLeases() {
        var live = DockLive()
        XCTAssertEqual(live.launchProblems(leases: 1).count, 1)
        live.increment(.observer)
        live.increment(.clickTap)
        XCTAssertEqual(live.launchProblems(leases: 0).count, 2)
        XCTAssertEqual(live.launchProblems(leases: 1).count, 3)
        XCTAssertTrue(live.launchProblems(leases: 0).allSatisfy { $0.hasPrefix("Dock Previews held 1 ") })
    }
}

