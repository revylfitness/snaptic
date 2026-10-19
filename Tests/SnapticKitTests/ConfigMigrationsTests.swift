import XCTest
@testable import SnapticKit

final class ConfigMigrationsTests: XCTestCase {
    func testIDs() {
        XCTAssertEqual(MigrationID.allCases.map(\.rawValue),
                       ["fromDisplays.v1", "fromDisplays.toast", "newModuleCards.v1", "menuShortcuts.v1", "showNits.v1",
                        "powerSwitch.v1", "awakeUpgrade.v1", "v031Welcome.v1", "v031Welcome.done"])
    }

    /// 0.3.1 E1a: recorded once per install; new users are done with the card at once, upgraders aren't.
    func testV031WelcomeMarksUpgradersOnce() {
        var fresh = MigrationLedger()
        XCTAssertFalse(fresh.showsV031Welcome)
        XCTAssertTrue(fresh.recordV031Welcome(upgrader: false))
        XCTAssertTrue(fresh.has(.v031Welcome))
        XCTAssertFalse(fresh.showsV031Welcome)

        var upgrader = MigrationLedger()
        XCTAssertTrue(upgrader.recordV031Welcome(upgrader: true))
        XCTAssertTrue(upgrader.showsV031Welcome)
        // A later launch (the module settings exist by then) changes nothing.
        XCTAssertFalse(upgrader.recordV031Welcome(upgrader: true))
        XCTAssertFalse(upgrader.recordV031Welcome(upgrader: false))
        XCTAssertTrue(upgrader.showsV031Welcome)
        upgrader.record(.v031WelcomeDone)
        XCTAssertFalse(upgrader.showsV031Welcome)
        // A new user's second launch is never taken for an upgrader.
        XCTAssertFalse(fresh.recordV031Welcome(upgrader: true))
        XCTAssertFalse(fresh.showsV031Welcome)
    }

    func testRecordAndHas() {
        var l = MigrationLedger()
        XCTAssertFalse(l.has(.showNits))
        l.record(.showNits)
        l.record(.showNits)
        XCTAssertTrue(l.has(.showNits))
        XCTAssertEqual(l.done, ["showNits.v1"])
    }

    func testDecodesElementWiseAndKeepsUnknownIDs() throws {
        let json = #"{"done":["showNits.v1",7,null,"future.v9","powerSwitch.v1"]}"#
        let l = try JSONDecoder().decode(MigrationLedger.self, from: Data(json.utf8))
        XCTAssertEqual(l.done, ["showNits.v1", "future.v9", "powerSwitch.v1"])
        let back = try JSONDecoder().decode(MigrationLedger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertTrue(back.done.contains("future.v9"))
        XCTAssertEqual(try JSONDecoder().decode(MigrationLedger.self, from: Data("{}".utf8)), MigrationLedger())
        XCTAssertEqual(try JSONDecoder().decode(MigrationLedger.self, from: Data(#"{"done":3}"#.utf8)), MigrationLedger())
    }

    func testEncodingIsSorted() throws {
        var l = MigrationLedger()
        for id in MigrationID.allCases.reversed() { l.record(id) }
        let text = String(decoding: try JSONEncoder().encode(l), as: UTF8.self)
        XCTAssertEqual(text, #"{"done":["awakeUpgrade.v1","fromDisplays.toast","fromDisplays.v1","menuShortcuts.v1","newModuleCards.v1","powerSwitch.v1","showNits.v1","v031Welcome.done","v031Welcome.v1"]}"#)
    }

    func testSanitizedBoundsTheLedgerButKeepsKnownIDs() {
        var l = MigrationLedger()
        for i in 0..<400 { l.done.insert(String(format: "junk.%03d", i)) }
        l.done.insert("")
        l.done.insert("with space")
        l.done.insert(String(repeating: "x", count: 65))
        for id in MigrationID.allCases { l.record(id) }
        let s = l.sanitized()
        XCTAssertEqual(s.done.count, MigrationLedger.maxIDs)
        for id in MigrationID.allCases { XCTAssertTrue(s.has(id)) }
        XCTAssertFalse(s.done.contains(""))
        XCTAssertFalse(s.done.contains("with space"))
        XCTAssertEqual(s.sanitized(), s)
    }
}
