import XCTest
@testable import SnapticKit

final class AwakeActivityGateTests: XCTestCase {
    private typealias Gate = AwakeActivityGate

    private static let allEvents: [Gate.Event] = [
        .uiStart, .hotkeyStart, .confirmAsked, .confirmAllowed, .confirmDeclined, .otherStart, .restore, .resume,
        .takeover, .replaced, .ended, .governingEnded(now: 50), .moduleStop, .acted(now: 60), .nothingGoverned(now: 70),
        .unchanged,
    ]

    /// A gate that has acted and seen an end, then went through `events`.
    private func gate(_ events: [Gate.Event]) -> Gate {
        events.reduce(Gate()) { $0.applying($1) }
    }

    func testInitialState() {
        let g = Gate()
        XCTAssertFalse(g.uiStartedInProcess)
        XCTAssertEqual(g.pointer, .notAllowed)
        XCTAssertNil(g.activitySince)
        XCTAssertNil(g.lastEnded)
        XCTAssertFalse(g.pointerAllowed)
    }

    func testUIStartAllowsAndResetsTheCap() {
        let g = gate([.acted(now: 10), .uiStart])
        XCTAssertTrue(g.uiStartedInProcess)
        XCTAssertEqual(g.pointer, .allowed)
        XCTAssertNil(g.activitySince)
        XCTAssertTrue(g.pointerAllowed)
    }

    func testHotkeyStartAsksUntilAllowed() {
        var g = gate([.acted(now: 10), .hotkeyStart])
        XCTAssertFalse(g.uiStartedInProcess)
        XCTAssertEqual(g.pointer, .askOnFirstUse)
        XCTAssertEqual(g.activitySince, 10, "kept")
        // Allow without asking first does nothing.
        XCTAssertEqual(g.applying(.confirmAllowed), g)
        g = g.applying(.confirmAsked)
        XCTAssertEqual(g.pointer, .asking)
        XCTAssertFalse(g.pointerAllowed)
        g = g.applying(.confirmAllowed)
        XCTAssertEqual(g.pointer, .allowed)
        XCTAssertTrue(g.uiStartedInProcess)
        XCTAssertNil(g.activitySince)
    }

    func testNotNowAndDismissalDecline() {
        XCTAssertEqual(gate([.hotkeyStart, .confirmAsked, .confirmDeclined]).pointer, .declined)
        XCTAssertEqual(gate([.hotkeyStart, .confirmDeclined]).pointer, .declined)
        // Stop on the first-nudge toast of a menu start.
        let stopped = gate([.uiStart, .confirmDeclined])
        XCTAssertEqual(stopped.pointer, .declined)
        XCTAssertFalse(stopped.pointerAllowed)
        // A declined gate can't be allowed by the toast again; only a new UI start allows.
        XCTAssertEqual(gate([.hotkeyStart, .confirmAsked, .confirmDeclined, .confirmAsked, .confirmAllowed]).pointer, .declined)
        XCTAssertEqual(gate([.hotkeyStart, .confirmDeclined, .uiStart]).pointer, .allowed)
        // From notAllowed, a decline changes nothing.
        XCTAssertEqual(Gate().applying(.confirmDeclined), Gate())
    }

    func testNonUIEventsClearThePointerAndKeepTheCap() {
        for e in [Gate.Event.otherStart, .restore, .resume, .takeover, .replaced, .ended] {
            let g = gate([.uiStart, .acted(now: 30), .governingEnded(now: 40), e])
            XCTAssertFalse(g.uiStartedInProcess, "\(e)")
            XCTAssertEqual(g.pointer, .notAllowed, "\(e)")
            XCTAssertEqual(g.activitySince, 30, "\(e)")
            XCTAssertEqual(g.lastEnded, 40, "\(e)")
        }
    }

    func testUnchangedLeavesTheGateEqual() {
        let states = [Gate(), gate([.uiStart, .acted(now: 3)]), gate([.hotkeyStart, .confirmAsked]),
                      gate([.otherStart, .governingEnded(now: 9)])]
        for g in states { XCTAssertEqual(g.applying(.unchanged), g) }
    }

    func testModuleStopResets() {
        XCTAssertEqual(gate([.uiStart, .acted(now: 3), .governingEnded(now: 4), .moduleStop]), Gate())
    }

