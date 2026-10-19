import XCTest
@testable import SnapticKit

final class AwakeCommandGrammarTests: XCTestCase {
    private func parse(_ verb: String, _ args: String...) -> AwakeCommand? {
        AwakeCommandGrammar.parse(verb: verb, args: args)
    }

    func testStatus() {
        XCTAssertEqual(parse("status"), .status(json: false))
        XCTAssertEqual(parse("status", "--json"), .status(json: true))
        XCTAssertNil(parse("status", "--json", "--json"))
        XCTAssertNil(parse("status", "now"))
    }

    func testStart() {
        XCTAssertEqual(parse("start"), .start(nil, displayMaySleep: false))
        XCTAssertEqual(parse("start", "2h"), .start(.duration(seconds: 7_200), displayMaySleep: false))
        XCTAssertEqual(parse("start", "--display-may-sleep", "90"), .start(.duration(seconds: 5_400), displayMaySleep: true))
        XCTAssertEqual(parse("start", "1h", "--display-may-sleep"), .start(.duration(seconds: 3_600), displayMaySleep: true))
        XCTAssertEqual(parse("start", "until", "17:30"), .start(.untilClock(hour: 17, minute: 30), displayMaySleep: false))
        XCTAssertEqual(parse("start", "idle"), .start(.untilIdle, displayMaySleep: false))
        XCTAssertEqual(parse("start", "indefinite"), .start(.indefinite, displayMaySleep: false),
                       "parses; SessionController refuses it with exit 4")
        XCTAssertNil(parse("start", "--display-may-sleep", "--display-may-sleep"))
        XCTAssertNil(parse("start", "--pid", "5"))
        XCTAssertNil(parse("start", "-5m"))
        XCTAssertNil(parse("start", "lots"))
        XCTAssertNil(parse("start", "31d"))
    }

    func testHold() {
        XCTAssertEqual(parse("hold"), .hold(pid: nil, maxSeconds: nil))
        XCTAssertEqual(parse("hold", "--pid", "4242"), .hold(pid: 4_242, maxSeconds: nil))
        XCTAssertEqual(parse("hold", "--max", "3h"), .hold(pid: nil, maxSeconds: 10_800))
        XCTAssertEqual(parse("hold", "--max", "24h", "--pid", "2"), .hold(pid: 2, maxSeconds: 86_400))
        for bad: [String] in [["--pid", "1"], ["--pid", "0"], ["--pid", "-5"], ["--pid", "x"], ["--pid", "12345678"],
                              ["--pid", "2147483648"], ["--pid"], ["--max", "25h"], ["--max", "idle"],
                              ["--max", "until", "5pm"], ["--max", "forever"], ["--pid", "5", "--pid", "6"],
                              ["--max", "1h", "--max", "2h"], ["--quiet"], ["5"], ["--pid", "５"], ["--pid", " 5"]] {
            XCTAssertNil(AwakeCommandGrammar.parse(verb: "hold", args: bad), "\(bad)")
        }
    }

    func testPresetByIndexAndName() {
        XCTAssertEqual(parse("preset", "1"), .preset(.index(1)))
        XCTAssertEqual(parse("preset", "12"), .preset(.index(12)))
        XCTAssertEqual(parse("preset", "Deep", "Work"), .preset(.name("Deep Work")))
        XCTAssertEqual(parse("preset", "For 1 Hour"), .preset(.name("For 1 Hour")))
        XCTAssertNil(parse("preset"))
        XCTAssertNil(parse("preset", "0"))
        XCTAssertNil(parse("preset", "100"))
        XCTAssertNil(parse("preset", "--name", "x"))
        XCTAssertNil(parse("preset", String(repeating: "n", count: 65)))
        XCTAssertNil(parse("preset", "bad\u{07}name"), "control characters are refused, not cleaned")
        XCTAssertEqual(parse("preset", String(repeating: "n", count: 64)), .preset(.name(String(repeating: "n", count: 64))))
    }

    func testExtendStopPause() {
        XCTAssertEqual(parse("extend", "1h"), .extend(seconds: 3_600))
        XCTAssertEqual(parse("extend", "1h", "30m"), .extend(seconds: 5_400))
        XCTAssertNil(parse("extend"))
        XCTAssertNil(parse("extend", "idle"))
        XCTAssertNil(parse("extend", "until", "5pm"))
        XCTAssertEqual(parse("stop"), .stop)
        XCTAssertNil(parse("stop", "now"))
        XCTAssertEqual(parse("pause"), .pause(seconds: nil))
        XCTAssertEqual(parse("pause", "2h"), .pause(seconds: 7_200))
        XCTAssertEqual(parse("pause", "24h"), .pause(seconds: 86_400))
        XCTAssertNil(parse("pause", "25h"))
        XCTAssertNil(parse("pause", "forever"))
    }

    func testUnknownVerbsAndOversizedInput() {
        XCTAssertNil(parse("resume"))
        XCTAssertNil(parse("edit-rules"))
        XCTAssertNil(parse("START"))
        XCTAssertNil(AwakeCommandGrammar.parse(verb: "start", args: Array(repeating: "1h", count: 17)))
        XCTAssertNil(AwakeCommandGrammar.parse(verb: "preset", args: [String(repeating: "x", count: 300)]))
    }

