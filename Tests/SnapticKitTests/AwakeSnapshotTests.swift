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
}
