import XCTest
@testable import SnapticKit

/// 0.5 K5: Dock Previews' control tables (§4.17 to §4.19), the Menu Bar page's Dock row, the §4.21 verb × state
/// table and the §4.24 canonical strings.
final class DockControlsTests: XCTestCase {
    private let tables: [any ControlTable.Type] = [
        DockPageControls.self, DockAdvancedSheetControls.self, DockMenuRowsControls.self,
    ]

    /// The shared privacy keys (§4.10): the switcher's store, which neither Dock restore touches.
    private let privacyKeys: Set<String> = ["protectPrivateWindows", "privateBundleIDs"]

    private func spec(_ id: String) -> ControlSpec? {
        ControlRegistry.tables.flatMap { $0.controls }.first { $0.id.rawValue == id }
    }

    // MARK: Registry

    func testIDsAreUniqueAcrossEveryTable() {
        var seen: Set<String> = []
        for t in ControlRegistry.tables {
            for spec in t.controls {
                XCTAssertTrue(seen.insert(spec.id.rawValue).inserted, "duplicate id \(spec.id.rawValue)")
            }
        }
        for t in tables {
            for spec in t.controls { XCTAssertTrue(spec.id.rawValue.hasPrefix(t.surface + "."), spec.id.rawValue) }
        }
    }

    func testEveryTableIsRegistered() {
        let registered = ControlRegistry.tables.map { String(describing: $0) }
        for t in tables { XCTAssertTrue(registered.contains(String(describing: t)), String(describing: t)) }
        XCTAssertEqual(Set(registered).count, registered.count)
    }

