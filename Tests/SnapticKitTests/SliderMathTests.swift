import XCTest
@testable import SnapticKit

final class SliderMathTests: XCTestCase {
    // MARK: clampSnap

    func testClampSnap() {
        XCTAssertEqual(SliderMath.clampSnap(5.4, range: 0...10, step: 1), 5)
        XCTAssertEqual(SliderMath.clampSnap(5.6, range: 0...10, step: 1), 6)
        XCTAssertEqual(SliderMath.clampSnap(11, range: 0...10, step: 1), 10)
        XCTAssertEqual(SliderMath.clampSnap(-1, range: 0...10, step: 1), 0)
        XCTAssertEqual(SliderMath.clampSnap(22, range: 5...50, step: 5), 20)
        XCTAssertEqual(SliderMath.clampSnap(23, range: 5...50, step: 5), 25)
        XCTAssertEqual(SliderMath.clampSnap(3.3, range: 0...10, step: nil), 3.3)
        XCTAssertEqual(SliderMath.clampSnap(3.3, range: 0...10, step: 0), 3.3)
        XCTAssertEqual(SliderMath.clampSnap(3.3, range: 0...10, step: -1), 3.3)
        XCTAssertEqual(SliderMath.clampSnap(3.3, range: 0...10, step: .nan), 3.3)
        XCTAssertEqual(SliderMath.clampSnap(.nan, range: 2...10, step: 1), 2)
        XCTAssertEqual(SliderMath.clampSnap(.infinity, range: 2...10, step: 1), 2)
        // The upper bound is unreachable when the range isn't a multiple of the step.
        XCTAssertEqual(SliderMath.clampSnap(10, range: 0...10, step: 3), 9)
        XCTAssertEqual(SliderMath.clampSnap(4, range: 4...4, step: 1), 4)
    }

    func testClampSnapRemovesBinaryNoise() {
        XCTAssertEqual(SliderMath.clampSnap(0.1 * 3, range: 0...1, step: 0.1), 0.3)
        XCTAssertEqual(SliderMath.clampSnap(0.7 + 0.1, range: 0...1, step: 0.01), 0.8)
        XCTAssertEqual(SliderMath.clampSnap(1.15, range: 0.05...2, step: 0.1), 1.15)
    }

    // MARK: isDefault and steps

    func testIsDefaultHalfStepTolerance() {
        XCTAssertTrue(SliderMath.isDefault(value: 20, default: 20, step: 5))
        XCTAssertTrue(SliderMath.isDefault(value: 22.4, default: 20, step: 5))
        XCTAssertFalse(SliderMath.isDefault(value: 25, default: 20, step: 5))
        XCTAssertTrue(SliderMath.isDefault(value: 0.5000000001, default: 0.5, step: nil))
        XCTAssertFalse(SliderMath.isDefault(value: 0.501, default: 0.5, step: nil))
        XCTAssertTrue(SliderMath.isDefault(value: 0.504, default: 0.5, step: 0.01))
    }

    func testNilDefaultNeverShowsReset() {
        XCTAssertTrue(SliderMath.isDefault(value: 0.3, default: nil, step: nil))
        XCTAssertTrue(SliderMath.isDefault(value: 900, default: nil, step: 1))
    }

    func testEffectiveStep() {
        XCTAssertEqual(SliderMath.effectiveStep(5, format: .seconds), 5)
        XCTAssertEqual(SliderMath.effectiveStep(nil, format: .percent(of: 1)), 0.01)
        XCTAssertEqual(SliderMath.effectiveStep(nil, format: .percent(of: 100)), 1)
        XCTAssertEqual(SliderMath.effectiveStep(nil, format: .kelvin), 1)
        XCTAssertEqual(SliderMath.effectiveStep(nil, format: .hertz), 0.01)
        XCTAssertEqual(SliderMath.effectiveStep(nil, format: .plain(digits: 2)), 0.01)
        XCTAssertEqual(SliderMath.effectiveStep(0, format: .minutes), 0.1)
    }

