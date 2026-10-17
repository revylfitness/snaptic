import XCTest
@testable import SnapticKit

final class KitHotkeysTests: XCTestCase {
    private func combo(_ key: UInt32, _ mods: UInt32) -> HotkeyCombo { HotkeyCombo(keyCode: key, carbonModifiers: mods) }

    func testValidCombos() {
        XCTAssertNil(HotkeyRules.problem(combo(40, HotkeyRules.command | HotkeyRules.option)))   // ⌥⌘K
        XCTAssertNil(HotkeyRules.problem(combo(40, HotkeyRules.control)))
        XCTAssertNil(HotkeyRules.problem(combo(107, 0)))                                         // F14 alone
        XCTAssertNil(HotkeyRules.problem(combo(122, HotkeyRules.shift)))                         // ⇧F1
    }

    func testRejectedCombos() {
        XCTAssertEqual(HotkeyRules.problem(combo(40, 0)), .needsModifier)
        XCTAssertEqual(HotkeyRules.problem(combo(40, HotkeyRules.option)), .optionShiftOnly)
        XCTAssertEqual(HotkeyRules.problem(combo(40, HotkeyRules.shift | HotkeyRules.option)), .optionShiftOnly)
        XCTAssertEqual(HotkeyRules.problem(combo(55, HotkeyRules.command)), .modifierKey)
        XCTAssertEqual(HotkeyRules.problem(combo(200, HotkeyRules.command)), .unknownKey)
        XCTAssertEqual(HotkeyRules.problem(combo(40, 0x80)), .needsModifier)                     // unknown bits ignored
    }

    func testEveryProblemHasAMessage() {
        for p in [HotkeyRules.Problem.needsModifier, .optionShiftOnly, .modifierKey, .unknownKey] {
            XCTAssertFalse(HotkeyRules.message(p).isEmpty)
        }
    }

    func testNormalizedDropsUnknownBits() {
        XCTAssertEqual(HotkeyRules.normalized(combo(1, HotkeyRules.command | 0x8000 | 0x1)), combo(1, HotkeyRules.command))
    }

    func testDisplayStringUsesAppleOrder() {
        let all = HotkeyRules.control | HotkeyRules.option | HotkeyRules.shift | HotkeyRules.command
        XCTAssertEqual(HotkeyRules.displayString(combo(40, all)), "⌃⌥⇧⌘K")
        XCTAssertEqual(HotkeyRules.displayString(combo(48, HotkeyRules.option)), "⌥⇥")
        XCTAssertEqual(HotkeyRules.displayString(combo(107, 0)), "F14")
        XCTAssertEqual(HotkeyRules.displayString(combo(127, HotkeyRules.command)), "⌘Key 127")
    }

    func testEveryKeyCodeHasAName() {
        // Also builds the name table, which would trap on a duplicate key.
        for code in UInt32(0)..<128 { XCTAssertFalse(HotkeyRules.keyName(code).isEmpty) }
        for code in HotkeyRules.functionKeyCodes { XCTAssertTrue(HotkeyRules.keyName(code).hasPrefix("F")) }
        XCTAssertEqual(HotkeyRules.functionKeyCodes.count, 20)
    }
}
