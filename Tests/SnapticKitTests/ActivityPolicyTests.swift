import XCTest
@testable import SnapticKit

/// ActivityPolicy and IdleMath (PLAN 0.3 §2.9, N10, §6.6).
final class ActivityPolicyTests: XCTestCase {
    /// Everything allows a nudge; tests flip one input at a time.
    private func inputs(mode: AwakeActivityMode = .nudge, nudgeAllowed: Bool = true) -> ActivityInputs {
        ActivityInputs(mode: mode, nudgeAllowed: nudgeAllowed, screenLocked: false, onConsole: true,
                       screensaverRunning: false, displaysAsleep: false, switcherVisible: false,
                       secondsSinceUserInput: 120, activityElapsedSeconds: 30, stopAfterSeconds: 3_600,
                       pointerEdgeDistance: 300)
    }

    // MARK: decide

    func testBaseline() {
        XCTAssertEqual(ActivityPolicy.decide(inputs()), .nudge)
        XCTAssertEqual(ActivityPolicy.decide(inputs(mode: .declare)), .declare)
        XCTAssertEqual(ActivityPolicy.decide(inputs(mode: .off)), .skip)
    }

    func testEverySkipCondition() {
        let skips: [(String, (inout ActivityInputs) -> Void)] = [
            ("locked", { $0.screenLocked = true }),
            ("off console", { $0.onConsole = false }),
            ("screensaver", { $0.screensaverRunning = true }),
            ("displays asleep", { $0.displaysAsleep = true }),
            ("switcher visible", { $0.switcherVisible = true }),
            ("user active", { $0.secondsSinceUserInput = 59 }),
            ("user input NaN", { $0.secondsSinceUserInput = .nan }),
            ("cap reached", { $0.activityElapsedSeconds = 3_600 }),
            ("cap passed", { $0.activityElapsedSeconds = 9_999 }),
            ("elapsed NaN", { $0.activityElapsedSeconds = .nan }),
            ("elapsed negative", { $0.activityElapsedSeconds = -1 }),
            ("stopAfter NaN", { $0.stopAfterSeconds = .nan }),
            ("stopAfter zero", { $0.stopAfterSeconds = 0 }),
        ]
        for mode in [AwakeActivityMode.declare, .nudge] {
            for (name, change) in skips {
                var i = inputs(mode: mode)
                change(&i)
                XCTAssertEqual(ActivityPolicy.decide(i), .skip, "\(mode) \(name)")
            }
        }
    }

    func testIntervalBoundary() {
        var i = inputs()
        i.secondsSinceUserInput = ActivityPolicy.intervalSeconds
        XCTAssertEqual(ActivityPolicy.decide(i), .nudge)
    }

    func testNudgeDegradesToDeclare() {
        let degrades: [(String, (inout ActivityInputs) -> Void)] = [
            ("not allowed", { $0.nudgeAllowed = false }),
            ("no pointer", { $0.pointerEdgeDistance = nil }),
            ("at the edge", { $0.pointerEdgeDistance = ActivityPolicy.edgeMarginPoints }),
            ("in a hot corner", { $0.pointerEdgeDistance = 0 }),
            ("edge NaN", { $0.pointerEdgeDistance = .nan }),
        ]
        for (name, change) in degrades {
            var i = inputs()
            change(&i)
            XCTAssertEqual(ActivityPolicy.decide(i), .declare, name)
        }
        var justInside = inputs()
        justInside.pointerEdgeDistance = ActivityPolicy.edgeMarginPoints + 0.5
        XCTAssertEqual(ActivityPolicy.decide(justInside), .nudge)
    }

