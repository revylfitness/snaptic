import XCTest
@testable import SnapticKit

final class AwakeMigrationTests: XCTestCase {
    private let combo = HotkeyCombo(keyCode: 2, carbonModifiers: 0x0900)

    private func key(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: 32 - hex.count) + hex
    }
    private func fp(_ n: Int) -> String { String(repeating: "a", count: 31) + String(n % 10) }

    /// A raw 0.2 Displays JSON with `flagged` displays that prevent sleep (with fingerprints unless listed in
    /// `bare`), plus one display that doesn't.
    private func raw(feature: Bool? = true, flagged: [Int], bare: Set<Int> = [], customNames: [Int: String] = [:],
                     shortcut: Bool = false) -> Data {
        var displays: [String] = []
        for n in flagged {
            let fingerprint = bare.contains(n) ? "{}" : #"{"t2":"\#(fp(n))","t3":"\#(fp(n + 1))"}"#
            let custom = customNames[n].map { #","customName":"\#($0)""# } ?? ""
            displays.append(#""\#(key(n))":{"management":{"preventSleep":true},"identity":{"fingerprint":\#(fingerprint),"lastKnownName":"Display \#(n)"\#(custom)}}"#)
        }
        displays.append(#""\#(key(999))":{"management":{"preventSleep":false},"identity":{"fingerprint":{"t2":"\#(fp(9))"}}}"#)
        let features = feature.map { #""features":{"sleepPrevention":\#($0),"brightness":true},"# } ?? ""
        let keys = shortcut ? #","keys":{"shortcuts":{"d.sleepPreventionToggle":{"keyCode":2,"carbonModifiers":2304},"c.brightnessUp":{"keyCode":1,"carbonModifiers":0}}}"# : ""
        return Data(("{" + features + #""perDisplay":{"# + displays.joined(separator: ",") + "}" + keys + "}").utf8)
    }

    private func migrate(_ data: Data?, modules: Set<ModuleID> = [.windowSwitcher, .displays],
                         shortcuts: LossyMap<AwakeActionID, HotkeyCombo> = LossyMap()) -> AwakeMigrationResult {
        AwakeMigration.fromDisplays(rawJSON: data, modulesEnabled: modules, awakeShortcuts: shortcuts)
    }

    func testNothingToMigrate() {
        XCTAssertEqual(migrate(nil), .nothing)
        XCTAssertEqual(migrate(Data()), .nothing)
        XCTAssertEqual(migrate(Data("{}".utf8)), .nothing)
        XCTAssertEqual(migrate(Data("not json".utf8)), .nothing)
        XCTAssertEqual(migrate(Data("[1,2]".utf8)), .nothing)
        XCTAssertEqual(migrate(Data(#"{"perDisplay":7,"features":"x"}"#.utf8)), .nothing)
        XCTAssertEqual(migrate(raw(flagged: [])), .nothing)
    }

    func testOneDisplayEffective() throws {
        let r = migrate(raw(flagged: [1], customNames: [1: "DELL U2720Q"]))
        XCTAssertTrue(r.enableModule)
        XCTAssertEqual(r.migratedDisplayNames, ["DELL U2720Q"])
        let rule = try XCTUnwrap(r.triggers.first)
        XCTAssertEqual(r.triggers.count, 1)
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.match, .any)
        XCTAssertEqual(rule.options, AwakeSessionOptions(display: .keepOn))
        XCTAssertEqual(rule.name, "While a display is connected")
        XCTAssertEqual(rule.criteria, [AwakeCriterionEntry(.display(.specific(record: FingerprintRecord(t2: fp(1), t3: fp(2)),
                                                                              name: "DELL U2720Q")))])
        XCTAssertEqual(rule.id, StableID.derived(namespace: "awake.m1", name: "0:" + key(1)))
        XCTAssertEqual(rule, rule.sanitized(), "already clean")
        XCTAssertNil(r.pauseRulesShortcut)
        XCTAssertFalse(r.droppedShortcut)
    }

    func testFeatureOffWithFlagsGivesDisabledRules() {
        let r = migrate(raw(feature: false, flagged: [1, 2]))
        XCTAssertFalse(r.enableModule)
        XCTAssertEqual(r.triggers.count, 1)
        XCTAssertFalse(r.triggers[0].enabled)
        XCTAssertEqual(r.triggers[0].criteria.count, 2)
        // A missing feature key is the opt-in default: off.
        XCTAssertFalse(migrate(raw(feature: nil, flagged: [1])).enableModule)
    }

    func testDisplaysModuleOffIsNotEffective() {
        let r = migrate(raw(flagged: [1]), modules: [.windowSwitcher])
        XCTAssertFalse(r.enableModule)
        XCTAssertEqual(r.triggers.count, 1)
        XCTAssertFalse(r.triggers[0].enabled)
    }

    func testThreeAndNineDisplaysSplitAtEight() {
        let three = migrate(raw(flagged: [3, 1, 2]))
        XCTAssertEqual(three.triggers.count, 1)
        XCTAssertEqual(three.triggers[0].criteria.count, 3)
        XCTAssertEqual(three.migratedDisplayNames, ["Display 1", "Display 2", "Display 3"], "sorted by display key")
        let nine = migrate(raw(flagged: Array(1...9)))
        XCTAssertEqual(nine.triggers.map(\.criteria.count), [8, 1])
        XCTAssertEqual(nine.triggers.map(\.name), ["While a display is connected", "While a display is connected (2)"])
        XCTAssertEqual(nine.migratedDisplayNames.count, 8)
        XCTAssertEqual(nine.triggers[1].id, StableID.derived(namespace: "awake.m1", name: "1:" + key(9)))
        XCTAssertEqual(nine.triggers[0].id,
                       StableID.derived(namespace: "awake.m1", name: "0:" + (1...8).map(key).joined(separator: ",")))
        XCTAssertTrue(nine.triggers.allSatisfy(\.enabled))
    }

    func testMissingFingerprintsAreSkipped() {
        let r = migrate(raw(flagged: [1, 2], bare: [1]))
        XCTAssertEqual(r.triggers.count, 1)
        XCTAssertEqual(r.triggers[0].criteria.count, 1)
        XCTAssertEqual(r.migratedDisplayNames, ["Display 2"])
        XCTAssertEqual(r.triggers[0].id, StableID.derived(namespace: "awake.m1", name: "0:" + key(2)))
        // Only displays without fingerprints: nothing to create.
        let none = migrate(raw(flagged: [1], bare: [1]))
        XCTAssertEqual(none, .nothing)
    }

    func testInvalidDisplayKeysAndNamesAreCleaned() {
        let json = #"{"features":{"sleepPrevention":true},"perDisplay":{"NOT-A-KEY":{"management":{"preventSleep":true},"identity":{"fingerprint":{"t2":"\#(fp(1))"}}},"\#(key(5))":{"management":{"preventSleep":true},"identity":{"fingerprint":{"t2":"\#(fp(5))"},"customName":"  \u0007\#(String(repeating: "W", count: 90))"}}}}"#
        let r = migrate(Data(json.utf8))
        XCTAssertEqual(r.triggers.count, 1)
        XCTAssertEqual(r.triggers[0].criteria.count, 1)
        // Control characters dropped, cut to 64 scalars, then trimmed.
        XCTAssertEqual(r.migratedDisplayNames, [String(repeating: "W", count: 62)])
    }

    func testTwoRunsGiveEqualIDsAndOneSetOfRulesWhenWrittenOverEachOther() {
        let data = raw(flagged: [4, 7, 1])
        let first = migrate(data), second = migrate(data)
        XCTAssertEqual(first, second)
        // The host's writer replaces rules by id: applying the second run over the first gives one set.
        var config = AwakeTriggersConfig()
        for result in [first, second] {
            let ids = Set(result.triggers.map(\.id))
            config.triggers = config.triggers.filter { !ids.contains($0.id) } + result.triggers
        }
        XCTAssertEqual(config.triggers, first.triggers)
    }

    func testLedgerMarkerPreventsASecondRun() {
        // The host runs M1 only while `fromDisplays.v1` is absent and records it after; the Kit side is pure.
        var ledger = MigrationLedger()
        var runs = 0
        for _ in 0..<3 where !ledger.has(.fromDisplays) {
            if migrate(raw(flagged: [1])) != .nothing { ledger.record(.fromDisplays) }
            runs += 1
        }
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(ledger.has(.fromDisplays))
    }

    // MARK: R5-12 hotkey move

    func testSleepPreventionHotkeyMovesToPauseRules() {
        let r = migrate(raw(flagged: [1], shortcut: true))
        XCTAssertEqual(r.pauseRulesShortcut, combo)
        XCTAssertFalse(r.droppedShortcut)
    }

    func testHotkeyIsDroppedWhenPauseRulesIsBoundOrNoRuleWasMade() {
        var bound = LossyMap<AwakeActionID, HotkeyCombo>()
        bound[.pauseAutomatic] = HotkeyCombo(keyCode: 9, carbonModifiers: 0)
        let taken = migrate(raw(flagged: [1], shortcut: true), shortcuts: bound)
        XCTAssertNil(taken.pauseRulesShortcut)
        XCTAssertTrue(taken.droppedShortcut)
        let noRules = migrate(raw(flagged: [], shortcut: true))
        XCTAssertNil(noRules.pauseRulesShortcut)
        XCTAssertTrue(noRules.droppedShortcut)
        XCTAssertEqual(noRules.triggers, [])
        XCTAssertNotEqual(noRules, .nothing, "the notice still needs the host to act")
        // Another Awake binding doesn't block the move.
        var other = LossyMap<AwakeActionID, HotkeyCombo>()
        other[.toggle] = HotkeyCombo(keyCode: 3, carbonModifiers: 0)
        XCTAssertEqual(migrate(raw(flagged: [1], shortcut: true), shortcuts: other).pauseRulesShortcut, combo)
    }

    func testRealDisplaysConfigJSONMigrates() throws {
        // A config written by the 0.2 model itself, not a hand-made fixture.
        var displays = DisplaysConfig()
        displays.features[.sleepPrevention] = true
        let k = try XCTUnwrap(DisplayKey(rawValue: key(42)))
        var per = PerDisplayConfig()
        per.management.preventSleep = true
        per.identity.fingerprint = FingerprintRecord(t2: fp(4))
        per.identity.customName = "Studio Display"
        displays.perDisplay[k] = per
        displays.keys.shortcuts[DisplayActionID(rawValue: "d.sleepPreventionToggle")] = combo
        let r = migrate(try JSONEncoder().encode(displays))
        XCTAssertTrue(r.enableModule)
        XCTAssertEqual(r.migratedDisplayNames, ["Studio Display"])
        XCTAssertEqual(r.pauseRulesShortcut, combo)
    }

    func testFuzzNeverTraps() {
        var rng = SeededGenerator(seed: 0x3131)
        let base = Array(raw(flagged: [1, 2, 3], shortcut: true))
        for _ in 0..<3_000 {
            var bytes = base
            for _ in 0..<(1 + Int(rng.next() % 6)) {
                let i = Int(rng.next() % UInt64(bytes.count))
                bytes[i] = UInt8(truncatingIfNeeded: rng.next())
            }
            let r = migrate(Data(bytes))
            XCTAssertLessThanOrEqual(r.migratedDisplayNames.count, 8)
            XCTAssertTrue(r.triggers.allSatisfy { $0.criteria.count <= 8 && !$0.criteria.isEmpty })
        }
    }
}
