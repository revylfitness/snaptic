import XCTest
@testable import SnapticKit

final class TrialLifecycleTests: XCTestCase {
    /// Drives a lifecycle the way the queue's trial task does, up to the panel.
    private func toPanel() -> TrialLifecycle {
        var t = TrialLifecycle()
        XCTAssertEqual(t.advance(to: .applying), .proceed)
        XCTAssertEqual(t.advance(to: .settling), .proceed)
        XCTAssertEqual(t.advance(to: .confirming), .proceed)
        return t
    }

    func testKeepAndRevertAndTimeout() {
        var keep = toPanel()
        XCTAssertEqual(keep.panelClosed(.keep), .proceed)
        XCTAssertEqual(keep.phase, .keeping)
        XCTAssertEqual(keep.checkpoint(), .proceed)
        XCTAssertEqual(keep.finishKeep(), .proceed)
        XCTAssertEqual(keep.end, .kept)

        var revert = toPanel()
        XCTAssertEqual(revert.panelClosed(.revert), .revert(.user))
        XCTAssertTrue(revert.finishRevert())
        XCTAssertEqual(revert.end, .reverted(.user))

        var timeout = toPanel()
        XCTAssertEqual(timeout.panelClosed(.timeout), .revert(.timeout))
        XCTAssertTrue(timeout.finishRevert())
        XCTAssertEqual(timeout.end, .reverted(.timeout))
        XCTAssertFalse(timeout.finishRevert(), "resolves exactly once")
        XCTAssertEqual(timeout.finishKeep(), .abandon)
        XCTAssertEqual(timeout.stop(), .none)
        XCTAssertEqual(timeout.end, .reverted(.timeout))
    }

    /// FIXES-R1 B1: a revert requested while settling (panel not up yet) is not lost.
    func testRevertDuringSettleIsNotLost() {
        for reason in [TrialRevertReason.panic, .session, .newRequest, .guardLost] {
            var t = TrialLifecycle()
            XCTAssertEqual(t.advance(to: .applying), .proceed)
            XCTAssertEqual(t.advance(to: .settling), .proceed)
            XCTAssertTrue(t.requestRevert(reason))
            XCTAssertEqual(t.checkpoint(), .revert(reason), "the settle loop sees it")
            XCTAssertEqual(t.advance(to: .confirming), .proceed, "already reverting: no panel")
            XCTAssertNotEqual(t.phase, .confirming)
            XCTAssertTrue(t.finishRevert())
            XCTAssertEqual(t.end, .reverted(reason))
        }
        // Even if the task only looks after the panel closed with Keep, Keep loses.
        var t = toPanel()
        t.requestRevert(.panic)
        XCTAssertEqual(t.panelClosed(.keep), .revert(.panic))
        XCTAssertTrue(t.finishRevert())
        XCTAssertEqual(t.end, .reverted(.panic))
    }

    func testRevertDuringArmingAndApplying() {
        var arming = TrialLifecycle()
        arming.requestRevert(.newRequest)
        XCTAssertEqual(arming.advance(to: .applying), .revert(.newRequest), "never applies")
        var applying = TrialLifecycle()
        XCTAssertEqual(applying.advance(to: .applying), .proceed)
        applying.guardDidRevert()
        XCTAssertTrue(applying.guardReverted)
        XCTAssertEqual(applying.checkpoint(), .revert(.guardReverted))
        var failed = TrialLifecycle()
        _ = failed.advance(to: .applying)
        XCTAssertEqual(failed.applyFailed(), .revert(.applyFailed))
        XCTAssertTrue(failed.finishRevert())
        XCTAssertEqual(failed.end, .reverted(.applyFailed))
    }

