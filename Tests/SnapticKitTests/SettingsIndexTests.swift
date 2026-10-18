import XCTest
@testable import SnapticKit

private enum SearchTestTableA: ControlTable {
    static let surface = "t.a"
    static let controls: [ControlSpec] = [
        ControlSpec("t.a.battery", .setting, search: SearchSpec("Battery level", keywords: ["low", "power"], root: "awake")),
        ControlSpec("t.a.button", .button),
        ControlSpec("t.a.brightness", .setting,
                    search: SearchSpec("Brightness", root: "displays", route: SettingsRoute("displays.brightness"))),
        ControlSpec("t.a.advanced", .setting, search: SearchSpec("Appear active", root: "awake", sheet: "awake.advanced")),
    ]
}

private enum SearchTestTableB: ControlTable {
    static let surface = "t.b"
    static let controls: [ControlSpec] = [
        ControlSpec("t.b.display", .setting, search: SearchSpec("Keep the display on", root: "awake")),
        // A repeated id (the registry test rejects it; search keeps the first).
        ControlSpec("t.a.battery", .setting, search: SearchSpec("Duplicate", root: "awake")),
    ]
}

private enum RevealTestTable: ControlTable {
    static let surface = "t.r"
    static let controls: [ControlSpec] = [
        ControlSpec("t.r.top", .setting, search: SearchSpec("Top", root: "awake")),
        ControlSpec("t.r.mid", .setting, when: [.parentOn(ControlID("t.r.top"))], search: SearchSpec("Mid", root: "awake")),
        ControlSpec("t.r.leaf", .list, when: [.module(.awake), .parentOn(ControlID("t.r.mid"))],
                    search: SearchSpec("Leaf", root: "awake")),
        // A cycle never loops.
        ControlSpec("t.r.a", .setting, when: [.parentOn(ControlID("t.r.b"))]),
        ControlSpec("t.r.b", .setting, when: [.parentOn(ControlID("t.r.a"))]),
        ControlSpec("t.r.useAwake", .setting, keys: ["modules.*.enabled"], search: SearchSpec("Use Awake", root: "awake")),
    ]
}

private enum CoverageTestTable: ControlTable {
    static let surface = "t.c"
    static let controls: [ControlSpec] = [
        ControlSpec("t.c.setting", .setting),
        ControlSpec("t.c.button", .button),
        ControlSpec("t.c.nav", .navigation),
        ControlSpec("t.c.list", .list),
        ControlSpec("t.c.shortcut", .shortcut),
        ControlSpec("t.c.status", .statusAction),
        ControlSpec("t.c.menu", .menuItem),
        ControlSpec("t.c.rowAction", .button, when: [.perItem("rule")]),
        ControlSpec("t.c.perRule", .setting, when: [.perItem("rule")]),
        ControlSpec("t.c.perDisplay", .setting, when: [.perItem("display")]),
        ControlSpec("t.c.perDisplayButton", .button, when: [.perItem("display")]),
        ControlSpec("t.c.found", .button, search: SearchSpec("Found", root: "general")),
    ]
}

final class SettingsIndexTests: XCTestCase {
    private func entry(_ id: String, _ title: String, keywords: [String] = [], root: String) -> SettingsSearchEntry {
        SettingsSearchEntry(id: id, title: title, keywords: keywords, root: root, anchor: id)
    }

    private lazy var sample: [SettingsSearchEntry] = [
        entry("e1", "Battery level", keywords: ["low", "power"], root: "awake"),
        entry("e2", "Brightness", root: "displays"),
        entry("e3", "Keep the display on", root: "awake"),
        entry("e4", "Hardware contrast", root: "displays"),
        entry("e5", "Picture in Picture", root: "displays"),
        entry("e6", "Extra brightness", root: "displays"),
        entry("e7", "Café mode", root: "general"),
        entry("e8", "Thumbnail size", root: "windowSwitcher"),
    ]

    private func ids(_ query: String) -> [String] {
        SettingsSearch.rank(entries: sample, query: query).map(\.id)
    }

    // MARK: Entries from specs

