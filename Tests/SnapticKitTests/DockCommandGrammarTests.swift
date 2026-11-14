import XCTest
@testable import SnapticKit

/// 0.5 K5: `snaptic dock …` (PLAN 0.5 §4.21, §6.1).
final class DockCommandGrammarTests: XCTestCase {
    private let example = 1_794_516_300.0 // 2026-11-12T20:45:00Z

    func testParse() {
        XCTAssertEqual(DockCommandGrammar.parse(verb: "status", args: []), .status(json: false))
        XCTAssertEqual(DockCommandGrammar.parse(verb: "status", args: ["--json"]), .status(json: true))
        XCTAssertEqual(DockCommandGrammar.parse(verb: "pause", args: []), .pause(seconds: 3_600), "1 h if no time")
        XCTAssertEqual(DockCommandGrammar.parse(verb: "pause", args: ["30m"]), .pause(seconds: 1_800))
        XCTAssertEqual(DockCommandGrammar.parse(verb: "pause", args: ["1h30m"]), .pause(seconds: 5_400))
        XCTAssertEqual(DockCommandGrammar.parse(verb: "pause", args: ["90"]), .pause(seconds: 5_400), "minutes")
        XCTAssertEqual(DockCommandGrammar.parse(verb: "pause", args: ["24h"]), .pause(seconds: 86_400))
        XCTAssertEqual(DockCommandGrammar.parse(verb: "pause", args: ["1m"]), .pause(seconds: 60))
        XCTAssertEqual(DockCommandGrammar.parse(verb: "resume", args: []), .resume)
        XCTAssertEqual(DockCommandGrammar.defaultPauseSeconds, 3_600)
        XCTAssertEqual(DockCommandGrammar.maxPauseSeconds, 86_400)
    }

    /// Anything else is a usage error (exit 2): over 24 h, zero, words that aren't a duration, Awake's open-ended
    /// forms, and any flag but `status --json`.
    func testUsageErrors() {
        let bad: [(String, [String])] = [
            ("pause", ["25h"]), ("pause", ["0"]), ("pause", ["x"]), ("pause", ["forever"]), ("pause", ["idle"]),
            ("pause", ["until", "17:30"]), ("pause", ["until"]), ("pause", ["--json"]), ("pause", ["--force"]),
            ("pause", ["24h", "1m"]), ("pause", ["1441"]), ("pause", ["-30m"]), ("pause", ["30s"]),
            ("status", ["--all"]), ("status", ["--JSON"]), ("status", ["--json", "--json"]), ("status", ["json"]),
            ("status", ["-j"]), ("resume", ["--force"]), ("resume", ["now"]), ("resume", ["30m"]),
            ("", []), ("Status", []), ("PAUSE", []), ("stop", []), ("start", []), ("show", []), ("on", []),
            ("pause", [String(repeating: "1", count: 17)]), ("pause", ["1", "2", "3", "4"]),
        ]
        for (verb, args) in bad { XCTAssertNil(DockCommandGrammar.parse(verb: verb, args: args), "\(verb) \(args)") }
        XCTAssertEqual(DockCommandGrammar.usage, "Usage error. Run “snaptic help dock”.")
        XCTAssertEqual(ControlExit.usage, 2)
    }

    func testHelpTextAndRules() {
        XCTAssertEqual(DockCommandGrammar.verbs.map(\.verb), ["status", "pause", "resume"])
        XCTAssertEqual(DockCommandGrammar.verbs.map(\.summary), [
            "State, pause reason and cache counts (never names)",
            "Pause Dock Previews and its Dock click actions for a while (1 h if no time is given)",
            "Resume Dock Previews and its Dock click actions",
        ])
        XCTAssertEqual(KitControl.dockVerbRules.map(\.verb), DockCommandGrammar.verbs.map { "dock " + $0.verb })
        for rule in KitControl.dockVerbRules {
            XCTAssertEqual(rule.policy, rule.verb == "dock status" ? .read : .low, rule.verb)
            XCTAssertEqual(rule.offOnly, rule.verb == "dock pause", rule.verb)
            XCTAssertFalse(rule.holds || rule.sessionLimited, rule.verb)
            XCTAssertEqual(KitControl.verbRule(rule.verb), rule)
            XCTAssertTrue(rule.verb.split(separator: " ").allSatisfy { KitControl.isVerbWord(String($0)) }, rule.verb)
            // Counted like any verb (an ordinary .control line), not under Awake's fixed counters.
            XCTAssertNil(KitControl.counterKey(verb: rule.verb, outcome: .ok), rule.verb)
        }
        for rule in KitControl.awakeVerbRules + KitControl.iconsVerbRules {
            XCTAssertEqual(KitControl.verbRule(rule.verb), rule)
        }
        XCTAssertNil(KitControl.verbRule("dock"))
    }

