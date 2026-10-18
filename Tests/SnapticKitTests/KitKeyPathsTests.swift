import XCTest
@testable import SnapticKit

final class KitKeyPathsTests: XCTestCase {
    private enum Kind: Equatable { case plain, duration(seconds: Int), until(hour: Int, minute: Int) }
    private enum Style: String { case a, b }
    private struct Inner: Equatable { var level = 1; var name = "x" }
    private struct Sample {
        var flag = true
        var style = Style.a
        var kind = Kind.duration(seconds: 60)
        var inner = Inner()
        var optional: Inner? = Inner()
        var missing: Inner? = nil
        var list = [Inner()]
        var empty: [Inner] = []
        var map = ["k": Inner()]
        var set: Set<Int> = [3]
        var lossy = LossyArray([Inner2(id: 1)])
        var lossyMap = LossyMap<DisplayActionID, Inner2>([DisplayActionID(rawValue: "a.b"): Inner2(id: 2)])
    }
    private struct Inner2: Codable, Equatable { var id: Int }

    func testWalkerRules() {
        let paths = KitKeyPaths.paths(Sample())
        let expected: Set<String> = [
            "flag", "style", "kind", "kind.duration", "kind.duration.seconds",
            "inner", "inner.level", "inner.name",
            "optional", "optional.level", "optional.name", "missing",
            "list", "list.*.level", "list.*.name", "empty",
            "map", "map.*.level", "map.*.name", "set",
            "lossy", "lossy.*.id", "lossyMap", "lossyMap.*.id",
        ]
        XCTAssertEqual(paths, expected)
        XCTAssertFalse(paths.contains { $0.contains("unknown") }, "LossyMap's private unknown map is skipped")
    }

    func testEnumPayloadWithSeveralLabels() {
        var s = Sample()
        s.kind = .until(hour: 9, minute: 30)
        let paths = KitKeyPaths.paths(s)
        XCTAssertTrue(paths.isSuperset(of: ["kind.until", "kind.until.hour", "kind.until.minute"]))
        s.kind = .plain
        XCTAssertFalse(KitKeyPaths.paths(s).contains { $0.hasPrefix("kind.") }, "no payload, no children")
    }

    func testLeavesAndCoverage() {
        let leaves = KitKeyPaths.leaves(["a", "a.b", "a.b.c", "d", "e.*.f"])
        XCTAssertEqual(leaves, ["a.b.c", "d", "e.*.f"])
        XCTAssertTrue(KitKeyPaths.isCovered("a.b.c", by: ["a"]))
        XCTAssertTrue(KitKeyPaths.isCovered("a.b.c", by: ["a.b.c"]))
        XCTAssertFalse(KitKeyPaths.isCovered("a.b.c", by: ["a.b.x", "b"]))
        XCTAssertTrue(KitKeyPaths.isCovered("empty", by: ["empty.*.name"]), "an empty list is covered by its elements")
        XCTAssertFalse(KitKeyPaths.isCovered("ab", by: ["a"]), "segments, not string prefixes")
    }

    func testCoverageProblems() {
        let walked = KitKeyPaths.paths(Sample())
        let legacy: [String: [LegacyControlID]] = [
            "flag": [LegacyControlID(rawValue: "l.x.flag")],
            "list.*.level": [LegacyControlID(rawValue: "l.x.level")],
            "gone": [LegacyControlID(rawValue: "l.x.gone")],
            "removedKey": [LegacyControlID(rawValue: "l.x.removed")],
        ]
        let declared: Set<String> = ["style", "kind", "inner", "optional", "missing", "list.*.name", "empty", "map",
                                     "set", "lossy", "lossyMap"]
        let problems = KitKeyPaths.coverageProblems(walked: walked, legacy: legacy, declared: declared, internalKeys: [],
                                                    removed: [LegacyControlID(rawValue: "l.x.removed")])
        XCTAssertEqual(problems, ["legacy key gone no longer exists and isn't removed"])

        var fewer = declared
        fewer.remove("set")
        let missing = KitKeyPaths.coverageProblems(walked: walked, legacy: legacy, declared: fewer, internalKeys: ["gone"],
                                                   removed: [LegacyControlID(rawValue: "l.x.gone"),
                                                             LegacyControlID(rawValue: "l.x.removed")])
        XCTAssertEqual(missing, ["key set has no control (declare it in a Switcher table's keys)"])
    }

    func testSwitcherLegacyPathsUseTheWalkerForm() {
        // ControlLegacy's keys are what this walker produces for the 0.2 Config: arrays are `*`, names are Swift's.
        for path in ControlLegacy.switcherKeyPaths.keys {
            XCTAssertFalse(path.contains(".."), path)
            XCTAssertFalse(path.hasPrefix(".") || path.hasSuffix("."), path)
            XCTAssertTrue(path.split(separator: ".").allSatisfy { $0 == "*" || $0.allSatisfy { $0.isLetter || $0.isNumber } },
                          path)
        }
        XCTAssertEqual(ControlLegacy.switcherKeyPaths["disabledFeatures"]?.count, 14)
    }
}
