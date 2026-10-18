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
