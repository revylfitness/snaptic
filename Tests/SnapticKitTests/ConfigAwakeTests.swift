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