    func testPositionsForTickMarks() {
        XCTAssertEqual(SliderMath.positions(range: 0...10, step: 1), 11)
        XCTAssertEqual(SliderMath.positions(range: 5...50, step: 5), 10)
        XCTAssertNil(SliderMath.positions(range: 0...100, step: 1))
        XCTAssertNil(SliderMath.positions(range: 0...1, step: nil))
        XCTAssertEqual(SliderMath.positions(range: 0...100, step: 1, limit: 101), 101)
        XCTAssertEqual(SliderMath.positions(range: 3...3, step: 1), 1)
    }

    func testNudged() {
        XCTAssertEqual(SliderMath.nudged(50, direction: 1, range: 0...100, step: nil), 51)
        XCTAssertEqual(SliderMath.nudged(50, direction: -1, range: 0...100, step: 5), 45)
        XCTAssertEqual(SliderMath.nudged(100, direction: 1, range: 0...100, step: 5), 100)
        XCTAssertEqual(SliderMath.nudged(0, direction: -3, range: 0...100, step: 5), 0)
        XCTAssertEqual(SliderMath.nudged(12, direction: 0, range: 0...100, step: 5), 10)
        XCTAssertEqual(SliderMath.nudged(.nan, direction: 1, range: 10...20, step: 1), 11)
    }

    // MARK: format

    func testFormatUnits() {
        XCTAssertEqual(SliderMath.format(0.7, .percent(of: 1), decimalSeparator: "."), "70%")
        XCTAssertEqual(SliderMath.format(20, .percent(of: 100), decimalSeparator: "."), "20%")
        XCTAssertEqual(SliderMath.format(5, .seconds, decimalSeparator: "."), "5 s")
        XCTAssertEqual(SliderMath.format(1.5, .seconds, decimalSeparator: ","), "1,5 s")
        XCTAssertEqual(SliderMath.format(15, .minutes, decimalSeparator: "."), "15 min")
        XCTAssertEqual(SliderMath.format(60, .hertz, decimalSeparator: "."), "60 Hz")
        XCTAssertEqual(SliderMath.format(59.94, .hertz, decimalSeparator: "."), "59.94 Hz")
        XCTAssertEqual(SliderMath.format(170, .points, decimalSeparator: "."), "170 pt")
        XCTAssertEqual(SliderMath.format(500, .nits, decimalSeparator: "."), "500 nits")
        XCTAssertEqual(SliderMath.format(6500, .kelvin, decimalSeparator: "."), "6500 K")
        XCTAssertEqual(SliderMath.format(1.23456, .plain(digits: 2), decimalSeparator: "."), "1.23")
        XCTAssertEqual(SliderMath.format(1.5, .plain(digits: 0), decimalSeparator: "."), "2")
        XCTAssertEqual(SliderMath.format(-1.5, .plain(digits: 1), decimalSeparator: "."), "-1.5")
        XCTAssertEqual(SliderMath.format(-0.004, .plain(digits: 2), decimalSeparator: "."), "0.00")
        XCTAssertEqual(SliderMath.format(12345678, .plain(digits: 0), decimalSeparator: "."), "12345678")
        XCTAssertEqual(SliderMath.format(2.5, .plain(digits: 99), decimalSeparator: "."), "2.500000")
    }

    func testFormatEdgeCases() {
        XCTAssertEqual(SliderMath.format(.nan, .percent(of: 1), decimalSeparator: "."), "–")
        XCTAssertEqual(SliderMath.format(.infinity, .seconds, decimalSeparator: "."), "–")
        XCTAssertEqual(SliderMath.format(0.5, .percent(of: 0), decimalSeparator: "."), "–")
        XCTAssertEqual(SliderMath.format(1.5, .seconds, decimalSeparator: ""), "1.5 s")
        XCTAssertFalse(SliderMath.format(1e300, .plain(digits: 0), decimalSeparator: ".").isEmpty)
    }

