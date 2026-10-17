import XCTest
@testable import SnapticKit

final class RiskClassifierTests: XCTestCase {
    typealias L = BLayout

    private func desc(_ m: ModeRef, native: Bool = false, def: Bool = false, usable: Bool = true) -> DisplayModeDescriptor {
        DisplayModeDescriptor(ref: m, isNative: native, isDefault: def, isUsableForDesktop: usable, ioFlags: 0, bitDepth: 8)
    }

    func testKnownGoodSet() {
        let native = L.mode(2560, 1440), def = L.mode(1280, 720, hidpi: true), other = L.mode(1920, 1080)
        let hz120 = L.mode(1600, 900, hz: 120)
        let modes = [desc(native, native: true), desc(def, def: true), desc(other), desc(hz120)]
        let kept = L.mode(1024, 768)
        let external = RiskClassifier.knownGood(modes: modes, current: other, isBuiltin: false, kept: [kept])
        XCTAssertEqual(external, [native, def, kept, other])
        let builtin = RiskClassifier.knownGood(modes: modes, current: other, isBuiltin: true, kept: [])
        XCTAssertTrue(builtin.contains(other) && builtin.contains(native))
        XCTAssertFalse(builtin.contains(hz120), "only the current refresh rate on built-in panels")
    }

    func testClassification() {
        let s = L.snapshot([L.display(1, .builtin), L.display(2, .airplay)])
        let good = L.mode(1280, 720), fresh = L.mode(1600, 900), hidden = L.mode(3000, 2000)
        let facts = ModeFacts(knownGood: [good], publicModes: [good, fresh])
        func risk(_ c: DisplayChange, _ setting: ConfirmResolutionChanges = .newModesOnly) -> RiskLevel {
            RiskClassifier.classify(c, current: s, facts: facts, setting: setting)
        }
        XCTAssertEqual(risk(.origin(1, x: 5, y: 5)), .low)
        XCTAssertEqual(risk(.main(1)), .low)
        XCTAssertEqual(risk(.main(2)), .trial, "main onto a weakly visible display needs a trial")
        XCTAssertEqual(risk(.mode(1, good)), .low)
        XCTAssertEqual(risk(.mode(1, fresh)), .trial)
        XCTAssertEqual(risk(.mode(1, good), .always), .trial)
        XCTAssertEqual(risk(.mode(1, fresh), .neverForPublic), .low)
        XCTAssertEqual(risk(.mode(1, hidden), .neverForPublic), .trial, "CGS modes always confirm")
        XCTAssertEqual(risk(.mode(1, L.mode(1920, 1080)), .always), .low, "unchanged is low")
        XCTAssertEqual(risk(.mirror(1, of: 2)), .trial)
        XCTAssertEqual(risk(.mirror(1, of: nil)), .low)
        XCTAssertEqual(risk(.enabled(1, false)), .trial)
        XCTAssertEqual(risk(.rotation(1, 90)), .trial)
        XCTAssertEqual(risk(.rotation(1, 360)), .low)
        XCTAssertEqual(risk(.hdr(1, true)), .trial)
        XCTAssertEqual(risk(.underscan(1, 0)), .low)
        XCTAssertEqual(RiskClassifier.classify([.origin(1, x: 0, y: 0), .enabled(2, false)], current: s,
                                               facts: { _ in facts }, setting: .newModesOnly), .trial)
        XCTAssertEqual(RiskClassifier.classify([], current: s, facts: { _ in facts }, setting: .always), .low)
        XCTAssertTrue(RiskLevel.low < .restore && RiskLevel.restore < .trial)
    }
}
