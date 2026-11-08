import XCTest
@testable import SnapticKit

/// 0.4 K5: `snaptic icons …` (§4.14).
final class IconsCommandGrammarTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "show", args: []), .show(all: false))
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "show", args: ["--all"]), .show(all: true))
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "hide", args: []), .hide)
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "toggle", args: []), .toggle(all: false))
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "toggle", args: ["--all"]), .toggle(all: true))
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "status", args: []), .status(json: false))
        XCTAssertEqual(IconsCommandGrammar.parse(verb: "status", args: ["--json"]), .status(json: true))
    }

    /// `--all` only with show and toggle, `--json` only with status, each once; nothing else (usage, exit 2).
    func testUsageErrors() {
        let bad: [(String, [String])] = [
            ("hide", ["--all"]), ("status", ["--all"]), ("show", ["--json"]), ("show", ["--all", "--all"]),
            ("toggle", ["--all", "--json"]), ("status", ["--json", "--json"]), ("show", ["all"]), ("show", ["-a"]),
            ("show", ["--ALL"]), ("hide", ["now"]), ("status", ["--JSON"]), ("", []), ("Show", []), ("open", []),
            ("list", []), ("arrange", []), ("show", ["--all", "x", "y"]), ("show", [String(repeating: "-", count: 17)]),
        ]
        for (verb, args) in bad { XCTAssertNil(IconsCommandGrammar.parse(verb: verb, args: args), "\(verb) \(args)") }
    }

    func testCLICommandsMapToTheQueuesCommands() {
        XCTAssertEqual(IconsCLICommand.show(all: false).command, .show)
        XCTAssertEqual(IconsCLICommand.show(all: true).command, .showAll)
        XCTAssertEqual(IconsCLICommand.hide.command, .hide)
        XCTAssertEqual(IconsCLICommand.toggle(all: false).command, .toggle)
        XCTAssertEqual(IconsCLICommand.toggle(all: true).command, .toggleAll)
        XCTAssertNil(IconsCLICommand.status(json: true).command)
    }

    func testVerbsAndRules() {
        XCTAssertEqual(IconsCommandGrammar.verbs.map(\.verb), ["show", "hide", "toggle", "status"])
        XCTAssertEqual(KitControl.iconsVerbRules.map(\.verb), IconsCommandGrammar.verbs.map { "icons " + $0.verb })
        for rule in KitControl.iconsVerbRules {
            XCTAssertEqual(rule.policy, rule.verb == "icons status" ? .read : .low, rule.verb)
            XCTAssertFalse(rule.offOnly || rule.holds || rule.sessionLimited, rule.verb)
            XCTAssertEqual(KitControl.verbRule(rule.verb), rule)
            XCTAssertTrue(rule.verb.split(separator: " ").allSatisfy { KitControl.isVerbWord(String($0)) }, rule.verb)
            // Counted like any verb (an ordinary .control line), not under Awake's fixed counters.
            XCTAssertNil(KitControl.counterKey(verb: rule.verb, outcome: .ok), rule.verb)
        }
        for rule in KitControl.awakeVerbRules { XCTAssertEqual(KitControl.verbRule(rule.verb), rule) }
        XCTAssertNotNil(KitControl.counterKey(verb: "awake status", outcome: .ok))
        XCTAssertTrue(IconsCommandGrammar.verbs.allSatisfy { !$0.summary.isEmpty })
    }

    func testStatusLineAndJSON() {
        let s = IconsStatusFacts(engine: .native, state: .collapsed, hidden: 7, alwaysHidden: 2, shown: 5,
                                 layoutAgeSeconds: 12.9)
        XCTAssertEqual(IconsCommandGrammar.statusLine(s), "engine=native state=collapsed hidden=7 alwaysHidden=2 shown=5")
        XCTAssertEqual(IconsCommandGrammar.statusJSON(s),
                       #"{"engine":"native","state":"collapsed","hidden":7,"alwaysHidden":2,"shown":5,"layoutAgeSeconds":12}"#)
        let none = IconsStatusFacts(engine: .unavailable, state: .unavailable)
        XCTAssertEqual(IconsCommandGrammar.statusLine(none),
                       "engine=unavailable state=unavailable hidden=0 alwaysHidden=0 shown=0")
        XCTAssertEqual(IconsCommandGrammar.statusJSON(none),
                       #"{"engine":"unavailable","state":"unavailable","hidden":0,"alwaysHidden":0,"shown":0,"layoutAgeSeconds":null}"#)
        let json = IconsCommandGrammar.statusJSON(s)
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(object?.count, 6)
    }

    func testLayoutAgeIsClamped() {
        XCTAssertNil(IconsCommandGrammar.layoutAge(nil))
        XCTAssertNil(IconsCommandGrammar.layoutAge(.nan))
        XCTAssertNil(IconsCommandGrammar.layoutAge(.infinity))
        XCTAssertEqual(IconsCommandGrammar.layoutAge(-5), 0)
        XCTAssertEqual(IconsCommandGrammar.layoutAge(0.4), 0)
        XCTAssertEqual(IconsCommandGrammar.layoutAge(1e300), IconsCommandGrammar.maxLayoutAgeSeconds)
    }

    func testRefusals() {
        XCTAssertNil(IconsCLIRefusal(state: .collapsed))
        XCTAssertNil(IconsCLIRefusal(state: .expanded))
        XCTAssertEqual(IconsCLIRefusal(state: .paused), .paused)
        XCTAssertEqual(IconsCLIRefusal(state: .needsPermission), .needsPermission)
        XCTAssertEqual(IconsCLIRefusal(state: .unavailable), .unavailable)
        XCTAssertEqual(IconsCLIRefusal(.arrangement), .arrangement)
        XCTAssertEqual(IconsCLIRefusal(.needsPermission), .needsPermission)
        for r in [IconsRefusal.arrowHidden, .dividerHidden, .ownItems, .exam] { XCTAssertNil(IconsCLIRefusal(r)) }
        XCTAssertEqual(IconsCLIRefusal.paused.message, "Hidden Icons is paused while another menu bar app hides icons.")
        XCTAssertEqual(IconsCLIRefusal.needsPermission.message,
                       "Hidden Icons needs Device Control and Data Access. Open Snaptic Settings › Permissions.")
        XCTAssertEqual(IconsCLIRefusal.unavailable.message, "Hidden Icons isn’t available on this version of macOS.")
        XCTAssertEqual(IconsCLIRefusal.arrangement.message, "Drag the | divider to the left of the arrow (hold ⌘).")
        for r in IconsCLIRefusal.allCases {
            XCTAssertEqual(r.exitCode, ControlExit.unavailable)
            XCTAssertFalse(r.message.contains("\n"))
        }
    }

    func testSeededParseNeverTraps() {
        var rng = SeededGenerator(seed: 0x1C0_5E)
        let words = ["show", "hide", "toggle", "status", "--all", "--json", "", "-", "--", "all", "🙂", "\u{0}",
                     String(repeating: "x", count: 300)]
        for _ in 0..<5_000 {
            let verb = words[Int(rng.next() % UInt64(words.count))]
            let args = (0..<Int(rng.next() % 5)).map { _ in words[Int(rng.next() % UInt64(words.count))] }
            if let c = IconsCommandGrammar.parse(verb: verb, args: args) {
                XCTAssertTrue(["show", "hide", "toggle", "status"].contains(verb))
                XCTAssertLessThanOrEqual(args.count, 1)
                _ = c.command
            }
            let facts = IconsStatusFacts(engine: IconsCLIEngine.allCases[Int(rng.next() % 3)],
                                         state: IconsCLIState.allCases[Int(rng.next() % 5)],
                                         hidden: Int(truncatingIfNeeded: rng.next()),
                                         alwaysHidden: Int(truncatingIfNeeded: rng.next()),
                                         shown: Int(truncatingIfNeeded: rng.next()),
                                         layoutAgeSeconds: Double(bitPattern: rng.next()))
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(IconsCommandGrammar.statusJSON(facts).utf8)))
            XCTAssertFalse(IconsCommandGrammar.statusLine(facts).contains("-"), "counts are never negative")
        }
    }
}