    // MARK: Replies (G2-12, G3-1)

    func testAPauseNeverShortensOneAlreadyRunning() {
        let now = example - 3_600
        XCTAssertEqual(DockCommandGrammar.pauseEnd(current: nil, now: now, seconds: 3_600), example)
        XCTAssertEqual(DockCommandGrammar.pauseEnd(current: example + 600, now: now, seconds: 1_800), example + 600,
                       "a shorter pause keeps the later end")
        XCTAssertEqual(DockCommandGrammar.pauseEnd(current: example, now: now, seconds: 7_200), now + 7_200,
                       "a longer pause extends it")
        XCTAssertEqual(DockCommandGrammar.pauseEnd(current: now - 60, now: now, seconds: 60), now + 60,
                       "an ended pause counts as none")
        XCTAssertEqual(DockCommandGrammar.pauseEnd(current: .nan, now: now, seconds: 60), now + 60)
        XCTAssertEqual(DockCommandGrammar.pauseEnd(current: nil, now: now, seconds: 10 * 86_400), now + 86_400)
    }

    func testReplies() {
        XCTAssertEqual(DockCommandGrammar.pausedReply(until: example),
                       "Dock Previews is paused until 2026-11-12T20:45:00Z.")
        XCTAssertNil(DockCommandGrammar.pausedReply(until: .infinity))
        XCTAssertNil(DockCommandGrammar.pausedReply(until: -1))
        XCTAssertEqual(DockCommandGrammar.resumeReply(.onAgain), "Dock Previews is on again.")
        XCTAssertEqual(DockCommandGrammar.resumeReply(.cleared), "Dock Previews’ pause is cleared.")
        XCTAssertEqual(DockCommandGrammar.resumeReply(.notPaused), "Dock Previews isn’t paused.")
        XCTAssertNil(DockCommandGrammar.resumeReply(.unknownCommand))
        XCTAssertNil(DockCommandGrammar.resumeReply(.refused(.voiceOver)))
    }

    func testRefusals() {
        let pane: (Permission) -> String = { $0 == .accessibility ? "Accessibility" : "Screen Recording" }
        XCTAssertEqual(DockCLIRefusal.safeMode.message(paneName: pane), "Dock Previews is paused in Safe Mode.")
        XCTAssertEqual(DockCLIRefusal.needsPermission.message(paneName: pane),
                       "Dock Previews needs Accessibility. Open Snaptic Settings › Permissions.")
        XCTAssertEqual(DockCLIRefusal.otherTool.message(paneName: pane),
                       "Dock Previews is paused while another Dock preview app runs. Choose Run Both Anyway in Dock "
                       + "Previews’ Advanced settings to use both.")
        XCTAssertEqual(DockCLIRefusal.voiceOver.message(paneName: pane),
                       "Dock Previews is paused while VoiceOver is on.")
        for r in DockCLIRefusal.allCases {
            XCTAssertEqual(r.exitCode, ControlExit.unavailable)
            XCTAssertEqual(r.exitCode, 5)
            XCTAssertFalse(r.message(paneName: pane).contains("\n"))
        }
    }

    // MARK: Status (G2-12)

