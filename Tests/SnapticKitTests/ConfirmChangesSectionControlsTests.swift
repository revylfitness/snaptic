import XCTest
@testable import SnapticKit

/// B's control tables (PLAN 0.3 §4.3 Displays › Advanced › Confirm display changes, §4.4 duplicates 1, 2 and 14,
/// §4.8): every 0.2 Safety id B owns has a home, the settings are searchable and land on F's Advanced sheet.
final class ConfirmChangesSectionControlsTests: XCTestCase {
    private typealias Confirm = ConfirmChangesSectionControls

    private func homes(_ tables: [any ControlTable.Type]) -> Set<String> {
        Set(tables.flatMap { $0.controls.flatMap { $0.replaces.map(\.rawValue) } })
    }

    private var safetyIDs: Set<String> {
        Set(ControlLegacy.ids.map(\.rawValue).filter { $0.hasPrefix("l.d.safety.") })
    }

    func testTablesAreRegisteredWithTheirSurfaces() {
        let names = ControlRegistry.tables.map { String(describing: $0) }
        XCTAssertTrue(names.contains("ConfirmChangesSectionControls"))
        XCTAssertTrue(names.contains("PanicCoordinatorControls"))
        XCTAssertEqual(Confirm.surface, "displays.advanced.confirm")
        XCTAssertEqual(PanicCoordinatorControls.surface, "menu.display.b")
        for spec in Confirm.controls { XCTAssertTrue(spec.id.rawValue.hasPrefix(Confirm.surface + "."), spec.id.rawValue) }
    }

    /// The section is the one home of the 0.2 Safety settings and of the two §4.4 duplicates (Resolution's and
    /// DDC's copies), and of the Restore All Displays shortcut (§4.4 #14).
    func testSectionHomesTheSafetySettingsAndDuplicates() {
        let mine = homes([Confirm.self])
        let expected: Set<String> = [
            "l.d.safety.confirm", "l.d.resolution.confirm",
            "l.d.safety.confirmSeconds", "l.d.safety.announceRecovery",
            "l.d.safety.panicHotkey", "l.action.b.restoreAll",
            "l.d.safety.allowedWithoutAsking", "l.d.ddc.allowedWithoutAsking",
            "l.d.safety.resume",
        ]
        XCTAssertEqual(mine, expected)
        let legacy = Set(ControlLegacy.ids.map(\.rawValue))
        let removed = Set(ControlRemovals.removed.keys.map(\.rawValue))
        for id in mine.union(homes([PanicCoordinatorControls.self])) {
            XCTAssertTrue(legacy.contains(id), id)
            XCTAssertFalse(removed.contains(id), id)
        }
    }

    /// The Safety ids that live outside the section, and where (§4.8 Safety rows): Restore All Displays Now in
    /// Display Tools; the status rows on Display Information (F). A new 0.2 Safety id can't slip through unassigned.
    func testEverySafetyIDHasAPlannedHome() {
        let elsewhere: Set<String> = [
            "l.d.safety.restoreAllNow",
            "l.d.safety.helper.status", "l.d.safety.helper.canRevert", "l.d.safety.pendingConfirmation",
            "l.d.safety.undoJournal", "l.d.safety.keptModes.forget", "l.d.safety.unavailable",
        ]
        let mine = homes([Confirm.self]).filter { $0.hasPrefix("l.d.safety.") }
        XCTAssertTrue(mine.isDisjoint(with: elsewhere))
        XCTAssertEqual(mine.union(elsewhere), safetyIDs)
        XCTAssertEqual(safetyIDs.count, 13)
        // Restore All Displays Now already has its Display Tools homes.
        XCTAssertTrue(homes(ControlRegistry.tables).contains("l.d.safety.restoreAllNow"))
    }

