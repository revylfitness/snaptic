import XCTest
@testable import SnapticKit

final class AwakeSnapshotTests: XCTestCase {
    private let boot = "BOOT-1"
    private func now(_ c: Double = 5_000, boot: String? = nil) -> ClockNow {
        ClockNow(wall: 1_700_000_000 + c, continuous: c, bootSession: boot ?? self.boot)
    }
    private func id(_ s: String) -> StableID { StableID.derived(namespace: "snap", name: s) }
    private func session(_ kind: AwakeSessionKind = .duration(seconds: 3_600), source: AwakeSessionSource = .menu,
                         display: AwakeDisplayPolicy = .keepOn) -> AwakeSession {
        AwakeClock.start(kind, options: AwakeSessionOptions(display: display), presetID: nil, source: source,
                         now: now(4_000), id: id("m"))
    }
    private func hold(_ n: String, pid: Int32 = 400, cap: Int = 3_600) -> AwakeHold {
        AwakeClock.hold(.process(pid: pid, startTime: 1), capSeconds: cap, now: now(4_000), id: id(n))
    }
    private func snapshot(manual: AwakeSession? = nil, holds: [AwakeHold] = [],
                          suppressions: [StableID: TriggerSuppression] = [:], paused: Double? = nil,
                          memory: GuardMemory = GuardMemory()) -> AwakeRuntimeSnapshot {
        var s = AwakeRuntimeSnapshot()
        s.bootSession = boot
        s.manual = manual
        s.holds = holds
        s.suppressions = LossyMap(suppressions)
        s.pausedUntil = paused
        s.guardMemory = memory
        return s
    }

    func testSameBootKeepsValidStateAndSource() {
        let m = session(source: .commandLine)
        let s = snapshot(manual: m, holds: [hold("a"), hold("b", pid: 401)]).sanitized(now: now())
        XCTAssertEqual(s.manual, m)
        XCTAssertEqual(s.manual?.source, .commandLine, "security L1: a restored CLI session stays CLI")
        XCTAssertEqual(s.holds.count, 2)
        XCTAssertEqual(s.bootSession, boot)
    }

    func testOtherBootDropsSessionHoldsAndTimedSuppressions() {
        var memory = GuardMemory()
        memory.holding = .batteryLow
        memory.heldSince = 100
        memory.warnedSerious = true
        memory.assertionHoldUntil = 900
        let raw = snapshot(manual: session(), holds: [hold("a")],
                           suppressions: [id("t1"): TriggerSuppression(until: 6_000, untilFalse: false),
                                          id("t2"): TriggerSuppression(until: 6_000, untilFalse: true),
                                          id("t3"): TriggerSuppression(until: nil, untilFalse: true)],
                           memory: memory)
        let s = raw.sanitized(now: now(10, boot: "BOOT-2"))
        XCTAssertNil(s.manual)
        XCTAssertEqual(s.holds, [])
        XCTAssertEqual(s.suppressions.values, [id("t2"): TriggerSuppression(until: nil, untilFalse: true),
                                               id("t3"): TriggerSuppression(until: nil, untilFalse: true)])
        var expected = GuardMemory()
        expected.warnedSerious = true
        XCTAssertEqual(s.guardMemory, expected)
        XCTAssertEqual(s.bootSession, "BOOT-2")
    }

    func testOutOfRangeAndForgedStateIsDropped() {
        // A session that started "after now", a rule session, a connection hold, an expired hold, a long hold.
        var future = session()
        future.startedContinuous = 9_999
        future.deadline = 9_999 + 3_600
        XCTAssertNil(snapshot(manual: future).sanitized(now: now()).manual)
        XCTAssertNil(snapshot(manual: session(source: .rule)).sanitized(now: now()).manual)
        var connection = hold("c")
        connection.binding = .connection(pid: 9, startTime: 1)
        var expired = hold("e")
        expired.deadline = 4_500
        var long = hold("l")
        long.deadline = long.startedContinuous + 200_000
        let s = snapshot(holds: [connection, expired, long, hold("ok")]).sanitized(now: now())
        XCTAssertEqual(s.holds.map(\.id), [id("ok")])
        // Out-of-range kind.
        var tiny = session()
        tiny.kind = .duration(seconds: 1)
        tiny.deadline = tiny.startedContinuous + 1
        XCTAssertNil(snapshot(manual: tiny).sanitized(now: now(4_000.5)).manual)
    }

