import XCTest
@testable import SnapticKit

final class AwakeClockTests: XCTestCase {
    private let boot = "BOOT-A"
    private let wall0: Double = 1_760_000_000
    private func now(_ continuous: Double, wall: Double? = nil, boot: String? = nil) -> ClockNow {
        ClockNow(wall: wall ?? wall0 + (continuous - 1_000), continuous: continuous, bootSession: boot ?? self.boot)
    }
    private let sid = StableID.derived(namespace: "test", name: "s")
    private func start(_ kind: AwakeSessionKind, at: Double = 1_000) -> AwakeSession {
        AwakeClock.start(kind, options: AwakeSessionOptions(), presetID: nil, source: .menu, now: now(at), id: sid)
    }

    // MARK: start / hold

    func testStartSetsDeadlinesPerKind() {
        XCTAssertNil(start(.indefinite).deadline)
        XCTAssertEqual(start(.duration(seconds: 3_600)).deadline, 4_600)
        XCTAssertNil(start(.until(unixTime: wall0 + 600)).deadline)
        XCTAssertNil(start(.whileApp(bundleID: "a.b", maxSeconds: nil)).deadline)
        XCTAssertEqual(start(.whileApp(bundleID: "a.b", maxSeconds: 7_200)).deadline, 8_200)
        XCTAssertEqual(start(.untilIdle(UntilIdleSpec(), maxSeconds: 600)).deadline, 1_600)
        let s = start(.duration(seconds: 3_600))
        XCTAssertEqual(s.startedAt, wall0)
        XCTAssertEqual(s.startedContinuous, 1_000)
        XCTAssertEqual(s.bootSession, boot)
        XCTAssertEqual(s.id, sid)
        XCTAssertFalse(s.overrideGuards)
    }

    func testStartClampsDurationsAndCaps() {
        XCTAssertEqual(start(.duration(seconds: 5)).kind, .duration(seconds: 60))
        XCTAssertEqual(start(.duration(seconds: .max)).kind, .duration(seconds: AwakeClock.maxSessionSeconds))
        XCTAssertEqual(start(.duration(seconds: .max)).deadline, 1_000 + Double(AwakeClock.maxSessionSeconds))
        XCTAssertEqual(start(.whileApp(bundleID: "a.b", maxSeconds: -1)).kind, .whileApp(bundleID: "a.b", maxSeconds: 60))
        XCTAssertEqual(start(.untilIdle(UntilIdleSpec(quietSeconds: 1), maxSeconds: nil)).kind,
                       .untilIdle(UntilIdleSpec(quietSeconds: 60), maxSeconds: nil))
    }

    func testHoldCapsAreClamped() {
        let b = HoldBinding.process(pid: 99, startTime: 1)
        XCTAssertEqual(AwakeClock.hold(b, capSeconds: AwakeClock.holdDefaultCapSeconds, now: now(1_000), id: sid).deadline,
                       1_000 + 43_200)
        XCTAssertEqual(AwakeClock.hold(b, capSeconds: .max, now: now(1_000), id: sid).deadline, 1_000 + 86_400)
        XCTAssertEqual(AwakeClock.hold(b, capSeconds: 0, now: now(1_000), id: sid).deadline, 1_060)
    }

    // MARK: remaining / expiry / end

    func testRemainingUsesContinuousForDurationAndWallForUntil() {
        let d = start(.duration(seconds: 3_600))
        XCTAssertEqual(AwakeClock.remaining(d, now: now(1_600)), 3_000)
        // A wall-clock jump of a day either way doesn't move a duration session.
        XCTAssertEqual(AwakeClock.remaining(d, now: now(1_600, wall: wall0 + 600 + 86_400)), 3_000)
        XCTAssertEqual(AwakeClock.remaining(d, now: now(1_600, wall: wall0 + 600 - 86_400)), 3_000)
        // Time asleep counts (continuous includes sleep).
        XCTAssertEqual(AwakeClock.remaining(d, now: now(4_000)), 600)
        let u = start(.until(unixTime: wall0 + 7_200))
        XCTAssertEqual(AwakeClock.remaining(u, now: now(1_600)), 6_600)
        // A wall-clock jump forward an hour brings an until session's end an hour closer.
        XCTAssertEqual(AwakeClock.remaining(u, now: now(1_600, wall: wall0 + 600 + 3_600)), 3_000)
        XCTAssertNil(AwakeClock.remaining(start(.indefinite), now: now(9_999)))
        XCTAssertNil(AwakeClock.remaining(start(.whileApp(bundleID: "a.b", maxSeconds: nil)), now: now(9_999)))
        XCTAssertEqual(AwakeClock.remaining(start(.untilIdle(UntilIdleSpec(), maxSeconds: 600)), now: now(1_100)), 500)
    }

