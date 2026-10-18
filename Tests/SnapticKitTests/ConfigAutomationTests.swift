import XCTest
@testable import SnapticKit

final class ConfigAutomationTests: XCTestCase {
    private let key = DisplayKey(rawValue: String(repeating: "1a", count: 16))!

    private func decode(_ json: String) throws -> AutomationConfig {
        try JSONDecoder().decode(AutomationConfig.self, from: Data(json.utf8))
    }

    func testRoundTrip() throws {
        var c = AutomationConfig()
        c.hooks = [HookSpec(name: "Dock", event: .connect, display: key,
                            command: CommandSpec(executable: "/Users/a/bin/dock.sh", arguments: ["on"]))]
        c.actions = [CustomActionSpec(name: "Dim Office", command: CommandSpec(executable: "/usr/bin/true"),
                                      cliAllowed: true, shortcut: HotkeyCombo(keyCode: 2, carbonModifiers: HotkeyRules.control))]
        let back = try JSONDecoder().decode(AutomationConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }

    func testBadEntriesAreDroppedOneByOne() throws {
        let id1 = StableID().rawValue, id2 = StableID().rawValue
        let json = """
        {"hooks":[{"id":"\(id1)","event":"connect","enabled":true,"command":{"executable":"/bin/echo"}},
                  {"id":"\(id2)","event":"teleport"},
                  {"event":"wake"},
                  7],
         "actions":"nope"}
        """
        let c = try decode(json)
        XCTAssertEqual(c.hooks.map(\.id.rawValue), [id1])
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(try decode("{}"), AutomationConfig())
    }

    func testMissingEnabledMeansOff() throws {
        let c = try decode(#"{"hooks":[{"id":"\#(StableID().rawValue)","event":"sleep"}]}"#)
        XCTAssertEqual(c.hooks.first?.enabled, false)
    }

    func testSanitizeBoundsAndCleans() {
        var c = AutomationConfig()
        let shared = StableID()
        c.hooks = (0..<20).map { i in HookSpec(name: "h\(i)\u{0}", event: .wakeDelayed, display: key, delaySeconds: 5_000) }
        c.hooks.append(HookSpec(id: shared))
        c.actions = [CustomActionSpec(id: shared, name: "dup"),
                     CustomActionSpec(name: "x", command: CommandSpec(executable: "/" + String(repeating: "a", count: 2000),
                                                                       arguments: Array(repeating: "a", count: 12)),
                                      shortcut: HotkeyCombo(keyCode: 0, carbonModifiers: HotkeyRules.option))]
        let s = c.sanitized()
        XCTAssertEqual(s.hooks.count, AutomationConfig.maxHooks)
        XCTAssertEqual(s.hooks[0].delaySeconds, 600)
        XCTAssertNil(s.hooks[0].display)                  // wake isn't per display
        XCTAssertEqual(s.hooks[0].name, "h0")
        XCTAssertEqual(s.actions.count, 1)                 // the duplicate id is dropped
        XCTAssertEqual(s.actions[0].command.executable, "")
        XCTAssertEqual(s.actions[0].command.arguments.count, KitHookPolicy.maxArguments)
        XCTAssertNil(s.actions[0].shortcut)                // ⌥-only isn't allowed
        XCTAssertEqual(s.sanitized(), s)
    }

    func testHooksForEvent() {
        var c = AutomationConfig()
        let other = DisplayKey(rawValue: String(repeating: "2b", count: 16))!
        let program = CommandSpec(executable: "/usr/bin/true")
        c.hooks = [HookSpec(name: "any", event: .connect, command: program),
                   HookSpec(name: "mine", event: .connect, display: key, command: program),
                   HookSpec(name: "off", enabled: false, event: .connect, command: program),
                   HookSpec(name: "no program", event: .connect),
                   HookSpec(name: "wake", event: .wake, command: program)]
        XCTAssertEqual(c.hooks(for: .connect, display: key).map(\.name), ["any", "mine"])
        XCTAssertEqual(c.hooks(for: .connect, display: other).map(\.name), ["any"])
        XCTAssertEqual(c.hooks(for: .wake, display: nil).map(\.name), ["wake"])
    }

    func testCLINames() {
        var c = AutomationConfig()
        c.actions = [CustomActionSpec(name: "Dim Office!"), CustomActionSpec(name: "Reset")]
        XCTAssertEqual(c.actions[0].cliName, "dim-office")
        XCTAssertEqual(c.action(cliName: "DIM-OFFICE")?.name, "Dim Office!")
        XCTAssertNil(c.action(cliName: "nothing"))
    }

    func testEveryEventHasATitle() {
        for e in HookEvent.allCases { XCTAssertFalse(e.title.isEmpty) }
        XCTAssertEqual(Set(HookEvent.allCases.map(\.title)).count, HookEvent.allCases.count)
        XCTAssertNotNil(HookEvent.softConnect.help)
        XCTAssertNil(HookEvent.connect.help)
    }

    func testSummaries() {
        XCTAssertEqual(HookSpec(event: .connect).summary(displayName: nil), "When a display connects")
        // A name without a chosen display is ignored: the hook watches every display.
        XCTAssertEqual(HookSpec(event: .disconnect).summary(displayName: "Studio"), "When a display disconnects")
        XCTAssertEqual(HookSpec(event: .softConnect, display: key).summary(displayName: "DELL U2720Q"),
                       "When “DELL U2720Q” turns on")
        XCTAssertEqual(HookSpec(event: .softDisconnect, display: key).summary(displayName: nil),
                       "When a display turns off")
        XCTAssertEqual(HookSpec(event: .softDisconnect, display: key).summary(displayName: ""),
                       "When a display turns off")
        XCTAssertEqual(HookSpec(event: .sleep, display: key).summary(displayName: "x"), "When your Mac goes to sleep")
        XCTAssertEqual(HookSpec(event: .wake).summary(displayName: nil), "When your Mac wakes")
        XCTAssertEqual(HookSpec(event: .wakeDelayed, delaySeconds: 10).summary(displayName: nil),
                       "When your Mac wakes, after 10 s")
        XCTAssertEqual(HookSpec(event: .wakeDelayed, delaySeconds: 90).summary(displayName: nil),
                       "When your Mac wakes, after 1 min 30 s")
        // The summary shows what runs: the clamped delay.
        XCTAssertEqual(HookSpec(event: .wakeDelayed, delaySeconds: 5_000).summary(displayName: nil),
                       "When your Mac wakes, after 10 min")
        XCTAssertEqual(HookSpec(event: .wakeDelayed, delaySeconds: .nan).summary(displayName: nil),
                       "When your Mac wakes, after 10 s")
        // Control characters in a display name never reach the label.
        XCTAssertEqual(HookSpec(event: .connect, display: key).summary(displayName: "A\u{202E}B\n"), "When “AB” connects")
    }

    func testDurationText() {
        XCTAssertEqual(HookSpec.durationText(0), "0 s")
        XCTAssertEqual(HookSpec.durationText(59.6), "1 min")
        XCTAssertEqual(HookSpec.durationText(61), "1 min 1 s")
        XCTAssertEqual(HookSpec.durationText(600), "10 min")
        XCTAssertEqual(HookSpec.durationText(-3), "0 s")
        XCTAssertEqual(HookSpec.durationText(.infinity), "0 s")
    }

    func testProgramNames() {
        XCTAssertEqual(CommandSpec().programName, "")
        XCTAssertEqual(CommandSpec(executable: "/Users/a/bin/dock.sh").programName, "dock.sh")
        XCTAssertEqual(CommandSpec(executable: "/Applications/Tool.app/").programName, "Tool.app")
        XCTAssertEqual(CommandSpec(executable: "relative").programName, "relative")
        XCTAssertFalse(HookSpec().hasProgram)
        XCTAssertTrue(HookSpec(command: CommandSpec(executable: "/bin/echo")).hasProgram)
    }
}
