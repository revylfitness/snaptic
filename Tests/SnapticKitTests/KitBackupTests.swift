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

    // MARK: Awake (0.3 §2.14, §3.2, §3.6)

    private let volumeID = "6F1C1E8A-1D0B-4C55-9D41-3A6E1B1E2F10"
    private let digest = String(repeating: "ab", count: 32)

    /// An `awake` section with everything a backup must never carry, beside what it may.
    private var hostileAwake: [String: Any] {
        ["features": ["pointerNudge": true, "commandLine": true, "activity": true, "triggers": true],
         "drives": ["volumes": [volumeID: ["name": "Backup", "enabled": true, "firstWriteDone": true]],
                    "intervalSeconds": 30, "evenWithoutSession": true],
         "sessions": ["presets": [["id": "B1C2D3E4-0000-4000-8000-000000000001", "kind": ["type": "indefinite"],
                                   "options": ["activity": "nudge", "display": "keepOn", "displayIdleMinutes": 30]]],
                      "recentApps": ["com.example.secret"], "lastCustomSeconds": 600,
                      "behavior": ["startAtLaunch": "B1C2D3E4-0000-4000-8000-000000000001", "resumeAfterRestart": true],
                      "defaultOptions": ["activity": "nudge", "display": "keepOn", "displayIdleMinutes": 30]],
         "guards": ["batteryFloorEnabled": false, "batteryFloor": 5],
         "triggers": ["triggers": [["id": "B1C2D3E4-0000-4000-8000-000000000002", "name": "Home", "enabled": true,
                                    "criteria": [["criterion": ["type": "network",
                                                                "condition": ["type": "router", "hash": digest,
                                                                              "label": "Home"]],
                                                  "negated": false],
                                                 ["criterion": ["type": "usb", "vendor": 1, "product": 2,
                                                                "serialHash": digest, "name": "Dock"]]]]]],
         "activity": ["stopAfterHours": 8],
         "indicator": ["style": "iconAndTime", "glyph": "eye"],
         "shortcuts": ["awake.toggle": ["keyCode": 5, "carbonModifiers": 2048]],
         // Never part of AwakeConfig, so never part of a backup (allowlist).
         "history": ["entries": [["start": 1, "end": 2]]], "snapshot": ["manual": ["x": 1]], "saltHint": "s",
         "futureField": ["x": 1]]
    }

    private func awakeText(_ object: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    func testAwakeExportIsAnAllowlist() throws {
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["awake": json(hostileAwake)], created: "t",
                                                         appVersion: "0.3.0"))
        let parsed = object(doc)
        let awake = try XCTUnwrap((parsed["sections"] as? [String: Any])?["awake"] as? [String: Any])
        XCTAssertEqual(Set(awake.keys), ["features", "sessions", "guards", "triggers", "activity", "indicator", "shortcuts"])
        let text = awakeText(awake)
        for banned in ["pointerNudge", "commandLine", "drives", volumeID, "evenWithoutSession", "recentApps",
                       "com.example.secret", "startAtLaunch", "history", "snapshot", "saltHint", "futureField",
                       digest, "serialHash", "\"hash\""] {
            XCTAssertFalse(text.contains(banned), banned)
        }
        for kept in ["activity", "resumeAfterRestart", "lastCustomSeconds", "batteryFloor", "Home", "Dock",
                     "iconAndTime", "awake.toggle", "stopAfterHours"] {
            XCTAssertTrue(text.contains(kept), kept)
        }
    }

    func testAwakeImportStripsTheSameEvenIfPresent() throws {
        let file: [String: Any] = ["format": KitBackup.format, "version": 1, "sections": ["awake": hostileAwake]]
        let parsed = try KitBackup.parseDocument(json(file)).get()
        let awake = object(try XCTUnwrap(parsed["awake"]))
        XCTAssertNil(awake["drives"])
        XCTAssertNil(awake["history"])
        XCTAssertNil(awake["futureField"])
        XCTAssertNil((awake["features"] as? [String: Any])?["pointerNudge"])
        XCTAssertNil((awake["features"] as? [String: Any])?["commandLine"])
        XCTAssertEqual((awake["features"] as? [String: Any])?["activity"] as? Bool, true)
        let sessions = awake["sessions"] as? [String: Any]
        XCTAssertNil(sessions?["recentApps"])
        XCTAssertNil((sessions?["behavior"] as? [String: Any])?["startAtLaunch"])
        XCTAssertEqual((sessions?["behavior"] as? [String: Any])?["resumeAfterRestart"] as? Bool, true)
        XCTAssertFalse(awakeText(awake).contains(digest))
    }

    func testAwakeAllowlistDropsWrongShapes() {
        let odd: [String: Any] = ["sessions": "not an object", "guards": [1, 2], "indicator": ["style": "icon"]]
        let out = KitBackup.strip(odd, section: "awake") as? [String: Any]
        XCTAssertNil(out?["sessions"], "an allowed path that must go deeper needs an object")
        XCTAssertEqual(out?["guards"] as? [Int], [1, 2], "a whole allowed key keeps its value; decoding rejects it")
        XCTAssertNotNil(out?["indicator"])
        XCTAssertEqual((KitBackup.strip("garbage", section: "awake") as? [String: Any])?.count, 0)
    }

    /// A hand-made backup with pointer movement, drives, nudge presets and loose guards: none of it survives the
    /// typed import (stub or G's `importable`), and the guards only ever get stricter (security L5).
    func testHostileAwakeBackupNeverLoosensAnything() throws {
        let file: [String: Any] = ["format": KitBackup.format, "version": 1, "sections": ["awake": hostileAwake]]
        let parsed = try KitBackup.parseDocument(json(file)).get()
        var current = AwakeConfig()
        current.guards.batteryFloor = 30
        current.features[.pointerNudge] = false
        let volume = try XCTUnwrap(VolumeUUIDKey(rawValue: "0A1B2C3D-0000-4000-8000-00000000AAAA"))
        current.drives.volumes[volume] = DriveAliveVolume(name: "Mine", enabled: false)
        current = current.sanitized()
        // Through the parsed (already stripped) section, and with the raw hostile JSON straight in.
        for imported in [try XCTUnwrap(parsed["awake"]), json(hostileAwake)] {
            let result = try XCTUnwrap(KitBackup.importAwake(current: current, imported: imported))
            XCTAssertEqual(result.features[.pointerNudge], current.features[.pointerNudge])
            XCTAssertEqual(result.drives, current.drives)
            XCTAssertTrue(result.guards.batteryFloorEnabled)
            XCTAssertGreaterThanOrEqual(result.guards.batteryFloor, current.guards.batteryFloor)
            XCTAssertGreaterThanOrEqual(result.guards.effectiveFloor, current.guards.effectiveFloor)
            XCTAssertNotEqual(result.sessions.defaultOptions.activity, .nudge)
            XCTAssertFalse(result.sessions.presets.contains { $0.options?.activity == .nudge })
            XCTAssertFalse(result.triggers.triggers.contains { $0.options.activity == .nudge })
            XCTAssertEqual(result.sessions.recentApps, current.sessions.recentApps)
            XCTAssertEqual(result.sessions.behavior.startAtLaunch, current.sessions.behavior.startAtLaunch)
            for trigger in result.triggers.triggers {
                for entry in trigger.criteria {
                    if case .network(.router) = entry.criterion { XCTFail("a router hash came in from a file") }
                    if case .usbDevice(_, _, let hash, _) = entry.criterion { XCTAssertNil(hash) }
                }
            }
        }
    }

    /// `importable(current:)` runs last, on the merged and sanitized value (security L5).
    func testAwakeImportAppliesImportableLast() throws {
        var current = AwakeConfig()
        current.indicator.glyph = .lightbulb
        current = current.sanitized()
        let imported = json(["indicator": ["style": "iconAndEndTime"], "guards": ["batteryFloor": 45]])
        let result = try XCTUnwrap(KitBackup.importAwake(current: current, imported: imported))
        let before = try JSONEncoder().encode(current)
        let merged = try XCTUnwrap(KitBackup.merge(current: before, imported: imported, section: "awake"))
        let expected = try JSONDecoder().decode(AwakeConfig.self, from: merged).sanitized().importable(current: current)
        XCTAssertEqual(result, expected)
        XCTAssertNil(KitBackup.importAwake(current: current, imported: Data("[1]".utf8)))
        XCTAssertNil(KitBackup.importAwake(current: current, imported: Data("nope".utf8)))
    }

    /// Without the rules checkbox the section has no `triggers` key, so importing it keeps the Mac's rules.
    func testAwakeRulesAreOptIn() throws {
        var config = AwakeConfig()
        config.triggers.triggers = [AwakeTrigger(id: StableID(), name: "Desk", criteria: [AwakeCriterionEntry(.cpuAbove(percent: 50))])]
        let without = object(try XCTUnwrap(KitBackup.awakeSectionData(config, includeTriggers: false)))
        XCTAssertNil(without["triggers"])
        let with = object(try XCTUnwrap(KitBackup.awakeSectionData(config, includeTriggers: true)))
        XCTAssertNotNil(with["triggers"])
        for section in [without, with] {
            let text = awakeText(section)
            for banned in ["drives", "pointerNudge", "recentApps", "startAtLaunch", "commandLine"] {
                XCTAssertFalse(text.contains(banned), banned)
            }
        }
        // A section without rules laid over a Mac with rules keeps them.
        let current = json(["triggers": ["triggers": [["id": "R1", "name": "Desk"]]], "indicator": ["style": "icon"]])
        let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: json(["indicator": ["style": "iconAndTime"]]),
                                                          section: "awake")))
        XCTAssertEqual(((merged["triggers"] as? [String: Any])?["triggers"] as? [[String: Any]])?.count, 1)
    }

    /// Exporting the Mac's own settings and importing them back changes nothing the preview would show.
    func testAwakeOwnBackupRoundTripChangesNothing() throws {
        var current = AwakeConfig()
        current.features[.pointerNudge] = true
        current = current.sanitized()
        let section = try XCTUnwrap(KitBackup.awakeSectionData(current, includeTriggers: true))
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["awake": section], created: "t", appVersion: "0.3.0"))
        let parsed = try KitBackup.parseDocument(doc).get()
        let result = try XCTUnwrap(KitBackup.importAwake(current: current, imported: try XCTUnwrap(parsed["awake"])))
        XCTAssertEqual(result.features[.pointerNudge], true, "kept from the Mac, never from the file")
        XCTAssertEqual(result.drives, current.drives)
        XCTAssertGreaterThanOrEqual(result.guards.batteryFloor, current.guards.batteryFloor)
    }

    func testAwakeSafetyChangesComeFirst() throws {
        for path in ["features.activity", "features.driveAlive", "guards.batteryFloor", "guards.batteryFloorEnabled",
                     "activity.stopAfterHours", "triggers.triggers", "shortcuts.awake.toggle.keyCode",
                     "sessions.presets", "sessions.defaultOptions.activity", "sessions.behavior.keepDisplayOnWhileLocked",
                     "(all)"] {
            XCTAssertTrue(KitBackup.isSafetyRelated(section: "awake", path: path), path)
        }
        for path in ["indicator.style", "indicator.glyph", "sessions.lastCustomSeconds", "sessions.defaultPresetID"] {
            XCTAssertFalse(KitBackup.isSafetyRelated(section: "awake", path: path), path)
        }
        let old = json(["guards": ["batteryFloor": 20], "indicator": ["style": "icon"],
                        "sessions": ["defaultOptions": ["activity": "off"], "lastCustomSeconds": 600]])
        let new = json(["guards": ["batteryFloor": 30], "indicator": ["style": "iconAndTime"],
                        "sessions": ["defaultOptions": ["activity": "declare"], "lastCustomSeconds": 900]])
        let preview = KitBackup.previewChanges(section: "awake", from: old, to: new, limit: 1)
        XCTAssertEqual(preview.safety, ["guards.batteryFloor", "sessions.defaultOptions.activity"])
        XCTAssertEqual(preview.other, ["indicator.style"], "the rest is shortened, safety never is")
    }

    func testAwakeSectionIsKnown() {
        XCTAssertTrue(KitBackup.sections.contains("awake"))
        for path in [["awake", "drives"], ["awake", "features", "pointerNudge"],
                     ["awake", "sessions", "behavior", "startAtLaunch"], ["awake", "sessions", "recentApps"]] {
            XCTAssertTrue(KitBackup.removedPaths.contains(path), path.joined(separator: "."))
        }
        XCTAssertTrue(KitBackup.safetyPaths.contains(["awake", "guards"]))
    }
}
