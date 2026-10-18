import XCTest
@testable import SnapticKit

/// OtherAssertions (PLAN 0.3 §1.1, §2.8, §3.6): parsing other processes' assertions and SleepDisabled.
final class OtherAssertionsTests: XCTestCase {
    private func assertion(_ type: String, level: Any? = 255, process: String? = nil, behalf: Any? = nil,
                           suspended: Any? = nil) -> [String: Any] {
        var d: [String: Any] = [OtherAssertions.typeKey: type]
        if let level { d[OtherAssertions.levelKey] = level }
        if let process { d[OtherAssertions.processKey] = process }
        if let behalf { d[OtherAssertions.onBehalfOfPIDKey] = behalf }
        if let suspended { d[OtherAssertions.suspendedKey] = suspended }
        return d
    }

    // MARK: Types

    func testKeepingTypesMapToKinds() {
        XCTAssertEqual(OtherAssertions.kind(ofType: "PreventUserIdleSystemSleep"), .idleSleep)
        XCTAssertEqual(OtherAssertions.kind(ofType: "NoIdleSleepAssertion"), .idleSleep)
        XCTAssertEqual(OtherAssertions.kind(ofType: "SystemIsActive"), .idleSleep)
        XCTAssertEqual(OtherAssertions.kind(ofType: "PreventUserIdleDisplaySleep"), .display)
        XCTAssertEqual(OtherAssertions.kind(ofType: "NoDisplaySleepAssertion"), .display)
        XCTAssertEqual(OtherAssertions.kind(ofType: "PreventSystemSleep"), .systemSleep)
    }

    func testOtherTypesAreIgnored() {
        for type in ["UserIsActive", "BackgroundTask", "PreventDiskIdle", "ApplePushServiceTask",
                     "InteractivePushServiceTask", "InternalPreventSleep", "InternalPreventDisplaySleep",
                     "DenySystemSleep", "EnableIdleSleep", "NetworkClientActive", "", "preventsystemsleep"] {
            XCTAssertNil(OtherAssertions.kind(ofType: type), type)
        }
    }

    func testKindsOrderStrongestLast() {
        XCTAssertLessThan(OtherAssertionKind.idleSleep, .display)
        XCTAssertLessThan(OtherAssertionKind.display, .systemSleep)
    }

    // MARK: Holders

    func testHoldersSkipOwnKernelAndInactive() {
        let byProcess: [Int32: [[String: Any]]] = [
            0: [assertion("PreventSystemSleep")],
            -3: [assertion("PreventSystemSleep")],
            100: [assertion("PreventUserIdleSystemSleep", process: "Snaptic")],
            200: [assertion("PreventUserIdleDisplaySleep", process: "caffeinate")],
            300: [assertion("PreventUserIdleSystemSleep", level: 0),
                  assertion("PreventUserIdleDisplaySleep", suspended: true),
                  assertion("UserIsActive")],
        ]
        let holders = OtherAssertions.holders(byProcess, ownPID: 100)
        XCTAssertEqual(holders, [OtherAssertionHolder(pid: 200, reportedName: "caffeinate", kinds: [.display], count: 1)])
    }

    func testMissingLevelCountsAsOn() {
        let holders = OtherAssertions.holders([42: [assertion("PreventSystemSleep", level: nil)]], ownPID: 1)
        XCTAssertEqual(holders.map(\.kinds), [[.systemSleep]])
    }

    func testOnBehalfOfAttributesToTheApp() {
        let byProcess: [Int32: [[String: Any]]] = [
            50: [assertion("PreventUserIdleSystemSleep", process: "coreaudiod", behalf: 700),
                 assertion("PreventUserIdleSystemSleep", process: "coreaudiod", behalf: Int32(100))],
            700: [assertion("PreventUserIdleDisplaySleep", process: "Music")],
        ]
        let holders = OtherAssertions.holders(byProcess, ownPID: 100)
        // The one for pid 100 (us) is dropped; coreaudiod's for Music merges into Music's own entry.
        XCTAssertEqual(holders, [OtherAssertionHolder(pid: 700, reportedName: "Music", kinds: [.idleSleep, .display],
                                                      count: 2)])
    }

    func testBadOnBehalfValuesKeepTheOwner() {
        for bad in [Any](arrayLiteral: 0, -5, "700", Double.nan, 1.5, Int64(Int32.max) + 1) {
            let holders = OtherAssertions.holders([50: [assertion("PreventSystemSleep", process: "d", behalf: bad)]],
                                                  ownPID: 1)
            XCTAssertEqual(holders.map(\.pid), [50], "\(bad)")
        }
    }

    func testReportedNamesAreCleaned() {
        let name = "\u{202E}evil\u{0007}" + String(repeating: "x", count: 200)
        let holders = OtherAssertions.holders([9: [assertion("PreventSystemSleep", process: name)]], ownPID: 1)
        let reported = holders.first?.reportedName ?? ""
        XCTAssertTrue(reported.hasPrefix("evil"))
        XCTAssertEqual(reported.unicodeScalars.count, OtherAssertions.maxNameScalars)
        let blank = OtherAssertions.holders([9: [assertion("PreventSystemSleep", process: "  \u{0001} ")]], ownPID: 1)
        XCTAssertNil(blank.first?.reportedName)
        XCTAssertEqual(blank.first?.count, 1)
    }

    func testHoldersAreBounded() {
        var byProcess: [Int32: [[String: Any]]] = [:]
        for pid in Int32(1)...Int32(100) {
            byProcess[pid] = Array(repeating: assertion("PreventUserIdleSystemSleep"), count: 300)
        }
        let holders = OtherAssertions.holders(byProcess, ownPID: 0)
        XCTAssertEqual(holders.count, OtherAssertions.maxHolders)
        XCTAssertEqual(holders.map(\.pid), Array(Int32(1)...Int32(64)))
        XCTAssertTrue(holders.allSatisfy { $0.count == OtherAssertions.maxAssertionsPerProcess })
    }

