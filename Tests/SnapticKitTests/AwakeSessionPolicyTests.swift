import XCTest
@testable import SnapticKit

final class AwakeSessionPolicyTests: XCTestCase {
    private let boot = "BOOT-A"
    private func now(_ continuous: Double, wall: Double = 1_000_000) -> ClockNow {
        ClockNow(wall: wall + continuous, continuous: continuous, bootSession: boot)
    }
    private func id(_ n: String) -> StableID { StableID.derived(namespace: "test", name: n) }
    private func session(_ kind: AwakeSessionKind, source: AwakeSessionSource = .menu, at t: Double = 0,
                         id name: String = "s") -> AwakeSession {
        AwakeClock.start(kind, options: AwakeSessionOptions(), presetID: nil, source: source, now: now(t), id: id(name))
    }

    // MARK: Start rules

    func testCLIRules() {
        let ui = session(.indefinite, source: .menu)
        let cli = session(.duration(seconds: 600), source: .commandLine)
        XCTAssertEqual(AwakeStartRules.refusal(kind: .indefinite, source: .commandLine, current: nil, now: now(1)),
                       .notAllowedFromCLI)
        XCTAssertEqual(AwakeStartRules.refusal(kind: .duration(seconds: 600), source: .commandLine, current: ui, now: now(1)),
                       .uiSessionRunning)
        XCTAssertNil(AwakeStartRules.refusal(kind: .duration(seconds: 600), source: .commandLine, current: cli, now: now(1)),
                     "a CLI session may replace a CLI session")
        XCTAssertNil(AwakeStartRules.refusal(kind: .duration(seconds: 600), source: .hotkey, current: ui, now: now(1)),
                     "UI starts replace anything")
        XCTAssertNil(AwakeStartRules.refusal(kind: .indefinite, source: .settings, current: nil, now: now(1)))
        XCTAssertEqual(AwakeStartRules.refusal(kind: .duration(seconds: 600), source: .rule, current: nil, now: now(1)),
                       .invalid, "rules never start manual sessions")
        let launch = session(.duration(seconds: 600), source: .launch)
        XCTAssertNil(AwakeStartRules.refusal(kind: .duration(seconds: 60), source: .commandLine, current: launch, now: now(1)))
    }