    /// The cap runs on Snaptic's clock: 1 h and 8 h, independent of input; never more than 8 h.
    func testCapAtOneAndEightHoursIndependentOfInput() {
        for hours in [1.0, 8.0] {
            var i = inputs(mode: .declare)
            i.stopAfterSeconds = hours * 3_600
            i.activityElapsedSeconds = hours * 3_600 - 1
            XCTAssertEqual(ActivityPolicy.decide(i), .declare)
            i.activityElapsedSeconds = hours * 3_600
            for idle in [60.0, 600, 86_400] {
                i.secondsSinceUserInput = idle
                XCTAssertEqual(ActivityPolicy.decide(i), .skip)
            }
        }
        var tooLong = inputs(mode: .declare)
        tooLong.stopAfterSeconds = 100 * 3_600
        tooLong.activityElapsedSeconds = 8 * 3_600
        XCTAssertEqual(ActivityPolicy.decide(tooLong), .skip, "a cap beyond 8 h is clamped")
    }

    func testSeededTruthTable() {
        var rng = SeededGenerator(seed: 0xAC71)
        for _ in 0..<20_000 {
            let modes: [AwakeActivityMode] = [.off, .declare, .nudge]
            let i = ActivityInputs(mode: modes[Int(rng.next() % 3)], nudgeAllowed: rng.next() % 2 == 0,
                                   screenLocked: rng.next() % 4 == 0, onConsole: rng.next() % 4 != 0,
                                   screensaverRunning: rng.next() % 4 == 0, displaysAsleep: rng.next() % 4 == 0,
                                   switcherVisible: rng.next() % 4 == 0,
                                   secondsSinceUserInput: Double(rng.next() % 200),
                                   activityElapsedSeconds: Double(rng.next() % 40_000),
                                   stopAfterSeconds: Double(rng.next() % 40_000),
                                   pointerEdgeDistance: rng.next() % 3 == 0 ? nil : Double(rng.next() % 6))
            let d = ActivityPolicy.decide(i)
            let acts = i.mode != .off && !i.screenLocked && i.onConsole && !i.screensaverRunning && !i.displaysAsleep
                && !i.switcherVisible && i.secondsSinceUserInput >= 60
                && i.activityElapsedSeconds < min(i.stopAfterSeconds, 8 * 3_600)
            if !acts {
                XCTAssertEqual(d, .skip)
            } else if i.mode == .nudge && i.nudgeAllowed && (i.pointerEdgeDistance ?? 0) > 2 {
                XCTAssertEqual(d, .nudge)
            } else {
                XCTAssertEqual(d, .declare)
            }
            XCTAssertFalse(d == .nudge && i.mode != .nudge, "a declare request never nudges")
        }
    }

    // MARK: nudgeAllowed

    private func session(_ source: AwakeSessionSource) -> AwakeSession {
        AwakeSession(id: StableID(), kind: .indefinite, options: AwakeSessionOptions(activity: .nudge), presetID: nil,
                     source: source, startedAt: 0, startedContinuous: 0, deadline: nil, bootSession: "B")
    }

    func testNudgeNeverAllowedWithoutADirectManualSession() {
        let gates = [AwakeActivityGate(), AwakeActivityGate().applying(.uiStart),
                     AwakeActivityGate().applying(.hotkeyStart).applying(.confirmAsked).applying(.confirmAllowed)]
        let top = TriggerTop(id: StableID(), index: 0, options: AwakeSessionOptions(activity: .nudge), since: 0)
        let hold = AwakeHold(id: StableID(), binding: .process(pid: 42, startTime: 1), startedAt: 0, startedContinuous: 0,
                             deadline: 100, bootSession: "B")
        for gate in gates {
            for governing in [AwakeGoverning.inactive, .trigger(top), .holds([hold]),
                              .manual(session(.commandLine)), .manual(session(.launch)), .manual(session(.rule))] {
                XCTAssertFalse(ActivityPolicy.nudgeAllowed(governing: governing, gate: gate, pointerNudgeEffective: true,
                                                           accessibility: true), "\(governing)")
            }
        }
    }

