import XCTest
@testable import SnapticKit

final class ConfigDDCTests: XCTestCase {
    func testVCPKey() {
        XCTAssertEqual(VCPKey(0x10).rawValue, "10")
        XCTAssertEqual(VCPKey(rawValue: "D6")?.code, 0xD6)
        XCTAssertNil(VCPKey(rawValue: "d6"), "uppercase only, so keys are canonical")
        XCTAssertNil(VCPKey(rawValue: "1"))
        XCTAssertNil(VCPKey(rawValue: "GG"))
        XCTAssertLessThan(VCPKey(0x10), VCPKey(0x12))
    }

    func testRoundTripWithControlsInputsAndCustom() throws {
        var p = PerDisplayDDC()
        p.framing = .spec
        p.controls[VCPKey(0x10)] = DDCControlTuning()
        p.inputs = [DDCInputEntry(value: 0x0F, name: "Mac"), DDCInputEntry(value: 0x11, name: "PC", hidden: true)]
        p.unlockedCodes = [VCPKey(0xE0)]
        p.customControls = [DDCCustomControl(name: "Mode", code: 0xDC, kind: .command, value: 3)]
        let decoded = try JSONDecoder().decode(PerDisplayDDC.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    func testOneBadInputDoesNotDropTheList() throws {
        let json = #"{"inputs":[{"value":15,"name":"A"},{"name":"no value"},{"value":17,"name":"B","hidden":"x"}]}"#
        let p = try JSONDecoder().decode(PerDisplayDDC.self, from: Data(json.utf8))
        XCTAssertEqual(p.inputs.map(\.value), [15, 17])
        XCTAssertFalse(p.inputs[1].hidden)
    }

    func testSanitize() {
        var p = PerDisplayDDC()
        p.replyDelayMs = 0
        p.retries = 99
        p.writeCount = 5
        p.unlockedCodes = [VCPKey(0x10), VCPKey(0xE0), VCPKey(0xE0), VCPKey(0x60)]
        p.inputs = (0..<40).map { DDCInputEntry(value: UInt16($0), name: String(repeating: "x", count: 300)) }
        p.inputs.append(DDCInputEntry(value: 1, name: "dup"))
        p.standbyValue = 5
        var tuning = DDCControlTuning()
        tuning.minimum = 50
        tuning.maximum = 10
        tuning.readbackInterval = 0.01
        p.controls[VCPKey(0x12)] = tuning
        let s = p.sanitized()
        XCTAssertEqual(s.replyDelayMs, 10)
        XCTAssertEqual(s.retries, 8)
        XCTAssertEqual(s.writeCount, 2)
        XCTAssertEqual(s.unlockedCodes, [VCPKey(0xE0)], "only unlockable codes can be unlocked")
        XCTAssertEqual(s.inputs.count, PerDisplayDDC.maxInputs)
        XCTAssertLessThanOrEqual(s.inputs[0].name.unicodeScalars.count, 64)
        XCTAssertEqual(s.standbyValue, 4, "hard power-off is never a standby value")
        XCTAssertNil(s.controls[VCPKey(0x12)]?.maximum)
        XCTAssertEqual(s.controls[VCPKey(0x12)]?.readbackInterval, 0.5)
        XCTAssertEqual(s.sanitized(), s)
    }

    func testUnknownControlKeysAreDropped() throws {
        let json = #"{"controls":{"10":{"inverted":true},"zz":{"inverted":true}}}"#
        let p = try JSONDecoder().decode(PerDisplayDDC.self, from: Data(json.utf8)).sanitized()
        XCTAssertEqual(p.controls.values.count, 1)
        XCTAssertEqual(p.tuning(0x10).inverted, true)
        let out = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(out.contains("zz"))
    }

    func testTuningMapping() {
        var t = DDCControlTuning()
        XCTAssertEqual(t.raw(fraction: 0.5, displayMax: 100), 50)
        XCTAssertEqual(t.fraction(raw: 25, displayMax: 100), 0.25, accuracy: 1e-12)
        t.minimum = 20
        t.maximum = 80
        XCTAssertEqual(t.raw(fraction: 0, displayMax: 100), 20)
        XCTAssertEqual(t.raw(fraction: 1, displayMax: 100), 80)
        XCTAssertEqual(t.fraction(raw: 50, displayMax: 100), 0.5, accuracy: 1e-12)
        t.inverted = true
        XCTAssertEqual(t.raw(fraction: 1, displayMax: 100), 20)
        XCTAssertEqual(t.fraction(raw: 80, displayMax: 100), 0, accuracy: 1e-12)
        XCTAssertEqual(DDCControlTuning().raw(fraction: .nan, displayMax: 100), 0)
        XCTAssertEqual(DDCControlTuning().fraction(raw: 5, displayMax: 0), 0)
    }

    func testAllowAndUnlockLookups() {
        var p = PerDisplayDDC()
        p.unlockedCodes = [VCPKey(0xE1)]
        XCTAssertTrue(p.isUnlocked(0xE1))
        XCTAssertFalse(p.isUnlocked(0xE2))
    }

    func testGlobalConfig() throws {
        let c = try JSONDecoder().decode(DDCConfig.self, from: Data(#"{"readback":true,"defaultReadbackInterval":-4}"#.utf8))
        XCTAssertTrue(c.readback)
        XCTAssertEqual(c.sanitized().defaultReadbackInterval, 0.5)
        XCTAssertEqual(try JSONDecoder().decode(DDCConfig.self, from: Data("{}".utf8)), DDCConfig())
    }
}