    func testPauseAndSuppressionBounds() {
        let s = snapshot(suppressions: [id("past"): TriggerSuppression(until: 4_000, untilFalse: false),
                                        id("far"): TriggerSuppression(until: 5_000 + 10 * 86_400, untilFalse: false),
                                        id("ok"): TriggerSuppression(until: 5_600, untilFalse: false),
                                        id("both"): TriggerSuppression(until: 4_000, untilFalse: true)],
                         paused: 1_700_000_000 + 5_000 + 3_600).sanitized(now: now())
        XCTAssertEqual(s.suppressions.values, [id("ok"): TriggerSuppression(until: 5_600, untilFalse: false),
                                               id("both"): TriggerSuppression(until: nil, untilFalse: true)])
        XCTAssertEqual(s.pausedUntil, 1_700_000_000 + 8_600)
        XCTAssertNil(snapshot(paused: 1_700_000_000 + 4_000).sanitized(now: now()).pausedUntil, "already over")
        XCTAssertNil(snapshot(paused: 1_700_000_000 + 5_000 + 30 * 86_400).sanitized(now: now()).pausedUntil, "too far")
    }

    func testABadHoldKeepsTheManualSessionAndTheOtherHolds() throws {
        let good = snapshot(manual: session(), holds: [hold("a"), hold("b", pid: 401)])
        var json = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        // Corrupt the first hold's binding only.
        json = json.replacingOccurrences(of: #""type":"process""#, with: #""type":"teleport""#, options: [],
                                         range: json.range(of: #""type":"process""#))
        let decoded = try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: Data(json.utf8))
        XCTAssertNotNil(decoded.manual)
        XCTAssertEqual(decoded.holds.count, 1)
    }

    func testDuplicateHoldIDsKeepTheFirst() throws {
        let a = hold("a", pid: 500), dup = hold("a", pid: 501)
        let decoded = try JSONDecoder().decode(AwakeRuntimeSnapshot.self,
                                               from: JSONEncoder().encode(snapshot(holds: [a, dup, hold("b")])))
        XCTAssertEqual(decoded.holds.map(\.binding.pid), [500, 400])
        // A programmatic writer too.
        XCTAssertEqual(snapshot(holds: [a, dup]).sanitized().holds.map(\.binding.pid), [500])
        XCTAssertEqual(snapshot(holds: (0..<12).map { hold("h\($0)", pid: Int32(600 + $0)) }).sanitized().holds.count, 8)
    }

    func testRuntimeInitBuildsAWholeCleanSnapshot() {
        var m = session()
        m.overrideGuards = true
        var connection = hold("c")
        connection.binding = .connection(pid: 77, startTime: 2)
        let s = AwakeRuntimeSnapshot(bootSession: boot, manual: m, holds: [connection, hold("p")],
                                     suppressions: [id("t"): TriggerSuppression(until: nil, untilFalse: true)],
                                     pausedUntil: .nan, guardMemory: GuardMemory())
        XCTAssertEqual(s.manual?.overrideGuards, false)
        XCTAssertEqual(s.holds.map(\.id), [id("p")], "connection holds never persist")
        XCTAssertNil(s.pausedUntil)
        XCTAssertEqual(s.suppressions[id("t")], TriggerSuppression(until: nil, untilFalse: true))
    }

    func testDynamicNeeds() {
        XCTAssertEqual(snapshot().dynamicNeeds, [])
        XCTAssertEqual(snapshot(manual: session(.untilIdle(UntilIdleSpec(), maxSeconds: nil))).dynamicNeeds, [.taskQuiet])
        XCTAssertEqual(snapshot(manual: session(.whileApp(bundleID: "a.b", maxSeconds: nil))).dynamicNeeds, [.apps])
        XCTAssertEqual(snapshot(manual: session(display: .keepOnWhileActive)).dynamicNeeds, [.idle])
        XCTAssertEqual(snapshot(manual: session(.whileApp(bundleID: "a.b", maxSeconds: nil), display: .keepOnWhileActive),
                                holds: [hold("h")]).dynamicNeeds, [.apps, .idle, .process])
        XCTAssertEqual(snapshot(holds: [hold("h")]).dynamicNeeds, [.process])
    }

    func testSanitizedIsIdempotentAndRoundTrips() throws {
        let s = snapshot(manual: session(), holds: [hold("a")],
                         suppressions: [id("t"): TriggerSuppression(until: 5_500, untilFalse: false)],
                         paused: 1_700_000_000 + 6_000).sanitized(now: now())
        XCTAssertEqual(s.sanitized(now: now()), s)
        XCTAssertEqual(try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(AwakeRuntimeSnapshot().sanitized(now: now()).bootSession, boot)
    }

    func testOutsideWritesAreReadOnlyThroughSanitize() throws {
        // A forged snapshot claiming a menu start can't carry any activity gate state: the gate isn't in it at all.
        let forged = #"{"bootSession":"BOOT-1","manual":{"id":"\#(id("m").rawValue)","kind":{"type":"indefinite"},"source":"menu","startedAt":1700004000,"startedContinuous":4000,"bootSession":"BOOT-1","uiStartedInProcess":true,"pointer":"allowed","overrideGuards":true}}"#
        let s = try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: Data(forged.utf8)).sanitized(now: now())
        XCTAssertEqual(s.manual?.overrideGuards, false)
        let out = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertFalse(out.contains("uiStartedInProcess"))
        XCTAssertFalse(out.contains("pointer"))
    }

    // MARK: Ended while Snaptic wasn't running (awake-correctness F5b, round-2 F1)

    private let t0 = 1_700_000_000.0
    private func stamp(_ c: Double, clean: Bool = true) -> AwakeStopStamp {
        AwakeStopStamp(wall: t0 + c, continuous: c, clean: clean)
    }

    func testExpiredWhileAwayReportsEndsAtTheirInstant() {
        let raw = snapshot(manual: session(), holds: [hold("a", cap: 600), hold("b", pid: 401, cap: 7_200)])
        // Everything still running at 4 500: nothing to report.
        XCTAssertTrue(raw.awayEnds(now: now(4_500)).isEmpty)
        // At 10 000 the 1-hour session (ended 7 600) and the 10-minute hold (ended 4 600) ran out.
        let late = raw.awayEnds(now: now(10_000))
        XCTAssertEqual(late.map(\.item.id), [id("m"), id("a")])
        XCTAssertEqual(late.map(\.endWall), [t0 + 7_600, t0 + 4_600])
        XCTAssertEqual(late.map(\.reason), [.timeUp, .timeUp])
        XCTAssertEqual(late.first?.startWall, t0 + 4_000)
        XCTAssertNil(raw.sanitized(now: now(10_000)).manual, "the sanitizer still drops it")
    }

    func testExpiredWhileAwayEndsWhenSnapticStopped() {
        // 2 h session started at 4 000, quit 30 min in, relaunched 3 h later: 30 min, not 2 h.
        var raw = snapshot(manual: session(.duration(seconds: 7_200)))
        raw.stop = stamp(5_800)
        let ends = raw.awayEnds(now: now(16_600))
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends.first?.startWall, t0 + 4_000)
        XCTAssertEqual(ends.first?.endWall, t0 + 5_800)
    }

