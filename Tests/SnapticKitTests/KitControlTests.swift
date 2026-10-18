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
        XCTAssertEqual(KitControl.protectedSetting(verb: "feature disable", arguments: ["sleep-prevention"]), "sleepprevention")
        XCTAssertEqual(KitControl.protectedSetting(verb: "set", arguments: ["prevent_sleep", "on"]), "preventsleep")
        XCTAssertEqual(KitControl.protectedSetting(verb: "toggle", arguments: ["SleepPrevention"]), "sleepprevention")
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
}
