import XCTest
@testable import SnapticKit

final class ConfigIdentityTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }

    func testDefaultsAndClamp() throws {
        XCTAssertEqual(IdentityConfig().forgetAfterDays, 90)
        let c = try JSONDecoder().decode(IdentityConfig.self, from: Data(#"{"forgetAfterDays":1,"showOfflineDisplays":"x"}"#.utf8))
        XCTAssertEqual(c.sanitized().forgetAfterDays, 7)
        XCTAssertTrue(c.showOfflineDisplays)
    }

    func testSaltRules() {
        XCTAssertEqual(IdentityConfig.saltKey, "SnapticDisplaySalt")
        XCTAssertTrue(IdentityConfig.isValidSalt(Data((0..<32).map { UInt8($0) })))
        XCTAssertFalse(IdentityConfig.isValidSalt(Data(count: 32)), "all zero")
        XCTAssertFalse(IdentityConfig.isValidSalt(Data(count: 16)))
        XCTAssertFalse(IdentityConfig.isValidSalt(nil))
        // The salt is never part of the Displays settings.
        let json = String(data: try! JSONEncoder().encode(DisplaysConfig()), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("Salt"))
    }

    func testForgetting() {
        var old = PerDisplayIdentity()
        old.lastSeen = 0
        var recent = PerDisplayIdentity()
        recent.lastSeen = 100 * 86_400
        let never = PerDisplayIdentity()
        let all = [key("a"): old, key("b"): recent, key("c"): never, key("d"): old]
        let forget = IdentityConfig().keysToForget(all, online: [key("d")], now: 120 * 86_400)
        XCTAssertEqual(forget, [key("a")], "online and recently seen displays stay")
    }

    func testPerDisplaySanitizing() throws {
        var p = PerDisplayIdentity()
        p.customName = "  Office\u{0000}Left " + String(repeating: "x", count: 200)
        p.symbol = "display; rm -rf"
        p.lastSeen = .nan
        let s = p.sanitized()
        XCTAssertLessThanOrEqual(s.customName?.unicodeScalars.count ?? 0, PerDisplayIdentity.maxNameScalars)
        XCTAssertFalse(s.customName?.contains("\u{0000}") ?? true)
        XCTAssertNil(s.symbol)
        XCTAssertNil(s.lastSeen)
        var q = PerDisplayIdentity()
        q.symbol = "display.2"
        q.customName = "   "
        XCTAssertEqual(q.sanitized().symbol, "display.2")
        XCTAssertNil(q.sanitized().customName)
        // Legacy menu keys (now MenuConfig's) are ignored; a bad fingerprint decodes lossily.
        let decoded = try JSONDecoder().decode(PerDisplayIdentity.self,
                                               from: Data(#"{"hiddenInMenu":true,"menuOrder":3,"customName":"Desk","fingerprint":7}"#.utf8))
        XCTAssertEqual(decoded.customName, "Desk")
        XCTAssertTrue(decoded.fingerprint.isEmpty)
        XCTAssertEqual(PerDisplayIdentity.day(86_400 * 3 + 500), 86_400 * 3)
    }
}