    func testEntriesComeFromSearchSpecsOfOneRoot() {
        let awake = SettingsIndex.entries([SearchTestTableA.self, SearchTestTableB.self], root: "awake")
        XCTAssertEqual(awake.map(\.id), ["t.a.battery", "t.a.advanced", "t.b.display"])
        XCTAssertEqual(awake[0].title, "Battery level")
        XCTAssertEqual(awake[0].keywords, ["low", "power"])
        XCTAssertEqual(awake[1].sheet, "awake.advanced")
        for e in awake {
            XCTAssertEqual(e.id, e.anchor)
            XCTAssertEqual(e.root, "awake")
        }
        let displays = SettingsIndex.entries([SearchTestTableA.self], root: "displays")
        XCTAssertEqual(displays.map(\.id), ["t.a.brightness"])
        XCTAssertEqual(displays[0].route, SettingsRoute("displays.brightness"))
        XCTAssertTrue(SettingsIndex.entries([SearchTestTableA.self], root: "general").isEmpty)
        XCTAssertTrue(SettingsIndex.entries([], root: "awake").isEmpty)
    }

    func testEntryInitFromSpec() {
        let spec = ControlSpec("awake.page.batteryFloor", .setting)
        let e = SettingsSearchEntry(spec, search: SearchSpec("Battery level", keywords: ["low"], root: "awake",
                                                             route: nil, sheet: nil))
        XCTAssertEqual(e.id, "awake.page.batteryFloor")
        XCTAssertEqual(e.anchor, "awake.page.batteryFloor")
        XCTAssertEqual(e.title, "Battery level")
        XCTAssertNil(e.route)
    }

    /// Across every registered table, each searchable spec yields exactly one entry under its root, and the ids
    /// (= anchors) are unique.
    func testRegistryEntriesAreUniqueAcrossRoots() {
        let all = SettingsRootID.all.flatMap { SettingsIndex.entries(ControlRegistry.tables, root: $0) }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for e in all { XCTAssertEqual(e.id, e.anchor) }
        let searchable = ControlRegistry.tables.flatMap { $0.controls }.filter {
            guard let root = $0.search?.root else { return false }
            return SettingsRootID.all.contains(root)
        }
        XCTAssertEqual(Set(searchable.map(\.id.rawValue)).count, all.count)
    }

    // MARK: Assembly

    func testAllAssemblesEveryRootInSidebarOrderOnce() {
        let tables: [any ControlTable.Type] = [SearchTestTableA.self, SearchTestTableB.self]
        let all = SettingsIndex.all(tables, roots: ["displays", "awake"])
        XCTAssertEqual(all.map(\.id), ["t.a.brightness", "t.a.battery", "t.a.advanced", "t.b.display"])
        // A root without a sidebar item has nothing to reveal into.
        XCTAssertEqual(SettingsIndex.all(tables, roots: ["awake"]).map(\.id), ["t.a.battery", "t.a.advanced", "t.b.display"])
        XCTAssertTrue(SettingsIndex.all(tables, roots: []).isEmpty)
    }

    /// The real index: one entry per searchable spec, every entry's root is a sidebar item, and its route and sheet
    /// belong to that root (so `reveal` can reach them).
    func testRegistryIndexCrossCheck() {
        let all = SettingsIndex.all(ControlRegistry.tables)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        var specs: [String: ControlSpec] = [:]
        for table in ControlRegistry.tables {
            for spec in table.controls { specs[spec.id.rawValue] = specs[spec.id.rawValue] ?? spec }
        }
        let roots = Set(SettingsRootID.all)
        for entry in all {
            XCTAssertEqual(entry.anchor, entry.id)
            XCTAssertNotNil(specs[entry.id]?.search, entry.id)
            XCTAssertTrue(roots.contains(entry.root), entry.id)
            XCTAssertFalse(entry.title.trimmingCharacters(in: .whitespaces).isEmpty, entry.id)
            XCTAssertFalse(entry.keywords.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, entry.id)
            for page in [entry.route?.id, entry.sheet].compactMap({ $0 }) {
                XCTAssertEqual(SettingsLocation.resolve(page, roots: roots)?.root, entry.root, "\(entry.id) → \(page)")
            }
        }
        // Nothing searchable is dropped for naming a root the sidebar doesn't have.
        let searchable = specs.values.filter { $0.search != nil }
        XCTAssertEqual(searchable.count, all.count)
        for spec in searchable { XCTAssertTrue(roots.contains(spec.search?.root ?? ""), spec.id.rawValue) }
    }