    /// After Keep: panic and the guard still win; sleep or a new request don't.
    func testKeepingPhase() {
        var sleepy = toPanel()
        _ = sleepy.panelClosed(.keep)
        XCTAssertFalse(sleepy.requestRevert(.session))
        XCTAssertFalse(sleepy.requestRevert(.newRequest))
        XCTAssertEqual(sleepy.checkpoint(), .proceed)
        XCTAssertEqual(sleepy.finishKeep(), .proceed)
        XCTAssertEqual(sleepy.end, .kept)

        var panic = toPanel()
        _ = panic.panelClosed(.keep)
        XCTAssertTrue(panic.requestRevert(.panic))
        XCTAssertEqual(panic.checkpoint(), .revert(.panic), "checked right after commitIntent")
        XCTAssertTrue(panic.finishRevert())
        XCTAssertEqual(panic.end, .reverted(.panic))

        var late = toPanel()
        _ = late.panelClosed(.keep)
        XCTAssertEqual(late.checkpoint(), .proceed)
        late.requestRevert(.panic)                      // during afterKeep
        XCTAssertEqual(late.finishKeep(), .revert(.panic), "panic during the Keep write still reverts")
        XCTAssertTrue(late.finishRevert())
        XCTAssertEqual(late.end, .reverted(.panic))
    }

    func testStop() {
        var settling = TrialLifecycle()
        _ = settling.advance(to: .applying)
        _ = settling.advance(to: .settling)
        XCTAssertEqual(settling.stop(), .undo)
        XCTAssertEqual(settling.end, .reverted(.stopped))
        XCTAssertEqual(settling.checkpoint(), .abandon, "the task touches nothing afterwards")
        XCTAssertEqual(settling.panelClosed(.keep), .abandon)
        XCTAssertFalse(settling.finishRevert())

        var keeping = toPanel()
        _ = keeping.panelClosed(.keep)
        XCTAssertEqual(keeping.stop(), .commit)
        XCTAssertEqual(keeping.end, .kept)
        XCTAssertEqual(keeping.finishKeep(), .abandon)

        var panicked = toPanel()
        _ = panicked.panelClosed(.keep)
        panicked.requestRevert(.panic)
        XCTAssertEqual(panicked.stop(), .undo, "a pending panic wins over the Keep at stop too")
        XCTAssertEqual(panicked.end, .reverted(.panic))

        var reverting = toPanel()
        _ = reverting.panelClosed(.revert)
        XCTAssertEqual(reverting.stop(), .undo, "the staged undo may be half done: finish it synchronously")
        XCTAssertEqual(reverting.end, .reverted(.user))
    }

    func testFirstReasonWins() {
        var t = toPanel()
        t.requestRevert(.session)
        t.requestRevert(.panic)
        XCTAssertEqual(t.panelClosed(.timeout), .revert(.session))
        XCTAssertFalse(t.requestRevert(.panic), "already reverting")
    }

    /// Random interleavings of the task's steps with outside events: the trial resolves
    /// exactly once, a panic before resolution always ends reverted, and Kept needs a Keep
    /// choice with no counting revert request before it.
    func testRandomInterleavings() {
        var rng = SeededGenerator(seed: 0xB1_7A1)
        let reasons = TrialRevertReason.allCases.filter { $0 != .stopped }
        for _ in 0..<5000 {
            var t = TrialLifecycle()
            var ends = 0
            var lastEnd: TrialEnd?
            var panicBeforeEnd = false
            var keepChosen = false
            var stopped = false
            var countedBeforeKeep = false
            func observe() {
                if let e = t.end, e != lastEnd {
                    ends += 1
                    lastEnd = e
                }
            }
            func outside() {
                switch rng.next() % 9 {
                case 0:
                    let r = reasons[Int(rng.next() % UInt64(reasons.count))]
                    let wasResolved = t.isResolved
                    let phase = t.phase
                    let counted = t.requestRevert(r)
                    if r == .panic && !wasResolved { panicBeforeEnd = true }
                    if counted && phase != .keeping { countedBeforeKeep = true }
                case 1:
                    let wasResolved = t.isResolved
                    let phase = t.phase
                    t.guardDidRevert()
                    if !wasResolved && phase != .keeping && phase != .reverting { countedBeforeKeep = true }
                case 2 where rng.next() % 6 == 0:
                    if !t.isResolved { stopped = true }
                    _ = t.stop()
                default:
                    break
                }
                observe()
            }
            // The task.
            var step: TrialStep = .proceed
            task: for phase in [TrialPhase.applying, .settling, .confirming] {
                outside()
                step = t.advance(to: phase)
                outside()
                if step != .proceed { break task }
                if t.phase == .reverting { break task }
            }
            if step == .proceed && t.phase == .confirming {
                outside()
                let choices: [TrialPanelChoice] = [.keep, .revert, .timeout]
                let choice = choices[Int(rng.next() % 3)]
                if choice == .keep && t.revertReason == nil && !t.isResolved { keepChosen = true }
                step = t.panelClosed(choice)
                outside()
                if step == .proceed {
                    step = t.checkpoint()            // after commitIntent
                    outside()
                    if step == .proceed {
                        outside()                    // during afterKeep
                        step = t.finishKeep()
                    }
                }
            }
            outside()
            if case .revert = step { t.finishRevert() }
            if t.phase == .reverting { t.finishRevert() }
            observe()
            if !t.isResolved { _ = t.stop() }
            observe()

            XCTAssertNotNil(t.end)
            XCTAssertEqual(ends, 1, "resolved exactly once")
            if panicBeforeEnd { XCTAssertNotEqual(t.end, .kept, "panic before resolution never ends kept") }
            if t.end == .kept {
                XCTAssertTrue(keepChosen, "kept needs the user's Keep")
                XCTAssertFalse(countedBeforeKeep && !stopped, "no revert request counted before Keep")
            }
        }
    }

