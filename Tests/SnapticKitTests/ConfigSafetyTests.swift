import XCTest
@testable import SnapticKit

final class ConfigSafetyTests: XCTestCase {
    private let key = DisplayKey(rawValue: String(repeating: "a", count: 32))!

    func testDefaults() {
        let c = SafetyConfig()
        XCTAssertEqual(c.confirmResolution, .newModesOnly)
        XCTAssertEqual(c.confirmSeconds, 15)
        XCTAssertTrue(c.panicHotkeyEnabled)
        XCTAssertEqual(c.panicHotkeyCandidates, [SafetyConfig.defaultPanicHotkey, SafetyConfig.fallbackPanicHotkey])
        XCTAssertEqual(c.sanitized(), c)
    }

    func testLossyDecodeAndClamp() throws {
        let json = #"{"confirmResolution":"bogus","confirmSeconds":2,"panicHotkeyEnabled":false,"#
            + #""panicHotkey":{"keyCode":999,"carbonModifiers":256},"keptModes":{"nothex":[]},"#
            + #""preConfirmAllowed":{"\#(key.rawValue)":["60:0011","zz:1","60:0011","d6:0004"]}}"#
        let c = try JSONDecoder().decode(SafetyConfig.self, from: Data(json.utf8)).sanitized()
        XCTAssertEqual(c.confirmResolution, .newModesOnly)
        XCTAssertEqual(c.confirmSeconds, 10)
        XCTAssertFalse(c.panicHotkeyEnabled)
        XCTAssertNil(c.panicHotkey, "invalid key code")
        XCTAssertEqual(c.preConfirmAllowed[key]?.entries, ["60:0011", "d6:0004"])
        XCTAssertTrue(c.keptModes.values.isEmpty)
        XCTAssertTrue(try JSONDecoder().decode(SafetyConfig.self, from: Data("{}".utf8)) == SafetyConfig())
    }

    func testAllowListAndExportStripping() {
        var c = SafetyConfig()
        c.preConfirmAllowed[key] = PreConfirmAllowList(entries: [PreConfirmAllowList.entry(vcp: 0x60, value: 0x11)])
        XCTAssertTrue(c.preConfirmAllowed[key]!.allows(vcp: 0x60, value: 0x11))
        XCTAssertFalse(c.preConfirmAllowed[key]!.allows(vcp: 0x60, value: 0x12))
        XCTAssertTrue(c.strippedForExport().preConfirmAllowed.values.isEmpty, "allow flags are never exported")
        let many = PreConfirmAllowList(entries: (0..<100).map { PreConfirmAllowList.entry(vcp: 0x60, value: UInt16($0)) })
        XCTAssertEqual(many.sanitized().entries.count, PreConfirmAllowList.maxEntries)
    }

    func testKeptModes() throws {
        var k = KeptModes()
        let m = BLayout.mode(1920, 1080, hidpi: true)
        k.remember(m)
        var same = m
        same.ioModeID = 77
        k.remember(same)
        XCTAssertEqual(k.modes, [same], "same shape replaces")
        for i in 0..<40 { k.remember(BLayout.mode(1000 + i, 700)) }
        XCTAssertEqual(k.modes.count, KeptModes.maxModes)
        k.forget(BLayout.mode(1039, 700))
        XCTAssertEqual(k.modes.count, KeptModes.maxModes - 1)
        let bad = KeptModes(modes: [ModeRef(ioModeID: 0, pixelWidth: 0, pixelHeight: 0, pointWidth: 0, pointHeight: 0, refreshMilliHz: 0)])
        XCTAssertTrue(bad.sanitized().modes.isEmpty)
        // One bad element doesn't drop the rest.
        let json = #"[{"ioModeID":1,"pixelWidth":10,"pixelHeight":10,"pointWidth":10,"pointHeight":10,"refreshMilliHz":0},{"x":1}]"#
        XCTAssertEqual(try JSONDecoder().decode(KeptModes.self, from: Data(json.utf8)).modes.count, 1)
    }

    func testCustomPanicHotkeyComesFirst() {
        var c = SafetyConfig()
        c.panicHotkey = HotkeyCombo(keyCode: 12, carbonModifiers: 0x1100)
        XCTAssertEqual(c.sanitized().panicHotkeyCandidates.count, 3)
        XCTAssertEqual(c.panicHotkeyCandidates.first?.keyCode, 12)
        c.panicHotkey = HotkeyCombo(keyCode: 12, carbonModifiers: 0)
        XCTAssertNil(c.sanitized().panicHotkey, "needs a modifier")
    }
}
