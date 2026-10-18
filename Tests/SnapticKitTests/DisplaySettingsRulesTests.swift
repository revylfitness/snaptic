import XCTest
@testable import SnapticKit

final class DisplaySettingsRulesTests: XCTestCase {
    // MARK: Shortcut groups

    func testEveryLegacyActionHasAGroup() {
        let expected: [String: DisplayShortcutGroup] = [
            "c.brightnessUp": .brightness, "c.brightnessDownFine": .brightness, "c.xdrToggle": .brightness,
            "c.syncToggle": .brightness, "c.volumeUp": .volumeAndContrast, "c.mute": .volumeAndContrast,
            "c.contrastDownFine": .volumeAndContrast, "c.gammaUp": .color, "c.temperatureDown": .color,
            "c.invert": .color, "c.colorReset": .color, "c.colorSuspend": .color, "c.nightShiftToggle": .color,
            "c.menuBarStrip": .color, "c.ddcPowerOn": .inputsAndPower, "c.ddcStandby": .inputsAndPower,
            "c.inputSlot3": .inputsAndPower, "d.resolutionUp": .resolution, "d.hiDPIToggle": .resolution,
            "d.nativeHalved": .resolution, "d.defaultMode": .resolution, "d.notchToggle": .resolution,
            "d.matchUI": .resolution, "d.favorite2": .resolution, "d.rotate": .arrangement,
            "d.mirrorToggle": .arrangement, "d.layout4": .arrangement, "d.virtualToggle1": .arrangement,
            "d.connectAll": .arrangement, "e.pipToggle.abc": .pictureInPicture, "e.pipStopAll": .pictureInPicture,
            "f.showPanel": .tools, "f.identify": .tools, "f.redetect": .tools, "f.copyDiagnostics": .tools,
            "b.restoreAll": .tools, "b.resumeAutomation": .tools, "a.custom.0F3A": .customActions,
        ]
        for (id, group) in expected {
            XCTAssertEqual(DisplayShortcutGroup.group(for: id), group, id)
        }
        // Every legacy action id lands somewhere, and unknown ids land in Tools.
        for legacy in ControlLegacy.ids where legacy.rawValue.hasPrefix("l.action.") {
            let id = String(legacy.rawValue.dropFirst("l.action.".count)).replacingOccurrences(of: "*", with: "1")
            XCTAssertTrue(DisplayShortcutGroup.allCases.contains(DisplayShortcutGroup.group(for: id)), id)
        }
        XCTAssertEqual(DisplayShortcutGroup.group(for: ""), .tools)
        XCTAssertEqual(DisplayShortcutGroup.group(for: "zzz"), .tools)
    }

    func testGroupTitlesAreSentenceCaseAndUnique() {
        let titles = DisplayShortcutGroup.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        for t in titles where t != "Picture in Picture" {
            let rest = t.dropFirst()
            XCTAssertEqual(String(rest), String(rest).lowercased(), t)
        }
    }

    func testFilterMatchesWordPrefixesOfTitleAndGroup() {
        let g = DisplayShortcutGroup.brightness
        XCTAssertTrue(DisplayShortcutGroup.matches(title: "Brightness Up", group: g, query: ""))
        XCTAssertTrue(DisplayShortcutGroup.matches(title: "Brightness Up", group: g, query: "   "))
        XCTAssertTrue(DisplayShortcutGroup.matches(title: "Brightness Up", group: g, query: "up"))
        XCTAssertTrue(DisplayShortcutGroup.matches(title: "Brightness Up", group: g, query: "BRI u"))
        XCTAssertFalse(DisplayShortcutGroup.matches(title: "Brightness Up", group: g, query: "down"))
        XCTAssertFalse(DisplayShortcutGroup.matches(title: "Brightness Up", group: g, query: "ightness"))
        XCTAssertTrue(DisplayShortcutGroup.matches(title: "Night Shift On or Off", group: .color, query: "colo"))
        XCTAssertTrue(DisplayShortcutGroup.matches(title: "Écran suivant", group: .tools, query: "ecran"))
    }

