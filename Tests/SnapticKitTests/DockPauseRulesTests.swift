import XCTest
@testable import SnapticKit

/// 0.5 A6b: `DockPauseRules` (§4.13, §4.15, §4.16, §4.21, §4.22; M22, M33, M49).
final class DockPauseRulesTests: XCTestCase {
    private let dockDoor = "com.ethanbills.DockDoor"
    private let command = DockCommandPause(untilUnix: 1_800_000_000, clock: "3:45 PM")

    // MARK: The pause

    func testEachSourcePausesAlone() {
        XCTAssertNil(DockPauseRules.effective(DockPageFacts()))
        XCTAssertEqual(DockPauseRules.effective(DockPageFacts(safeMode: true)), .safeMode)
        XCTAssertEqual(DockPauseRules.effective(DockPageFacts(runningBundleIDs: [dockDoor])), .otherTool)
        XCTAssertEqual(DockPauseRules.effective(DockPageFacts(voiceOverOn: true)), .voiceOver)
        XCTAssertEqual(DockPauseRules.effective(DockPageFacts(commandPause: command)), .command)
    }

    func testPausesWinInSafeModeOtherToolVoiceOverCommandOrder() {
        let all = DockPageFacts(safeMode: true, runningBundleIDs: [dockDoor], voiceOverOn: true, commandPause: command)
        XCTAssertEqual(DockPauseRules.effective(all), .safeMode)
        var f = all
        f.safeMode = false
        XCTAssertEqual(DockPauseRules.effective(f), .otherTool)
        f.runningBundleIDs = []
        XCTAssertEqual(DockPauseRules.effective(f), .voiceOver)
        f.voiceOverOn = false
        XCTAssertEqual(DockPauseRules.effective(f), .command)
        f.commandPause = nil
        XCTAssertNil(DockPauseRules.effective(f))
    }

    func testRunAlongsideAndShowWithVoiceOverLiftTheirPauses() {
        // M22: paused by default; the setting lifts it.
        XCTAssertNil(DockPauseRules.effective(DockPageFacts(runningBundleIDs: [dockDoor], runAlongsideOtherTools: true)))
        XCTAssertNil(DockPauseRules.effective(DockPageFacts(voiceOverOn: true, showWithVoiceOver: true)))
        XCTAssertNil(DockPauseRules.effective(DockPageFacts(showWithVoiceOver: false)))
    }

    func testEveryKnownToolPausesAndNoOtherAppDoes() {
        for tool in KnownDockTools.all {
            XCTAssertEqual(DockPauseRules.effective(DockPageFacts(runningBundleIDs: [tool.bundleID])), .otherTool)
        }
        for id in ["com.ethanbills.dockdoor", "com.ethanbills.DockDoor.helper", "com.apple.dock", ""] {
            XCTAssertNil(DockPauseRules.effective(DockPageFacts(runningBundleIDs: [id])), id)
        }
    }

    func testThePauseDoesNotWaitForADockRead() {
        // Rows 4, 5 and Starting win the page; the pause holds anyway, so nothing shows when the read arrives.
        for read in DockReadState.allCases {
            let f = DockPageFacts(read: read, loginLadderEnded: false, runningBundleIDs: [dockDoor])
            XCTAssertEqual(DockPauseRules.effective(f), .otherTool, read.rawValue)
        }
        XCTAssertEqual(DockPauseRules.effective(DockPageFacts(accessibility: false, voiceOverOn: true)), .voiceOver)
    }

    func testOnlyVoiceOverKeepsTheEngineAndOnlyWhileClicksWork() {
        XCTAssertTrue(DockPauseRules.engineRuns(pause: nil, clicksWork: false))
        XCTAssertTrue(DockPauseRules.engineRuns(pause: nil, clicksWork: true))
        XCTAssertTrue(DockPauseRules.engineRuns(pause: .voiceOver, clicksWork: true))
        XCTAssertFalse(DockPauseRules.engineRuns(pause: .voiceOver, clicksWork: false))
        for reason in [DockPauseReason.safeMode, .otherTool, .command] {
            XCTAssertFalse(DockPauseRules.engineRuns(pause: reason, clicksWork: true), reason.rawValue)
            XCTAssertFalse(DockPauseRules.engineRuns(pause: reason, clicksWork: false), reason.rawValue)
        }
    }

    func testNoObserverReadsAsAttachedSoThePauseRowShows() {
        let read = DockPauseRules.read(nil)
        XCTAssertEqual(read.read, .attached)
        XCTAssertTrue(read.ladderEnded)
        XCTAssertNil(read.unreadableSince)
        let f = DockPageFacts(read: read.read, loginLadderEnded: read.ladderEnded, commandPause: command)
        XCTAssertEqual(DockPageRules.row(f), .pausedByCommand)

        let stats = DockObserverStats()
        let live = DockPauseRules.read(stats)
        XCTAssertEqual(live.read, stats.read)
        XCTAssertEqual(live.ladderEnded, stats.ladderEnded)
    }

