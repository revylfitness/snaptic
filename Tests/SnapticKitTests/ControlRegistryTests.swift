import XCTest
@testable import SnapticKit

/// PLAN 0.3 §4.8 tests (R5-13 timing): the per-table tests run from step 0; totality (test 1's home check) and the
/// key cross-check (test 5) are skipped until the step-3 exit, when the lead turns them on.
final class ControlRegistryTests: XCTestCase {
    private var specs: [(table: String, surface: String, spec: ControlSpec)] {
        ControlRegistry.tables.flatMap { t in t.controls.map { (String(describing: t), t.surface, $0) } }
    }

    private var legacy: Set<LegacyControlID> { Set(ControlLegacy.ids) }

    /// "A trailing `*` matches the pattern ids": a legacy id ending in `*` is the family itself.
    private func isLegacy(_ id: LegacyControlID) -> Bool { legacy.contains(id) }

    // MARK: The frozen list

    func testFrozenListIsTheLiteral588() {
        XCTAssertEqual(ControlLegacy.ids.count, 588)
        XCTAssertEqual(legacy.count, 588)
        XCTAssertTrue(ControlLegacy.ids.allSatisfy { $0.rawValue.hasPrefix("l.") })
        XCTAssertEqual(ControlLegacy.ids.filter { $0.rawValue.hasPrefix("l.sw.feature.") }.count, 14)
        XCTAssertEqual(ControlLegacy.ids.filter { $0.rawValue.hasPrefix("l.menu.") && !$0.rawValue.hasPrefix("l.menu.fixed.") }.count, 46)
    }

    func testRemovalsAreLegacyIDsWithReasons() {
        XCTAssertEqual(ControlRemovals.removed.count, 16)
        for (id, reason) in ControlRemovals.removed {
            XCTAssertTrue(isLegacy(id), id.rawValue)
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty, id.rawValue)
        }
    }

    func testSwitcherKeyPathsNameLegacyIDs() {
        let map = ControlLegacy.switcherKeyPaths
        XCTAssertEqual(map["disabledFeatures"]?.count, 14)
        XCTAssertEqual(map.count, 8 + 13 + 1)
        for ids in map.values { for id in ids { XCTAssertTrue(isLegacy(id), id.rawValue) } }
        XCTAssertTrue(ControlLegacy.internalKeys.contains("shortcuts.*.id"))
    }

    // MARK: Per table (tests 2, 3, 4, 6, replaces ⊆ legacy, parentOn)

    func testRegistryListsEachTableOnce() {
        let names = ControlRegistry.tables.map { String(describing: $0) }
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(names.allSatisfy { $0.hasSuffix("Controls") })
        XCTAssertTrue(ControlRegistry.tables.allSatisfy { !$0.surface.isEmpty && !$0.surface.hasSuffix(".") })
    }

    func testIDsAreUniqueAndStartWithTheirSurface() {
        var seen = Set<ControlID>()
        for (table, surface, spec) in specs {
            XCTAssertTrue(seen.insert(spec.id).inserted, "duplicate \(spec.id.rawValue)")
            XCTAssertTrue(spec.id.rawValue.hasPrefix(surface + "."), "\(table): \(spec.id.rawValue)")
        }
    }

    func testParentOnTargetsAreInTheSameTable() {
        for t in ControlRegistry.tables {
            let ids = Set(t.controls.map(\.id))
            for spec in t.controls {
                for case .parentOn(let parent) in spec.when {
                    XCTAssertTrue(ids.contains(parent), "\(spec.id.rawValue) → \(parent.rawValue)")
                }
            }
        }
    }

    func testReplacesAreLegacyIDsAndNeverRemoved() {
        let removed = Set(ControlRemovals.removed.keys)
        for (_, _, spec) in specs {
            for id in spec.replaces {
                XCTAssertTrue(isLegacy(id), "\(spec.id.rawValue) replaces unknown \(id.rawValue)")
                XCTAssertFalse(removed.contains(id), "\(id.rawValue) has a home and a removal reason")
            }
        }
    }

    func testEverySettingIsSearchableAndEntriesAreUnique() {
        var ids = Set<String>()
        for (_, _, spec) in specs {
            if spec.kind == .setting { XCTAssertNotNil(spec.search, spec.id.rawValue) }
            guard let search = spec.search else { continue }
            let entry = SettingsSearchEntry(spec, search: search)
            XCTAssertEqual(entry.id, spec.id.rawValue)
            XCTAssertEqual(entry.anchor, spec.id.rawValue)
            XCTAssertTrue(ids.insert(entry.id).inserted)
        }
    }

    func testMenuHomesAreCustomizableAndSlidersNeverInSubmenus() {
        for (_, _, spec) in specs {
            if spec.kind == .menuSlider, let menu = spec.menu {
                XCTAssertFalse(menu.location.lowercased().contains("submenu"), spec.id.rawValue)
                XCTAssertNotEqual(menu.customize, .threeWay, spec.id.rawValue)
            }
            for id in spec.replaces where id.rawValue.hasPrefix("l.menu.") && !id.rawValue.hasPrefix("l.menu.fixed.") {
                XCTAssertNotEqual(spec.menu?.customize ?? MenuCustomize.none, MenuCustomize.none, spec.id.rawValue)
            }
        }
    }

    // MARK: Skipped until the step-3 exit

    func testEveryLegacyIDHasAHomeOrARemovalReason() throws {
        throw XCTSkip("Totality is turned on at the 0.3 step-3 exit (R5-13).")
    }

    func testKeyCrossCheck() throws {
        throw XCTSkip("The key cross-check is turned on at the 0.3 step-3 exit (R5-13).")
    }

    /// The walker itself is exercised now, so step 3 only flips the skip.
    func testFixturesWalkIntoKeyPaths() {
        let displays = ConfigFixtures.keyPaths(ConfigFixtures.fullDisplays())
        XCTAssertTrue(displays.contains("perDisplay.*.identity.customName"))
        XCTAssertTrue(displays.contains("menu.showPanelShortcut.keyCode"))
        XCTAssertTrue(displays.contains("features"))
        XCTAssertFalse(displays.contains { $0.contains("unknown") })
        let modules = ConfigFixtures.keyPaths(ConfigFixtures.fullModules())
        XCTAssertTrue(modules.contains("modules.*.presence"))
        XCTAssertTrue(modules.contains("newModuleCards"))
        let awake = ConfigFixtures.keyPaths(ConfigFixtures.fullAwake())
        XCTAssertTrue(awake.contains("drives.volumes.*.firstWriteDone"))
        XCTAssertTrue(awake.contains("sessions.behavior.endAfterLockedHours"))
        XCTAssertTrue(ConfigFixtures.isCovered("perDisplay.*.identity.customName", by: ["perDisplay.*.identity"]))
        XCTAssertFalse(ConfigFixtures.isCovered("perDisplay.*.color", by: ["perDisplay.*.identity"]))
    }
}