    func testKindValidity() {
        let n = now(10)
        XCTAssertEqual(AwakeStartRules.refusal(kind: .duration(seconds: 59), source: .menu, current: nil, now: n), .invalid)
        XCTAssertNil(AwakeStartRules.refusal(kind: .duration(seconds: 60), source: .menu, current: nil, now: n))
        XCTAssertEqual(AwakeStartRules.refusal(kind: .duration(seconds: AwakeClock.maxSessionSeconds + 1), source: .menu,
                                               current: nil, now: n), .invalid)
        XCTAssertEqual(AwakeStartRules.refusal(kind: .until(unixTime: n.wall - 5), source: .menu, current: nil, now: n), .invalid)
        XCTAssertEqual(AwakeStartRules.refusal(kind: .until(unixTime: .nan), source: .menu, current: nil, now: n), .invalid)
        XCTAssertNil(AwakeStartRules.refusal(kind: .until(unixTime: n.wall + 3_600), source: .menu, current: nil, now: n))
        XCTAssertEqual(AwakeStartRules.refusal(kind: .until(unixTime: n.wall + 31 * 86_400), source: .menu, current: nil,
                                               now: n), .invalid)
        XCTAssertNil(AwakeStartRules.refusal(kind: .whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: nil), source: .menu,
                                             current: nil, now: n))
        XCTAssertEqual(AwakeStartRules.refusal(kind: .whileApp(bundleID: "not a bundle", maxSeconds: nil), source: .menu,
                                               current: nil, now: n), .invalid)
        XCTAssertEqual(AwakeStartRules.refusal(kind: .whileApp(bundleID: "com.a.b", maxSeconds: 10), source: .menu,
                                               current: nil, now: n), .invalid)
        XCTAssertNil(AwakeStartRules.refusal(kind: .untilIdle(UntilIdleSpec(), maxSeconds: 3_600), source: .menu,
                                             current: nil, now: n))
    }

    func testCLIKinds() {
        XCTAssertEqual(AwakeStartRules.cliKind(nil, untilUnix: nil), .duration(seconds: 3_600), "C10: no argument = 1 h")
        XCTAssertEqual(AwakeStartRules.cliKind(.untilIdle, untilUnix: nil),
                       .untilIdle(UntilIdleSpec(), maxSeconds: AwakeClock.holdDefaultCapSeconds))
        XCTAssertEqual(AwakeStartRules.cliKind(.untilClock(hour: 17, minute: 30), untilUnix: 5_000), .until(unixTime: 5_000))
        XCTAssertNil(AwakeStartRules.cliKind(.untilClock(hour: 17, minute: 30), untilUnix: nil))
        XCTAssertEqual(AwakeStartRules.cliKind(.indefinite, untilUnix: nil), .indefinite)
        XCTAssertEqual(AwakeStartRules.cliCapped(.untilIdle(UntilIdleSpec(), maxSeconds: 600)),
                       .untilIdle(UntilIdleSpec(), maxSeconds: 600), "an explicit cap stays")
        XCTAssertEqual(AwakeStartRules.cliCapped(.indefinite), .indefinite)
    }

    // MARK: Turn Off

    func testTurnOffTargetsAndNotices() {
        let m = session(.indefinite)
        let top = TriggerTop(id: id("r"), index: 0, options: AwakeSessionOptions(), since: 0)
        let hold = AwakeClock.hold(.process(pid: 50, startTime: 1), capSeconds: 600, now: now(0), id: id("h"))
        XCTAssertEqual(AwakeTurnOff.target(.inactive), .nothing)
        XCTAssertEqual(AwakeTurnOff.target(.manual(m)), .manual)
        XCTAssertEqual(AwakeTurnOff.target(.trigger(top)), .trigger(id("r")))
        XCTAssertEqual(AwakeTurnOff.target(.holds([hold])), .holds)
        XCTAssertEqual(AwakeTurnOff.notice(after: .trigger(top)), .rules(id("r")))
        XCTAssertEqual(AwakeTurnOff.notice(after: .holds([hold])), .holds)
        XCTAssertNil(AwakeTurnOff.notice(after: .inactive), "nothing remains: no toast")
    }

    // MARK: Reminders

    func testFiveMinuteReminderOncePerEnd() {
        var r = AwakeReminders()
        let s = session(.duration(seconds: 3_600))
        XCTAssertNil(r.due(s, now: now(3_000)), "more than 5 min left")
        XCTAssertEqual(r.nextDue(s, now: now(3_000)) ?? -1, 300, accuracy: 0.001)
        XCTAssertEqual(r.due(s, now: now(3_301)), .fiveMinutes)
        XCTAssertNil(r.due(s, now: now(3_400)), "once")
        XCTAssertNil(r.nextDue(s, now: now(3_400)))
        // Add 1 Hour moves the end: it reminds again.
        let extended = AwakeClock.extended(s, by: 3_600, now: now(3_400))!
        XCTAssertNil(r.due(extended, now: now(3_400)))
        XCTAssertEqual(r.due(extended, now: now(6_901)), .fiveMinutes)
    }

    func testFiveMinuteReminderNeedsFifteenMinutesOfRun() {
        var r = AwakeReminders()
        let short = session(.duration(seconds: 900))
        XCTAssertNil(r.due(short, now: now(700)), "a 15-min session is at 11 min when 5 min remain")
        XCTAssertNil(r.nextDue(short, now: now(700)), "it never ran 15 min with time left")
        let twenty = session(.duration(seconds: 1_200), id: "t")
        XCTAssertEqual(r.nextDue(twenty, now: now(0)) ?? -1, 900, accuracy: 0.001, "waits for the 15 min of run")
        XCTAssertEqual(r.due(twenty, now: now(900)), .fiveMinutes)
    }

    func testEightHourReminderOnceForIndefinite() {
        var r = AwakeReminders()
        let s = session(.indefinite)
        XCTAssertNil(r.due(s, now: now(8 * 3_600 - 1)))
        XCTAssertEqual(r.nextDue(s, now: now(3_600)) ?? -1, 7 * 3_600, accuracy: 0.001)
        XCTAssertEqual(r.due(s, now: now(8 * 3_600)), .eightHours)
        XCTAssertNil(r.due(s, now: now(9 * 3_600)))
        XCTAssertNil(r.due(session(.whileApp(bundleID: "com.a.b", maxSeconds: nil)), now: now(9 * 3_600)),
                     "task kinds have no long-session reminder")
        let other = session(.indefinite, id: "other")
        XCTAssertEqual(r.due(other, now: now(9 * 3_600)), .eightHours, "a new session reminds again")
        XCTAssertNil(r.due(other, now: ClockNow(wall: 0, continuous: 9 * 3_600, bootSession: "B")), "other boot")
    }

    // MARK: Tick

    func testTickPicksTheSoonestAndClamps() {
        let r = AwakeReminders()
        XCTAssertNil(AwakeTick.next(manual: nil, holds: [], reminders: r, now: now(0)))
        XCTAssertNil(AwakeTick.next(manual: session(.whileApp(bundleID: "com.a.b", maxSeconds: nil)), holds: [],
                                    reminders: r, now: now(0)))
        let s = session(.duration(seconds: 3_600))
        XCTAssertEqual(AwakeTick.next(manual: s, holds: [], reminders: r, now: now(0)) ?? -1, 60, accuracy: 0.001,
                       "the countdown's minute boundary")
        let hold = AwakeClock.hold(.process(pid: 50, startTime: 1), capSeconds: 600, now: now(0), id: id("h"))
        XCTAssertEqual(AwakeTick.next(manual: nil, holds: [hold], reminders: r, now: now(599.9)) ?? -1,
                       AwakeTick.minimum, accuracy: 0.001)
        XCTAssertEqual(AwakeTick.next(manual: session(.indefinite), holds: [], reminders: r, now: now(0)) ?? -1,
                       AwakeTick.maximum, accuracy: 0.001, "the 8-hour reminder is further than the cap")
    }

    func testTickFuzzIsBoundedAndFinite() {
        var rng = SeededGenerator(seed: 0xA11CE)
        var reminders = AwakeReminders()
        for i in 0..<5_000 {
            let start = Double(rng.next() % 100_000)
            let kinds: [AwakeSessionKind] = [.indefinite, .duration(seconds: Int(rng.next() % 200_000) + 60),
                                             .until(unixTime: 1_000_000 + start + Double(rng.next() % 90_000)),
                                             .untilIdle(UntilIdleSpec(), maxSeconds: Int(rng.next() % 9_000) + 60)]
            let s = session(kinds[Int(rng.next() % 4)], at: start, id: "f\(i % 7)")
            let t = now(start + Double(rng.next() % 300_000))
            _ = reminders.due(s, now: t)
            if let next = AwakeTick.next(manual: s, holds: [], reminders: reminders, now: t) {
                XCTAssertTrue(next.isFinite && next >= AwakeTick.minimum && next <= AwakeTick.maximum)
            }
        }
    }

    // MARK: Pointer prompt (R5-1)

    func testPromptAsksOnlyWhenShown() {
        var p = AwakePointerPrompt()
        XCTAssertNil(p.offered(session: id("a"), shown: false), "suppressed: the gate stays askOnFirstUse")
        XCTAssertFalse(p.isShowing)
        XCTAssertEqual(p.offered(session: id("a"), shown: true), .confirmAsked)
        XCTAssertTrue(p.isShowing)
    }

    func testAllowAppliesOnlyToTheSameSession() {
        var p = AwakePointerPrompt()
        _ = p.offered(session: id("a"), shown: true)
        XCTAssertNil(p.allowed(governingManual: id("b")), "replaced meanwhile: Allow does nothing")
        XCTAssertFalse(p.isShowing)
        _ = p.offered(session: id("a"), shown: true)
        XCTAssertNil(p.allowed(governingManual: nil), "ended meanwhile")
        _ = p.offered(session: id("a"), shown: true)
        XCTAssertEqual(p.allowed(governingManual: id("a")), .confirmAllowed)
        XCTAssertNil(p.allowed(governingManual: id("a")), "one answer per prompt")
    }

    func testDeclineAndDismissalBoundToTheSession() {
        var p = AwakePointerPrompt()
        _ = p.offered(session: id("a"), shown: true)
        XCTAssertEqual(p.declined(governingManual: id("a")), .confirmDeclined)
        _ = p.offered(session: id("a"), shown: true)
        XCTAssertNil(p.declined(governingManual: id("b")), "a late dismissal never declines the next session")
        _ = p.offered(session: id("a"), shown: true)
        p.reset()
        XCTAssertNil(p.allowed(governingManual: id("a")))
    }

    /// The gate wiring end to end: hotkey start → prompt → only Allow for the same session reaches `.allowed`.
    func testPromptAndGateTogether() {
        var rng = SeededGenerator(seed: 0x51DE)
        for _ in 0..<2_000 {
            var gate = AwakeActivityGate().applying(.hotkeyStart)
            var prompt = AwakePointerPrompt()
            var governing: StableID? = id("a")
            var allowedLegitimately = false
            for _ in 0..<6 {
                switch rng.next() % 6 {
                case 0:
                    if let e = prompt.offered(session: governing ?? id("a"), shown: rng.next() % 2 == 0) {
                        gate = gate.applying(e)
                    }
                case 1:
                    let wasSame = prompt.sessionID != nil && prompt.sessionID == governing && gate.pointer == .asking
                    if let e = prompt.allowed(governingManual: governing) {
                        gate = gate.applying(e)
                        if wasSame { allowedLegitimately = true }
                    }
                case 2:
                    if let e = prompt.declined(governingManual: governing) { gate = gate.applying(e) }
                case 3:
                    governing = id("b")
                    prompt.reset()
                    gate = gate.applying(.replaced).applying(.hotkeyStart)
                    allowedLegitimately = false
                case 4:
                    gate = gate.applying(.unchanged)
                default:
                    governing = nil
                    prompt.reset()
                    gate = gate.applying(.ended)
                    allowedLegitimately = false
                }
                if gate.pointer == .allowed { XCTAssertTrue(allowedLegitimately) }
            }
        }
    }

    // MARK: System policy

    func testUserSwitchAndLockEnds() {
        var b = AwakeBehavior()
        XCTAssertEqual(b.userSwitchEnd, .afterHour)
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false, lockedSince: nil,
                                           sessionStart: 0, now: 3_599))
        XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                             lockedSince: nil, sessionStart: 0, now: 3_600), .userSwitch)
        XCTAssertEqual(AwakeSystemPolicy.nextCheck(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                                   lockedSince: nil, sessionStart: 0, now: 600) ?? -1, 3_000, accuracy: 0.001)
        b.userSwitchEnd = .immediately
        XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: nil, locked: false,
                                             lockedSince: nil, sessionStart: 0, now: 0), .userSwitch)
        b.userSwitchEnd = .never
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false, lockedSince: nil,
                                           sessionStart: 0, now: 99_999))
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: true, lockedSince: 0,
                                           sessionStart: 0, now: 99_999), "no locked limit by default")
        b.endAfterLockedHours = 4
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: true, lockedSince: 0,
                                           sessionStart: 0, now: 4 * 3_600 - 1))
        XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: true, lockedSince: 0,
                                             sessionStart: 0, now: 4 * 3_600), .lockedTooLong)
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: false,
                                           lockedSince: nil, sessionStart: 0, now: 9 * 3_600))
    }

    /// Lead decision (review5 awake N2, review6 F1): off-console and locked time count from `max(since, start)`.
    func testGraceCountsFromTheSessionStart() {
        var b = AwakeBehavior()
        let h: Double = 3_600
        // Another user has had the console for 2 h; a CLI start now gets the full hour.
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                           lockedSince: nil, sessionStart: 2 * h, now: 2 * h))
        XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                           lockedSince: nil, sessionStart: 2 * h, now: 3 * h - 1))
        XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                             lockedSince: nil, sessionStart: 2 * h, now: 3 * h), .userSwitch)
        XCTAssertEqual(AwakeSystemPolicy.nextCheck(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                                   lockedSince: nil, sessionStart: 2 * h, now: 2 * h) ?? -1, h,
                       accuracy: 0.001)
        // A session that was running when the switch happened still counts from the switch.
        XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: h, locked: false,
                                             lockedSince: nil, sessionStart: 0, now: 2 * h), .userSwitch)
        // `.immediately` still means at once, whenever the session started.
        b.userSwitchEnd = .immediately
        XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: false, offConsoleSince: 0, locked: false,
                                             lockedSince: nil, sessionStart: 2 * h, now: 2 * h), .userSwitch)
        // Locked for N hours before the start: the session gets N hours of its own.
        b = AwakeBehavior()
        for hours in 1...6 {
            b.endAfterLockedHours = hours
            let n = Double(hours) * h
            XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: true,
                                               lockedSince: 0, sessionStart: n, now: n), "locked \(hours) h")
            XCTAssertNil(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: true,
                                               lockedSince: 0, sessionStart: n, now: 2 * n - 1))
            XCTAssertEqual(AwakeSystemPolicy.end(behavior: b, onConsole: true, offConsoleSince: nil, locked: true,
                                                 lockedSince: 0, sessionStart: n, now: 2 * n), .lockedTooLong)
            XCTAssertEqual(AwakeSystemPolicy.nextCheck(behavior: b, onConsole: true, offConsoleSince: nil, locked: true,
                                                       lockedSince: 0, sessionStart: n, now: n) ?? -1, n, accuracy: 0.001)
        }
        // Not locked and on console: nothing counts, whatever the start.
        XCTAssertNil(AwakeSystemPolicy.nextCheck(behavior: b, onConsole: true, offConsoleSince: nil, locked: false,
                                                 lockedSince: nil, sessionStart: 0, now: 10 * h))
        XCTAssertNil(AwakeSystemPolicy.counting(since: nil, sessionStart: 5))
        XCTAssertEqual(AwakeSystemPolicy.counting(since: 3, sessionStart: .nan), 3, "a bad start never shortens the grace")
        XCTAssertNil(AwakeSystemPolicy.counting(since: .infinity, sessionStart: 5))
    }

    // MARK: Keep Awake shortcut registered (fix round 2 shared decision)

    func testKeepAwakeRegisteredOnlyWhenEverythingHolds() {
        typealias R = AwakeShortcutRegistration
        // Working: the feature is effective, a combo is stored and registering it succeeded.
        XCTAssertTrue(R.keepAwakeRegistered(shortcutsEffective: true, hasCombo: true, registered: true))
        // The kill switch, Safe Mode, the Shortcuts setting off or a stopped module: a stale registration doesn't count.
        XCTAssertFalse(R.keepAwakeRegistered(shortcutsEffective: false, hasCombo: true, registered: true))
        // The combo was cleared (the old registration may linger until the next pass).
        XCTAssertFalse(R.keepAwakeRegistered(shortcutsEffective: true, hasCombo: false, registered: true))
        // Another app or macOS owns the combo: registering failed.
        XCTAssertFalse(R.keepAwakeRegistered(shortcutsEffective: true, hasCombo: true, registered: false))
        XCTAssertFalse(R.keepAwakeRegistered(shortcutsEffective: false, hasCombo: false, registered: false))
        // What the menu bar's Don't Show fallback then sees: a hidden Awake stays reachable only in the working case.
        let killed = R.keepAwakeRegistered(shortcutsEffective: false, hasCombo: true, registered: true)
        XCTAssertFalse(MenuLayout.awakeShortcutStatus(LossyMap(), failed: [], registered: killed).isBound)
        let working = R.keepAwakeRegistered(shortcutsEffective: true, hasCombo: true, registered: true)
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(LossyMap(), failed: [], registered: working), .registered)
    }

    func testRemindersKeepingOnlyTheirSession() {
        let a = StableID(), b = StableID()
        var r = AwakeReminders()
        let s = AwakeClock.start(.indefinite, options: AwakeSessionOptions(), presetID: nil, source: .menu,
                                 now: ClockNow(wall: 1_000, continuous: 0, bootSession: "B"), id: a)
        XCTAssertEqual(r.due(s, now: ClockNow(wall: 1_000 + 8 * 3_600, continuous: 8 * 3_600, bootSession: "B")), .eightHours)
        var kept = r.keeping(session: a)
        XCTAssertEqual(kept, r)
        XCTAssertNil(kept.due(s, now: ClockNow(wall: 1_000 + 9 * 3_600, continuous: 9 * 3_600, bootSession: "B")))
        XCTAssertEqual(r.keeping(session: b), AwakeReminders())
        r = AwakeReminders()
        XCTAssertEqual(r.keeping(session: a), AwakeReminders())
    }
}