    func testNudgeNeedsTheFeatureAccessibilityAndTheGate() throws {
        let fresh = AwakeActivityGate()
        for source in [AwakeSessionSource.menu, .hotkey, .settings] {
            // A fresh gate (restored, resumed, unconfirmed): never.
            XCTAssertFalse(ActivityPolicy.nudgeAllowed(governing: .manual(session(source)), gate: fresh,
                                                       pointerNudgeEffective: true, accessibility: true))
        }
        let allowed = AwakeActivityGate().applying(.uiStart)
        XCTAssertTrue(allowed.pointer == .allowed && allowed.uiStartedInProcess, "AwakeActivityGate's truth table (G)")
        XCTAssertTrue(ActivityPolicy.nudgeAllowed(governing: .manual(session(.menu)), gate: allowed,
                                                  pointerNudgeEffective: true, accessibility: true))
        XCTAssertFalse(ActivityPolicy.nudgeAllowed(governing: .manual(session(.menu)), gate: allowed,
                                                   pointerNudgeEffective: false, accessibility: true))
        XCTAssertFalse(ActivityPolicy.nudgeAllowed(governing: .manual(session(.menu)), gate: allowed,
                                                   pointerNudgeEffective: true, accessibility: false))
        XCTAssertFalse(ActivityPolicy.nudgeAllowed(governing: .manual(session(.commandLine)), gate: allowed,
                                                   pointerNudgeEffective: true, accessibility: true))
        let hotkey = AwakeActivityGate().applying(.hotkeyStart)
        XCTAssertFalse(ActivityPolicy.nudgeAllowed(governing: .manual(session(.hotkey)), gate: hotkey,
                                                   pointerNudgeEffective: true, accessibility: true),
                       "an unconfirmed hotkey start")
    }

    func testNeedsPointerConfirmation() throws {
        // Not asking: never.
        XCTAssertFalse(ActivityPolicy.needsPointerConfirmation(inputs(nudgeAllowed: false), gate: AwakeActivityGate()))
        let ask = AwakeActivityGate().applying(.hotkeyStart)
        XCTAssertEqual(ask.pointer, .askOnFirstUse, "AwakeActivityGate's truth table (G)")
        XCTAssertTrue(ActivityPolicy.needsPointerConfirmation(inputs(nudgeAllowed: false), gate: ask))
        XCTAssertFalse(ActivityPolicy.needsPointerConfirmation(inputs(mode: .declare, nudgeAllowed: false), gate: ask))
        var locked = inputs(nudgeAllowed: false)
        locked.screenLocked = true
        XCTAssertFalse(ActivityPolicy.needsPointerConfirmation(locked, gate: ask), "would not act anyway")
        var corner = inputs(nudgeAllowed: false)
        corner.pointerEdgeDistance = 0
        XCTAssertFalse(ActivityPolicy.needsPointerConfirmation(corner, gate: ask), "would only declare")
    }

    // MARK: IdleMath

    func testRealInputIsKept() {
        // Idle 5 s at t = 100: input at 95.
        XCTAssertEqual(IdleMath.lastRealInput(previous: 50, now: 100, hidIdleSeconds: 5, nudgeTimes: [], declareTimes: []), 95)
        XCTAssertEqual(IdleMath.lastRealInput(previous: 50, now: 100, hidIdleSeconds: 5, nudgeTimes: [80],
                                              declareTimes: [70]), 95)
    }

    func testNudgeAndDeclarationEchoesAreIgnored() {
        XCTAssertEqual(IdleMath.lastRealInput(previous: 50, now: 100, hidIdleSeconds: 5, nudgeTimes: [94.5],
                                              declareTimes: []), 50)
        XCTAssertEqual(IdleMath.lastRealInput(previous: 50, now: 100, hidIdleSeconds: 5, nudgeTimes: [],
                                              declareTimes: [95.8]), 50)
        XCTAssertEqual(IdleMath.lastRealInput(previous: 50, now: 100, hidIdleSeconds: 5, nudgeTimes: [96.01],
                                              declareTimes: []), 95, "beyond the echo window")
    }

