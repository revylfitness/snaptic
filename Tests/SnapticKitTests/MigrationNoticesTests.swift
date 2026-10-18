import XCTest
@testable import SnapticKit

final class MigrationNoticesTests: XCTestCase {
    private let combo = HotkeyCombo(keyCode: 2, carbonModifiers: 0x0900)

    private func id(_ n: Int) -> StableID { StableID.derived(namespace: "test", name: String(n)) }

    private func rule(_ n: Int, enabled: Bool = true) -> AwakeTrigger {
        var t = AwakeTrigger(id: id(n), name: "Rule \(n)", criteria: [])
        t.enabled = enabled
        return t
    }

    func testMovedText() {
        XCTAssertEqual(MigrationNotices.movedText(displayNames: ["DELL U2720Q"]),
                       "Keeping your Mac awake while “DELL U2720Q” is connected is now part of Awake.")
        XCTAssertEqual(MigrationNotices.movedText(displayNames: ["A", "B"]),
                       "Keeping your Mac awake while “A” or “B” is connected is now part of Awake.")
        XCTAssertEqual(MigrationNotices.movedText(displayNames: ["A", "B", "C"]),
                       "Keeping your Mac awake while “A” or another display is connected is now part of Awake.")
        XCTAssertEqual(MigrationNotices.movedText(displayNames: []),
                       "Keeping your Mac awake while a display is connected is now part of Awake.")
        XCTAssertEqual(MigrationNotices.movedText(displayNames: [" ", "B"]),
                       "Keeping your Mac awake while “B” is connected is now part of Awake.")
    }

    func testToastWatchAndDue() {
        var ledger = MigrationLedger()
        let migrated: Set<StableID> = [id(1), id(2)]
        XCTAssertFalse(MigrationNotices.needsToastWatch(ledger: ledger, migratedRuleIDs: migrated, configuredRuleIDs: [id(1)]),
                       "M1 hasn't run")
        ledger.record(.fromDisplays)
        XCTAssertTrue(MigrationNotices.needsToastWatch(ledger: ledger, migratedRuleIDs: migrated, configuredRuleIDs: [id(1)]))
        XCTAssertFalse(MigrationNotices.needsToastWatch(ledger: ledger, migratedRuleIDs: migrated, configuredRuleIDs: [id(3)]),
                       "the user deleted the migrated rules")
        XCTAssertFalse(MigrationNotices.needsToastWatch(ledger: ledger, migratedRuleIDs: [], configuredRuleIDs: [id(1)]))
        XCTAssertFalse(MigrationNotices.toastDue(ledger: ledger, migratedRuleIDs: migrated, activeRuleIDs: [id(3)]))
        XCTAssertTrue(MigrationNotices.toastDue(ledger: ledger, migratedRuleIDs: migrated, activeRuleIDs: [id(3), id(2)]))
        ledger.record(.fromDisplaysToast)
        XCTAssertFalse(MigrationNotices.toastDue(ledger: ledger, migratedRuleIDs: migrated, activeRuleIDs: [id(2)]), "once")
        XCTAssertFalse(MigrationNotices.needsToastWatch(ledger: ledger, migratedRuleIDs: migrated, configuredRuleIDs: [id(1)]))
    }

