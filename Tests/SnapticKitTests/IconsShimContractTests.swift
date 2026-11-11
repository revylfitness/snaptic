import XCTest
@testable import SnapticKit

/// 0.4 B1: the Native shim's encoding table, state and self-test verdict (§4.2.2, H8, H12).
final class IconsShimContractTests: XCTestCase {
    private typealias C = IconsShimContract

    /// What S0-1 read on 27.2 (26B123).
    private let recorded: [String: String] = [
        "MBAssessmentModeConfiguration initWithAllowedSystemItems:allowedBundleIdentifiers:": "@32@0:8@16@24",
        "MBAssessmentModeConfiguration initWithUnrestrictedMenuBarItems": "@16@0:8",
        "MBAssessmentModeAssertion init": "@16@0:8",
        "MBAssessmentModeAssertion activateWithConfiguration:completionHandler:": "v32@0:8@16@?24",
        "MBAssessmentModeAssertion invalidate": "v16@0:8",
    ]

    private func actual(_ table: [String: String]) -> (String, String) -> String? {
        { table[$0 + " " + $1] }
    }

    func testTableMatchesWhatS0Recorded() {
        XCTAssertEqual(C.requirements.count, 5)
        XCTAssertEqual(Set(C.requirements.map(\.name)), Set(recorded.keys))
        XCTAssertEqual(Set(C.requirements.map(\.className)), [C.configurationClass, C.assertionClass])
        XCTAssertEqual(C.mismatches(actual: actual(recorded)), [])
    }

    func testAnyMissingOrChangedSelectorIsAMismatch() {
        for r in C.requirements {
            var missing = recorded
            missing[r.name] = nil
            XCTAssertEqual(C.mismatches(actual: actual(missing)), [r], r.name)
            var changed = recorded
            changed[r.name] = "v24@0:8q16"
            XCTAssertEqual(C.mismatches(actual: actual(changed)), [r], r.name)
        }
        XCTAssertEqual(C.mismatches { _, _ in nil }, C.requirements)
        // Offsets don't matter; types do (KitEncoding).
        var shifted = recorded
        shifted["MBAssessmentModeAssertion invalidate"] = "v8@0:4"
        XCTAssertEqual(C.mismatches(actual: actual(shifted)), [])
    }

    func testState() {
        let one = [C.requirements[0]]
        XCTAssertEqual(C.state(present: true, poisoned: false, mismatches: []), .available)
        XCTAssertEqual(C.state(present: true, poisoned: false, mismatches: one), .unavailable)
        XCTAssertEqual(C.state(present: false, poisoned: false, mismatches: []), .unavailable)
        XCTAssertEqual(C.state(present: false, poisoned: false, mismatches: C.requirements), .unavailable)
        for present in [true, false] {
            for m in [[], one] { XCTAssertEqual(C.state(present: present, poisoned: true, mismatches: m), .poisoned) }
        }
    }

    func testLaunchLine() {
        XCTAssertEqual(C.launchLine(.available), "selftest-launch: icons shim available")
        XCTAssertEqual(C.launchLine(.unavailable), "selftest-launch: icons shim unavailable")
        XCTAssertEqual(C.launchLine(.poisoned), "selftest-launch: icons shim poisoned")
    }

    /// H8: fails on poisoned, on a mismatch while present, and against an expectation (CI: unavailable).
    func testSelfTestVerdict() {
        XCTAssertEqual(C.selfTestProblems(state: .unavailable, present: false, mismatches: C.requirements, expect: nil), [])
        XCTAssertEqual(C.selfTestProblems(state: .unavailable, present: false, mismatches: C.requirements,
                                          expect: "unavailable"), [])
        XCTAssertEqual(C.selfTestProblems(state: .available, present: true, mismatches: [], expect: "available"), [])
        XCTAssertEqual(C.selfTestProblems(state: .available, present: true, mismatches: [], expect: nil), [])
        XCTAssertEqual(C.selfTestProblems(state: .available, present: true, mismatches: [], expect: "unavailable"),
                       ["expected the icons shim unavailable, found available"])
        XCTAssertEqual(C.selfTestProblems(state: .poisoned, present: true, mismatches: [], expect: nil),
                       ["the icons shim is poisoned"])
        let changed = C.selfTestProblems(state: .unavailable, present: true, mismatches: [C.requirements[3]], expect: nil)
        XCTAssertEqual(changed, ["icons shim encodings changed: MBAssessmentModeAssertion activateWithConfiguration:completionHandler:"])
        for bad in ["", "poisoned", "Available", "yes"] {
            XCTAssertEqual(C.selfTestProblems(state: .unavailable, present: false, mismatches: [], expect: bad),
                           ["\(C.expectVariable) must be available or unavailable"], bad)
        }
    }

    func testPoisonVerdict() {
        XCTAssertEqual(C.poisonProblems(poisoned: true, available: false), [])
        XCTAssertEqual(C.poisonProblems(poisoned: false, available: false).count, 1)
        XCTAssertEqual(C.poisonProblems(poisoned: true, available: true).count, 1)
        XCTAssertEqual(C.poisonProblems(poisoned: false, available: true).count, 2)
    }

    /// H12: the state and a y/n per encoding; names of classes and selectors only, never a bundle id.
    func testDiagnosticsRows() {
        let rows = C.diagnosticsRows(state: .available, mismatches: [C.requirements[1]])
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].0, "Icons shim")
        XCTAssertEqual(rows[0].1, "available")
        XCTAssertEqual(rows.dropFirst().map(\.1), ["y", "n", "y", "y", "y"])
        XCTAssertEqual(rows.dropFirst().map(\.0), C.requirements.map(\.name))
    }
}
