import XCTest
@testable import SnapticKit

/// 0.4 K1: Hidden Icons' two stores (H10), the backup section (H7), and what a 0.4 file looks like to older types.
final class ConfigIconsTests: XCTestCase {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func object(_ data: Data?) -> [String: Any] {
        guard let data else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: IconsConfig

    func testDefaults() {
        let c = IconsConfig()
        XCTAssertTrue(c.autoCollapse)
        XCTAssertEqual(c.autoCollapseSeconds, 10)
        XCTAssertTrue(c.collapseAtLaunch)
        XCTAssertFalse(c.alwaysHidden)
        XCTAssertTrue(c.dividers)
        XCTAssertNil(c.shortcut)
        XCTAssertFalse(c.hover)
        XCTAssertEqual(c.newApps, .show)
        XCTAssertEqual(c.otherHiders, .pause)
        XCTAssertFalse(c.fullBarOnExpand)
        XCTAssertTrue(c.showDuringCapture)
        XCTAssertFalse(c.arranged)
        XCTAssertEqual(IconsConfig.key, "SnapticIconsV1")
        XCTAssertEqual(c.sanitized(), c)
    }

    func testRoundTripsEveryField() throws {
        let full = ConfigFixtures.fullIcons()
        XCTAssertEqual(try roundTrip(full), full)
        XCTAssertEqual(try roundTrip(IconsConfig()), IconsConfig())
    }