    func testEndWallFollowsAClockChange() {
        let d = start(.duration(seconds: 3_600))
        XCTAssertEqual(AwakeClock.endWall(d, now: now(1_600)), wall0 + 3_600)
        // The wall clock moved back 10 minutes: the shown end moves with it, the deadline doesn't.
        XCTAssertEqual(AwakeClock.endWall(d, now: now(1_600, wall: wall0)), wall0 + 3_000)
        XCTAssertEqual(AwakeClock.endWall(start(.until(unixTime: wall0 + 50)), now: now(1_600)), wall0 + 600,
                       "an expired session shows now")
        XCTAssertNil(AwakeClock.endWall(start(.indefinite), now: now(1_600)))
    }

    func testContinuousEndForUntilKinds() {
        let u = start(.until(unixTime: wall0 + 7_200))
        XCTAssertEqual(AwakeClock.continuousEnd(u, now: now(1_600)), 8_200)
        // After a +1 h clock change the continuous end comes an hour earlier.
        XCTAssertEqual(AwakeClock.continuousEnd(u, now: now(1_600, wall: wall0 + 600 + 3_600)), 4_600)
        XCTAssertEqual(AwakeClock.continuousEnd(start(.duration(seconds: 60)), now: now(1_010)), 1_060)
        XCTAssertNil(AwakeClock.continuousEnd(start(.indefinite), now: now(1_010)))
        XCTAssertNil(AwakeClock.continuousEnd(start(.whileApp(bundleID: "a.b", maxSeconds: nil)), now: now(1_010)))
    }

    func testExpiryIncludingReboot() {
        let d = start(.duration(seconds: 60))
        XCTAssertFalse(AwakeClock.isExpired(d, now: now(1_059)))
        XCTAssertTrue(AwakeClock.isExpired(d, now: now(1_060)))
        XCTAssertTrue(AwakeClock.isExpired(start(.indefinite), now: now(1_001, boot: "BOOT-B")), "reboot ends everything")
        XCTAssertEqual(AwakeClock.remaining(d, now: now(1_001, boot: "BOOT-B")), 0)
        XCTAssertFalse(AwakeClock.isExpired(start(.indefinite), now: now(9e9)))
        XCTAssertTrue(AwakeClock.isExpired(start(.until(unixTime: wall0 + 10)), now: now(1_010)))
        var broken = d
        broken.deadline = nil
        XCTAssertTrue(AwakeClock.isExpired(broken, now: now(1_001)), "a duration without a deadline counts as over")
    }

    // MARK: extend

    func testCanExtendPerKind() {
        XCTAssertTrue(AwakeClock.canExtend(start(.duration(seconds: 60))))
        XCTAssertTrue(AwakeClock.canExtend(start(.until(unixTime: wall0 + 600))))
        XCTAssertTrue(AwakeClock.canExtend(start(.whileApp(bundleID: "a.b", maxSeconds: 600))))
        XCTAssertTrue(AwakeClock.canExtend(start(.untilIdle(UntilIdleSpec(), maxSeconds: 600))))
        XCTAssertFalse(AwakeClock.canExtend(start(.indefinite)))
        XCTAssertFalse(AwakeClock.canExtend(start(.whileApp(bundleID: "a.b", maxSeconds: nil))))
        XCTAssertFalse(AwakeClock.canExtend(start(.untilIdle(UntilIdleSpec(), maxSeconds: nil))))
        XCTAssertNil(AwakeClock.extended(start(.indefinite), by: 3_600, now: now(1_100)))
    }

