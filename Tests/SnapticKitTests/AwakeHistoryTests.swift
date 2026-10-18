import XCTest
@testable import SnapticKit

final class AwakeHistoryTests: XCTestCase {
    private func entry(_ start: Double, _ end: Double, kind: AwakeHistoryKind = .duration, source: AwakeSessionSource = .menu,
                       reason: AwakeEndReason = .timeUp, bundleID: String? = nil) -> AwakeHistoryEntry {
        AwakeHistoryEntry(start: start, end: end, kind: kind, source: source, presetID: nil, triggerID: nil,
                          bundleID: bundleID, endReason: reason)
    }

    func testOffersStartAgainPerSourceAndKind() {
        XCTAssertTrue(entry(0, 1).offersStartAgain)
        XCTAssertTrue(entry(0, 1, source: .hotkey).offersStartAgain)
        XCTAssertTrue(entry(0, 1, source: .launch).offersStartAgain)
        XCTAssertFalse(entry(0, 1, source: .commandLine).offersStartAgain)
        XCTAssertFalse(entry(0, 1, source: .rule).offersStartAgain)
        XCTAssertFalse(entry(0, 1, kind: .process).offersStartAgain)
        XCTAssertFalse(entry(0, 1, kind: .automatic).offersStartAgain)
        XCTAssertTrue(entry(0, 1, kind: .idle).offersStartAgain)
        XCTAssertTrue(entry(0, 1, kind: .app, bundleID: "com.apple.dt.Xcode").offersStartAgain)
        XCTAssertFalse(entry(0, 1, kind: .app).offersStartAgain, "an app session without its app can't start again")
    }

    func testAppendingCapsAndKeepsTheNewest() {
        var h = AwakeHistory()
        for i in 0..<600 { h = h.appending(entry(Double(i) * 100, Double(i) * 100 + 50), cap: 500) }
        XCTAssertEqual(h.entries.count, 500)
        XCTAssertEqual(h.entries.first?.start, 10_000)
        XCTAssertEqual(h.entries.last?.start, 59_900)
        XCTAssertEqual(AwakeHistory().appending(entry(0, 1), cap: 0).entries.count, 1, "cap is at least 1")
        XCTAssertEqual(h.appending(entry(1e9, 1e9 + 1), cap: 10_000).entries.count, 500, "cap is at most 500")
    }

    func testShortReplacedRunsMerge() {
        var h = AwakeHistory().appending(entry(0, 1_000, reason: .timeUp), cap: 500)
        // Clicking through presets: two replacements within seconds, then a real session.
        h = h.appending(entry(2_000, 2_010, reason: .replaced), cap: 500)
        h = h.appending(entry(2_010, 2_030, reason: .replaced), cap: 500)
        h = h.appending(entry(2_030, 5_000, reason: .user), cap: 500)
        XCTAssertEqual(h.entries.count, 2)
        XCTAssertEqual(h.entries.last?.start, 2_000)
        XCTAssertEqual(h.entries.last?.end, 5_000)
        XCTAssertEqual(h.entries.last?.endReason, .user)
        // A long replaced session stays, and so does one that isn't contiguous.
        h = h.appending(entry(6_000, 6_120, reason: .replaced), cap: 500)
        h = h.appending(entry(6_120, 7_000), cap: 500)
        h = h.appending(entry(8_000, 8_010, reason: .replaced), cap: 500)
        h = h.appending(entry(9_000, 9_500), cap: 500)
        XCTAssertEqual(h.entries.count, 6)
    }

    func testInvalidEntriesAreNotAppended() {
        XCTAssertEqual(AwakeHistory().appending(entry(10, 5), cap: 500).entries, [])
        XCTAssertEqual(AwakeHistory().appending(entry(.nan, 5), cap: 500).entries, [])
        XCTAssertNil(AwakeHistory().appending(entry(0, 5, kind: .app, bundleID: "not valid"), cap: 500).entries.first?.bundleID)
    }

    func testPrune() {
        var h = AwakeHistory()
        let day = 86_400.0
        h.entries = [entry(0, 10), entry(50 * day, 50 * day + 10), entry(95 * day, 95 * day + 10)]
        let pruned = h.pruned(now: 100 * day, keepDays: 90)
        XCTAssertEqual(pruned.entries.map(\.start), [50 * day, 95 * day])
        XCTAssertEqual(h.pruned(now: 100 * day, keepDays: 0).entries.map(\.start), [], "at least one day kept: none here")
        XCTAssertEqual(h.pruned(now: .nan, keepDays: 90), h)
    }

    func testTotalsCountOverlapsOnceAndClipToTheDay() {
        var h = AwakeHistory()
        h.entries = [
            entry(500, 1_500),                         // straddles weekStart: 500 counted for the week
            entry(5_000, 6_000),                       // before today
            entry(10_000, 11_000), entry(10_500, 12_000, kind: .process),   // overlap: 2_000 total
            entry(13_000, 20_000),                     // runs past now: clipped
        ]
        let t = h.totals(todayStart: 9_000, weekStart: 1_000, now: 15_000)
        XCTAssertEqual(t.today, 2_000 + 2_000)
        XCTAssertEqual(t.week, 500 + 1_000 + 2_000 + 2_000)
        XCTAssertEqual(AwakeHistory().totals(todayStart: 0, weekStart: 0, now: 100).today, 0)
        XCTAssertEqual(h.totals(todayStart: 20_000, weekStart: 20_000, now: 15_000).week, 0)
    }

    func testLossyDecodeKeepsTheRestAndSurvivesTheNextSave() throws {
        let json = #"{"entries":[{"start":1,"end":2,"kind":"duration","source":"menu","endReason":"timeUp","bundleID":5},{"start":1,"end":2,"kind":"duration","source":"menu","endReason":"wormhole"},{"start":3,"end":4,"kind":"app","source":"settings","endReason":"appQuit","bundleID":"com.apple.dt.Xcode","presetID":"bad"}]}"#
        let h = try JSONDecoder().decode(AwakeHistory.self, from: Data(json.utf8))
        XCTAssertEqual(h.entries.count, 2)
        XCTAssertNil(h.entries[0].bundleID)
        XCTAssertNil(h.entries[1].presetID)
        XCTAssertEqual(h.entries[1].bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(try JSONDecoder().decode(AwakeHistory.self, from: JSONEncoder().encode(h)), h)
        XCTAssertEqual(try JSONDecoder().decode(AwakeHistory.self, from: Data(#"{"entries":7}"#.utf8)), AwakeHistory())
    }

    func testSanitizeDropsBrokenEntriesAndCaps() {
        var h = AwakeHistory()
        h.entries = (0..<520).map { entry(Double($0), Double($0) + 1) } + [entry(5, 1), entry(-1, 3)]
        let s = h.sanitized()
        XCTAssertEqual(s.entries.count, 500)
        XCTAssertEqual(s.entries.last?.start, 519)
        XCTAssertEqual(AwakeHistory.key, "SnapticAwakeHistoryV1")
    }
}
