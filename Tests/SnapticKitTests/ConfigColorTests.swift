import XCTest
@testable import SnapticKit

final class ConfigColorTests: XCTestCase {
    func testRoundTrip() throws {
        var p = PerDisplayColor()
        p.adjustments.contrast = 1.2
        p.adjustments.inverted = true
        p.menuBarStrip = true
        p.cornerRadiusTop = 0.02
        XCTAssertEqual(try JSONDecoder().decode(PerDisplayColor.self, from: JSONEncoder().encode(p)), p)
        XCTAssertEqual(try JSONDecoder().decode(ColorConfig.self, from: JSONEncoder().encode(ColorConfig())), ColorConfig())
    }

    func testLossyAndSanitize() throws {
        let json = #"{"adjustments":{"contrast":99,"gamma":"x"},"cornerRadiusTop":1,"menuBarStrip":"yes"}"#
        let p = try JSONDecoder().decode(PerDisplayColor.self, from: Data(json.utf8)).sanitized()
        XCTAssertEqual(p.adjustments.contrast, ColorAdjustments.contrastRange.upperBound)
        XCTAssertEqual(p.adjustments.gamma, 1)
        XCTAssertEqual(p.cornerRadiusTop, PerDisplayColor.cornerRange.upperBound)
        XCTAssertFalse(p.menuBarStrip)
        XCTAssertTrue(p.hasRoundedCorners)
        let c = try JSONDecoder().decode(ColorConfig.self, from: Data(#"{"shortcutStep":5}"#.utf8)).sanitized()
        XCTAssertEqual(c.shortcutStep, 0.25)
    }

    func testSuspendKeepsBrightness() {
        var p = PerDisplayColor()
        p.adjustments.brightness = 0.7
        p.adjustments.gamma = 1.4
        XCTAssertEqual(p.effectiveAdjustments(suspendAll: false).gamma, 1.4)
        XCTAssertEqual(p.effectiveAdjustments(suspendAll: true).gamma, 1)
        XCTAssertEqual(p.effectiveAdjustments(suspendAll: true).brightness, 0.7)
        p.suspended = true
        XCTAssertTrue(p.effectiveAdjustments(suspendAll: false).suspended.isIdentity == false)
        XCTAssertEqual(p.effectiveAdjustments(suspendAll: false).gamma, 1)
    }
}
