import XCTest
@testable import SnapticKit

final class KitModulesTests: XCTestCase {
    func testModuleStartOrder() {
        XCTAssertEqual(ModuleID.allCases, [.windowSwitcher, .displays, .awake])
        XCTAssertEqual(ModuleID.awake.rawValue, "awake")
    }

    func testMenuPresenceAllowedPerModule() {
        XCTAssertEqual(MenuPresence.allowed(for: .displays), [.ownIcon, .ownIconWhenActive, .inSnapticMenu, .hidden])
        XCTAssertEqual(MenuPresence.allowed(for: .awake), MenuPresence.allCases)
        XCTAssertFalse(MenuPresence.allowed(for: .windowSwitcher).contains(.ownIconWhenActive))
        XCTAssertEqual(MenuPresence.allCases.map(\.rawValue), ["ownIcon", "ownIconWhenActive", "inSnapticMenu", "hidden"])
    }

    func testMenuPresenceLegacyMappingRoundTrips() {
        XCTAssertEqual(MenuPresence.ownIcon.legacyPlacement, .ownIcon)
        XCTAssertEqual(MenuPresence.ownIconWhenActive.legacyPlacement, .ownIcon)
        XCTAssertEqual(MenuPresence.inSnapticMenu.legacyPlacement, .shared)
        XCTAssertEqual(MenuPresence.hidden.legacyPlacement, .hidden)
        XCTAssertEqual(MenuPresence(legacy: .shared, hideWithoutExternalDisplay: false), .inSnapticMenu)
        XCTAssertEqual(MenuPresence(legacy: .shared, hideWithoutExternalDisplay: true), .inSnapticMenu)
        XCTAssertEqual(MenuPresence(legacy: .hidden, hideWithoutExternalDisplay: true), .hidden)
        XCTAssertEqual(MenuPresence(legacy: .ownIcon, hideWithoutExternalDisplay: false), .ownIcon)
        XCTAssertEqual(MenuPresence(legacy: .ownIcon, hideWithoutExternalDisplay: true), .ownIconWhenActive)
        for p in MenuPresence.allCases {
            XCTAssertEqual(MenuPresence(legacy: p.legacyPlacement, hideWithoutExternalDisplay: p == .ownIconWhenActive), p)
        }
    }

    func testNewModuleCardRawValues() throws {
        XCTAssertEqual(NewModuleCard.awakeMigrated.rawValue, "awake.migrated")
        let data = try JSONEncoder().encode([NewModuleCard.displays, .awakeMigrated])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["displays","awake.migrated"]"#)
    }

    func testAwakeEventsAreNeverExported() {
        let awake: EventCategory = .awake
        XCTAssertFalse(awake.isExportedInDiagnostics)
        XCTAssertTrue(EventCategory.modules.isExportedInDiagnostics)
        XCTAssertTrue(EventCategory.ddc.isExportedInDiagnostics)
    }

    func testMigrationConstants() {
        XCTAssertEqual(DisplayActionID.fShowPanel.rawValue, "f.showPanel")
        XCTAssertEqual(DisplayActionID.fIdentify.rawValue, "f.identify")
        XCTAssertEqual(DisplayMenuItemID.cDDCPower.rawValue, "c.ddc.power")
        XCTAssertEqual(AwakeCriterionKind.allCases.count, 12)
    }

    // MARK: NameHash / StableID.derived (fixed vectors)

    private func hex(_ h: (hi: UInt64, lo: UInt64)) -> String {
        String(format: "%016llx%016llx", h.hi, h.lo)
    }

    func testFNV1a128Vectors() {
        XCTAssertEqual(hex(NameHash.fnv1a128([])), "6c62272e07bb014262b821756295c58d")
        XCTAssertEqual(hex(NameHash.fnv1a128(Array("a".utf8))), "d228cb696f1a8caf78912b704e4a8964")
        XCTAssertEqual(hex(NameHash.fnv1a128(Array("foobar".utf8))), "343e1662793c64bf6f0d3597ba446f18")
    }

    func testDerivedIDVectors() {
        XCTAssertEqual(StableID.derived(namespace: "awake.preset.default", name: "1h").rawValue,
                       "66C0F97A-B845-86A0-852B-C4AC9DFCDFFF")
        XCTAssertEqual(StableID.derived(namespace: "awake.preset.default", name: "indefinite").rawValue,
                       "5F34459B-7E97-8F11-BCCF-E804A363653D")
        XCTAssertEqual(StableID.derived(namespace: "awake.m1", name: "0:aaaa").rawValue,
                       "38BABFC8-DEDD-8750-9347-FA3A4EA94E9A")
        XCTAssertEqual(StableID.derived(namespace: "", name: "").rawValue, "D228CB69-101A-8CAF-B891-2B704E4A147F")
    }

    func testDerivedIDsAreValidVersion8Variant10AndDeterministic() {
        var seen = Set<String>()
        for name in ["indefinite", "30m", "1h", "2h", "5h", "idle", "0:a,b", "1:a,b", "", "é"] {
            let id = StableID.derived(namespace: "awake.preset.default", name: name)
            XCTAssertEqual(id, StableID.derived(namespace: "awake.preset.default", name: name))
            XCTAssertEqual(StableID(rawValue: id.rawValue), id)
            let chars = Array(id.rawValue)
            XCTAssertEqual(chars.count, 36)
            XCTAssertEqual(chars[14], "8")
            XCTAssertTrue("89AB".contains(chars[19]))
            XCTAssertTrue(seen.insert(id.rawValue).inserted)
        }
        // The separator keeps (namespace, name) pairs apart.
        XCTAssertNotEqual(StableID.derived(namespace: "ab", name: "c"), StableID.derived(namespace: "a", name: "bc"))
    }
}
