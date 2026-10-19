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
                       "Held by Terminal (2), the command line, and Xcode")
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
                       "Snaptic couldn’t keep your Mac awake. Try again, or restart Snaptic.")
        for silent: AwakeEndReason in [.user, .replaced, .triggerEnded, .moduleStopped, .safeMode, .reboot] {
            XCTAssertNil(AwakeEndText.toast(silent, floor: 20, appName: nil, lockedHours: nil), silent.rawValue)
        }
        for reason in AwakeEndReason.allCases {
            XCTAssertFalse(AwakeEndText.phrase(reason, floor: 20, appName: nil, lockedHours: nil).isEmpty)
        }
    }

    /// 0.3.1 B3.3: the session ended because lid-closed mode turned off with the lid shut.
    func testLidEndedText() {
        XCTAssertEqual(AwakeEndText.toast(.lidEnded, floor: 20, appName: nil, lockedHours: nil),
                       "Awake ended: lid-closed mode turned off while the lid was closed.")
        XCTAssertEqual(AwakeEndText.lastEnd(.lidEnded, clock: "3:12 AM", floor: 20, lockedHours: nil),
                       "Ended at 3:12 AM: lid-closed mode turned off while the lid was closed.")
        XCTAssertTrue(AwakeEndText.isInterruption(.lidEnded))
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
            "Awake kill switches: none",
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

    /// Review7 security N1: the kill switches that are set are listed by id, unkillable ones dropped, so a deployed
    /// `Awake.disable.history` reads differently from History turned off by the user.
    func testDiagnosticsListsAwakeKillSwitches() {
        let f = AwakeDiagnosticsFacts(effective: [.sessions], governing: nil, kind: nil, assertion: .off,
                                      assertionErrors: 0, guardHolding: nil, activeServices: [], holds: 0, rules: 0,
                                      conditionsByKind: [:], eventCounts: [:], drives: 0,
                                      killSwitches: [.history, .pointerNudge, .batteryGuard, .sessions])
        XCTAssertEqual(f.killSwitches, [.history, .pointerNudge])
        XCTAssertTrue(AwakeDiagnosticsReport.lines(f).contains("Awake kill switches: history, pointerNudge"))
        for feature in AwakeFeature.allCases {
            let one = AwakeDiagnosticsFacts(effective: [], governing: nil, kind: nil, assertion: .off,
                                            assertionErrors: 0, guardHolding: nil, activeServices: [], holds: 0,
                                            rules: 0, conditionsByKind: [:], eventCounts: [:], drives: 0,
                                            killSwitches: [feature])
            let line = AwakeDiagnosticsReport.lines(one).first { $0.hasPrefix("Awake kill switches: ") }
            XCTAssertEqual(line, "Awake kill switches: "
                           + (AwakeFeatureGraph.unkillable.contains(feature) ? "none" : feature.rawValue))
        }
    }

    // MARK: Settings status row

    private func facts(_ g: AwakeGoverning, holds: Bool = false, rules: Bool = false, paused: Bool = false) -> AwakeStatusRowFacts {
        AwakeStatusRowFacts(governing: g, holdsExist: holds, rulesExist: rules, rulesPaused: paused)
    }

    func testStatusButtons() {
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive)), [.keepAwake])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive, rules: true)), [.pauseRules, .keepAwake])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive, rules: true, paused: true)), [.resumeRules, .keepAwake])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.manual(session(.indefinite)))), [.options, .turnOff])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.trigger(top), rules: true)), [.pauseRules, .options, .turnOff])
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.holds([hold]), holds: true)), [.keepAwake, .turnOff],
                       "holds only: start a session beside the holds (parity P4); Turn Off ends them (R5-10)")
        XCTAssertEqual(AwakeStatusPlan.buttons(facts(.inactive, paused: true)), [.keepAwake], "no rule: no pause slot")
        for g: AwakeGoverning in [.inactive, .manual(session(.indefinite)), .trigger(top), .holds([hold])] {
            for rules in [false, true] {
                let b = AwakeStatusPlan.buttons(facts(g, rules: rules))
                let holdsOnly: Bool
                if case .holds = g { holdsOnly = true } else { holdsOnly = false }
                XCTAssertEqual(b.contains(.keepAwake), !g.isActive || holdsOnly, "a start is offered idle and beside holds")
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

    func testStatusRowExplainsTheClosedLidRoute() {
        var i = AwakeDetailInput(governing: .manual(session(.indefinite)), now: now(0))
        XCTAssertFalse(AwakeStatusText.details(i, pausedUntilClock: nil).contains(AwakeStatusText.lidRoute))
        i.lidWarning = true
        let details = AwakeStatusText.details(i, pausedUntilClock: nil)
        XCTAssertEqual(details.suffix(2), ["Closing the lid will put your Mac to sleep.", AwakeStatusText.lidRoute])
        XCTAssertFalse(AwakeDetail.lines(i).contains(AwakeStatusText.lidRoute), "the menu header stays at 2 lines")
    }

    // MARK: Background stop and feature locks (round-2 F2, ux N2)

    func testBackgroundTextNamesOnlyWhatIsInUse() {
        XCTAssertNil(AwakeBackgroundText.unreadableToast(activity: false, drives: false))
        XCTAssertEqual(AwakeBackgroundText.unreadableToast(activity: true, drives: true),
                       "Snaptic can’t read the battery level, so it stopped appearing active and keeping drives awake.")
        XCTAssertEqual(AwakeBackgroundText.unreadableToast(activity: false, drives: true),
                       "Snaptic can’t read the battery level, so it stopped keeping drives awake.")
        XCTAssertNil(AwakeBackgroundText.paused(nil, activity: true, drives: true))
        XCTAssertNil(AwakeBackgroundText.paused(.heat, activity: false, drives: false))
        XCTAssertEqual(AwakeBackgroundText.paused(.batteryUnreadable, activity: true, drives: false),
                       "Appear active is paused: Snaptic can’t read the battery level.")
        XCTAssertEqual(AwakeBackgroundText.paused(.heat, activity: true, drives: true),
                       "Appear active and Drive Alive are paused: your Mac is too hot.")
    }

    func testBackgroundPausedLineIsShownActiveAndIdle() {
        let now = ClockNow(wall: 1_000, continuous: 100, bootSession: "B")
        let s = AwakeClock.start(.indefinite, options: AwakeSessionOptions(), presetID: nil, source: .menu, now: now,
                                 id: StableID())
        let line = "Appear active is paused: the battery is low."
        var i = AwakeDetailInput(governing: .manual(s), now: now, activity: .declare, backgroundPaused: line)
        XCTAssertEqual(AwakeDetail.lines(i), ["Until turned off", line], "explains instead of “Appearing active”")
        i.governing = .inactive
        XCTAssertTrue(AwakeStatusText.details(i, pausedUntilClock: nil).contains(line), "Drive Alive runs idle too")
    }

    func testFeatureLocks() {
        XCTAssertEqual(AwakeFeatureLock.of(.triggers, killSwitches: [], safeMode: true), .safeMode)
        XCTAssertNil(AwakeFeatureLock.of(.shortcuts, killSwitches: [], safeMode: true), "Safe Mode keeps shortcuts")
        XCTAssertEqual(AwakeFeatureLock.of(.activity, killSwitches: [.activity], safeMode: true), .killSwitch,
                       "a kill switch outlasts Safe Mode: named first")
        XCTAssertNil(AwakeFeatureLock.of(.sessions, killSwitches: [.sessions], safeMode: false), "unkillable")
        XCTAssertEqual(AwakeFeatureLock.first([.pointerNudge, .activity], killSwitches: [.activity], safeMode: false)?.feature,
                       .activity)
        XCTAssertEqual(AwakeFeatureLock.killSwitch.text, DefaultsLock.text)
        XCTAssertEqual(AwakeFeatureLock.safeMode.text, "Paused in Safe Mode.")
        for f in AwakeFeatureGraph.safeModeRemoves {
            XCTAssertEqual(AwakeFeatureLock.of(f, killSwitches: [], safeMode: true), .safeMode)
        }
        XCTAssertFalse(AwakeFeatureLock.safeModeStatus.contains("doesn"), "sessions still work in Safe Mode")
    }
}


// MARK: - 0.3.1: lid-closed mode and the tab style (owner: T-lid-kit; PLAN 0.3.1 A4, B0, B1, B3)

extension AwakePresentationTests {
    private var presets: [StableID] { [id("p1"), id("p2")] }

    private func lid(_ state: LidRowState = .off, takes: Bool = false) -> AwakeLidMenuFacts {
        AwakeLidMenuFacts(state: state, sessionTakesMode: takes, presets: presets)
    }

    private func facts(_ g: AwakeGoverning, lid: AwakeLidMenuFacts?, style: AwakeMenuStyle = .own, holds: Bool = false,
                       rules: Bool = false) -> AwakeMenuFacts {
        var f = AwakeMenuFacts(governing: g, holdsExist: holds, rulesShown: rules, style: style)
        f.lid = lid
        return f
    }

    func testLidRowPlacement() {
        // Idle: the submenu right after the default preset.
        XCTAssertEqual(AwakeMenuModel.rows(facts(.inactive, lid: lid())),
                       [.header, .separator, .startDefault, .lidSubmenu(presets), .startSession, .whileApp, .separator,
                        .settings])
        // Holds only: the same slot.
        XCTAssertEqual(AwakeMenuModel.rows(facts(.holds([hold]), lid: lid(), holds: true)).filter { $0 != .separator },
                       [.header, .turnOff, .startDefault, .lidSubmenu(presets), .startSession, .whileApp, .settings])
        // A menu or Settings session started in this process: the row right after ✓ Keep Display On.
        let timed = AwakeGoverning.manual(session(.duration(seconds: 3_600)))
        XCTAssertEqual(AwakeMenuModel.rows(facts(timed, lid: lid(takes: true), holds: true)).filter { $0 != .separator },
                       [.header, .turnOff, .addTime(seconds: 900), .addTime(seconds: 3_600), .keepDisplayOn,
                        .lidClosed(.off), .endHolds, .startSession, .whileApp, .settings])
        XCTAssertEqual(AwakeMenuModel.rows(facts(timed, lid: lid(.on, takes: true))).filter { $0 != .separator }[5],
                       .lidClosed(.on))
        // Any other governing state: the idle submenu (a hotkey, CLI, launch or restored session; a rule).
        XCTAssertEqual(AwakeMenuModel.rows(facts(timed, lid: lid(takes: false))).filter { $0 != .separator }[5],
                       .lidSubmenu(presets))
        XCTAssertEqual(AwakeMenuModel.rows(facts(.trigger(top), lid: lid(takes: true))).filter { $0 != .separator },
                       [.header, .turnOff, .keepDisplayOn, .lidSubmenu(presets), .startSession, .whileApp, .settings])
        XCTAssertEqual(AwakeMenuModel.rows(facts(.inactive, lid: lid(takes: true)))[3], .lidSubmenu(presets),
                       "idle: always the submenu")
        // Pending and finishing rows take the same slot, disabled.
        for state in [LidRowState.authorizing, .verifying, .stopping, .finishingEarlier] {
            XCTAssertEqual(AwakeMenuModel.rows(facts(.inactive, lid: lid(state)))[3], .lidClosed(state), "\(state)")
            XCTAssertEqual(AwakeMenuModel.rows(facts(timed, lid: lid(state, takes: true))).filter { $0 != .separator }[5],
                           .lidClosed(state), "\(state)")
        }
        // Unavailable: no lid row anywhere.
        for g in [AwakeGoverning.inactive, timed, .trigger(top), .holds([hold])] {
            XCTAssertFalse(AwakeMenuModel.rows(facts(g, lid: nil)).contains {
                if case .lidClosed = $0 { return true }
                if case .lidSubmenu = $0 { return true }
                return false
            })
        }
        XCTAssertNil(AwakeMenuModel.lidRow(nil, governing: .inactive))
    }

    /// A4: `tab` is `own` without Awake Settings… (and the separator before it); `compact` has the lid rows too.
    func testTabAndCompactStyles() {
        var rng = SeededGenerator(seed: 0x7AB)
        let states: [AwakeGoverning] = [.inactive, .manual(session(.indefinite)), .manual(session(.duration(seconds: 600))),
                                        .trigger(top), .holds([hold])]
        let lids: [AwakeLidMenuFacts?] = [nil, lid(), lid(.on, takes: true), lid(.verifying), lid(takes: true)]
        for _ in 0..<500 {
            let g = states[Int(rng.next() % 5)], l = lids[Int(rng.next() % 5)]
            let holds = rng.next() % 2 == 0, rules = rng.next() % 2 == 0
            let own = AwakeMenuModel.rows(facts(g, lid: l, style: .own, holds: holds, rules: rules))
            let tab = AwakeMenuModel.rows(facts(g, lid: l, style: .tab, holds: holds, rules: rules))
            let compact = AwakeMenuModel.rows(facts(g, lid: l, style: .compact, holds: holds, rules: rules))
            XCTAssertEqual(Array(own.suffix(2)), [.separator, .settings])
            XCTAssertEqual(tab, Array(own.dropLast(2)))
            XCTAssertFalse(tab.contains(.settings))
            XCTAssertNotEqual(tab.last, .separator)
            XCTAssertEqual(compact, own.filter { $0 != .separator && $0 != .settings })
            for rows in [own, tab, compact] {
                XCTAssertEqual(rows.first, .header)
                XCTAssertFalse(zip(rows, rows.dropFirst()).contains { $0 == .separator && $1 == .separator })
                XCTAssertLessThanOrEqual(rows.filter { $0 != .separator }.count, 11)
                // B1: every style shows the lid row exactly once while the mode is available.
                let lidRows = rows.filter { row in
                    switch row {
                    case .lidClosed, .lidSubmenu: return true
                    default: return false
                    }
                }
                XCTAssertEqual(lidRows.count, l == nil ? 0 : 1)
            }
        }
        var f = AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: false, style: .tab)
        XCTAssertFalse(f.compact)
        f.compact = true
        XCTAssertEqual(f.style, .compact)
        f.compact = false
        XCTAssertEqual(f.style, .own)
        XCTAssertEqual(AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: false, compact: true).style,
                       .compact)
    }

    func testLidRowStateAndTitles() {
        let t = "0123456789abcdef0123456789abcdef"
        XCTAssertEqual(AwakeLidMenuFacts.rowState(mode: .off, recovery: .pending), .finishingEarlier)
        XCTAssertEqual(AwakeLidMenuFacts.rowState(mode: .off, recovery: .leftover), .off, "the refusal toast explains")
        XCTAssertEqual(AwakeLidMenuFacts.rowState(mode: .on(token: t, pid: 5, until: 9), recovery: .pending), .on)
        XCTAssertEqual(AwakeLidMenuFacts.rowState(mode: .authorizing(token: t), recovery: .nothing), .authorizing)
        XCTAssertEqual(AwakeLidMenuFacts.rowState(mode: .failed(.spawn), recovery: .nothing), .off)
        let titles: [(LidRowState, String, Bool, Bool)] = [
            (.off, "Keep Awake with the Lid Closed…", true, false),
            (.on, "Keep Awake with the Lid Closed", true, true),
            (.authorizing, "Waiting for Password…", false, false),
            (.verifying, "Turning On…", false, false),
            (.stopping, "Turning Off…", false, false),
            (.finishingEarlier, "Finishing Earlier Session…", false, false),
        ]
        for (state, title, enabled, checked) in titles {
            XCTAssertEqual(AwakeLidText.rowTitle(state), title)
            XCTAssertEqual(AwakeLidText.rowEnabled(state), enabled, title)
            XCTAssertEqual(AwakeLidText.rowChecked(state), checked, title)
        }
        XCTAssertEqual(AwakeLidText.title, "Keep Awake with the Lid Closed")
        XCTAssertEqual(AwakeLidText.presetTitle("For 1 Hour"), "For 1 Hour…")
        XCTAssertEqual(AwakeLidText.custom, "Custom…")
        XCTAssertEqual(AwakeLidText.setting, "Keep awake with the lid closed")
        XCTAssertEqual(AwakeLidText.settingHelp,
                       "Choose Keep Awake with the Lid Closed in the Awake menu. Asks for an administrator password each time.")
        XCTAssertEqual(AwakeLidText.customHelp, "Asks for an administrator password when you click Start.")
        XCTAssertEqual(AwakeLidText.customStart, "Start…")
        XCTAssertEqual(AwakeLidText.advancedFooter,
                       "While lid-closed mode is on, your Mac can’t sleep for low battery or heat. Awake turns it off at the Awake page’s battery level (at least 10%), when your Mac gets hot, or after 24 hours. Use it on a hard surface, not in a bag.")
        XCTAssertEqual(AwakeLidText.translocated,
                       "Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode.")
    }

    /// B1: the lid line is the first extra while the mode is on; the cap's clock when the cap ends first.
    func testLidHeaderPriority() {
        let s = session(.untilIdle(UntilIdleSpec(), maxSeconds: 7_200))
        var i = AwakeDetailInput(governing: .manual(s), now: now(0), nextRuleName: "Desk", holderSummary: "Held by Terminal",
                                 activity: .declare, lidWarning: true)
        XCTAssertFalse(AwakeDetail.extras(i).contains { $0.hasPrefix("Stays awake") })
        XCTAssertTrue(AwakeDetail.extras(i).contains("Closing the lid will put your Mac to sleep."))
        i.lidModeOn = true
        let extras = AwakeDetail.extras(i)
        XCTAssertEqual(extras.first, "Stays awake with the lid closed")
        XCTAssertFalse(extras.contains("Closing the lid will put your Mac to sleep."), "no warning while on")
        XCTAssertEqual(AwakeDetail.lines(i).last, "Stays awake with the lid closed", "it wins the header's second line")
        i.lidUntilClock = "6:40 PM"
        XCTAssertEqual(AwakeDetail.lines(i).last, "Stays awake with the lid closed until 6:40 PM")
        XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil).dropFirst().first,
                       "Stays awake with the lid closed until 6:40 PM", "after the time left in Settings")
        XCTAssertFalse(AwakeStatusText.details(i, pausedUntilClock: nil).contains { $0.hasPrefix("To keep it awake") })
        var idle = AwakeDetailInput(governing: .inactive, now: now(0))
        idle.lidModeOn = true
        XCTAssertEqual(AwakeDetail.extras(idle), [], "nothing governs: no lid line")
    }

    func testLidWarningRule() {
        for willSleep in [nil, false, true] as [Bool?] {
            for on in [false, true] {
                for battery in [false, true] {
                    for external in [false, true] {
                        XCTAssertEqual(AwakeDetail.showsLidWarning(lidWillSleep: willSleep, lidModeOn: on, onBattery: battery,
                                                                   externalDisplay: external),
                                       willSleep == true && !on && (battery || !external))
                    }
                }
            }
        }
    }

    func testLidRouteVariants() {
        XCTAssertEqual(AwakeStatusText.lidRoute(.featureOff),
                       "To keep it awake with the lid closed, connect power and an external display, or turn on lid-closed mode in Awake › Advanced.")
        XCTAssertEqual(AwakeStatusText.lidRoute(.available),
                       "To keep it awake with the lid closed, connect power and an external display, or choose Keep Awake with the Lid Closed in the Awake menu.")
        XCTAssertEqual(AwakeStatusText.lidRoute(.unavailable),
                       "To keep it awake with the lid closed, connect power and an external display.")
        XCTAssertEqual(AwakeStatusText.lidRoute(.unavailable), AwakeStatusText.lidRoute, "the 0.3 text, unchanged")
        for route in AwakeLidRoute.allCases {
            var i = AwakeDetailInput(governing: .manual(session(.indefinite)), now: now(0), lidWarning: true, lidRoute: route)
            XCTAssertEqual(AwakeStatusText.details(i, pausedUntilClock: nil).last, AwakeStatusText.lidRoute(route))
            i.lidModeOn = true
            XCTAssertFalse(AwakeStatusText.details(i, pausedUntilClock: nil).contains(AwakeStatusText.lidRoute(route)))
        }
    }

    func testLidStatusSuffix() {
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .manual(session(.indefinite)), remaining: nil,
                                                             appName: nil, ruleName: nil, holderSummary: nil, lidModeOn: true),
                       "Awake, until turned off, even with the lid closed")
        XCTAssertEqual(AwakeIndicatorText.accessibilityLabel(governing: .inactive, remaining: nil, appName: nil,
                                                             ruleName: nil, holderSummary: nil, lidModeOn: true),
                       "Awake, off")
        XCTAssertEqual(AwakeLidText.statusSuffix, ", even with the lid closed")
        XCTAssertEqual(AwakeLidText.voiceOverOn, "Keeping your Mac awake with the lid closed.")
        XCTAssertEqual(AwakeLidText.voiceOverOff, "Lid-closed mode turned off.")
    }

    func testLidEndLinesAndToasts() {
        let lines: [AwakeLidEnd: String] = [
            .battery: "Lid-closed mode ended at 3:12 AM: battery at 20%.",
            .heat: "Lid-closed mode ended at 3:12 AM: your Mac got hot.",
            .cap: "Lid-closed mode ended at 3:12 AM: time limit reached.",
            .otherApp: "Lid-closed mode ended at 3:12 AM: another app turned sleep back on.",
            .quit: "Lid-closed mode ended at 3:12 AM: Snaptic quit.",
        ]
        for end in AwakeLidEnd.allCases {
            XCTAssertEqual(AwakeLidText.lastEnd(end, clock: "3:12 AM", floor: 20), lines[end], "\(end)")
        }
        let toasts: [AwakeLidEnd: String] = [
            .cap: "Lid-closed mode turned off after 24 hours. Awake is still on; your Mac sleeps if you close the lid.",
            .battery: "Lid-closed mode turned off at 20% battery.",
            .heat: "Lid-closed mode turned off because your Mac got hot.",
            .otherApp: "Another app turned sleep back on, so lid-closed mode stopped.",
        ]
        for end in AwakeLidEnd.allCases {
            XCTAssertEqual(AwakeLidText.endToast(end, floor: 20), toasts[end], "\(end)")
        }
        XCTAssertEqual(AwakeLidText.capSpan, "24 hours")
        XCTAssertEqual(AwakeCountdown.unit(1, "hour", "hours"), "1 hour", "the singular rule stays")
        XCTAssertEqual(AwakeLidText.capWarning,
                       "Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep.")
        XCTAssertEqual(AwakeLidText.verifying, "Turning on lid-closed mode…")
        XCTAssertEqual(AwakeLidText.couldNotTurnOn, "Snaptic couldn’t turn on lid-closed mode. Try again.")
        XCTAssertEqual(AwakeLidText.alreadyOff,
                       "Sleep is already turned off for this Mac by another app or command, so it stays awake with the lid closed.")
        XCTAssertEqual(AwakeLidText.replaced, "Replaced the running session.")
        XCTAssertEqual(AwakeEndText.toast(.lidEnded, floor: 20, appName: nil, lockedHours: nil),
                       "Awake ended: lid-closed mode turned off while the lid was closed.")
    }

    func testLeftoverTexts() {
        XCTAssertEqual(AwakeLidText.menuLeftover, "Sleep Is Turned Off")
        XCTAssertEqual(AwakeLidText.turnSleepBackOn, "Turn Sleep Back On…")
        XCTAssertEqual(AwakeLidText.leftover,
                       "Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish.")
        XCTAssertEqual(AwakeLidText.keepSleepOff, "Keep Sleep Off")
        XCTAssertEqual(AwakeLidText.notNow, "Not Now")
        XCTAssertEqual(AwakeLidText.openAwakeSettings, "Open Awake Settings…")
        XCTAssertEqual(OtherAssertions.sleepDisabledByOther,
                       "Sleep is turned off for this Mac by another app or command. Snaptic leaves it as it is.")
        XCTAssertEqual(AwakeLidText.historySuffix, " · Lid closed")
    }
}

