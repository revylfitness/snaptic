import XCTest
import SnapticKit

final class ConfigDisplaysTests: XCTestCase {
    private let key = DisplayKey(rawValue: String(repeating: "a", count: 32))!

    func testRoundTrip() throws {
        var c = DisplaysConfig()
        c.features[.xdr] = true
        c.perDisplay[key] = PerDisplayConfig()
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(DisplaysConfig.self, from: data), c)
    }

    func testBadSectionFallsBackAlone() throws {
        let json = #"{"features":{"xdr":true,"futureFeature":true,"sync":"yes"},"brightness":42,"perDisplay":{"nothex":{},"\#(key.rawValue)":{}}}"#
        let c = try JSONDecoder().decode(DisplaysConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.features[.xdr], true)
        XCTAssertNil(c.features[.sync])
        XCTAssertNotNil(c.perDisplay[key])
        XCTAssertEqual(c.brightness, BrightnessConfig())
    }

    func testUnknownFeatureKeysSurviveRoundTrip() throws {
        let json = #"{"features":{"futureFeature":true}}"#
        let c = try JSONDecoder().decode(DisplaysConfig.self, from: Data(json.utf8))
        let out = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertTrue(out.contains("futureFeature"))
    }

    func testSanitizedCapsRememberedDisplays() {
        var c = DisplaysConfig()
        for i in 0..<(DisplaysConfig.maxRememberedDisplays + 10) {
            let k = DisplayKey(rawValue: String(format: "%032x", i))!
            c.perDisplay[k] = PerDisplayConfig()
        }
        XCTAssertEqual(c.sanitized().perDisplay.values.count, DisplaysConfig.maxRememberedDisplays)
    }

    func testGarbageDecodesToDefaults() throws {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<300 {
            let bytes = (0..<Int(rng.next() % 64)).map { _ in UInt8(rng.next() % 256) }
            if let c = try? JSONDecoder().decode(DisplaysConfig.self, from: Data(bytes)) {
                XCTAssertEqual(c.sanitized(), c.sanitized().sanitized())
            }
        }
    }

    // MARK: 0.3 sections (§4.5)

    func testNoChangeNoSections() {
        XCTAssertEqual(DisplaysConfig.changedSections(old: DisplaysConfig(), new: DisplaysConfig()), [])
    }

    func testChangedSectionsPerField() {
        let base = DisplaysConfig()
        var c = base
        c.features[.xdr] = true
        XCTAssertEqual(DisplaysConfig.changedSections(old: base, new: c), [.features])
        c = base
        c.menu.compact.toggle()
        XCTAssertEqual(DisplaysConfig.changedSections(old: base, new: c), [.menu])
        c = base
        c.keys.osdShowNits.toggle()
        XCTAssertEqual(DisplaysConfig.changedSections(old: base, new: c), [.keys])
        c = base
        c.brightness.showNits.toggle()
        XCTAssertEqual(DisplaysConfig.changedSections(old: base, new: c), [.brightness])
    }

    func testChangedSectionsSplitPerDisplay() {
        var base = DisplaysConfig()
        base.perDisplay[key] = PerDisplayConfig()
        var c = base
        var entry = PerDisplayConfig()
        entry.management.powerSwitch = .disconnect
        c.perDisplay[key] = entry
        XCTAssertEqual(DisplaysConfig.changedSections(old: base, new: c), [.perDisplayManagement])
        entry = PerDisplayConfig()
        entry.identity.customName = "Desk"
        c.perDisplay[key] = entry
        XCTAssertEqual(DisplaysConfig.changedSections(old: base, new: c), [.perDisplayIdentity])
        // A display appearing or going away touches every per-display section.
        XCTAssertEqual(DisplaysConfig.changedSections(old: DisplaysConfig(), new: base),
                       DisplaysConfigSection.perDisplaySections)
    }

    func testAnyChangeGivesASection() {
        var rng = SeededGenerator(seed: 0x5EC7)
        for _ in 0..<200 {
            var a = DisplaysConfig()
            var b = DisplaysConfig()
            if rng.next() % 2 == 0 { a.features[.sync] = true }
            if rng.next() % 2 == 0 { b.menu.mainFirst = false }
            if rng.next() % 2 == 0 { b.perDisplay[key] = PerDisplayConfig() }
            if rng.next() % 2 == 0 { a.safety = SafetyConfig().sanitized() }
            XCTAssertEqual(a == b, DisplaysConfig.changedSections(old: a, new: b).isEmpty)
        }
    }

    // MARK: 0.3 restore scopes

    func testRestoreDefaultsResetsOnlyItsScope() {
        var c = DisplaysConfig()
        c.features[.xdr] = true
        c.brightness.showNits = false
        c.menu.compact = true
        var entry = PerDisplayConfig()
        entry.identity.customName = "Desk"
        entry.management.powerSwitch = .disconnect
        c.perDisplay[key] = entry

        let b = c.restoringDefaults(scope: .brightness)
        XCTAssertEqual(b.brightness, BrightnessConfig())
        XCTAssertEqual(b.menu, c.menu)
        XCTAssertEqual(b.features, c.features)
        XCTAssertEqual(b.perDisplay[key]?.management, entry.management)

        let all = c.restoringDefaults(scope: .all)
        XCTAssertEqual(all.features, DisplaysConfig().features)
        XCTAssertEqual(all.menu, MenuConfig())
        XCTAssertEqual(all.perDisplay[key]?.identity.customName, "Desk")   // identities are kept
        XCTAssertEqual(all.perDisplay[key]?.management, PerDisplayManagement())

        let one = c.restoringDefaults(scope: .color(key))
        XCTAssertEqual(one.color, c.color)
        XCTAssertEqual(one.perDisplay[key]?.color, PerDisplayColor())
        XCTAssertEqual(c.restoringDefaults(scope: .confirm).safety, SafetyConfig())
    }

    // MARK: 0.3 migrations M4, M5, M10 (R5-2)

    private var combo: HotkeyCombo { HotkeyCombo(keyCode: 35, carbonModifiers: 0x0100 | 0x0800) }

    func testM4MovesMenuShortcutsOnce() {
        var c = DisplaysConfig()
        c.menu.showPanelShortcut = combo
        c.menu.identifyShortcut = HotkeyCombo(keyCode: 34, carbonModifiers: 0x0100)
        var ledger = MigrationLedger()
        let once = c.migrated(ledger: &ledger)
        XCTAssertEqual(once.keys.shortcuts[.fShowPanel], combo)
        XCTAssertEqual(once.keys.shortcuts[.fIdentify], c.menu.identifyShortcut)
        XCTAssertEqual(once.menu.showPanelShortcut, combo)                  // legacy field kept for 0.2
        XCTAssertTrue(ledger.has(.menuShortcuts))
        var cleared = once
        cleared.keys.shortcuts[.fShowPanel] = nil                           // the user removes it in 0.3
        XCTAssertNil(cleared.migrated(ledger: &ledger).keys.shortcuts[.fShowPanel])
    }

    func testM4KeepsAnExistingShortcut() {
        var c = DisplaysConfig()
        c.menu.showPanelShortcut = combo
        let other = HotkeyCombo(keyCode: 1, carbonModifiers: 0x0100)
        c.keys.shortcuts[.fShowPanel] = other
        var ledger = MigrationLedger()
        XCTAssertEqual(c.migrated(ledger: &ledger).keys.shortcuts[.fShowPanel], other)
    }

    func testM5RunsOnceSoALaterOffSticks() {
        var c = DisplaysConfig()
        c.keys.osdShowNits = true
        c.brightness.showNits = false
        var ledger = MigrationLedger()
        var once = c.migrated(ledger: &ledger)
        XCTAssertTrue(once.brightness.showNits)
        XCTAssertTrue(ledger.has(.showNits))
        once.brightness.showNits = false
        XCTAssertFalse(once.migrated(ledger: &ledger).brightness.showNits)
    }

    func testM10PromotesPowerSwitchItemsOnce() {
        var c = DisplaysConfig()
        var a = PerDisplayConfig()
        a.management.powerSwitch = .disconnect
        var b = PerDisplayConfig()
        b.management.powerSwitch = .ddcStandby
        c.perDisplay[key] = a
        c.perDisplay[DisplayKey(rawValue: String(repeating: "b", count: 32))!] = b
        var ledger = MigrationLedger()
        var once = c.migrated(ledger: &ledger)
        XCTAssertEqual(once.menu.items[.dDisconnectItem], .visible)
        XCTAssertEqual(once.menu.items[.cDDCPower], .visible)
        XCTAssertEqual(once.perDisplay[key]?.management.powerSwitch, .disconnect)   // kept, unused
        XCTAssertTrue(ledger.has(.powerSwitch))
        once.menu.items[.dDisconnectItem] = .hidden
        XCTAssertEqual(once.migrated(ledger: &ledger).menu.items[.dDisconnectItem], .hidden)
    }

    func testRecordedMarkersRunNothingAndNothingNeededChangesNothing() {
        var c = DisplaysConfig()
        c.keys.osdShowNits = true
        c.brightness.showNits = false
        c.menu.showPanelShortcut = combo
        var done = MigrationLedger()
        for id in MigrationID.allCases { done.record(id) }
        XCTAssertEqual(c.migrated(ledger: &done), c)
        var fresh = MigrationLedger()
        XCTAssertEqual(DisplaysConfig().migrated(ledger: &fresh), DisplaysConfig())
        XCTAssertTrue(fresh.has(.menuShortcuts) && fresh.has(.showNits) && fresh.has(.powerSwitch))
    }

    func testZeroTwoRoundTripReRunsNothing() throws {
        // 0.3 runs the migrations, the user changes their mind in 0.3, 0.2 re-saves (legacy fields kept, the ledger
        // untouched), 0.3 loads again: nothing re-runs.
        var c = DisplaysConfig()
        c.keys.osdShowNits = true
        c.brightness.showNits = false
        var ledger = MigrationLedger()
        var migrated = c.migrated(ledger: &ledger)
        migrated.brightness.showNits = false
        let reloaded = try JSONDecoder().decode(DisplaysConfig.self, from: JSONEncoder().encode(migrated))
        XCTAssertTrue(reloaded.keys.osdShowNits)
        let storedLedger = try JSONDecoder().decode(MigrationLedger.self, from: JSONEncoder().encode(ledger))
        var again = storedLedger
        XCTAssertEqual(reloaded.migrated(ledger: &again), reloaded)
        XCTAssertEqual(again, storedLedger)
    }
}
