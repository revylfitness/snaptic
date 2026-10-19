import XCTest
@testable import SnapticKit

final class ConfigAwakeSessionsTests: XCTestCase {
    private let text12 = AwakeTextContext(uses24Hour: false, decimalSeparator: ".")
    private let text24 = AwakeTextContext(uses24Hour: true, decimalSeparator: ",")
    private func derived(_ n: String) -> StableID { StableID.derived(namespace: "awake.preset.default", name: n) }

    func testDefaultPresetsInR5Order() {
        let c = AwakeSessionsConfig()
        XCTAssertEqual(c.presets.map(\.id), ["indefinite", "30m", "1h", "2h", "5h", "idle"].map(derived))
        XCTAssertEqual(c.presets.map { $0.title(text12) },
                       ["Until Turned Off", "For 30 Minutes", "For 1 Hour", "For 2 Hours", "For 5 Hours",
                        "Until Downloads and Tasks Finish"])
        XCTAssertTrue(c.presets.allSatisfy { $0.options == nil && $0.name == nil })
        XCTAssertNil(c.defaultPresetID)
        XCTAssertEqual(c.defaultPreset.kind, .indefinite, "nil default → Until Turned Off (C10)")
        XCTAssertEqual(c.lastCustomSeconds, 5_400)
        XCTAssertEqual(c.sanitized(), c)
        // Same ids on every construction.
        XCTAssertEqual(AwakeSessionsConfig().presets, c.presets)
        XCTAssertEqual(AwakeSessionsConfig.derivedPresetID("1h"), derived("1h"))
    }

    func testVerbTitles() {
        let presets = AwakeSessionsConfig().presets
        XCTAssertEqual(presets.map { $0.verbTitle(text12) },
                       ["Keep Awake Until Turned Off", "Keep Awake for 30 Minutes", "Keep Awake for 1 Hour",
                        "Keep Awake for 2 Hours", "Keep Awake for 5 Hours", "Keep Awake Until Downloads and Tasks Finish"])
        let five = AwakePreset(id: derived("x"), name: nil, kind: .untilTime(hour: 17, minute: 0), options: nil)
        XCTAssertEqual(five.verbTitle(text12), "Keep Awake Until 5:00 PM")
        XCTAssertEqual(five.title(text24), "Until 17:00")
        let named = AwakePreset(id: derived("n"), name: "  Deep Work ", kind: .duration(seconds: 5_400), options: nil)
        XCTAssertEqual(named.title(text12), "Deep Work")
        XCTAssertEqual(named.verbTitle(text12), "Keep Awake: Deep Work")
        XCTAssertEqual(AwakePresetKind.spanTitle(5_400), "1 Hour 30 Minutes")
        XCTAssertEqual(AwakePresetKind.spanTitle(60), "1 Minute")
        XCTAssertEqual(AwakePresetKind.spanTitle(90), "2 Minutes")
        XCTAssertEqual(AwakePresetKind.spanTitle(2 * 86_400), "2 Days")
        XCTAssertEqual(AwakePresetKind.spanTitle(86_400 + 3_600), "25 Hours")
    }

    func testPresetKindCodable() throws {
        let kinds: [AwakePresetKind] = [.indefinite, .duration(seconds: 3_600), .untilTime(hour: 17, minute: 30),
                                        .untilIdle(UntilIdleSpec(), maxSeconds: nil), .untilIdle(UntilIdleSpec(quietSeconds: 600), maxSeconds: 7_200)]
        for k in kinds {
            let p = AwakePreset(id: derived("k"), name: nil, kind: k, options: AwakeSessionOptions(activity: .declare))
            XCTAssertEqual(try JSONDecoder().decode(AwakePreset.self, from: JSONEncoder().encode(p)), p)
        }
        for bad in [#"{"type":"hold"}"#, #"{"type":"duration"}"#, #"{"type":"untilTime","hour":5}"#, "{}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(AwakePresetKind.self, from: Data(bad.utf8)), bad)
        }
    }

