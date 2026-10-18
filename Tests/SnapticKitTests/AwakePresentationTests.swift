import XCTest
@testable import SnapticKit

final class AwakePresentationTests: XCTestCase {
    private let boot = "BOOT-A"
    private func now(_ continuous: Double) -> ClockNow {
        ClockNow(wall: 1_000_000 + continuous, continuous: continuous, bootSession: boot)
    }
    private func id(_ n: String) -> StableID { StableID.derived(namespace: "test", name: n) }
    private func session(_ kind: AwakeSessionKind) -> AwakeSession {
        AwakeClock.start(kind, options: AwakeSessionOptions(), presetID: nil, source: .menu, now: now(0), id: id("s"))
    }
    private var top: TriggerTop { TriggerTop(id: id("r"), index: 0, options: AwakeSessionOptions(), since: 0) }
    private var hold: AwakeHold {
        AwakeClock.hold(.process(pid: 50, startTime: 1), capSeconds: 600, now: now(0), id: id("h"))
    }

    // MARK: Holders

    func testHolderSummary() {
        XCTAssertNil(AwakeHolderText.summary([]))
        XCTAssertEqual(AwakeHolderText.summary(["Terminal"]), "Held by Terminal")
        XCTAssertEqual(AwakeHolderText.summary(["Terminal", "Terminal"]), "Held by Terminal (2)")
        XCTAssertEqual(AwakeHolderText.summary(["Terminal", "Xcode"]), "Held by Terminal and Xcode")
        XCTAssertEqual(AwakeHolderText.summary(["Terminal", nil, "Xcode", "Terminal"]),
                       "Held by Terminal (2), the command line and Xcode")
        XCTAssertEqual(AwakeHolderText.summary([nil, ""]), "Held by the command line (2)")
        XCTAssertEqual(AwakeHolderText.stillKeeping(["Terminal", "Terminal"]), "Terminal is still keeping your Mac awake.")
        XCTAssertEqual(AwakeHolderText.stillKeeping(["Terminal", "Xcode"]),
                       "Terminal and Xcode are still keeping your Mac awake.")
        XCTAssertEqual(AwakeHolderText.stillKeeping([nil]), "The command line is still keeping your Mac awake.")
    }

    // MARK: End texts

    func testEndToasts() {
        XCTAssertEqual(AwakeEndText.toast(.batteryLow, floor: 20, appName: nil, lockedHours: nil),
                       "Awake ended: battery is below 20%.")
        XCTAssertEqual(AwakeEndText.toast(.appQuit, floor: 20, appName: "Xcode", lockedHours: nil), "Awake ended: Xcode quit.")
        XCTAssertEqual(AwakeEndText.toast(.appQuit, floor: 20, appName: nil, lockedHours: nil), "Awake ended: the app quit.")
        XCTAssertEqual(AwakeEndText.toast(.tasksFinished, floor: 20, appName: nil, lockedHours: nil),
                       "Awake ended: downloads and tasks finished.")
        XCTAssertEqual(AwakeEndText.toast(.lockedTooLong, floor: 20, appName: nil, lockedHours: 4),
                       "Awake ended: the screen was locked for 4 hours.")
        XCTAssertEqual(AwakeEndText.toast(.assertionFailed, floor: 20, appName: nil, lockedHours: nil),
                       "Snaptic couldn't keep your Mac awake. Try again, or restart Snaptic.")
        for silent: AwakeEndReason in [.user, .replaced, .triggerEnded, .moduleStopped, .safeMode, .reboot] {
            XCTAssertNil(AwakeEndText.toast(silent, floor: 20, appName: nil, lockedHours: nil), silent.rawValue)
        }
        for reason in AwakeEndReason.allCases {
            XCTAssertFalse(AwakeEndText.phrase(reason, floor: 20, appName: nil, lockedHours: nil).isEmpty)
        }
    }

    func testLastEndOnlyForInterruptions() {
        XCTAssertEqual(AwakeEndText.lastEnd(.batteryLow, clock: "3:12 AM", floor: 20, lockedHours: nil),
                       "Ended at 3:12 AM: battery below 20%.")
        XCTAssertTrue(AwakeEndText.isInterruption(.thermal))
        XCTAssertTrue(AwakeEndText.isInterruption(.commandLineOff))
        XCTAssertFalse(AwakeEndText.isInterruption(.timeUp))
        XCTAssertFalse(AwakeEndText.isInterruption(.user))
        XCTAssertEqual(AwakeEndText.holding(.batteryLow, floor: 20), "Ended because the battery is below 20%.")
        XCTAssertNil(AwakeEndText.holding(.timeUp, floor: 20))
        XCTAssertEqual(AwakeEndText.refusal(.batteryLow, floor: 20), "Battery is below 20%.")
    }

