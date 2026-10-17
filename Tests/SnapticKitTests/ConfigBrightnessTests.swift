import XCTest
@testable import SnapticKit

final class ConfigBrightnessTests: XCTestCase {
    func testDefaultsRoundTrip() throws {
        let c = BrightnessConfig()
        XCTAssertEqual(try JSONDecoder().decode(BrightnessConfig.self, from: JSONEncoder().encode(c)), c)
        var p = PerDisplayBrightness()
        p.method = .ddc
        p.value = 0.4
        p.nits = NitsRange(minimum: 1, maximum: 400, peak: 800, isEstimate: false)
        p.gammaWorks = false
        XCTAssertEqual(try JSONDecoder().decode(PerDisplayBrightness.self, from: JSONEncoder().encode(p)), p)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try JSONDecoder().decode(BrightnessConfig.self, from: Data("{}".utf8)), BrightnessConfig())
        XCTAssertEqual(try JSONDecoder().decode(PerDisplayBrightness.self, from: Data("{}".utf8)), PerDisplayBrightness())
    }

    func testFieldsDecodeLossily() throws {
        let json = #"{"restoreMode":"bogus","dimOnLockLevel":"x","xdrMaxScale":2.5,"syncSource":"nothex","syncMode":"delta"}"#
        let c = try JSONDecoder().decode(BrightnessConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.restoreMode, .brightness)
        XCTAssertEqual(c.dimOnLockLevel, 0.5)
        XCTAssertEqual(c.xdrMaxScale, 2.5)
        XCTAssertNil(c.syncSource)
        XCTAssertEqual(c.syncMode, .delta)
        let p = try JSONDecoder().decode(PerDisplayBrightness.self, from: Data(#"{"method":"laser","value":0.3,"xdrEnabled":"yes"}"#.utf8))
        XCTAssertNil(p.method)
        XCTAssertEqual(p.value, 0.3)
        XCTAssertFalse(p.xdrEnabled)
    }

    func testSanitizeClamps() {
        var c = BrightnessConfig()
        c.dimOnLockLevel = 0
        c.xdrMaxScale = 50
        c.xdrBatteryFloor = 0.01
        let s = c.sanitized()
        XCTAssertEqual(s.dimOnLockLevel, BrightnessConfig.dimOnLockFloor)
        XCTAssertEqual(s.xdrMaxScale, 4)
        XCTAssertEqual(s.xdrBatteryFloor, 0.2, "20% is the hard minimum")
        var p = PerDisplayBrightness()
        p.value = 7
        p.switchover = -1
        p.minHardware = .nan
        p.xdrMax = 0.5
        p.syncOffset = 3
        let q = p.sanitized()
        XCTAssertEqual(q.value, 1)
        XCTAssertEqual(q.switchover, 0)
        XCTAssertEqual(q.minHardware, 0)
        XCTAssertEqual(q.xdrMax, BrightnessConfig.xdrScaleRange.lowerBound)
        XCTAssertEqual(q.syncOffset, 0.5)
        XCTAssertEqual(q.sanitized(), q)
    }

    func testMethodMetadata() {
        XCTAssertTrue(BrightnessMethod.apple.isHardware)
        XCTAssertTrue(BrightnessMethod.ddc.isHardware)
        XCTAssertFalse(BrightnessMethod.gamma.isHardware)
        XCTAssertEqual(BrightnessMethod.overlay.feature, .brightnessOverlay)
        for m in BrightnessMethod.allCases { XCTAssertEqual(FeatureGraph.controller(of: m.feature), .brightness) }
    }

    func testFuzzedJSONNeverTrapsAndSanitizeIsIdempotent() {
        var rng = SeededGenerator(seed: 0xB417)
        let fragments = [#""value":"#, #""xdrMax":"#, #""method":"#, "1e309", "-3", "\"apple\"", "null", "{}", "[]", "0.5"]
        for _ in 0..<500 {
            var json = "{"
            for i in 0..<Int(rng.next() % 4) {
                if i > 0 { json += "," }
                json += fragments[Int(rng.next() % 3)] + fragments[3 + Int(rng.next() % 7)]
            }
            json += "}"
            if let p = try? JSONDecoder().decode(PerDisplayBrightness.self, from: Data(json.utf8)) {
                XCTAssertEqual(p.sanitized(), p.sanitized().sanitized())
            }
        }
    }
}