    func testPresetSanitize() {
        let p = AwakePreset(id: derived("s"), name: " \u{0007} ", kind: .duration(seconds: 1), options:
                                AwakeSessionOptions(displayIdleMinutes: 0)).sanitized()
        XCTAssertNil(p.name, "blank names become generated")
        XCTAssertEqual(p.kind, .duration(seconds: 60))
        XCTAssertEqual(p.options?.displayIdleMinutes, 1)
        XCTAssertEqual(AwakePresetKind.untilTime(hour: 30, minute: -4).sanitized(), .untilTime(hour: 23, minute: 0))
        XCTAssertEqual(AwakePresetKind.untilIdle(UntilIdleSpec(quietSeconds: 5), maxSeconds: 99_999_999).sanitized(),
                       .untilIdle(UntilIdleSpec(quietSeconds: 60), maxSeconds: AwakeClock.maxSessionSeconds))
        let long = AwakePreset(id: derived("l"), name: String(repeating: "z", count: 99), kind: .indefinite, options: nil)
        XCTAssertEqual(long.sanitized().name?.unicodeScalars.count, 64)
    }

    func testSessionKindFromPreset() {
        XCTAssertEqual(AwakePresetKind.indefinite.sessionKind(untilUnixTime: nil), .indefinite)
        XCTAssertEqual(AwakePresetKind.duration(seconds: 1_800).sessionKind(untilUnixTime: nil), .duration(seconds: 1_800))
        XCTAssertNil(AwakePresetKind.untilTime(hour: 17, minute: 0).sessionKind(untilUnixTime: nil))
        XCTAssertNil(AwakePresetKind.untilTime(hour: 17, minute: 0).sessionKind(untilUnixTime: .nan))
        XCTAssertEqual(AwakePresetKind.untilTime(hour: 17, minute: 0).sessionKind(untilUnixTime: 99), .until(unixTime: 99))
        XCTAssertEqual(AwakePresetKind.untilIdle(UntilIdleSpec(), maxSeconds: 600).sessionKind(untilUnixTime: nil),
                       .untilIdle(UntilIdleSpec(), maxSeconds: 600))
    }