    func testApplyEffectiveReplacesByIDAndMovesTheShortcut() {
        var awake = AwakeConfig()
        awake.triggers.triggers = [rule(9), rule(1, enabled: false)]
        var modules = ModulesConfig()
        modules.modules[.awake] = ModulesConfig.awakeUpgradePreferences
        let result = AwakeMigrationResult(triggers: [rule(1), rule(2)], enableModule: true, migratedDisplayNames: ["A"],
                                          pauseRulesShortcut: combo)
        XCTAssertTrue(result.apply(to: &awake, modules: &modules))
        XCTAssertEqual(awake.triggers.triggers.map(\.id), [id(9), id(1), id(2)])
        XCTAssertTrue(awake.triggers.triggers[1].enabled, "replaced, not appended")
        XCTAssertEqual(awake.shortcuts[.pauseAutomatic], combo)
        XCTAssertEqual(awake.features[.triggers], true)
        XCTAssertEqual(modules.modules[.awake], ModulePreferences(enabled: true, presence: .ownIconWhenActive))
        XCTAssertEqual(modules.newModuleCards.filter { $0 == .awakeMigrated }.count, 1)

        // A re-run after a crash between saves gives the same state once.
        let before = (awake, modules)
        XCTAssertTrue(result.apply(to: &awake, modules: &modules))
        XCTAssertEqual(awake, before.0)
        XCTAssertEqual(modules, before.1)
    }

    func testApplyNotEffectiveLeavesTheModuleOff() {
        var awake = AwakeConfig()
        var modules = ModulesConfig()
        modules.modules[.awake] = ModulesConfig.awakeUpgradePreferences
        let cards = modules.newModuleCards
        let result = AwakeMigrationResult(triggers: [rule(1, enabled: false)], enableModule: false, migratedDisplayNames: [])
        XCTAssertFalse(result.apply(to: &awake, modules: &modules))
        XCTAssertEqual(awake.triggers.triggers.map(\.id), [id(1)])
        XCTAssertNil(awake.features[.triggers])
        XCTAssertEqual(modules.modules[.awake], ModulesConfig.awakeUpgradePreferences)
        XCTAssertEqual(modules.newModuleCards, cards)
    }

    func testApplyNeverOverwritesABoundPauseShortcut() {
        var awake = AwakeConfig()
        let mine = HotkeyCombo(keyCode: 9, carbonModifiers: 0)
        awake.shortcuts[.pauseAutomatic] = mine
        var modules = ModulesConfig()
        let result = AwakeMigrationResult(triggers: [rule(1)], enableModule: true, migratedDisplayNames: [],
                                          pauseRulesShortcut: combo)
        _ = result.apply(to: &awake, modules: &modules)
        XCTAssertEqual(awake.shortcuts[.pauseAutomatic], mine)
    }

    /// End to end over G's M1: the raw 0.2 JSON with the toggle shortcut moves it; the dropped case is reported.
    func testWithRealMigration() throws {
        let key = String(repeating: "0", count: 31) + "1"
        let fp = String(repeating: "a", count: 32)
        let json = #"{"features":{"sleepPrevention":true},"perDisplay":{"\#(key)":{"management":{"preventSleep":true},"identity":{"fingerprint":{"t2":"\#(fp)"},"customName":"Studio"}}},"keys":{"shortcuts":{"d.sleepPreventionToggle":{"keyCode":2,"carbonModifiers":2304}}}}"#
        let result = AwakeMigration.fromDisplays(rawJSON: Data(json.utf8), modulesEnabled: [.displays],
                                                 awakeShortcuts: LossyMap())
        XCTAssertEqual(result.pauseRulesShortcut, combo)
        var awake = AwakeConfig()
        var modules = ModulesConfig()
        XCTAssertTrue(result.apply(to: &awake, modules: &modules))
        XCTAssertEqual(awake.shortcuts[.pauseAutomatic], combo)
        XCTAssertEqual(MigrationNotices.movedText(displayNames: result.migratedDisplayNames),
                       "Keeping your Mac awake while “Studio” is connected is now part of Awake.")

        var bound = LossyMap<AwakeActionID, HotkeyCombo>()
        bound[.pauseAutomatic] = HotkeyCombo(keyCode: 9, carbonModifiers: 0)
        let dropped = AwakeMigration.fromDisplays(rawJSON: Data(json.utf8), modulesEnabled: [.displays],
                                                  awakeShortcuts: bound)
        XCTAssertTrue(dropped.droppedShortcut)
        XCTAssertNil(dropped.pauseRulesShortcut)
    }
}
