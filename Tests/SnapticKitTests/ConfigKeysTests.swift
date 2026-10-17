import XCTest
@testable import SnapticKit

final class ConfigKeysTests: XCTestCase {
    func testOSDefaults() {
        XCTAssertEqual(OSDPosition.osDefault(majorVersion: 26), .underIcon)
        XCTAssertEqual(OSDPosition.osDefault(majorVersion: 27), .topCenter, "R5.8: top center on 27")
        XCTAssertEqual(OSDStyle.osDefault(majorVersion: 27), .rounded)
        XCTAssertEqual(OSDStyle.osDefault(majorVersion: 15), .classic)
        var k = KeysConfig()
        XCTAssertEqual(k.effectiveOSDPosition(osMajor: 27), .topCenter)
        k.osdPosition = .bottomCenter
        XCTAssertEqual(k.effectiveOSDPosition(osMajor: 27), .bottomCenter)
    }

    func testRoundTripWithShortcutsAndSlots() throws {
        var k = KeysConfig()
        k.shortcuts[DisplayActionID(rawValue: "c.brightnessUp")] = HotkeyCombo(keyCode: 0x7E, carbonModifiers: 0x1100)
        k.inputSlots = [InputSlot(display: DisplayKey(rawValue: String(repeating: "b", count: 32)), value: 0x11)]
        k.osdStyle = .classic
        XCTAssertEqual(try JSONDecoder().decode(KeysConfig.self, from: JSONEncoder().encode(k)), k)
    }

    func testLossyDecode() throws {
        let json = #"{"steps":"x","target":"nowhere","osdPosition":"left","osdStyle":"rounded","inputSlots":[{"value":17},5]}"#
        let k = try JSONDecoder().decode(KeysConfig.self, from: Data(json.utf8))
        XCTAssertEqual(k.steps, 16)
        XCTAssertEqual(k.target, .pointer)
        XCTAssertNil(k.osdPosition)
        XCTAssertEqual(k.osdStyle, .rounded)
        XCTAssertEqual(k.inputSlots.map(\.value), [17])
        XCTAssertEqual(try JSONDecoder().decode(KeysConfig.self, from: Data("{}".utf8)), KeysConfig())
    }

    func testSanitize() {
        var k = KeysConfig()
        k.steps = 1
        k.fineSteps = 2
        k.inputSlots = Array(repeating: InputSlot(), count: 20)
        k.shortcuts[DisplayActionID(rawValue: "ok")] = HotkeyCombo(keyCode: 1, carbonModifiers: 0x0100)
        k.shortcuts[DisplayActionID(rawValue: "badKey")] = HotkeyCombo(keyCode: 9999, carbonModifiers: 0x0100)
        k.shortcuts[DisplayActionID(rawValue: "badMods")] = HotkeyCombo(keyCode: 1, carbonModifiers: 0x0001)
        let s = k.sanitized()
        XCTAssertEqual(s.steps, KeysConfig.stepRange.lowerBound)
        XCTAssertGreaterThanOrEqual(s.fineSteps, s.steps)
        XCTAssertEqual(s.inputSlots.count, KeysConfig.maxSlots)
        XCTAssertEqual(Set(s.shortcuts.values.keys.map(\.rawValue)), ["ok"])
        XCTAssertEqual(s.sanitized(), s)
        XCTAssertEqual(KeysConfig().step(fine: false), 1.0 / 16)
        XCTAssertEqual(KeysConfig().step(fine: true), 1.0 / 64)
    }

    func testPerDisplayKeys() throws {
        var p = PerDisplayKeys()
        p.audioDeviceName = "\u{202E}LG HDR 4K" + String(repeating: "x", count: 200)
        let s = p.sanitized()
        XCTAssertFalse(s.audioDeviceName?.unicodeScalars.contains { $0.value == 0x202E } ?? true)
        XCTAssertLessThanOrEqual(s.audioDeviceName?.unicodeScalars.count ?? 0, 64)
        p.audioDeviceName = "\u{1}"
        XCTAssertNil(p.sanitized().audioDeviceName)
        XCTAssertEqual(try JSONDecoder().decode(PerDisplayKeys.self, from: Data(#"{"keysEnabled":false}"#.utf8)).keysEnabled, false)
    }
}
