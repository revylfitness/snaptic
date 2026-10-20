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
        XCTAssertTrue(fresh.recordV031Welcome(upgrader: false, canAsk: true))
        XCTAssertTrue(fresh.has(.v031Welcome))
        XCTAssertFalse(fresh.showsV031Welcome)

        var upgrader = MigrationLedger()
        XCTAssertTrue(upgrader.recordV031Welcome(upgrader: true, canAsk: true))
        XCTAssertTrue(upgrader.showsV031Welcome)
        // A later launch (the module settings exist by then) changes nothing.
        XCTAssertFalse(upgrader.recordV031Welcome(upgrader: true, canAsk: true))
        XCTAssertFalse(upgrader.recordV031Welcome(upgrader: false, canAsk: true))
        XCTAssertTrue(upgrader.showsV031Welcome)
        upgrader.record(.v031WelcomeDone)
        XCTAssertFalse(upgrader.showsV031Welcome)
        // A new user's second launch is never taken for an upgrader.
        XCTAssertFalse(fresh.recordV031Welcome(upgrader: true, canAsk: true))
        XCTAssertFalse(fresh.showsV031Welcome)
    }

    /// r3 C3-5: a new user whose first 0.3.1 build can't update itself (ad hoc, from source) was never asked, so they
    /// aren't done with the card: the first signed build shows it. A new user of a signed build is asked in onboarding.
    func testV031WelcomeStaysDueForNewUsersOfBuildsThatCantAsk() {
        var adHoc = MigrationLedger()
        XCTAssertTrue(adHoc.recordV031Welcome(upgrader: false, canAsk: false))
        XCTAssertTrue(adHoc.has(.v031Welcome))
        XCTAssertFalse(adHoc.has(.v031WelcomeDone))
        XCTAssertTrue(adHoc.showsV031Welcome)
        // The signed build's launch later records nothing new, and the card is still due.
        XCTAssertFalse(adHoc.recordV031Welcome(upgrader: true, canAsk: true))
        XCTAssertTrue(adHoc.showsV031Welcome)

        var signed = MigrationLedger()
        XCTAssertTrue(signed.recordV031Welcome(upgrader: false, canAsk: true))
        XCTAssertTrue(signed.has(.v031WelcomeDone))
        XCTAssertFalse(signed.showsV031Welcome)

        var upgrader = MigrationLedger()
        XCTAssertTrue(upgrader.recordV031Welcome(upgrader: true, canAsk: false))
        XCTAssertFalse(upgrader.has(.v031WelcomeDone))
    }

    /// r2 C2-1: a 0.1 or 0.2 user (launched before, no module settings yet) skips onboarding, so they get the card.
    func testV031UpgradersIncludeUsersOfVersionsBeforeModuleSettings() {
        XCTAssertFalse(MigrationLedger.isV031Upgrader(modulesExisted: false, launchedBefore: false))
        XCTAssertTrue(MigrationLedger.isV031Upgrader(modulesExisted: true, launchedBefore: false))
        XCTAssertTrue(MigrationLedger.isV031Upgrader(modulesExisted: true, launchedBefore: true))
        XCTAssertTrue(MigrationLedger.isV031Upgrader(modulesExisted: false, launchedBefore: true))
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