    func testFormatLabels() {
        let labels = ["1280 × 800", "1512 × 982", "1800 × 1169"]
        XCTAssertEqual(SliderLabels.text(1, labels), "1512 × 982")
        XCTAssertEqual(SliderLabels.text(1.4, labels), "1512 × 982")
        XCTAssertEqual(SliderLabels.text(7, labels), "1800 × 1169")
        XCTAssertEqual(SliderLabels.text(-3, labels), "1280 × 800")
        XCTAssertEqual(SliderLabels.text(.nan, labels), "")
        XCTAssertEqual(SliderLabels.text(0, []), "")
        XCTAssertEqual(SliderLabels.widest(["1280 × 800", "1512 × 982", "800 × 600"]), "1280 × 800")
        XCTAssertEqual(SliderLabels.widest([]), "")
    }

    // MARK: spoken

    func testSpoken() {
        XCTAssertEqual(SliderMath.spoken(0.7, .percent(of: 1), decimalSeparator: "."), "70 percent")
        XCTAssertEqual(SliderMath.spoken(1, .minutes, decimalSeparator: "."), "1 minute")
        XCTAssertEqual(SliderMath.spoken(15, .minutes, decimalSeparator: "."), "15 minutes")
        XCTAssertEqual(SliderMath.spoken(1, .seconds, decimalSeparator: "."), "1 second")
        XCTAssertEqual(SliderMath.spoken(1.5, .seconds, decimalSeparator: "."), "1.5 seconds")
        XCTAssertEqual(SliderMath.spoken(60, .hertz, decimalSeparator: "."), "60 hertz")
        XCTAssertEqual(SliderMath.spoken(1, .nits, decimalSeparator: "."), "1 nit")
        XCTAssertEqual(SliderMath.spoken(170, .points, decimalSeparator: "."), "170 points")
        XCTAssertEqual(SliderMath.spoken(6500, .kelvin, decimalSeparator: "."), "6500 kelvin")
        XCTAssertEqual(SliderLabels.spoken(1, ["1280 × 800", "1512 × 982"]), "1512 by 982")
        XCTAssertEqual(SliderMath.spoken(.nan, .seconds, decimalSeparator: "."), "no value")
    }

    // MARK: widestText

    func testWidestText() {
        XCTAssertEqual(SliderMath.widestText(range: 0...600, step: 10, format: .seconds), "600 s")
        XCTAssertEqual(SliderMath.widestText(range: 0...1, step: nil, format: .percent(of: 1)), "100%")
        XCTAssertEqual(SliderMath.widestText(range: 1000...10000, step: 100, format: .kelvin), "10000 K")
        XCTAssertEqual(SliderMath.widestText(range: 48...120, step: nil, format: .hertz), "119.45 Hz")
        XCTAssertEqual(SliderMath.widestText(range: 0.5...2, step: 0.1, format: .seconds), "0.5 s")
        XCTAssertEqual(SliderMath.widestText(range: -100...100, step: 1, format: .plain(digits: 0)), "-100")
    }

    // MARK: parse

    func testParseUnitsAndSpacing() {
        XCTAssertEqual(SliderMath.parse("70", .percent(of: 1), decimalSeparator: "."), 0.7)
        XCTAssertEqual(SliderMath.parse("70 %", .percent(of: 1), decimalSeparator: "."), 0.7)
        XCTAssertEqual(SliderMath.parse("70%", .percent(of: 1), decimalSeparator: "."), 0.7)
        XCTAssertEqual(SliderMath.parse(" 70 percent ", .percent(of: 1), decimalSeparator: "."), 0.7)
        XCTAssertEqual(SliderMath.parse("20", .percent(of: 100), decimalSeparator: "."), 20)
        XCTAssertEqual(SliderMath.parse("15 min", .minutes, decimalSeparator: "."), 15)
        XCTAssertEqual(SliderMath.parse("15m", .minutes, decimalSeparator: "."), 15)
        XCTAssertEqual(SliderMath.parse("60Hz", .hertz, decimalSeparator: "."), 60)
        XCTAssertEqual(SliderMath.parse("59.94 hz", .hertz, decimalSeparator: "."), 59.94)
        XCTAssertEqual(SliderMath.parse("6500 K", .kelvin, decimalSeparator: "."), 6500)
        XCTAssertEqual(SliderMath.parse("6500k", .kelvin, decimalSeparator: "."), 6500)
        XCTAssertEqual(SliderMath.parse("170 pt", .points, decimalSeparator: "."), 170)
        XCTAssertEqual(SliderMath.parse("500 nits", .nits, decimalSeparator: "."), 500)
        XCTAssertEqual(SliderMath.parse("120\u{00A0}s", .seconds, decimalSeparator: "."), 120)
    }

