import XCTest
@testable import SnapticKit

final class ConfigAwakeIndicatorTests: XCTestCase {
    func testDefaults() {
        let c = AwakeIndicatorConfig()
        XCTAssertEqual(c.style, .icon)
        XCTAssertEqual(c.glyph, .cup)
        XCTAssertFalse(c.showsTime)
        XCTAssertEqual(c.sanitized(), c)
    }

    func testGlyphSymbols() {
        XCTAssertEqual(AwakeGlyphFamily.cup.idle, "cup.and.saucer")
        XCTAssertEqual(AwakeGlyphFamily.cup.active, "cup.and.saucer.fill")
        XCTAssertEqual(AwakeGlyphFamily.eye.active, "eye.fill")
        XCTAssertEqual(AwakeGlyphFamily.lightbulb.idle, "lightbulb")
        var c = AwakeIndicatorConfig()
        c.glyph = .eye
        XCTAssertEqual(c.symbol(active: true), "eye.fill")
        XCTAssertEqual(c.symbol(active: false), "eye")
        for g in AwakeGlyphFamily.allCases { XCTAssertEqual(g.active, g.idle + ".fill") }
    }

    func testLegacyAndUnknownValuesDecodeAsDefaults() throws {
        for glyph in ["mug", "sun", "bolt", "rocket"] {
            let c = try JSONDecoder().decode(AwakeIndicatorConfig.self, from: Data(#"{"glyph":"\#(glyph)","style":"iconAndTime"}"#.utf8))
            XCTAssertEqual(c.glyph, .cup, glyph)
            XCTAssertEqual(c.style, .iconAndTime)
            XCTAssertTrue(c.showsTime)
        }
        let odd = try JSONDecoder().decode(AwakeIndicatorConfig.self, from: Data(#"{"style":"marquee","glyph":"lightbulb"}"#.utf8))
        XCTAssertEqual(odd.style, .icon)
        XCTAssertEqual(odd.glyph, .lightbulb)
        var c = AwakeIndicatorConfig()
        c.style = .iconAndEndTime
        c.glyph = .eye
        XCTAssertEqual(try JSONDecoder().decode(AwakeIndicatorConfig.self, from: JSONEncoder().encode(c)), c)
    }
}
