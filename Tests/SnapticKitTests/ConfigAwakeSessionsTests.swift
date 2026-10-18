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
}
