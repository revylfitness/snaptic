import XCTest
@testable import SnapticKit

final class KitControlTests: XCTestCase {
    // MARK: Wire format

    func testRequestRoundTrip() throws {
        let r = ControlRequest(verb: "layout apply", arguments: ["Office"], json: true, skipConfirmation: false)
        let line = try XCTUnwrap(KitControl.encode(r))
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(try KitControl.decodeRequest(line.dropLast()).get(), r)
    }

    func testResponseRoundTrip() throws {
        let r = ControlResponse.failure(ControlExit.refused, "Only off")
        let line = try XCTUnwrap(KitControl.encode(r))
        XCTAssertEqual(KitControl.decodeResponse(line.dropLast()), r)
    }

    func testOldClientsWithoutFlagsDecode() throws {
        let r = try KitControl.decodeRequest(Data(#"{"verb":"list","arguments":[]}"#.utf8)).get()
        XCTAssertFalse(r.json)
        XCTAssertFalse(r.skipConfirmation)
    }

    func testMalformedRequestsAreUsageErrors() {
        for bad in ["", "nope", "{}", #"{"verb":""}"#, #"{"verb":"Bad Verb"}"#, #"{"verb":"a  b"}"#,
                    #"{"verb":"a b c d e"}"#, #"{"verb":"x/y"}"#, #"{"verb":1}"#] {
            guard case .failure(let response) = KitControl.decodeRequest(Data(bad.utf8)) else {
                XCTFail(bad); continue
            }
            XCTAssertEqual(response.exitCode, ControlExit.usage, bad)
        }
    }

    func testLimits() {
        let many = (0..<40).map { "\"a\($0)\"" }.joined(separator: ",")
        if case .success = KitControl.decodeRequest(Data(#"{"verb":"set","arguments":[\#(many)]}"#.utf8)) { XCTFail() }
        let long = String(repeating: "x", count: 2000)
        if case .success = KitControl.decodeRequest(Data(#"{"verb":"set","arguments":["\#(long)"]}"#.utf8)) { XCTFail() }
        if case .success = KitControl.decodeRequest(Data(count: KitControl.maxMessageBytes + 1)) { XCTFail() }
        XCTAssertNil(KitControl.encode(ControlResponse.ok(String(repeating: "y", count: 70_000))))
    }

    func testFuzzedRequestsNeverCrash() {
        var rng = SeededGenerator(seed: 0xC0DE)
        let pieces = ["{", "}", "\"verb\"", ":", "\"list\"", ",", "\"arguments\"", "[", "]", "\"x\"", "null", "1", "true"]
        for _ in 0..<5_000 {
            let text = (0..<Int(rng.next() % 12)).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }.joined()
            if case .success(let r) = KitControl.decodeRequest(Data(text.utf8)) {
                XCTAssertTrue(r.verb.split(separator: " ").allSatisfy { KitControl.isVerbWord(String($0)) })
            }
        }
    }

    // MARK: Command line

    func testParseCommandLine() throws {
        let c = try KitControl.parseCommandLine(["--json", "set", "brightness", "main", "-10"]).get()
        XCTAssertEqual(c.words, ["set", "brightness", "main", "-10"])
        XCTAssertTrue(c.json)
        XCTAssertFalse(c.yes)
        XCTAssertTrue(try KitControl.parseCommandLine([]).get().help)
        XCTAssertTrue(try KitControl.parseCommandLine(["--help"]).get().help)
        XCTAssertEqual(try KitControl.parseCommandLine(["--yes", "rotate", "main", "90"]).get().words, ["rotate", "main", "90"])
        XCTAssertEqual(try KitControl.parseCommandLine(["run", "--", "--json"]).get().words, ["run", "--json"])
        if case .success = KitControl.parseCommandLine(["--frobnicate"]) { XCTFail() }
    }

    // MARK: Verbs

    func testLongestVerbWins() {
        let verbs = ["layout", "layout apply", "layout list", "list"]
        XCTAssertEqual(KitControl.match(["layout", "apply", "Office"], verbs: verbs)?.verb, "layout apply")
        XCTAssertEqual(KitControl.match(["layout", "apply", "Office"], verbs: verbs)?.arguments, ["Office"])
        XCTAssertEqual(KitControl.match(["Layout", "LIST"], verbs: verbs)?.verb, "layout list")
        XCTAssertEqual(KitControl.match(["layout", "Office"], verbs: verbs)?.arguments, ["Office"])
        XCTAssertNil(KitControl.match(["frob"], verbs: verbs))
        XCTAssertNil(KitControl.match([], verbs: verbs))
    }

    func testArgumentsKeepTheirCase() {
        XCTAssertEqual(KitControl.match(["layout", "apply", "Office"], verbs: ["layout apply"])?.arguments, ["Office"])
    }

    // MARK: Policy

    func testTurningOnIsDetected() {
        XCTAssertTrue(KitControl.requestsTurningOn(["on"]))
        XCTAssertTrue(KitControl.requestsTurningOn(["ENABLE"]))
        XCTAssertTrue(KitControl.requestsTurningOn(["start", "2"]))
        XCTAssertFalse(KitControl.requestsTurningOn(["off"]))
        XCTAssertFalse(KitControl.requestsTurningOn([]))
    }

    /// FIXES-R3 2: display number 1 is a selector, not "on".
    func testDisplayNumberOneIsNotTurningOn() {
        XCTAssertFalse(KitControl.requestsTurningOn(["off", "1"]))
        XCTAssertFalse(KitControl.requestsTurningOn(["1"]))
        XCTAssertFalse(KitControl.requestsTurningOn(["off", "on"]))
        XCTAssertFalse(KitControl.requestsTurningOn(["windowSwitcher"]))
    }

    /// FIXES-R3 1: --yes counts only with the user's setting and only for trial verbs.
    func testSkipConfirmationNeedsTheSettingAndATrialVerb() {
        XCTAssertTrue(KitControl.skipsConfirmation(requested: true, allowed: true, policy: .trial))
        XCTAssertFalse(KitControl.skipsConfirmation(requested: true, allowed: false, policy: .trial))
        XCTAssertFalse(KitControl.skipsConfirmation(requested: false, allowed: true, policy: .trial))
        for policy in [ControlPolicy.read, .low, .preConfirm] {
            XCTAssertFalse(KitControl.skipsConfirmation(requested: true, allowed: true, policy: policy))
        }
    }

    // MARK: JSON output (FIXES-R3 10)

    private func object(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    func testJSONRepliesPassHandlerJSONThrough() {
        let array = ControlResponse.ok(#"[{"display":1}]"#)
        XCTAssertEqual(KitControl.jsonReply(array), array)
        let dict = ControlResponse.ok(#" {"a":1}"#)
        XCTAssertEqual(KitControl.jsonReply(dict), dict)
    }

    func testJSONRepliesWrapTextAndEmptyOutput() throws {
        XCTAssertEqual(object(KitControl.jsonReply(.ok()).output)?["ok"] as? Bool, true)
        XCTAssertNil(object(KitControl.jsonReply(.ok()).output)?["output"])
        let wrapped = try XCTUnwrap(object(KitControl.jsonReply(.ok("1. Office [trusted]\n2. Home")).output))
        XCTAssertEqual(wrapped["output"] as? String, "1. Office [trusted]\n2. Home")
        // A bare number or a broken object is text, not JSON.
        XCTAssertEqual(object(KitControl.jsonReply(.ok("60")).output)?["output"] as? String, "60")
        XCTAssertEqual(object(KitControl.jsonReply(.ok("{broken")).output)?["output"] as? String, "{broken")
    }

    func testJSONRepliesLeaveFailuresAlone() {
        let failure = ControlResponse.failure(ControlExit.cancelled, "Change reverted")
        XCTAssertEqual(KitControl.jsonReply(failure), failure)
    }

    func testClientErrorsAsJSON() throws {
        let error = try XCTUnwrap(object(KitControl.errorJSON(ControlExit.usage, "Unknown option: -x")))
        XCTAssertEqual(error["exitCode"] as? Int, 2)
        XCTAssertEqual(error["error"] as? String, "Unknown option: -x")
        XCTAssertTrue(KitControl.wantsJSON(["--json", "list"]))
        XCTAssertTrue(KitControl.wantsJSON(["--yes", "--frob", "--json"]))
        XCTAssertFalse(KitControl.wantsJSON(["list", "--json"]))
        XCTAssertFalse(KitControl.wantsJSON(["--", "--json"]))
        XCTAssertFalse(KitControl.wantsJSON([]))
    }

    func testProtectedSettingsAreFound() {
        XCTAssertEqual(KitControl.protectedSetting(verb: "toggle", arguments: ["hooks"]), "hooks")
        XCTAssertEqual(KitControl.protectedSetting(verb: "set", arguments: ["dim-to-black", "on"]), "dimtoblack")
        XCTAssertEqual(KitControl.protectedSetting(verb: "features", arguments: ["autoDisconnectBuiltin", "off"]),
                       "autodisconnectbuiltin")
        XCTAssertEqual(KitControl.protectedSetting(verb: "module", arguments: ["cli"]), "cli")
        XCTAssertNil(KitControl.protectedSetting(verb: "set", arguments: ["brightness", "50"]))
        // The 0.2 sleep-prevention words went with the feature (R5-14).
        XCTAssertNil(KitControl.protectedSetting(verb: "feature disable", arguments: ["sleep-prevention"]))
        XCTAssertNil(KitControl.protectedSetting(verb: "set", arguments: ["prevent_sleep", "on"]))
        XCTAssertNil(KitControl.protectedSetting(verb: "toggle", arguments: ["SleepPrevention"]))
        XCTAssertNil(KitControl.protectedSetting(verb: "disconnect", arguments: ["main"]))   // an action, not a setting
        // The host's `feature disable` verb: protected features stay untouchable even off.
        XCTAssertEqual(KitControl.protectedSetting(verb: "feature disable", arguments: ["disconnect"]), "disconnect")
        XCTAssertEqual(KitControl.protectedSetting(verb: "feature disable", arguments: ["custom-actions"]), "customactions")
        XCTAssertNil(KitControl.protectedSetting(verb: "feature disable", arguments: ["xdr"]))
    }

    func testShellQuoting() {
        XCTAssertEqual(KitControl.shellQuoted("/Applications/Snaptic.app"), "'/Applications/Snaptic.app'")
        XCTAssertEqual(KitControl.shellQuoted("/Users/o'neil/Snaptic"), "'/Users/o'\\''neil/Snaptic'")
        XCTAssertEqual(KitControl.shellQuoted(""), "''")
        XCTAssertEqual(KitControl.installCommand(executable: "/A B/Snaptic"),
                       "sudo ln -sf '/A B/Snaptic' /usr/local/bin/snaptic")
    }

    func testFeatureNames() {
        XCTAssertEqual(KitControl.feature(named: "xdr"), .xdr)
        XCTAssertEqual(KitControl.feature(named: "night-shift"), .nightShift)
        XCTAssertEqual(KitControl.feature(named: "NIGHT_SHIFT"), .nightShift)
        XCTAssertEqual(KitControl.feature(named: "autoDisconnectBuiltin"), .autoDisconnectBuiltin)
        XCTAssertNil(KitControl.feature(named: ""))
        XCTAssertNil(KitControl.feature(named: "warp-drive"))
        XCTAssertNil(KitControl.feature(named: String(repeating: "x", count: 200)))
        for feature in DisplayFeature.allCases {
            XCTAssertEqual(KitControl.feature(named: feature.rawValue), feature)
        }
    }

    // MARK: Selectors and values

    func testSelectors() {
        XCTAssertEqual(ControlSelector.parse("main"), .main)
        XCTAssertEqual(ControlSelector.parse("Pointer"), .mouse)
        XCTAssertEqual(ControlSelector.parse("all"), .all)
        XCTAssertEqual(ControlSelector.parse("id:3"), .id(3))
        let key = String(repeating: "ab", count: 16)
        XCTAssertEqual(ControlSelector.parse(key), .key(DisplayKey(rawValue: key)!))
        XCTAssertEqual(ControlSelector.parse("Studio"), .name("Studio"))
        XCTAssertTrue(ControlSelector.parse("stu")!.matchesName("Studio Display"))
        XCTAssertFalse(ControlSelector.parse("dell")!.matchesName("Studio Display"))
        XCTAssertNil(ControlSelector.parse("  "))
        XCTAssertNil(ControlSelector.parse(String(repeating: "x", count: 200)))
    }

    func testValues() throws {
        let range = 0.0...100.0
        XCTAssertEqual(try XCTUnwrap(ControlValue.parse("50")).apply(to: 10, in: range), 50)
        XCTAssertEqual(try XCTUnwrap(ControlValue.parse("+10")).apply(to: 95, in: range), 100)
        XCTAssertEqual(try XCTUnwrap(ControlValue.parse("-10")).apply(to: 5, in: range), 0)
        XCTAssertEqual(try XCTUnwrap(ControlValue.parse("25%")).apply(to: 0, in: 0...1), 0.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ControlValue.parse("+10%")).apply(to: 0.5, in: 0...1), 0.6, accuracy: 1e-9)
        XCTAssertNil(ControlValue.parse("abc"))
        XCTAssertNil(ControlValue.parse("inf"))
        XCTAssertNil(ControlValue.parse("nan"))
        XCTAssertNil(ControlValue.parse(""))
    }

    func testRateWindow() {
        var w = ControlRateWindow(limit: 20, window: 1)
        for i in 0..<20 { XCTAssertTrue(w.allow(now: 10 + Double(i) * 0.01)) }
        XCTAssertFalse(w.allow(now: 10.5))
        XCTAssertTrue(w.allow(now: 11.01))
    }

    func testPathsFitSunPath() {
        XCTAssertTrue(KitControl.isUsableSocketPath(KitControl.socketPath(home: "/Users/someone")))
        XCTAssertFalse(KitControl.isUsableSocketPath(KitControl.socketPath(home: "/Users/" + String(repeating: "n", count: 80))))
        XCTAssertFalse(KitControl.isUsableSocketPath("relative/sock"))
    }

    func testEveryExitCodeIsDescribed() {
        for code in [ControlExit.ok, ControlExit.usage, ControlExit.notFound, ControlExit.refused,
                     ControlExit.unavailable, ControlExit.cancelled] {
            XCTAssertFalse(ControlExit.describe(code).isEmpty)
        }
    }

    // MARK: Client options vs. verb arguments

    func testOnlyClientOptionsBeforeTheVerbAreRead() throws {
        let c = try KitControl.parseCommandLine(["--json", "-y", "pip", "start", "--display", "2"]).get()
        XCTAssertTrue(c.json)
        XCTAssertTrue(c.yes)
        XCTAssertFalse(c.help)
        XCTAssertEqual(c.words, ["pip", "start", "--display", "2"])
        // Client-looking options after the verb belong to the verb: passed through as typed.
        let d = try KitControl.parseCommandLine(["rotate", "main", "90", "--yes", "--json", "-h"]).get()
        XCTAssertFalse(d.yes)
        XCTAssertFalse(d.json)
        XCTAssertFalse(d.help)
        XCTAssertEqual(d.words, ["rotate", "main", "90", "--yes", "--json", "-h"])
        XCTAssertEqual(try KitControl.parseCommandLine(["set", "brightness", "main", "-10"]).get().words,
                       ["set", "brightness", "main", "-10"])
    }

    func testSeparators() throws {
        // `--` before the verb ends the client's options.
        let a = try KitControl.parseCommandLine(["--json", "--", "list"]).get()
        XCTAssertTrue(a.json)
        XCTAssertEqual(a.words, ["list"])
        // The old workaround (`pip start -- --display 2`) still works: one `--` after the verb is dropped.
        XCTAssertEqual(try KitControl.parseCommandLine(["pip", "start", "--", "--display", "2"]).get().words,
                       ["pip", "start", "--display", "2"])
        XCTAssertEqual(try KitControl.parseCommandLine(["run", "--", "--"]).get().words, ["run", "--"])
        XCTAssertTrue(try KitControl.parseCommandLine(["--"]).get().help)
    }

    func testUnknownOptionBeforeTheVerbIsAUsageError() {
        for argv in [["--display", "2", "pip", "start"], ["-d", "pip"], ["--json", "--frobnicate", "list"]] {
            if case .success = KitControl.parseCommandLine(argv) { XCTFail("\(argv)") }
        }
    }

    func testSplitFuzz() {
        var rng = SeededGenerator(seed: 0x5EED_C11)
        let clientOptions: Set<String> = ["--json", "--yes", "-y", "--help", "-h"]
        let pool = ["--json", "--yes", "-y", "--help", "-h", "--", "pip", "start", "--display", "2", "-10", "x"]
        for _ in 0..<2_000 {
            let argv = (0..<Int(rng.next() % 9)).map { _ in pool[Int(rng.next() % UInt64(pool.count))] }
            // Reference model: skip the client's options, then one `--`; the rest is the
            // command as typed, minus one bare `--` after the verb.
            var i = 0
            while i < argv.count, clientOptions.contains(argv[i]) { i += 1 }
            let hadSeparator = i < argv.count && argv[i] == "--"
            if hadSeparator { i += 1 }
            var expected = Array(argv[i...])
            if expected.count > 1, let sep = expected.dropFirst().firstIndex(of: "--") { expected.remove(at: sep) }
            switch KitControl.parseCommandLine(argv) {
            case .success(let c):
                XCTAssertEqual(c.words, expected, "\(argv)")
                XCTAssertEqual(c.json, argv[..<i].contains("--json"), "\(argv)")
                XCTAssertEqual(c.yes, argv[..<i].contains("--yes") || argv[..<i].contains("-y"), "\(argv)")
            case .failure:
                // Only an unknown option before the verb is refused.
                XCTAssertFalse(hadSeparator, "\(argv)")
                XCTAssertTrue(i < argv.count && argv[i].hasPrefix("-") && argv[i] != "--", "\(argv)")
            }
        }
    }

    // MARK: Client timeout (N7)

    func testClientWaitsForTheLongestConfirmationPanel() {
        XCTAssertEqual(KitControl.confirmSeconds, Double(SafetyConfig.confirmSecondsRange.upperBound))
        XCTAssertGreaterThanOrEqual(KitControl.clientTimeoutSeconds, 60 + 30)
        XCTAssertGreaterThanOrEqual(KitControl.clientTimeoutSeconds,
                                    Double(SafetyConfig.confirmSecondsRange.upperBound) + KitControl.applyMarginSeconds)
    }

    // MARK: 0.3 connection holds (§2.10)

    func testResponseHoldingRoundTripsAndOldRepliesDecode() throws {
        let held = ControlResponse.holding("Holding until this command ends (at most 12 h). Press Control-C to stop.")
        XCTAssertTrue(held.holding)
        let line = try XCTUnwrap(KitControl.encode(held))
        XCTAssertEqual(KitControl.decodeResponse(line.dropLast()), held)
        // A 0.2 server's reply has no "holding" key; a reply with a junk value is not a hold.
        let old = try XCTUnwrap(KitControl.decodeResponse(Data(#"{"exitCode":0,"output":"ok"}"#.utf8)))
        XCTAssertEqual(old, .ok("ok"))
        XCTAssertFalse(old.holding)
        XCTAssertEqual(KitControl.decodeResponse(Data(#"{"exitCode":4,"output":"x","holding":"yes"}"#.utf8)),
                       .failure(4, "x"))
        XCTAssertEqual(KitControl.decodeResponse(Data(#"{"exitCode":0}"#.utf8)), .ok(""))
        XCTAssertNil(KitControl.decodeResponse(Data(#"{"output":"no code"}"#.utf8)))
    }

    func testOrdinaryRepliesKeepTheirBytes() throws {
        let line = try XCTUnwrap(KitControl.encode(ControlResponse.ok("hi")))
        XCTAssertEqual(String(decoding: line, as: UTF8.self), "{\"exitCode\":0,\"output\":\"hi\"}\n")
        let held = try XCTUnwrap(KitControl.encode(ControlResponse.holding("h")))
        XCTAssertEqual(String(decoding: held, as: UTF8.self), "{\"exitCode\":0,\"holding\":true,\"output\":\"h\"}\n")
    }

    func testJSONReplyKeepsHolding() throws {
        let wrapped = KitControl.jsonReply(.holding("Holding while process 42 runs."))
        XCTAssertTrue(wrapped.holding)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(wrapped.output.utf8)) as? [String: Any])
        XCTAssertEqual(object["output"] as? String, "Holding while process 42 runs.")
        XCTAssertFalse(KitControl.jsonReply(.ok("x")).holding)
    }

    func testHoldLimitsAndPing() {
        XCTAssertEqual(KitControl.maxHeldConnections, 8)
        XCTAssertEqual(KitControl.holdPingSeconds, 300)
        XCTAssertEqual(KitControl.pingLine.last, 0x0A)
        XCTAssertTrue(KitControl.isPing(KitControl.pingLine.dropLast()))
        XCTAssertTrue(KitControl.isPing(Data(#" { "ping" : true } "#.utf8)))
        for notPing in [#"{"ping":false}"#, #"{"ping":true,"exitCode":0}"#, #"{"exitCode":0,"output":"ping"}"#,
                        "ping", "", #"{"ping":1}"#, "[true]"] {
            XCTAssertFalse(KitControl.isPing(Data(notPing.utf8)), notPing)
        }
        // A reply is never mistaken for a ping, and a ping never decodes as a reply.
        XCTAssertNil(KitControl.decodeResponse(KitControl.pingLine.dropLast()))
    }

    func testProtectedAwakeWords() {
        for word in ["awake", "nudge", "pointernudge", "drivealive", "activity", "guards", "batteryguard", "thermalguard"] {
            XCTAssertTrue(KitControl.protectedSettings.contains(word), word)
        }
        // The 0.2 words went with Displays' sleep prevention (R5-14).
        XCTAssertTrue(KitControl.protectedSettings.isDisjoint(with: ["sleepprevention", "preventsleep"]))
        XCTAssertEqual(KitControl.protectedSetting(verb: "set", arguments: ["pointer-nudge", "on"]), "pointernudge")
        XCTAssertEqual(KitControl.protectedSetting(verb: "feature", arguments: ["enable", "drive_alive"]), "drivealive")
        XCTAssertEqual(KitControl.protectedSetting(verb: "set", arguments: ["awake", "on"]), "awake")
        XCTAssertEqual(KitControl.protectedSetting(verb: "toggle", arguments: ["thermal-guard"]), "thermalguard")
        // `module disable awake` names the module (off-only), not a setting.
        XCTAssertNil(KitControl.protectedSetting(verb: "module disable", arguments: ["awake"]))
        XCTAssertNil(KitControl.protectedSetting(verb: "module", arguments: ["disable", "Awake"]))
        XCTAssertEqual(KitControl.protectedSetting(verb: "module disable", arguments: ["cli"]), "cli")
        XCTAssertNil(KitControl.protectedSetting(verb: "awake", arguments: ["hold"]), "awake verbs aren't setting verbs")
    }

    // MARK: Retired verbs (R5-12)

    func testPreventSleepIsRetiredWithItsPointer() {
        XCTAssertEqual(KitControl.retiredVerbs, ["prevent-sleep": "Moved to Awake: use “snaptic awake …”."])
        for words in [["prevent-sleep"], ["prevent-sleep", "off"], ["PREVENT-SLEEP", "on"], ["Prevent-Sleep", "x", "y"]] {
            let retired = KitControl.retiredVerb(words)
            XCTAssertEqual(retired?.verb, "prevent-sleep", "\(words)")
            XCTAssertEqual(retired?.message, "Moved to Awake: use “snaptic awake …”.")
        }
        for words in [[], ["prevent"], ["prevent", "sleep"], ["prevent-sleeps"], ["awake", "prevent-sleep"], ["help"],
                      ["help", "prevent-sleep"]] {
            XCTAssertNil(KitControl.retiredVerb(words), "\(words)")
        }
        // No retired verb is a live verb word or an Awake verb.
        for verb in KitControl.retiredVerbs.keys {
            XCTAssertTrue(verb.split(separator: " ").allSatisfy { KitControl.isVerbWord(String($0)) }, verb)
            XCTAssertNil(KitControl.verbRule(verb), verb)
        }
        XCTAssertEqual(ControlExit.usage, 2)
    }

    func testLineReaderKeepsBytesAfterTheNewline() {
        var reader = ControlLineReader(maxLineBytes: 100)
        let first = reader.append(Array("{\"a\":1}\n{\"ping\":true}\n{\"b\"".utf8))
        XCTAssertEqual(first.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"ping\":true}"])
        XCTAssertTrue(reader.hasPartialLine)
        XCTAssertEqual(reader.remainder.map { String(decoding: $0, as: UTF8.self) }, "{\"b\"")
        XCTAssertEqual(reader.append(Array(":2}\n".utf8)).map { String(decoding: $0, as: UTF8.self) }, ["{\"b\":2}"])
        XCTAssertNil(reader.remainder)
        XCTAssertEqual(reader.append(Array("\n".utf8)), [Data()], "an empty line is still a line")
    }

    func testLineReaderDropsOverlongLinesOnly() {
        var reader = ControlLineReader(maxLineBytes: 4)
        XCTAssertEqual(reader.append(Array("12345".utf8)), [])
        XCTAssertTrue(reader.overflowed)
        XCTAssertNil(reader.remainder)
        XCTAssertEqual(reader.append(Array("678\nok\n".utf8)), [Data("ok".utf8)])
        XCTAssertFalse(reader.overflowed)
    }

    func testLineReaderFuzzIsChunkingIndependent() {
        var rng = SeededGenerator(seed: 0x11E5)
        for _ in 0..<500 {
            let alphabet: [UInt8] = [0x0A, 0x61, 0x62, 0x7B, 0x7D]
            let stream = (0..<Int(rng.next() % 200)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }
            var whole = ControlLineReader(maxLineBytes: 16)
            let expected = whole.append(stream)
            var chunked = ControlLineReader(maxLineBytes: 16)
            var got: [Data] = []
            var index = 0
            while index < stream.count {
                let n = 1 + Int(rng.next() % 9)
                got += chunked.append(stream[index..<min(stream.count, index + n)])
                index += n
            }
            XCTAssertEqual(got, expected)
            XCTAssertEqual(chunked.remainder, whole.remainder)
            XCTAssertTrue(got.allSatisfy { $0.count <= 16 && !$0.contains(0x0A) })
        }
    }

    func testSlotPoolMovesAHoldExactlyOnce() {
        var pool = ControlSlotPool()
        for _ in 0..<4 { XCTAssertTrue(pool.admit()) }
        XCTAssertFalse(pool.admit(), "a 5th request is busy")
        XCTAssertTrue(pool.promote())
        XCTAssertEqual(pool.active, 3)
        XCTAssertEqual(pool.held, 1)
        XCTAssertTrue(pool.admit(), "a hold frees its request slot")
        pool.release(wasHeld: true)
        XCTAssertEqual(pool.held, 0)
        XCTAssertEqual(pool.active, 4, "the held connection's finish never frees a request slot")
    }

    func testSlotPoolRefusesTheNinthHold() {
        var pool = ControlSlotPool()
        for _ in 0..<8 {
            XCTAssertTrue(pool.admit())
            XCTAssertTrue(pool.promote())
        }
        XCTAssertTrue(pool.admit())
        XCTAssertFalse(pool.promote())
        XCTAssertEqual(pool.held, 8)
        XCTAssertEqual(pool.active, 1)
        pool.release(wasHeld: false)
        XCTAssertEqual(pool, { var p = ControlSlotPool(); for _ in 0..<8 { _ = p.admit(); _ = p.promote() }; return p }())
    }

    func testSlotPoolFuzzKeepsCountsInRange() {
        var rng = SeededGenerator(seed: 0x5107)
        var pool = ControlSlotPool()
        var connections: [Bool] = []   // wasHeld per open connection
        for _ in 0..<20_000 {
            switch rng.next() % 3 {
            case 0:
                if pool.admit() { connections.append(false) }
            case 1:
                if let i = connections.firstIndex(of: false), pool.promote() { connections[i] = true }
            default:
                if !connections.isEmpty {
                    let i = Int(rng.next() % UInt64(connections.count))
                    pool.release(wasHeld: connections.remove(at: i))
                }
            }
            XCTAssertEqual(pool.active, connections.filter { !$0 }.count)
            XCTAssertEqual(pool.held, connections.filter { $0 }.count)
            XCTAssertTrue((0...4).contains(pool.active) && (0...8).contains(pool.held))
        }
    }

    // MARK: Awake verbs (0.3 §2.10, §3.1)

    func testAwakeVerbTable() {
        let rules = KitControl.awakeVerbRules
        XCTAssertEqual(rules.map(\.verb), ["awake status", "awake start", "awake hold", "awake preset", "awake extend",
                                           "awake stop", "awake pause"])
        XCTAssertEqual(Set(rules.map(\.verb)).count, rules.count)
        for rule in rules {
            XCTAssertTrue(rule.verb.split(separator: " ").allSatisfy { KitControl.isVerbWord(String($0)) }, rule.verb)
            XCTAssertLessThanOrEqual(rule.verb.split(separator: " ").count, KitControl.maxVerbWords)
            XCTAssertEqual(KitControl.verbRule(rule.verb), rule)
        }
        XCTAssertEqual(rules.filter(\.holds).map(\.verb), ["awake hold"])
        XCTAssertEqual(Set(rules.filter(\.offOnly).map(\.verb)), ["awake stop", "awake pause"])
        XCTAssertEqual(Set(rules.filter(\.sessionLimited).map(\.verb)),
                       ["awake start", "awake hold", "awake preset", "awake stop", "awake extend"])
        XCTAssertEqual(KitControl.verbRule("awake status")?.policy, .read)
        XCTAssertNil(KitControl.verbRule("awake"))
        XCTAssertNil(KitControl.verbRule("brightness"))
        XCTAssertEqual(KitControl.sessionVerbsPerSecond, 1)
    }

    /// Every documented command line reaches its verb through the client's parsing and the server's matching, is
    /// never mistaken for a protected setting or a turn-on, and parses with the Awake grammar.
    func testAwakeCommandLinesReachTheirVerbs() throws {
        let verbs = KitControl.awakeVerbRules.map(\.verb) + ["version", "modules", "module disable", "list"]
        let lines: [[String]] = [
            ["awake", "status"], ["awake", "status", "--json"], ["--json", "awake", "status"],
            ["awake", "start"], ["awake", "start", "2h"], ["awake", "start", "1h", "30m", "--display-may-sleep"],
            ["awake", "start", "until", "5:30", "pm"], ["awake", "start", "idle"],
            ["awake", "hold"], ["awake", "hold", "--max", "2h"], ["awake", "hold", "--pid", "4242"],
            ["awake", "hold", "--pid", "4242", "--max", "30m"],
            ["awake", "preset", "1"], ["awake", "preset", "Focus", "Time"], ["awake", "extend", "15m"],
            ["awake", "stop"], ["awake", "pause"], ["awake", "pause", "2h"], ["AWAKE", "Hold"],
        ]
        for line in lines {
            let command = try KitControl.parseCommandLine(line).get()
            let match = try XCTUnwrap(KitControl.match(command.words, verbs: verbs), line.joined(separator: " "))
            let rule = try XCTUnwrap(KitControl.verbRule(match.verb))
            XCTAssertNil(KitControl.protectedSetting(verb: match.verb, arguments: match.arguments))
            if rule.offOnly { XCTAssertFalse(KitControl.requestsTurningOn(match.arguments), line.joined(separator: " ")) }
            let word = String(rule.verb.split(separator: " ").last ?? "")
            XCTAssertNotNil(AwakeCommandGrammar.parse(verb: word, args: match.arguments), line.joined(separator: " "))
        }
        XCTAssertEqual(try KitControl.parseCommandLine(["--json", "awake", "status"]).get().json, true)
        // Off-only verbs refuse a turn-on word; a hold without its pid is a usage error.
        XCTAssertTrue(KitControl.requestsTurningOn(["on"]))
        XCTAssertNil(AwakeCommandGrammar.parse(verb: "hold", args: ["--pid"]))
        guard case .hold(let pid, nil)? = AwakeCommandGrammar.parse(verb: "hold", args: ["--pid", "4242"]) else {
            return XCTFail("--pid form")
        }
        XCTAssertEqual(pid, 4242)
        guard case .hold(nil, let cap)? = AwakeCommandGrammar.parse(verb: "hold", args: ["--max", "2h"]) else {
            return XCTFail("connection form")
        }
        XCTAssertEqual(cap, 7_200)
    }
}
