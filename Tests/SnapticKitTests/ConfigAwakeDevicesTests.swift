import XCTest
@testable import SnapticKit

/// AwakeActivityConfig, DriveAliveConfig, VolumeUUIDKey and the salted-identifier rules (PLAN 0.3 §2.14, §6.6).
final class ConfigAwakeDevicesTests: XCTestCase {
    private let uuid = "1B4E28BA-2FA1-11D2-883F-0016D3CCA427"

    // MARK: VolumeUUIDKey

    func testVolumeUUIDKeyValidation() throws {
        XCTAssertEqual(VolumeUUIDKey(rawValue: uuid.lowercased())?.rawValue, uuid)
        XCTAssertEqual(VolumeUUIDKey(rawValue: uuid)?.rawValue, uuid)
        for bad in ["", "nope", "1B4E28BA-2FA1-11D2-883F", uuid + "0", " " + uuid, "../../etc"] {
            XCTAssertNil(VolumeUUIDKey(rawValue: bad), bad)
        }
        let decoded = try JSONDecoder().decode([VolumeUUIDKey].self, from: Data("[\"\(uuid.lowercased())\"]".utf8))
        XCTAssertEqual(decoded.first?.rawValue, uuid)
        XCTAssertThrowsError(try JSONDecoder().decode(VolumeUUIDKey.self, from: Data("\"bad\"".utf8)))
    }

    // MARK: AwakeActivityConfig

    func testActivityConfigClampsAndDecodesLossily() throws {
        var c = AwakeActivityConfig()
        XCTAssertEqual(c.stopAfterHours, 1)
        c.stopAfterHours = 0
        XCTAssertEqual(c.sanitized().stopAfterHours, 1)
        c.stopAfterHours = 99
        XCTAssertEqual(c.sanitized().stopAfterHours, 8)
        let bad = try JSONDecoder().decode(AwakeActivityConfig.self, from: Data(#"{"stopAfterHours":"two"}"#.utf8))
        XCTAssertEqual(bad, AwakeActivityConfig())
    }

    // MARK: DriveAliveConfig

    func testDriveAliveDefaults() {
        let c = DriveAliveConfig()
        XCTAssertEqual(c.intervalSeconds, 120)
        XCTAssertFalse(c.evenWithoutSession)
        XCTAssertTrue(c.volumes.values.isEmpty)
        XCTAssertEqual(c.sanitized(), c)
    }

    func testDriveAliveSanitizeClampsInterval() {
        var c = DriveAliveConfig()
        c.intervalSeconds = 1
        XCTAssertEqual(c.sanitized().intervalSeconds, 30)
        c.intervalSeconds = 100_000
        XCTAssertEqual(c.sanitized().intervalSeconds, 600)
    }

    func testDriveAliveSanitizeCapsVolumesEnabledFirst() {
        var c = DriveAliveConfig()
        for i in 0..<30 {
            let digits = String(i)
            let key = VolumeUUIDKey(rawValue: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - digits.count) + digits)!
            c.volumes[key] = DriveAliveVolume(name: "Disk \(i)", enabled: i >= 25)
        }
        let s = c.sanitized()
        XCTAssertEqual(s.volumes.values.count, DriveAliveConfig.maxVolumes)
        XCTAssertEqual(s.enabledVolumes.count, 5, "every enabled volume survives the cap")
        XCTAssertEqual(s.sanitized(), s, "sanitize is idempotent")
    }

    func testDriveAliveSanitizeCleansNames() throws {
        var c = DriveAliveConfig()
        let key = try XCTUnwrap(VolumeUUIDKey(rawValue: uuid))
        c.volumes[key] = DriveAliveVolume(name: "Back\u{202E}up\n" + String(repeating: "x", count: 200), enabled: true,
                                          firstWriteDone: true)
        let v = try XCTUnwrap(c.sanitized().volumes[key])
        XCTAssertFalse(v.name.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0x0A })
        XCTAssertLessThanOrEqual(v.name.unicodeScalars.count, DriveAliveConfig.maxNameScalars)
        XCTAssertTrue(v.enabled)
        XCTAssertTrue(v.firstWriteDone)
    }

    func testDriveAliveDecodeIsLossyPerVolume() throws {
        let json = #"{"volumes":{"\#(uuid)":{"name":"Backup","enabled":true},"not-a-uuid":{"name":"x","enabled":true},"#
            + #""00000000-0000-0000-0000-000000000001":{"name":7,"enabled":"yes"}},"intervalSeconds":"fast","evenWithoutSession":true}"#
        let c = try JSONDecoder().decode(DriveAliveConfig.self, from: Data(json.utf8)).sanitized()
        XCTAssertEqual(c.intervalSeconds, 120)
        XCTAssertTrue(c.evenWithoutSession)
        XCTAssertEqual(c.enabledVolumes, [VolumeUUIDKey(rawValue: uuid)!])
        let second = try XCTUnwrap(c.volumes[VolumeUUIDKey(rawValue: "00000000-0000-0000-0000-000000000001")!])
        XCTAssertEqual(second, DriveAliveVolume(name: "", enabled: false))
        XCTAssertEqual(try JSONDecoder().decode(DriveAliveConfig.self, from: JSONEncoder().encode(c)), c)
    }

    // MARK: Salt and hash material

    func testSaltRules() {
        XCTAssertEqual(AwakeSaltRules.key, "SnapticAwakeSalt")
        XCTAssertNotEqual(AwakeSaltRules.key, IdentityConfig.saltKey, "its own key, separate from the display salt")
        XCTAssertTrue(AwakeSaltRules.isValid(Data(repeating: 7, count: 32)))
        XCTAssertFalse(AwakeSaltRules.isValid(Data(repeating: 0, count: 32)))
        XCTAssertFalse(AwakeSaltRules.isValid(Data(repeating: 7, count: 31)))
        XCTAssertFalse(AwakeSaltRules.isValid(nil))
    }

    func testUSBSerialMaterial() {
        XCTAssertEqual(AwakeHashMaterial.usbSerial("  ABC123\u{0}"), "usb:ABC123")
        XCTAssertNil(AwakeHashMaterial.usbSerial(""))
        XCTAssertNil(AwakeHashMaterial.usbSerial("   "))
        XCTAssertNil(AwakeHashMaterial.usbSerial("0"))
        XCTAssertNil(AwakeHashMaterial.usbSerial("000000"))
        XCTAssertNil(AwakeHashMaterial.usbSerial(String(repeating: "A", count: 129)))
        XCTAssertEqual(AwakeHashMaterial.usbSerial("0001"), "usb:0001")
    }

    func testHex() {
        XCTAssertEqual(AwakeHashMaterial.hex([0x00, 0x0F, 0xA0, 0xFF]), "000fa0ff")
        XCTAssertEqual(AwakeHashMaterial.hex([]), "")
    }
}
