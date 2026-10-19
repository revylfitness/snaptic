import XCTest
@testable import SnapticKit

final class AwakeSessionTests: XCTestCase {
    private let boot = "BOOT-A"
    private func now(_ continuous: Double = 10_000, wall: Double = 1_700_000_000) -> ClockNow {
        ClockNow(wall: wall, continuous: continuous, bootSession: boot)
    }
    private func id(_ n: String) -> StableID { StableID.derived(namespace: "test", name: n) }

    private func roundTrip<T: Codable>(_ v: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(v))
    }

    private func text<T: Encodable>(_ v: T) throws -> String {
        String(decoding: try JSONEncoder().encode(v), as: UTF8.self)
    }

    private func decodeSession(_ json: String) throws -> AwakeSession {
        try JSONDecoder().decode(AwakeSession.self, from: Data(json.utf8))
    }

    // MARK: Options and spec

    func testOptionsClampAndNudgeRemoval() throws {
        XCTAssertEqual(AwakeSessionOptions(displayIdleMinutes: 0).sanitized().displayIdleMinutes, 1)
        XCTAssertEqual(AwakeSessionOptions(displayIdleMinutes: 9_999).sanitized().displayIdleMinutes, 240)
        XCTAssertEqual(AwakeSessionOptions(activity: .nudge).withoutNudge().activity, .declare)
        XCTAssertEqual(AwakeSessionOptions(activity: .off).withoutNudge().activity, .off)
        let o = try JSONDecoder().decode(AwakeSessionOptions.self,
                                         from: Data(#"{"display":"bogus","displayIdleMinutes":"x","activity":"nudge"}"#.utf8))
        XCTAssertEqual(o, AwakeSessionOptions(display: .keepOn, displayIdleMinutes: 30, activity: .nudge))
    }

    func testUntilIdleSpecClampsEveryField() {
        let low = UntilIdleSpec(topProcessPercent: 0, newProcesses: 0, totalCPUPercent: 0, diskKBps: 0, networkKBps: 0,
                                quietSeconds: 0, minimumHoldSeconds: -5).sanitized()
        XCTAssertEqual(low, UntilIdleSpec(topProcessPercent: 10, newProcesses: 1, totalCPUPercent: 1, diskKBps: 64,
                                          networkKBps: 1, quietSeconds: 60, minimumHoldSeconds: 0))
        let high = UntilIdleSpec(topProcessPercent: .max, newProcesses: .max, totalCPUPercent: .max, diskKBps: .max,
                                 networkKBps: .max, quietSeconds: .max, minimumHoldSeconds: .max).sanitized()
        XCTAssertEqual(high, UntilIdleSpec(topProcessPercent: 800, newProcesses: 50, totalCPUPercent: 90,
                                           diskKBps: 1_000_000, networkKBps: 100_000, quietSeconds: 3_600,
                                           minimumHoldSeconds: 3_600))
        XCTAssertEqual(UntilIdleSpec().sanitized(), UntilIdleSpec())
    }

    // MARK: TaskQuiet

    private let quiet = TaskActivitySample(topProcessPercent: 1, newProcesses: 0, totalCPUPercent: 2, diskKBps: 10,
                                           networkKBps: 1)

    func testEachBusySignalAloneKeepsTheSession() {
        let spec = UntilIdleSpec()
        XCTAssertFalse(TaskQuiet.isBusy(quiet, spec: spec))
        var s = quiet; s.topProcessPercent = 50
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.newProcesses = 3
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.totalCPUPercent = 15
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.diskKBps = 1_024
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.networkKBps = 50
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        // Just under every threshold is quiet.
        let under = TaskActivitySample(topProcessPercent: 49.9, newProcesses: 2, totalCPUPercent: 14.9, diskKBps: 1_023.9,
                                       networkKBps: 49.9)
        XCTAssertFalse(TaskQuiet.isBusy(under, spec: spec))
    }

    func testUnknownOrNonFiniteSignalsAreBusy() {
        let spec = UntilIdleSpec()
        XCTAssertTrue(TaskQuiet.isBusy(.unknown, spec: spec))
        var s = quiet; s.diskKBps = nil
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.newProcesses = nil
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.totalCPUPercent = .nan
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
        s = quiet; s.networkKBps = .infinity
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: spec))
    }

    func testSingleThreadedLoadOnManyCoresStaysBusy() {
        // One core fully busy on a 12-core Mac: ~8% total, but the top process reads 100% of one core (parity M2).
        let s = TaskActivitySample(topProcessPercent: 100, newProcesses: 0, totalCPUPercent: 8.3, diskKBps: 0, networkKBps: 0)
        XCTAssertTrue(TaskQuiet.isBusy(s, spec: UntilIdleSpec()))
    }

    /// Runs samples every 5 s from `started` and returns the instant the session finished, or nil.
    private func run(_ samples: (Double) -> TaskActivitySample, started: Double = 0, until end: Double,
                     spec: UntilIdleSpec = UntilIdleSpec(), wakes: Set<Int> = []) -> Double? {
        var since: Double?
        var t = started
        var step = 0
        while t <= end {
            if wakes.contains(step) { since = nil }
            let r = TaskQuiet.step(quietSince: since, sample: samples(t), now: t, started: started, spec: spec)
            if r.finished { return t }
            since = r.quietSince
            t += 5
            step += 1
        }
        return nil
    }

    func testAllQuietEndsAfterQuietSecondsButNeverInsideTheMinimumHold() {
        // Quiet from the start: 5 min of quiet are reached at 300 s, but the 10-minute minimum hold wins.
        XCTAssertEqual(run({ _ in self.quiet }, until: 2_000), 600)
        // Without a minimum hold it ends at exactly quietSeconds.
        let spec = UntilIdleSpec(minimumHoldSeconds: 0)
        XCTAssertEqual(run({ _ in self.quiet }, until: 2_000, spec: spec), 300)
    }

    func testBusyStretchResetsTheQuietWindow() {
        let busy = TaskActivitySample(topProcessPercent: 300, newProcesses: 0, totalCPUPercent: 40, diskKBps: 0, networkKBps: 0)
        // Busy until 1_000 s, then quiet: ends 300 s after the first quiet sample.
        XCTAssertEqual(run({ $0 < 1_000 ? busy : self.quiet }, until: 3_000), 1_300)
    }

    func testUnknownSampleAndWakeResetTheWindow() {
        let spec = UntilIdleSpec(minimumHoldSeconds: 0)
        // An unknown sample at 200 s restarts the 5-minute window.
        XCTAssertEqual(run({ $0 == 200 ? .unknown : self.quiet }, until: 3_000, spec: spec), 505)
        // A wake (the app clears quietSince) at step 40 (200 s) restarts it too.
        XCTAssertEqual(run({ _ in self.quiet }, until: 3_000, spec: spec, wakes: [40]), 500)
    }

    func testLongLivedParentWithGrowingChildTimeStaysBusy() {
        // R5-4: the parent's child CPU grows 5 s per 5 s window → ≈ 100% of one core; CPUMath reports it as `top`.
        let make = TaskActivitySample(topProcessPercent: 100, newProcesses: 0, totalCPUPercent: 9, diskKBps: 20,
                                      networkKBps: 0)
        XCTAssertNil(run({ _ in make }, until: 10_000))
        // make -j1: no child alive at either sample instant, 0 new processes; the parent's reap delta reads 40% of a
        // core, which keeps a session busy whose threshold is below that.
        let serial = TaskActivitySample(topProcessPercent: 40, newProcesses: 0, totalCPUPercent: 4, diskKBps: 0,
                                        networkKBps: 0)
        XCTAssertNil(run({ _ in serial }, until: 10_000, spec: UntilIdleSpec(topProcessPercent: 30)))
    }

    func testQuietFor() {
        XCTAssertNil(TaskQuiet.quietFor(quietSince: nil, now: 100))
        XCTAssertEqual(TaskQuiet.quietFor(quietSince: 40, now: 100), 60)
        XCTAssertEqual(TaskQuiet.quietFor(quietSince: 200, now: 100), 0)
        XCTAssertNil(TaskQuiet.quietFor(quietSince: .nan, now: 100))
    }

    func testStepIgnoresAQuietSinceInTheFuture() {
        let r = TaskQuiet.step(quietSince: 500, sample: quiet, now: 100, started: 0, spec: UntilIdleSpec())
        XCTAssertEqual(r.quietSince, 100)
        XCTAssertFalse(r.finished)
    }

    // MARK: Kinds and sources

    func testKindProperties() {
        let idle = AwakeSessionKind.untilIdle(UntilIdleSpec(), maxSeconds: 7_200)
        XCTAssertTrue(AwakeSessionKind.duration(seconds: 60).isTimed)
        XCTAssertTrue(AwakeSessionKind.until(unixTime: 5).isTimed)
        XCTAssertFalse(AwakeSessionKind.indefinite.isTimed)
        XCTAssertFalse(idle.isTimed)
        XCTAssertEqual(idle.cap, 7_200)
        XCTAssertEqual(AwakeSessionKind.whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: nil).cap, nil)
        XCTAssertNil(AwakeSessionKind.duration(seconds: 60).cap)
        XCTAssertTrue(idle.isTaskBound)
        XCTAssertTrue(AwakeSessionKind.whileApp(bundleID: "a.b", maxSeconds: nil).isTaskBound)
        XCTAssertFalse(AwakeSessionKind.until(unixTime: 1).isTaskBound)
        XCTAssertEqual(idle.historyKind, .idle)
        XCTAssertEqual(AwakeSessionKind.whileApp(bundleID: "a.b", maxSeconds: nil).historyKind, .app)
    }

    func testDirectUserActionPerSource() {
        XCTAssertTrue(AwakeSessionSource.menu.isDirectUserAction)
        XCTAssertTrue(AwakeSessionSource.hotkey.isDirectUserAction)
        XCTAssertTrue(AwakeSessionSource.settings.isDirectUserAction)
        XCTAssertFalse(AwakeSessionSource.commandLine.isDirectUserAction)
        XCTAssertFalse(AwakeSessionSource.launch.isDirectUserAction)
        XCTAssertFalse(AwakeSessionSource.rule.isDirectUserAction)
    }

    func testKindCodableRoundTripsEveryCase() throws {
        let kinds: [AwakeSessionKind] = [
            .indefinite, .duration(seconds: 5_400), .until(unixTime: 1_700_000_123.5),
            .whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: nil), .whileApp(bundleID: "com.apple.Music", maxSeconds: 3_600),
            .untilIdle(UntilIdleSpec(quietSeconds: 120), maxSeconds: nil), .untilIdle(UntilIdleSpec(), maxSeconds: 43_200),
        ]
        for k in kinds { XCTAssertEqual(try roundTrip(k), k) }
        let obj = try text(AwakeSessionKind.duration(seconds: 5_400))
        XCTAssertTrue(obj.contains(#""type":"duration""#))
        XCTAssertTrue(obj.contains(#""seconds":5400"#))
        let idle = try text(AwakeSessionKind.untilIdle(UntilIdleSpec(), maxSeconds: nil))
        XCTAssertTrue(idle.contains(#""spec":{"#), "the spec sits whole under its own key")
        XCTAssertFalse(idle.contains("maxSeconds"))
    }

    func testUnknownKindsAndBrokenPayloadsThrow() {
        for text in [#"{"type":"hold","pid":4}"#, #"{"type":"teleport"}"#, #"{}"#, #"{"type":"duration"}"#,
                     #"{"type":"duration","seconds":"x"}"#, #"{"type":"until"}"#, #"{"type":"whileApp"}"#, "3"] {
            XCTAssertThrowsError(try JSONDecoder().decode(AwakeSessionKind.self, from: Data(text.utf8)), text)
        }
        // Optional parts are lossy.
        let k = try? JSONDecoder().decode(AwakeSessionKind.self,
                                          from: Data(#"{"type":"untilIdle","spec":7,"maxSeconds":"x"}"#.utf8))
        XCTAssertEqual(k, .untilIdle(UntilIdleSpec(), maxSeconds: nil))
    }

    func testHoldBindingOnlyProcessDecodes() throws {
        let process = HoldBinding.process(pid: 4_242, startTime: 1_700_000_000_123_456)
        XCTAssertEqual(try roundTrip(process), process)
        XCTAssertEqual(process.pid, 4_242)
        XCTAssertEqual(process.startTime, 1_700_000_000_123_456)
        XCTAssertTrue(process.isProcess)
        let connection = HoldBinding.connection(pid: 77, startTime: 9)
        XCTAssertFalse(connection.isProcess)
        XCTAssertEqual(connection.pid, 77)
        XCTAssertThrowsError(try roundTrip(connection))
        XCTAssertThrowsError(try JSONDecoder().decode(HoldBinding.self, from: Data(#"{"type":"process","pid":1}"#.utf8)))
    }

    // MARK: Session Codable and sanitize

    private func session(_ kind: AwakeSessionKind, source: AwakeSessionSource = .menu, at: Double = 10_000) -> AwakeSession {
        AwakeClock.start(kind, options: AwakeSessionOptions(), presetID: id("p"), source: source, now: now(at), id: id("s"))
    }

    func testSessionRoundTripKeepsSourceAndDropsOverride() throws {
        for source in [AwakeSessionSource.menu, .hotkey, .settings, .commandLine, .launch, .rule] {
            var s = session(.duration(seconds: 3_600), source: source)
            s.overrideGuards = true
            let back = try roundTrip(s)
            XCTAssertEqual(back.source, source)
            XCTAssertFalse(back.overrideGuards)
            s.overrideGuards = false
            XCTAssertEqual(back, s)
        }
        XCTAssertFalse(try text(session(.indefinite)).contains("override"))
    }

    func testSessionWithBadKindOrSourceIsDropped() throws {
        let sid = id("s").rawValue
        let base = #""startedAt":5,"startedContinuous":6,"deadline":3606,"bootSession":"BOOT-A""#
        let good = #"{"id":"\#(sid)","kind":{"type":"duration","seconds":3600},"source":"menu",\#(base)}"#
        XCTAssertEqual(try decodeSession(good).kind, .duration(seconds: 3_600))
        XCTAssertThrowsError(try decodeSession(#"{"id":"\#(sid)","kind":{"type":"hold"},"source":"menu",\#(base)}"#))
        XCTAssertThrowsError(try decodeSession(#"{"id":"\#(sid)","kind":{"type":"indefinite"},"source":"telepathy",\#(base)}"#))
        XCTAssertThrowsError(try decodeSession(#"{"id":"nope","kind":{"type":"indefinite"},"source":"menu",\#(base)}"#))
        let lossy = try decodeSession(#"{"id":"\#(sid)","kind":{"type":"indefinite"},"source":"launch","options":"x","startedAt":"y"}"#)
        XCTAssertEqual(lossy.options, AwakeSessionOptions())
        XCTAssertEqual(lossy.startedAt, 0)
        XCTAssertEqual(lossy.source, .launch)
        XCTAssertNil(lossy.deadline)
    }

    func testSanitizedKeepsValidSessionsOfEveryKind() {
        let kinds: [AwakeSessionKind] = [
            .indefinite, .duration(seconds: 3_600), .until(unixTime: 1_700_000_000 + 7_200),
            .whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: nil), .whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: 3_600),
            .untilIdle(UntilIdleSpec(), maxSeconds: nil), .untilIdle(UntilIdleSpec(), maxSeconds: 3_600),
        ]
        for k in kinds {
            let s = session(k)
            XCTAssertEqual(s.sanitized(now: now(10_100, wall: 1_700_000_100)), s, "\(k)")
        }
    }

    func testSanitizedBounds() {
        let later = now(10_100, wall: 1_700_000_100)
        // Other boot, rule source, start after now.
        var s = session(.duration(seconds: 3_600))
        s.bootSession = "BOOT-B"
        XCTAssertNil(s.sanitized(now: later))
        XCTAssertNil(session(.duration(seconds: 3_600), source: .rule).sanitized(now: later))
        XCTAssertNil(session(.duration(seconds: 3_600), at: 20_000).sanitized(now: later))
        // Expired.
        XCTAssertNil(session(.duration(seconds: 60)).sanitized(now: now(10_061)))
        // Deadline beyond the kind (r3 security L3).
        s = session(.duration(seconds: 3_600))
        s.deadline = s.startedContinuous + 90_000
        XCTAssertNil(s.sanitized(now: later))
        s.deadline = nil
        XCTAssertNil(s.sanitized(now: later))
        // Duration out of range.
        s = session(.duration(seconds: 3_600))
        s.kind = .duration(seconds: 10)
        s.deadline = s.startedContinuous + 10
        XCTAssertNil(s.sanitized(now: now(10_001)))
        s.kind = .duration(seconds: AwakeClock.maxSessionSeconds + 1)
        s.deadline = s.startedContinuous + Double(AwakeClock.maxSessionSeconds + 1)
        XCTAssertNil(s.sanitized(now: later))
        // Indefinite with a deadline, until with a deadline or beyond 30 days.
        s = session(.indefinite)
        s.deadline = 99_999
        XCTAssertNil(s.sanitized(now: later))
        s = session(.until(unixTime: 1_700_000_000 + Double(AwakeClock.maxSessionSeconds) + 100))
        XCTAssertNil(s.sanitized(now: later))
        s = session(.until(unixTime: 1_700_000_000 + 600))
        s.deadline = 10_600
        XCTAssertNil(s.sanitized(now: later))
        // Cap and deadline disagree.
        s = session(.whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: 3_600))
        s.deadline = s.startedContinuous + 7_200
        XCTAssertNil(s.sanitized(now: later))
        s.deadline = nil
        XCTAssertNil(s.sanitized(now: later))
        s = session(.untilIdle(UntilIdleSpec(), maxSeconds: nil))
        s.deadline = 20_000
        XCTAssertNil(s.sanitized(now: later))
        // Bad bundle id.
        XCTAssertNil(session(.whileApp(bundleID: "not a bundle", maxSeconds: nil)).sanitized(now: later))
        // Non-finite times.
        s = session(.indefinite)
        s.startedContinuous = .nan
        XCTAssertNil(s.sanitized(now: later))
    }

    func testSanitizedClampsOptionsAndSpecAndClearsOverride() {
        var s = session(.untilIdle(UntilIdleSpec(), maxSeconds: nil))
        s.kind = .untilIdle(UntilIdleSpec(quietSeconds: 1), maxSeconds: nil)
        s.options.displayIdleMinutes = 10_000
        s.overrideGuards = true
        let out = s.sanitized(now: now(10_010))
        XCTAssertEqual(out?.kind, .untilIdle(UntilIdleSpec(quietSeconds: 60), maxSeconds: nil))
        XCTAssertEqual(out?.options.displayIdleMinutes, 240)
        XCTAssertEqual(out?.overrideGuards, false)
    }

    // MARK: Holds

    private func hold(cap: Int = 3_600, at: Double = 10_000, pid: Int32 = 500) -> AwakeHold {
        AwakeClock.hold(.process(pid: pid, startTime: 7), capSeconds: cap, now: now(at), id: id("h\(pid)"))
    }

    func testHoldRoundTripAndConnectionHoldsNeverDecode() throws {
        let h = hold()
        XCTAssertEqual(try roundTrip(h), h)
        var c = h
        c.binding = .connection(pid: 600, startTime: 1)
        XCTAssertThrowsError(try roundTrip(c))
        XCTAssertEqual(AwakeHold.maxHolds, 8)
    }

    func testHoldSanitizedBounds() {
        let h = hold()
        XCTAssertEqual(h.sanitized(now: now(10_100)), h)
        XCTAssertNil(h.sanitized(now: now(13_601)), "expired")
        XCTAssertNil(hold(at: 20_000).sanitized(now: now(10_100)), "started after now")
        var other = h
        other.bootSession = "BOOT-B"
        XCTAssertNil(other.sanitized(now: now(10_100)))
        var long = h
        long.deadline = h.startedContinuous + Double(AwakeClock.holdMaxCapSeconds) + 60
        XCTAssertNil(long.sanitized(now: now(10_100)))
        XCTAssertNil(hold(pid: 1).sanitized(now: now(10_100)))
        XCTAssertNil(hold(pid: -4).sanitized(now: now(10_100)))
        var nan = h
        nan.deadline = .infinity
        XCTAssertNil(nan.sanitized(now: now(10_100)))
        XCTAssertEqual(h.remaining(now: now(10_100)), 3_500)
        XCTAssertEqual(other.remaining(now: now(10_100)), 0)
    }

    // MARK: Governing and refusals

    func testGoverningSourceAndOptions() {
        XCTAssertNil(AwakeGoverning.inactive.source)
        XCTAssertFalse(AwakeGoverning.inactive.isActive)
        XCTAssertEqual(AwakeGoverning.manual(session(.indefinite, source: .commandLine)).source, .commandLine)
        let top = TriggerTop(id: id("t"), index: 0, options: AwakeSessionOptions(display: .maySleep), since: 1)
        XCTAssertEqual(AwakeGoverning.trigger(top).source, .rule)
        XCTAssertEqual(AwakeGoverning.trigger(top).options?.display, .maySleep)
        XCTAssertEqual(AwakeGoverning.holds([hold()]).source, .commandLine)
        XCTAssertEqual(AwakeGoverning.holds([hold()]).options?.display, .maySleep)
        XCTAssertTrue(AwakeGoverning.holds([hold()]).isActive)
    }

    func testRefusalExitCodesAndTexts() {
        let all: [AwakeRefusal] = [.guardActive(.batteryLow), .guardActive(.lowPowerMode), .guardActive(.thermal),
                                   .guardActive(.adapterDisconnected), .guardActive(.user), .unavailable(.featureOff),
                                   .unavailable(.safeMode), .unavailable(.turnedOffByDefaults), .invalid,
                                   .notAllowedFromCLI, .uiSessionRunning, .holdLimit,
                                   .endedAtStart(.userSwitch), .endedAtStart(.lockedTooLong),
                                   .endedAtStart(.assertionFailed), .endedAtStart(.systemSleep)]
        for r in all {
            XCTAssertEqual(r.exitCode, 4)
            XCTAssertFalse(r.text.isEmpty)
            XCTAssertNotEqual(r.text, "Not built yet")
        }
        XCTAssertEqual(Set(all.map(\.text)).count, all.count, "every refusal reads differently")
        XCTAssertEqual(AwakeRefusal.holdLimit.text, "Snaptic is already holding for 8 commands.")
        // N2: a start its own first arbitration ended says why, not "can't start".
        XCTAssertEqual(AwakeRefusal.endedAtStart(.userSwitch).text, "Awake ended at once: another user is using this Mac.")
        XCTAssertEqual(AwakeRefusal.endedAtStart(.systemSleep).text, "Awake ended at once: your Mac went to sleep.")
        // A kill switch reads the same everywhere (review ux m9).
        XCTAssertEqual(AwakeRefusal.unavailable(.turnedOffByDefaults).text, DefaultsLock.text)
        XCTAssertEqual(AwakeRefusal.uiSessionRunning.text,
                       "A session started in Snaptic is running. Stop it first with “snaptic awake stop”, or use “snaptic awake hold”.")
    }

    func testEndReasonsUserEnds() {
        XCTAssertTrue(AwakeEndReason.user.isUserEnd)
        XCTAssertTrue(AwakeEndReason.replaced.isUserEnd)
        XCTAssertFalse(AwakeEndReason.batteryLow.isUserEnd)
        XCTAssertFalse(AwakeEndReason.commandLineOff.isUserEnd)
    }

    func testBundleIDValidation() {
        for ok in ["com.apple.dt.Xcode", "a.b", "org.mozilla.firefox", "com.foo-bar.App_2"] {
            XCTAssertTrue(AwakeBundleID.isValid(ok), ok)
        }
        for bad in ["", "Xcode", ".a.b", "a..b", "a.b.", "com.apple.Xcode ", "com/apple", "com.äpple.x",
                    String(repeating: "a.", count: 128) + "b"] {
            XCTAssertFalse(AwakeBundleID.isValid(bad), bad)
        }
    }

    func testSaturatingAdd() {
        XCTAssertEqual(AwakeMath.adding(.max, 1), .max)
        XCTAssertEqual(AwakeMath.adding(.min, -1), .min)
        XCTAssertEqual(AwakeMath.adding(2, 3), 5)
        XCTAssertEqual(AwakeMath.clamp(.nan, 1, 2), 1)
    }
}