    // MARK: Detail lines

    func testPrimaryLines() {
        let t = session(.duration(seconds: 4_320))
        var i = AwakeDetailInput(governing: .manual(t), now: now(0), endClock: "3:45 PM")
        XCTAssertEqual(AwakeDetail.lines(i), ["Until 3:45 PM · 1h 12m left"])
        i.governing = .manual(session(.indefinite))
        XCTAssertEqual(AwakeDetail.lines(i), ["Until turned off"])
        i.governing = .manual(session(.whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: nil)))
        i.appName = "Xcode"
        XCTAssertEqual(AwakeDetail.lines(i), ["While Xcode is running"])
        i.governing = .manual(session(.whileApp(bundleID: "com.apple.dt.Xcode", maxSeconds: 3_600)))
        XCTAssertEqual(AwakeDetail.lines(i), ["While Xcode is running · at most 1h left"])
        i.governing = .trigger(top)
        i.ruleName = "Desk dock"
        XCTAssertEqual(AwakeDetail.lines(i), ["While “Desk dock” applies"])
        i.governing = .holds([hold])
        i.holderSummary = "Held by Terminal (2)"
        XCTAssertEqual(AwakeDetail.lines(i), ["Held by Terminal (2)"], "holds-only: the summary is the primary line")
        i.governing = .inactive
        XCTAssertEqual(AwakeDetail.lines(i), [], "no detail at rest")
        i.idleNote = "Ended at 3:12 AM: battery below 20%."
        XCTAssertEqual(AwakeDetail.lines(i), ["Ended at 3:12 AM: battery below 20%."])
    }

    func testExtrasInPriorityOrderAndCapped() {
        let idle = session(.untilIdle(UntilIdleSpec(), maxSeconds: nil))
        var i = AwakeDetailInput(governing: .manual(idle), now: now(0), nextRuleName: "Desk dock",
                                 holderSummary: "Held by Terminal", quietFor: 130, activity: .declare, lidWarning: true)
        XCTAssertEqual(AwakeDetail.lines(i), ["Until downloads and tasks finish",
                                              "Ends after 5 min with no activity · quiet for 2 min"])
        XCTAssertEqual(AwakeDetail.extras(i), ["Ends after 5 min with no activity · quiet for 2 min",
                                               "Then “Desk dock” keeps it awake.", "Held by Terminal", "Appearing active",
                                               "Closing the lid will put your Mac to sleep."])
        i.quietFor = nil
        XCTAssertEqual(AwakeDetail.extras(i).first, "Ends after 5 min with no activity")
        i.governing = .trigger(top)
        i.activityCapped = true
        XCTAssertEqual(AwakeDetail.extras(i), ["Held by Terminal", "Stopped appearing active after 1 hour.",
                                               "Closing the lid will put your Mac to sleep."],
                       "a rule session has no Then line")
        i.governing = .holds([hold])
        XCTAssertFalse(AwakeDetail.extras(i).contains("Held by Terminal"), "already the primary line")
        XCTAssertLessThanOrEqual(AwakeDetail.lines(i).count, AwakeDetail.maxLines)
    }

    // MARK: Indicator

    func testIndicatorTitles() {
        let t = session(.duration(seconds: 6_120))
        XCTAssertNil(AwakeIndicatorText.title(style: .icon, governing: .manual(t), remaining: 6_120, endClock: "5:00 PM"))
        XCTAssertEqual(AwakeIndicatorText.title(style: .iconAndTime, governing: .manual(t), remaining: 6_120,
                                                endClock: "5:00 PM"), "1h 42m")
        XCTAssertEqual(AwakeIndicatorText.title(style: .iconAndEndTime, governing: .manual(t), remaining: 6_120,
                                                endClock: "5:00 PM"), "5:00 PM")
        XCTAssertNil(AwakeIndicatorText.title(style: .iconAndTime, governing: .manual(session(.indefinite)), remaining: nil,
                                              endClock: nil), "indefinite: glyph only")
        XCTAssertNil(AwakeIndicatorText.title(style: .iconAndTime, governing: .trigger(top), remaining: 40, endClock: nil),
                     "automatic: glyph only")
        XCTAssertNil(AwakeIndicatorText.title(style: .iconAndTime, governing: .holds([hold]), remaining: 40, endClock: nil))
    }

    func testIndicatorLabels() {
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .inactive, remaining: nil, appName: nil,
                                                             ruleName: nil, holderSummary: nil), "Awake, off")
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .manual(session(.duration(seconds: 6_120))),
                                                             remaining: 6_120, appName: nil, ruleName: nil,
                                                             holderSummary: nil),
                       "Awake, 1 hour 42 minutes remaining")
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .manual(session(.indefinite)), remaining: nil,
                                                             appName: nil, ruleName: nil, holderSummary: nil),
                       "Awake, until turned off")
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .holds([hold]), remaining: nil, appName: nil,
                                                             ruleName: nil, holderSummary: "Held by Terminal"),
                       "Awake, held by Terminal")
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .trigger(top), remaining: nil, appName: nil,
                                                             ruleName: "Desk dock", holderSummary: nil),
                       "Awake, while “Desk dock” applies")
    }

    // MARK: Menu rows

    func testIdleRows() {
        let f = AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: true, compact: false)
        XCTAssertEqual(AwakeMenuModel.rows(f), [.header, .separator, .startDefault, .startSession, .whileApp, .separator,
                                                .rules, .separator, .settings], "6 items with a rule (§5.3)")
        let without = AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: false, compact: false)
        XCTAssertEqual(AwakeMenuModel.rows(without).filter { $0 != .separator }.count, 5)
    }

    func testActiveTimedRows() {
        let s = session(.duration(seconds: 3_600))
        let f = AwakeMenuFacts(governing: .manual(s), holdsExist: false, rulesShown: true, compact: false)
        XCTAssertEqual(AwakeMenuModel.rows(f).filter { $0 != .separator },
                       [.header, .turnOff, .addTime(seconds: 900), .addTime(seconds: 3_600), .keepDisplayOn,
                        .startSession, .whileApp, .rules, .settings], "9 rows with a rule (§5.3)")
        let indefinite = AwakeMenuFacts(governing: .manual(session(.indefinite)), holdsExist: true, rulesShown: false,
                                        compact: false)
        XCTAssertEqual(AwakeMenuModel.rows(indefinite).filter { $0 != .separator },
                       [.header, .turnOff, .keepDisplayOn, .endHolds, .startSession, .whileApp, .settings],
                       "no Add Time for an indefinite session; End Command-Line Holds under another source")
    }

    func testHoldsOnlyAndRuleRows() {
        let holdsOnly = AwakeMenuFacts(governing: .holds([hold]), holdsExist: true, rulesShown: false, compact: false)
        let rows = AwakeMenuModel.rows(holdsOnly)
        XCTAssertTrue(rows.contains(.turnOff))
        XCTAssertTrue(rows.contains(.startDefault), "starting adds a session beside the holds")
        XCTAssertFalse(rows.contains(.endHolds), "R5-10: Turn Off only")
        XCTAssertFalse(rows.contains(.keepDisplayOn))
        let rule = AwakeMenuFacts(governing: .trigger(top), holdsExist: false, rulesShown: true, compact: false)
        XCTAssertEqual(AwakeMenuModel.rows(rule).filter { $0 != .separator },
                       [.header, .turnOff, .keepDisplayOn, .startSession, .whileApp, .rules, .settings])
    }

    func testCompactSection() {
        let f = AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: true, compact: true)
        XCTAssertEqual(AwakeMenuModel.rows(f), [.header, .startDefault, .startSession, .whileApp, .rules],
                       "§5.4: no separators, no Settings item, Rules at rest")
        let active = AwakeMenuFacts(governing: .manual(session(.duration(seconds: 3_600))), holdsExist: false,
                                    rulesShown: false, compact: true)
        XCTAssertFalse(AwakeMenuModel.rows(active).contains(.separator))
        XCTAssertFalse(AwakeMenuModel.rows(active).contains(.settings))
    }

    func testRowsNeverDoubleSeparators() {
        var rng = SeededGenerator(seed: 0x3E7)
        let states: [AwakeGoverning] = [.inactive, .manual(session(.indefinite)), .manual(session(.duration(seconds: 600))),
                                        .trigger(top), .holds([hold])]
        for _ in 0..<500 {
            let f = AwakeMenuFacts(governing: states[Int(rng.next() % 5)], holdsExist: rng.next() % 2 == 0,
                                   rulesShown: rng.next() % 2 == 0, compact: rng.next() % 2 == 0)
            let rows = AwakeMenuModel.rows(f)
            XCTAssertEqual(rows.first, .header)
            XCTAssertNotEqual(rows.last, .separator)
            XCTAssertFalse(zip(rows, rows.dropFirst()).contains { $0 == .separator && $1 == .separator })
            XCTAssertEqual(rows.contains(.turnOff), f.governing.isActive)
            XCTAssertLessThanOrEqual(rows.filter { $0 != .separator }.count, 10)
        }
    }

    // MARK: Rules submenu

    func testRulesMenuSelection() {
        let triggers = (0..<8).map { n -> AwakeTrigger in
            var t = AwakeTrigger(id: id("r\(n)"), name: "R\(n)", criteria: [AwakeCriterionEntry(.power(.onAdapter))])
            t.enabled = n != 2
            return t
        }
        let v = AwakeRulesMenu.visible(triggers, active: [id("r6")], waiting: [id("r1")])
        XCTAssertEqual(v.map(\.id), [id("r0"), id("r1"), id("r2"), id("r3"), id("r6")], "active + ≤ 4 others, in order")
        XCTAssertEqual(v.map(\.state), [.idle, .waiting, .off, .idle, .active])
        XCTAssertEqual(AwakeRulesMenu.subtitle(pausedUntilClock: "4:00 PM", activeName: "Desk dock", waitingName: nil),
                       "Paused until 4:00 PM", "R5-11: paused wins")
        XCTAssertEqual(AwakeRulesMenu.subtitle(pausedUntilClock: nil, activeName: "Desk dock", waitingName: "X"),
                       "Desk dock is active")
        XCTAssertEqual(AwakeRulesMenu.subtitle(pausedUntilClock: nil, activeName: nil, waitingName: "Desk dock"),
                       "Waiting for Desk dock")
        XCTAssertNil(AwakeRulesMenu.subtitle(pausedUntilClock: nil, activeName: nil, waitingName: nil))
    }

    // MARK: Diagnostics

    func testDiagnosticsLinesCarryNoNames() {
        let f = AwakeDiagnosticsFacts(effective: [.sessions, .indicator], governing: .manual, kind: .duration,
                                      assertion: .display, assertionErrors: 0, guardHolding: nil,
                                      activeServices: [.assertions, .power], holds: 2, rules: 3,
                                      conditionsByKind: [.app: 2, .power: 1, .usb: 0],
                                      eventCounts: ["awake.hold.started": 2, "awake.session.started.duration": 0],
                                      drives: 1)
        XCTAssertEqual(AwakeDiagnosticsReport.lines(f), [
            "Awake features: indicator, sessions",
            "Awake governing: manual (duration)",
            "Awake assertion: display",
            "Awake guard: none",
            "Awake services: assertions, power",
            "Awake holds: 2",
            "Awake rules: 3 (app 2, power 1)",
            "Awake drives: 1",
            "Awake event awake.hold.started: 2",
        ])
    }

    // MARK: Settings status row

    private func facts(_ g: AwakeGoverning, holds: Bool = false, rules: Bool = false, paused: Bool = false) -> AwakeStatusFacts {
        AwakeStatusFacts(governing: g, holdsExist: holds, rulesExist: rules, rulesPaused: paused)
    }

    func testStatusButtons() {
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive)), [.keepAwake])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive, rules: true)), [.pauseRules, .keepAwake])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive, rules: true, paused: true)), [.resumeRules, .keepAwake])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.manual(session(.indefinite)))), [.options, .turnOff])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.trigger(top), rules: true)), [.pauseRules, .options, .turnOff])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.holds([hold]), holds: true)), [.turnOff], "R5-10: holds only")
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive, paused: true)), [.keepAwake], "no rule: no pause slot")
        for g: AwakeGoverning in [.inactive, .manual(session(.indefinite)), .trigger(top), .holds([hold])] {
            for rules in [false, true] {
                let b = AwakeStatusPlan.buttons(facts(g, rules: rules))
                XCTAssertEqual(b.contains(.keepAwake), !g.isActive)
                XCTAssertEqual(b.contains(.turnOff), g.isActive)
                XCTAssertEqual(b.filter { $0 == .pauseRules || $0 == .resumeRules }.count, rules ? 1 : 0)
            }
        }
    }

    func testStatusOptions() {
        XCTAssertEqual(AwakeStatusPlan.options(facts(.inactive)), [])
        XCTAssertEqual(AwakeStatusPlan.options(facts(.holds([hold]), holds: true)), [])
        XCTAssertEqual(AwakeStatusPlan.options(facts(.manual(session(.duration(seconds: 3_600))))),
                       [.addTime(seconds: 900), .addTime(seconds: 3_600), .addTimeCustom, .separator, .keepDisplayOn,
                        .separator, .replaceWith])
        XCTAssertEqual(AwakeStatusPlan.options(facts(.manual(session(.indefinite)), holds: true)),
                       [.keepDisplayOn, .endHolds, .separator, .replaceWith])
        XCTAssertEqual(AwakeStatusPlan.options(facts(.manual(session(.whileApp(bundleID: "com.apple.Xcode", maxSeconds: nil))))),
                       [.keepDisplayOn, .separator, .replaceWith], "an uncapped app session can't be extended")
        XCTAssertTrue(AwakeStatusPlan.options(facts(.manual(session(.untilIdle(UntilIdleSpec(), maxSeconds: 7_200)))))
            .contains(.addTimeCustom), "a capped task session can")
        XCTAssertEqual(AwakeStatusPlan.options(facts(.trigger(top))), [.keepDisplayOn, .separator, .replaceWith])
    }

    func testStatusText() {
        var i = AwakeDetailInput(governing: .inactive, now: now(0))
        XCTAssertEqual(AwakeStatusText.primary(i), "Your Mac can sleep as usual.")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil), [])
        i.idleNote = "Ended at 3:12 AM: battery below 20%."
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: "4:00 PM"),
                       ["Ended at 3:12 AM: battery below 20%.", "Rules are paused until 4:00 PM."])
        i = AwakeDetailInput(governing: .manual(session(.duration(seconds: 4_320))), now: now(0), endClock: "3:45 PM",
                             activity: .declare)
        XCTAssertEqual(AwakeStatusText.primary(i), "Keeping your Mac awake until 3:45 PM")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil), ["1h 12m left", "Appearing active"])
        i.idleNote = "ignored while active"
        XCTAssertFalse(AwakeStatusText.details(i, pausedUntilClock: nil).contains("ignored while active"))
        i = AwakeDetailInput(governing: .manual(session(.indefinite)), now: now(0))
        XCTAssertEqual(AwakeStatusText.primary(i), "Keeping your Mac awake until turned off")
        i = AwakeDetailInput(governing: .manual(session(.whileApp(bundleID: "com.apple.Xcode", maxSeconds: 3_600))),
                             now: now(0), appName: "Xcode")
        XCTAssertEqual(AwakeStatusText.primary(i), "Keeping your Mac awake while Xcode is running")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil), ["At most 1h left"])
        i = AwakeDetailInput(governing: .manual(session(.untilIdle(UntilIdleSpec(), maxSeconds: nil))), now: now(0))
        XCTAssertEqual(AwakeStatusText.primary(i), "Keeping your Mac awake until downloads and tasks finish")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil).first, "Ends after 5 min with no activity")
        i = AwakeDetailInput(governing: .trigger(top), now: now(0), ruleName: "Desk dock", holderSummary: "Held by Terminal (2)")
        XCTAssertEqual(AwakeStatusText.primary(i), "Keeping your Mac awake while “Desk dock” applies")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil), ["Held by Terminal (2)"])
        i = AwakeDetailInput(governing: .holds([hold]), now: now(0), holderSummary: "Held by Terminal (2)")
        XCTAssertEqual(AwakeStatusText.primary(i), "Held by Terminal (2)")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil), [], "the holders are the primary line")
    }

    func testRuleRowState() {
        XCTAssertEqual(AwakeRuleRowText.state(enabled: false, active: true, waiting: false), "Off")
        XCTAssertEqual(AwakeRuleRowText.state(enabled: true, active: true, waiting: true), "Active")
        XCTAssertEqual(AwakeRuleRowText.state(enabled: true, active: false, waiting: true), "Waiting")
        XCTAssertNil(AwakeRuleRowText.state(enabled: true, active: false, waiting: false))
    }
}