    func testActedSetsOnlyTheFirstTime() {
        let g = gate([.uiStart, .acted(now: 100), .acted(now: 200)])
        XCTAssertEqual(g.activitySince, 100)
        XCTAssertEqual(g.activityElapsed(now: 160), 60)
        XCTAssertEqual(Gate().activityElapsed(now: 160), 0)
        XCTAssertEqual(g.activityElapsed(now: 50), 0, "never negative")
        XCTAssertNil(Gate().applying(.acted(now: .nan)).activitySince)
    }

    // MARK: R5-7 cap chains

    func testRuleHandOffOneSecondApartCarriesTheCap() {
        // Rule A acts, ends (governing → inactive), rule B starts 1 s later.
        var g = gate([.takeover, .acted(now: 1_000), .governingEnded(now: 4_600)])
        g = g.applying(.nothingGoverned(now: 4_600)).applying(.takeover)
        XCTAssertEqual(g.activitySince, 1_000)
        XCTAssertEqual(g.activityElapsed(now: 4_601), 3_601)
    }

    func testHandOffWithoutInactiveTurnCarries() {
        let g = gate([.uiStart, .acted(now: 10), .ended, .takeover, .unchanged])
        XCTAssertEqual(g.activitySince, 10)
    }

    func testFifteenMinutesWithNothingGoverningResets() {
        var g = gate([.uiStart, .acted(now: 10), .ended, .governingEnded(now: 100)])
        g = g.applying(.nothingGoverned(now: 100 + 899))
        XCTAssertEqual(g.activitySince, 10, "a gap under 15 min carries")
        g = g.applying(.nothingGoverned(now: 100 + 900))
        XCTAssertNil(g.activitySince)
    }

    func testLaunchWithNothingGoverningSetsLastEndedWithoutResetting() {
        var g = Gate().applying(.acted(now: 5))
        g = g.applying(.nothingGoverned(now: 2_000))
        XCTAssertEqual(g.lastEnded, 2_000)
        XCTAssertEqual(g.activitySince, 5)
        // A later governingEnded moves the reference.
        g = g.applying(.governingEnded(now: 3_000)).applying(.nothingGoverned(now: 3_500))
        XCTAssertEqual(g.activitySince, 5)
        XCTAssertNil(g.applying(.nothingGoverned(now: 3_900)).activitySince)
    }

    // MARK: R5-1 / N10: only a UI start or an Allow after asking reach `.allowed`

    func testOnlyUIStartOrAllowFromAskingReachAllowed() {
        var rng = SeededGenerator(seed: 0xA11_0E)
        let noUI = Self.allEvents.filter { $0 != .uiStart }
        for _ in 0..<20_000 {
            var g = rng.next() % 2 == 0 ? Gate().applying(.hotkeyStart) : Gate().applying(.otherStart)
            var previous = g
            let length = Int(rng.next() % 12)
            for _ in 0..<length {
                let e = noUI[Int(rng.next() % UInt64(noUI.count))]
                previous = g
                g = g.applying(e)
                if g.pointer == .allowed && previous.pointer != .allowed {
                    XCTAssertEqual(e, .confirmAllowed)
                    XCTAssertEqual(previous.pointer, .asking)
                }
                // `allowed` always comes with uiStartedInProcess.
                if g.pointer == .allowed { XCTAssertTrue(g.uiStartedInProcess) }
                if g.uiStartedInProcess { XCTAssertEqual(g.pointer == .allowed || g.pointer == .declined, true) }
            }
        }
    }

    func testNoSequenceWithoutUIStartOrConfirmationAllows() {
        // From askOnFirstUse/asking, every sequence without confirmAllowed or uiStart leaves pointer != .allowed.
        var rng = SeededGenerator(seed: 0xC0FFEE)
        let blocked = Self.allEvents.filter { $0 != .uiStart && $0 != .confirmAllowed }
        for _ in 0..<20_000 {
            var g = Gate().applying(.hotkeyStart)
            if rng.next() % 2 == 0 { g = g.applying(.confirmAsked) }
            for _ in 0..<Int(rng.next() % 16) {
                g = g.applying(blocked[Int(rng.next() % UInt64(blocked.count))])
                XCTAssertNotEqual(g.pointer, .allowed)
                XCTAssertFalse(g.pointerAllowed)
            }
        }
    }
}
