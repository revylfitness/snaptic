import XCTest
@testable import SnapticKit

/// 0.5 K1: Dock Previews' module id and store (H1, H10), its card, the backup section (H7), and what a 0.5 modules
/// file looks like to older types (PLAN 0.5 §6.1, K1).
final class ConfigDockTests: XCTestCase {
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

    // MARK: ModuleID and presence (H1)

    func testIDOrderAndRawValue() throws {
        XCTAssertEqual(ModuleID.allCases.last, .dockPreviews, "started last, stopped first")
        XCTAssertEqual(ModuleID.allCases.firstIndex(of: .dockPreviews), ModuleID.allCases.count - 1)
        XCTAssertEqual(ModuleID.dockPreviews.rawValue, "dockPreviews")
        XCTAssertEqual(ModuleID(rawValue: "dockPreviews"), .dockPreviews)
        XCTAssertEqual(NewModuleCard.dockPreviews.rawValue, "dockPreviews")
        XCTAssertEqual(String(decoding: try JSONEncoder().encode([NewModuleCard.dockPreviews]), as: UTF8.self),
                       #"["dockPreviews"]"#)
        XCTAssertEqual(SettingsRootID.dockPreviews, "dockPreviews")
        XCTAssertEqual(ModuleID.dockPreviews.shortTitle, "Dock")
    }

    func testAllowedContainsFallbackForEveryID() {
        for id in ModuleID.allCases {
            XCTAssertTrue(MenuPresence.allowed(for: id).contains(MenuPresence.fallback(for: id)), id.rawValue)
            XCTAssertTrue(MenuPresence.allowed(for: id).contains(ModulesConfig.defaultPreferences(id).presence),
                          id.rawValue)
        }
        XCTAssertEqual(MenuPresence.allowed(for: .dockPreviews), [.inSnapticMenu, .hidden])
        XCTAssertEqual(MenuPresence.fallback(for: .dockPreviews), .inSnapticMenu)
    }

    /// A tab adds no menu bar icon: a stored own icon (an older or edited file) reads as Show in Snaptic Menu, and
    /// `MenuLayout.ownIconIDs` never lists Dock Previews, even before sanitizing.
    func testSanitizeOwnIconFallsBackToInSnapticMenu() throws {
        for stored in [MenuPresence.ownIcon, .ownIconWhenActive] {
            var c = ModulesConfig()
            c.modules[.dockPreviews] = ModulePreferences(enabled: true, presence: stored)
            XCTAssertEqual(c.ownIconIDs(running: Set(ModuleID.allCases), displaysActive: true).contains(.dockPreviews),
                           false, stored.rawValue)
            XCTAssertEqual(c.effectivePresence(.dockPreviews), .inSnapticMenu, stored.rawValue)
            XCTAssertEqual(c.sanitized().presence(.dockPreviews), .inSnapticMenu, stored.rawValue)
            var set = ModulesConfig()
            set.setPresence(stored, for: .dockPreviews)
            XCTAssertEqual(set.presence(.dockPreviews), .inSnapticMenu, stored.rawValue)
        }
        let file = try decode(ModulesConfig.self, #"{"modules":{"dockPreviews":{"enabled":true,"presence":"ownIcon"}}}"#)
        XCTAssertEqual(file.sanitized().presence(.dockPreviews), .inSnapticMenu)
        var hidden = ModulesConfig()
        hidden.setPresence(.hidden, for: .dockPreviews)
        XCTAssertEqual(hidden.sanitized().presence(.dockPreviews), .hidden)
    }

    func testFreshDefaultsDockOffInSnapticMenu() throws {
        let c = ModulesConfig()
        XCTAssertFalse(c.isEnabled(.dockPreviews))
        XCTAssertEqual(c.presence(.dockPreviews), .inSnapticMenu)
        XCTAssertFalse(c.enabledModules.contains(.dockPreviews))
        XCTAssertEqual(ModulesConfig.defaultPreferences(.dockPreviews), ModulePreferences(enabled: false,
                                                                                           presence: .inSnapticMenu))
        // Upgraders and new users alike start with it off (an unknown id was never stored by 0.4).
        XCTAssertFalse(ModulesConfig.upgradeDefaults().isEnabled(.dockPreviews))
        XCTAssertFalse(ModulesConfig.firstRun(launchedBefore: false).isEnabled(.dockPreviews))
        XCTAssertFalse(ModulesConfig.firstRun(launchedBefore: true).isEnabled(.dockPreviews))
        let stored = try roundTrip(c)
        XCTAssertFalse(stored.isEnabled(.dockPreviews))
        XCTAssertEqual(stored.presence(.dockPreviews), .inSnapticMenu)
    }

    // MARK: "New: Dock Previews" (§4.20, marker dockCard.v1)

    func testDockCardGoesToUpgradersOnce() {
        var ledger = MigrationLedger()
        var c = ModulesConfig()
        c.onboarding = .done
        c.newModuleCards = [.hiddenIcons]
        c = c.insertingDockCard(upgrader: true, ledger: &ledger)
        XCTAssertEqual(c.newModuleCards, [.hiddenIcons, .dockPreviews])
        XCTAssertTrue(ledger.has(.dockCard))
        XCTAssertEqual(MigrationID.dockCard.rawValue, "dockCard.v1")
        // Dismissed, then a later launch: the marker keeps it gone.
        c = GeneralCardRules.dismissing(.dockPreviews, in: c)
        XCTAssertEqual(c.insertingDockCard(upgrader: true, ledger: &ledger).newModuleCards, [.hiddenIcons])
        // Mid-onboarding, Dock Previews already on, or a card already stored: no card, marker recorded.
        var midOnboarding = ModulesConfig()
        midOnboarding.onboarding = .modules
        var first = MigrationLedger()
        XCTAssertFalse(midOnboarding.insertingDockCard(upgrader: true, ledger: &first).newModuleCards
            .contains(.dockPreviews))
        XCTAssertTrue(first.has(.dockCard))
        var on = ModulesConfig()
        on.onboarding = .done
        on.setEnabled(true, for: .dockPreviews)
        var second = MigrationLedger()
        XCTAssertFalse(on.insertingDockCard(upgrader: true, ledger: &second).newModuleCards.contains(.dockPreviews))
        var stored = ModulesConfig()
        stored.onboarding = .done
        stored.newModuleCards = [.dockPreviews]
        var third = MigrationLedger()
        XCTAssertEqual(stored.insertingDockCard(upgrader: true, ledger: &third).newModuleCards, [.dockPreviews])
        // The Hidden Icons marker is a different one.
        var iconsOnly = MigrationLedger()
        iconsOnly.record(.iconsCard)
        XCTAssertFalse(iconsOnly.has(.dockCard))
    }

    func testDockCardSkipsFreshInstallsAcrossLaunches() {
        var ledger = MigrationLedger()
        var c = ModulesConfig.firstRun(launchedBefore: false)
        c = c.insertingDockCard(upgrader: false, ledger: &ledger)
        XCTAssertFalse(c.newModuleCards.contains(.dockPreviews))
        XCTAssertTrue(ledger.has(.dockCard))
        // The second launch counts as an upgrader (module settings now exist) but the marker is recorded.
        c.onboarding = .done
        XCTAssertFalse(c.insertingDockCard(upgrader: true, ledger: &ledger).newModuleCards.contains(.dockPreviews))
    }

    /// A 0.1 user without module settings (`upgradeDefaults`, onboarding skipped) is an upgrader too.
    func testDockCardReachesZeroOneUpgraders() {
        var ledger = MigrationLedger()
        let c = ModulesConfig.firstRun(launchedBefore: true).insertingDockCard(upgrader: true, ledger: &ledger)
        XCTAssertTrue(c.newModuleCards.contains(.dockPreviews))
        XCTAssertEqual(GeneralCardRules.visible(c.newModuleCards, enabled: Set(c.enabledModules), blocked: []).last,
                       .dockPreviews)
        XCTAssertEqual(GeneralCardRules.module(of: .dockPreviews), .dockPreviews)
    }

    /// Turning Dock Previews on clears its card and never changes its presence (D2-29).
    func testSetEnabledClearsDockCard() {
        var c = ModulesConfig()
        c.onboarding = .done
        c.newModuleCards = [.hiddenIcons, .dockPreviews]
        c.setPresence(.hidden, for: .dockPreviews)
        c.setEnabled(true, for: .dockPreviews)
        XCTAssertEqual(c.newModuleCards, [.hiddenIcons])
        XCTAssertTrue(c.isEnabled(.dockPreviews))
        XCTAssertEqual(c.presence(.dockPreviews), .hidden)
        // Turning it off doesn't bring the card back, and other modules leave it alone.
        c.setEnabled(false, for: .dockPreviews)
        XCTAssertEqual(c.newModuleCards, [.hiddenIcons])
        var other = ModulesConfig()
        other.newModuleCards = [.dockPreviews]
        other.setEnabled(true, for: .hiddenIcons)
        XCTAssertEqual(other.newModuleCards, [.dockPreviews])
        // While it's on, the card isn't shown even when stored (a restored backup).
        var restored = ModulesConfig()
        restored.newModuleCards = [.dockPreviews]
        restored.modules[.dockPreviews] = ModulePreferences(enabled: true, presence: .inSnapticMenu)
        XCTAssertFalse(GeneralCardRules.visible(restored.newModuleCards, enabled: Set(restored.enabledModules),
                                                blocked: []).contains(.dockPreviews))
    }

    // MARK: Icons that need an external display (W16)

    /// Displays shown only with an external display, plus Dock Previews on with Don't Show: Dock Previews adds no
    /// icon, so the bar can still be empty.
    func testIconsNeedExternalDisplayIgnoresDockHidden() {
        var c = ModulesConfig()
        c.setEnabled(false, for: .windowSwitcher)
        c.setEnabled(false, for: .awake)
        c.setPresence(.ownIconWhenActive, for: .displays)
        XCTAssertTrue(c.iconsNeedExternalDisplay)
        c.setEnabled(true, for: .dockPreviews)
        c.setPresence(.hidden, for: .dockPreviews)
        XCTAssertTrue(c.iconsNeedExternalDisplay)
        // An own icon can't be stored for it, and even unsanitized it never counts as one.
        c.modules[.dockPreviews] = ModulePreferences(enabled: true, presence: .hidden)
        XCTAssertTrue(c.iconsNeedExternalDisplay)
    }

    /// Dock Previews on in the Snaptic menu: its tab keeps the Snaptic icon in the bar.
    func testIconsNeedExternalDisplayCountsDockInMenu() {
        var c = ModulesConfig()
        c.setEnabled(false, for: .windowSwitcher)
        c.setEnabled(false, for: .awake)
        c.setPresence(.ownIconWhenActive, for: .displays)
        c.setEnabled(true, for: .dockPreviews)
        XCTAssertEqual(c.presence(.dockPreviews), .inSnapticMenu)
        XCTAssertFalse(c.iconsNeedExternalDisplay)
        // Off again: back to needing a display.
        c.setEnabled(false, for: .dockPreviews)
        XCTAssertTrue(c.iconsNeedExternalDisplay)
    }

    // MARK: DockConfig (H10)

    func testDockConfigDefaults() throws {
        let c = DockConfig()
        XCTAssertEqual(DockConfig.key, "SnapticDockV1")
        XCTAssertEqual(c.delay, 0.2)
        XCTAssertEqual(c.cardSize, .medium)
        XCTAssertTrue(c.thumbnails)
        XCTAssertTrue(c.includeMinimizedAndHidden)
        XCTAssertTrue(c.otherSpaces)
        XCTAssertEqual(c.clickActions, .doNothing)
        XCTAssertFalse(c.restoreAllMinimized)
        XCTAssertEqual(c.sort, .recentlyUsed)
        XCTAssertTrue(c.keys)
        XCTAssertTrue(c.windowlessApps)
        XCTAssertFalse(c.runAlongsideOtherTools, "Pause Dock Previews is the default")
        XCTAssertFalse(c.showWithVoiceOver)
        XCTAssertTrue(c.hiddenBundleIDs.isEmpty)
        XCTAssertEqual(c.sanitized(), c)
        XCTAssertEqual(DockCardSize.allCases.map(\.rawValue), ["small", "medium", "large"])
        XCTAssertEqual(DockClickAction.allCases.map(\.rawValue), ["doNothing", "hideApp", "minimizeWindows"])
        XCTAssertEqual(DockSort.allCases.map(\.rawValue), ["recentlyUsed", "minimizedAndHiddenLast", "title"])
    }

    func testSanitizeClampsDelay() {
        var c = DockConfig()
        for (raw, want) in [(0.0, 0.0), (0.2, 0.2), (1.0, 1.0), (-0.1, 0.0), (1.5, 1.0), (-.infinity, 0.0),
                            (.infinity, 1.0), (.greatestFiniteMagnitude, 1.0), (-0.0, 0.0)] {
            c.delay = raw
            XCTAssertEqual(c.sanitized().delay, want, "\(raw)")
        }
        c.delay = .nan
        XCTAssertEqual(c.sanitized().delay, 0.2)
        c.delay = .signalingNaN
        XCTAssertEqual(c.sanitized().delay, DockConfig.defaultDelay)
    }

    func testSanitizeKeepsValidHiddenAppsOnceWithinTheCap() {
        var c = DockConfig()
        c.hiddenBundleIDs = ["com.example.A", "", "nodots", "com.ex ample.B", "com.example.A", "com.example.é",
                             "com.example.C"]
        XCTAssertEqual(c.sanitized().hiddenBundleIDs, ["com.example.A", "com.example.C"])
        c.hiddenBundleIDs = (0..<(DockConfig.hiddenBundleIDsCap + 20)).map { "com.example.app\($0)" }
        let capped = c.sanitized()
        XCTAssertEqual(capped.hiddenBundleIDs.count, DockConfig.hiddenBundleIDsCap)
        XCTAssertEqual(capped.hiddenBundleIDs.first, "com.example.app0")
        XCTAssertEqual(capped.sanitized(), capped)
    }

    func testLossyEnumsFallBack() throws {
        let c = try decode(DockConfig.self, """
            {"cardSize": "huge", "clickActions": "quitApp", "sort": 3, "delay": "soon", "keys": false,
             "thumbnails": "no", "hiddenBundleIDs": ["com.example.A", 7, null, "com.example.B"]}
            """)
        XCTAssertEqual(c.cardSize, .medium)
        XCTAssertEqual(c.clickActions, .doNothing)
        XCTAssertEqual(c.sort, .recentlyUsed)
        XCTAssertEqual(c.delay, 0.2)
        XCTAssertFalse(c.keys)                         // a good field next to bad ones is kept
        XCTAssertTrue(c.thumbnails)
        XCTAssertEqual(c.hiddenBundleIDs, ["com.example.A", "com.example.B"])
        let ok = try decode(DockConfig.self, #"{"cardSize": "small", "clickActions": "hideApp", "sort": "title"}"#)
        XCTAssertEqual(ok.cardSize, .small)
        XCTAssertEqual(ok.clickActions, .hideApp)
        XCTAssertEqual(ok.sort, .title)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try decode(DockConfig.self, "{}"), DockConfig())
        let c = try decode(DockConfig.self, #"{"showWithVoiceOver": true, "futureField": [1, 2]}"#)
        var expected = DockConfig()
        expected.showWithVoiceOver = true
        XCTAssertEqual(c, expected)
        XCTAssertThrowsError(try decode(DockConfig.self, "[]"))
    }

    func testRoundTrip() throws {
        let full = ConfigFixtures.fullDock()
        XCTAssertEqual(try roundTrip(full), full)
        XCTAssertEqual(try roundTrip(DockConfig()), DockConfig())
        XCTAssertEqual(full.sanitized(), full)
        // Every field of the fixture is away from its default, so a dropped field would show.
        let fullObject = object(try JSONEncoder().encode(full))
        let plainObject = object(try JSONEncoder().encode(DockConfig()))
        for key in DockConfig.exportedKeys {
            XCTAssertFalse((fullObject[key] as AnyObject).isEqual(plainObject[key]), key)
        }
    }

    func testFieldNamesAvoidTheSensitiveFragments() {
        // KitBackup drops any key containing one of these at any depth; a setting named so would silently vanish.
        let names = Set(DockConfig.exportedKeys + [DockConfig.key] + DockFeature.allCases.map(\.rawValue)
            + DockCardSize.allCases.map(\.rawValue) + DockClickAction.allCases.map(\.rawValue)
            + DockSort.allCases.map(\.rawValue))
        for name in names {
            for fragment in KitBackup.sensitiveKeyFragments {
                XCTAssertFalse(name.lowercased().contains(fragment.lowercased()), "\(name) contains \(fragment)")
            }
        }
        XCTAssertTrue(DockConfig.exportedKeys.contains("runAlongsideOtherTools"), "Run Both is stored under this name")
    }

    func testDockExportedKeysAreEveryCodingKey() throws {
        let encoded = object(try JSONEncoder().encode(ConfigFixtures.fullDock()))
        XCTAssertEqual(Set(encoded.keys), Set(DockConfig.exportedKeys))
        XCTAssertEqual(Set(DockConfig.exportedKeys).count, DockConfig.exportedKeys.count)
        XCTAssertEqual(DockConfig.exportedKeys.count, 13)
        XCTAssertEqual(KitBackup.allowedPaths[KitBackup.dockSection], DockConfig.exportedKeys.map { [$0] })
    }

    // MARK: Backup (H7, H10)

    func testDockIsABackupSection() {
        XCTAssertEqual(KitBackup.dockSection, "dock")
        XCTAssertEqual(KitBackup.sections.last, "dock")
        XCTAssertNil(KitBackup.sectionSensitiveKeys["dock"])
        XCTAssertFalse(KitBackup.unionPaths.contains { $0.first == "dock" }, "the hidden apps list is replaced")
    }

    func testBackupAllowlistRoundTrip() throws {
        let full = ConfigFixtures.fullDock()
        let section = try XCTUnwrap(KitBackup.dockSectionData(full))
        XCTAssertEqual(Set(object(section).keys), Set(DockConfig.exportedKeys))
        // A hostile file: unknown and sensitive-looking keys never get into a document or back out of one.
        var hostile = object(section)
        hostile["futureField"] = 1
        hostile["allowEverything"] = true
        hostile["secretToken"] = "x"
        let doc = try XCTUnwrap(KitBackup.makeDocument(
            sections: ["dock": JSONSerialization.data(withJSONObject: hostile, options: [.sortedKeys])],
            created: "t", appVersion: "0.5.0"))
        let text = String(decoding: doc, as: UTF8.self)
        for banned in ["futureField", "allowEverything", "secretToken"] { XCTAssertFalse(text.contains(banned), banned) }
        let parsed = try XCTUnwrap(KitBackup.parseDocument(doc).get()["dock"])
        XCTAssertEqual(Set(object(parsed).keys), Set(DockConfig.exportedKeys))
        XCTAssertEqual(KitBackup.importDock(current: DockConfig(), imported: parsed), full)

        // An import lays the file over this Mac's settings and sanitizes; fields it lacks are kept.
        var current = DockConfig()
        current.showWithVoiceOver = true
        let partial = Data(#"{"delay": 9, "cardSize": "large", "sort": "nope", "hiddenBundleIDs": ["bad", "com.example.X"]}"#.utf8)
        let r = try XCTUnwrap(KitBackup.importDock(current: current, imported: partial))
        XCTAssertEqual(r.delay, 1)
        XCTAssertEqual(r.cardSize, .large)
        XCTAssertEqual(r.sort, .recentlyUsed)
        XCTAssertTrue(r.showWithVoiceOver)
        XCTAssertEqual(r.hiddenBundleIDs, ["com.example.X"])
        XCTAssertNil(KitBackup.importDock(current: current, imported: Data("[1]".utf8)))
        XCTAssertNil(KitBackup.importDock(current: current, imported: Data("nope".utf8)))
    }

    func testDockBackupSafetyPathsListedFirst() throws {
        let safety = ["clickActions", "keys", "runAlongsideOtherTools", "showWithVoiceOver"]
        for key in safety {
            XCTAssertTrue(KitBackup.safetyPaths.contains(["dock", key]), key)
            XCTAssertTrue(KitBackup.isSafetyRelated(section: "dock", path: key), key)
        }
        XCTAssertFalse(KitBackup.isSafetyRelated(section: "dock", path: "cardSize"))
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "dock", path: "(all)"))
        let old = try XCTUnwrap(KitBackup.dockSectionData(DockConfig()))
        let new = try XCTUnwrap(KitBackup.dockSectionData(ConfigFixtures.fullDock()))
        let preview = KitBackup.previewChanges(section: "dock", from: old, to: new, limit: 2)
        XCTAssertEqual(preview.safety, safety, "all of them, sorted")
        XCTAssertEqual(preview.other.count, 2, "the rest is shortened, safety never is")
        XCTAssertTrue(preview.other.allSatisfy { !safety.contains($0) })
    }

    // MARK: Downgrade (H7: a 0.5 modules file read by the paths 0.4.0 also has)

    /// What 0.5 writes to `SnapticModulesV1`: Dock Previews on and hidden, its card, an unknown module and card, and
    /// an onboarding step this build doesn't know. The real 0.4.0 check runs in a `v0.4.0` worktree (H1-SITES.md).
    func testA05ModulesFileDecodesWithUnknownValues() throws {
        let json = """
            {"modules": {"windowSwitcher": {"enabled": true, "presence": "inSnapticMenu"},
                         "dockPreviews": {"enabled": true, "presence": "hidden"},
                         "futureModule": {"enabled": true, "presence": "inSnapticMenu"}},
             "newModuleCards": ["future.card", "dockPreviews", "hiddenIcons"],
             "onboarding": "futureStep"}
            """
        let c = try decode(ModulesConfig.self, json)
        XCTAssertEqual(c.newModuleCards, [.dockPreviews, .hiddenIcons])
        XCTAssertEqual(c.onboarding, .done)
        XCTAssertTrue(c.isEnabled(.windowSwitcher))
        XCTAssertTrue(c.isEnabled(.dockPreviews))
        XCTAssertEqual(c.presence(.dockPreviews), .hidden)
        let written = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertTrue(written.contains("futureModule"))
        XCTAssertEqual(try roundTrip(c), c)
    }

    // MARK: Events, kill switches, permissions

    func testEventCategoryDockExported() {
        XCTAssertEqual(EventCategory.dock.rawValue, "dock")
        XCTAssertTrue(EventCategory.dock.isExportedInDiagnostics)
        XCTAssertNotEqual(EventCategory.dock, EventCategory.icons)
    }

    func testDockFeatureKillSwitches() {
        XCTAssertEqual(DockFeature.allCases.map(\.rawValue), ["clickActions", "keys"])
        XCTAssertEqual(KillSwitches.key(prefix: "Dock", id: "keys"), "Dock.disable.keys")
        let domain: [String: Any] = ["Dock.disable.clickActions": true, "Dock.disable.keys": false,
                                     "Dock.disable.thumbnails": true, "Icons.disable.keys": true,
                                     "Modules.disable.dockPreviews": true]
        XCTAssertEqual(KillSwitches.read(domain, prefix: "Dock", as: DockFeature.self), [.clickActions])
        XCTAssertEqual(KillSwitches.read(domain, prefix: "Modules", as: ModuleID.self), [.dockPreviews])
        XCTAssertEqual(KillSwitches.read(nil, prefix: "Dock", as: DockFeature.self), [])
    }

    /// The sheet's Restore Defaults resets its own settings only; the page's restore is `DockConfig()` (§4.18).
    func testRestoringAdvancedDefaultsKeepsThePageSettings() {
        var c = DockConfig()
        c.delay = 0.7
        c.cardSize = .large
        c.thumbnails = false
        c.includeMinimizedAndHidden = false
        c.otherSpaces = false
        c.clickActions = .hideApp
        c.restoreAllMinimized = true
        c.sort = .title
        c.keys = false
        c.windowlessApps = false
        c.runAlongsideOtherTools = true
        c.showWithVoiceOver = true
        c.hiddenBundleIDs = ["com.apple.Safari"]
        let restored = c.restoringAdvancedDefaults()
        var expected = DockConfig()
        expected.delay = 0.7
        expected.cardSize = .large
        expected.thumbnails = false
        expected.includeMinimizedAndHidden = false
        expected.otherSpaces = false
        expected.clickActions = .hideApp
        expected.restoreAllMinimized = true
        XCTAssertEqual(restored, expected)
    }

    /// “Show previews after” (§4.18; P3-7): “Immediately”, then “0.1 s” to “1 s”, one position per tenth.
    func testDelayLabelsAndPositions() {
        XCTAssertEqual(DockConfig.delayLabels(), ["Immediately", "0.1 s", "0.2 s", "0.3 s", "0.4 s", "0.5 s", "0.6 s",
                                                  "0.7 s", "0.8 s", "0.9 s", "1 s"])
        XCTAssertEqual(DockConfig.delayLabel(0.3, decimalSeparator: ","), "0,3 s")
        XCTAssertEqual(DockConfig.delayPosition(DockConfig.defaultDelay), 2)
        XCTAssertEqual(DockConfig.delayPosition(0.04), 0)
        XCTAssertEqual(DockConfig.delayPosition(5), 10)
        XCTAssertEqual(DockConfig.delayPosition(-1), 0)
        XCTAssertEqual(DockConfig.delayPosition(.nan), 2)
        XCTAssertEqual(DockConfig.delay(atPosition: 3), 0.3)
        XCTAssertEqual(DockConfig.delay(atPosition: 12), 1)
        XCTAssertEqual(DockConfig.delay(atPosition: -2), 0)
        for position in 0...10 {
            XCTAssertEqual(DockConfig.delayPosition(DockConfig.delay(atPosition: Double(position))), Double(position))
        }
    }

    func testRequiredPermissions() {
        var c = DockConfig()
        XCTAssertEqual(c.requiredPermissions, [.accessibility, .screenRecording])
        c.thumbnails = false
        XCTAssertEqual(c.requiredPermissions, [.accessibility])
    }
}