    func testLocaleIndependentNumbers() {
        XCTAssertNil(parse("start", "1,5h"), "a comma is never a decimal separator on the CLI")
        XCTAssertEqual(parse("start", "1.5h"), .start(.duration(seconds: 5_400), displayMaySleep: false))
        XCTAssertNil(parse("start", "٢h"))
    }

    // MARK: Status output

    private func facts(active: Bool = true, source: AwakeStatusSource? = .manual, kind: AwakeHistoryKind? = .duration,
                       display: AwakeDisplayPolicy? = .keepOn, end: Double? = 1_760_808_600, remaining: Double? = 3_540.2,
                       rule: Int? = nil, pids: [Int32] = []) -> AwakeStatusFacts {
        AwakeStatusFacts(active: active, source: source, kind: kind, display: display, endUnix: end, remaining: remaining,
                         triggerNumber: rule, holdPIDs: pids)
    }

    func testStatusLine() {
        XCTAssertEqual(AwakeCommandGrammar.statusLine(facts(active: false)), "inactive")
        XCTAssertEqual(AwakeCommandGrammar.statusLine(facts()), "active\tmanual\tduration\tkeepOn\t2025-10-18T17:30:00Z\t3541\t0")
        XCTAssertEqual(AwakeCommandGrammar.statusLine(facts(source: .automatic, kind: .automatic, display: .maySleep, end: nil,
                                                            remaining: nil, rule: 2, pids: [10, 11])),
                       "active\tautomatic\tautomatic\tmaySleep\t-\t-\t2")
    }

