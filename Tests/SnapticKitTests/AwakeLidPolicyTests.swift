import XCTest
@testable import SnapticKit

// Lid-closed mode's rules (owner: T-lid-kit; PLAN 0.3.1 B2, B3.0–B3.4, B5).

final class AwakeLidPolicyTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"
    private let boot = "BOOT-1"

    private func now(_ continuous: Double) -> ClockNow {
        ClockNow(wall: 1_700_000_000 + continuous, continuous: continuous, bootSession: boot)
    }

    private func journal(boot: String? = nil, at: Double = 1_000, pid: Int32? = 4_242, floor: Int = 20,
                         token: String? = nil) -> AwakeLidJournal {
        AwakeLidJournal(token: token ?? self.token, bootSessionUUID: boot ?? self.boot, startedAtWall: 1_700_001_000,
                        startedAtContinuous: at, pid: pid, instanceID: 77, floor: floor)
    }

    // MARK: Mode

    func testModeProperties() {
        let modes: [AwakeLidMode] = [.off, .authorizing(token: token), .verifying(token: token, pid: 5),
                                     .on(token: token, pid: 5, until: 9), .stopping(token: token), .failed(.verify)]
        XCTAssertEqual(modes.map(\.isOn), [false, false, false, true, false, false])
        XCTAssertEqual(modes.map(\.isPending), [false, true, true, false, true, false])
        XCTAssertEqual(modes.map(\.token), [nil, token, token, token, token, nil])
        XCTAssertEqual(modes.map(\.rowState), [.off, .authorizing, .verifying, .on, .stopping, .off])
        XCTAssertEqual(AwakeLidEnd.allCases.count, 12)
        XCTAssertEqual(AwakeLidFailStage.allCases.map(\.rawValue), ["beacon", "spawn", "args", "verify", "timeout",
                                                                       "restore"])
    }

    // MARK: Floor, cap

    func testFloor() {
        var g = AwakeGuardsConfig()
        XCTAssertEqual(AwakeLidPolicy.floor(awakeGuards: g), 20)
        for (set, expected) in [(5, 10), (10, 10), (15, 15), (30, 30), (50, 50), (90, 50), (-3, 10)] {
            g.batteryFloor = set
            XCTAssertEqual(AwakeLidPolicy.floor(awakeGuards: g), expected, "\(set)")
        }
        g.batteryFloorEnabled = false
        g.batteryFloor = 45
        XCTAssertEqual(AwakeLidPolicy.floor(awakeGuards: g), 20, "Awake's floor off: 20%")
    }

    func testUntilAndCap() {
        let cap = Double(LidWatchdog.capSeconds)
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: nil, capStart: 100), 100 + cap)
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: 5_000, capStart: 100), 5_000)
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: 1e9, capStart: 100), 100 + cap)
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: .infinity, capStart: 100), 100 + cap)
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: .nan, capStart: 100), 100 + cap)
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: 5_000, capStart: .nan), -.infinity, "fails toward ending")
        // A kept replacement never moves the cap: capStart is the first turn-on.
        XCTAssertEqual(AwakeLidPolicy.until(sessionEnd: 200_000, capStart: 100), 100 + cap)
    }

    func testCapWarning() {
        let until = 100_000.0
        XCTAssertFalse(AwakeLidPolicy.capWarningDue(until: until, sessionEnd: nil, now: until - 301))
        XCTAssertTrue(AwakeLidPolicy.capWarningDue(until: until, sessionEnd: nil, now: until - 300))
        XCTAssertTrue(AwakeLidPolicy.capWarningDue(until: until, sessionEnd: until + 1, now: until - 10))
        XCTAssertFalse(AwakeLidPolicy.capWarningDue(until: until, sessionEnd: nil, now: until))
        XCTAssertFalse(AwakeLidPolicy.capWarningDue(until: until, sessionEnd: until, now: until - 10),
                       "the session ends first: its own 5-minute reminder covers it")
        XCTAssertFalse(AwakeLidPolicy.capWarningDue(until: until, sessionEnd: until - 50, now: until - 10))
        XCTAssertFalse(AwakeLidPolicy.capWarningDue(until: .nan, sessionEnd: nil, now: 0))
        XCTAssertTrue(AwakeLidPolicy.capEndsFirst(until: until, sessionEnd: nil))
        XCTAssertTrue(AwakeLidPolicy.capEndsFirst(until: until, sessionEnd: until + 1))
        XCTAssertFalse(AwakeLidPolicy.capEndsFirst(until: until, sessionEnd: until))
    }

    // MARK: Ends

    func testEndsSession() {
        let ending: Set<AwakeLidEnd> = [.user, .cap, .battery, .heat, .otherApp, .watchdogLost, .featureOff]
        for end in AwakeLidEnd.allCases {
            XCTAssertEqual(AwakeLidPolicy.endsSession(lidShut: true, lidWillSleep: true, reason: end), ending.contains(end),
                           "\(end)")
            XCTAssertFalse(AwakeLidPolicy.endsSession(lidShut: false, lidWillSleep: true, reason: end), "lid open \(end)")
            XCTAssertFalse(AwakeLidPolicy.endsSession(lidShut: true, lidWillSleep: false, reason: end),
                           "closing doesn't sleep \(end)")
            XCTAssertFalse(AwakeLidPolicy.endsSession(lidShut: true, lidWillSleep: nil, reason: end), "no lid \(end)")
        }
    }

    func testLidEndForSessionEnds() {
        for r in AwakeEndReason.allCases {
            let expected: AwakeLidEnd
            switch r {
            case .replaced: expected = .replaced
            case .moduleStopped: expected = .moduleStopped
            case .safeMode: expected = .safeMode
            default: expected = .sessionEnded
            }
            XCTAssertEqual(AwakeLidPolicy.lidEnd(sessionEnded: r, terminating: false), expected, "\(r)")
        }
        XCTAssertEqual(AwakeLidPolicy.lidEnd(sessionEnded: .moduleStopped, terminating: true), .quit)
        XCTAssertEqual(AwakeLidPolicy.lidEnd(sessionEnded: .user, terminating: true), .sessionEnded)
    }

    func testGuardEnd() {
        XCTAssertEqual(AwakeLidPolicy.guardEnd(batteryPercent: 80, discharging: false, floor: 20, thermalSerious: true), .heat)
        XCTAssertEqual(AwakeLidPolicy.guardEnd(batteryPercent: 20, discharging: true, floor: 20, thermalSerious: false), .battery)
        XCTAssertEqual(AwakeLidPolicy.guardEnd(batteryPercent: 5, discharging: true, floor: 20, thermalSerious: true), .heat)
        XCTAssertNil(AwakeLidPolicy.guardEnd(batteryPercent: 21, discharging: true, floor: 20, thermalSerious: false))
        XCTAssertNil(AwakeLidPolicy.guardEnd(batteryPercent: 5, discharging: false, floor: 20, thermalSerious: false))
        XCTAssertNil(AwakeLidPolicy.guardEnd(batteryPercent: nil, discharging: true, floor: 20, thermalSerious: false))
    }

    func testLiveness() {
        var l = AwakeLidLiveness()
        XCTAssertNil(l.tick(watchdogAlive: true, sleepDisabled: true))
        XCTAssertNil(l.tick(watchdogAlive: true, sleepDisabled: false))
        XCTAssertNil(l.tick(watchdogAlive: true, sleepDisabled: nil), "unreadable changes nothing")
        XCTAssertEqual(l.tick(watchdogAlive: true, sleepDisabled: false), .otherApp, "0 twice")
        var m = AwakeLidLiveness()
        XCTAssertNil(m.tick(watchdogAlive: true, sleepDisabled: false))
        XCTAssertNil(m.tick(watchdogAlive: true, sleepDisabled: true), "a 1 resets the count")
        XCTAssertNil(m.tick(watchdogAlive: true, sleepDisabled: false))
        XCTAssertEqual(m.zeroReads, 1)
        XCTAssertEqual(m.tick(watchdogAlive: false, sleepDisabled: true), .watchdogLost)
        var n = AwakeLidLiveness()
        XCTAssertEqual(n.tick(watchdogAlive: false, sleepDisabled: nil), .watchdogLost)
    }

    // MARK: Turning on

    func testLaunchStep() {
        XCTAssertEqual(AwakeLidPolicy.launchStep(.launched(pid: 4_242)), .verify(pid: 4_242))
        XCTAssertEqual(AwakeLidPolicy.launchStep(.canceled), .canceled)
        XCTAssertEqual(AwakeLidPolicy.launchStep(.failed(3)), .alreadyOff)
        XCTAssertEqual(AwakeLidPolicy.launchStep(.failed(64)), .failed(.args))
        XCTAssertEqual(AwakeLidPolicy.launchStep(.failed(-1)), .failed(.spawn))
        XCTAssertEqual(AwakeLidPolicy.launchStep(.failed(1)), .failed(.spawn))
        // The whole chain from osascript's text.
        XCTAssertEqual(AwakeLidPolicy.launchStep(LidWatchdog.parseResult("err -128\n")), .canceled)
        XCTAssertEqual(AwakeLidPolicy.launchStep(LidWatchdog.parseResult("err 3\n")), .alreadyOff)
        XCTAssertEqual(AwakeLidPolicy.launchStep(LidWatchdog.parseResult("ok 1\n")), .failed(.spawn))
    }

    func testWatchdogVerified() {
        XCTAssertTrue(AwakeLidPolicy.watchdogVerified(realUID: 0, startTime: 1_000.5, spawnedAt: 1_000))
        XCTAssertTrue(AwakeLidPolicy.watchdogVerified(realUID: 0, startTime: 999.5, spawnedAt: 1_000), "a small clock step")
        XCTAssertFalse(AwakeLidPolicy.watchdogVerified(realUID: 0, startTime: 990, spawnedAt: 1_000), "an older process")
        XCTAssertFalse(AwakeLidPolicy.watchdogVerified(realUID: 501, startTime: 1_001, spawnedAt: 1_000), "not root")
        XCTAssertFalse(AwakeLidPolicy.watchdogVerified(realUID: nil, startTime: 1_001, spawnedAt: 1_000))
        XCTAssertFalse(AwakeLidPolicy.watchdogVerified(realUID: 0, startTime: nil, spawnedAt: 1_000))
        XCTAssertFalse(AwakeLidPolicy.watchdogVerified(realUID: 0, startTime: .nan, spawnedAt: 1_000))
    }

    func testStartRefusals() {
        func refusal(battery: Int? = 80, discharging: Bool = false, floor: Int = 20, hot: Bool = false,
                     override: Bool = false, translocated: Bool = false, recovery: AwakeLidRecovery = .nothing,
                     busy: Bool = false) -> AwakeLidRefusal? {
            AwakeLidPolicy.startRefusal(batteryPercent: battery, discharging: discharging, floor: floor,
                                        thermalSerious: hot, overrideGuards: override, translocated: translocated,
                                        recovery: recovery, adminBusy: busy)
        }
        XCTAssertNil(refusal())
        XCTAssertNil(refusal(recovery: .clear))
        XCTAssertNil(refusal(battery: 25, discharging: true))
        XCTAssertEqual(refusal(battery: 24, discharging: true), .lowBattery(needed: 25))
        XCTAssertEqual(refusal(battery: 34, discharging: true, floor: 30), .lowBattery(needed: 35))
        XCTAssertNil(refusal(battery: 3, discharging: false), "on power")
        XCTAssertEqual(refusal(battery: nil, discharging: true), .lowBattery(needed: 25), "unknown level on battery")
        XCTAssertNil(refusal(battery: nil, discharging: false))
        XCTAssertEqual(refusal(hot: true), .tooHot)
        XCTAssertEqual(refusal(override: true), .startAnywaySession)
        XCTAssertEqual(refusal(translocated: true), .translocated)
        XCTAssertEqual(refusal(recovery: .pending), .journalPending)
        XCTAssertEqual(refusal(recovery: .leftover), .leftover)
        // Most fundamental first.
        XCTAssertEqual(refusal(battery: 1, discharging: true, hot: true, override: true, translocated: true,
                               recovery: .leftover), .translocated)
        XCTAssertEqual(refusal(battery: 1, discharging: true, hot: true, override: true, recovery: .leftover), .leftover)
        XCTAssertEqual(refusal(battery: 1, discharging: true, hot: true, override: true, recovery: .pending),
                       .journalPending)
        XCTAssertEqual(refusal(battery: 1, discharging: true, hot: true, override: true), .startAnywaySession)
        XCTAssertEqual(refusal(battery: 1, discharging: true, hot: true), .tooHot)
        // r2 A2-3: an earlier request's osascript isn't reaped yet (a superseded one): refused before any journal or
        // beacon work, so its stop file stays.
        XCTAssertEqual(refusal(busy: true), .journalPending)
        XCTAssertEqual(refusal(battery: 1, discharging: true, hot: true, override: true, busy: true), .journalPending)
        XCTAssertEqual(refusal(recovery: .leftover, busy: true), .leftover)
        XCTAssertEqual(refusal(translocated: true, busy: true), .translocated)
    }

    func testRefusalTexts() {
        XCTAssertEqual(AwakeLidRefusal.lowBattery(needed: 25).text,
                       "Lid-closed mode needs at least 25% battery, or connect power.")
        XCTAssertEqual(AwakeLidRefusal.tooHot.text, "Your Mac is too hot for lid-closed mode right now.")
        XCTAssertEqual(AwakeLidRefusal.startAnywaySession.text, "Lid-closed mode isn’t available in a Start Anyway session.")
        XCTAssertEqual(AwakeLidRefusal.translocated.text,
                       "Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode.")
        XCTAssertEqual(AwakeLidRefusal.journalPending.text,
                       "Snaptic is finishing an earlier lid-closed session. Try again in a minute.")
        XCTAssertEqual(AwakeLidRefusal.leftover.text,
                       "Turn sleep back on first. It may have been left off by an earlier lid-closed session.")
        XCTAssertEqual(AwakeLidRefusal.leftover.buttons, ["Turn Sleep Back On…", "Open Awake Settings…"])
        XCTAssertEqual(AwakeLidRefusal.tooHot.buttons, [])
    }

    // MARK: Journal and recovery (B3.4)

    func testJournalRoundTripAndParse() throws {
        let j = journal()
        let data = try XCTUnwrap(j.encoded())
        XCTAssertEqual(AwakeLidJournal.parse(data), j)
        XCTAssertEqual(AwakeLidJournal.parse(Data("{}".utf8)), .unreadable)
        XCTAssertEqual(AwakeLidJournal.parse(Data("not json".utf8)), .unreadable)
        XCTAssertEqual(AwakeLidJournal.parse(Data(repeating: 0x20, count: AwakeLidJournal.maxBytes + 1)), .unreadable)
        var noPID = j
        noPID.pid = nil
        noPID.instanceID = nil
        XCTAssertEqual(AwakeLidJournal.parse(try XCTUnwrap(noPID.encoded())), noPID, "written before verify")
    }

    func testJournalSanity() {
        XCTAssertTrue(journal().isSane(ownPID: 1_000))
        XCTAssertTrue(journal(pid: nil).isSane(ownPID: 1_000))
        XCTAssertFalse(journal(pid: 1_000).isSane(ownPID: 1_000), "the watchdog is never Snaptic itself")
        XCTAssertFalse(journal(pid: 1).isSane(ownPID: 1_000))
        XCTAssertFalse(journal(pid: 100_000).isSane(ownPID: 1_000))
        XCTAssertFalse(journal(floor: 9).isSane(ownPID: 1_000))
        XCTAssertFalse(journal(token: "x").isSane(ownPID: 1_000))
        XCTAssertFalse(journal(boot: "").isSane(ownPID: 1_000))
        XCTAssertFalse(journal(at: .nan).isSane(ownPID: 1_000))
        XCTAssertFalse(AwakeLidJournal.unreadable.isSane(ownPID: 1_000))
    }

    func testClassifyTable() {
        func c(_ j: AwakeLidJournal?, _ sd: Bool?, boot: String? = nil, at: Double = 1_100) -> AwakeLidRecovery {
            AwakeLidPolicy.classify(journal: j, bootUUID: boot ?? self.boot, sleepDisabled: sd, now: now(at), ownPID: 1_000)
        }
        // B3.4's table.
        XCTAssertEqual(c(nil, true), .nothing, "someone else's setting")
        XCTAssertEqual(c(nil, false), .nothing)
        XCTAssertEqual(c(nil, nil), .nothing)
        XCTAssertEqual(c(journal(), false), .clear)
        XCTAssertEqual(c(journal(boot: "BOOT-0"), true), .leftover, "SleepDisabled survives a reboot")
        XCTAssertEqual(c(journal(), true), .pending, "same boot: the watchdog may still restore")
        // Fail-safe readings.
        XCTAssertEqual(c(journal(), nil), .pending, "unreadable: keep the journal, refuse, look again")
        XCTAssertEqual(c(journal(), true, boot: ""), .pending, "boot unreadable")
        XCTAssertEqual(c(.unreadable, true), .leftover, "a journal file that can't be read is still Snaptic's")
        XCTAssertEqual(c(.unreadable, false), .clear)
        XCTAssertEqual(c(journal(pid: 1_000), true), .leftover)
        // No watchdog outlives its cap: a same-boot journal older than that is a leftover at once.
        let longest = Double(LidWatchdog.capSeconds + 60) + AwakeLidPolicy.pendingRecheckSeconds
        XCTAssertEqual(c(journal(at: 1_000), true, at: 1_000 + longest), .pending)
        XCTAssertEqual(c(journal(at: 1_000), true, at: 1_000 + longest + 1), .leftover)
        XCTAssertEqual(c(journal(at: 1_000), true, at: 999), .leftover, "a start after now")
        // The re-check.
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: false), .clear)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: true), .leftover)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: nil), .pending)
    }

    /// r1 S1: only an exit after which a watchdog may have run keeps and watches the journal. "Already off" (the
    /// preflight, `check`'s 3), `check`'s 64, Cancel and every failure before osascript ran never do, so another
    /// app's `SleepDisabled` never becomes Snaptic's leftover.
    func testAbandonWatchesOnlyWhenAWatchdogMayHaveRun() {
        let table: [(AwakeLidStage, LidWatchdog.Outcome?, Bool, String)] = [
            (.preflight, nil, false, "preflight: already off, or the kernel unreadable"),
            (.preflight, .failed(3), false, "preflight"),
            (.journaled, nil, false, "beacon, args or spawn failure: osascript never ran"),
            (.journaled, .launched(pid: 4_242), false, "never started"),
            (.spawned, .canceled, false, "Cancel: no password, nothing ran"),
            (.spawned, .failed(3), false, "check exit 3: sleep already off, run never executes"),
            (.spawned, .failed(64), false, "check exit 64: run never executes"),
            (.spawned, .launched(pid: 4_242), true, "verify failed or timed out"),
            (.spawned, .failed(1), true, "an error after check passed"),
            (.spawned, .failed(-1), true, "unparsable answer"),
            (.spawned, nil, true, "timeout, superseded or stopped while osascript may run"),
        ]
        for (stage, outcome, expected, label) in table {
            XCTAssertEqual(AwakeLidPolicy.abandonWatches(stage: stage, outcome: outcome), expected, label)
        }
        // The whole chain from osascript's text.
        XCTAssertFalse(AwakeLidPolicy.abandonWatches(stage: .spawned, outcome: LidWatchdog.parseResult("err 3\n")))
        XCTAssertFalse(AwakeLidPolicy.abandonWatches(stage: .spawned, outcome: LidWatchdog.parseResult("err -128\n")))
        XCTAssertTrue(AwakeLidPolicy.abandonWatches(stage: .spawned, outcome: LidWatchdog.parseResult("err 1\n")))
    }

    /// B3.4's first row at the end of a wait: no Snaptic journal, no leftover (r1 S1/C1).
    func testRecheckWithoutAJournalIsNothing() {
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: true, journalExists: false), .nothing)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: nil, journalExists: false), .nothing)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: false, journalExists: false), .nothing)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: true, journalExists: true), .leftover)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: nil, journalExists: true), .pending)
        XCTAssertEqual(AwakeLidPolicy.recheck(sleepDisabled: false, journalExists: true), .clear)
    }

    /// r1 A3: a lost watchdog waits like any other end before the leftover rows; quitting hands the host longer.
    func testEndPollSeconds() {
        XCTAssertEqual(AwakeLidPolicy.endPollSeconds(.watchdogLost), 15)
        for reason in [AwakeLidEnd.user, .sessionEnded, .replaced, .cap, .battery, .heat, .otherApp, .featureOff] {
            XCTAssertEqual(AwakeLidPolicy.endPollSeconds(reason), 15, "\(reason)")
        }
        for reason in [AwakeLidEnd.quit, .moduleStopped, .safeMode] {
            XCTAssertEqual(AwakeLidPolicy.endPollSeconds(reason), 30, "\(reason)")
        }
    }

    /// r1 A4: the Custom… panel never closes without starting something or saying why.
    func testCustomPanel() {
        let modes: [AwakeLidMode] = [.off, .failed(.verify), .authorizing(token: token), .verifying(token: token, pid: 5),
                                     .on(token: token, pid: 5, until: 9), .stopping(token: token)]
        XCTAssertEqual(modes.map { AwakeLidPolicy.customToggleShown(effective: true, mode: $0) },
                       [true, true, false, false, false, false])
        XCTAssertEqual(modes.map { AwakeLidPolicy.customToggleShown(effective: false, mode: $0) },
                       [false, false, false, false, false, false])
        XCTAssertEqual(modes.map { AwakeLidPolicy.customStart(lidToggle: true, effective: true, mode: $0) },
                       [.request, .request, .pending(.authorizing), .pending(.verifying), .plain, .pending(.stopping)])
        XCTAssertEqual(modes.map { AwakeLidPolicy.customStart(lidToggle: false, effective: true, mode: $0) },
                       [.plain, .plain, .plain, .plain, .plain, .plain])
        // r2 A2-2: the feature turned off (or its kill switch, or Safe Mode) while the panel was open.
        XCTAssertEqual(modes.map { AwakeLidPolicy.customStart(lidToggle: true, effective: false, mode: $0) },
                       [.unavailable, .unavailable, .pending(.authorizing), .pending(.verifying), .plain,
                        .pending(.stopping)])
        XCTAssertEqual(modes.map { AwakeLidPolicy.customStart(lidToggle: false, effective: false, mode: $0) },
                       [.plain, .plain, .plain, .plain, .plain, .plain])
        XCTAssertEqual(AwakeLidText.rowTitle(.authorizing), "Waiting for Password…")
        XCTAssertEqual(AwakeLidText.customUnavailable,
                       "Lid-closed mode isn’t available right now. To start without it, turn off “Keep awake with the lid closed”.")
        // The pending toast is a sentence, not the bare row title.
        XCTAssertEqual(AwakeLidText.pendingToast(.authorizing),
                       "Lid-closed mode is waiting for a password. Try again in a moment.")
        XCTAssertEqual(AwakeLidText.pendingToast(.verifying), "Lid-closed mode is turning on. Try again in a moment.")
        XCTAssertEqual(AwakeLidText.pendingToast(.stopping), "Lid-closed mode is turning off. Try again in a moment.")
        XCTAssertEqual(AwakeLidText.pendingToast(.finishingEarlier),
                       "Snaptic is finishing an earlier lid-closed session. Try again in a minute.")
        XCTAssertNil(AwakeLidText.pendingToast(.off))
        XCTAssertNil(AwakeLidText.pendingToast(.on))
    }

    /// r2 A2-1: the watchdog gone is named by the app's own facts when they explain it.
    func testLostReason() {
        let cap = Double(LidWatchdog.capSeconds)
        func reason(battery: Int? = 80, discharging: Bool = false, hot: Bool = false, now: Double = 5_000,
                    zero: Bool = false) -> AwakeLidEnd {
            AwakeLidPolicy.lostReason(batteryPercent: battery, discharging: discharging, floor: 20, thermalSerious: hot,
                                      capStart: 1_000, now: now, zeroReadWhileAlive: zero)
        }
        XCTAssertEqual(reason(), .watchdogLost)
        XCTAssertEqual(reason(battery: 20, discharging: true), .battery)
        XCTAssertEqual(reason(battery: 21, discharging: true), .watchdogLost)
        XCTAssertEqual(reason(battery: 20, discharging: false), .watchdogLost, "on power")
        XCTAssertEqual(reason(battery: nil, discharging: true), .watchdogLost, "unknown level")
        XCTAssertEqual(reason(hot: true), .heat)
        XCTAssertEqual(reason(battery: 5, discharging: true, hot: true), .heat, "heat first")
        XCTAssertEqual(reason(now: 1_000 + cap), .cap)
        XCTAssertEqual(reason(now: 1_000 + cap + 90), .cap)
        XCTAssertEqual(reason(now: 1_000 + cap - 1), .watchdogLost, "the watchdog's cap is never before the app's")
        XCTAssertEqual(reason(battery: 10, discharging: true, now: 1_000 + cap), .battery)
        // r3 A3-1: root left first after another app turned sleep back on; the app had read that 0 already.
        XCTAssertEqual(reason(zero: true), .otherApp)
        XCTAssertEqual(reason(battery: 20, discharging: true, zero: true), .battery, "the floor first")
        XCTAssertEqual(reason(hot: true, zero: true), .heat, "heat first")
        XCTAssertEqual(reason(now: 1_000 + cap, zero: true), .cap, "the cap first")
    }

    /// r2 A2-5: only a quit after a restart, shut down or log out writes the halt file.
    func testWritesHalt() {
        XCTAssertTrue(AwakeLidPolicy.writesHalt(.quit, poweringOff: true))
        XCTAssertFalse(AwakeLidPolicy.writesHalt(.quit, poweringOff: false), "a plain quit with the lid shut sleeps")
        XCTAssertFalse(AwakeLidPolicy.writesHalt(.moduleStopped, poweringOff: true))
        XCTAssertFalse(AwakeLidPolicy.writesHalt(.safeMode, poweringOff: true))
        XCTAssertFalse(AwakeLidPolicy.writesHalt(.user, poweringOff: true))
    }

    /// r3 S3-1: a new request keeps stop files younger than 3 minutes; beacons and halt files always go.
    func testClearsBeaconFile() {
        let t = "0123456789abcdef0123456789abcdef"
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile("stop-" + t, ageSeconds: 0))
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile("stop-" + t, ageSeconds: 179))
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile("stop-" + t, ageSeconds: -600), "clock stepped back")
        XCTAssertTrue(AwakeLidPolicy.clearsBeaconFile("stop-" + t, ageSeconds: 180))
        XCTAssertTrue(AwakeLidPolicy.clearsBeaconFile("stop-" + t, ageSeconds: .infinity), "unreadable")
        XCTAssertTrue(AwakeLidPolicy.clearsBeaconFile("beat-" + t, ageSeconds: 0))
        XCTAssertTrue(AwakeLidPolicy.clearsBeaconFile("halt-" + t, ageSeconds: 0))
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile("stop-" + t + "0", ageSeconds: 1_000))
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile("beat-xyz", ageSeconds: 1_000))
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile("note.txt", ageSeconds: 1_000))
        XCTAssertFalse(AwakeLidPolicy.clearsBeaconFile(t, ageSeconds: 1_000))
    }

    /// r3 U3-6: the Custom… panel stays open after a refusal, as when the feature is unavailable.
    func testCustomPanelClosesOnlyOnceStarted() {
        XCTAssertTrue(AwakeLidRequestResult.started.closesCustomPanel)
        XCTAssertFalse(AwakeLidRequestResult.refused.closesCustomPanel)
        XCTAssertFalse(AwakeLidRequestResult.nothing.closesCustomPanel)
    }

    /// r2 A2-4: "Snaptic quit" only for the resumed session that had the mode.
    func testQuitEndShown() {
        let s = StableID(), other = StableID()
        XCTAssertTrue(AwakeLidPolicy.quitEndShown(launchJournal: true, leftover: false, lidSession: s, resumed: s))
        XCTAssertFalse(AwakeLidPolicy.quitEndShown(launchJournal: true, leftover: false, lidSession: nil, resumed: s),
                       "a failed request's journal survived the quit; the session never had the mode")
        XCTAssertFalse(AwakeLidPolicy.quitEndShown(launchJournal: true, leftover: false, lidSession: other, resumed: s))
        XCTAssertFalse(AwakeLidPolicy.quitEndShown(launchJournal: false, leftover: false, lidSession: s, resumed: s),
                       "the mode had already ended before the quit")
        XCTAssertFalse(AwakeLidPolicy.quitEndShown(launchJournal: true, leftover: true, lidSession: s, resumed: s),
                       "the leftover rows explain it")
    }

    /// r1 C4 and U7: Turn Sleep Back On… says when it failed, and the menus' row waits like the Awake page's.
    func testTurnSleepBackOnFeedback() {
        XCTAssertTrue(AwakeLidPolicy.restoreFailed(.failed(1)))
        XCTAssertTrue(AwakeLidPolicy.restoreFailed(.failed(-1)))
        XCTAssertFalse(AwakeLidPolicy.restoreFailed(.canceled))
        XCTAssertFalse(AwakeLidPolicy.restoreFailed(.restored))
        XCTAssertTrue(AwakeLidPolicy.restoreFailed(LidWatchdog.parseRestoreResult("garbage")))
        XCTAssertEqual(AwakeLidText.couldNotTurnSleepBackOn, "Snaptic couldn’t turn sleep back on. Try again.")
        XCTAssertEqual(AwakeLidText.restoreRow(restoring: false).title, "Turn Sleep Back On…")
        XCTAssertTrue(AwakeLidText.restoreRow(restoring: false).enabled)
        XCTAssertEqual(AwakeLidText.restoreRow(restoring: true).title, "Waiting for Password…")
        XCTAssertFalse(AwakeLidText.restoreRow(restoring: true).enabled)
    }

    /// r1 A2: a superseded request's late exit can't read or clear the next request's handle or line.
    func testTokenSlot() {
        let a = "a" + String(token.dropFirst()), b = "b" + String(token.dropFirst())
        var slot = AwakeLidTokenSlot<Int>()
        XCTAssertNil(slot.take(a))
        slot.put(1, for: a)
        slot.put(2, for: b)              // the next request
        XCTAssertNil(slot.value(for: a))
        XCTAssertNil(slot.take(a), "A's late exit")
        XCTAssertEqual(slot.value(for: b), 2, "B's is untouched")
        XCTAssertEqual(slot.take(b), 2)
        XCTAssertNil(slot.value(for: b), "taken once")
        XCTAssertNil(slot.token)
    }

    func testTimings() {
        XCTAssertEqual(AwakeLidPolicy.osascriptTimeoutSeconds, 120)
        XCTAssertEqual(AwakeLidPolicy.osascriptKillGraceSeconds, 5)
        XCTAssertEqual(AwakeLidPolicy.verifyLimitSeconds, 10)
        XCTAssertEqual(AwakeLidPolicy.verifyPollSeconds, 0.5)
        XCTAssertEqual(AwakeLidPolicy.heartbeatSeconds, 5)
        XCTAssertEqual(AwakeLidPolicy.stopPollSeconds, 15)
        XCTAssertEqual(AwakeLidPolicy.failedExitPollSeconds, 30)
        XCTAssertEqual(AwakeLidPolicy.capWarningSeconds, 300)
        XCTAssertEqual(AwakeLidPolicy.lastEndKeepSeconds, 43_200)
        XCTAssertEqual(AwakeLidPolicy.mainAgeLimitMillis, 10_000)
    }
}
