import XCTest
@testable import SnapticKit

/// The lead's AwakeConfig shell and the R5-3 decoders the step-0 stubs declare. G and J test their sections.
final class ConfigAwakeTests: XCTestCase {
    private func decode(_ json: String) throws -> AwakeConfig {
        try JSONDecoder().decode(AwakeConfig.self, from: Data(json.utf8))
    }

    func testEmptyAndGarbageFallBackToDefaults() throws {
        XCTAssertEqual(try decode("{}"), AwakeConfig())
        XCTAssertEqual(try decode(#"{"sessions":3,"guards":[],"triggers":"x","drives":null,"indicator":{"glyph":"mug"}}"#),
                       AwakeConfig())
    }

    func testBadSectionFallsBackAlone() throws {
        let c = try decode(#"{"features":{"triggers":true,"future":true},"guards":7,"activity":{"stopAfterHours":3}}"#)
        XCTAssertEqual(c.features[.triggers], true)
        XCTAssertEqual(c.guards, AwakeGuardsConfig())
        XCTAssertEqual(c.activity.stopAfterHours, 3)
        let out = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertTrue(out.contains("future"))
    }

    func testRoundTrip() throws {
        var c = AwakeConfig()
        c.features[.history] = false
        c.guards.batteryFloor = 30
        c.indicator.glyph = .eye
        c.shortcuts[AwakeActionID(rawValue: "awake.toggle")] = HotkeyCombo(keyCode: 1, carbonModifiers: 0x0100)
        c.drives.volumes[VolumeUUIDKey(rawValue: "1b4e28ba-2fa1-11d2-883f-0016d3cca427")!] =
            DriveAliveVolume(name: "Backup", enabled: true)
        XCTAssertEqual(try JSONDecoder().decode(AwakeConfig.self, from: JSONEncoder().encode(c)), c)
    }

    func testRestoreExportImportStubsAreSafe() {
        var c = AwakeConfig()
        c.features[.pointerNudge] = true
        XCTAssertEqual(c.restoringDefaults(), AwakeConfig())
        XCTAssertEqual(c.exportable(includeTriggers: true), AwakeConfig())
        XCTAssertEqual(AwakeConfig().importable(current: c), c)
    }

    // MARK: Restore keeps rules running (review parity P1); import strips only the file's own (review security S-2)

    private static let routerHash = String(repeating: "ab", count: 32)

    /// A Mac with a "Connected to this network" rule, a nudge preset and nudge default options.
    private func ownMac() -> AwakeConfig {
        var c = AwakeConfig()
        c.features[.triggers] = true
        c.features[.activity] = true
        c.features[.pointerNudge] = true
        let rule = AwakeTrigger(id: StableID(), name: "Office Wi-Fi",
                                criteria: [AwakeCriterionEntry(.network(.router(hash: Self.routerHash, label: "Office"))),
                                           AwakeCriterionEntry(.network(.vpnConnected), negated: true)])
        c.triggers.triggers = [rule]
        c.sessions.presets.append(AwakePreset(id: StableID(), name: "Nudge", kind: .duration(seconds: 1_800),
                                              options: AwakeSessionOptions(activity: .nudge)))
        c.sessions.defaultOptions.activity = .nudge
        return c.sanitized()
    }

    private func ownBackup(_ c: AwakeConfig, includeTriggers: Bool) throws -> AwakeConfig {
        let section = try XCTUnwrap(KitBackup.awakeSectionData(c, includeTriggers: includeTriggers))
        return try XCTUnwrap(KitBackup.importAwake(current: c, imported: section))
    }

    func testRestoreDefaultsKeepsRulesRunning() {
        let c = ownMac()
        let restored = c.restoringDefaults()
        XCTAssertEqual(restored.features[.triggers], true)
        XCTAssertEqual(restored.triggers, c.triggers)
        XCTAssertNotEqual(restored.features[.pointerNudge], true)
        XCTAssertEqual(restored.sessions.presets, AwakeConfig().sanitized().sessions.presets)
        var off = c
        off.features[.triggers] = false
        XCTAssertEqual(off.restoringDefaults().features[.triggers], false, "rules the user turned off stay off")
    }

    func testImportingOwnBackupKeepsTheMacsRulesAndPresets() throws {
        let c = ownMac()
        XCTAssertEqual(c.triggers.triggers.first?.criteria.count, 2)
        for includeTriggers in [false, true] {
            let result = try ownBackup(c, includeTriggers: includeTriggers)
            XCTAssertEqual(result.triggers, c.triggers, "rules, includeTriggers \(includeTriggers)")
            XCTAssertEqual(result.sessions.presets, c.sessions.presets, "presets, includeTriggers \(includeTriggers)")
            XCTAssertEqual(result.sessions.defaultOptions, c.sessions.defaultOptions)
            XCTAssertEqual(result.features[.pointerNudge], true)
        }
    }

    func testImportStillStripsWhatTheFileBrings() {
        let current = ownMac()
        var file = current
        // A rule this Mac doesn't have, with a salted hash; the Mac's own rule changed by the file; a preset the
        // file turned into pointer movement; default options the file changed.
        var foreign = AwakeTrigger(id: StableID(), name: "Their Wi-Fi",
                                   criteria: [AwakeCriterionEntry(.network(.router(hash: Self.routerHash, label: "X"))),
                                              AwakeCriterionEntry(.network(.vpnConnected))])
        foreign.enabled = true
        file.triggers.triggers[0].name = "Renamed"
        file.triggers.triggers.append(foreign)
        let plain = file.sessions.presets[0].id
        file.sessions.presets[0].options = AwakeSessionOptions(activity: .nudge)
        file.sessions.defaultOptions = AwakeSessionOptions(display: .maySleep, activity: .nudge)
        let result = file.importable(current: current)
        XCTAssertEqual(result.triggers.triggers.count, 2)
        for t in result.triggers.triggers {
            XCTAssertFalse(t.enabled, t.name)
            XCTAssertEqual(t.criteria, [AwakeCriterionEntry(.network(.vpnConnected), negated: t.name == "Renamed")])
        }
        XCTAssertEqual(result.sessions.presets.first { $0.id == plain }?.options?.activity, .declare)
        XCTAssertEqual(result.sessions.defaultOptions.activity, .declare)
        XCTAssertEqual(result.sessions.defaultOptions.display, .maySleep)
        // The Mac's own nudge preset, untouched by the file, keeps its pointer movement.
        XCTAssertEqual(result.sessions.presets.last, current.sessions.presets.last)
    }

    func testRulesDecodeElementWiseAndDuplicateIDsKeepTheFirst() throws {
        let a = StableID().rawValue, b = StableID().rawValue
        let json = #"{"triggers":{"triggers":[{"id":"\#(a)","name":"one"},{"id":"nope"},{"id":"\#(b)"},{"id":"\#(a)","name":"dup"}]}}"#
        let c = try decode(json)
        XCTAssertEqual(c.triggers.triggers.map(\.id.rawValue), [a, b])
        XCTAssertEqual(c.triggers.triggers.first?.name, "one")
        XCTAssertEqual(try JSONDecoder().decode(AwakeConfig.self, from: JSONEncoder().encode(c)).triggers, c.triggers)
    }

    func testSnapshotKeepsTheRestWhenAPartIsBad() throws {
        let json = #"{"bootSession":"B","manual":{"id":"bad"},"holds":[{"id":"x"}],"pausedUntil":"soon","guardMemory":{"warnedSerious":true,"unreadableReads":"x"}}"#
        let s = try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.bootSession, "B")
        XCTAssertNil(s.manual)
        XCTAssertEqual(s.holds, [])
        XCTAssertNil(s.pausedUntil)
        XCTAssertTrue(s.guardMemory.warnedSerious)
        XCTAssertEqual(s.guardMemory.unreadableReads, 0)
    }

    func testHistoryDecodesElementWise() throws {
        let json = #"{"entries":[{"start":1,"end":2,"kind":"duration","source":"menu","endReason":"timeUp"},{"kind":"teleport"},{"start":3,"end":4,"kind":"idle","source":"rule","endReason":"commandLineOff"}]}"#
        let h = try JSONDecoder().decode(AwakeHistory.self, from: Data(json.utf8))
        XCTAssertEqual(h.entries.map(\.kind), [.duration, .idle])
        XCTAssertEqual(h.entries.last?.source, .rule)
    }
}