    // MARK: EventLog and diagnostics (§4.22)

    func testEventLinesCarryTheEnumOnly() {
        XCTAssertNil(DockPauseRules.eventLine(from: nil, to: nil))
        XCTAssertNil(DockPauseRules.eventLine(from: .otherTool, to: .otherTool))
        XCTAssertEqual(DockPauseRules.eventLine(from: nil, to: .otherTool), "dock.paused reason=otherTool")
        XCTAssertEqual(DockPauseRules.eventLine(from: .command, to: .voiceOver), "dock.paused reason=voiceOver")
        XCTAssertEqual(DockPauseRules.eventLine(from: .command, to: nil), "dock.resumed")
        for reason in DockPauseReason.allCases {
            let line = DockPauseRules.eventLine(from: nil, to: reason) ?? ""
            XCTAssertFalse(KnownDockTools.all.contains { line.contains($0.name) || line.contains($0.bundleID) })
        }
    }

    func testPauseLine() {
        XCTAssertEqual(DockPauseRules.pauseLine(nil), "Pause reason: none")
        XCTAssertEqual(DockPauseRules.pauseLine(.safeMode), "Pause reason: safeMode")
        XCTAssertEqual(DockPauseRules.pauseLine(.otherTool), "Pause reason: otherTool")
    }

    private func reports(_ state: WindowSymbolState = .available) -> [WindowSymbolReport] {
        WindowSymbolID.allCases.map { WindowSymbolReport(name: $0.rawValue, state: state) }
    }

    private func allProbed(_ build: String) -> [WindowSymbolID: String] {
        Dictionary(uniqueKeysWithValues: WindowSymbolID.allCases.map { ($0, build) })
    }

    func testSymbolLinesOnePerSymbolInTableOrder() {
        let lines = DockPauseRules.symbolLines(reports(), probedBuilds: allProbed("25A1"), currentBuild: "25A1",
                                               safeMode: false)
        XCTAssertEqual(lines, WindowSymbolID.allCases.map { $0.rawValue + ": available" })
    }

    func testSafeModeReadsOnTheCaptureSymbolOnly() {
        // M33: `hwCapture: safeMode`.
        let lines = DockPauseRules.symbolLines(reports(), probedBuilds: allProbed("25A1"), currentBuild: "25A1",
                                               safeMode: true)
        XCTAssertEqual(lines.first, "hwCapture: safeMode")
        XCTAssertEqual(Array(lines.dropFirst()), WindowSymbolID.allCases.dropFirst().map { $0.rawValue + ": available" })
        let unavailable = DockPauseRules.symbolLines(reports(.unavailable), probedBuilds: [:], currentBuild: "25A1",
                                                     safeMode: true)
        XCTAssertEqual(unavailable.first, "hwCapture: safeMode")
    }

    func testAnAvailableSymbolWithoutAPassOnThisBuildIsNotProbed() {
        let lines = DockPauseRules.symbolLines(reports(), probedBuilds: [.hwCapture: "24G1"], currentBuild: "25A1",
                                               safeMode: false)
        for (id, line) in zip(WindowSymbolID.allCases, lines) {
            let expected = id.presenceOnlyProbe ? "available" : "notProbed"
            XCTAssertEqual(line, id.rawValue + ": " + expected)
        }
        // An unknown build never counts as a pass.
        let empty = DockPauseRules.symbolLines(reports(), probedBuilds: allProbed(""), currentBuild: "",
                                               safeMode: false)
        XCTAssertEqual(empty.first, "hwCapture: notProbed")
    }

    func testOtherStatesAndImageMoved() {
        var list = reports(.disabled)
        list[1].state = .poisoned
        list[2].state = .unavailable
        list[3].imageMoved = true
        let lines = DockPauseRules.symbolLines(list, probedBuilds: [:], currentBuild: "25A1", safeMode: false)
        let ids = WindowSymbolID.allCases
        XCTAssertEqual(lines[0], ids[0].rawValue + ": disabled")
        XCTAssertEqual(lines[1], ids[1].rawValue + ": poisoned")
        XCTAssertEqual(lines[2], ids[2].rawValue + ": unavailable")
        XCTAssertEqual(lines[3], ids[3].rawValue + ": disabled, imageMoved")
        XCTAssertEqual(lines.count, ids.count)
    }

    func testSymbolLinesParseAsDiagnosticsRows() {
        let lines = DockPauseRules.symbolLines(reports(), probedBuilds: [:], currentBuild: "25A1", safeMode: true)
        let row = HostReport.row(lines[0])
        XCTAssertEqual(row?.label, "hwCapture")
        XCTAssertEqual(row?.value, "safeMode")
    }

    // MARK: `dock status` (§4.21)