    func testExtendAddsTimePerKind() throws {
        let d = try XCTUnwrap(AwakeClock.extended(start(.duration(seconds: 3_600)), by: 3_600, now: now(1_100)))
        XCTAssertEqual(d.kind, .duration(seconds: 7_200))
        XCTAssertEqual(d.deadline, 8_200)
        let u = try XCTUnwrap(AwakeClock.extended(start(.until(unixTime: wall0 + 600)), by: 900, now: now(1_100)))
        XCTAssertEqual(u.kind, .until(unixTime: wall0 + 1_500))
        let a = try XCTUnwrap(AwakeClock.extended(start(.whileApp(bundleID: "a.b", maxSeconds: 600)), by: 3_600,
                                                  now: now(1_100)))
        XCTAssertEqual(a.kind, .whileApp(bundleID: "a.b", maxSeconds: 4_200))
        XCTAssertEqual(a.deadline, 5_200)
        let i = try XCTUnwrap(AwakeClock.extended(start(.untilIdle(UntilIdleSpec(), maxSeconds: 600)), by: 60, now: now(1_100)))
        XCTAssertEqual(i.kind.cap, 660)
        XCTAssertEqual(i.deadline, 1_660)
        // The extended session still passes the load-time bounds.
        XCTAssertNotNil(d.sanitized(now: now(1_200)))
        XCTAssertNotNil(a.sanitized(now: now(1_200)))
        XCTAssertNotNil(i.sanitized(now: now(1_200)))
    }

    func testExtendCapsAtThirtyDaysAndRefusesBadInput() throws {
        let max = AwakeClock.maxSessionSeconds
        let d = try XCTUnwrap(AwakeClock.extended(start(.duration(seconds: max - 60)), by: .max, now: now(1_100)))
        XCTAssertEqual(d.kind, .duration(seconds: max))
        let again = try XCTUnwrap(AwakeClock.extended(d, by: 3_600, now: now(1_100)))
        XCTAssertEqual(again, d, "a session at the limit comes back unchanged")
        let u = try XCTUnwrap(AwakeClock.extended(start(.until(unixTime: wall0 + 600)), by: .max, now: now(1_100)))
        guard case .until(let t) = u.kind else { return XCTFail() }
        XCTAssertEqual(t, wall0 + Double(max), accuracy: 0.001)
        XCTAssertNotNil(u.sanitized(now: now(1_200)))
        XCTAssertNil(AwakeClock.extended(start(.duration(seconds: 60)), by: 0, now: now(1_001)))
        XCTAssertNil(AwakeClock.extended(start(.duration(seconds: 60)), by: -60, now: now(1_001)))
        XCTAssertNil(AwakeClock.extended(start(.duration(seconds: 60)), by: 60, now: now(1_061)), "already over")
    }

    func testClockJumpsNeverMoveDurationSessionsFuzz() {
        var rng = SeededGenerator(seed: 0xC10C)
        for _ in 0..<2_000 {
            let seconds = 60 + Int(rng.next() % UInt64(AwakeClock.maxSessionSeconds - 60))
            let s = start(.duration(seconds: seconds))
            let elapsed = Double(rng.next() % UInt64(seconds))
            let jump = (Double(rng.next() % 172_800) - 86_400)
            let base = AwakeClock.remaining(s, now: now(1_000 + elapsed))
            let jumped = AwakeClock.remaining(s, now: now(1_000 + elapsed, wall: wall0 + elapsed + jump))
            XCTAssertEqual(base, jumped)
            XCTAssertEqual(base ?? -1, Double(seconds) - elapsed, accuracy: 0.0001)
        }
    }

    // MARK: Countdown

    func testShortBoundaries() {
        XCTAssertEqual(AwakeCountdown.short(3_600), "1h")
        XCTAssertEqual(AwakeCountdown.short(7_200), "2h")
        XCTAssertEqual(AwakeCountdown.short(3_599), "1h", "rounded up to 60 minutes")
        XCTAssertEqual(AwakeCountdown.short(3_601), "1h 1m")
        XCTAssertEqual(AwakeCountdown.short(6_120), "1h 42m")
        XCTAssertEqual(AwakeCountdown.short(61), "2m")
        XCTAssertEqual(AwakeCountdown.short(60), "1m")
        XCTAssertEqual(AwakeCountdown.short(59.5), "1m")
        XCTAssertEqual(AwakeCountdown.short(59), "59s")
        XCTAssertEqual(AwakeCountdown.short(42.3), "43s")
        XCTAssertEqual(AwakeCountdown.short(1), "1s")
        XCTAssertEqual(AwakeCountdown.short(0), "0s")
        XCTAssertEqual(AwakeCountdown.short(-5), "0s")
        XCTAssertEqual(AwakeCountdown.short(.nan), "0s")
        XCTAssertEqual(AwakeCountdown.short(.infinity), "0s")
        XCTAssertEqual(AwakeCountdown.short(Double(AwakeClock.maxSessionSeconds)), "720h")
    }