    func testOlderResetsAndBadReadingsChangeNothing() {
        XCTAssertEqual(IdleMath.lastRealInput(previous: 97, now: 100, hidIdleSeconds: 5, nudgeTimes: [], declareTimes: []), 97)
        XCTAssertEqual(IdleMath.lastRealInput(previous: 97, now: 100, hidIdleSeconds: .nan, nudgeTimes: [], declareTimes: []), 97)
        XCTAssertEqual(IdleMath.lastRealInput(previous: 97, now: .infinity, hidIdleSeconds: 1, nudgeTimes: [],
                                              declareTimes: []), 97)
        XCTAssertEqual(IdleMath.lastRealInput(previous: 97, now: 100, hidIdleSeconds: -3, nudgeTimes: [], declareTimes: []), 100)
        XCTAssertEqual(IdleMath.lastRealInput(previous: -.infinity, now: 100, hidIdleSeconds: 30, nudgeTimes: [],
                                              declareTimes: []), 70)
    }

    /// A nudge every 60 s while the user is away never looks like real input; a key press does.
    func testSimulatedAwaySessionKeepsTheLastRealInput() {
        var last = 0.0
        var nudges: [Double] = []
        for minute in 1...30 {
            let t = Double(minute) * 60
            nudges = IdleMath.remembering(t, in: nudges)
            last = IdleMath.lastRealInput(previous: last, now: t + 0.3, hidIdleSeconds: 0.3, nudgeTimes: nudges,
                                          declareTimes: [])
            XCTAssertEqual(last, 0)
        }
        last = IdleMath.lastRealInput(previous: last, now: 1_830, hidIdleSeconds: 2, nudgeTimes: nudges, declareTimes: [])
        XCTAssertEqual(last, 1_828)
        XCTAssertEqual(nudges.count, IdleMath.rememberedActions)
    }

    func testRemembering() {
        var list: [Double] = []
        for i in 0..<25 { list = IdleMath.remembering(Double(i), in: list) }
        XCTAssertEqual(list, (15..<25).map(Double.init))
    }

    func testSeededFuzzIsMonotonic() {
        var rng = SeededGenerator(seed: 0x1D7E)
        for _ in 0..<5_000 {
            let previous = Double(rng.next() % 1_000)
            let now = previous + Double(rng.next() % 1_000)
            let idle = rng.next() % 10 == 0 ? Double.nan : Double(rng.next() % 2_000) - 100
            let nudges = (0..<Int(rng.next() % 4)).map { _ in Double(rng.next() % 2_000) }
            let declares = (0..<Int(rng.next() % 4)).map { _ in Double(rng.next() % 2_000) }
            let out = IdleMath.lastRealInput(previous: previous, now: now, hidIdleSeconds: idle, nudgeTimes: nudges,
                                             declareTimes: declares)
            XCTAssertGreaterThanOrEqual(out, previous)
            XCTAssertLessThanOrEqual(out, max(previous, now))
        }
    }

    // MARK: First-nudge notice

    func testNudgeNoticeShowsOncePerManualSession() {
        var notice = NudgeNotice()
        let a = StableID(), b = StableID()
        XCTAssertFalse(notice.noteAction(.declare, session: a))
        XCTAssertFalse(notice.noteAction(.skip, session: a))
        XCTAssertFalse(notice.noteAction(.nudge, session: nil), "no manual session: never")
        XCTAssertTrue(notice.noteAction(.nudge, session: a))
        XCTAssertFalse(notice.noteAction(.nudge, session: a))
        XCTAssertFalse(notice.noteAction(.declare, session: a))
        XCTAssertFalse(notice.noteAction(.nudge, session: a))
        XCTAssertEqual(notice.shownFor, a)
        XCTAssertTrue(notice.noteAction(.nudge, session: b), "a new session shows it again")
        XCTAssertFalse(notice.noteAction(.nudge, session: b))
        XCTAssertTrue(notice.noteAction(.nudge, session: a))
    }
}