    func testOtherBootEndsReboot() {
        // Until Turned Off started at 4 000, Mac shut down at 36 400 (quit stamp): one `.reboot` entry.
        var raw = snapshot(manual: session(.indefinite), holds: [hold("a", cap: 86_400)])
        raw.stop = stamp(36_400)
        let ends = raw.awayEnds(now: now(50, boot: "BOOT-2"))
        XCTAssertEqual(ends.map(\.item.id), [id("m"), id("a")])
        XCTAssertEqual(ends.map(\.reason), [.reboot, .reboot])
        XCTAssertEqual(ends.map(\.endWall), [t0 + 36_400, t0 + 36_400])
        XCTAssertEqual(ends.first?.startWall, t0 + 4_000)
        // A crash before the reboot: the last heartbeat bounds it the same way.
        raw.stop = stamp(30_000, clean: false)
        XCTAssertEqual(raw.awayEnds(now: now(50, boot: "BOOT-2")).first?.endWall, t0 + 30_000)
        // A timed session that ran out before Snaptic stopped ends `.timeUp` at its own end.
        var timed = snapshot(manual: session(.duration(seconds: 600)))
        timed.stop = stamp(4_550)
        timed.manual = session(.duration(seconds: 600))
        let t = timed.awayEnds(now: now(50, boot: "BOOT-2"))
        XCTAssertEqual(t.first?.reason, .reboot, "still running at the stop stamp")
        XCTAssertEqual(t.first?.endWall, t0 + 4_550)
        timed.stop = stamp(4_700)
        XCTAssertEqual(timed.awayEnds(now: now(50, boot: "BOOT-2")).first?.reason, .timeUp)
        XCTAssertEqual(timed.awayEnds(now: now(50, boot: "BOOT-2")).first?.endWall, t0 + 4_600)
        // Without a stamp (a snapshot from before stamps) another boot's end is unknown: nothing is reported.
        XCTAssertTrue(snapshot(manual: session(.indefinite)).awayEnds(now: now(50, boot: "BOOT-2")).isEmpty)
    }

