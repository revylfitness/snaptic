import XCTest
@testable import SnapticKit

final class LayoutPresetModelTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }
    private func id(_ n: Int) -> StableID {
        let digits = String(n)
        return StableID(rawValue: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - digits.count) + digits)!
    }
    private func ident(_ t1: String?, _ t2: String? = "uuid") -> LayoutDisplayIdentity { LayoutDisplayIdentity(tier1: t1, tier2: t2) }
    private let mode = ModeRef(ioModeID: 3, pixelWidth: 3024, pixelHeight: 1964, pointWidth: 1512, pointHeight: 982, refreshMilliHz: 120_000)

    /// A stand-in digest (the app uses SHA-256); any injective-enough function works for the logic.
    private func digest(_ d: Data) -> String { d.base64EncodedString() }

    private func layout(_ n: Int, _ displays: [DisplayKey: SavedDisplaySettings], auto: LayoutAutoApply = .whenIncludes,
                        priority: Int = 0, name: String = "L") -> SavedLayout {
        SavedLayout(id: id(n), name: name, displays: displays, autoApply: auto, priority: priority)
    }

    func testMatchTier1AndTier2() {
        let l = layout(1, [key("a"): SavedDisplaySettings(identity: ident("t1a")), key("b"): SavedDisplaySettings(identity: ident(nil, "u-b"))])
        let liveOK = [LiveLayoutDisplay(key: key("a"), identity: ident("t1a")), LiveLayoutDisplay(key: key("b"), identity: ident(nil, "u-b"))]
        let m = LayoutPresetModel.match(l, live: liveOK)
        XCTAssertEqual(m, LayoutMatch(layoutID: id(1), exact: true, usesTier2: true))
        // Wrong tier-1 identity under the same key: no match.
        XCTAssertNil(LayoutPresetModel.match(l, live: [LiveLayoutDisplay(key: key("a"), identity: ident("other")), liveOK[1]]))
        // Missing referenced display: no match.
        XCTAssertNil(LayoutPresetModel.match(l, live: [liveOK[0]]))
        // Extra display: includes, not exact.
        let extra = liveOK + [LiveLayoutDisplay(key: key("c"), identity: ident("t1c"))]
        XCTAssertEqual(LayoutPresetModel.match(l, live: extra)?.exact, false)
        // No identity at all: never matches.
        XCTAssertNil(LayoutPresetModel.match(layout(2, [key("a"): SavedDisplaySettings(identity: ident(nil, nil))]),
                                             live: liveOK))
        XCTAssertNil(LayoutPresetModel.match(layout(3, [:]), live: liveOK))
    }

    func testSelectionOrder() {
        let a = SavedDisplaySettings(identity: ident("A")), b = SavedDisplaySettings(identity: ident("B"))
        let live = [LiveLayoutDisplay(key: key("a"), identity: ident("A")), LiveLayoutDisplay(key: key("b"), identity: ident("B"))]
        let low = layout(1, [key("a"): a], priority: 0, name: "low")
        let specific = layout(2, [key("a"): a, key("b"): b], priority: 0, name: "specific")
        let high = layout(3, [key("a"): a], priority: 5, name: "high")
        let never = layout(4, [key("a"): a, key("b"): b], auto: .never, priority: 50)
        let exactOnly = layout(5, [key("a"): a], auto: .whenExactly, priority: 99)
        XCTAssertEqual(LayoutPresetModel.select([low, specific, never, exactOnly], live: live)?.layout.id, id(2))
        XCTAssertEqual(LayoutPresetModel.select([low, specific, high, never, exactOnly], live: live)?.layout.id, id(3))
        XCTAssertEqual(LayoutPresetModel.select([exactOnly, low], live: [live[0]])?.layout.id, id(5))
        XCTAssertNil(LayoutPresetModel.select([never], live: live))
        // Deterministic tie-break by name.
        let t1 = layout(6, [key("a"): a], name: "b"), t2 = layout(7, [key("a"): a], name: "a")
        XCTAssertEqual(LayoutPresetModel.select([t1, t2], live: live)?.layout.id, id(7))
        XCTAssertEqual(LayoutPresetModel.select([t2, t1], live: live)?.layout.id, id(7))
    }

    func testTrustStamp() {
        var l = layout(1, [key("a"): SavedDisplaySettings(mode: mode, x: 0, y: 0, isMain: true, brightness: 0.5, identity: ident("t1"))])
        l.trust = LayoutPresetModel.stamp(l, osMajor: 26, digest: digest)
        XCTAssertNotNil(l.trust)
        XCTAssertTrue(LayoutPresetModel.isTrusted(l, osMajor: 26, digest: digest))
        XCTAssertFalse(LayoutPresetModel.isTrusted(l, osMajor: 27, digest: digest), "OS major update clears trust")
        // Name, priority and auto-apply aren't covered; content is.
        var renamed = l
        renamed.name = "Other"
        renamed.priority = 9
        XCTAssertTrue(LayoutPresetModel.isTrusted(renamed, osMajor: 26, digest: digest))
        var edited = l
        edited.displays[key("a")]?.brightness = 0.6
        XCTAssertFalse(LayoutPresetModel.isTrusted(edited, osMajor: 26, digest: digest))
        var moved = l
        moved.displays[key("a")]?.identity = ident("t1-other")
        XCTAssertFalse(LayoutPresetModel.isTrusted(moved, osMajor: 26, digest: digest), "fingerprint change clears trust")
        var addedVirtual = l
        addedVirtual.virtualScreens[id(9)] = true
        XCTAssertFalse(LayoutPresetModel.isTrusted(addedVirtual, osMajor: 26, digest: digest))
        // Tier-2-only displays can't be trusted.
        let t2 = layout(2, [key("a"): SavedDisplaySettings(identity: ident(nil, "u"))])
        XCTAssertNil(LayoutPresetModel.trustInput(t2, osMajor: 26))
        XCTAssertNil(LayoutPresetModel.stamp(t2, osMajor: 26, digest: digest))
        XCTAssertFalse(LayoutPresetModel.isTrusted(l.withTrust(nil), osMajor: 26, digest: digest))
    }

    func testTrustInputIsCanonical() {
        let s1 = SavedDisplaySettings(x: 1, y: 2, adjustments: ["b": 0.2, "a": 0.1], identity: ident("x"))
        let s2 = SavedDisplaySettings(x: 3, y: 4, identity: ident("y"))
        let l1 = layout(1, [key("a"): s1, key("b"): s2])
        let l2 = layout(1, [key("b"): s2, key("a"): s1])
        XCTAssertEqual(LayoutPresetModel.trustInput(l1, osMajor: 26), LayoutPresetModel.trustInput(l2, osMajor: 26))
    }

    func testRevalidated() {
        var l = layout(1, [key("a"): SavedDisplaySettings(identity: ident("t1"))])
        l.trust = TrustStamp(digest: "x", osMajor: 26)
        XCTAssertNotNil(LayoutPresetModel.revalidated(l, live: [LiveLayoutDisplay(key: key("a"), identity: ident("t1"))]).trust)
        XCTAssertNil(LayoutPresetModel.revalidated(l, live: [LiveLayoutDisplay(key: key("a"), identity: ident("t2"))]).trust)
        XCTAssertNotNil(LayoutPresetModel.revalidated(l, live: []).trust, "absent displays don't clear trust")
    }

    func testSanitize() {
        var s = SavedDisplaySettings(rotation: 45, mirrorOf: key("8"), mirrorSet: true, brightness: 4, volume: -1, identity: ident("a"))
        s.adjustments = ["ok": 1, "nan": .nan]
        var l = layout(1, [key("a"): s, key("b"): SavedDisplaySettings(mirrorOf: key("a"), mirrorSet: true, identity: ident("b"))])
        l.name = "\u{0000}"
        l.priority = 1000
        l.trust = TrustStamp(digest: "", osMajor: 1)
        let c = l.sanitized()
        XCTAssertEqual(c.name, L("Layout"))
        XCTAssertEqual(c.priority, 100)
        XCTAssertNil(c.trust)
        let a = c.displays[key("a")]!
        XCTAssertNil(a.rotation)
        XCTAssertEqual(a.brightness, 1)
        XCTAssertEqual(a.volume, 0)
        XCTAssertNil(a.mirrorOf, "mirror target outside the layout")
        XCTAssertFalse(a.mirrorSet)
        XCTAssertEqual(a.adjustments, ["ok": 1])
        XCTAssertEqual(c.displays[key("b")]?.mirrorOf, key("a"))
        XCTAssertTrue(c.hasTrialContent)
        XCTAssertEqual(c.sanitized(), c)
    }

    func testLossyDecode() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Office","priority":"high","autoApply":"sometimes",
         "displays":{"\(String(repeating: "a", count: 32))":{"x":5,"rotation":"left"},"bad":{"x":1}},
         "trust":{"digest":"abc","osMajor":26}}
        """
        let l = try JSONDecoder().decode(SavedLayout.self, from: Data(json.utf8))
        XCTAssertEqual(l.name, "Office")
        XCTAssertEqual(l.priority, 0)
        XCTAssertEqual(l.autoApply, .never)
        XCTAssertEqual(l.displays.values.count, 1)
        XCTAssertEqual(l.displays[key("a")]?.x, 5)
        XCTAssertNil(l.displays[key("a")]?.rotation)
        XCTAssertEqual(l.trust, TrustStamp(digest: "abc", osMajor: 26))
        XCTAssertEqual(try JSONDecoder().decode(SavedLayout.self, from: JSONEncoder().encode(l)), l)
    }

    // MARK: Menu (0.3 §5.2)

    func testBestMatchIgnoresAutoApply() {
        let a = layout(1, [key("a"): SavedDisplaySettings(identity: ident("t1a"))], auto: .never, name: "Desk")
        let b = layout(2, [key("a"): SavedDisplaySettings(identity: ident("t1a")), key("b"): SavedDisplaySettings(identity: ident("t1b"))],
                       auto: .never, name: "Dock")
        let live = [LiveLayoutDisplay(key: key("a"), identity: ident("t1a")), LiveLayoutDisplay(key: key("b"), identity: ident("t1b"))]
        // Never auto-applies, but the menu still offers the most specific match, unchanged.
        XCTAssertNil(LayoutPresetModel.select([a, b], live: live))
        XCTAssertEqual(LayoutPresetModel.bestMatch([a, b], live: live), b)
        XCTAssertEqual(LayoutPresetModel.bestMatch([a, b], live: [live[0]]), a)
        XCTAssertNil(LayoutPresetModel.bestMatch([b], live: [live[0]]))
        XCTAssertNil(LayoutPresetModel.bestMatch([], live: live))
    }

    func testIsCurrentComparesOnlySavedFields() {
        let s = SavedDisplaySettings(mode: mode, x: 0, y: 0, isMain: true, rotation: 0, identity: ident("t1a"))
        let mirrored = SavedDisplaySettings(x: 99, y: 99, mirrorOf: key("a"), mirrorSet: true, identity: ident("t1b"))
        let l = layout(1, [key("a"): s, key("b"): mirrored])
        let otherRefresh = ModeRef(ioModeID: 9, pixelWidth: 3024, pixelHeight: 1964, pointWidth: 1512, pointHeight: 982,
                                   refreshMilliHz: 120_005)
        var states: [DisplayKey: LayoutLiveState] = [
            key("a"): LayoutLiveState(mode: otherRefresh, x: 0, y: 0, isMain: true, rotation: 0, mirrorOf: nil),
            // A mirrored display's saved origin is not compared.
            key("b"): LayoutLiveState(mode: nil, x: 5, y: 5, isMain: false, rotation: 0, mirrorOf: key("a")),
        ]
        XCTAssertTrue(LayoutPresetModel.isCurrent(l, states: states))
        states[key("b")]?.mirrorOf = nil
        XCTAssertFalse(LayoutPresetModel.isCurrent(l, states: states))
        states[key("b")]?.mirrorOf = key("a")
        states[key("a")]?.x = 1
        XCTAssertFalse(LayoutPresetModel.isCurrent(l, states: states))
        states[key("a")]?.x = 0
        states[key("a")]?.rotation = 90
        XCTAssertFalse(LayoutPresetModel.isCurrent(l, states: states))
        states[key("a")]?.rotation = 0
        states[key("a")]?.isMain = false
        XCTAssertFalse(LayoutPresetModel.isCurrent(l, states: states))
        states[key("a")]?.isMain = true
        states[key("a")]?.mode = nil
        XCTAssertFalse(LayoutPresetModel.isCurrent(l, states: states))
        // A missing display, an empty layout, or one that saves nothing comparable is never current.
        XCTAssertFalse(LayoutPresetModel.isCurrent(l, states: [:]))
        XCTAssertFalse(LayoutPresetModel.isCurrent(layout(2, [:]), states: states))
        XCTAssertFalse(LayoutPresetModel.isCurrent(layout(3, [key("a"): SavedDisplaySettings(identity: ident("t1a"))]), states: states))
    }
}

private extension SavedLayout {
    func withTrust(_ t: TrustStamp?) -> SavedLayout {
        var c = self
        c.trust = t
        return c
    }
}

final class ListReorderTests: XCTestCase {
    private struct Item: Equatable { let id: String; let n: Int }

    func testReorderFollowsTheGivenOrder() {
        let items = [Item(id: "a", n: 1), Item(id: "b", n: 2), Item(id: "c", n: 3)]
        XCTAssertEqual(ListReorder.reordered(items, id: \.id, order: ["c", "a", "b"]).map(\.id), ["c", "a", "b"])
    }

    func testUnknownMissingAndRepeatedIDs() {
        let items = [Item(id: "a", n: 1), Item(id: "b", n: 2), Item(id: "c", n: 3)]
        // "x" doesn't exist, "a" repeats, "b" wasn't listed: kept after the listed ones.
        XCTAssertEqual(ListReorder.reordered(items, id: \.id, order: ["x", "c", "a", "a"]).map(\.id), ["c", "a", "b"])
        XCTAssertEqual(ListReorder.reordered(items, id: \.id, order: []).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ListReorder.reordered([Item](), id: \.id, order: ["a"]), [])
    }

    func testDuplicateIDsInTheStoreAreNeverDropped() {
        let items = [Item(id: "a", n: 1), Item(id: "a", n: 2), Item(id: "b", n: 3)]
        XCTAssertEqual(ListReorder.reordered(items, id: \.id, order: ["b", "a"]).map(\.n), [3, 1, 2])
    }

    func testMoving() {
        XCTAssertEqual(ListReorder.moving("b", by: -1, in: ["a", "b", "c"]), ["b", "a", "c"])
        XCTAssertEqual(ListReorder.moving("b", by: 5, in: ["a", "b", "c"]), ["a", "c", "b"])
        XCTAssertEqual(ListReorder.moving("a", by: -1, in: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(ListReorder.moving("z", by: 1, in: ["a", "b"]), ["a", "b"])
    }

    func testReorderFuzzKeepsEveryItemOnce() {
        var rng = SeededGenerator(seed: 0x1A70)
        for _ in 0..<300 {
            let count = Int.random(in: 0...10, using: &rng)
            let items = (0..<count).map { Item(id: String(Int.random(in: 0...6, using: &rng)), n: $0) }
            let order = (0..<Int.random(in: 0...12, using: &rng)).map { _ in String(Int.random(in: 0...8, using: &rng)) }
            let result = ListReorder.reordered(items, id: \.id, order: order)
            XCTAssertEqual(result.map(\.n).sorted(), items.map(\.n))
        }
    }
}

