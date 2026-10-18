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

    // MARK: Lists of objects with ids (FIXES-R3 8)

    /// A Displays section with the kinds of lists that carry stripped fields.
    private var listSection: [String: Any] {
        ["layouts": ["undoToast": true,
                     "layouts": [["id": "L1", "name": "Office", "trust": ["os": 26, "digest": "d1"], "autoApply": "always"],
                                 ["id": "L2", "name": "Home", "trust": ["os": 26, "digest": "d2"], "autoApply": "never"]]],
         "virtualScreens": ["screens": [["id": "V1", "name": "Sidecar", "allowLowResolution": true, "hiDPI": true]]],
         "pip": ["protectedBundlePrefixes": ["com.bank"],
                 "configurations": [["id": "P1", "name": "Cam", "kind": "window"], ["id": "P2", "name": "Desk", "kind": "display"]]],
         "perDisplay": ["k1": ["management": ["preventSleep": true, "ignoreForAutoDisconnect": true, "rotationLock": false]]],
         "ddc": ["unlocks": ["k1": ["0xD6"]], "step": 4],
         "automation": ["hooks": [["id": "H1", "path": "/bin/true"]]],
         "features": ["brightness": true, "disconnect": true]]
    }

    private func canonical(_ data: Data) -> String {
        let o = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        return String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
    }

    /// Export → import of your own backup changes nothing, stripped fields included.
    func testOwnBackupRoundTripChangesNothing() throws {
        let current = json(listSection)
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["displays": current, "modules": json(modules)],
                                                         created: "2026-10-17T00:00:00Z", appVersion: "0.2.0"))
        let text = String(decoding: doc, as: UTF8.self)
        XCTAssertFalse(text.contains("digest"), "trust is stripped from the export")
        XCTAssertFalse(text.contains("allowLowResolution"))
        let parsed = try KitBackup.parseDocument(doc).get()
        for (name, now) in [("displays", current), ("modules", json(modules))] {
            let imported = try XCTUnwrap(parsed[name])
            let merged = try XCTUnwrap(KitBackup.merge(current: now, imported: imported, section: name))
            XCTAssertEqual(canonical(merged), canonical(now), name)
            XCTAssertEqual(KitBackup.changedPaths(from: now, to: merged), [], name)
        }
    }

    func testListElementsMergeByIDKeepingStrippedFields() throws {
        let current = json(listSection)
        // The backup renamed L1, dropped L2, added L3 and reordered the PIP configurations.
        let imported = json(["layouts": ["layouts": [["id": "L3", "name": "Cafe"], ["id": "L1", "name": "Work"]]],
                             "pip": ["configurations": [["id": "P2", "name": "Desk 2"], ["id": "P1", "name": "Cam"]]]])
        let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: imported, section: "displays")))
        let layouts = try XCTUnwrap((merged["layouts"] as? [String: Any])?["layouts"] as? [[String: Any]])
        XCTAssertEqual(layouts.map { $0["id"] as? String }, ["L3", "L1"])
        XCTAssertEqual(layouts[1]["name"] as? String, "Work")
        XCTAssertEqual((layouts[1]["trust"] as? [String: Any])?["digest"] as? String, "d1", "current trust survives")
        XCTAssertEqual(layouts[1]["autoApply"] as? String, "always")
        XCTAssertNil(layouts[0]["trust"], "a new layout never arrives trusted")
        let pip = try XCTUnwrap((merged["pip"] as? [String: Any])?["configurations"] as? [[String: Any]])
        XCTAssertEqual(pip.map { $0["id"] as? String }, ["P2", "P1"])
        XCTAssertEqual(pip[0]["kind"] as? String, "display")
        XCTAssertEqual(pip[0]["name"] as? String, "Desk 2")
    }

    func testListsWithoutIDsAreStillReplaced() throws {
        let current = json(["a": [["x": 1], ["x": 2]], "b": [1, 2, 3], "c": [["id": "1", "v": 1]], "d": [["id": "1"]]])
        let imported = json(["a": [["x": 9]], "b": [4], "c": [["v": 2]], "d": [Any]()])
        let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: imported)))
        XCTAssertEqual((merged["a"] as? [[String: Any]])?.first?["x"] as? Int, 9)
        XCTAssertEqual(merged["b"] as? [Int], [4])
        XCTAssertEqual((merged["c"] as? [[String: Any]])?.first?["v"] as? Int, 2)
        XCTAssertNil((merged["c"] as? [[String: Any]])?.first?["id"], "an element without id replaces the list")
        XCTAssertEqual((merged["d"] as? [Any])?.count, 0, "an empty import empties the list")
        // Numeric ids and duplicate ids.
        let n = object(try XCTUnwrap(KitBackup.merge(current: json(["l": [["id": 1, "keep": "k", "v": 1]]]),
                                                     imported: json(["l": [["id": 1, "v": 2], ["id": 1, "v": 3]]]))))
        let l = try XCTUnwrap(n["l"] as? [[String: Any]])
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[0]["keep"] as? String, "k")
        XCTAssertEqual(l[0]["v"] as? Int, 2)
        XCTAssertNil(l[1]["keep"])
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