    /// FIXES-R3 1: `--yes` (allowed) keeps right after settle; automatic requests never skip.
    func testSkippingThePanel() {
        XCTAssertEqual(TrialPanelChoice.withoutPanel(skipConfirmation: true, automatic: false), .keep)
        XCTAssertNil(TrialPanelChoice.withoutPanel(skipConfirmation: false, automatic: false))
        XCTAssertNil(TrialPanelChoice.withoutPanel(skipConfirmation: true, automatic: true))
        XCTAssertNil(TrialPanelChoice.withoutPanel(skipConfirmation: false, automatic: true))

        // The skipped trial goes through the same lifecycle: Keep, commit intent, kept.
        var kept = toPanel()
        let choice = TrialPanelChoice.withoutPanel(skipConfirmation: true, automatic: false)!
        XCTAssertEqual(kept.panelClosed(choice), .proceed)
        XCTAssertEqual(kept.checkpoint(), .proceed)
        XCTAssertEqual(kept.finishKeep(), .proceed)
        XCTAssertEqual(kept.end, .kept)

        // A revert requested while settling still wins: the queue checks the lifecycle
        // (advance to .confirming) before it decides to skip the panel.
        var t = TrialLifecycle()
        XCTAssertEqual(t.advance(to: .applying), .proceed)
        XCTAssertEqual(t.advance(to: .settling), .proceed)
        XCTAssertTrue(t.requestRevert(.session))
        XCTAssertEqual(t.advance(to: .confirming), .revert(.session))
        XCTAssertTrue(t.finishRevert())
        XCTAssertEqual(t.end, .reverted(.session))

        // Panic during the Keep write still overrides a skipped confirmation.
        var p = toPanel()
        XCTAssertEqual(p.panelClosed(choice), .proceed)
        XCTAssertTrue(p.requestRevert(.panic))
        XCTAssertEqual(p.finishKeep(), .revert(.panic))
    }

    func testSupersession() {
        var s = TrialSupersession()
        let auto1 = s.ticket(user: false)
        let user1 = s.ticket(user: true)
        XCTAssertTrue(s.isSuperseded(auto1), "a user request supersedes older automatic trials")
        XCTAssertFalse(s.isSuperseded(user1))
        let auto2 = s.ticket(user: false)
        XCTAssertFalse(s.isSuperseded(auto2))
        XCTAssertFalse(s.isSuperseded(user1), "automatic requests never supersede")
        let user2 = s.ticket(user: true)
        XCTAssertTrue(s.isSuperseded(user1) && s.isSuperseded(auto2))
        XCTAssertFalse(s.isSuperseded(user2))
    }
}