    func testLossyDecodeOneBadPresetKeepsTheOthersAndTheNextSave() throws {
        let a = derived("1h").rawValue, b = StableID().rawValue
        let json = """
        {"presets":[{"id":"\(a)","kind":{"type":"duration","seconds":3600}},{"id":"\(b)","kind":{"type":"teleport"}},
                    {"id":"bad","kind":{"type":"indefinite"}},{"id":"\(a)","kind":{"type":"indefinite"}},
                    {"id":"\(b)","kind":{"type":"untilTime","hour":17,"minute":0},"name":3,"options":"x"}],
         "defaultPresetID":"\(b)","defaultOptions":{"display":"maySleep"},"lastCustomSeconds":"x",
         "behavior":{"userSwitchEnd":"sometimes","endAfterLockedHours":4},"recentApps":["com.a.b",7,"com.a.b","com.c.d"]}
        """
        let c = try JSONDecoder().decode(AwakeSessionsConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.presets.map(\.id.rawValue), [a, b])
        XCTAssertEqual(c.presets[1].kind, .untilTime(hour: 17, minute: 0))
        XCTAssertNil(c.presets[1].name)
        XCTAssertNil(c.presets[1].options)
        XCTAssertEqual(c.defaultPresetID?.rawValue, b)
        XCTAssertEqual(c.defaultOptions.display, .maySleep)
        XCTAssertEqual(c.lastCustomSeconds, 5_400)
        XCTAssertEqual(c.behavior.userSwitchEnd, .afterHour)
        XCTAssertEqual(c.behavior.endAfterLockedHours, 4)
        XCTAssertEqual(c.recentApps, ["com.a.b", "com.c.d"])
        XCTAssertEqual(try JSONDecoder().decode(AwakeSessionsConfig.self, from: JSONEncoder().encode(c)), c)
        // An explicit empty list stays empty (the user deleted every preset).
        XCTAssertEqual(try JSONDecoder().decode(AwakeSessionsConfig.self, from: Data(#"{"presets":[]}"#.utf8)).presets, [])
        XCTAssertEqual(try JSONDecoder().decode(AwakeSessionsConfig.self, from: Data("{}".utf8)), AwakeSessionsConfig())
    }

    func testSanitize() {
        var c = AwakeSessionsConfig()
        c.presets += (0..<10).map { AwakePreset(id: StableID.derived(namespace: "extra", name: "\($0)"), name: nil,
                                                kind: .duration(seconds: 600 * ($0 + 1)), options: nil) }
        c.presets.append(c.presets[0])
        c.defaultPresetID = StableID.derived(namespace: "extra", name: "9")
        c.behavior.startAtLaunch = derived("2h")
        c.behavior.endAfterLockedHours = 2
        c.lastCustomSeconds = 0
        c.recentApps = ["com.a.b", "nope", "com.c.d", "com.a.b", "e.f", "g.h", "i.j", "k.l"]
        c.defaultOptions.displayIdleMinutes = 999
        let s = c.sanitized()
        XCTAssertEqual(s.presets.count, 12)
        XCTAssertNil(s.defaultPresetID, "the default fell off the list")
        XCTAssertEqual(s.behavior.startAtLaunch, derived("2h"))
        XCTAssertEqual(s.behavior.endAfterLockedHours, 4, "snaps up to a choice")
        XCTAssertEqual(s.lastCustomSeconds, 60)
        XCTAssertEqual(s.recentApps, ["com.a.b", "com.c.d", "e.f", "g.h", "i.j"])
        XCTAssertEqual(s.defaultOptions.displayIdleMinutes, 240)
        var gone = AwakeSessionsConfig()
        gone.behavior.startAtLaunch = StableID()
        XCTAssertNil(gone.sanitized().behavior.startAtLaunch)
        var behavior = AwakeBehavior()
        behavior.endAfterLockedHours = 0
        XCTAssertNil(behavior.sanitized().endAfterLockedHours)
        behavior.endAfterLockedHours = 50
        XCTAssertEqual(behavior.sanitized().endAfterLockedHours, 12)
        behavior.endAfterLockedHours = 1
        XCTAssertEqual(behavior.sanitized().endAfterLockedHours, 1)
    }

    func testDefaultPresetFallbacks() {
        var c = AwakeSessionsConfig()
        c.defaultPresetID = derived("2h")
        XCTAssertEqual(c.defaultPreset.id, derived("2h"))
        c.defaultPresetID = StableID()
        XCTAssertEqual(c.defaultPreset.id, derived("indefinite"))
        c.presets = []
        XCTAssertEqual(c.defaultPreset.kind, .indefinite)
        XCTAssertEqual(c.defaultPreset.id, derived("indefinite"))
        XCTAssertNil(c.preset(derived("1h")))
    }

    func testRecentApps() {
        var c = AwakeSessionsConfig()
        for app in ["a.one", "a.two", "a.three", "a.four", "a.five", "a.six", "a.two", "not valid"] {
            c = c.notingRecentApp(app)
        }
        XCTAssertEqual(c.recentApps, ["a.two", "a.six", "a.five", "a.four", "a.three"])
    }

    // MARK: Options (consistency M2, R5-11)

    func testEffectiveOptionsClampActivityToEffectiveFeatures() {
        var c = AwakeSessionsConfig()
        c.defaultOptions = AwakeSessionOptions(display: .maySleep, activity: .nudge)
        let kinds: [AwakeSessionKind] = [.indefinite, .duration(seconds: 60), .whileApp(bundleID: "a.b", maxSeconds: nil),
                                         .untilIdle(UntilIdleSpec(), maxSeconds: nil)]
        for kind in kinds {
            XCTAssertEqual(c.effectiveOptions(for: kind, preset: nil, effective: [.sessions, .activity, .pointerNudge]).activity,
                           .nudge)
            XCTAssertEqual(c.effectiveOptions(for: kind, preset: nil, effective: [.sessions, .activity]).activity, .declare)
            XCTAssertEqual(c.effectiveOptions(for: kind, preset: nil, effective: [.sessions, .pointerNudge]).activity, .off)
            XCTAssertEqual(c.effectiveOptions(for: kind, preset: nil, effective: [.sessions]).display, .maySleep,
                           "R5-11: the default display policy for every kind")
        }
        let own = AwakePreset(id: derived("o"), name: nil, kind: .indefinite,
                              options: AwakeSessionOptions(display: .keepOnWhileActive, displayIdleMinutes: 0, activity: .declare))
        let o = c.effectiveOptions(for: .indefinite, preset: own, effective: [.activity])
        XCTAssertEqual(o, AwakeSessionOptions(display: .keepOnWhileActive, displayIdleMinutes: 1, activity: .declare))
        XCTAssertEqual(c.defaultDisplayPolicy(for: .untilIdle(UntilIdleSpec(), maxSeconds: nil)), .maySleep)
        XCTAssertEqual(c.defaultDisplayPolicy(for: .indefinite), .maySleep)
    }

    func testActivitySwitches() {
        var c = AwakeConfig()
        c = c.settingAppearActive(true)
        XCTAssertEqual(c.features[.activity], true)
        XCTAssertEqual(c.sessions.defaultOptions.activity, .declare)
        c = c.settingPointerNudge(true)
        XCTAssertEqual(c.features[.pointerNudge], true)
        XCTAssertEqual(c.sessions.defaultOptions.activity, .nudge)
        c = c.settingPointerNudge(false)
        XCTAssertEqual(c.features[.pointerNudge], false)
        XCTAssertEqual(c.sessions.defaultOptions.activity, .declare)
        c = c.settingPointerNudge(true).settingAppearActive(false)
        XCTAssertEqual(c.features[.activity], false)
        XCTAssertEqual(c.features[.pointerNudge], false)
        XCTAssertEqual(c.sessions.defaultOptions.activity, .off)
        // Presets with explicit options keep theirs.
        XCTAssertEqual(c.sessions.presets, AwakeSessionsConfig().presets)
        XCTAssertEqual(c.settingKeepDisplayOn(false).sessions.defaultOptions.display, .maySleep)
        XCTAssertEqual(c.settingKeepDisplayOn(true).sessions.defaultOptions.display, .keepOn)
    }

    func testBehaviorDefaultsAndLossyDecode() throws {
        let b = AwakeBehavior()
        XCTAssertFalse(b.endOnSystemSleep)
        XCTAssertEqual(b.userSwitchEnd, .afterHour)
        XCTAssertNil(b.endAfterLockedHours)
        XCTAssertFalse(b.keepDisplayOnWhileLocked)
        XCTAssertTrue(b.resumeAfterRestart)
        XCTAssertNil(b.startAtLaunch)
        let d = try JSONDecoder().decode(AwakeBehavior.self, from: Data(#"{"endOnSystemSleep":true,"resumeAfterRestart":"x","startAtLaunch":"bad"}"#.utf8))
        XCTAssertTrue(d.endOnSystemSleep)
        XCTAssertTrue(d.resumeAfterRestart)
        XCTAssertNil(d.startAtLaunch)
    }

    // MARK: AwakeConfig transforms (step 2: restoringDefaults, exportable, importable)

    private let digest = String(repeating: "ab", count: 16)
    private func sid(_ n: String) -> StableID { StableID.derived(namespace: "test", name: n) }

    /// A config with every risky field set: nudge everywhere, volumes, start at launch, hashes, a low floor.
    private func hostile() -> AwakeConfig {
        var c = AwakeConfig()
        c.features[.pointerNudge] = true
        c.features[.activity] = true
        c.features[.driveAlive] = true
        c.sessions.defaultOptions.activity = .nudge
        c.sessions.presets.append(AwakePreset(id: sid("p"), name: "Nudge", kind: .duration(seconds: 600),
                                              options: AwakeSessionOptions(activity: .nudge)))
        c.sessions.behavior.startAtLaunch = sid("p")
        c.sessions.recentApps = ["com.apple.dt.Xcode"]
        var rule = AwakeTrigger(id: sid("r"), name: "Home", criteria: [
            AwakeCriterionEntry(.network(.router(hash: digest, label: "Home"))),
            AwakeCriterionEntry(.power(.onAdapter)),
        ])
        rule.options = AwakeSessionOptions(activity: .nudge)
        let plain = AwakeTrigger(id: sid("q"), name: "Plain", criteria: [AwakeCriterionEntry(.power(.onAdapter))])
        c.triggers.triggers = [rule, plain]
        let key = VolumeUUIDKey(rawValue: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        c.drives.volumes[key] = DriveAliveVolume(name: "Backup", enabled: true, firstWriteDone: true)
        c.drives.evenWithoutSession = true
        c.guards.batteryFloorEnabled = false
        c.guards.batteryFloor = 5
        c.indicator.style = .iconAndTime
        c.shortcuts[.toggle] = HotkeyCombo(keyCode: 0, carbonModifiers: 0x0900)
        return c
    }

    private func hasNudge(_ c: AwakeConfig) -> Bool {
        c.sessions.defaultOptions.activity == .nudge || c.sessions.presets.contains { $0.options?.activity == .nudge }
            || c.triggers.triggers.contains { $0.options.activity == .nudge }
    }

    func testRestoringDefaultsTurnsPointerMovementAndDrivesOff() {
        let r = hostile().restoringDefaults()
        XCTAssertNil(r.features[.pointerNudge])
        XCTAssertFalse(hasNudge(r))
        XCTAssertTrue(r.drives.volumes.values.isEmpty)
        XCTAssertFalse(r.drives.evenWithoutSession)
        XCTAssertEqual(r.sessions.presets, AwakeSessionsConfig().presets, "the default presets with their derived ids")
        XCTAssertEqual(r.sessions.presets.map(\.id), AwakeConfig().restoringDefaults().sessions.presets.map(\.id))
        XCTAssertNil(r.sessions.behavior.startAtLaunch)
        XCTAssertEqual(r.guards, AwakeGuardsConfig())
        // Other scopes and user content stay.
        XCTAssertEqual(r.triggers.triggers.map(\.id), [sid("r"), sid("q")])
        XCTAssertEqual(r.indicator.style, .iconAndTime)
        XCTAssertNotNil(r.shortcuts[.toggle])
        XCTAssertEqual(r.sessions.recentApps, ["com.apple.dt.Xcode"])
        XCTAssertEqual(AwakeConfig().restoringDefaults(), AwakeConfig().sanitized())
    }

    func testExportableStripsPersonalAndRiskyFields() throws {
        let e = hostile().exportable(includeTriggers: true)
        XCTAssertNil(e.features[.pointerNudge])
        XCTAssertEqual(e.features[.activity], true, "other feature choices travel")
        XCTAssertFalse(hasNudge(e))
        XCTAssertTrue(e.drives.volumes.values.isEmpty)
        XCTAssertTrue(e.sessions.recentApps.isEmpty)
        XCTAssertNil(e.sessions.behavior.startAtLaunch)
        XCTAssertEqual(e.triggers.triggers.count, 2)
        XCTAssertFalse(e.triggers.triggers[0].enabled, "lost its router condition")
        XCTAssertTrue(e.triggers.triggers[1].enabled)
        let json = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertFalse(json.contains(digest), "no salted hash leaves")
        XCTAssertFalse(json.contains("Backup"))
        XCTAssertTrue(hostile().exportable(includeTriggers: false).triggers.triggers.isEmpty, "rules are opt-in")
    }

    func testImportableNeverLoosensAnything() {
        var current = AwakeConfig()
        current.guards.batteryFloor = 30
        current.guards.endOnLowPowerMode = true
        let key = VolumeUUIDKey(rawValue: "1F9619FF-8B86-D011-B42D-00C04FC964FF")!
        current.drives.volumes[key] = DriveAliveVolume(name: "Mine", enabled: false)
        current.sessions.recentApps = ["com.apple.Safari"]
        let i = hostile().importable(current: current)
        XCTAssertNil(i.features[.pointerNudge], "kept from current")
        XCTAssertFalse(hasNudge(i))
        XCTAssertEqual(Array(i.drives.volumes.values.keys), [key], "volumes kept from current")
        XCTAssertFalse(i.drives.evenWithoutSession)
        XCTAssertEqual(i.sessions.recentApps, ["com.apple.Safari"])
        XCTAssertNil(i.sessions.behavior.startAtLaunch)
        XCTAssertTrue(i.guards.batteryFloorEnabled, "guards only tighten")
        XCTAssertEqual(i.guards.batteryFloor, 30)
        XCTAssertTrue(i.guards.endOnLowPowerMode)
        XCTAssertFalse(i.triggers.triggers[0].enabled)
        var on = AwakeConfig()
        on.features[.pointerNudge] = true
        XCTAssertEqual(AwakeConfig().importable(current: on).features[.pointerNudge], true,
                       "an import can't turn pointer movement off behind the user's back either")
        var stricter = AwakeConfig()
        stricter.guards.batteryFloor = 40
        XCTAssertEqual(stricter.importable(current: current).guards.batteryFloor, 40)
    }

    func testImportedConfigSurvivesARoundTrip() throws {
        let i = hostile().importable(current: AwakeConfig())
        let back = try JSONDecoder().decode(AwakeConfig.self, from: JSONEncoder().encode(i))
        XCTAssertEqual(back.sanitized(), i)
    }

    // MARK: Sessions sheet

    func testKindSwitchingCarriesValuesOver() {
        let hour = AwakePresetKind.duration(seconds: 3_600)
        XCTAssertEqual(hour.choice, .duration)
        XCTAssertEqual(hour.switched(to: .duration), hour, "the same kind keeps its values")
        XCTAssertEqual(hour.switched(to: .untilIdle), .untilIdle(UntilIdleSpec(), maxSeconds: 3_600), "length → cap")
        XCTAssertEqual(AwakePresetKind.duration(seconds: 1_800).switched(to: .untilIdle),
                       .untilIdle(UntilIdleSpec(), maxSeconds: 3_600), "the next At most choice")
        XCTAssertEqual(AwakePresetKind.duration(seconds: 3 * 3_600).switched(to: .untilIdle),
                       .untilIdle(UntilIdleSpec(), maxSeconds: 4 * 3_600))
        XCTAssertEqual(AwakePresetKind.duration(seconds: 86_400).switched(to: .untilIdle),
                       .untilIdle(UntilIdleSpec(), maxSeconds: 12 * 3_600), "at most 12 hours")
        XCTAssertEqual(AwakePresetKind.untilIdle(UntilIdleSpec(), maxSeconds: 7_200).switched(to: .duration),
                       .duration(seconds: 7_200), "cap → length")
        XCTAssertEqual(AwakePresetKind.untilIdle(UntilIdleSpec(), maxSeconds: nil).switched(to: .duration),
                       .duration(seconds: 3_600))
        XCTAssertEqual(hour.switched(to: .untilTime), .untilTime(hour: 17, minute: 0))
        XCTAssertEqual(AwakePresetKind.indefinite.switched(to: .untilIdle), .untilIdle(UntilIdleSpec(), maxSeconds: nil))
        XCTAssertEqual(hour.switched(to: .indefinite), .indefinite)
        for from in [AwakePresetKind.indefinite, hour, .untilTime(hour: 9, minute: 30),
                     .untilIdle(UntilIdleSpec(), maxSeconds: 600)] {
            for to in AwakePresetKindChoice.allCases {
                let k = from.switched(to: to)
                XCTAssertEqual(k.choice, to)
                XCTAssertEqual(k.sanitized(), k, "every switch lands in range")
            }
        }
    }

    func testAddAndRemoveSessions() {
        var c = AwakeSessionsConfig()
        let id = StableID()
        c = c.addingPreset(id: id) ?? c
        XCTAssertEqual(c.presets.count, 7)
        XCTAssertEqual(c.presets.last?.kind, .duration(seconds: 3_600))
        XCTAssertNil(c.addingPreset(id: id), "an existing id isn't added twice")
        c.defaultPresetID = id
        c.behavior.startAtLaunch = id
        c = c.removingPreset(id)
        XCTAssertEqual(c.presets.count, 6)
        XCTAssertNil(c.defaultPresetID)
        XCTAssertNil(c.behavior.startAtLaunch)
        var full = AwakeSessionsConfig()
        while let next = full.addingPreset(id: StableID()) { full = next }
        XCTAssertEqual(full.presets.count, AwakeSessionsConfig.maxPresets)
        var one = AwakeSessionsConfig()
        one.presets = [one.presets[0]]
        XCTAssertEqual(one.removingPreset(one.presets[0].id), one, "the last session stays")
    }

    func testRestoringDefaultSessions() {
        var c = AwakeSessionsConfig()
        let id = StableID()
        c = c.addingPreset(id: id) ?? c
        c.defaultPresetID = id
        c.behavior.startAtLaunch = id
        c.behavior.endOnSystemSleep = true
        let r = c.restoringDefaultPresets()
        XCTAssertEqual(r.presets, AwakeSessionsConfig.defaultPresets)
        XCTAssertNil(r.defaultPresetID)
        XCTAssertNil(r.behavior.startAtLaunch, "a removed session can't start at launch")
        XCTAssertTrue(r.behavior.endOnSystemSleep, "other settings stay")
        c.behavior.startAtLaunch = derived("1h")
        XCTAssertEqual(c.restoringDefaultPresets().behavior.startAtLaunch, derived("1h"))
    }
}
