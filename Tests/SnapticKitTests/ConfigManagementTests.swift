import XCTest
@testable import SnapticKit

final class ConfigManagementTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }
    private func state(main: Bool = false) -> ProtectedDisplayState {
        ProtectedDisplayState(mode: nil, x: 0, y: 0, rotation: 0, mirrorOf: nil, isMain: main)
    }

    func testDefaults() throws {
        let c = ManagementConfig()
        XCTAssertFalse(c.autoDisconnectWithoutDDC)
        XCTAssertEqual(c.protectionFields, ProtectedFields())
        XCTAssertEqual(try JSONDecoder().decode(ManagementConfig.self, from: JSONEncoder().encode(c)), c)
        XCTAssertEqual(try JSONDecoder().decode(ManagementConfig.self, from: Data("{}".utf8)), c)
        let p = PerDisplayManagement()
        XCTAssertEqual(p.powerSwitch, .none)
        XCTAssertEqual(try JSONDecoder().decode(PerDisplayManagement.self, from: Data(#"{"powerSwitch":"explode"}"#.utf8)), p)
    }

    func testProfilesMustMatchTheirSet() {
        var c = ManagementConfig()
        let ab = DisplaySetKey(keys: [key("a"), key("b")])!
        let a = DisplaySetKey(keys: [key("a")])!
        c.protection = LossyMap([
            ab: ProtectionProfile(displays: [key("a"): state(main: true), key("b"): state()]),
            a: ProtectionProfile(displays: [key("b"): state(main: true)]),
        ])
        let s = c.sanitized()
        XCTAssertEqual(Set(s.protection.values.keys), [ab])
    }

    func testAtMost32Profiles() {
        var c = ManagementConfig()
        var all: [DisplaySetKey: ProtectionProfile] = [:]
        let hex = Array("0123456789abcdef")
        for i in 0..<40 {
            let k = DisplayKey(rawValue: String(repeating: hex[i % 16], count: 31) + String(hex[i / 16]))!
            all[DisplaySetKey(keys: [k])!] = ProtectionProfile(displays: [k: state(main: true)], capturedAt: Double(i))
        }
        c.protection = LossyMap(all)
        let s = c.sanitized()
        XCTAssertEqual(s.protection.values.count, ManagementConfig.maxProfiles)
        XCTAssertTrue(s.protection.values.values.allSatisfy { $0.capturedAt >= 8 }, "keeps the most recent")
    }

    func testFieldsLossy() throws {
        let f = try JSONDecoder().decode(ProtectedFields.self, from: Data(#"{"mode":false,"origin":"no"}"#.utf8))
        XCTAssertFalse(f.mode)
        XCTAssertTrue(f.origin)
        XCTAssertTrue(ProtectedFields(mode: false, origin: false, main: false, mirror: false, rotation: false).isEmpty)
    }
}
