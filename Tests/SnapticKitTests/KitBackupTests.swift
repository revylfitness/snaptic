import XCTest
@testable import SnapticKit

final class KitBackupTests: XCTestCase {
    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    private func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }

    private var displays: [String: Any] {
        ["features": ["brightness": true, "disconnect": true, "dimToBlack": true, "sleepPrevention": true, "hooks": true],
         "automation": ["hooks": [["id": "x"]]],
         "ddc": ["unlocks": ["a": 1], "step": 4],
         "layouts": ["presets": [["name": "Office", "trustStamp": "abc"]]],
         "identity": ["saltHint": "s", "names": ["k": "Desk"]]]
    }

    private var modules: [String: Any] {
        ["commandLine": ["enabled": true], "sharedSymbol": "display", "onboarding": "done"]
    }

    func testExportLeavesOutProtectedFields() throws {
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["displays": json(displays), "modules": json(modules)],
                                                         created: "2026-10-17T00:00:00Z", appVersion: "0.2.0"))
        let text = String(decoding: doc, as: UTF8.self)
        for banned in ["automation", "disconnect", "dimToBlack", "sleepPrevention", "unlocks", "trustStamp", "saltHint",
                       "commandLine", "onboarding", "\"hooks\""] {
            XCTAssertFalse(text.contains(banned), banned)
        }
        for kept in ["brightness", "step", "Office", "Desk", "sharedSymbol"] {
            XCTAssertTrue(text.contains(kept), kept)
        }
        XCTAssertTrue(text.contains(KitBackup.format))
    }

    func testImportStripsTheSameFieldsEvenIfPresent() throws {
        let doc: [String: Any] = ["format": KitBackup.format, "version": 1,
                                  "sections": ["displays": displays, "modules": modules, "evil": ["x": 1]]]
        let parsed = try KitBackup.parseDocument(json(doc)).get()
        XCTAssertEqual(Set(parsed.keys), ["displays", "modules"])
        let d = object(parsed["displays"]!)
        XCTAssertNil(d["automation"])
        XCTAssertNil((d["features"] as? [String: Any])?["disconnect"])
        XCTAssertNil((d["ddc"] as? [String: Any])?["unlocks"])
        XCTAssertNotNil((d["ddc"] as? [String: Any])?["step"])
        XCTAssertNil(object(parsed["modules"]!)["commandLine"])
    }

    func testRejectsWrongFilesAndNewerVersions() {
        XCTAssertEqual(KitBackup.parseDocument(Data("hello".utf8)), .failure(.notJSON))
        XCTAssertEqual(KitBackup.parseDocument(json(["format": "other", "version": 1])), .failure(.wrongFormat))
        XCTAssertEqual(KitBackup.parseDocument(json(["format": KitBackup.format, "version": 9, "sections": [:]])),
                       .failure(.newerVersion(9)))
        XCTAssertEqual(KitBackup.parseDocument(json(["format": KitBackup.format, "version": 1, "sections": [:]])),
                       .failure(.noSections))
        XCTAssertEqual(KitBackup.parseDocument(Data(count: KitBackup.maxBytes + 1)), .failure(.tooLarge))
    }

    func testMergeKeepsFieldsTheImportLacks() throws {
        let current = json(["features": ["brightness": false, "disconnect": true], "automation": ["hooks": [1]],
                            "ddc": ["step": 2, "unlocks": ["a": 1]]])
        let imported = json(["features": ["brightness": true], "ddc": ["step": 8]])
        let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: imported)))
        let features = merged["features"] as? [String: Any]
        XCTAssertEqual(features?["brightness"] as? Bool, true)
        XCTAssertEqual(features?["disconnect"] as? Bool, true)       // current value survives
        XCTAssertNotNil(merged["automation"])
        XCTAssertEqual((merged["ddc"] as? [String: Any])?["step"] as? Int, 8)
        XCTAssertNotNil((merged["ddc"] as? [String: Any])?["unlocks"])
    }

    func testChangedPaths() throws {
        let old = json(["a": 1, "b": ["c": true, "d": "x"], "e": [1, 2]])
        let new = json(["a": 1, "b": ["c": false, "d": "x"], "e": [1, 3], "f": 0])
        XCTAssertEqual(KitBackup.changedPaths(from: old, to: new), ["b.c", "e", "f"])
        XCTAssertEqual(KitBackup.changedPaths(from: old, to: old), [])
    }

    func testSensitiveNames() {
        for name in ["salt", "displaySalt", "trustStamp", "ddcUnlocks", "allowWithoutAsking", "apiToken"] {
            XCTAssertTrue(KitBackup.isSensitive(name), name)
        }
        for name in ["brightness", "step", "features", "names"] { XCTAssertFalse(KitBackup.isSensitive(name), name) }
    }
}