// MARK: - 0.3.1: the shapes T-lid-app wires (owner: T-lid-kit)

extension AwakePresentationTests {
    func testMenuFactsWithLid() {
        let p = [id("p1")]
        let made = AwakeLidMenuFacts.make(available: true, mode: .off, recovery: .nothing, sessionTakesMode: false, presets: p)
        XCTAssertEqual(made, AwakeLidMenuFacts(state: .off, sessionTakesMode: false, presets: p))
        XCTAssertNil(AwakeLidMenuFacts.make(available: false, mode: .off, recovery: .pending, sessionTakesMode: true,
                                            presets: p))
        XCTAssertEqual(AwakeLidMenuFacts.make(available: true, mode: .off, recovery: .pending, sessionTakesMode: false,
                                              presets: p)?.state, .finishingEarlier)
        let f = AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: false, style: .tab, lid: made)
        XCTAssertEqual(AwakeMenuModel.rows(f), [.header, .separator, .startDefault, .lidSubmenu(p), .startSession, .whileApp])
        XCTAssertNil(AwakeMenuFacts(governing: .inactive, holdsExist: false, rulesShown: false, style: .own).lid)
        XCTAssertEqual(LidRowState.finishingEarlier.rawValue, "finishingEarlier")
    }

    func testLidLastEndLine() {
        let ended = AwakeLidText.lastEnd(.battery, clock: "3:12 AM", floor: 20)
        // Idle: after the idle note, within the header's two lines.
        let idle = AwakeDetailInput(governing: .inactive, now: now(0), idleNote: "Ended at 3:12 AM: time is up.",
                                    lidLastEnd: ended)
        XCTAssertEqual(AwakeDetail.lines(idle), ["Ended at 3:12 AM: time is up.", "Lid-closed mode ended at 3:12 AM: battery at 20%."])
        XCTAssertEqual(AwakeStatusText.details(idle, pausedUntilClock: nil).last, ended)
        let alone = AwakeDetailInput(governing: .inactive, now: now(0), lidLastEnd: ended)
        XCTAssertEqual(AwakeDetail.lines(alone), [ended ?? ""])
        // A session that goes on: the first extra.
        var active = AwakeDetailInput(governing: .manual(session(.indefinite)), now: now(0), activity: .declare,
                                      lidLastEnd: ended)
        XCTAssertEqual(AwakeDetail.lines(active).last, ended)
        active.lidModeOn = true
        XCTAssertFalse(AwakeDetail.extras(active).contains(ended ?? "-"), "cleared at the next turn-on")
        XCTAssertEqual(AwakeDetail.extras(active).first, "Stays awake with the lid closed")
    }

    func testDiagnosticsLidLine() {
        var f = AwakeDiagnosticsFacts(effective: [], governing: nil, kind: nil, assertion: .off, assertionErrors: 0,
                                      guardHolding: nil, activeServices: [], holds: 0, rules: 0, conditionsByKind: [:],
                                      eventCounts: [:], drives: 0)
        XCTAssertFalse(AwakeDiagnosticsReport.lines(f).contains { $0.contains("lid") }, "unchanged without the feature")
        f.lid = .on
        XCTAssertTrue(AwakeDiagnosticsReport.lines(f).contains("Awake lid-closed mode: on"))
        f.lid = nil
        f.lidLeftover = true
        XCTAssertTrue(AwakeDiagnosticsReport.lines(f).contains("Awake lid-closed mode: unavailable (leftover)"))
        let g = AwakeDiagnosticsFacts(effective: [], governing: nil, kind: nil, assertion: .off, assertionErrors: 0,
                                      guardHolding: nil, activeServices: [], holds: 0, rules: 0, conditionsByKind: [:],
                                      eventCounts: [:], drives: 0, lid: .verifying, lidLeftover: false)
        XCTAssertTrue(AwakeDiagnosticsReport.lines(g).contains("Awake lid-closed mode: verifying"))
    }

    func testLidGlyph() {
        for g in AwakeGlyphFamily.allCases {
            XCTAssertNil(g.lidActiveSymbol, "no family has its own lid symbol: the app draws the bar")
            var c = AwakeIndicatorConfig()
            c.glyph = g
            XCTAssertNil(c.lidSymbol())
            XCTAssertEqual(c.symbol(active: true), g.active, "the bar goes under the active glyph")
        }
        XCTAssertTrue(AwakeGlyphFamily.lidBarHeightRatio > 0 && AwakeGlyphFamily.lidBarHeightRatio < 0.5)
    }
}
