import XCTest
import SnapticKit

final class ConfigDisplaysTests: XCTestCase {
    private let key = DisplayKey(rawValue: String(repeating: "a", count: 32))!

    func testRoundTrip() throws {
        var c = DisplaysConfig()
        c.features[.xdr] = true
        c.perDisplay[key] = PerDisplayConfig()
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(DisplaysConfig.self, from: data), c)
    }

    func testBadSectionFallsBackAlone() throws {
        let json = #"{"features":{"xdr":true,"futureFeature":true,"sync":"yes"},"brightness":42,"perDisplay":{"nothex":{},"\#(key.rawValue)":{}}}"#
        let c = try JSONDecoder().decode(DisplaysConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.features[.xdr], true)
        XCTAssertNil(c.features[.sync])
        XCTAssertNotNil(c.perDisplay[key])
        XCTAssertEqual(c.brightness, BrightnessConfig())
    }

    func testUnknownFeatureKeysSurviveRoundTrip() throws {
        let json = #"{"features":{"futureFeature":true}}"#
        let c = try JSONDecoder().decode(DisplaysConfig.self, from: Data(json.utf8))
        let out = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertTrue(out.contains("futureFeature"))
    }

    func testSanitizedCapsRememberedDisplays() {
        var c = DisplaysConfig()
        for i in 0..<(DisplaysConfig.maxRememberedDisplays + 10) {
            let k = DisplayKey(rawValue: String(format: "%032x", i))!
            c.perDisplay[k] = PerDisplayConfig()
        }
        XCTAssertEqual(c.sanitized().perDisplay.values.count, DisplaysConfig.maxRememberedDisplays)
    }

    func testGarbageDecodesToDefaults() throws {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<300 {
            let bytes = (0..<Int(rng.next() % 64)).map { _ in UInt8(rng.next() % 256) }
            if let c = try? JSONDecoder().decode(DisplaysConfig.self, from: Data(bytes)) {
                XCTAssertEqual(c.sanitized(), c.sanitized().sanitized())
            }
        }
    }
}
