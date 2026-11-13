import XCTest
@testable import SnapticKit

/// 0.5 K3: `DockPageRules` (§4.17, §4.19, §4.21; G2-2, G2-5, G2-6, G2-9, G3-1, X2-16).
final class DockPageRulesTests: XCTestCase {
    private let dockDoor = "com.ethanbills.DockDoor"
    private let hyperDock = "de.bahoom.HyperDock"
    private let pause = DockCommandPause(untilUnix: 1_800_000_000, clock: "3:45 PM")

    /// Facts where exactly one row applies, keyed by the row.
    private func only(_ row: DockPageRow) -> DockPageFacts {
        switch row {
        case .killSwitch: DockPageFacts(killSwitch: true)
        case .off: DockPageFacts(enabled: false)
        case .safeMode: DockPageFacts(safeMode: true)
        case .needsPermission: DockPageFacts(accessibility: false)
        case .starting: DockPageFacts(read: .starting)
        case .dockUnreadable: DockPageFacts(read: .unreadable)
        case .otherTool: DockPageFacts(runningBundleIDs: [dockDoor])
        case .voiceOver: DockPageFacts(voiceOverOn: true)
        case .pausedByCommand: DockPageFacts(commandPause: pause)
        case .working: DockPageFacts()
        }
    }

    /// Facts where every row from `row` down applies.
    private func from(_ row: DockPageRow) -> DockPageFacts {
        let rows = DockPageRow.allCases
        let start = rows.firstIndex(of: row) ?? 0
        var f = DockPageFacts()
        for r in rows[start...] {
            switch r {
            case .killSwitch: f.killSwitch = true
            case .off: f.enabled = false
            case .safeMode: f.safeMode = true
            case .needsPermission: f.accessibility = false
            case .starting: f.read = .starting
            case .dockUnreadable: if row == .dockUnreadable { f.read = .unreadable }
            case .otherTool: f.runningBundleIDs = [dockDoor]
            case .voiceOver: f.voiceOverOn = true
            case .pausedByCommand: f.commandPause = pause
            case .working: break
            }
        }
        return f
    }

    // MARK: Rows

    /// The 9 rows of §4.17 plus Starting, each alone.
    func testEachRowAlone() {
        XCTAssertEqual(DockPageRow.allCases.count, 10)
        for row in DockPageRow.allCases {
            XCTAssertEqual(DockPageRules.row(only(row)), row, "\(row)")
        }
    }

    /// The first applying row wins: with every row from r down holding, r shows.
    func testTheFirstApplyingRowWins() {
        for row in DockPageRow.allCases {
            XCTAssertEqual(DockPageRules.row(from(row)), row, "\(row)")
        }
    }

