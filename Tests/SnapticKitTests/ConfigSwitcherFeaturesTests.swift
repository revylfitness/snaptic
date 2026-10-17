import XCTest
@testable import SnapticKit

final class ConfigSwitcherFeaturesTests: XCTestCase {
    private func decode(_ json: String) throws -> SwitcherFeaturesConfig {
        try JSONDecoder().decode(SwitcherFeaturesConfig.self, from: Data(json.utf8))
    }

    private func encodeString(_ c: SwitcherFeaturesConfig) throws -> String {
        String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
    }

    func testDefaultEverythingOn() {
        let c = SwitcherFeaturesConfig()
        for f in SwitcherFeature.allCases { XCTAssertTrue(c.isEnabled(f), f.rawValue) }
    }

    func testStoredAsArrayOfNames() throws {
        let c = SwitcherFeaturesConfig(disabled: [.search, .thumbnails])
        XCTAssertEqual(try encodeString(c), #"["search","thumbnails"]"#)
        XCTAssertEqual(try decode(#"["thumbnails","search"]"#), c)
    }

    func testUnknownNamesAreKeptAndWrittenBack() throws {
        let c = try decode(#"["search","teleport","zoom"]"#)
        XCTAssertFalse(c.isEnabled(.search))
        XCTAssertEqual(c.unknownNames, ["teleport", "zoom"])
        XCTAssertEqual(try encodeString(c), #"["search","teleport","zoom"]"#)
    }

    func testNonStringElementsAreSkipped() throws {
        let c = try decode(#"[1, {"a":2}, "hoverButtons", null, ["x"], "actionQuit"]"#)
        XCTAssertEqual(c.disabled, [.hoverButtons, .actionQuit])
    }

    func testNotAnArrayFallsBackInAContainer() throws {
        struct Holder: Decodable {
            var features: SwitcherFeaturesConfig
            enum CodingKeys: String, CodingKey { case features }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                features = c.lossy(.features, SwitcherFeaturesConfig())
            }
        }
        let h = try JSONDecoder().decode(Holder.self, from: Data(#"{"features":"search"}"#.utf8))
        XCTAssertEqual(h.features, SwitcherFeaturesConfig())
    }

    func testSanitizeBoundsUnknownNames() throws {
        let names = (0..<100).map { "\"future\($0)\"" } + ["\"\"", "\"" + String(repeating: "x", count: 80) + "\"",
                                                            "\"future1\""]
        let c = try decode("[" + names.joined(separator: ",") + "]").sanitized()
        XCTAssertEqual(c.unknownNames.count, SwitcherFeaturesConfig.maxUnknown)
        XCTAssertFalse(c.unknownNames.contains(""))
        XCTAssertEqual(Set(c.unknownNames).count, c.unknownNames.count)
        XCTAssertEqual(c.sanitized(), c)
    }

    func testSetToggles() {
        var c = SwitcherFeaturesConfig()
        c.set(.passthrough, enabled: false)
        XCTAssertFalse(c.isEnabled(.passthrough))
        c.set(.passthrough, enabled: true)
        XCTAssertTrue(c.isEnabled(.passthrough))
        XCTAssertEqual(c, SwitcherFeaturesConfig())
    }

    func testHintLineListsOnlyWorkingKeys() {
        XCTAssertEqual(SwitcherFeaturesConfig().hintLine(),
                       "S search · W close · M minimize · F full screen · Q quit · H hide")
        let c = SwitcherFeaturesConfig(disabled: [.search, .actionQuit, .actionFullscreen])
        XCTAssertEqual(c.hintLine(), "W close · M minimize · H hide")
        let none = SwitcherFeaturesConfig(disabled: Set(SwitcherFeaturesConfig.actions + [.search]))
        XCTAssertEqual(none.hintLine(), "")
    }

    func testEveryFeatureHasTitleAndDetail() {
        for f in SwitcherFeature.allCases {
            XCTAssertFalse(SwitcherFeaturesConfig.title(f).isEmpty, f.rawValue)
            XCTAssertFalse(SwitcherFeaturesConfig.detail(f).isEmpty, f.rawValue)
        }
    }

    func testFuzzRoundTrip() throws {
        var rng = SeededGenerator(seed: 0xFEA7)
        let all = SwitcherFeature.allCases
        for _ in 0..<1_000 {
            let set = Set(all.filter { _ in rng.next() % 3 == 0 })
            let c = SwitcherFeaturesConfig(disabled: set)
            let back = try JSONDecoder().decode(SwitcherFeaturesConfig.self, from: JSONEncoder().encode(c))
            XCTAssertEqual(back, c)
        }
    }
}