    func testAwayEndsIgnoreEndlessAndForgedItems() {
        XCTAssertTrue(snapshot(manual: session(.indefinite)).awayEnds(now: now(99_000)).isEmpty, "still running")
        var forged = session()
        forged.deadline = 4_000 + 99_999   // deadline doesn't match the duration
        XCTAssertTrue(snapshot(manual: forged).awayEnds(now: now(200_000)).isEmpty)
        var rule = session()
        rule.source = .rule
        XCTAssertTrue(snapshot(manual: rule).awayEnds(now: now(10_000)).isEmpty)
        let until = session(.until(unixTime: t0 + 4_000 + 1_800))
        XCTAssertEqual(snapshot(manual: until).awayEnds(now: now(9_000)).first?.endWall, t0 + 5_800)
    }

    func testRestoreEndAndResumedSegment() {
        let m = session(.indefinite)
        var raw = snapshot(manual: m)
        // Crash with resume off: the session ends at the last heartbeat, not at the relaunch.
        raw.stop = stamp(9_000, clean: false)
        let end = raw.restoreEnd(.session(m), reason: .moduleStopped, now: now(20_000))
        XCTAssertEqual(end.startWall, t0 + 4_000)
        XCTAssertEqual(end.endWall, t0 + 9_000)
        // Without a stamp: now.
        XCTAssertEqual(snapshot(manual: m).restoreEnd(.session(m), reason: .appQuit, now: now(20_000)).endWall, t0 + 20_000)
        // A resume after a gap: the part before it is one entry; a short gap (update relaunch) keeps one segment.
        let before = raw.resumedSegment(.session(m), now: now(20_000))
        XCTAssertEqual(before, AwakeAwayEnd(item: .session(m), startWall: t0 + 4_000, endWall: t0 + 9_000, reason: .moduleStopped))
        XCTAssertNil(raw.resumedSegment(.session(m), now: now(9_030)))
        XCTAssertNil(snapshot(manual: m).resumedSegment(.session(m), now: now(20_000)), "no stamp: no split")
        // The next segment starts where the resume began, and survives the next relaunch.
        raw.segmentStarts = LossyMap([m.id: t0 + 20_000])
        raw.stop = stamp(30_000)
        XCTAssertEqual(raw.segmentStart(m.id, startedAt: m.startedAt), t0 + 20_000)
        XCTAssertEqual(raw.resumedSegment(.session(m), now: now(40_000))?.startWall, t0 + 20_000)
        XCTAssertEqual(raw.sanitized(now: now(40_000)).segmentStarts.values, [m.id: t0 + 20_000])
        XCTAssertNil(raw.sanitized(now: now(40_000)).stop, "the stamp is read once, from the store")
        // A forged segment start before the start is ignored.
        raw.segmentStarts = LossyMap([m.id: 10])
        XCTAssertEqual(raw.segmentStart(m.id, startedAt: m.startedAt), m.startedAt)
    }