    func testFilterFuzzNeverTrapsAndEmptyAlwaysMatches() {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        let alphabet = Array("abcdeéÉ ⌥⇥-_.0123456789XYZ\u{301}\u{0}🙂")
        for _ in 0..<2_000 {
            let n = Int(rng.next() % 90)
            var s = ""
            for _ in 0..<n { s.append(alphabet[Int(rng.next() % UInt64(alphabet.count))]) }
            let group = DisplayShortcutGroup.allCases[Int(rng.next() % UInt64(DisplayShortcutGroup.allCases.count))]
            _ = DisplayShortcutGroup.matches(title: s, group: group, query: s)
            XCTAssertTrue(DisplayShortcutGroup.matches(title: s, group: group, query: ""))
            if !SettingsSearch.words(s).isEmpty, s.count <= SettingsSearch.maxQueryLength {
                XCTAssertTrue(DisplayShortcutGroup.matches(title: s, group: group, query: s), s)
            }
        }
    }

    // MARK: Indicator style

    func testIndicatorChoiceRoundTrips() {
        for choice in IndicatorStyleChoice.allCases {
            let k = KeysConfig().settingIndicator(choice)
            XCTAssertEqual(k.indicatorChoice(systemOffered: true), choice)
        }
    }

    func testSystemIndicatorOnlyWhereOffered() {
        var k = KeysConfig().settingIndicator(.classic).settingIndicator(.system)
        XCTAssertTrue(k.osdNative)
        XCTAssertEqual(k.osdStyle, .classic, "the drawn style stays for when the system indicator can't be used")
        XCTAssertEqual(k.indicatorChoice(systemOffered: false), .classic)
        k = k.settingIndicator(.automatic)
        XCTAssertFalse(k.osdNative)
        XCTAssertNil(k.osdStyle)
        XCTAssertEqual(KeysConfig().indicatorChoice(systemOffered: true), .automatic)
    }

    // MARK: Restore brightness

    func testRestoreChoice() {
        XCTAssertEqual(BrightnessRestoreChoice.shown(featureOn: false, mode: .brightness), .off)
        XCTAssertEqual(BrightnessRestoreChoice.shown(featureOn: true, mode: .adjustmentsOnly), .adjustmentsOnly)
        let off = BrightnessRestoreChoice.stored(.off, current: .adjustmentsOnly)
        XCTAssertFalse(off.featureOn)
        XCTAssertEqual(off.mode, .adjustmentsOnly, "Off keeps the stored mode")
        let on = BrightnessRestoreChoice.stored(.brightness, current: .adjustmentsOnly)
        XCTAssertTrue(on.featureOn)
        XCTAssertEqual(on.mode, .brightness)
        for choice in BrightnessRestoreMode.allCases {
            for mode in BrightnessRestoreMode.allCases {
                let s = BrightnessRestoreChoice.stored(choice, current: mode)
                XCTAssertEqual(BrightnessRestoreChoice.shown(featureOn: s.featureOn, mode: s.mode), choice)
            }
        }
    }

    // MARK: Restore defaults

    func testKeyboardDefaultsKeepShortcuts() {
        var c = DisplaysConfig()
        let up = DisplayActionID(rawValue: "c.brightnessUp")
        let combo = HotkeyCombo(keyCode: 0x7E, carbonModifiers: 0x1100)
        c.keys.shortcuts[up] = combo
        c.keys.steps = 32
        c.keys.inputSlots = [InputSlot(value: 0x11)]
        c.brightness.smoothTransitions = !BrightnessConfig().smoothTransitions
        let r = c.restoringKeyboardDefaults()
        XCTAssertEqual(r.keys.shortcuts[up], combo)
        XCTAssertEqual(r.keys.steps, KeysConfig().steps)
        XCTAssertEqual(r.keys.inputSlots, KeysConfig().inputSlots)
        XCTAssertEqual(r.brightness, c.brightness, "other sections stay")
    }