    /// Step-3 exit "search finds every entry": every visible control on a Settings page or sheet has a search entry,
    /// or an exclusion with a reason.
    func testEveryVisibleSettingsControlIsSearchable() {
        XCTAssertEqual(SettingsIndexCoverage.missing(ControlRegistry.tables), [])
    }

    func testExclusionsHaveReasonsAndHostPagesHaveNoStaleOnes() {
        XCTAssertTrue(SettingsIndexCoverage.unsearchable.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertTrue(Set(SettingsIndexCoverage.unsearchable.keys).isDisjoint(with: SettingsIndexCoverage.awaitingSearch))
        // The host pages' own exclusions (H) name controls that exist, need an entry, and have none.
        let hostSurfaces = ["general.", "permissions.", "about.", "switcher.", "onboarding"]
        for (id, _) in SettingsIndexCoverage.unsearchable where hostSurfaces.contains(where: { id.hasPrefix($0) }) {
            guard let table = ControlRegistry.tables.first(where: { t in t.controls.contains { $0.id.rawValue == id } }),
                  let spec = table.controls.first(where: { $0.id.rawValue == id }) else {
                XCTFail("stale exclusion \(id)")
                continue
            }
            XCTAssertNil(spec.search, id)
            XCTAssertTrue(SettingsIndexCoverage.requiresSearch(spec, surface: table.surface), id)
        }
    }

    func testCoverageRules() {
        let missing = Set(SettingsIndexCoverage.missing([CoverageTestTable.self]).map { $0.components(separatedBy: ": ").last ?? "" })
        XCTAssertEqual(missing, ["t.c.setting", "t.c.button", "t.c.nav", "t.c.list", "t.c.shortcut", "t.c.perDisplay"])
        XCTAssertTrue(SettingsIndexCoverage.missing([CoverageTestTable.self]).allSatisfy { $0.hasPrefix("CoverageTestTable: ") })
        let setting = ControlSpec("x.setting", .setting)
        XCTAssertTrue(SettingsIndexCoverage.requiresSearch(setting, surface: "awake.page"))
        XCTAssertTrue(SettingsIndexCoverage.requiresSearch(setting, surface: "menubar.page"))
        XCTAssertTrue(SettingsIndexCoverage.requiresSearch(setting, surface: "displays.details"))
        for surface in ["menu", "menu.display.c", "menu.awake.item", "onboarding", "onboarding.displays", "displays.panel",
                        "awake.custom", "awake.rule", "awake.sessions", "displays.pip.editor", "displays.automations.hook"] {
            XCTAssertFalse(SettingsIndexCoverage.requiresSearch(setting, surface: surface), surface)
        }
    }

    func testMasterSwitch() {
        XCTAssertEqual(SettingsIndex.masterSwitch(root: "awake", in: [RevealTestTable.self]), "t.r.useAwake")
        XCTAssertNil(SettingsIndex.masterSwitch(root: "displays", in: [RevealTestTable.self]))
        let tables = ControlRegistry.tables
        XCTAssertEqual(SettingsIndex.masterSwitch(root: SettingsRootID.windowSwitcher, in: tables), "switcher.page.header")
        XCTAssertEqual(SettingsIndex.masterSwitch(root: SettingsRootID.displays, in: tables), "displays.root.useDisplays")
        XCTAssertNil(SettingsIndex.masterSwitch(root: SettingsRootID.general, in: tables))
        XCTAssertNil(SettingsIndex.masterSwitch(root: SettingsRootID.permissions, in: tables))
    }

    /// A route that names a row of a root page deep-links to that row (review ui F7).
    func testAnchorEntryForRowRoutes() {
        let entry = SettingsIndex.anchorEntry("awake.page.rules", root: SettingsRootID.awake, in: ControlRegistry.tables)
        XCTAssertEqual(entry?.anchor, "awake.page.rules")
        XCTAssertNil(entry?.route)
        XCTAssertNil(SettingsIndex.anchorEntry("awake.page.rules", root: SettingsRootID.displays, in: ControlRegistry.tables))
        XCTAssertNil(SettingsIndex.anchorEntry("awake.rules", root: SettingsRootID.awake, in: ControlRegistry.tables))
        XCTAssertEqual(SettingsIndex.anchorEntry("switcher.advanced.excludedApps", root: SettingsRootID.windowSwitcher,
                                                 in: ControlRegistry.tables)?.sheet, "switcher.advanced")
    }

    func testRevealFallbacksFollowParents() {
        let tables: [any ControlTable.Type] = [RevealTestTable.self]
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "t.r.leaf", in: tables), ["t.r.mid", "t.r.top"])
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "t.r.mid", in: tables), ["t.r.top"])
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "t.r.top", in: tables), [])
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "t.r.a", in: tables), ["t.r.b"])
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "nope", in: tables), [])
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "switcher.advanced.privateApps", in: ControlRegistry.tables),
                       ["switcher.advanced.protectPrivate"])
        XCTAssertEqual(SettingsIndex.revealFallbacks(for: "general.page.copyInstall", in: ControlRegistry.tables),
                       ["general.page.commandLine"])
        // Every parent named by a searchable spec is itself searchable, so a fallback is always a real row.
        for table in ControlRegistry.tables {
            for spec in table.controls where spec.search != nil {
                for parent in SettingsIndex.revealFallbacks(for: spec.id.rawValue, in: ControlRegistry.tables) {
                    XCTAssertNotNil(SettingsIndex.spec(parent, in: ControlRegistry.tables), "\(spec.id.rawValue) → \(parent)")
                }
            }
        }
    }

    func testPageTitlesAndLocation() {
        XCTAssertEqual(SettingsIndex.pageTitle("displays.color"), "Color")
        XCTAssertEqual(SettingsIndex.pageTitle("switcher.shortcuts"), "More Shortcuts")
        XCTAssertEqual(SettingsIndex.pageTitle("switcher.advanced"), "Advanced")
        XCTAssertEqual(SettingsIndex.pageTitle("displays.brightness.advanced"), "Advanced")
        XCTAssertEqual(SettingsIndex.pageTitle("displays.keyboard.shortcuts"), "Keyboard Shortcuts")
        XCTAssertNil(SettingsIndex.pageTitle("displays.unknown"))
        for (route, title) in [("displays.resolution", "Resolution"), ("displays.connection", "Connection"),
                               ("displays.matchTextSize", "Match Text Size"),
                               ("displays.virtual.editor", "Virtual Display")] {
            XCTAssertEqual(SettingsIndex.pageTitle(route), title)
        }
        let sheet = SettingsSearchEntry(id: "a", title: "Search", root: "windowSwitcher", anchor: "a", sheet: "switcher.advanced")
        XCTAssertEqual(SettingsIndex.location(of: sheet, rootTitle: "Window Switcher"), "Window Switcher › Advanced")
        let sub = SettingsSearchEntry(id: "b", title: "Gamma", root: "displays", route: SettingsRoute("displays.color"),
                                      anchor: "b", sheet: "displays.color.advanced")
        XCTAssertEqual(SettingsIndex.location(of: sub, rootTitle: "Displays"), "Displays › Color › Advanced")
        XCTAssertEqual(SettingsIndex.location(of: sub, rootTitle: "Displays", routeTitle: "Colour"), "Displays › Colour › Advanced")
        let plain = SettingsSearchEntry(id: "c", title: "Open at login", root: "general", anchor: "c")
        XCTAssertEqual(SettingsIndex.location(of: plain, rootTitle: "General"), "General")
        let unknown = SettingsSearchEntry(id: "d", title: "X", root: "displays", route: SettingsRoute("displays.zzz"), anchor: "d")
        XCTAssertEqual(SettingsIndex.location(of: unknown, rootTitle: "Displays"), "Displays")
    }

    /// The host pages' rows rank where a person would look for them.
    func testRegistryRankingFindsHostRows() {
        let all = SettingsIndex.all(ControlRegistry.tables)
        func top(_ query: String, _ n: Int = 3) -> [String] {
            Array(SettingsSearch.rank(entries: all, query: query).prefix(n).map(\.id))
        }
        XCTAssertTrue(top("open at login").contains("general.page.openAtLogin"))
        XCTAssertTrue(top("launch at login").contains("general.page.openAtLogin"))
        XCTAssertTrue(top("thumbnail size").contains("switcher.page.thumbnailSize"))
        XCTAssertTrue(top("safe mode").contains("general.advanced.safeMode"))
        XCTAssertTrue(top("screen rec").contains("permissions.page.screenRecording"))
        XCTAssertTrue(top("acknowledg").contains("about.page.acknowledgements"))
        XCTAssertTrue(top("gather").contains("switcher.shortcuts.gather"))
        XCTAssertTrue(SettingsSearch.rank(entries: all, query: "hotkey").map(\.id).contains("switcher.page.shortcut"))
        XCTAssertTrue(SettingsSearch.rank(entries: all, query: "alt-tab").map(\.id).contains("switcher.page.header"))
    }

    // MARK: Ranking

    func testTitlePrefixFirst() {
        XCTAssertEqual(ids("bright"), ["e2", "e6"])
        XCTAssertEqual(ids("BRIGHT"), ["e2", "e6"])
        XCTAssertEqual(ids("display"), ["e3"])
        XCTAssertEqual(ids("keep disp"), ["e3"])
        XCTAssertEqual(ids("disp keep"), ["e3"])
    }

    func testTieBreakStartsWithThenShorterThenOrder() {
        XCTAssertEqual(ids("b"), ["e2", "e1", "e6"])
    }

    func testKeywordsAfterTitle() {
        XCTAssertEqual(ids("low"), ["e1"])
        XCTAssertEqual(ids("battery pow"), ["e1"])
    }

    func testWordPrefixOnlyNotSubstring() {
        XCTAssertEqual(ids("rightness"), [])
        XCTAssertEqual(ids("ness"), [])
    }

    func testDiacriticsAndCase() {
        XCTAssertEqual(ids("CAFE"), ["e7"])
        XCTAssertEqual(ids("café"), ["e7"])
        XCTAssertEqual(ids("cafe\u{301}"), ["e7"])
    }

    func testSynonyms() {
        XCTAssertEqual(ids("monitor"), ["e4"])
        XCTAssertEqual(ids("ddc"), ["e4"])
        XCTAssertEqual(ids("pip"), ["e5"])
        XCTAssertEqual(ids("xdr"), ["e6"])
        XCTAssertEqual(ids("alt-tab"), ["e8"])
        XCTAssertEqual(ids("⌥⇥"), ["e8"])
        // Synonyms that name a page list that page's settings.
        XCTAssertEqual(ids("caffeinate"), ["e1", "e3"])
        XCTAssertEqual(ids("insomnia"), ["e1", "e3"])
        XCTAssertEqual(ids("prevent sl"), ["e1", "e3"])
    }

    func testMoreSynonyms() {
        let entries = [
            entry("login", "Open at login", root: "general"),
            entry("key", "Shortcut", root: "windowSwitcher"),
            entry("reset", "Reset All Settings", root: "general"),
            entry("restore", "Restore Awake Defaults", root: "awake"),
            entry("vol", "Volume", root: "displays"),
            entry("cli", "Command-line control", keywords: ["cli"], root: "general"),
        ]
        func find(_ q: String) -> [String] { SettingsSearch.rank(entries: entries, query: q).map(\.id) }
        XCTAssertEqual(find("launch at login"), ["login"])
        XCTAssertEqual(find("startup"), ["login"])
        XCTAssertEqual(find("hotkey"), ["key"])
        XCTAssertEqual(find("keyboard shortcut"), ["key"])
        XCTAssertEqual(find("reset"), ["reset", "restore"])
        XCTAssertEqual(find("restore defaults"), ["restore", "reset"])
        XCTAssertEqual(find("sound"), ["vol"])
        XCTAssertEqual(find("terminal"), ["cli"])
    }

    func testDirectMatchesRankAboveSynonyms() {
        let entries = [
            entry("a", "Hardware contrast", root: "displays"),
            entry("b", "Use DDC", root: "displays"),
        ]
        XCTAssertEqual(SettingsSearch.rank(entries: entries, query: "ddc").map(\.id), ["b", "a"])
    }

    func testShortQueriesDontExpandSynonyms() {
        XCTAssertEqual(ids("s"), ["e8"])
        XCTAssertEqual(ids("pi"), ["e5"])
    }

    func testEmptyAndOversizedQueries() {
        XCTAssertEqual(ids(""), [])
        XCTAssertEqual(ids("   "), [])
        XCTAssertEqual(ids("—…"), [])
        XCTAssertEqual(ids(String(repeating: "b", count: 10_000)), [])
        XCTAssertEqual(ids("b b b b b b b b b b b b"), ["e2", "e1", "e6"])
    }

    func testDuplicateIDsInInputAppearOnce() {
        let e = entry("x", "Battery level", root: "awake")
        XCTAssertEqual(SettingsSearch.rank(entries: [e, e], query: "batt").map(\.id), ["x"])
    }

    // MARK: Folding

    func testFoldTables() {
        XCTAssertEqual(SettingsSearch.foldTableSizes.latin1, 64)
        XCTAssertEqual(SettingsSearch.foldTableSizes.latinExtendedA, 128)
        XCTAssertEqual(SettingsSearch.fold("ÀÉÎÕÜ ß æ Œ ł"), "aeiou ss ae oe l")
        XCTAssertEqual(SettingsSearch.fold("ÐÑØÝÞÿ"), "dnoythy")
        XCTAssertEqual(SettingsSearch.fold("Ďēğħıĳĵķŀńōŕśţūŵŷžſ"), "deghiijjklnorstuwyzs")
        XCTAssertEqual(SettingsSearch.fold("e\u{301}"), "e")
        XCTAssertEqual(SettingsSearch.fold("ΩMEGA"), "ωmega")
        XCTAssertEqual(SettingsSearch.fold("1512 × 982"), "1512   982")
    }

    func testWords() {
        XCTAssertEqual(SettingsSearch.words("Restore Displays — Defaults…"), ["restore", "displays", "defaults"])
        XCTAssertEqual(SettingsSearch.words("Mirror for “DELL”"), ["mirror", "for", "dell"])
        XCTAssertEqual(SettingsSearch.words("⌥⇥ alt-tab"), ["⌥⇥", "alt", "tab"])
        XCTAssertEqual(SettingsSearch.words(""), [])
        XCTAssertEqual(SettingsSearch.rootWords("windowSwitcher"), ["window", "switcher"])
        XCTAssertEqual(SettingsSearch.rootWords("menuBar"), ["menu", "bar"])
        XCTAssertEqual(SettingsSearch.rootWords("awake"), ["awake"])
    }

    /// Random queries over the sample never trap and only return sample entries, once each.
    func testSeededRankNeverTraps() {
        var g = SeededGenerator(seed: 0x5EA2C4)
        let alphabet = Array("abcdeilmnoprstuvwxyzéßŒ -—…⌥⇥×1")
        for _ in 0..<2000 {
            var q = ""
            for _ in 0..<Int(g.next() % 16) { q.append(alphabet[Int(g.next() % UInt64(alphabet.count))]) }
            let result = SettingsSearch.rank(entries: sample, query: q)
            XCTAssertEqual(Set(result.map(\.id)).count, result.count)
            XCTAssertTrue(result.allSatisfy { r in sample.contains(r) })
        }
    }
}
