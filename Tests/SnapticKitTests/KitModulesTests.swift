import XCTest
@testable import SnapticKit

final class KitModulesTests: XCTestCase {
    /// Review6 ux R3-3: names inside sentences and joined lists (design-spec §4.1).
    func testSentenceTextInSentence() {
        XCTAssertEqual(SentenceText.inSentence("Virtual displays"), "virtual displays")
        XCTAssertEqual(SentenceText.inSentence("Keyboard shortcuts"), "keyboard shortcuts")
        XCTAssertEqual(SentenceText.inSentence("Picture in Picture filters"), "Picture in Picture filters")
        XCTAssertEqual(SentenceText.inSentence("Night Shift controls"), "Night Shift controls")
        XCTAssertEqual(SentenceText.inSentence("High Dynamic Range switch"), "High Dynamic Range switch")
        XCTAssertEqual(SentenceText.inSentence("HDR virtual modes"), "HDR virtual modes")
        XCTAssertEqual(SentenceText.inSentence("HiDPI sizes"), "HiDPI sizes")
        XCTAssertEqual(SentenceText.inSentence("USB-C input"), "USB-C input")
        XCTAssertEqual(SentenceText.inSentence("Apple native brightness"), "Apple native brightness")
        XCTAssertEqual(SentenceText.inSentence("Machine names"), "machine names", "a proper name is a whole word")
        XCTAssertEqual(SentenceText.inSentence("macOS updates"), "macOS updates")
        XCTAssertEqual(SentenceText.inSentence(""), "")
    }

    func testSentenceTextListUsesTheSerialComma() {
        XCTAssertEqual(SentenceText.list([]), "")
        XCTAssertEqual(SentenceText.list(["sharper text"]), "sharper text")
        XCTAssertEqual(SentenceText.list(["sharper text", "HDR virtual modes"]), "sharper text and HDR virtual modes")
        XCTAssertEqual(SentenceText.list(["a", "b", "c"]), "a, b, and c")
        XCTAssertEqual(SentenceText.list(["a", "b", "c", "d"]), "a, b, c, and d")
        // Seeded: every list of n ≥ 3 has n − 1 commas and one ", and " before the last item.
        var rng = SeededGenerator(seed: 20261018)
        for _ in 0..<500 {
            let n = Int(rng.next() % 9)
            let items = (0..<n).map { "item\($0)" }
            let text = SentenceText.list(items)
            XCTAssertEqual(text.filter { $0 == "," }.count, n >= 3 ? n - 1 : 0, text)
            if n >= 2 { XCTAssertTrue(text.hasSuffix((n >= 3 ? ", and " : " and ") + items[n - 1]), text) }
            XCTAssertEqual(text.components(separatedBy: " and ").count, n >= 2 ? 2 : 1, text)
        }
    }

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

    func testKillSwitchesReadOnlyTrueForKnownIDs() {
        XCTAssertEqual(KillSwitches.key(prefix: "Modules", id: "awake"), "Modules.disable.awake")
        let domain: [String: Any] = ["Modules.disable.awake": true, "Modules.disable.displays": false,
                                     "Modules.disable.windowSwitcher": "1", "Modules.disable.teleport": true,
                                     "Displays.disable.awake": true, "Awake.disable.history": true]
        XCTAssertEqual(KillSwitches.read(domain, prefix: "Modules", as: ModuleID.self), [.awake])
        let awake: Set<AwakeFeature> = KillSwitches.read(domain, prefix: "Awake")
        XCTAssertEqual(awake, [.history])
        XCTAssertEqual(KillSwitches.read(nil, prefix: "Modules", as: ModuleID.self), [])
        XCTAssertEqual(KillSwitches.read([:], prefix: "Displays", as: DisplayFeature.self), [])
    }
}