    func testStatusJSON() {
        XCTAssertEqual(AwakeCommandGrammar.statusJSON(facts(active: false, pids: [])),
                       #"{"active":false,"source":null,"kind":null,"display":null,"end":null,"remaining":null,"rule":null,"holds":0,"pids":[],"lidClosed":false}"#)
        XCTAssertEqual(AwakeCommandGrammar.statusJSON(facts(source: .holds, kind: .process, display: .maySleep, rule: nil,
                                                            pids: [4242, 77])),
                       #"{"active":true,"source":"holds","kind":"process","display":"maySleep","end":"2025-10-18T17:30:00Z","remaining":3541,"rule":null,"holds":2,"pids":[4242,77],"lidClosed":false}"#)
        let rule = AwakeCommandGrammar.statusJSON(facts(source: .automatic, kind: .automatic, end: nil, remaining: nil, rule: 3))
        XCTAssertTrue(rule.contains(#""rule":3"#))
        // Valid JSON on every platform.
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(rule.utf8)))
    }

    /// 0.3.1 B1: `lidClosed` is the JSON's last key; the tab-separated line doesn't change; nothing governing reads
    /// false.
    func testStatusLidClosed() {
        var on = facts()
        on.lidClosed = true
        XCTAssertTrue(AwakeCommandGrammar.statusJSON(on).hasSuffix(#","pids":[],"lidClosed":true}"#))
        XCTAssertEqual(AwakeCommandGrammar.statusLine(on), AwakeCommandGrammar.statusLine(facts()))
        var idle = facts(active: false)
        idle.lidClosed = true
        XCTAssertTrue(AwakeCommandGrammar.statusJSON(idle).hasSuffix(#""lidClosed":false}"#))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(AwakeCommandGrammar.statusJSON(on).utf8)))
        let n = ClockNow(wall: 1_700_000_000, continuous: 100, bootSession: "B")
        let s = AwakeClock.start(.indefinite, options: AwakeSessionOptions(), presetID: nil, source: .menu, now: n,
                                 id: StableID.derived(namespace: "lid", name: "s"))
        XCTAssertTrue(AwakeStatusFacts(governing: .manual(s), holds: [], now: n, lidClosed: true).lidClosed)
        XCTAssertFalse(AwakeStatusFacts(governing: .manual(s), holds: [], now: n).lidClosed)
        XCTAssertFalse(AwakeStatusFacts(governing: .inactive, holds: [], now: n, lidClosed: true).lidClosed)
    }

    func testISOTimeIsHandFormattedUTC() {
        XCTAssertEqual(AwakeCommandGrammar.isoUTC(0), "1970-01-01T00:00:00Z")
        XCTAssertEqual(AwakeCommandGrammar.isoUTC(951_782_400), "2000-02-29T00:00:00Z")
        XCTAssertEqual(AwakeCommandGrammar.isoUTC(1_709_164_799.9), "2024-02-28T23:59:59Z")
        XCTAssertEqual(AwakeCommandGrammar.isoUTC(4_102_444_800), "2100-01-01T00:00:00Z")
        XCTAssertEqual(AwakeCommandGrammar.isoUTC(253_402_300_799), "9999-12-31T23:59:59Z")
        XCTAssertNil(AwakeCommandGrammar.isoUTC(-1))
        XCTAssertNil(AwakeCommandGrammar.isoUTC(.nan))
        XCTAssertNil(AwakeCommandGrammar.isoUTC(1e20))
        // Agrees with Foundation's calendar arithmetic (UTC, Gregorian) on a sample of instants.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        var rng = SeededGenerator(seed: 0x150)
        for _ in 0..<500 {
            let t = Double(rng.next() % 4_000_000_000)
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: t))
            let parts = [c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0]
            let iso = AwakeCommandGrammar.isoUTC(t) ?? ""
            let digits = iso.split(whereSeparator: { "-T:Z".contains($0) }).compactMap { Int($0) }
            XCTAssertEqual(digits, parts, iso)
        }
    }

    func testStatusFactsFromGoverning() {
        let now = ClockNow(wall: 1_000_000, continuous: 500, bootSession: "B")
        let s = AwakeClock.start(.duration(seconds: 600), options: AwakeSessionOptions(display: .maySleep), presetID: nil,
                                 source: .commandLine, now: ClockNow(wall: 999_900, continuous: 400, bootSession: "B"),
                                 id: StableID.derived(namespace: "t", name: "s"))
        let holds = [AwakeClock.hold(.process(pid: 321, startTime: 1), capSeconds: 3_600, now: now,
                                     id: StableID.derived(namespace: "t", name: "h"))]
        let manual = AwakeStatusFacts(governing: .manual(s), holds: holds, now: now)
        XCTAssertEqual(manual, AwakeStatusFacts(active: true, source: .manual, kind: .duration, display: .maySleep,
                                                endUnix: 1_000_500, remaining: 500, triggerNumber: nil, holdPIDs: [321]))
        let top = TriggerTop(id: StableID.derived(namespace: "t", name: "r"), index: 2, options: AwakeSessionOptions(), since: 1)
        XCTAssertEqual(AwakeStatusFacts(governing: .trigger(top), holds: [], now: now).triggerNumber, 3)
        let held = AwakeStatusFacts(governing: .holds(holds), holds: holds, now: now)
        XCTAssertEqual(held.source, .holds)
        XCTAssertEqual(held.kind, .process)
        XCTAssertEqual(held.remaining, 3_600)
        XCTAssertFalse(AwakeStatusFacts(governing: .inactive, holds: [], now: now).active)
        XCTAssertEqual(AwakeCommandGrammar.statusLine(held).split(separator: "\t").last, "1")
    }

    func testHoldReply() {
        XCTAssertEqual(AwakeCommandGrammar.holdReply(pid: nil, capSeconds: 43_200),
                       "Holding until this command ends (at most 12 h). Press Control-C to stop.")
        XCTAssertEqual(AwakeCommandGrammar.holdReply(pid: 4_242, capSeconds: 10_800),
                       "Holding while process 4242 runs (at most 3 h).")
        XCTAssertEqual(AwakeCommandGrammar.capText(5_400), "1 h 30 min")
        XCTAssertEqual(AwakeCommandGrammar.capText(2_700), "45 min")
        XCTAssertEqual(AwakeCommandGrammar.capText(61), "2 min")
        XCTAssertEqual(AwakeCommandGrammar.capText(0), "1 min")
    }

    func testActionIDs() {
        XCTAssertEqual(AwakeActionID.allAwake.map(\.rawValue),
                       ["awake.toggle", "awake.keepDisplayOn", "awake.preset1", "awake.preset2", "awake.preset3",
                        "awake.preset4", "awake.pauseAutomatic"])
        XCTAssertEqual(AwakeActionID.preset(3), .preset3)
        XCTAssertNil(AwakeActionID.preset(5))
    }

    func testParseFuzzNeverTraps() {
        var rng = SeededGenerator(seed: 0xC11)
        let verbs = ["status", "start", "hold", "preset", "extend", "stop", "pause", "x"]
        let words = ["--json", "--pid", "--max", "--display-may-sleep", "1", "0", "-1", "99999999", "1h", "30m", "1.5h",
                     "until", "17:30", "5pm", "idle", "forever", "indefinite", "1e9", "٣", "", " ", "\u{0}", "Work"]
        for _ in 0..<50_000 {
            let verb = verbs[Int(rng.next() % UInt64(verbs.count))]
            let args = (0..<Int(rng.next() % 6)).map { _ in words[Int(rng.next() % UInt64(words.count))] }
            guard let command = AwakeCommandGrammar.parse(verb: verb, args: args) else { continue }
            switch command {
            case .hold(let pid, let cap):
                if let p = pid { XCTAssertGreaterThan(p, 1) }
                if let c = cap { XCTAssertLessThanOrEqual(c, AwakeClock.holdMaxCapSeconds) }
            case .pause(let s?):
                XCTAssertLessThanOrEqual(s, 86_400)
            case .extend(let s):
                XCTAssertTrue(AwakeClock.durationRange.contains(s))
            case .preset(.index(let n)):
                XCTAssertGreaterThanOrEqual(n, 1)
            case .preset(.name(let n)):
                XCTAssertFalse(n.isEmpty)
                XCTAssertLessThanOrEqual(n.unicodeScalars.count, 64)
            default:
                break
            }
        }
    }
}