    func testRemindersSurviveSameBootOnlyForTheirSession() throws {
        let m = session(.indefinite)
        var r = AwakeReminders()
        XCTAssertEqual(r.due(m, now: now(4_000 + 8 * 3_600)), .eightHours)
        var raw = snapshot(manual: m)
        raw.reminders = r
        let decoded = try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: JSONEncoder().encode(raw))
        var restored = decoded.sanitized(now: now(4_000 + 10 * 3_600)).reminders
        XCTAssertNil(restored.due(m, now: now(4_000 + 10 * 3_600)), "N1: once per session across relaunches")
        XCTAssertEqual(decoded.sanitized(now: now(10, boot: "BOOT-2")).reminders, AwakeReminders())
        raw.manual = session(.duration(seconds: 7_200))
        raw.manual?.id = id("other")
        XCTAssertEqual(raw.sanitized().reminders, AwakeReminders(), "another session's marks are dropped")
        r = AwakeReminders()
        XCTAssertEqual(r.keeping(session: nil), AwakeReminders())
    }

    func testContentIgnoresTheStamp() {
        var a = snapshot(manual: session())
        var b = a
        a.stop = stamp(5_000)
        b.stop = stamp(6_000, clean: false)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.content, b.content)
    }

    // MARK: Seeded fuzz of the outside-writable snapshot (code F5)

    func testSeededFuzzNeverTrapsAndSanitizedIsStable() throws {
        var rng = SeededGenerator(seed: 0xA3A4E)
        let valid = snapshot(manual: session(.untilIdle(UntilIdleSpec(), maxSeconds: 7_200)), holds: [hold("a"), hold("b", pid: 401)],
                             suppressions: [id("t"): TriggerSuppression(until: 5_500, untilFalse: true)],
                             paused: 1_700_000_000 + 6_000)
        var stamped = valid
        stamped.stop = AwakeStopStamp(wall: 1_700_000_000 + 5_200, continuous: 5_200, clean: true)
        stamped.reminders = AwakeReminders()
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stamped))
        for round in 0..<600 {
            let mutated = mutate(base, &rng, depth: 0)
            guard JSONSerialization.isValidJSONObject(mutated),
                  let data = try? JSONSerialization.data(withJSONObject: mutated),
                  let decoded = try? JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: data) else { continue }
            let clock = now(Double(rng.next() % 20_000), boot: rng.next() % 4 == 0 ? "BOOT-2" : nil)
            let s = decoded.sanitized(now: clock)
            XCTAssertEqual(s.sanitized(now: clock), s, "round \(round)")
            XCTAssertLessThanOrEqual(s.holds.count, AwakeHold.maxHolds)
            XCTAssertTrue(s.holds.allSatisfy { $0.binding.isProcess && $0.deadline > clock.continuous })
            XCTAssertNotEqual(s.manual?.source, .rule)
            XCTAssertNotEqual(s.manual?.overrideGuards, true)
            if let p = s.pausedUntil { XCTAssertLessThanOrEqual(p - clock.wall, AwakeRuntimeSnapshot.maxPauseSeconds) }
            XCTAssertLessThanOrEqual(s.suppressions.values.count, AwakeRuntimeSnapshot.maxSuppressions)
            XCTAssertEqual(try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: JSONEncoder().encode(s)), s)
            let away = decoded.awayEnds(now: clock)
            XCTAssertTrue(away.allSatisfy { $0.startWall <= $0.endWall && $0.endWall.isFinite })
            if clock.bootSession == boot { XCTAssertTrue(away.allSatisfy { $0.endWall <= clock.wall }) }
            if let st = decoded.sanitized().stop, decoded.bootSession == boot {
                XCTAssertTrue(away.allSatisfy { $0.endWall <= max(st.wall, $0.startWall) }, "never after Snaptic stopped")
            }
            XCTAssertLessThanOrEqual(away.count, AwakeHold.maxHolds + 1)
            XCTAssertEqual(Set(away.map(\.item.id)).count, away.count)
        }
    }

    private func mutate(_ value: Any, _ rng: inout SeededGenerator, depth: Int) -> Any {
        if var d = value as? [String: Any] {
            for key in d.keys.sorted() {
                switch rng.next() % 6 {
                case 0: d[key] = nil
                case 1: d[key] = junk(&rng, depth: depth)
                default: if let v = d[key] { d[key] = mutate(v, &rng, depth: depth + 1) }
                }
            }
            if rng.next() % 5 == 0 { d["extra\(rng.next() % 3)"] = junk(&rng, depth: depth) }
            return d
        }
        if var a = value as? [Any] {
            a = a.map { mutate($0, &rng, depth: depth + 1) }
            if let first = a.first, rng.next() % 3 == 0 {
                a += Array(repeating: first, count: Int(rng.next() % 12))
            }
            if rng.next() % 4 == 0 { a.append(junk(&rng, depth: depth)) }
            return a
        }
        return rng.next() % 4 == 0 ? junk(&rng, depth: depth) : value
    }

    private func junk(_ rng: inout SeededGenerator, depth: Int) -> Any {
        switch rng.next() % (depth > 3 ? 7 : 9) {
        case 0: return NSNull()
        case 1: return Int.max
        case 2: return -Int(rng.next() % 10_000)
        case 3: return 1e300
        case 4: return ["", "BOOT-1", "rule", "commandLine", "duration", "process"][Int(rng.next() % 6)]
        case 5: return rng.next() % 2 == 0
        case 6: return Double(rng.next() % 20_000) + 0.5
        case 7: return [junk(&rng, depth: depth + 1), junk(&rng, depth: depth + 1)]
        default: return ["type": "duration", "seconds": Int(rng.next() % 100_000), "x": junk(&rng, depth: depth + 1)]
        }
    }
}