    func testColorDefaultsKeepOverlaysAndOnlyTouchTheChosenDisplay() {
        let a = DisplayKey(rawValue: String(repeating: "a", count: 32))!
        let b = DisplayKey(rawValue: String(repeating: "b", count: 32))!
        var c = DisplaysConfig()
        for key in [a, b] {
            var entry = PerDisplayConfig()
            entry.color.adjustments.contrast = 1.3
            entry.color.adjustments.brightness = 0.6
            entry.color.suspended = true
            entry.color.menuBarStrip = true
            entry.color.cornerRadiusTop = 0.02
            entry.color.cornerRadiusBottom = 0.01
            entry.brightness.minHardware = 0.3
            c.perDisplay[key] = entry
        }
        c.color.suspendAll = true

        let one = c.restoringColorDefaults(for: a)
        XCTAssertEqual(one.perDisplay[a]?.color.adjustments.contrast, 1)
        XCTAssertEqual(one.perDisplay[a]?.color.suspended, false)
        XCTAssertEqual(one.perDisplay[a]?.color.menuBarStrip, true)
        XCTAssertEqual(one.perDisplay[a]?.color.cornerRadiusTop, 0.02)
        XCTAssertEqual(one.perDisplay[a]?.color.cornerRadiusBottom, 0.01)
        XCTAssertEqual(one.perDisplay[a]?.color.adjustments.brightness, 0.6)
        XCTAssertEqual(one.perDisplay[a]?.brightness.minHardware, 0.3, "other sections stay")
        XCTAssertEqual(one.perDisplay[b], c.perDisplay[b], "the other display stays")
        XCTAssertTrue(one.color.suspendAll, "one display leaves the shared settings")

        let all = c.restoringColorDefaults(for: nil)
        for key in [a, b] {
            XCTAssertEqual(all.perDisplay[key]?.color.adjustments.contrast, 1)
            XCTAssertEqual(all.perDisplay[key]?.color.menuBarStrip, true)
            XCTAssertEqual(all.perDisplay[key]?.color.cornerRadiusTop, 0.02)
        }
        XCTAssertFalse(all.color.suspendAll)
    }

    // MARK: Raw values

    func testParseValue() {
        XCTAssertEqual(HardwareControlText.parseValue("17"), 17)
        XCTAssertEqual(HardwareControlText.parseValue(" 0x11 "), 17)
        XCTAssertEqual(HardwareControlText.parseValue("11h"), 17)
        XCTAssertEqual(HardwareControlText.parseValue("0XfF"), 255)
        XCTAssertEqual(HardwareControlText.parseValue("65535"), 65535)
        XCTAssertNil(HardwareControlText.parseValue("65536"))
        XCTAssertNil(HardwareControlText.parseValue(""))
        XCTAssertNil(HardwareControlText.parseValue("0x"))
        XCTAssertNil(HardwareControlText.parseValue("h"))
        XCTAssertNil(HardwareControlText.parseValue("-1"))
        XCTAssertNil(HardwareControlText.parseValue("12345678901"))
        XCTAssertNil(HardwareControlText.parseValue("1.5"))
    }

    func testParseValueFuzz() {
        var rng = SeededGenerator(seed: 42)
        let alphabet = Array("0123456789abcdefxhX -+.")
        for _ in 0..<5_000 {
            let n = Int(rng.next() % 12)
            var s = ""
            for _ in 0..<n { s.append(alphabet[Int(rng.next() % UInt64(alphabet.count))]) }
            if let v = HardwareControlText.parseValue(s) {
                XCTAssertEqual(HardwareControlText.parseValue(String(v)), v)
                XCTAssertEqual(HardwareControlText.parseValue("0x" + String(v, radix: 16)), v)
            }
        }
    }
}
