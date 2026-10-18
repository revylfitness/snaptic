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

    // MARK: M6 (0.3 §4.6): the shortcut row edits the 0.2 fields with their 0.2 meanings, no data migration

    private let custom = HotkeyCombo(keyCode: 15, carbonModifiers: HotkeyRules.control | HotkeyRules.command)   // ⌃⌘R

    func testM6NilKeepsTheDefaultAndItsFallback() {
        let c = SafetyConfig()
        XCTAssertNil(c.panicHotkey)
        XCTAssertTrue(c.panicHotkeyEnabled)
        XCTAssertEqual(c.panicShortcutState, .standard)
        XCTAssertEqual(c.panicShortcutShown, SafetyConfig.defaultPanicHotkey)
        XCTAssertEqual(c.panicHotkeys(longArmed: false), [SafetyConfig.defaultPanicHotkey, SafetyConfig.fallbackPanicHotkey])
        XCTAssertEqual(c.panicHotkeys(longArmed: true), c.panicHotkeys(longArmed: false))
        // A stored combo equal to the default is the default (with its fallback), not a custom shortcut.
        var same = c
        same.panicHotkey = SafetyConfig.defaultPanicHotkey
        XCTAssertEqual(same.panicShortcutState, .standard)
        XCTAssertEqual(same.panicHotkeys(longArmed: false), c.panicHotkeys(longArmed: false))
    }

    func testM6FalseDisablesEveryShortcut() {
        var c = SafetyConfig()
        c.panicHotkeyEnabled = false
        XCTAssertEqual(c.panicShortcutState, .off)
        XCTAssertNil(c.panicShortcutShown)
        XCTAssertEqual(c.panicHotkeys(longArmed: false), [], "no default, no fallback")
        c.panicHotkey = custom
        XCTAssertEqual(c.panicShortcutState, .off, "a stored custom combo doesn't turn it back on")
        XCTAssertEqual(c.panicHotkeys(longArmed: false), [])
        // While a long-armed state exists the shortcut stays registered, whatever the setting (0.2 §4.7).
        XCTAssertEqual(c.panicHotkeys(longArmed: true),
                       [custom, SafetyConfig.defaultPanicHotkey, SafetyConfig.fallbackPanicHotkey])
    }

    func testM6RecordingClearingAndUseDefault() {
        let base = SafetyConfig()
        let recorded = base.settingPanicShortcut(custom)
        XCTAssertEqual(recorded.panicHotkey, custom)
        XCTAssertTrue(recorded.panicHotkeyEnabled)
        XCTAssertEqual(recorded.panicShortcutState, .custom(custom))
        XCTAssertEqual(recorded.panicShortcutShown, custom)
        XCTAssertEqual(recorded.panicHotkeys(longArmed: false),
                       [custom, SafetyConfig.defaultPanicHotkey, SafetyConfig.fallbackPanicHotkey], "custom is tried first")

        // Recording the default stores nil (so the fallback stays behind it).
        XCTAssertNil(recorded.settingPanicShortcut(SafetyConfig.defaultPanicHotkey).panicHotkey)
        XCTAssertEqual(recorded.settingPanicShortcut(SafetyConfig.defaultPanicHotkey).panicShortcutState, .standard)

        // Clear = the 0.2 switch off: the custom combo stays stored, untouched.
        let cleared = recorded.settingPanicShortcut(nil)
        XCTAssertFalse(cleared.panicHotkeyEnabled)
        XCTAssertEqual(cleared.panicHotkey, custom)
        XCTAssertEqual(cleared.panicShortcutState, .off)

        // Recording again after Clear turns it back on.
        XCTAssertEqual(cleared.settingPanicShortcut(custom).panicShortcutState, .custom(custom))

        // Use Default: nil and on, from either state.
        for start in [recorded, cleared] {
            let d = start.usingDefaultPanicShortcut()
            XCTAssertNil(d.panicHotkey)
            XCTAssertTrue(d.panicHotkeyEnabled)
            XCTAssertEqual(d.panicShortcutState, .standard)
        }

        // A combo macOS can't register changes nothing.
        XCTAssertEqual(base.settingPanicShortcut(HotkeyCombo(keyCode: 15, carbonModifiers: 0)), base)
        XCTAssertEqual(base.settingPanicShortcut(HotkeyCombo(keyCode: 15, carbonModifiers: HotkeyRules.option)), base)
        XCTAssertEqual(base.settingPanicShortcut(HotkeyCombo(keyCode: 200, carbonModifiers: HotkeyRules.command)), base)
        // Stray modifier bits are dropped, so the stored combo compares equal to a registered one.
        let noisy = HotkeyCombo(keyCode: 15, carbonModifiers: custom.carbonModifiers | 0x0080)
        XCTAssertEqual(base.settingPanicShortcut(noisy).panicHotkey, custom)
    }

    func testM6WritesOnlyThe02FieldsAndRoundTrips() throws {
        let states = [SafetyConfig(), SafetyConfig().settingPanicShortcut(custom),
                      SafetyConfig().settingPanicShortcut(custom).settingPanicShortcut(nil),
                      SafetyConfig().settingPanicShortcut(nil)]
        let keys: Set<String> = ["confirmResolution", "confirmSeconds", "panicHotkeyEnabled", "panicHotkey",
                                 "announceRecovery", "preConfirmAllowed", "keptModes"]
        for c in states {
            let data = try JSONEncoder().encode(c)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertTrue(Set(object.keys).isSubset(of: keys), "no new keys: \(object.keys.sorted())")
            let back = try JSONDecoder().decode(SafetyConfig.self, from: data).sanitized()
            XCTAssertEqual(back, c)
            XCTAssertEqual(back.panicShortcutState, c.panicShortcutState)
        }
        // 0.2 files mean the same in 0.3.
        let off = try JSONDecoder().decode(SafetyConfig.self, from: Data(#"{"panicHotkeyEnabled":false}"#.utf8))
        XCTAssertEqual(off.panicShortcutState, .off)
        let json = #"{"panicHotkey":{"keyCode":15,"carbonModifiers":\#(custom.carbonModifiers)}}"#
        let mine = try JSONDecoder().decode(SafetyConfig.self, from: Data(json.utf8))
        XCTAssertEqual(mine.panicShortcutState, .custom(custom))
    }

    func testAllowedWithoutAskingDescriptions() {
        XCTAssertEqual(PreConfirmAllowList.describe("60:0011"), "Input source: HDMI 1")
        XCTAssertEqual(PreConfirmAllowList.describe("d6:0004"), "Power mode: Off")
        XCTAssertEqual(PreConfirmAllowList.describe("d6:0002"), "Power mode: Standby")
        XCTAssertEqual(PreConfirmAllowList.describe("10:0032"), "Brightness: 50")
        XCTAssertNil(PreConfirmAllowList.describe("zz:1"))
        XCTAssertNil(PreConfirmAllowList.describe("60:11"))
        let list = PreConfirmAllowList(entries: ["60:0011", "bad", "60:000f"])
        XCTAssertEqual(list.descriptions, ["Input source: HDMI 1", "Input source: DisplayPort 1"])
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
