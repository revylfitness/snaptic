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
        var s = SavedDisplaySettings(rotation: 45, mirrorOf: key("z"), mirrorSet: true, brightness: 4, volume: -1, identity: ident("a"))
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
}

private extension SavedLayout {
    func withTrust(_ t: TrustStamp?) -> SavedLayout {
        var c = self
        c.trust = t
        return c
    }
}
