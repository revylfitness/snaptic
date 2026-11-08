import XCTest
@testable import SnapticKit

/// 0.4 §4.10: the fixed table of other menu bar hiders (ids from S0-15).
final class KnownMenuBarHidersTests: XCTestCase {
    func testTheTable() {
        XCTAssertEqual(KnownMenuBarHiders.all.map(\.name), ["Hidden Bar", "Bartender", "Ice", "Thaw"])
        XCTAssertEqual(KnownMenuBarHiders.all.map(\.bundleID),
                       ["com.dwarvesv.minimalbar", "com.surteesstudios.Bartender", "com.jordanbaird.Ice",
                        "com.stonerl.Thaw"])
        for h in KnownMenuBarHiders.all { XCTAssertTrue(AwakeBundleID.isValid(h.bundleID), h.name) }
    }

    func testMatchNeedsTheTeamWhenKnown() {
        XCTAssertEqual(KnownMenuBarHiders.match(bundleID: "com.dwarvesv.minimalbar", teamID: "W777S7V8TN")?.name,
                       "Hidden Bar")
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.dwarvesv.minimalbar", teamID: "AAAAAAAAAA"))
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.dwarvesv.minimalbar", teamID: nil))
        XCTAssertEqual(KnownMenuBarHiders.match(bundleID: "com.jordanbaird.Ice", teamID: "K2ATHQPJDP")?.name, "Ice")
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.jordanbaird.Ice", teamID: "A7CKWF99ML"))
    }

    func testUnknownTeamMatchesByBundleOnly() {
        XCTAssertEqual(KnownMenuBarHiders.match(bundleID: "com.surteesstudios.Bartender", teamID: nil)?.name, "Bartender")
        XCTAssertEqual(KnownMenuBarHiders.match(bundleID: "com.surteesstudios.Bartender", teamID: "ZZ")?.name, "Bartender")
    }

    func testThawIsAPrefixMatchOnComponents() {
        let team = "A7CKWF99ML"
        XCTAssertEqual(KnownMenuBarHiders.match(bundleID: "com.stonerl.Thaw", teamID: team)?.name, "Thaw")
        XCTAssertEqual(KnownMenuBarHiders.match(bundleID: "com.stonerl.Thaw.beta", teamID: team)?.name, "Thaw")
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.stonerl.Thawed", teamID: team))
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.stonerl.Thaw.beta", teamID: nil))
    }

    func testExactIDsAreNotPrefixes() {
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.jordanbaird.Ice.fork", teamID: "K2ATHQPJDP"))
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "com.jordanbaird.ice", teamID: "K2ATHQPJDP"))
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: nil, teamID: "K2ATHQPJDP"))
        XCTAssertNil(KnownMenuBarHiders.match(bundleID: "", teamID: nil))
    }
}