    func testRows1And2() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(killSwitch: true, enabled: false)), .killSwitch)
    }

    func testRows2And3() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(enabled: false, safeMode: true)), .off)
    }

    func testRows3And4() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(safeMode: true, accessibility: false)), .safeMode)
    }

    func testRow4AndStarting() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(accessibility: false, read: .starting)), .needsPermission)
    }

    /// An unreadable Dock is Starting while the login ladder runs, and row 5 once it ends.
    func testStartingAndRow5() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(read: .unreadable, loginLadderEnded: false)), .starting)
        XCTAssertEqual(DockPageRules.row(DockPageFacts(read: .unreadable, loginLadderEnded: true)), .dockUnreadable)
        XCTAssertEqual(DockPageRules.row(DockPageFacts(read: .starting, runningBundleIDs: [dockDoor])), .starting)
    }

    func testRows5And6() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(read: .unreadable, runningBundleIDs: [dockDoor])),
                       .dockUnreadable)
    }

    func testRows6And7() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(runningBundleIDs: [dockDoor], voiceOverOn: true)), .otherTool)
    }

    func testRows7And8() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(voiceOverOn: true, commandPause: pause)), .voiceOver)
    }

    func testRows8And9() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(commandPause: pause)), .pausedByCommand)
        XCTAssertEqual(DockPageRules.row(DockPageFacts()), .working)
    }

    /// Row 6 names the first running known tool in `KnownDockTools` order; Run Both and unknown apps don't count.
    func testOtherToolRow() {
        XCTAssertEqual(DockPageRules.otherTool(DockPageFacts(runningBundleIDs: [hyperDock, dockDoor]))?.name,
                       "DockDoor")
        XCTAssertNil(DockPageRules.otherTool(DockPageFacts(runningBundleIDs: ["com.example.Other"])))
        let both = DockPageFacts(runningBundleIDs: [dockDoor], runAlongsideOtherTools: true)
        XCTAssertNil(DockPageRules.otherTool(both))
        XCTAssertEqual(DockPageRules.row(both), .working)
    }

    /// Row 7 holds only while “Show previews with VoiceOver” is off (G2-5).
    func testVoiceOverRow() {
        XCTAssertEqual(DockPageRules.row(DockPageFacts(voiceOverOn: true, showWithVoiceOver: true)), .working)
        XCTAssertFalse(DockPageRules.voiceOverPauses(DockPageFacts(voiceOverOn: false)))
    }

    // MARK: Pause

    /// Safe Mode, then another tool, then VoiceOver, then the command (§4.17).
    func testPausePrecedence() {
        XCTAssertEqual(DockPauseReason.winning(safeMode: true, otherTool: true, voiceOver: true, command: true), .safeMode)
        XCTAssertEqual(DockPauseReason.winning(safeMode: false, otherTool: true, voiceOver: true, command: true), .otherTool)
        XCTAssertEqual(DockPauseReason.winning(safeMode: false, otherTool: false, voiceOver: true, command: true), .voiceOver)
        XCTAssertEqual(DockPauseReason.winning(safeMode: false, otherTool: false, voiceOver: false, command: true), .command)
        XCTAssertNil(DockPauseReason.winning(safeMode: false, otherTool: false, voiceOver: false, command: false))

        XCTAssertEqual(DockPageRules.pause(from(.safeMode)), .safeMode)
        XCTAssertEqual(DockPageRules.pause(DockPageFacts(runningBundleIDs: [dockDoor], voiceOverOn: true,
                                                         commandPause: pause)), .otherTool)
        XCTAssertEqual(DockPageRules.pause(DockPageFacts(voiceOverOn: true, commandPause: pause)), .voiceOver)
        XCTAssertEqual(DockPageRules.pause(only(.pausedByCommand)), .command)
        for row in [DockPageRow.killSwitch, .off, .needsPermission, .starting, .dockUnreadable, .working] {
            XCTAssertNil(DockPageRules.pause(only(row)), "\(row)")
        }
    }

    // MARK: Status row

    func testStatusTexts() {
        XCTAssertNil(DockPageRules.status(only(.killSwitch)).text)
        XCTAssertNil(DockPageRules.status(only(.off)).text)
        XCTAssertNil(DockPageRules.status(only(.working)).text)
        XCTAssertEqual(DockPageRules.status(only(.starting)).text, "Starting…")
        XCTAssertEqual(DockPageRules.status(only(.safeMode)).text, "Paused in Safe Mode")

        let permission = DockPageRules.status(only(.needsPermission))
        XCTAssertEqual(permission.text, "Dock Previews needs Accessibility to read the Dock.")
        XCTAssertTrue(permission.warning)
        XCTAssertEqual(permission.action, .openPrivacy)

        let unreadable = DockPageRules.status(only(.dockUnreadable))
        XCTAssertEqual(unreadable.text, "Dock Previews can’t read the Dock. It tries again when the Dock restarts.")
        XCTAssertTrue(unreadable.warning)
        XCTAssertEqual(unreadable.action, .tryAgain)

        let tool = DockPageRules.status(only(.otherTool))
        XCTAssertEqual(tool.text, "Paused while DockDoor runs")
        XCTAssertEqual(tool.action, .advancedOtherTools)

        let voiceOver = DockPageRules.status(only(.voiceOver))
        XCTAssertEqual(voiceOver.text, "Paused while VoiceOver is on")
        XCTAssertEqual(voiceOver.action, .advancedVoiceOver)
        for f in [DockPageFacts(voiceOverOn: true, clickActionOn: true), DockPageFacts(voiceOverOn: true, restoreAllOn: true)] {
            XCTAssertEqual(DockPageRules.status(f).text,
                           "Previews are paused while VoiceOver is on. Dock click actions still work.")
        }

        let paused = DockPageRules.status(only(.pausedByCommand))
        XCTAssertEqual(paused.text, "Paused until 3:45 PM")
        XCTAssertEqual(paused.action, .resume)
        XCTAssertEqual(paused.notes, [])
    }

    /// The added rows, in §4.17's order, under any row but 1 and 2.
    func testAddedRows() {
        let f = DockPageFacts(thumbnailsOn: true, screenRecording: false, clickBreakerTripped: true,
                              keysBreakerTripped: true, crashGuardStops: ["Window thumbnails"],
                              poisoned: ["Dock click actions"])
        let notes = DockPageRules.status(f).notes
        XCTAssertEqual(notes.map(\.action), [.openPrivacy, .relaunch, .relaunch, .tryAgain, nil])
        XCTAssertEqual(notes.map(\.text), [
            "Window thumbnails need Screen Recording. Until then, previews show window titles.",
            "Dock click actions stopped because macOS turned them off 3 times. Relaunch Snaptic to use them again.",
            "Keyboard shortcuts in previews stopped because macOS turned them off 3 times. Relaunch Snaptic to use them again.",
            "Window thumbnails stopped after a problem in macOS. Snaptic tries again after a macOS update.",
            "Dock click actions stopped because macOS answered in a way Snaptic didn’t expect. Quit and reopen Snaptic to try again.",
        ])
        XCTAssertTrue(notes.allSatisfy(\.warning))
        // Thumbnails off, or Screen Recording granted: no row.
        XCTAssertEqual(DockPageRules.status(DockPageFacts(thumbnailsOn: false, screenRecording: false)).notes, [])
        XCTAssertEqual(DockPageRules.status(DockPageFacts(thumbnailsOn: true, screenRecording: true)).notes, [])
        // Rows 1 and 2 show no added rows.
        var off = f
        off.enabled = false
        XCTAssertEqual(DockPageRules.status(off).notes, [])
        off.killSwitch = true
        XCTAssertEqual(DockPageRules.status(off).notes, [])
    }

    /// A held command pause adds its row under Starting, row 4 and row 5, where row 8 can't show (G3-1).
    func testAHeldPauseAddsItsRow() {
        for row in [DockPageRow.starting, .needsPermission, .dockUnreadable] {
            var f = only(row)
            f.commandPause = pause
            XCTAssertEqual(DockPageRules.row(f), row)
            XCTAssertTrue(DockPageRules.heldPauseUnder(f), "\(row)")
            let status = DockPageRules.status(f)
            XCTAssertEqual(status.notes.last, DockPageNote("Paused until 3:45 PM", warning: false, action: .resume))
            let menu = DockPageRules.menu(f)
            XCTAssertTrue(menu.contains(.status("Paused until 3:45 PM")), "\(row)")
            XCTAssertTrue(menu.contains(.resume), "\(row)")
            XCTAssertFalse(menu.contains(.pauseForOneHour), "\(row)")
            XCTAssertEqual(DockPageRules.cli(f)?.until, AwakeCommandGrammar.isoUTC(1_800_000_000))
        }
        // Under rows 3, 6 and 7 the pause is held but doesn't add a row; row 8 is the pause itself.
        for row in [DockPageRow.safeMode, .otherTool, .voiceOver, .pausedByCommand] {
            var f = only(row)
            f.commandPause = pause
            XCTAssertFalse(DockPageRules.heldPauseUnder(f), "\(row)")
            XCTAssertEqual(DockPageRules.status(f).notes, [], "\(row)")
        }
    }

    // MARK: Menu

    func testMenu() {
        XCTAssertEqual(DockPageRules.menu(only(.killSwitch)), [])
        XCTAssertEqual(DockPageRules.menu(only(.off)), [])
        XCTAssertEqual(DockPageRules.menu(only(.working)), [.pauseForOneHour, .settings])
        XCTAssertEqual(DockPageRules.menu(only(.starting)), [.settings])
        XCTAssertEqual(DockPageRules.menu(only(.safeMode)), [.status("Paused in Safe Mode"), .settings])
        XCTAssertEqual(DockPageRules.menu(only(.needsPermission)),
                       [.status("Needs Permission"), .openPane("Accessibility"), .settings])
        XCTAssertEqual(DockPageRules.menu(only(.dockUnreadable)), [.status("Can’t read the Dock"), .settings])
        XCTAssertEqual(DockPageRules.menu(only(.otherTool)), [.status("Paused while DockDoor runs"), .settings])
        XCTAssertEqual(DockPageRules.menu(only(.voiceOver)), [.status("Paused while VoiceOver is on"), .settings])
        XCTAssertEqual(DockPageRules.menu(only(.pausedByCommand)), [.status("Paused until 3:45 PM"), .resume, .settings])

        var held = only(.needsPermission)
        held.commandPause = pause
        XCTAssertEqual(DockPageRules.menu(held), [.status("Needs Permission"), .status("Paused until 3:45 PM"),
                                                  .openPane("Accessibility"), .resume, .settings])
        XCTAssertEqual(DockMenuItem.openPane("Accessibility").title, "Open Accessibility Settings…")
        XCTAssertEqual(DockMenuItem.pauseForOneHour.title, "Pause Dock Previews for 1 Hour")
    }

    // MARK: CLI

    func testCLI() {
        XCTAssertNil(DockPageRules.cli(only(.killSwitch)))
        XCTAssertNil(DockPageRules.cli(only(.off)))
        XCTAssertEqual(DockPageRules.cli(only(.starting)), DockCLIStatus(state: .starting))
        XCTAssertEqual(DockPageRules.cli(only(.safeMode)), DockCLIStatus(state: .paused, reason: .safeMode))
        XCTAssertEqual(DockPageRules.cli(only(.needsPermission)), DockCLIStatus(state: .needsPermission))
        XCTAssertEqual(DockPageRules.cli(only(.dockUnreadable)),
                       DockCLIStatus(state: .unavailable, reason: .dockUnreadable))
        XCTAssertEqual(DockPageRules.cli(only(.otherTool)), DockCLIStatus(state: .paused, reason: .otherTool))
        XCTAssertEqual(DockPageRules.cli(only(.voiceOver)), DockCLIStatus(state: .paused, reason: .voiceOver))
        XCTAssertEqual(DockPageRules.cli(only(.pausedByCommand)),
                       DockCLIStatus(state: .paused, reason: .command, until: AwakeCommandGrammar.isoUTC(1_800_000_000)))
        XCTAssertEqual(DockPageRules.cli(only(.working)), DockCLIStatus(state: .on))
        XCTAssertEqual(AwakeCommandGrammar.isoUTC(1_800_000_000), "2027-01-15T08:00:00Z")
        // A pause held under Safe Mode keeps Safe Mode's reason and adds `until`.
        var f = only(.safeMode)
        f.commandPause = pause
        XCTAssertEqual(DockPageRules.cli(f), DockCLIStatus(state: .paused, reason: .safeMode,
                                                           until: "2027-01-15T08:00:00Z"))
    }

    // MARK: Attention

    func testAttention() {
        XCTAssertTrue(DockPageRules.attention(only(.needsPermission)))
        XCTAssertFalse(DockPageRules.attention(DockPageFacts(read: .unreadable, unreadableSince: 10, now: 129.9)))
        XCTAssertTrue(DockPageRules.attention(DockPageFacts(read: .unreadable, unreadableSince: 10, now: 130)))
        XCTAssertFalse(DockPageRules.attention(only(.dockUnreadable)))
        XCTAssertFalse(DockPageRules.attention(only(.working)))
        XCTAssertTrue(DockPageRules.attention(DockPageFacts(clickBreakerTripped: true)))
        XCTAssertTrue(DockPageRules.attention(DockPageFacts(keysBreakerTripped: true)))
        XCTAssertFalse(DockPageRules.attention(DockPageFacts(enabled: false, clickBreakerTripped: true)))
        XCTAssertFalse(DockPageRules.attention(DockPageFacts(killSwitch: true, accessibility: false)))
        for row in [DockPageRow.safeMode, .starting, .otherTool, .voiceOver, .pausedByCommand] {
            XCTAssertFalse(DockPageRules.attention(only(row)), "\(row)")
        }
    }
}
