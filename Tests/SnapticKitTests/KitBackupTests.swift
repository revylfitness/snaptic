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
        for name in ["salt", "displaySalt", "trustStamp", "ddcUnlocks", "allowWithoutAsking", "apiToken", "preConfirmAllowed"] {
            XCTAssertTrue(KitBackup.isSensitive(name), name)
        }
        for name in ["brightness", "step", "features", "names"] { XCTAssertFalse(KitBackup.isSensitive(name), name) }
        for name in ["allowGammaWithCustomProfile", "allowBelow720p", "cliAllowed"] {
            XCTAssertTrue(KitBackup.isSensitive(name), name)
        }
    }

    // MARK: Safety switches (FIXES-R1 A2)

    private let keyA = String(repeating: "a", count: 32)
    private let keyB = String(repeating: "b", count: 32)

    private func safetyDisplays(preventSleep: Bool, ignore: Bool, withoutDDC: Bool, gamma: Bool,
                                prefixes: [String]) -> [String: Any] {
        ["management": ["autoDisconnectWithoutDDC": withoutDDC, "snapArrangement": true],
         "perDisplay": [keyA: ["management": ["preventSleep": preventSleep, "ignoreForAutoDisconnect": ignore,
                                              "powerSwitch": "none"]],
                        keyB: ["management": ["preventSleep": preventSleep], "brightness": ["minHardware": 0.1]]],
         "color": ["allowGammaWithCustomProfile": gamma, "shortcutStep": 0.1],
         "resolution": ["allowBelow720p": true, "sliderSnapping": true],
         "pip": ["protectedBundlePrefixes": prefixes, "pauseWhenOccluded": true]]
    }

    func testSafetySwitchesNeverLeaveOrEnter() throws {
        let unsafe = safetyDisplays(preventSleep: true, ignore: true, withoutDDC: true, gamma: true, prefixes: ["com.x"])
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["displays": json(unsafe)], created: "t", appVersion: "1"))
        let text = String(decoding: doc, as: UTF8.self)
        for banned in ["preventSleep", "ignoreForAutoDisconnect", "autoDisconnectWithoutDDC", "allowGammaWithCustomProfile",
                       "allowBelow720p"] {
            XCTAssertFalse(text.contains(banned), banned)
        }
        for kept in ["powerSwitch", "snapArrangement", "shortcutStep", "sliderSnapping", "minHardware", "com.x"] {
            XCTAssertTrue(text.contains(kept), kept)
        }

        // A hand-made file that carries them anyway: stripped, and the current values stay.
        let file: [String: Any] = ["format": KitBackup.format, "version": 1, "sections": ["displays": unsafe]]
        let parsed = try KitBackup.parseDocument(json(file)).get()
        let current = json(safetyDisplays(preventSleep: false, ignore: false, withoutDDC: false, gamma: false,
                                          prefixes: ["com.x"]))
        let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: parsed["displays"]!,
                                                          section: "displays")))
        let management = merged["management"] as? [String: Any]
        XCTAssertEqual(management?["autoDisconnectWithoutDDC"] as? Bool, false)
        let perDisplay = merged["perDisplay"] as? [String: [String: Any]]
        for key in [keyA, keyB] {
            let m = perDisplay?[key]?["management"] as? [String: Any]
            XCTAssertEqual(m?["preventSleep"] as? Bool, false, key)
        }
        XCTAssertEqual((perDisplay?[keyA]?["management"] as? [String: Any])?["ignoreForAutoDisconnect"] as? Bool, false)
        XCTAssertEqual((merged["color"] as? [String: Any])?["allowGammaWithCustomProfile"] as? Bool, false)
    }

    func testWildcardRemovalReachesEveryDisplayOnly() {
        let input: [String: Any] = ["perDisplay": [keyA: ["management": ["preventSleep": true, "powerSwitch": "x"]],
                                                   keyB: "not an object"],
                                    "management": ["preventSleep": true]]
        let out = KitBackup.strip(input, section: "displays") as? [String: Any]
        let a = ((out?["perDisplay"] as? [String: Any])?[keyA] as? [String: Any])?["management"] as? [String: Any]
        XCTAssertNil(a?["preventSleep"])
        XCTAssertEqual(a?["powerSwitch"] as? String, "x")
        XCTAssertEqual((out?["perDisplay"] as? [String: Any])?[keyB] as? String, "not an object")
        // Only the listed path: a same-named key elsewhere stays.
        XCTAssertEqual((out?["management"] as? [String: Any])?["preventSleep"] as? Bool, true)
    }

    func testProtectedPrefixesOnlyGrow() throws {
        let current = json(["pip": ["protectedBundlePrefixes": ["com.bank", "com.mail"], "pauseWhenOccluded": true]])
        func prefixes(_ imported: [String: Any]) throws -> [String]? {
            let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: json(imported), section: "displays")))
            return (merged["pip"] as? [String: Any])?["protectedBundlePrefixes"] as? [String]
        }
        XCTAssertEqual(try prefixes(["pip": ["protectedBundlePrefixes": [String]()]]), ["com.bank", "com.mail"])
        XCTAssertEqual(try prefixes(["pip": ["protectedBundlePrefixes": ["com.notes", "com.bank"]]]),
                       ["com.bank", "com.mail", "com.notes"])
        XCTAssertEqual(try prefixes(["pip": ["pauseWhenOccluded": false]]), ["com.bank", "com.mail"])
        XCTAssertEqual(try prefixes(["pip": "garbage"]), ["com.bank", "com.mail"])
        // Other sections and the section-less merge replace lists as before.
        let plain = object(try XCTUnwrap(KitBackup.merge(current: current,
                                                         imported: json(["pip": ["protectedBundlePrefixes": ["x"]]]))))
        XCTAssertEqual((plain["pip"] as? [String: Any])?["protectedBundlePrefixes"] as? [String], ["x"])
    }

    func testPreviewListsSafetyChangesFirstAndInFull() {
        var oldFeatures: [String: Bool] = [:]
        var newFeatures: [String: Bool] = [:]
        for i in 0..<70 { oldFeatures["f\(i)"] = false; newFeatures["f\(i)"] = true }
        var oldNames: [String: String] = [:]
        var newNames: [String: String] = [:]
        for i in 0..<70 { oldNames["n\(i)"] = "a"; newNames["n\(i)"] = "b" }
        let old = json(["features": oldFeatures, "identity": ["names": oldNames],
                        "pip": ["protectedBundlePrefixes": ["a"], "luts": [1]]])
        let new = json(["features": newFeatures, "identity": ["names": newNames],
                        "pip": ["protectedBundlePrefixes": ["a", "b"], "luts": [2]]])
        let preview = KitBackup.previewChanges(section: "displays", from: old, to: new, limit: 10)
        XCTAssertEqual(preview.safety.count, 71)
        XCTAssertTrue(preview.safety.contains("pip.protectedBundlePrefixes"))
        XCTAssertTrue(preview.safety.allSatisfy { $0.hasPrefix("features.") || $0 == "pip.protectedBundlePrefixes" })
        XCTAssertEqual(preview.other.count, 10)
        XCTAssertFalse(preview.safety.contains("pip.luts"))
        XCTAssertEqual(preview.other, Array(preview.other.sorted()))
    }

    func testSafetyClassification() {
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "displays", path: "features.xdr"))
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "displays", path: "perDisplay.\(keyA).management.powerSwitch"))
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "displays", path: "perDisplay.\(keyA).ddc.enabled"))
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "displays", path: "safety.confirmSeconds"))
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "displays", path: "(all)"))
        XCTAssertTrue(KitBackup.isSafetyRelated(section: "modules", path: "enabled.displays"))
        XCTAssertFalse(KitBackup.isSafetyRelated(section: "displays", path: "perDisplay.\(keyA).identity.customName"))
        XCTAssertFalse(KitBackup.isSafetyRelated(section: "displays", path: "menu.compact"))
        XCTAssertFalse(KitBackup.isSafetyRelated(section: "displays", path: "pip.luts"))
        XCTAssertFalse(KitBackup.isSafetyRelated(section: "displays", path: "perDisplay"))
        XCTAssertFalse(KitBackup.isSafetyRelated(section: "switcher", path: "(all)"))
    }
}