    func testIsActiveValueShapes() {
        XCTAssertTrue(OtherAssertions.isActive([:]))
        XCTAssertTrue(OtherAssertions.isActive([OtherAssertions.levelKey: 255]))
        XCTAssertTrue(OtherAssertions.isActive([OtherAssertions.levelKey: "junk"]))
        XCTAssertFalse(OtherAssertions.isActive([OtherAssertions.levelKey: 0]))
        XCTAssertFalse(OtherAssertions.isActive([OtherAssertions.levelKey: NSNumber(value: 0)]))
        XCTAssertFalse(OtherAssertions.isActive([OtherAssertions.suspendedKey: true]))
        XCTAssertFalse(OtherAssertions.isActive([OtherAssertions.suspendedKey: 1]))
        XCTAssertTrue(OtherAssertions.isActive([OtherAssertions.suspendedKey: false]))
    }

    // MARK: Rows

    func testRowsMergeEqualNamesAndSort() {
        let holders = [
            OtherAssertionHolder(pid: 1, reportedName: nil, kinds: [.idleSleep], count: 1),
            OtherAssertionHolder(pid: 2, reportedName: nil, kinds: [.display], count: 3),
            OtherAssertionHolder(pid: 3, reportedName: nil, kinds: [.systemSleep], count: 1),
            OtherAssertionHolder(pid: 4, reportedName: nil, kinds: [.idleSleep], count: 1),
            OtherAssertionHolder(pid: 5, reportedName: nil, kinds: [], count: 0),
        ]
        let names: [Int32: String] = [1: "zoom.us", 2: "Zoom.us", 3: "Backup Tool", 4: " \u{0001} ", 5: "Empty"]
        let rows = OtherAssertions.rows(holders) { names[$0.pid] }
        XCTAssertEqual(rows, [
            OtherAssertionRow(name: "Backup Tool", kinds: [.systemSleep], processes: 1),
            OtherAssertionRow(name: "zoom.us", kinds: [.display, .idleSleep], processes: 2),
        ])
    }

    func testRowsDropUnnamedHolders() {
        let rows = OtherAssertions.rows([OtherAssertionHolder(pid: 1, reportedName: nil, kinds: [.display], count: 1)]) { _ in nil }
        XCTAssertEqual(rows, [])
    }

    // MARK: SleepDisabled

    func testSleepDisabled() {
        XCTAssertFalse(OtherAssertions.sleepDisabled(nil))
        XCTAssertFalse(OtherAssertions.sleepDisabled([:]))
        XCTAssertFalse(OtherAssertions.sleepDisabled(["Other": true]))
        XCTAssertTrue(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: true]))
        XCTAssertTrue(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: 1]))
        XCTAssertTrue(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: NSNumber(value: 1)]))
        XCTAssertTrue(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: "YES"]))
        XCTAssertFalse(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: false]))
        XCTAssertFalse(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: 0]))
        XCTAssertFalse(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: "maybe"]))
        XCTAssertFalse(OtherAssertions.sleepDisabled([OtherAssertions.sleepDisabledKey: [1]]))
    }

    // MARK: Fuzz

    /// Random shapes never trap, never list `ownPID` or a pid ≤ 0, and always respect the bounds.
    func testFuzzedRepliesStayInBounds() {
        var g = SeededGenerator(seed: 0x534E_5054)
        let types = ["PreventSystemSleep", "PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "UserIsActive",
                     "BackgroundTask", "NoIdleSleepAssertion", "x"]
        func pick<T>(_ list: [T]) -> T { list[Int(g.next() % UInt64(list.count))] }
        let values: [Any] = [0, 1, 255, -1, "1", true, false, Double.infinity, NSNumber(value: 7), [String: Any](), 100, 7]
        for _ in 0..<300 {
            var byProcess: [Int32: [[String: Any]]] = [:]
            for _ in 0..<Int(g.next() % 12) {
                let pid = Int32(truncatingIfNeeded: Int(g.next() % 20) - 3)
                var list: [[String: Any]] = []
                for _ in 0..<Int(g.next() % 6) {
                    var d: [String: Any] = [:]
                    if g.next() % 5 != 0 { d[OtherAssertions.typeKey] = pick(types) }
                    if g.next() % 2 == 0 { d[OtherAssertions.levelKey] = pick(values) }
                    if g.next() % 3 == 0 { d[OtherAssertions.onBehalfOfPIDKey] = pick(values) }
                    if g.next() % 4 == 0 { d[OtherAssertions.suspendedKey] = pick(values) }
                    if g.next() % 2 == 0 { d[OtherAssertions.processKey] = g.next() % 2 == 0 ? "proc" : pick(values) }
                    list.append(d)
                }
                byProcess[pid] = list
            }
            let holders = OtherAssertions.holders(byProcess, ownPID: 7)
            XCTAssertLessThanOrEqual(holders.count, OtherAssertions.maxHolders)
            XCTAssertTrue(holders.allSatisfy { $0.pid > 0 && $0.pid != 7 && !$0.kinds.isEmpty && $0.count > 0 })
            XCTAssertEqual(holders.map(\.pid), holders.map(\.pid).sorted())
            let rows = OtherAssertions.rows(holders) { $0.reportedName }
            XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty && !$0.kinds.isEmpty && $0.processes > 0 })
            XCTAssertEqual(rows.map(\.processes).reduce(0, +), holders.filter { $0.reportedName != nil }.count)
        }
    }
}