    func testStatusLineAndJSON() {
        let on = DockStatusFacts(state: .on, thumbnails: .on, clickActions: .off, keys: .on, cacheEntries: 12,
                                 cacheBytes: 3_400_000)
        XCTAssertEqual(DockCommandGrammar.statusLine(on),
                       "state=on reason=- until=- thumbnails=on clickActions=off keys=on cacheEntries=12 "
                       + "cacheBytes=3400000")
        XCTAssertEqual(DockCommandGrammar.statusJSON(on),
                       #"{"state":"on","reason":null,"until":null,"thumbnails":"on","clickActions":"off","keys":"on","#
                       + #""cacheEntries":12,"cacheBytes":3400000,"observerAttached":null,"live":null}"#)
        let paused = DockStatusFacts(state: .paused, reason: .command, pausedUntil: example, thumbnails: .noPermission,
                                     clickActions: .paused, keys: .stopped, cacheEntries: -4, cacheBytes: -1,
                                     observerAttached: true,
                                     live: DockStatusLiveCounts(observer: 2, clickTap: 1, keys: 0, panel: 1, timers: 3,
                                                                leases: -2))
        XCTAssertEqual(DockCommandGrammar.statusLine(paused),
                       "state=paused reason=command until=2026-11-12T20:45:00Z thumbnails=noPermission "
                       + "clickActions=paused keys=stopped cacheEntries=0 cacheBytes=0")
        XCTAssertEqual(DockCommandGrammar.statusJSON(paused),
                       #"{"state":"paused","reason":"command","until":"2026-11-12T20:45:00Z","thumbnails":"noPermission","#
                       + #""clickActions":"paused","keys":"stopped","cacheEntries":0,"cacheBytes":0,"#
                       + #""observerAttached":true,"live":{"observer":2,"clickTap":1,"keys":0,"panel":1,"timers":3,"#
                       + #""leases":0}}"#)
        // A pause held under row 5 keeps the row's reason and adds `until=` (G3-1).
        let held = DockStatusFacts(state: .unavailable, reason: .dockUnreadable, pausedUntil: example,
                                   clickActions: .disabled)
        XCTAssertTrue(DockCommandGrammar.statusLine(held)
            .hasPrefix("state=unavailable reason=dockUnreadable until=2026-11-12T20:45:00Z "))
        XCTAssertTrue(DockCommandGrammar.statusLine(held).contains(" clickActions=disabled "))
        // The plain keys, in order, then the JSON's extras.
        let plainKeys = DockCommandGrammar.statusLine(on).split(separator: " ").map { String($0.split(separator: "=")[0]) }
        XCTAssertEqual(plainKeys, ["state", "reason", "until", "thumbnails", "clickActions", "keys", "cacheEntries",
                                   "cacheBytes"])
        let object = try? JSONSerialization.jsonObject(with: Data(DockCommandGrammar.statusJSON(paused).utf8))
            as? [String: Any]
        XCTAssertEqual(object?.count, 10)
        XCTAssertEqual((object?["live"] as? [String: Any])?.count, 6)
    }

    func testValueSets() {
        XCTAssertEqual(DockCLIState.allCases.map(\.rawValue), ["on", "starting", "paused", "needsPermission",
                                                               "unavailable"])
        XCTAssertEqual(DockCLIReason.allCases.map(\.rawValue), ["safeMode", "otherTool", "voiceOver", "command",
                                                                "dockUnreadable"])
        XCTAssertEqual(DockCLIThumbnails.allCases.map(\.rawValue), ["on", "off", "noPermission"])
        XCTAssertEqual(DockCLIFeature.allCases.map(\.rawValue), ["on", "off", "paused", "stopped", "disabled"])
    }

    // MARK: The verb × state table (§4.21; DockControlsTests checks each cell)

    func testTableHasOneEntryPerRowInOrder() {
        // The table follows §4.21's order (Starting after rows 1 and 2); `DockPageRow` is §4.17's precedence order.
        XCTAssertEqual(Set(DockCommandGrammar.table.map(\.row)), Set(DockPageRow.allCases))
        XCTAssertEqual(DockCommandGrammar.table.count, DockPageRow.allCases.count)
        XCTAssertEqual(DockCommandGrammar.table.map(\.row.number), [1, 2, nil, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(DockPageRow.allCases.map(\.number), [1, 2, 3, 4, nil, 5, 6, 7, 8, 9])
        for row in DockPageRow.allCases {
            let cells = DockCommandGrammar.cells(row)
            XCTAssertEqual(cells.row, row)
            // A row that registers no verb answers every verb "Unknown command"; one that does never does.
            let unknown = [cells.status == .unknownCommand, cells.pause == .unknownCommand,
                           cells.resume == .unknownCommand, cells.resumeHeld == .unknownCommand]
            XCTAssertEqual(unknown, Array(repeating: !row.registersVerbs, count: 4), row.rawValue)
            // `status` reports the row's own state and reason.
            if let state = row.state {
                XCTAssertEqual(cells.status, .answers(state: state, reason: row.reason), row.rawValue)
            }
        }
    }

    // MARK: A9: the table as `DockCLI` applies it

    func testReachingFactsReachEachRow() {
        let held = DockCommandPause(untilUnix: example, clock: "8:45 PM")
        for row in DockPageRow.allCases {
            XCTAssertEqual(DockPageRules.row(.reaching(row)), row, row.rawValue)
            // A held pause doesn't change the row (G3-1), except that it makes row 8 apply over Working.
            XCTAssertEqual(DockPageRules.row(.reaching(row, commandPause: held)), row, row.rawValue)
            XCTAssertEqual(DockPageFacts.reaching(row, commandPause: held).commandPause, row == .working ? nil : held)
        }
        XCTAssertNotNil(DockPageFacts.reaching(.pausedByCommand).commandPause)
        XCTAssertNil(DockPageFacts.reaching(.working).commandPause)
    }

    /// Each cell of §4.21's verb × state table, as the step `DockCLI` takes: rows 1 and 2 are "Unknown command"
    /// (nothing is registered), Safe Mode, another tool and VoiceOver refuse `pause` and `resume`, row 4 refuses only
    /// `pause`, and `resume` clears a pause held under Starting, row 4 or row 5.
    func testStepFollowsTheTable() {
        typealias Steps = (status: DockCLIStep, pause: DockCLIStep, resume: DockCLIStep, resumeHeld: DockCLIStep)
        let pause = DockCLIStep.pause(seconds: 1_800)
        func refused(_ r: DockCLIRefusal) -> Steps { (.status(json: false), .refuse(r), .refuse(r), .refuse(r)) }
        let expected: [DockPageRow: Steps] = [
            .killSwitch: (.unknownCommand, .unknownCommand, .unknownCommand, .unknownCommand),
            .off: (.unknownCommand, .unknownCommand, .unknownCommand, .unknownCommand),
            .starting: (.status(json: false), pause, .resume(.notPaused), .resume(.cleared)),
            .safeMode: refused(.safeMode),
            .needsPermission: (.status(json: false), .refuse(.needsPermission), .resume(.notPaused), .resume(.cleared)),
            .dockUnreadable: (.status(json: false), pause, .resume(.notPaused), .resume(.cleared)),
            .otherTool: refused(.otherTool),
            .voiceOver: refused(.voiceOver),
            .pausedByCommand: (.status(json: false), pause, .resume(.onAgain), .resume(.onAgain)),
            .working: (.status(json: false), pause, .resume(.notPaused), .resume(.notPaused)),
        ]
        XCTAssertEqual(expected.count, DockPageRow.allCases.count)
        for row in DockPageRow.allCases {
            guard let want = expected[row] else { continue }
            for held in [false, true] {
                let name = "\(row.rawValue) held=\(held)"
                XCTAssertEqual(DockCommandGrammar.step(.status(json: false), row: row, held: held), want.status, name)
                XCTAssertEqual(DockCommandGrammar.step(.pause(seconds: 1_800), row: row, held: held), want.pause, name)
                XCTAssertEqual(DockCommandGrammar.step(.resume, row: row, held: held),
                               held ? want.resumeHeld : want.resume, name)
                let json = DockCommandGrammar.step(.status(json: true), row: row, held: held)
                XCTAssertEqual(json, row.registersVerbs ? .status(json: true) : .unknownCommand, name)
            }
            // The facts form reads the row and the held pause from the facts.
            let pauseHeld = DockCommandPause(untilUnix: example, clock: "")
            for facts in [DockPageFacts.reaching(row), .reaching(row, commandPause: pauseHeld)] {
                let held = facts.commandPause != nil
                for command in [DockCLICommand.status(json: false), .pause(seconds: 1_800), .resume] {
                    XCTAssertEqual(DockCommandGrammar.step(command, facts: facts),
                                   DockCommandGrammar.step(command, row: row, held: held), row.rawValue)
                }
            }
        }
    }

    func testClearsPause() {
        XCTAssertTrue(DockResumeCell.onAgain.clearsPause)
        XCTAssertTrue(DockResumeCell.cleared.clearsPause)
        XCTAssertFalse(DockResumeCell.notPaused.clearsPause)
        XCTAssertFalse(DockResumeCell.unknownCommand.clearsPause)
        for r in DockCLIRefusal.allCases { XCTAssertFalse(DockResumeCell.refused(r).clearsPause) }
        // Every cell `step` hands to `resume` has a reply.
        for cell in [DockResumeCell.onAgain, .cleared, .notPaused] { XCTAssertNotNil(DockCommandGrammar.resumeReply(cell)) }
    }

    /// P3-2: in Safe Mode `status` answers paused, safeMode, with no end, and `pause` and `resume` refuse (exit 5).
    func testSafeModeStatusAndRefusals() {
        let facts = DockPageFacts.reaching(.safeMode)
        guard let status = DockPauseRules.status(facts, keysOn: true, killed: [], cacheEntries: 0, cacheBytes: 0,
                                                 observerAttached: false, live: DockStatusLiveCounts()) else {
            return XCTFail("Safe Mode has a status")
        }
        XCTAssertTrue(DockCommandGrammar.statusLine(status).hasPrefix("state=paused reason=safeMode until=- "))
        XCTAssertTrue(DockCommandGrammar.statusJSON(status)
            .hasPrefix("{\"state\":\"paused\",\"reason\":\"safeMode\",\"until\":null,"))
        XCTAssertEqual(DockCommandGrammar.step(.pause(seconds: 3_600), facts: facts), .refuse(.safeMode))
        XCTAssertEqual(DockCommandGrammar.step(.resume, facts: facts), .refuse(.safeMode))
        XCTAssertEqual(DockCLIRefusal.safeMode.exitCode, 5)
        // Rows 1 and 2 have no status at all.
        for row in [DockPageRow.killSwitch, .off] {
            XCTAssertNil(DockPauseRules.status(.reaching(row), keysOn: true, killed: [], cacheEntries: 0, cacheBytes: 0,
                                               observerAttached: false, live: DockStatusLiveCounts()))
        }
    }

    /// The command-line sequences A9's `dockCases` run, on facts: `pause`, `pause 30m`, a later end that extends and
    /// an earlier one that doesn't, `resume`, `resume` while not paused, and M43 (a pause held when Accessibility is
    /// revoked: `status` shows its end, `pause` refuses, `resume` clears it).
    func testPauseResumeSequences() {
        var facts = DockPageFacts.reaching(.working)
        var now = example
        func apply(_ command: DockCLICommand) -> DockCLIStep {
            let step = DockCommandGrammar.step(command, facts: facts)
            switch step {
            case .pause(let seconds):
                let end = DockCommandGrammar.pauseEnd(current: facts.commandPause?.untilUnix, now: now, seconds: seconds)
                facts.commandPause = DockCommandPause(untilUnix: end, clock: "")
            case .resume(let cell) where cell.clearsPause:
                facts.commandPause = nil
            default:
                break
            }
            return step
        }
        XCTAssertEqual(apply(.pause(seconds: DockCommandGrammar.defaultPauseSeconds)), .pause(seconds: 3_600))
        XCTAssertEqual(facts.commandPause?.untilUnix, example + 3_600)
        XCTAssertEqual(DockPageRules.row(facts), .pausedByCommand)
        XCTAssertEqual(apply(.resume), .resume(.onAgain))
        XCTAssertEqual(DockCommandGrammar.resumeReply(.onAgain), "Dock Previews is on again.")
        XCTAssertEqual(DockPageRules.row(facts), .working)
        XCTAssertEqual(apply(.resume), .resume(.notPaused))
        XCTAssertEqual(DockCommandGrammar.resumeReply(.notPaused), "Dock Previews isn’t paused.")
        XCTAssertEqual(apply(.pause(seconds: 1_800)), .pause(seconds: 1_800))
        XCTAssertEqual(facts.commandPause?.untilUnix, example + 1_800)
        now += 60
        XCTAssertEqual(apply(.pause(seconds: 7_200)), .pause(seconds: 7_200))
        XCTAssertEqual(facts.commandPause?.untilUnix, example + 60 + 7_200, "a later end extends")
        XCTAssertEqual(apply(.pause(seconds: 1_800)), .pause(seconds: 1_800))
        XCTAssertEqual(facts.commandPause?.untilUnix, example + 60 + 7_200, "an earlier end doesn't shorten it")
        // M43: Accessibility is revoked with the pause held.
        facts.accessibility = false
        XCTAssertEqual(DockPageRules.row(facts), .needsPermission)
        XCTAssertEqual(DockPageRules.cli(facts)?.state, .needsPermission)
        XCTAssertEqual(DockPageRules.cli(facts)?.until, AwakeCommandGrammar.isoUTC(example + 60 + 7_200))
        XCTAssertEqual(apply(.pause(seconds: 1_800)), .refuse(.needsPermission))
        XCTAssertEqual(apply(.resume), .resume(.cleared))
        XCTAssertEqual(DockCommandGrammar.resumeReply(.cleared), "Dock Previews’ pause is cleared.")
        XCTAssertNil(facts.commandPause)
        XCTAssertNil(DockPageRules.cli(facts)?.until)
        XCTAssertEqual(apply(.resume), .resume(.notPaused))
        // Another tool and VoiceOver refuse both, and keep a held pause.
        for row in [DockPageRow.otherTool, .voiceOver] {
            facts = .reaching(row, commandPause: DockCommandPause(untilUnix: example, clock: ""))
            XCTAssertEqual(apply(.resume), .refuse(row == .otherTool ? .otherTool : .voiceOver))
            XCTAssertEqual(apply(.pause(seconds: 60)), .refuse(row == .otherTool ? .otherTool : .voiceOver))
            XCTAssertEqual(facts.commandPause?.untilUnix, example)
        }
    }

    func testSeededParseNeverTraps() {
        var rng = SeededGenerator(seed: 0xD0C_5E)
        let words = ["status", "pause", "resume", "--json", "30m", "1h30m", "90", "24h", "25h", "0", "forever",
                     "idle", "until", "17:30", "", "-", "--", "🙂", "\u{0}", "1e9", "-1",
                     String(repeating: "9", count: 300)]
        for _ in 0..<5_000 {
            let verb = words[Int(rng.next() % UInt64(words.count))]
            let args = (0..<Int(rng.next() % 5)).map { _ in words[Int(rng.next() % UInt64(words.count))] }
            if let c = DockCommandGrammar.parse(verb: verb, args: args) {
                XCTAssertTrue(["status", "pause", "resume"].contains(verb))
                if case .pause(let seconds) = c {
                    XCTAssertTrue((60...86_400).contains(seconds), "\(args)")
                }
            }
            let live = rng.next() % 2 == 0 ? nil : DockStatusLiveCounts(
                observer: Int(truncatingIfNeeded: rng.next()), clickTap: Int(truncatingIfNeeded: rng.next()),
                keys: Int(truncatingIfNeeded: rng.next()), panel: Int(truncatingIfNeeded: rng.next()),
                timers: Int(truncatingIfNeeded: rng.next()), leases: Int(truncatingIfNeeded: rng.next()))
            let facts = DockStatusFacts(
                state: DockCLIState.allCases[Int(rng.next() % 5)],
                reason: rng.next() % 6 == 0 ? nil : DockCLIReason.allCases[Int(rng.next() % 5)],
                pausedUntil: rng.next() % 2 == 0 ? nil : Double(bitPattern: rng.next()),
                thumbnails: DockCLIThumbnails.allCases[Int(rng.next() % 3)],
                clickActions: DockCLIFeature.allCases[Int(rng.next() % 5)],
                keys: DockCLIFeature.allCases[Int(rng.next() % 5)],
                cacheEntries: Int(truncatingIfNeeded: rng.next()), cacheBytes: Int(truncatingIfNeeded: rng.next()),
                observerAttached: rng.next() % 3 == 0 ? nil : rng.next() % 2 == 0, live: live)
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(DockCommandGrammar.statusJSON(facts).utf8)))
            let line = DockCommandGrammar.statusLine(facts)
            XCTAssertNil(line.range(of: "=-[0-9]", options: .regularExpression), "counts are never negative")
            XCTAssertEqual(line.split(separator: " ").count, 8)
            _ = DockCommandGrammar.pauseEnd(current: Double(bitPattern: rng.next()),
                                            now: Double(Int32(truncatingIfNeeded: rng.next())),
                                            seconds: Int(truncatingIfNeeded: rng.next()))
        }
    }
}