    func testEmptyAndPartialObjectsDecodeToDefaults() throws {
        XCTAssertEqual(try decode(IconsConfig.self, "{}"), IconsConfig())
        let c = try decode(IconsConfig.self, #"{"hover": true, "futureField": [1, 2]}"#)
        var expected = IconsConfig()
        expected.hover = true
        XCTAssertEqual(c, expected)
    }

    func testBadFieldsFallBackOneByOne() throws {
        let c = try decode(IconsConfig.self, """
            {"autoCollapse": "yes", "autoCollapseSeconds": 60, "newApps": "sometimes", "otherHiders": "runBoth",
             "shortcut": {"keyCode": "x"}, "dividers": false}
            """)
        XCTAssertTrue(c.autoCollapse)
        XCTAssertEqual(c.autoCollapseSeconds, 60)
        XCTAssertEqual(c.newApps, .show)
        XCTAssertEqual(c.otherHiders, .runBoth)
        XCTAssertNil(c.shortcut)
        XCTAssertFalse(c.dividers)
    }

    func testSanitizeClampsTheDelay() {
        var c = IconsConfig()
        for (raw, want) in [(0, 5), (-40, 5), (4, 5), (5, 5), (299, 299), (300, 300), (301, 300), (Int.max, 300)] {
            c.autoCollapseSeconds = raw
            XCTAssertEqual(c.sanitized().autoCollapseSeconds, want, "\(raw)")
        }
    }

    func testRestoreDefaultsKeepsArranged() {
        let full = ConfigFixtures.fullIcons()
        var expected = IconsConfig()
        expected.arranged = true
        XCTAssertEqual(full.restoringDefaults(), expected)
        XCTAssertEqual(IconsConfig().restoringDefaults(), IconsConfig())
    }

    func testAdvancedRestoreDefaultsResetsOnlyItsRows() {
        let full = ConfigFixtures.fullIcons()
        let r = full.restoringAdvancedDefaults()
        XCTAssertFalse(r.hover)
        XCTAssertEqual(r.newApps, .show)
        XCTAssertEqual(r.otherHiders, .pause)
        XCTAssertFalse(r.fullBarOnExpand)
        XCTAssertTrue(r.showDuringCapture)
        // The page's rows stay.
        XCTAssertEqual(r.autoCollapse, full.autoCollapse)
        XCTAssertEqual(r.autoCollapseSeconds, full.autoCollapseSeconds)
        XCTAssertEqual(r.collapseAtLaunch, full.collapseAtLaunch)
        XCTAssertEqual(r.alwaysHidden, full.alwaysHidden)
        XCTAssertEqual(r.dividers, full.dividers)
        XCTAssertEqual(r.shortcut, full.shortcut)
        XCTAssertEqual(r.arranged, full.arranged)
    }

    func testFieldNamesAvoidTheSensitiveFragments() {
        // KitBackup drops any key containing one of these at any depth; a setting named so would silently vanish.
        let names = Set(IconsConfig.exportedKeys + ["arranged", "layout", "knownBundles", "newShown", "choices",
                                                     "toasts", "readAt", "sections", "firstSeen", "lastSeen",
                                                     "missedReads", "section"])
        for name in names {
            for fragment in KitBackup.sensitiveKeyFragments {
                XCTAssertFalse(name.lowercased().contains(fragment.lowercased()), "\(name) contains \(fragment)")
            }
        }
    }

    // MARK: IconsAppsState

    func testAppsStateDefaultsAndKey() throws {
        let s = IconsAppsState()
        XCTAssertEqual(IconsAppsState.key, "SnapticIconsAppsV1")
        XCTAssertNil(s.layout)
        XCTAssertTrue(s.knownBundles.isEmpty && s.newShown.isEmpty && s.choices.isEmpty && s.toasts.isEmpty)
        XCTAssertEqual(try decode(IconsAppsState.self, "{}"), s)
        XCTAssertEqual(s.sanitized(), s)
    }

    func testAppsStateRoundTrips() throws {
        var s = IconsAppsState()
        s.layout = IconsLayoutCache(readAt: 1_800_000_000, sections: ["com.example.A": .hidden, "com.example.B": .shown])
        s.knownBundles["com.example.A"] = IconsKnownBundle(section: .alwaysHidden, firstSeen: 10, lastSeen: 20,
                                                          missedReads: 1)
        s.newShown["com.example.C"] = 30
        s.choices["com.example.D"] = .alwaysHide
        s.toasts["com.example.E"] = 20_800
        XCTAssertEqual(try roundTrip(s), s)
        XCTAssertEqual(s.sanitized(), s)
    }

    func testAppsStateDecodesEntryByEntry() throws {
        let s = try decode(IconsAppsState.self, """
            {"choices": {"com.example.ok": "alwaysShow", "com.example.bad": "sometimes", "com.example.n": 3},
             "newShown": {"com.example.x": 5, "com.example.y": "later"},
             "knownBundles": {"com.example.k": {"section": "nowhere", "firstSeen": 1, "lastSeen": 2}},
             "layout": {"readAt": "noon", "sections": {"com.example.l": "hidden", "com.example.m": "up"}},
             "toasts": [1, 2]}
            """)
        XCTAssertEqual(s.choices, ["com.example.ok": .alwaysShow])
        XCTAssertEqual(s.newShown, ["com.example.x": 5])
        XCTAssertEqual(s.knownBundles["com.example.k"], IconsKnownBundle(section: nil, firstSeen: 1, lastSeen: 2))
        XCTAssertEqual(s.layout, IconsLayoutCache(readAt: 0, sections: ["com.example.l": .hidden]))
        XCTAssertTrue(s.toasts.isEmpty)
    }

    func testSanitizeDropsInvalidBundlesAndBadTimes() {
        var s = IconsAppsState()
        s.choices = ["com.example.ok": .alwaysShow, "": .alwaysHide, "nodots": .alwaysHide, "com.ex ample.sp": .alwaysShow,
                     "com.example.é": .alwaysShow, String(repeating: "a.", count: 200): .alwaysHide]
        s.newShown = ["com.example.nan": .nan, "com.example.inf": .infinity, "com.example.neg": -4, "com.example.ok": 9]
        s.knownBundles = ["com.example.k": IconsKnownBundle(firstSeen: 50, lastSeen: 10, missedReads: 99),
                          "bad": IconsKnownBundle(firstSeen: 1, lastSeen: 2)]
        s.toasts = ["com.example.t": -3]
        s.layout = IconsLayoutCache(readAt: -.infinity, sections: ["x": .hidden, "com.example.l": .shown])
        let c = s.sanitized()
        XCTAssertEqual(c.choices, ["com.example.ok": .alwaysShow])
        XCTAssertEqual(c.newShown, ["com.example.nan": 0, "com.example.inf": 0, "com.example.neg": 0, "com.example.ok": 9])
        XCTAssertEqual(c.knownBundles, ["com.example.k": IconsKnownBundle(firstSeen: 50, lastSeen: 50,
                                                                         missedReads: IconsAppsState.dropAfterMissedReads)])
        XCTAssertEqual(c.toasts, ["com.example.t": 0])
        XCTAssertEqual(c.layout, IconsLayoutCache(readAt: 0, sections: ["com.example.l": .shown]))
        XCTAssertEqual(c.sanitized(), c)
    }

    func testSanitizeKeepsTheMostRecentlySeenWithinTheCaps() {
        var s = IconsAppsState()
        for i in 0..<(IconsAppsState.knownBundlesCap + 40) {
            s.knownBundles["com.example.k\(i)"] = IconsKnownBundle(firstSeen: 1, lastSeen: Double(i + 1))
        }
        for i in 0..<(IconsAppsState.newShownCap + 10) { s.newShown["com.example.n\(i)"] = Double(i + 1) }
        let c = s.sanitized()
        XCTAssertEqual(c.knownBundles.count, IconsAppsState.knownBundlesCap)
        XCTAssertNil(c.knownBundles["com.example.k0"])
        XCTAssertNil(c.knownBundles["com.example.k39"])
        XCTAssertNotNil(c.knownBundles["com.example.k40"])
        XCTAssertEqual(c.newShown.count, IconsAppsState.newShownCap)
        XCTAssertNil(c.newShown["com.example.n9"])
        XCTAssertNotNil(c.newShown["com.example.n10"])
        XCTAssertEqual(c.sanitized(), c)
    }

    func testCapTiesAreDeterministic() {
        var s = IconsAppsState()
        for i in 0..<(IconsAppsState.newShownCap + 1) { s.newShown[String(format: "com.example.n%03d", i)] = 7 }
        let c = s.sanitized()
        XCTAssertEqual(c.newShown.count, IconsAppsState.newShownCap)
        XCTAssertNil(c.newShown[String(format: "com.example.n%03d", IconsAppsState.newShownCap)])
        XCTAssertEqual(s.sanitized(), c)
    }

    func testAppsRestoreDefaultsClearsChoicesAndTheNewList() {
        var s = IconsAppsState()
        s.choices["com.example.a"] = .alwaysShow
        s.newShown["com.example.b"] = 1
        s.knownBundles["com.example.c"] = IconsKnownBundle(firstSeen: 1, lastSeen: 2)
        s.layout = IconsLayoutCache(readAt: 3, sections: ["com.example.c": .hidden])
        s.toasts["com.example.d"] = 4
        let r = s.restoringDefaults()
        XCTAssertTrue(r.choices.isEmpty)
        XCTAssertTrue(r.newShown.isEmpty)
        XCTAssertEqual(r.knownBundles, s.knownBundles)
        XCTAssertEqual(r.layout, s.layout)
        XCTAssertEqual(r.toasts, s.toasts)
    }

    // MARK: Backup (H7)

    func testIconsIsABackupSection() {
        XCTAssertEqual(KitBackup.sections, ["switcher", "modules", "displays", "awake", "icons", "dock"])
        XCTAssertEqual(KitBackup.iconsSection, "icons")
        XCTAssertNotNil(KitBackup.allowedPaths["icons"])
    }

    func testExportCarriesEverySettingButArranged() throws {
        let data = try XCTUnwrap(KitBackup.iconsSectionData(ConfigFixtures.fullIcons()))
        let section = object(data)
        XCTAssertEqual(Set(section.keys), Set(IconsConfig.exportedKeys))
        XCTAssertNil(section["arranged"])
        XCTAssertFalse(IconsConfig.exportedKeys.contains("arranged"))
        // A default config has no shortcut, so the key is simply absent.
        let plain = object(KitBackup.iconsSectionData(IconsConfig()))
        XCTAssertNil(plain["shortcut"])
        XCTAssertNil(plain["arranged"])
    }

    func testDocumentRoundTripLeavesOutArrangedAndBundleData() throws {
        var hostile = object(try JSONEncoder().encode(ConfigFixtures.fullIcons()))
        hostile["knownBundles"] = ["com.example.a": ["firstSeen": 1, "lastSeen": 2]]
        hostile["choices"] = ["com.example.a": "alwaysHide"]
        hostile["futureField"] = 1
        let doc = try XCTUnwrap(KitBackup.makeDocument(
            sections: ["icons": JSONSerialization.data(withJSONObject: hostile, options: [.sortedKeys])],
            created: "t", appVersion: "0.4.0"))
        let parsed = try KitBackup.parseDocument(doc).get()
        let icons = object(try XCTUnwrap(parsed["icons"]))
        XCTAssertEqual(Set(icons.keys), Set(IconsConfig.exportedKeys))
        let text = String(decoding: doc, as: UTF8.self)
        for banned in ["arranged", "knownBundles", "choices", "com.example.a", "futureField"] {
            XCTAssertFalse(text.contains(banned), banned)
        }
    }

    func testImportKeepsThisMacsArrangedAndSanitizes() throws {
        var current = IconsConfig()
        current.arranged = true
        current.hover = true
        let file = Data(#"{"arranged": false, "autoCollapseSeconds": 9000, "dividers": false, "otherHiders": "runBoth"}"#.utf8)
        let r = try XCTUnwrap(KitBackup.importIcons(current: current, imported: file))
        XCTAssertTrue(r.arranged)
        XCTAssertTrue(r.hover)                         // absent from the file: kept
        XCTAssertEqual(r.autoCollapseSeconds, 300)     // clamped
        XCTAssertFalse(r.dividers)
        XCTAssertEqual(r.otherHiders, .runBoth)

        var notArranged = IconsConfig()
        notArranged.arranged = false
        XCTAssertFalse(try XCTUnwrap(KitBackup.importIcons(current: notArranged,
                                                           imported: Data(#"{"arranged": true}"#.utf8))).arranged)
        XCTAssertNil(KitBackup.importIcons(current: current, imported: Data("[1]".utf8)))
        XCTAssertNil(KitBackup.importIcons(current: current, imported: Data("nope".utf8)))
    }

    func testImportLooksUpSafetyPaths() {
        XCTAssertTrue(KitBackup.safetyPaths.contains(["icons", "shortcut"]))
        XCTAssertTrue(KitBackup.safetyPaths.contains(["icons", "otherHiders"]))
        XCTAssertTrue(KitBackup.safetyPaths.contains(["icons", "showDuringCapture"]))
    }

    // MARK: Downgrade (K1 exit: a 0.4 config decodes with the 0.3.4 types)

    /// What 0.4 writes to `SnapticModulesV1`, decoded by the paths 0.3.4 also has: an unknown module id is kept (and
    /// written back), an unknown card is skipped, an unknown onboarding step reads as done. The real 0.3.4 check is
    /// run against a `v0.3.4` worktree (STEP0-NOTES §K1).
    func testA04ModulesFileDecodesWithUnknownValues() throws {
        let json = """
            {"modules": {"windowSwitcher": {"enabled": true, "presence": "inSnapticMenu"},
                         "futureModule": {"enabled": true, "presence": "inSnapticMenu"}},
             "newModuleCards": ["future.card", "displays"],
             "onboarding": "futureStep"}
            """
        let c = try decode(ModulesConfig.self, json)
        XCTAssertEqual(c.newModuleCards, [.displays])
        XCTAssertEqual(c.onboarding, .done)
        XCTAssertTrue(c.isEnabled(.windowSwitcher))
        let written = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertTrue(written.contains("futureModule"))
    }

    func testA04ModulesFileWithHiddenIconsRoundTrips() throws {
        var c = ModulesConfig()
        c.setEnabled(true, for: .hiddenIcons)
        c.setPresence(.hidden, for: .hiddenIcons)
        let back = try roundTrip(c)
        XCTAssertTrue(back.isEnabled(.hiddenIcons))
        XCTAssertEqual(back.presence(.hiddenIcons), .hidden)
        // A presence Hidden Icons can't have falls back on decode.
        var own = ModulesConfig()
        own.modules[.hiddenIcons] = ModulePreferences(enabled: true, presence: .ownIcon)
        XCTAssertTrue(MenuPresence.allowed(for: .hiddenIcons).contains(own.sanitized().presence(.hiddenIcons)))
    }
}