    func testParseDecimalSeparators() {
        XCTAssertEqual(SliderMath.parse("1,5 s", .seconds, decimalSeparator: ","), 1.5)
        XCTAssertEqual(SliderMath.parse("1.5 s", .seconds, decimalSeparator: ","), 1.5)
        XCTAssertEqual(SliderMath.parse("1.5", .seconds, decimalSeparator: "."), 1.5)
        XCTAssertNil(SliderMath.parse("1,5", .seconds, decimalSeparator: "."))
        XCTAssertEqual(SliderMath.parse(".5", .seconds, decimalSeparator: "."), 0.5)
        XCTAssertEqual(SliderMath.parse("5.", .seconds, decimalSeparator: "."), 5)
        XCTAssertEqual(SliderMath.parse("0.3", .plain(digits: 1), decimalSeparator: "."), 0.3)
    }

    func testParseSigns() {
        XCTAssertEqual(SliderMath.parse("-5", .plain(digits: 0), decimalSeparator: "."), -5)
        XCTAssertEqual(SliderMath.parse("\u{2212}5", .plain(digits: 0), decimalSeparator: "."), -5)
        XCTAssertEqual(SliderMath.parse("+5", .plain(digits: 0), decimalSeparator: "."), 5)
    }

    func testParseRejects() {
        XCTAssertNil(SliderMath.parse("70 Hz", .percent(of: 1), decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("1,000", .plain(digits: 0), decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("1 000", .plain(digits: 0), decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("1e3", .plain(digits: 0), decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("1.2.3", .plain(digits: 0), decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("", .seconds, decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("   ", .seconds, decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse(".", .seconds, decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("-", .seconds, decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("abc", .seconds, decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("1234567890123456", .plain(digits: 0), decimalSeparator: "."))
        XCTAssertEqual(SliderMath.parse("123456789012345", .plain(digits: 0), decimalSeparator: "."), 123456789012345)
        XCTAssertNil(SliderMath.parse(String(repeating: "1", count: 65), .plain(digits: 0), decimalSeparator: "."))
        XCTAssertNil(SliderMath.parse("70", .percent(of: .infinity), decimalSeparator: "."))
    }

    func testParseLabels() {
        let labels = ["1280 × 800", "1512 × 982", "1800 × 1169"]
        XCTAssertEqual(SliderLabels.parse("1512x982", labels), 1)
        XCTAssertEqual(SliderLabels.parse(" 1512 × 982 ", labels), 1)
        XCTAssertEqual(SliderLabels.parse("1500 x 1000", labels), 1)
        XCTAssertEqual(SliderLabels.parse("4000x3000", labels), 2)
        XCTAssertNil(SliderLabels.parse("wide", labels))
        XCTAssertNil(SliderLabels.parse("1512x", labels))
        XCTAssertNil(SliderLabels.parse("", labels))
        XCTAssertNil(SliderLabels.parse(String(repeating: "1", count: 65), labels))
        XCTAssertEqual(SliderLabels.parse("Native", ["Default", "Native"]), 1)
    }

    /// Percent-labelled resolution stops: a typed number snaps to the nearest position (review ui F6).
    func testParseLabelsSnapsTypedNumbers() {
        let labels = ["80%", "100%", "120%"]
        XCTAssertEqual(SliderLabels.parse("100", labels), 1)
        XCTAssertEqual(SliderLabels.parse("100%", labels), 1)
        XCTAssertEqual(SliderLabels.parse(" 100 % ", labels), 1)
        XCTAssertEqual(SliderLabels.parse("110%", labels), 1, "a tie takes the lower position")
        XCTAssertEqual(SliderLabels.parse("111", labels), 2)
        XCTAssertEqual(SliderLabels.parse("125%", labels), 2)
        XCTAssertEqual(SliderLabels.parse("5", labels), 0)
        XCTAssertEqual(SliderLabels.parse("-40%", labels), 0)
        XCTAssertEqual(SliderLabels.parse("99,5", labels), 1)
        XCTAssertNil(SliderLabels.parse("%", labels))
        XCTAssertNil(SliderLabels.parse("1x2%", labels))
        // Non-numeric labels are skipped; none numeric means no match.
        XCTAssertEqual(SliderLabels.parse("130", ["Default", "100%", "150%"]), 2)
        XCTAssertNil(SliderLabels.parse("130", ["Default", "Native"]))
        XCTAssertNil(SliderLabels.parse("1512", ["1280 × 800", "1512 × 982"]))
        // Sizes still match sizes.
        XCTAssertEqual(SliderLabels.parse("1500x1000", ["1280 × 800", "1512 × 982"]), 1)
    }

    // MARK: Typed field (review ui F1)

    private func parsePercent(_ text: String) -> Double? {
        SliderMath.parse(text, .percent(of: 1), decimalSeparator: ".").map { SliderMath.clampSnap($0, range: 0...1, step: 0.01) }
    }

    private func showPercent(_ v: Double) -> String { SliderMath.format(v, .percent(of: 1), decimalSeparator: ".") }

    /// Return, then a slider drag, then blur: the field follows the drag and blur writes nothing.
    func testTypedFieldFollowsValueAfterReturnAndNeverWritesStaleText() {
        var f = TypedFieldState(display: "50%")
        f.edit("40")
        XCTAssertTrue(f.isDirty)
        XCTAssertEqual(f.commit(display: "50%", parse: parsePercent, format: showPercent), .write(0.4))
        XCTAssertEqual(f.text, "40%")
        XCTAssertFalse(f.isDirty)
        // Still focused (AppKit keeps first responder after Return); the slider moves to 80%.
        f.sync(display: "80%")
        XCTAssertEqual(f.text, "80%")
        // Focus leaves: nothing typed since, nothing written.
        XCTAssertEqual(f.commit(display: "80%", parse: parsePercent, format: showPercent), .none)
        XCTAssertEqual(f.text, "80%")
    }

    /// A value change elsewhere while focused but untouched is shown; blur doesn't write it back.
    func testTypedFieldFollowsExternalChangesWhileFocused() {
        var f = TypedFieldState(display: "20 s")
        f.sync(display: "25 s")
        f.sync(display: "30 s")
        XCTAssertEqual(f.text, "30 s")
        XCTAssertEqual(f.commit(display: "30 s", parse: { _ in XCTFail("untyped text parsed"); return nil },
                                format: { "\($0)" }), .none)
    }

    /// Typed text survives outside changes until committed, and is what gets written.
    func testTypedFieldKeepsTypingOverExternalChanges() {
        var f = TypedFieldState(display: "50%")
        f.edit("6")
        f.sync(display: "70%")
        XCTAssertEqual(f.text, "6")
        XCTAssertEqual(f.commit(display: "70%", parse: parsePercent, format: showPercent), .write(0.06))
        XCTAssertEqual(f.text, "6%")
    }

    /// Typing the shown text back, or nothing, isn't an edit; invalid text reverts to the current value.
    func testTypedFieldUnchangedAndInvalid() {
        var f = TypedFieldState(display: "50%")
        f.edit("5")
        f.edit("50%")
        XCTAssertFalse(f.isDirty)
        XCTAssertEqual(f.commit(display: "55%", parse: parsePercent, format: showPercent), .none)
        XCTAssertEqual(f.text, "55%", "a commit with nothing typed re-syncs")
        f.edit("abc")
        XCTAssertEqual(f.commit(display: "55%", parse: parsePercent, format: showPercent), .invalid)
        XCTAssertEqual(f.text, "55%")
        XCTAssertFalse(f.isDirty)
        f.edit("x")
        f.revert(display: "60%")
        XCTAssertEqual(f.text, "60%")
        XCTAssertFalse(f.isDirty)
    }

    /// ↑/↓ step from typed text when there is some, else from the value (not from the rounded text).
    func testTypedFieldNudge() {
        var f = TypedFieldState(display: "50%")
        let up: (Double) -> Double = { SliderMath.nudged($0, direction: 1, range: 0...1, step: 0.01) }
        let raw: (String) -> Double? = { SliderMath.parse($0, .percent(of: 1), decimalSeparator: ".") }
        XCTAssertEqual(f.nudge(value: 0.8, parse: raw, step: up, format: showPercent), 0.81, accuracy: 1e-9)
        XCTAssertEqual(f.text, "81%")
        f.edit("30")
        XCTAssertEqual(f.nudge(value: 0.81, parse: raw, step: up, format: showPercent), 0.31, accuracy: 1e-9)
        XCTAssertFalse(f.isDirty)
    }

    /// Round 2 ui F1: text typed without Return, then the row's own slider drag (or stepper arrow, or Reset): the
    /// field shows the new value and focus leaving later writes nothing over it.
    func testTypedFieldRowControlDiscardsTyping() {
        var f = TypedFieldState(display: "50%")
        f.edit("40")
        // Drag begins (the row bumps its discard token at the start of the drag).
        f.discardTyping(display: "50%")
        XCTAssertFalse(f.isDirty)
        XCTAssertEqual(f.text, "50%")
        // The drag moves the value; the field follows.
        f.sync(display: "80%")
        XCTAssertEqual(f.text, "80%")
        XCTAssertEqual(f.commit(display: "80%", parse: { _ in XCTFail("discarded text parsed"); return nil },
                                format: showPercent), .none)
        XCTAssertEqual(f.text, "80%")

        // Reset: the value and the discard arrive in the same update, in either order.
        for discardFirst in [true, false] {
            var r = TypedFieldState(display: "70%")
            r.edit("12")
            if discardFirst {
                r.discardTyping(display: "50%")
                r.sync(display: "50%")
            } else {
                r.sync(display: "50%")
                XCTAssertEqual(r.text, "12", "an outside change alone keeps the typing")
                r.discardTyping(display: "50%")
            }
            XCTAssertEqual(r.text, "50%")
            XCTAssertEqual(r.commit(display: "50%", parse: parsePercent, format: showPercent), .none)
        }
    }

    /// Round 2 ui N2: the binding clamps a written value back to the old one, so the display never changes; the
    /// settle on the next turn shows the stored value. Typing in between is kept.
    func testTypedFieldSettlesToStoredValueAfterWrite() {
        var f = TypedFieldState(display: "800 nits")
        f.edit("1000")
        XCTAssertEqual(f.commit(display: "800 nits", parse: { Double($0) }, format: { "\(Int($0)) nits" }), .write(1000))
        XCTAssertEqual(f.text, "1000 nits")
        f.settle(display: "800 nits")
        XCTAssertEqual(f.text, "800 nits")
        XCTAssertFalse(f.isDirty)

        f.edit("900")
        f.settle(display: "800 nits")
        XCTAssertEqual(f.text, "900", "a settle never drops new typing")
    }

    /// Any sequence of syncs and edits: a commit writes only when the last thing before it was typing that changed the
    /// text, and the field is never dirty after a commit.
    func testSeededTypedFieldCommitsOnlyTypedText() {
        var g = SeededGenerator(seed: 0x7E_1D)
        let texts = ["10%", "20%", "30%", "40", "abc", "", "55%", "20%"]
        for _ in 0..<2000 {
            var f = TypedFieldState(display: "20%")
            var shown = "20%"
            var typedSinceSync = false
            for _ in 0..<Int(g.next() % 8) {
                let t = texts[Int(g.next() % UInt64(texts.count))]
                let roll = g.next() % 3
                if roll == 0 {
                    shown = t
                    f.sync(display: t)
                    if !f.isDirty { typedSinceSync = false }
                } else if roll == 1 && g.next() % 3 == 0 {
                    // The row's own slider, stepper or Reset.
                    shown = t
                    f.discardTyping(display: t)
                    typedSinceSync = false
                    XCTAssertEqual(f.text, t)
                } else {
                    f.edit(t)
                    typedSinceSync = f.isDirty
                }
            }
            let result = f.commit(display: shown, parse: parsePercent, format: showPercent)
            if !typedSinceSync { XCTAssertEqual(result, .none) }
            if case .write = result { XCTAssertTrue(typedSinceSync) }
            XCTAssertFalse(f.isDirty)
        }
    }

    // MARK: Fuzz

    /// format → parse gives the value back within half the shown resolution, for both separators.
    func testSeededFormatParseRoundTrip() {
        var g = SeededGenerator(seed: 0x51_1D_E5)
        let formats: [ValueFormat] = [.percent(of: 1), .percent(of: 100), .seconds, .minutes, .hertz, .points, .nits,
                                      .kelvin, .plain(digits: 0), .plain(digits: 2)]
        for _ in 0..<4000 {
            let format = formats[Int(g.next() % UInt64(formats.count))]
            let value = Double(g.next() % 2_000_001) / 1000 - 1000
            let separator = g.next() % 2 == 0 ? "." : ","
            let text = SliderMath.format(value, format, decimalSeparator: separator)
            guard let back = SliderMath.parse(text, format, decimalSeparator: separator) else {
                XCTFail("\(text) didn't parse")
                continue
            }
            let tolerance = SliderMath.effectiveStep(nil, format: format) / 2 + 1e-9 * max(1, abs(value))
            XCTAssertLessThanOrEqual(abs(back - value), tolerance, "\(value) → \(text) → \(back)")
        }
    }

    /// Random text never traps and never yields a non-finite value.
    func testSeededParseNeverTraps() {
        var g = SeededGenerator(seed: 0xF00D)
        let alphabet = Array("0123456789.,-+ %smhzkpt×x\u{2212}\u{00A0}e")
        let formats: [ValueFormat] = [.percent(of: 1), .seconds, .minutes, .hertz, .kelvin, .plain(digits: 1)]
        for _ in 0..<4000 {
            let length = Int(g.next() % 21)
            var text = ""
            for _ in 0..<length { text.append(alphabet[Int(g.next() % UInt64(alphabet.count))]) }
            for format in formats {
                if let v = SliderMath.parse(text, format, decimalSeparator: g.next() % 2 == 0 ? "." : ",") {
                    XCTAssertTrue(v.isFinite, text)
                }
            }
            if let i = SliderLabels.parse(text, ["1280 × 800", "1512 × 982"]) { XCTAssertTrue(i == 0 || i == 1, text) }
        }
    }

    /// clampSnap always lands inside the range and is idempotent.
    func testSeededClampSnapStaysInRange() {
        var g = SeededGenerator(seed: 0xC1A3)
        let steps: [Double?] = [nil, 1, 5, 0.1, 0.05, 10, 0.25]
        for _ in 0..<4000 {
            let lo = Double(g.next() % 1000) / 10 - 50
            let hi = lo + Double(g.next() % 1000) / 10
            let step = steps[Int(g.next() % UInt64(steps.count))]
            let value = Double(Int64(bitPattern: g.next() % 4001) - 2000) / 10
            let v = SliderMath.clampSnap(value, range: lo...hi, step: step)
            XCTAssertTrue(v >= lo && v <= hi, "\(value) in \(lo)...\(hi) step \(String(describing: step)) → \(v)")
            XCTAssertEqual(SliderMath.clampSnap(v, range: lo...hi, step: step), v, accuracy: 1e-9)
        }
    }
}