    /// The Menu Bar page's Dock Previews row (§4.19, H1): a presence choice shown only while the module is on.
    func testDockPresenceIsOnTheMenuBarPage() {
        let row = MenuBarPageControls.controls.first { $0.id.rawValue == "menubar.page.dockPresence" }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.kind, .setting)
        XCTAssertEqual(row?.when, [.module(.dockPreviews)])
        XCTAssertEqual(row?.keys, ["modules.*.presence"])
        XCTAssertNotNil(row?.search)
        XCTAssertTrue(row?.replaces.isEmpty ?? false)
        // It sits right after Hidden Icons' row.
        let ids = MenuBarPageControls.controls.map(\.id.rawValue)
        if let icons = ids.firstIndex(of: "menubar.page.iconsPresence"),
           let dock = ids.firstIndex(of: "menubar.page.dockPresence") {
            XCTAssertEqual(dock, icons + 1)
        } else {
            XCTFail("iconsPresence or dockPresence missing")
        }
    }

    func testMasterSwitch() {
        XCTAssertEqual(SettingsIndex.masterSwitch(root: SettingsRootID.dockPreviews, in: ControlRegistry.tables),
                       "dock.page.useDockPreviews")
        XCTAssertEqual(SettingsIndex.masterSwitch(root: SettingsRootID.dockPreviews, in: tables),
                       "dock.page.useDockPreviews")
    }

    // MARK: Search

    func testSettingsSurfacesSearchIntoDockPreviews() {
        let roots = Set(SettingsRootID.all)
        for t in [DockPageControls.self, DockAdvancedSheetControls.self] as [any ControlTable.Type] {
            XCTAssertTrue(SettingsIndexCoverage.isSettingsSurface(t.surface), t.surface)
            for spec in t.controls {
                guard let search = spec.search else { continue }
                XCTAssertEqual(search.root, SettingsRootID.dockPreviews, spec.id.rawValue)
                for page in [search.route?.id, search.sheet].compactMap({ $0 }) {
                    XCTAssertEqual(SettingsLocation.resolve(page, roots: roots)?.root, SettingsRootID.dockPreviews,
                                   page)
                }
            }
        }
        for spec in DockAdvancedSheetControls.controls where spec.search != nil {
            XCTAssertEqual(spec.search?.sheet, DockAdvancedSheetControls.sheet, spec.id.rawValue)
        }
        XCTAssertEqual(SettingsIndexCoverage.missing(tables), [])
        XCTAssertEqual(SettingsIndexCoverage.missing([MenuBarPageControls.self]), [])
        XCTAssertFalse(SettingsIndexCoverage.isSettingsSurface(DockMenuRowsControls.surface))
    }

    func testSearchFindsThePageFromOtherToolsNames() {
        let all = SettingsIndex.all(ControlRegistry.tables)
        for query in ["dockdoor", "hyperdock", "window preview"] {
            let ids = SettingsSearch.rank(entries: all, query: query).map(\.id)
            XCTAssertTrue(ids.contains("dock.page.useDockPreviews"), query)
        }
    }

    // MARK: Conditions and keys

    /// Everything but the master switch needs the module; status actions and menu rows name their state.
    func testConditions() {
        for t in tables {
            for spec in t.controls where spec.id.rawValue != "dock.page.useDockPreviews" {
                XCTAssertTrue(spec.when.contains(.module(.dockPreviews)), spec.id.rawValue)
            }
        }
        XCTAssertEqual(spec("dock.page.useDockPreviews")?.when, [])
        XCTAssertEqual(spec("dock.page.useDockPreviews")?.keys, ["modules.*.enabled"])
        let states: [(String, ControlState)] = [
            ("dock.page.openPrivacy", .dockNeedsPermission), ("dock.page.tryAgain", .dockUnreadable),
            ("dock.page.otherToolAdvanced", .dockOtherTool), ("dock.page.voiceOverAdvanced", .dockVoiceOver),
            ("dock.page.resume", .dockCommandPause), ("dock.page.thumbnailsPrivacy", .screenRecordingMissing),
            ("dock.page.relaunch", .dockBreakerTripped), ("dock.page.crashGuardTryAgain", .dockCrashGuard),
            ("menu.dock.openPrivacy", .dockNeedsPermission), ("menu.dock.pause", .dockWorking),
            ("menu.dock.resume", .dockCommandPause),
        ]
        for (id, state) in states { XCTAssertTrue(spec(id)?.when.contains(.state(state)) == true, id) }
        for id in ["dock.page.crashGuardTryAgain"] {
            XCTAssertTrue(spec(id)?.when.contains(.perItem("windowFeature")) == true, id)
        }
        for id in ["dock.page.clickActionsLock", "dock.advanced.killSwitch"] {
            XCTAssertTrue(spec(id)?.when.contains(.perItem("killSwitch")) == true, id)
        }
        XCTAssertTrue(spec("dock.advanced.privateApps")?.when
                        .contains(.parentOn(ControlID("dock.advanced.protectPrivate"))) == true)
        for spec in DockPageControls.controls where spec.kind == .statusAction {
            XCTAssertNil(spec.search, spec.id.rawValue)
            XCTAssertTrue(spec.keys.isEmpty, spec.id.rawValue)
        }
    }

    /// The page's Restore Defaults… covers every exported Dock setting; the sheet's covers only its own rows. Neither
    /// touches the shared privacy keys (§4.10, §4.18).
    func testRestoreKeys() {
        XCTAssertEqual(Set(spec("dock.page.restore")?.keys ?? []), Set(DockConfig.exportedKeys))
        let advancedRows = DockAdvancedSheetControls.controls
            .filter { $0.kind == .setting || $0.kind == .list }.flatMap(\.keys)
        XCTAssertEqual(Set(spec("dock.advanced.restore")?.keys ?? []), Set(advancedRows).subtracting(privacyKeys))
        for id in ["dock.page.restore", "dock.advanced.restore"] {
            XCTAssertTrue(Set(spec(id)?.keys ?? []).isDisjoint(with: privacyKeys), id)
        }
        // The privacy rows bind the same keys as the switcher's (one store, two sheets).
        let switcher = SwitcherAdvancedSheetControls.controls.flatMap(\.keys)
        XCTAssertTrue(privacyKeys.isSubset(of: Set(switcher)))
    }

    func testEveryDockSettingHasAControl() {
        let declared = Set(tables.flatMap { $0.controls }.flatMap(\.keys))
        let paths = ConfigFixtures.keyPaths(ConfigFixtures.fullDock())
        XCTAssertFalse(paths.isEmpty)
        let leaves = paths.filter { path in !paths.contains { $0.hasPrefix(path + ".") } }
        for path in leaves { XCTAssertTrue(ConfigFixtures.isCovered(path, by: declared), path) }
    }

    func testMenuRowsArentCustomizable() {
        XCTAssertEqual(DockMenuRowsControls.controls.map(\.id.rawValue),
                       ["menu.dock.status", "menu.dock.openPrivacy", "menu.dock.pause", "menu.dock.resume",
                        "menu.dock.settings"])
        for spec in DockMenuRowsControls.controls {
            XCTAssertEqual(spec.kind, .menuItem, spec.id.rawValue)
            XCTAssertEqual(spec.menu?.customize, MenuCustomize.none, spec.id.rawValue)
            XCTAssertTrue(spec.replaces.isEmpty, spec.id.rawValue)
            XCTAssertNil(spec.search, spec.id.rawValue)
        }
    }

    /// New in 0.5: nothing in the Dock tables replaces an earlier control.
    func testNothingReplacesAnEarlierControl() {
        for t in tables { for spec in t.controls { XCTAssertTrue(spec.replaces.isEmpty, spec.id.rawValue) } }
    }

    // MARK: Verb × state (§4.21; G3-1)

    /// Each cell of §4.21's table, written out: `resume` is checked with and without a held command pause.
    func testVerbByStateTable() {
        typealias Row = (DockStatusCell, DockPauseCell, DockResumeCell, DockResumeCell)
        let expected: [DockPageRow: Row] = [
            .killSwitch: (.unknownCommand, .unknownCommand, .unknownCommand, .unknownCommand),
            .off: (.unknownCommand, .unknownCommand, .unknownCommand, .unknownCommand),
            .starting: (.answers(state: .starting, reason: nil), .pauses, .notPaused, .cleared),
            .safeMode: (.answers(state: .paused, reason: .safeMode), .refused(.safeMode), .refused(.safeMode),
                        .refused(.safeMode)),
            .needsPermission: (.answers(state: .needsPermission, reason: nil), .refused(.needsPermission),
                               .notPaused, .cleared),
            .dockUnreadable: (.answers(state: .unavailable, reason: .dockUnreadable), .pauses, .notPaused, .cleared),
            .otherTool: (.answers(state: .paused, reason: .otherTool), .refused(.otherTool), .refused(.otherTool),
                         .refused(.otherTool)),
            .voiceOver: (.answers(state: .paused, reason: .voiceOver), .refused(.voiceOver), .refused(.voiceOver),
                         .refused(.voiceOver)),
            .pausedByCommand: (.answers(state: .paused, reason: .command), .pauses, .onAgain, .onAgain),
            .working: (.answers(state: .on, reason: nil), .pauses, .notPaused, .notPaused),
        ]
        XCTAssertEqual(expected.count, DockPageRow.allCases.count)
        for row in DockPageRow.allCases {
            let cells = DockCommandGrammar.cells(row)
            guard let e = expected[row] else { XCTFail("\(row)"); continue }
            XCTAssertEqual(cells.row, row)
            XCTAssertEqual(cells.status, e.0, "\(row) status")
            XCTAssertEqual(cells.pause, e.1, "\(row) pause")
            XCTAssertEqual(cells.resume, e.2, "\(row) resume")
            XCTAssertEqual(cells.resumeHeld, e.3, "\(row) resume with a held pause")
        }
    }

    /// The table's shape: rows 1 and 2 answer nothing; `status` always answers otherwise, with the row's own state
    /// and reason; refusals are exit 5 for `pause` and `resume` only; a held pause is cleared exactly where it can
    /// be held without being the row (Starting, row 4, row 5).
    func testVerbByStateInvariants() {
        for row in DockPageRow.allCases {
            let cells = DockCommandGrammar.cells(row)
            if !row.registersVerbs {
                XCTAssertEqual(cells.status, .unknownCommand, "\(row)")
                XCTAssertEqual(cells.pause, .unknownCommand, "\(row)")
                XCTAssertEqual(cells.resume, .unknownCommand, "\(row)")
                XCTAssertEqual(cells.resumeHeld, .unknownCommand, "\(row)")
                continue
            }
            XCTAssertEqual(cells.status, .answers(state: row.state ?? .on, reason: row.reason), "\(row)")
            XCTAssertNotNil(row.state, "\(row)")
            XCTAssertNotEqual(cells.pause, .unknownCommand, "\(row)")
            XCTAssertNotEqual(cells.resume, .unknownCommand, "\(row)")
            let refusesBoth = [DockPageRow.safeMode, .otherTool, .voiceOver].contains(row)
            if case .refused(let refusal) = cells.pause, refusal != .needsPermission {
                XCTAssertTrue(refusesBoth, "\(row)")
                XCTAssertEqual(cells.resume, .refused(refusal), "\(row)")
                XCTAssertEqual(cells.resumeHeld, .refused(refusal), "\(row)")
            } else {
                XCTAssertTrue(!refusesBoth, "\(row)")
            }
            let clears = [DockPageRow.starting, .needsPermission, .dockUnreadable].contains(row)
            XCTAssertEqual(cells.resumeHeld == .cleared, clears, "\(row)")
            // Every non-refused resume answers exit 0 with a line; every refused one has none.
            for cell in [cells.resume, cells.resumeHeld] {
                if case .refused = cell {
                    XCTAssertNil(DockCommandGrammar.resumeReply(cell), "\(row)")
                } else {
                    XCTAssertNotNil(DockCommandGrammar.resumeReply(cell), "\(row)")
                }
            }
        }
        for refusal in DockCLIRefusal.allCases { XCTAssertEqual(refusal.exitCode, ControlExit.unavailable) }
        XCTAssertEqual(ControlExit.unavailable, 5)
        XCTAssertEqual(ControlExit.usage, 2)
        XCTAssertEqual(DockPageRow.allCases.compactMap(\.number), Array(1...9))
    }

    // MARK: Canonical strings (§4.24; P3-1)

    /// The repository root (this file is Tests/SnapticKitTests/…), when the app sources are next to the tests.
    private static var repositoryRoot: URL? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/SnapticKit")
        return FileManager.default.fileExists(atPath: sources.path) ? root : nil
    }

    /// §4's quoted strings as the sources spell them: interpolations in their source form. K5 lists its own (§4.18's
    /// search titles and §4.21's CLI lines); A4a, A4b, A6b, A7 and A8 append theirs as they land them.
    private static let canonical: [String] = [
        // §4.21: help, replies, usage and refusals.
        #"State, pause reason and cache counts (never names)"#,
        #"Pause Dock Previews and its Dock click actions for a while (1 h if no time is given)"#,
        #"Resume Dock Previews and its Dock click actions"#,
        #"Dock Previews is paused until \(end)."#,
        #"Dock Previews is on again."#,
        #"Dock Previews’ pause is cleared."#,
        #"Dock Previews isn’t paused."#,
        #"Usage error. Run “snaptic help dock”."#,
        #"Dock Previews is paused in Safe Mode."#,
        #"Dock Previews needs \(paneName(.accessibility)). Open Snaptic Settings › Permissions."#,
        #"Dock Previews is paused while another Dock preview app runs. Choose Run Both Anyway in Dock "#
            + #"Previews’ Advanced settings to use both."#,
        #"Dock Previews is paused while VoiceOver is on."#,
        // §4.17 and §4.18: the rows the search index names.
        #"Use Dock Previews"#,
        #"Show previews after"#,
        #"Card size"#,
        #"Window thumbnails"#,
        #"Include minimized and hidden windows"#,
        #"Windows on other Spaces"#,
        #"When you click the active app in the Dock"#,
        #"Restore all minimized windows"#,
        #"Sort windows by"#,
        #"Keyboard shortcuts in previews"#,
        #"Apps with no open windows"#,
        #"When another app shows Dock previews"#,
        #"Show previews while VoiceOver is on"#,
        #"Apps hidden from Dock previews"#,
        #"Protect private windows"#,
        #"Never show thumbnails for"#,
        // §4.3: A4a's cards.
        #"No open windows"#,
        #"No windows shown"#,
        #"Its windows are minimized, hidden, or on other Spaces."#,
        #"Windows can’t be read right now"#,
        #"Window on another Space"#,
        #"More windows…"#,
        #"Full screen"#,
        #"On another Space"#,
    ]

    /// Every listed string is a whole literal somewhere in the app or Kit sources, so a reworded string fails here
    /// until the plan and the code agree again.
    func testEveryCanonicalStringIsInTheSources() throws {
        guard let root = Self.repositoryRoot else { throw XCTSkip("Sources aren't next to the tests.") }
        let sources = root.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return XCTFail("can't list \(sources.path)")
        }
        var text = ""
        for case let url as URL in walker where url.pathExtension == "swift" {
            text += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        XCTAssertEqual(Set(Self.canonical).count, Self.canonical.count, "a string is listed twice")
        for string in Self.canonical {
            XCTAssertTrue(text.contains("\"" + string + "\""), "§4.24 string not in the sources: \(string)")
        }
    }
}
