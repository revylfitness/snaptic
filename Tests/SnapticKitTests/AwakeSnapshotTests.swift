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

    /// 0.3.1 B1, r1 A5: a session that had lid-closed mode keeps "Lid closed" in History across a quit or crash.
    func testLidSessionMarksHistoryAcrossARelaunch() throws {
        let m = session(.indefinite)
        var raw = snapshot(manual: m)
        raw.lidSession = m.id
        raw.stop = stamp(9_000, clean: false)
        let decoded = try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: JSONEncoder().encode(raw))
        XCTAssertEqual(decoded.lidSession, m.id, "persisted")
        XCTAssertEqual(decoded.sanitized(now: now(20_000)).lidSession, m.id, "carried with its session")
        // The part before a gap, a dropped session, another boot's: each entry says "Lid closed".
        let before = try XCTUnwrap(raw.resumedSegment(.session(m), now: now(20_000)))
        XCTAssertTrue(before.lidClosed)
        XCTAssertTrue(AwakeHistoryEntry(before).lidClosed)
        XCTAssertTrue(raw.restoreEnd(.session(m), reason: .moduleStopped, now: now(20_000)).lidClosed)
        let away = try XCTUnwrap(raw.awayEnds(now: now(50, boot: "BOOT-2")).first)
        XCTAssertEqual(away.reason, .reboot)
        XCTAssertTrue(AwakeHistoryEntry(away).lidClosed)
        // Without the marker, or for another session, nothing changes.
        raw.lidSession = nil
        XCTAssertFalse(AwakeHistoryEntry(try XCTUnwrap(raw.resumedSegment(.session(m), now: now(20_000)))).lidClosed)
        raw.lidSession = id("other")
        XCTAssertFalse(raw.restoreEnd(.session(m), reason: .moduleStopped, now: now(20_000)).lidClosed)
        XCTAssertNil(raw.sanitized().lidSession, "a marker for another session is dropped")
        XCTAssertNil(snapshot().sanitized(now: now(20_000)).lidSession)
        // An old snapshot (no key) decodes without it, and a snapshot without it encodes no key.
        let plain = String(decoding: try JSONEncoder().encode(snapshot(manual: m)), as: UTF8.self)
        XCTAssertFalse(plain.contains("lidSession"))
    }

    func testContentIgnoresTheStamp() {
        var a = snapshot(manual: session())
        var b = a
        a.stop = stamp(5_000)
        b.stop = stamp(6_000, clean: false)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.content, b.content)
    }

    // MARK: A rule session cut short by a crash (review6 N2)

    func testRuleEndOnlyAfterACrash() throws {
        let rule = AwakeRuleRecord(triggerID: id("desk"), startWall: t0 + 1_000)
        var raw = snapshot()
        raw.rule = rule
        raw.stop = stamp(9_000, clean: false)
        // Same boot: it ran until the last heartbeat.
        let same = try XCTUnwrap(raw.ruleEnd(now: now(20_000)))
        XCTAssertEqual(same, AwakeAwayEnd(item: .rule(rule), startWall: t0 + 1_000, endWall: t0 + 9_000, reason: .moduleStopped))
        let entry = AwakeHistoryEntry(same)
        XCTAssertEqual(entry.kind, .automatic)
        XCTAssertEqual(entry.source, .rule)
        XCTAssertEqual(entry.triggerID, id("desk"))
        XCTAssertEqual(entry.start, t0 + 1_000)
        XCTAssertEqual(entry.end, t0 + 9_000)
        XCTAssertEqual(entry.endReason, .moduleStopped)
        // The Mac restarted since: `.reboot`, still at the heartbeat.
        XCTAssertEqual(raw.ruleEnd(now: now(50, boot: "BOOT-2"))?.reason, .reboot)
        XCTAssertEqual(raw.ruleEnd(now: now(50, boot: "BOOT-2"))?.endWall, t0 + 9_000)
        // A clean quit recorded it already; no stamp, no bound: nothing is owed.
        raw.stop = stamp(9_000, clean: true)
        XCTAssertNil(raw.ruleEnd(now: now(20_000)))
        raw.stop = nil
        XCTAssertNil(raw.ruleEnd(now: now(20_000)))
        // Never after now, never before its start.
        raw.stop = stamp(9_000, clean: false)
        XCTAssertEqual(raw.ruleEnd(now: now(8_000))?.endWall, t0 + 8_000)
        raw.rule = AwakeRuleRecord(triggerID: id("desk"), startWall: t0 + 9_500)
        XCTAssertEqual(raw.ruleEnd(now: now(20_000))?.endWall, t0 + 9_500)
        // A forged start is dropped; the record survives encoding and is read once (not carried by `sanitized(now:)`).
        raw.rule = AwakeRuleRecord(triggerID: id("desk"), startWall: .nan)
        XCTAssertNil(raw.sanitized().rule)
        XCTAssertNil(raw.ruleEnd(now: now(20_000)))
        raw.rule = rule
        let decoded = try JSONDecoder().decode(AwakeRuntimeSnapshot.self, from: JSONEncoder().encode(raw))
        XCTAssertEqual(decoded.rule, rule)
        XCTAssertNil(decoded.sanitized(now: now(20_000)).rule)
        // The rule is snapshot content: a change of rule is written at once, not at the next heartbeat.
        var other = raw
        other.rule = AwakeRuleRecord(triggerID: id("other"), startWall: t0 + 1_000)
        XCTAssertNotEqual(raw.content, other.content)
    }

    // MARK: Discarded unread (a launch with Modules.disable.awake; review6 code N3)

    func testDiscardedEndsTable() {
        let running = session(.duration(seconds: 3_600))
        let expired = hold("short", cap: 600)                 // ran out at 4 600
        let resumable = hold("long", pid: 401, cap: 7_200)    // runs until 11 200
        var raw = snapshot(manual: running, holds: [expired, resumable])
        raw.stop = stamp(5_000)
        // Same boot, resume on, quit at 5 000, relaunched at 6 000 with the module off: the session and the long hold
        // end when Snaptic stopped; the short hold ran out on its own before that.
        let ends = raw.discardedEnds(now: now(6_000), resume: true)
        XCTAssertEqual(ends.map(\.item.id), [id("short"), id("m"), id("long")])
        XCTAssertEqual(ends.map(\.reason), [.timeUp, .moduleStopped, .moduleStopped])
        XCTAssertEqual(ends.map(\.endWall), [t0 + 4_600, t0 + 5_000, t0 + 5_000])
        XCTAssertEqual(ends.map(\.startWall), [t0 + 4_000, t0 + 4_000, t0 + 4_000])
        // Resume off: the quit recorded the session, but a stamp means it was left by a crash: still owed.
        XCTAssertEqual(raw.discardedEnds(now: now(6_000), resume: false).map(\.item.id), [id("short"), id("m"), id("long")])
        // Resume off without a stamp (a build before stamps): the quit recorded the session; `--pid` holds are owed.
        var unstamped = raw
        unstamped.stop = nil
        let old = unstamped.discardedEnds(now: now(6_000), resume: false)
        XCTAssertEqual(old.map(\.item.id), [id("short"), id("long")])
        XCTAssertEqual(old.last?.endWall, t0 + 6_000, "no stamp: until now")
        XCTAssertEqual(unstamped.discardedEnds(now: now(6_000), resume: true).map(\.item.id),
                       [id("short"), id("m"), id("long")])
        // Another boot: everything ended `.reboot` at the stamp (the short hold had already run out).
        let reboot = raw.discardedEnds(now: now(50, boot: "BOOT-2"), resume: true)
        XCTAssertEqual(reboot.map(\.item.id), [id("m"), id("short"), id("long")])
        XCTAssertEqual(reboot.map(\.reason), [.reboot, .timeUp, .reboot])
        // A crash during a rule session adds it once.
        raw.stop = stamp(5_000, clean: false)
        raw.rule = AwakeRuleRecord(triggerID: id("desk"), startWall: t0 + 3_000)
        let crashed = raw.discardedEnds(now: now(6_000), resume: true)
        XCTAssertEqual(crashed.map(\.item.id), [id("short"), id("m"), id("long"), id("desk")])
        XCTAssertEqual(crashed.last?.reason, .moduleStopped)
        XCTAssertEqual(Set(crashed.map(\.item.id)).count, crashed.count, "never twice")
        XCTAssertTrue(snapshot().discardedEnds(now: now(6_000), resume: true).isEmpty)
    }

    /// security S3-1 / review6 N3: the module-off launch records nothing when History isn't effective.
    func testDiscardedHistoryHonorsHistorySwitchAndKillSwitch() {
        var raw = snapshot(manual: session(.indefinite))
        raw.stop = stamp(5_000)
        var config = AwakeConfig()
        XCTAssertEqual(raw.discardedHistory(now: now(6_000), config: config, killSwitches: []).count, 1)
        XCTAssertEqual(raw.discardedHistory(now: now(6_000), config: config, killSwitches: []).first?.endReason,
                       .moduleStopped)
        XCTAssertTrue(raw.discardedHistory(now: now(6_000), config: config, killSwitches: [.history]).isEmpty,
                      "Awake.disable.history")
        XCTAssertEqual(raw.discardedHistory(now: now(6_000), config: config, killSwitches: [.triggers]).count, 1,
                       "another kill switch doesn't matter")
        config.features[.history] = false
        XCTAssertTrue(raw.discardedHistory(now: now(6_000), config: config, killSwitches: []).isEmpty, "History off")
    }

    func testSegmentStartStatic() {
        XCTAssertEqual(AwakeRuntimeSnapshot.segmentStart(stored: nil, startedAt: 10), 10)
        XCTAssertEqual(AwakeRuntimeSnapshot.segmentStart(stored: 20, startedAt: 10), 20)
        XCTAssertEqual(AwakeRuntimeSnapshot.segmentStart(stored: 5, startedAt: 10), 10, "never before the start")
        XCTAssertEqual(AwakeRuntimeSnapshot.segmentStart(stored: .infinity, startedAt: 10), 10)
    }

    // MARK: Seeded fuzz of the outside-writable snapshot (code F5)

    func testSeededFuzzNeverTrapsAndSanitizedIsStable() throws {
        var rng = SeededGenerator(seed: 0xA3A4E)
        let valid = snapshot(manual: session(.untilIdle(UntilIdleSpec(), maxSeconds: 7_200)), holds: [hold("a"), hold("b", pid: 401)],
                             suppressions: [id("t"): TriggerSuppression(until: 5_500, untilFalse: true)],
                             paused: 1_700_000_000 + 6_000)
        var stamped = valid
        stamped.stop = AwakeStopStamp(wall: 1_700_000_000 + 5_200, continuous: 5_200, clean: false)
        stamped.rule = AwakeRuleRecord(triggerID: id("r"), startWall: 1_700_000_000 + 3_000)
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
            // Discarded unread (code N3): each item at most once, start ≤ end, never after Snaptic stopped or now.
            let discarded = decoded.discardedEnds(now: clock, resume: rng.next() % 2 == 0)
            XCTAssertEqual(Set(discarded.map(\.item.id)).count, discarded.count, "round \(round)")
            XCTAssertTrue(discarded.allSatisfy { $0.startWall <= $0.endWall && $0.endWall.isFinite })
            if clock.bootSession == boot { XCTAssertTrue(discarded.allSatisfy { $0.endWall <= max(clock.wall, $0.startWall) }) }
            if let st = decoded.sanitized().stop, decoded.bootSession == boot {
                XCTAssertTrue(discarded.allSatisfy { $0.endWall <= max(st.wall, $0.startWall) }, "never after Snaptic stopped")
            }
            XCTAssertLessThanOrEqual(discarded.count, AwakeHold.maxHolds + 2)
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