    func testFeaturePrecedence() {
        XCTAssertEqual(DockPauseRules.feature(on: true, killed: true, stopped: true, paused: true), .disabled)
        XCTAssertEqual(DockPauseRules.feature(on: false, killed: false, stopped: true, paused: true), .off)
        XCTAssertEqual(DockPauseRules.feature(on: true, killed: false, stopped: true, paused: true), .stopped)
        XCTAssertEqual(DockPauseRules.feature(on: true, killed: false, stopped: false, paused: true), .paused)
        XCTAssertEqual(DockPauseRules.feature(on: true, killed: false, stopped: false, paused: false), .on)
    }

    func testThumbnails() {
        XCTAssertEqual(DockPauseRules.thumbnails(on: false, screenRecording: true), .off)
        XCTAssertEqual(DockPauseRules.thumbnails(on: false, screenRecording: false), .off)
        XCTAssertEqual(DockPauseRules.thumbnails(on: true, screenRecording: false), .noPermission)
        XCTAssertEqual(DockPauseRules.thumbnails(on: true, screenRecording: true), .on)
    }

    private func status(_ f: DockPageFacts, keysOn: Bool = true,
                        killed: Set<DockFeature> = []) -> DockStatusFacts? {
        DockPauseRules.status(f, keysOn: keysOn, killed: killed, cacheEntries: 3, cacheBytes: 4_096,
                              observerAttached: false, live: DockStatusLiveCounts())
    }

    func testOtherToolStatus() {
        // A6b's done-when: with DockDoor running, `dock status` reports otherTool.
        let s = status(DockPageFacts(runningBundleIDs: [dockDoor], clickActionOn: true, thumbnailsOn: true))
        XCTAssertEqual(s?.state, .paused)
        XCTAssertEqual(s?.reason, .otherTool)
        XCTAssertEqual(s?.clickActions, .paused)
        XCTAssertEqual(s?.keys, .paused)
        XCTAssertEqual(s?.thumbnails, .on)
        XCTAssertNil(s?.pausedUntil)
        XCTAssertEqual(s?.cacheEntries, 3)
        XCTAssertEqual(s?.cacheBytes, 4_096)
        let line = DockCommandGrammar.statusLine(s ?? DockStatusFacts(state: .on))
        XCTAssertTrue(line.contains("reason=otherTool"), line)
        XCTAssertFalse(line.contains("DockDoor") || line.contains(dockDoor), line)
        XCTAssertFalse(DockCommandGrammar.statusJSON(s ?? DockStatusFacts(state: .on)).contains(dockDoor))
    }

    func testVoiceOverPausesKeysButNotClicks() {
        let s = status(DockPageFacts(voiceOverOn: true, restoreAllOn: true))
        XCTAssertEqual(s?.state, .paused)
        XCTAssertEqual(s?.reason, .voiceOver)
        XCTAssertEqual(s?.clickActions, .on)
        XCTAssertEqual(s?.keys, .paused)
    }

    func testCommandPauseCarriesItsEnd() {
        let s = status(DockPageFacts(commandPause: command))
        XCTAssertEqual(s?.reason, .command)
        XCTAssertEqual(s?.pausedUntil, command.untilUnix)
        XCTAssertEqual(s?.clickActions, .off)
        // A command pause behind another tool still reports its end.
        let behind = status(DockPageFacts(runningBundleIDs: [dockDoor], commandPause: command))
        XCTAssertEqual(behind?.reason, .otherTool)
        XCTAssertEqual(behind?.pausedUntil, command.untilUnix)
    }

    func testKillSwitchesAndSettingsBeatThePause() {
        let s = status(DockPageFacts(runningBundleIDs: [dockDoor], clickActionOn: true), keysOn: false,
                       killed: [.clickActions])
        XCTAssertEqual(s?.clickActions, .disabled)
        XCTAssertEqual(s?.keys, .off)
        let breakers = DockPauseRules.status(DockPageFacts(clickActionOn: true), keysOn: true, killed: [],
                                             clickBreakerTripped: true, keysBreakerTripped: true, cacheEntries: 0,
                                             cacheBytes: 0, observerAttached: true, live: DockStatusLiveCounts())
        XCTAssertEqual(breakers?.clickActions, .stopped)
        XCTAssertEqual(breakers?.keys, .stopped)
        XCTAssertEqual(breakers?.state, .on)
    }

    func testWorkingAndSafeModeAndRowsOneAndTwo() {
        let working = status(DockPageFacts(clickActionOn: true))
        XCTAssertEqual(working?.state, .on)
        XCTAssertNil(working?.reason)
        XCTAssertEqual(working?.clickActions, .on)
        XCTAssertEqual(working?.keys, .on)
        let safe = status(DockPageFacts(safeMode: true))
        XCTAssertEqual(safe?.state, .paused)
        XCTAssertEqual(safe?.reason, .safeMode)
        XCTAssertNil(status(DockPageFacts(killSwitch: true)))
        XCTAssertNil(status(DockPageFacts(enabled: false)))
    }
}