    func testSpoken() {
        XCTAssertEqual(AwakeCountdown.spoken(6_120), "1 hour 42 minutes remaining")
        XCTAssertEqual(AwakeCountdown.spoken(7_200), "2 hours remaining")
        XCTAssertEqual(AwakeCountdown.spoken(3_660), "1 hour 1 minute remaining")
        XCTAssertEqual(AwakeCountdown.spoken(42 * 60), "42 minutes remaining")
        XCTAssertEqual(AwakeCountdown.spoken(60), "1 minute remaining")
        XCTAssertEqual(AwakeCountdown.spoken(42), "42 seconds remaining")
        XCTAssertEqual(AwakeCountdown.spoken(1), "1 second remaining")
    }

    func testClock12And24Hour() {
        XCTAssertEqual(AwakeCountdown.clock(hour: 17, minute: 0, uses24Hour: false), "5:00 PM")
        XCTAssertEqual(AwakeCountdown.clock(hour: 17, minute: 0, uses24Hour: true), "17:00")
        XCTAssertEqual(AwakeCountdown.clock(hour: 0, minute: 5, uses24Hour: false), "12:05 AM")
        XCTAssertEqual(AwakeCountdown.clock(hour: 0, minute: 5, uses24Hour: true), "00:05")
        XCTAssertEqual(AwakeCountdown.clock(hour: 12, minute: 30, uses24Hour: false), "12:30 PM")
        XCTAssertEqual(AwakeCountdown.clock(hour: 9, minute: 7, uses24Hour: true), "09:07")
        XCTAssertEqual(AwakeCountdown.clock(hour: 25, minute: 61, uses24Hour: true), "01:01", "wraps, never traps")
        XCTAssertEqual(AwakeCountdown.clock(hour: -1, minute: -1, uses24Hour: true), "23:59")
    }

