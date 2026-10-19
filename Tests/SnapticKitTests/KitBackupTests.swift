import XCTest
@testable import SnapticKit

final class KitBackupTests: XCTestCase {
    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    private func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }

    private var displays: [String: Any] {
        ["features": ["brightness": true, "disconnect": true, "dimToBlack": true, "hooks": true],
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
        for banned in ["automation", "disconnect", "dimToBlack", "unlocks", "trustStamp", "saltHint",
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

    private func safetyDisplays(ignore: Bool, withoutDDC: Bool, gamma: Bool, prefixes: [String]) -> [String: Any] {
        ["management": ["autoDisconnectWithoutDDC": withoutDDC, "snapArrangement": true],
         "perDisplay": [keyA: ["management": ["ignoreForAutoDisconnect": ignore, "powerSwitch": "none"]],
                        keyB: ["management": ["ignoreForAutoDisconnect": ignore], "brightness": ["minHardware": 0.1]]],
         "color": ["allowGammaWithCustomProfile": gamma, "shortcutStep": 0.1],
         "resolution": ["allowBelow720p": true, "sliderSnapping": true],
         "pip": ["protectedBundlePrefixes": prefixes, "pauseWhenOccluded": true]]
    }

    func testSafetySwitchesNeverLeaveOrEnter() throws {
        let unsafe = safetyDisplays(ignore: true, withoutDDC: true, gamma: true, prefixes: ["com.x"])
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["displays": json(unsafe)], created: "t", appVersion: "1"))
        let text = String(decoding: doc, as: UTF8.self)
        for banned in ["ignoreForAutoDisconnect", "autoDisconnectWithoutDDC", "allowGammaWithCustomProfile",
                       "allowBelow720p"] {
            XCTAssertFalse(text.contains(banned), banned)
        }
        for kept in ["powerSwitch", "snapArrangement", "shortcutStep", "sliderSnapping", "minHardware", "com.x"] {
            XCTAssertTrue(text.contains(kept), kept)
        }

        // A hand-made file that carries them anyway: stripped, and the current values stay.
        let file: [String: Any] = ["format": KitBackup.format, "version": 1, "sections": ["displays": unsafe]]
        let parsed = try KitBackup.parseDocument(json(file)).get()
        let current = json(safetyDisplays(ignore: false, withoutDDC: false, gamma: false, prefixes: ["com.x"]))
        let merged = object(try XCTUnwrap(KitBackup.merge(current: current, imported: parsed["displays"]!,
                                                          section: "displays")))
        let management = merged["management"] as? [String: Any]
        XCTAssertEqual(management?["autoDisconnectWithoutDDC"] as? Bool, false)
        let perDisplay = merged["perDisplay"] as? [String: [String: Any]]
        for key in [keyA, keyB] {
            let m = perDisplay?[key]?["management"] as? [String: Any]
            XCTAssertEqual(m?["ignoreForAutoDisconnect"] as? Bool, false, key)
        }
        XCTAssertEqual((merged["color"] as? [String: Any])?["allowGammaWithCustomProfile"] as? Bool, false)
    }

    func testWildcardRemovalReachesEveryDisplayOnly() {
        let input: [String: Any] = ["perDisplay": [keyA: ["management": ["ignoreForAutoDisconnect": true, "powerSwitch": "x"]],
                                                   keyB: "not an object"],
                                    "management": ["ignoreForAutoDisconnect": true]]
        let out = KitBackup.strip(input, section: "displays") as? [String: Any]
        let a = ((out?["perDisplay"] as? [String: Any])?[keyA] as? [String: Any])?["management"] as? [String: Any]
        XCTAssertNil(a?["ignoreForAutoDisconnect"])
        XCTAssertEqual(a?["powerSwitch"] as? String, "x")
        XCTAssertEqual((out?["perDisplay"] as? [String: Any])?[keyB] as? String, "not an object")
        // Only the listed path: a same-named key elsewhere stays.
        XCTAssertEqual((out?["management"] as? [String: Any])?["ignoreForAutoDisconnect"] as? Bool, true)
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

    // MARK: Seeded fuzz and nesting depth (code review F5)

    private func pick<T>(_ items: [T], _ g: inout SeededGenerator) -> T { items[Int(g.next() % UInt64(items.count))] }

    private static let fuzzKeys = ["unlocks", "trustStamp", "hash", "uidHash", "serialHash", "record", "pointerNudge",
                                   "drives", "commandLine", "allowWithoutAsking", "saltHint", "secretX", "tokenY",
                                   "recentApps", "startAtLaunch", "id", "triggers", "guards", "batteryFloor",
                                   "batteryFloorEnabled", "activity", "features", "sessions", "presets", "automation",
                                   "disconnect", "hooks", "x"]

    /// A random JSON value, at most `depth` more levels deep.
    private func garbage(_ g: inout SeededGenerator, depth: Int) -> Any {
        switch g.next() % (depth > 0 ? 8 : 5) {
        case 0: return Int(g.next() % 2_001) - 1_000
        case 1: return pick(["", "x", "nudge", "declare", "keepOn", "router", "network", "∞", volumeID, digest], &g)
        case 2: return g.next() % 2 == 0
        case 3: return NSNull()
        case 4: return Double(Int(g.next() % 10_000)) / 7
        case 5: return (0..<Int(g.next() % 4)).map { _ in garbage(&g, depth: depth - 1) }
        case 6:
            // An id-carrying list element (merged by id), built key by key: a picked key may be "id" too.
            var row: [String: Any] = [pick(Self.fuzzKeys, &g): garbage(&g, depth: depth - 1)]
            row["id"] = pick(["R1", "B1C2D3E4-0000-4000-8000-000000000001", "7"], &g)
            return [row]
        default:
            var out: [String: Any] = [:]
            for _ in 0..<Int(g.next() % 4) { out[pick(Self.fuzzKeys, &g)] = garbage(&g, depth: depth - 1) }
            return out
        }
    }

    /// One mutation somewhere in `value`: drop, replace or duplicate a key, insert a protected one, wrap in more
    /// nesting, or swap the type.
    private func mutate(_ value: Any, _ g: inout SeededGenerator) -> Any {
        if var dict = value as? [String: Any], !dict.isEmpty, g.next() % 3 != 0 {
            let key = pick(dict.keys.sorted(), &g)
            switch g.next() % 6 {
            case 0: dict[key] = nil
            case 1: dict[key] = garbage(&g, depth: 3)
            case 2: dict[key + pick(["", "2", "Copy"], &g)] = dict[key]
            case 3: dict[pick(Self.fuzzKeys, &g)] = garbage(&g, depth: 2)
            default: if let child = dict[key] { dict[key] = mutate(child, &g) }
            }
            return dict
        }
        if var array = value as? [Any], !array.isEmpty, g.next() % 3 != 0 {
            let i = Int(g.next() % UInt64(array.count))
            switch g.next() % 4 {
            case 0: array.remove(at: i)
            case 1: array.append(array[i])
            default: array[i] = mutate(array[i], &g)
            }
            return array
        }
        switch g.next() % 3 {
        case 0:
            var wrapped = value
            for _ in 0..<Int(g.next() % 80) { wrapped = g.next() % 2 == 0 ? [wrapped] : ["x": wrapped] }
            return wrapped
        default:
            return garbage(&g, depth: 3)
        }
    }

    /// Every key below `object` with its path; array elements add "[]" (never matching a "*" display key). The
    /// input passed `maxDepth`, so this recursion is bounded.
    private func keyPaths(_ object: Any, _ path: [String] = [], into out: inout [[String]]) {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                out.append(path + [key])
                keyPaths(value, path + [key], into: &out)
            }
        } else if let array = object as? [Any] {
            for value in array { keyPaths(value, path + ["[]"], into: &out) }
        }
    }

    private var fuzzBase: [String: Any] {
        var config = AwakeConfig()
        config.triggers.triggers = [AwakeTrigger(id: StableID(), name: "Desk",
                                                 criteria: [AwakeCriterionEntry(.cpuAbove(percent: 50))])]
        let awake = object(KitBackup.awakeSectionData(config, includeTriggers: true) ?? Data())
        return ["format": KitBackup.format, "version": 1, "created": "t", "snaptic": "0.3.0",
                "sections": ["displays": displays, "modules": modules, "awake": awake.merging(hostileAwake) { a, _ in a },
                             "switcher": ["shortcuts": [["id": "S1", "keyCode": 48]], "allowList": ["x"]]]]
    }

    /// Seeded mutations of a valid document: no trap, nothing protected ever comes in, strip is idempotent, and the
    /// typed Awake import never loosens what it guards (security L5).
    func testSeededFuzzImportNeverTrapsOrLetsProtectedFieldsIn() throws {
        var g = SeededGenerator(seed: 0x5EED_BAC0)
        var current = AwakeConfig()
        current.guards.batteryFloor = 25
        current.features[.pointerNudge] = false
        current = current.sanitized()
        let currentData = try JSONEncoder().encode(current)
        var accepted = 0
        for round in 0..<400 {
            // Mostly inside the sections (so most documents stay importable), sometimes the wrapper too.
            var sections = try XCTUnwrap(fuzzBase["sections"] as? [String: Any])
            for _ in 0...(g.next() % 4) {
                let name = pick(sections.keys.sorted(), &g)
                if let section = sections[name] { sections[name] = mutate(section, &g) }
            }
            var wrapper = fuzzBase
            wrapper["sections"] = sections
            let doc: Any = g.next() % 10 == 0 ? mutate(wrapper, &g) : wrapper as Any
            guard JSONSerialization.isValidJSONObject(doc),
                  let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) else { continue }
            let deep = KitBackup.nestingDepth(data, limit: KitBackup.maxDepth) == nil
            guard case .success(let parsed) = KitBackup.parseDocument(data) else { continue }
            XCTAssertFalse(deep, "round \(round): a document deeper than maxDepth was accepted")
            accepted += 1
            for (name, sectionData) in parsed {
                let section = try XCTUnwrap((try? JSONSerialization.jsonObject(with: sectionData)) as? [String: Any])
                var paths: [[String]] = []
                keyPaths(section, into: &paths)
                for path in paths {
                    let key = path[path.count - 1]
                    XCTAssertFalse(KitBackup.isSensitive(key), "round \(round): \(name).\(path)")
                    XCTAssertFalse(KitBackup.sectionSensitiveKeys[name]?.contains(key) ?? false, "round \(round): \(path)")
                    for removed in KitBackup.removedPaths where removed.first == name {
                        let pattern = Array(removed.dropFirst())
                        let hit = pattern.count == path.count && zip(pattern, path).allSatisfy { $0 == "*" || $0 == $1 }
                        XCTAssertFalse(hit, "round \(round): \(name).\(path.joined(separator: "."))")
                    }
                }
                if let allowed = KitBackup.allowedPaths[name] {
                    XCTAssertTrue(Set(section.keys).isSubset(of: Set(allowed.compactMap(\.first))), "round \(round)")
                }
                // Stripping again changes nothing.
                XCTAssertEqual(canonical(json(KitBackup.strip(section, section: name))), canonical(sectionData),
                               "round \(round): strip isn't idempotent for \(name)")
                _ = KitBackup.previewChanges(section: name, from: sectionData, to: sectionData)
            }
            if let awake = parsed["awake"] {
                XCTAssertNotNil(KitBackup.merge(current: currentData, imported: awake, section: "awake"))
                guard let result = KitBackup.importAwake(current: current, imported: awake) else { continue }
                XCTAssertEqual(result.features[.pointerNudge], current.features[.pointerNudge], "round \(round)")
                XCTAssertEqual(result.drives, current.drives, "round \(round)")
                XCTAssertEqual(result.sessions.recentApps, current.sessions.recentApps, "round \(round)")
                XCTAssertEqual(result.sessions.behavior.startAtLaunch, current.sessions.behavior.startAtLaunch)
                XCTAssertTrue(result.guards.batteryFloorEnabled, "round \(round)")
                XCTAssertGreaterThanOrEqual(result.guards.effectiveFloor, current.guards.effectiveFloor, "round \(round)")
                XCTAssertNotEqual(result.sessions.defaultOptions.activity, .nudge, "round \(round)")
                XCTAssertFalse(result.sessions.presets.contains { $0.options?.activity == .nudge }, "round \(round)")
                XCTAssertFalse(result.triggers.triggers.contains { $0.options.activity == .nudge }, "round \(round)")
            }
        }
        XCTAssertGreaterThan(accepted, 200, "the fuzz should mostly produce importable documents")
    }

    /// Random bytes, truncations and byte flips of a valid document never trap.
    func testSeededFuzzRawBytesNeverTrap() throws {
        var g = SeededGenerator(seed: 0xB17E_5)
        let valid = json(fuzzBase)
        for _ in 0..<300 {
            var bytes = [UInt8](valid)
            switch g.next() % 3 {
            case 0: bytes = Array(bytes.prefix(Int(g.next() % UInt64(bytes.count))))
            case 1:
                for _ in 0..<(1 + Int(g.next() % 8)) {
                    bytes[Int(g.next() % UInt64(bytes.count))] = pick(Array("{}[]\",:\\0a".utf8) + [0xFF, 0x00], &g)
                }
            default: bytes = (0..<Int(g.next() % 512)).map { _ in UInt8(truncatingIfNeeded: g.next()) }
            }
            let data = Data(bytes)
            _ = KitBackup.parseDocument(data)
            _ = KitBackup.importAwake(current: AwakeConfig(), imported: data)
            _ = KitBackup.merge(current: valid, imported: data, section: "awake")
            _ = KitBackup.changedPaths(from: valid, to: data)
        }
    }

    /// A 1 MB `[[[[…` file (or an object chain) is refused before anything recursive or JSONSerialization sees it.
    func testDeepNestingIsRefusedWithoutRecursion() throws {
        let depth = KitBackup.maxBytes / 2 - 200
        func wrapped(_ inner: String) -> Data {
            Data(("{\"format\":\"\(KitBackup.format)\",\"version\":1,\"sections\":{\"awake\":{\"guards\":" + inner
                  + "}}}").utf8)
        }
        let arrays = wrapped(String(repeating: "[", count: depth) + String(repeating: "]", count: depth))
        XCTAssertLessThanOrEqual(arrays.count, KitBackup.maxBytes)
        XCTAssertNil(KitBackup.nestingDepth(arrays, limit: KitBackup.maxDepth))
        XCTAssertEqual(KitBackup.parseDocument(arrays), .failure(.wrongFormat))
        let chain = String(repeating: "{\"x\":", count: depth / 4) + "1" + String(repeating: "}", count: depth / 4)
        XCTAssertEqual(KitBackup.parseDocument(wrapped(chain)), .failure(.wrongFormat))
        XCTAssertNil(KitBackup.importAwake(current: AwakeConfig(), imported: Data(chain.utf8)))
        XCTAssertNil(KitBackup.merge(current: Data("{}".utf8), imported: Data(chain.utf8), section: "awake"))
        XCTAssertEqual(KitBackup.changedPaths(from: Data("{}".utf8), to: Data(chain.utf8)), ["(all)"])
        // Unclosed: still refused, still linear.
        XCTAssertEqual(KitBackup.parseDocument(Data(String(repeating: "[", count: depth).utf8)), .failure(.wrongFormat))
    }

    /// UTF-16 and UTF-32 input is refused before the depth scan (security S2-2): in UTF-16LE a character whose high
    /// byte is 0x5C right before a closing quote would make a byte scan think the quote is escaped and miss the
    /// nesting that follows.
    func testNonUTF8InputIsRefusedBeforeTheDepthScan() throws {
        let deep = String(repeating: "[", count: KitBackup.maxDepth * 4) + String(repeating: "]", count: KitBackup.maxDepth * 4)
        let text = "{\"format\":\"\(KitBackup.format)\",\"version\":1,\"x\":\"\u{5C41}\",\"sections\":{\"awake\":{\"guards\":"
            + deep + "}}}"
        let utf16 = try XCTUnwrap(text.data(using: .utf16LittleEndian))
        // The bypass the check exists for: the byte scan alone misses the nesting.
        XCTAssertNotNil(KitBackup.nestingDepth(utf16.filter { $0 != 0 }, limit: KitBackup.maxDepth))
        XCTAssertEqual(KitBackup.parseDocument(utf16), .failure(.wrongFormat))
        XCTAssertNil(KitBackup.nestingDepth(utf16, limit: KitBackup.maxDepth))
        for encoding: String.Encoding in [.utf16, .utf16BigEndian, .utf32, .utf32LittleEndian, .utf32BigEndian] {
            let data = try XCTUnwrap(text.data(using: encoding))
            XCTAssertFalse(KitBackup.isUTF8Text(data))
            XCTAssertEqual(KitBackup.parseDocument(data), .failure(.wrongFormat))
        }
        // A shallow, otherwise valid backup in UTF-16 is refused too; the same text in UTF-8 is accepted.
        let small = json(["format": KitBackup.format, "version": 1, "sections": ["awake": ["guards": ["batteryFloor": 20]]]])
        let smallText = try XCTUnwrap(String(data: small, encoding: .utf8))
        XCTAssertEqual(KitBackup.parseDocument(try XCTUnwrap(smallText.data(using: .utf16))), .failure(.wrongFormat))
        if case .failure(let error) = KitBackup.parseDocument(small) { XCTFail("UTF-8 refused: \(error)") }
        // A NUL byte or invalid UTF-8 anywhere is refused.
        XCTAssertFalse(KitBackup.isUTF8Text(Data([0x7B, 0x00, 0x7D])))
        XCTAssertFalse(KitBackup.isUTF8Text(Data([0x7B, 0xFF, 0x7D])))
        XCTAssertTrue(KitBackup.isUTF8Text(Data("{\"a\":\"\u{00E9}\\u0000\"}".utf8)))
        XCTAssertEqual(KitBackup.parseDocument(small + Data([0])), .failure(.wrongFormat))
    }

    func testNestingDepthCountsOnlyStructure() throws {
        XCTAssertEqual(KitBackup.nestingDepth(Data("1".utf8), limit: 4), 0)
        XCTAssertEqual(KitBackup.nestingDepth(Data("{\"a\":[1,{\"b\":[]}]}".utf8), limit: 4), 4)
        XCTAssertNil(KitBackup.nestingDepth(Data("{\"a\":[1,{\"b\":[]}]}".utf8), limit: 3))
        // Brackets inside strings, also after escaped quotes and backslashes, don't count.
        let text = "{\"a\":\"[[[[\\\"[[[\\\\\",\"b\":\"]]}}{{\"}"
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(text.utf8)))
        XCTAssertEqual(KitBackup.nestingDepth(Data(text.utf8), limit: 2), 1)
        // Exactly maxDepth is accepted, one more is not; isShallow agrees with the byte count.
        func nested(_ n: Int) -> String { String(repeating: "[", count: n) + String(repeating: "]", count: n) }
        let atLimit = Data(nested(KitBackup.maxDepth).utf8)
        XCTAssertEqual(KitBackup.nestingDepth(atLimit, limit: KitBackup.maxDepth), KitBackup.maxDepth)
        XCTAssertNil(KitBackup.nestingDepth(Data(nested(KitBackup.maxDepth + 1).utf8), limit: KitBackup.maxDepth))
        let object = try JSONSerialization.jsonObject(with: atLimit)
        XCTAssertTrue(KitBackup.isShallow(object, limit: KitBackup.maxDepth))
        XCTAssertFalse(KitBackup.isShallow(object, limit: KitBackup.maxDepth - 1))
        XCTAssertFalse(KitBackup.isShallow([[["x": [1]]]], limit: 3))
        XCTAssertTrue(KitBackup.isShallow("leaf", limit: 0))
        // strip drops what is too deep instead of walking it.
        var deep: Any = 1
        for _ in 0..<(KitBackup.maxDepth + 5) { deep = ["guards": deep] }
        XCTAssertEqual((KitBackup.strip(deep, section: "awake") as? [String: Any])?.count, 0)
        XCTAssertEqual((KitBackup.strip(deep, section: "displays") as? [String: Any])?.count, 0)
        // Real backups stay far below the limit.
        let awakeSection = (fuzzBase["sections"] as? [String: Any])?["awake"] ?? [String: Any]()
        let doc = try XCTUnwrap(KitBackup.makeDocument(sections: ["awake": json(awakeSection), "displays": json(displays)],
                                                         created: "t", appVersion: "0.3.0"))
        XCTAssertLessThan(try XCTUnwrap(KitBackup.nestingDepth(doc, limit: KitBackup.maxDepth)), 16)
    }
}