    func testMenuItemsHomeTheirLegacyItems() {
        let byID = Dictionary(uniqueKeysWithValues: PanicCoordinatorControls.controls.map { ($0.id.rawValue, $0) })
        let restore = byID["menu.display.b.restoreAll"]
        XCTAssertEqual(restore?.menu?.legacyMenuID?.rawValue, "b.restoreAll")
        XCTAssertEqual(restore?.menu?.customize, MenuCustomize.checkbox)
        let resume = byID["menu.display.b.resume"]
        XCTAssertEqual(resume?.menu?.legacyMenuID?.rawValue, "b.resumeAutomation")
        XCTAssertEqual(resume?.when ?? [], [ControlCondition.state(.automationPaused)])
    }

    /// Every setting row is searchable, opens F's Advanced sheet on the Displays page and anchors to its own id.
    func testSettingsAreSearchableOnTheAdvancedSheet() throws {
        let settings = Confirm.controls.filter { $0.kind == .setting || $0.kind == .shortcut || $0.kind == .list }
        XCTAssertEqual(settings.count, 5)
        let entries = SettingsIndex.entries(ControlRegistry.tables, root: SettingsRootID.displays)
        for spec in settings {
            let search = try XCTUnwrap(spec.search, spec.id.rawValue)
            XCTAssertEqual(search.root, SettingsRootID.displays)
            XCTAssertNil(search.route, "the sheet opens over the Displays root page")
            XCTAssertEqual(search.sheet, DisplaysAdvancedSheetControls.sheet)
            let entry = try XCTUnwrap(entries.first { $0.id == spec.id.rawValue }, spec.id.rawValue)
            XCTAssertEqual(entry.anchor, spec.id.rawValue)
            XCTAssertEqual(entry.title, search.title)
        }
        // Rows that exist only sometimes (paused, a non-default shortcut, per display) aren't search targets.
        for id in ["displays.advanced.confirm.resume", "displays.advanced.confirm.useDefaultShortcut",
                   "displays.advanced.confirm.askAgain"] {
            XCTAssertNil(Confirm.controls.first { $0.id.rawValue == id }?.search, id)
        }
    }

    /// The words people use for these settings find them first.
    func testSearchFindsTheSection() {
        let entries = SettingsIndex.entries(ControlRegistry.tables, root: SettingsRootID.displays)
        func top(_ query: String) -> String? { SettingsSearch.rank(entries: entries, query: query).first?.id }
        XCTAssertEqual(top("revert after"), "displays.advanced.confirm.revertAfter")
        XCTAssertEqual(top("confirm resolution"), "displays.advanced.confirm.resolution")
        XCTAssertEqual(top("tell me when"), "displays.advanced.confirm.announceRecovery")
        XCTAssertEqual(top("allowed without asking"), "displays.advanced.confirm.allowedWithoutAsking")
        XCTAssertEqual(top("restore all displays shortcut"), "displays.advanced.confirm.shortcut")
        let panic = SettingsSearch.rank(entries: entries, query: "panic").map(\.id)
        XCTAssertTrue(panic.contains("displays.advanced.confirm.shortcut"))
        let countdown = SettingsSearch.rank(entries: entries, query: "countdown").map(\.id)
        XCTAssertTrue(countdown.contains("displays.advanced.confirm.revertAfter"))
    }

    /// Every `SafetyConfig` field is edited here except `keptModes` (Display Information's remembered resolutions);
    /// the declared keys are what the key cross-check (R5-13) will look for.
    func testKeysCoverTheSectionsFields() throws {
        let keys = Set(Confirm.controls.flatMap(\.keys))
        XCTAssertEqual(keys, ["safety.confirmResolution", "safety.confirmSeconds", "safety.announceRecovery",
                              "safety.panicHotkey", "safety.panicHotkeyEnabled", "safety.preConfirmAllowed"])
        var full = SafetyConfig()
        full.panicHotkey = HotkeyCombo(keyCode: 15, carbonModifiers: HotkeyRules.command | HotkeyRules.option)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as? [String: Any])
        let fields = Set(object.keys.map { "safety." + $0 })
        XCTAssertTrue(keys.isSubset(of: fields))
        XCTAssertEqual(fields.subtracting(keys), ["safety.keptModes"])
    }
}
