import XCTest
@testable import SnapticKit

/// PLAN 0.3 §4.8 tests (R5-13): the per-table tests, totality (test 1's home check) and the key cross-check (test 5),
/// all on since the step-3 exit.
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
        XCTAssertEqual(ControlRemovals.removed.count, 19)
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

    // MARK: Menu contributor coverage (R5-13, `--selftest-controls`; review5 code N1)

    private var removedIDs: Set<LegacyControlID> { Set(ControlRemovals.removed.keys) }

    /// What a complete set of contributors declares: every frozen menu id that is neither removed nor a family.
    private var covering: [String] {
        ControlLegacy.displayMenuItemIDs.filter {
            !$0.hasSuffix("*") && !removedIDs.contains(LegacyControlID(rawValue: "l.menu." + $0))
        }
    }

    func testDisplayMenuItemIDsAreTheFrozenMenuRows() {
        let ids = ControlLegacy.displayMenuItemIDs
        XCTAssertEqual(ids.count, 46)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains("c.brightness.slider"))
        XCTAssertTrue(ids.contains("a.custom.*"))
        XCTAssertFalse(ids.contains { $0.hasPrefix("fixed.") || $0.hasPrefix("l.") })
    }

    func testMenuCoverageAcceptsACompleteSplit() {
        let ids = covering
        XCTAssertGreaterThan(ids.count, 30)
        let half = ids.count / 2
        let contributed = ["A": Array(ids[..<half]), "B": Array(ids[half...]), "Families": []]
        XCTAssertEqual(ControlLegacy.menuCoverageProblems(contributed: contributed, removed: removedIDs), [])
        // Extra 0.3-only ids are fine.
        let extra = ["A": ids + ["d.newIn03"]]
        XCTAssertEqual(ControlLegacy.menuCoverageProblems(contributed: extra, removed: removedIDs), [])
    }

    func testMenuCoverageReportsMissingDuplicateRemovedAndEmpty() {
        var ids = covering
        let missing = ids.removeLast()
        let removed = ControlLegacy.displayMenuItemIDs.first {
            removedIDs.contains(LegacyControlID(rawValue: "l.menu." + $0))
        } ?? ""
        XCTAssertFalse(removed.isEmpty)
        let problems = ControlLegacy.menuCoverageProblems(
            contributed: ["A": ids, "B": [ids[0], removed, ""]], removed: removedIDs)
        XCTAssertEqual(problems.count, 4, problems.joined(separator: "\n"))
        XCTAssertTrue(problems.contains { $0.contains("0.2 menu item \(missing) has no contributor") })
        XCTAssertTrue(problems.contains { $0.contains("\(ids[0]) is declared by both A and B") })
        XCTAssertTrue(problems.contains { $0.contains("which ControlRemovals lists as removed") })
        XCTAssertTrue(problems.contains { $0.contains("B declares an empty menu item id") })
        XCTAssertEqual(problems, problems.sorted())
    }

    func testMenuCoverageNeedsNoContributorForRemovedOrFamilyIDs() {
        let problems = ControlLegacy.menuCoverageProblems(contributed: [:], removed: removedIDs)
        XCTAssertEqual(problems.count, covering.count)
        XCTAssertFalse(problems.contains { $0.contains("a.custom.*") || $0.contains(" d.sleepPrevention ") })
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
        for (_, surface, spec) in specs {
            // Settings on surfaces outside Settings (the Custom… panel, 0.3.1 B7) have no entry.
            if spec.kind == .setting && SettingsIndexCoverage.isSettingsSurface(surface) {
                XCTAssertNotNil(spec.search, spec.id.rawValue)
            }
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

    /// 0.3.3: lid-closed mode's opt-in left Awake › Advanced for the Awake page, with a second switch on the Menu Bar
    /// page; both show on the same Macs, and search opens each on its page, not in a sheet. The leftover rows stay
    /// under Advanced › Other Apps.
    func testLidClosedOptInLivesOnTheAwakeAndMenuBarPages() {
        let owners = specs.map { $0.spec }.filter { $0.keys.contains("features.lidClosed") }
        XCTAssertEqual(Set(owners.map { $0.id.rawValue }), ["awake.page.lidClosed", "menubar.page.awakeLidClosed"])
        for spec in owners {
            XCTAssertEqual(spec.kind, .setting, spec.id.rawValue)
            XCTAssertEqual(Set(spec.when), [.module(.awake), .hardware(.battery)], spec.id.rawValue)
            XCTAssertNotNil(spec.search, spec.id.rawValue)
            XCTAssertNil(spec.search?.sheet, spec.id.rawValue)
        }
        XCTAssertEqual(owners.first { $0.id.rawValue == "awake.page.lidClosed" }?.search?.root, "awake")
        XCTAssertEqual(owners.first { $0.id.rawValue == "menubar.page.awakeLidClosed" }?.search?.root, "menuBar")
        let learnMore = AwakePageControls.controls.first { $0.id.rawValue == "awake.page.lidBundleLearnMore" }
        XCTAssertNotNil(learnMore)
        XCTAssertTrue(learnMore?.when.contains(.parentOn(ControlID("awake.page.lidClosed"))) ?? false)
        let advanced = Set(AwakeAdvancedSheetControls.controls.map { $0.id.rawValue }.filter { $0.contains(".lid") })
        XCTAssertEqual(advanced, ["awake.advanced.lidRestore", "awake.advanced.lidKeepOff", "awake.advanced.lidDismiss"])
    }

    // MARK: Totality and the key cross-check (step-3 exit)

    /// Test 1: every frozen 0.2 id has a home (some spec's `replaces`) or a removal reason, never both.
    func testEveryLegacyIDHasAHomeOrARemovalReason() {
        var homed = Set<LegacyControlID>()
        for (_, _, spec) in specs { homed.formUnion(spec.replaces) }
        let removed = ControlRemovals.removed
        var missing: [String] = []
        for id in ControlLegacy.ids {
            let home = homed.contains(id), gone = removed[id] != nil
            if !home && !gone { missing.append(id.rawValue) }
            XCTAssertFalse(home && gone, "\(id.rawValue) has a home and a removal reason")
        }
        for id in missing { XCTFail("no home or removal reason: \(id)") }
        XCTAssertTrue(homed.isSubset(of: legacy))
        XCTAssertTrue(Set(removed.keys).isSubset(of: legacy))
    }

    /// Test 5: every leaf key path of the full fixtures is declared by some spec's `keys` (or an ancestor of it is)
    /// or is internal state.
    func testKeyCrossCheck() {
        var declared = ControlLegacy.internalKeys
        for (_, _, spec) in specs { declared.formUnion(spec.keys) }
        let configs: [(String, Any)] = [("DisplaysConfig", ConfigFixtures.fullDisplays()),
                                        ("ModulesConfig", ConfigFixtures.fullModules()),
                                        ("AwakeConfig", ConfigFixtures.fullAwake())]
        for (name, value) in configs {
            let paths = ConfigFixtures.keyPaths(value)
            XCTAssertFalse(paths.isEmpty, name)
            let leaves = paths.filter { path in !paths.contains { $0.hasPrefix(path + ".") } }
            for path in leaves.sorted() where !ConfigFixtures.isCovered(path, by: declared) {
                XCTFail("\(name): no control declares \(path) and it isn't in ControlLegacy.internalKeys")
            }
        }
    }

    /// The fixtures reach into every list (one element each), so the cross-check sees list element fields.
    func testFixturesFillEveryList() {
        let displays = ConfigFixtures.keyPaths(ConfigFixtures.fullDisplays())
        for path in ["perDisplay.*.ddc.inputs.*.name", "perDisplay.*.pip.configurations.*.filters.*.kind",
                     "virtualScreens.screens.*.associations.*.target", "layouts.layouts.*.displays.*.identity.tier1",
                     "automation.hooks.*.command.arguments", "automation.actions.*.shortcut.keyCode",
                     "management.protection.*.displays.*.mode.pixelWidth", "safety.keptModes.*.modes.*.ioModeID",
                     "keys.inputSlots.*.display", "pip.luts.*.size"] {
            XCTAssertTrue(displays.contains(path), path)
        }
        let awake = ConfigFixtures.keyPaths(ConfigFixtures.fullAwake())
        XCTAssertTrue(awake.contains("triggers.triggers.*.criteria.*.criterion.usbDevice.serialHash"))
        XCTAssertTrue(awake.contains("sessions.presets.*.kind.untilIdle.maxSeconds"))
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