    func testNextChangeNeverZeroAndLandsOnTheChange() {
        XCTAssertEqual(AwakeCountdown.nextChange(3_600), 60)
        XCTAssertEqual(AwakeCountdown.nextChange(3_601), 1)
        XCTAssertEqual(AwakeCountdown.nextChange(61), 1)
        XCTAssertEqual(AwakeCountdown.nextChange(60), 1)
        XCTAssertEqual(AwakeCountdown.nextChange(59), 1)
        XCTAssertEqual(AwakeCountdown.nextChange(42.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(AwakeCountdown.nextChange(0), 1)
        XCTAssertEqual(AwakeCountdown.nextChange(.nan), 60)
        var rng = SeededGenerator(seed: 0x71C)
        for _ in 0..<20_000 {
            let r = Double(rng.next() % 200_000) / 10
            let step = AwakeCountdown.nextChange(r)
            XCTAssertGreaterThan(step, 0)
            XCTAssertLessThanOrEqual(step, 60)
            if r > step {
                // Just before the change the text is unchanged; at the change it differs.
                XCTAssertEqual(AwakeCountdown.short(r - step + 1e-6), AwakeCountdown.short(r), "r=\(r)")
                XCTAssertNotEqual(AwakeCountdown.short(r - step - 1e-6), AwakeCountdown.short(r), "r=\(r)")
            }
        }
    }

    // MARK: Duration grammar

    func testDurationForms() {
        let p = AwakeDurationGrammar.parse
        XCTAssertEqual(p(["90"]), .duration(seconds: 5_400))
        XCTAssertEqual(p(["90m"]), .duration(seconds: 5_400))
        XCTAssertEqual(p(["1h30m"]), .duration(seconds: 5_400))
        XCTAssertEqual(p(["1h", "30m"]), .duration(seconds: 5_400))
        XCTAssertEqual(p(["2h"]), .duration(seconds: 7_200))
        XCTAssertEqual(p(["1.5h"]), .duration(seconds: 5_400))
        XCTAssertEqual(p(["1.25H"]), .duration(seconds: 4_500))
        XCTAssertEqual(p(["2", "hours"]), nil, "a unit must touch its number")
        XCTAssertEqual(p(["2hours"]), .duration(seconds: 7_200))
        XCTAssertEqual(p(["1d"]), .duration(seconds: 86_400))
        XCTAssertEqual(p(["30d"]), .duration(seconds: AwakeClock.maxSessionSeconds))
        XCTAssertEqual(p(["1.5m"]), .duration(seconds: 90))
        XCTAssertEqual(p(["indefinite"]), .indefinite)
        XCTAssertEqual(p(["Forever"]), .indefinite)
        XCTAssertEqual(p(["idle"]), .untilIdle)
    }

    func testClockForms() {
        let p = AwakeDurationGrammar.parse
        XCTAssertEqual(p(["until", "17:30"]), .untilClock(hour: 17, minute: 30))
        XCTAssertEqual(p(["until", "5:30pm"]), .untilClock(hour: 17, minute: 30))
        XCTAssertEqual(p(["until", "5:30", "PM"]), .untilClock(hour: 17, minute: 30))
        XCTAssertEqual(p(["until", "5pm"]), .untilClock(hour: 17, minute: 0))
        XCTAssertEqual(p(["until", "12am"]), .untilClock(hour: 0, minute: 0))
        XCTAssertEqual(p(["until", "12:15pm"]), .untilClock(hour: 12, minute: 15))
        XCTAssertEqual(p(["until", "0:00"]), .untilClock(hour: 0, minute: 0))
        for bad in [["until"], ["until", "17"], ["until", "24:00"], ["until", "13pm"], ["until", "0am"], ["until", "5:3"],
                    ["until", "5:60"], ["until", "5:30xm"], ["until", "-5:00"], ["until", "５:00"], ["until", "1", "2", "3"]] {
            XCTAssertNil(p(bad), "\(bad)")
        }
    }

    func testInvalidDurations() {
        let p = AwakeDurationGrammar.parse
        for bad: [String] in [[], [""], ["0"], ["59s"], ["0.5"], ["-5"], ["+5"], ["5e2"], ["1e300h"],
                              ["12345678"], ["1.234h"], ["1.h"], [".5h"], ["1..5h"], ["30m1h"], ["1h1h"], ["1h2"], ["h"],
                              ["99999999999999999999999h"], ["31d"], ["720h1m"], ["٣٠"], ["90 m"], ["1h", "x"],
                              ["indefinite", "now"], ["idle", "1h"]] {
            XCTAssertNil(p(bad), "\(bad)")
        }
        XCTAssertEqual(p(["1"]), .duration(seconds: 60), "a bare 1 is one minute, the minimum")
        XCTAssertEqual(p(["30"]), .duration(seconds: 1_800))
    }

    func testDigitAndDecimalLimits() {
        XCTAssertEqual(AwakeDurationGrammar.parse(["0000060m"]), .duration(seconds: 3_600), "7 digits allowed")
        XCTAssertNil(AwakeDurationGrammar.parse(["00000060m"]), "8 digits refused")
        XCTAssertEqual(AwakeDurationGrammar.parse(["1.01h"]), .duration(seconds: 3_636))
        XCTAssertNil(AwakeDurationGrammar.parse(["1.001h"]))
        XCTAssertEqual(AwakeDurationGrammar.durationSeconds(["2h"]), 7_200)
        XCTAssertNil(AwakeDurationGrammar.durationSeconds(["idle"]))
    }

    func testGrammarFuzzNeverTraps() {
        var rng = SeededGenerator(seed: 0xD0_0D)
        let alphabet = Array("0123456789.:hHmMdDsSuntilpaAPM -+e٣")
        let words = ["until", "idle", "forever", "indefinite", "1h", "30m", "pm", "17:30", "9999999", "1.25"]
        for _ in 0..<30_000 {
            var input: [String] = []
            for _ in 0..<Int(rng.next() % 4) {
                if rng.next() % 3 == 0 {
                    input.append(words[Int(rng.next() % UInt64(words.count))])
                } else {
                    let n = Int(rng.next() % 12)
                    input.append(String((0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }))
                }
            }
            if case .duration(let s)? = AwakeDurationGrammar.parse(input) {
                XCTAssertTrue(AwakeClock.durationRange.contains(s), "\(input)")
            }
            if case .untilClock(let h, let m)? = AwakeDurationGrammar.parse(input) {
                XCTAssertTrue((0...23).contains(h) && (0...59).contains(m), "\(input)")
            }
        }
    }

    func testTextContextStandard() {
        XCTAssertFalse(AwakeTextContext.standard.uses24Hour)
        XCTAssertEqual(AwakeTextContext.standard.decimalSeparator, ".")
    }
}
