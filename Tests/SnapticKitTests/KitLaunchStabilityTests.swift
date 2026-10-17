import XCTest
@testable import SnapticKit

final class KitLaunchStabilityTests: XCTestCase {
    private func crash(_ h: LaunchHistory, at t: Double) -> LaunchHistory {
        KitLaunchStability.beginLaunch(h, now: t).history   // begins, then dies without marks
    }

    func testFirstLaunchIsStable() {
        let r = KitLaunchStability.beginLaunch(LaunchHistory(), now: 100)
        XCTAssertFalse(r.unstable)
        XCTAssertEqual(r.history.records, [LaunchRecord(startedAt: 100)])
    }

    func testOneCrashIsNotEnough() {
        let h = crash(LaunchHistory(), at: 1)
        XCTAssertFalse(KitLaunchStability.beginLaunch(h, now: 2).unstable)
    }

    func testTwoShortCrashesInARowTriggerSafeMode() {
        let h = crash(crash(LaunchHistory(), at: 1), at: 2)
        XCTAssertTrue(KitLaunchStability.beginLaunch(h, now: 3).unstable)
    }

    func testSurvivingOrQuittingCleanlyBreaksTheChain() {
        var h = crash(LaunchHistory(), at: 1)
        h = KitLaunchStability.markSurvived(KitLaunchStability.beginLaunch(h, now: 2).history)
        XCTAssertFalse(KitLaunchStability.beginLaunch(h, now: 3).unstable)

        var q = crash(LaunchHistory(), at: 1)
        q = KitLaunchStability.markCleanQuit(KitLaunchStability.beginLaunch(q, now: 2).history)
        XCTAssertFalse(KitLaunchStability.beginLaunch(q, now: 3).unstable)
    }

    func testSafeModeLaunchThatAlsoCrashesStaysUnstable() {
        var h = crash(crash(LaunchHistory(), at: 1), at: 2)
        let third = KitLaunchStability.beginLaunch(h, now: 3)
        XCTAssertTrue(third.unstable)
        h = third.history   // the Safe Mode launch crashes too
        XCTAssertTrue(KitLaunchStability.beginLaunch(h, now: 4).unstable)
    }

    func testHistoryIsBounded() {
        var h = LaunchHistory()
        for i in 0..<50 { h = KitLaunchStability.markCleanQuit(KitLaunchStability.beginLaunch(h, now: Double(i)).history) }
        XCTAssertEqual(h.records.count, LaunchHistory.maxRecords)
        XCTAssertEqual(h.records.last?.startedAt, 49)
    }

    func testMarksOnEmptyHistoryAreHarmless() {
        XCTAssertEqual(KitLaunchStability.markSurvived(LaunchHistory()), LaunchHistory())
        XCTAssertEqual(KitLaunchStability.markCleanQuit(LaunchHistory()), LaunchHistory())
    }

    func testRoundTrip() throws {
        var h = crash(LaunchHistory(), at: 10)
        h = KitLaunchStability.markSurvived(KitLaunchStability.beginLaunch(h, now: 20).history)
        let data = try XCTUnwrap(KitLaunchStability.encode(h))
        XCTAssertEqual(KitLaunchStability.decode(data), h)
    }

    func testGarbageDecodesToEmpty() {
        XCTAssertEqual(KitLaunchStability.decode(nil), LaunchHistory())
        XCTAssertEqual(KitLaunchStability.decode(Data("not json".utf8)), LaunchHistory())
        XCTAssertEqual(KitLaunchStability.decode(Data("[1,2]".utf8)), LaunchHistory())
        XCTAssertEqual(KitLaunchStability.decode(Data(repeating: 0x20, count: 20_000)), LaunchHistory())
    }

    func testDamagedFieldsNeverForceSafeMode() throws {
        let json = #"{"records":[{"startedAt":"x"},{"survived":"no"},{}]}"#
        let h = KitLaunchStability.decode(Data(json.utf8))
        XCTAssertEqual(h.records.count, 3)
        XCTAssertFalse(KitLaunchStability.beginLaunch(h, now: 1).unstable)
    }

    func testFuzzedHistoriesDecideOnlyFromTheLastTwo() {
        var rng = SeededGenerator(seed: 0x57AB)
        for _ in 0..<2_000 {
            var h = LaunchHistory()
            for i in 0..<Int(rng.next() % 10) {
                h.records.append(LaunchRecord(startedAt: Double(i), survived: rng.next() % 2 == 0,
                                              cleanQuit: rng.next() % 2 == 0))
            }
            let last = h.records.suffix(2)
            let expected = last.count == 2 && last.allSatisfy { !$0.survived && !$0.cleanQuit }
            XCTAssertEqual(KitLaunchStability.beginLaunch(h, now: 99).unstable, expected)
        }
    }
}
