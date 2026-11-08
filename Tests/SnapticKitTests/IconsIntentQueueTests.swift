import XCTest
@testable import SnapticKit

/// 0.4 K4: `IconsIntentQueue` (§4.4).
final class IconsIntentQueueTests: XCTestCase {
    private func step(_ r: IconsSubmitResult) -> IconsStep? {
        if case .run(let s, _) = r { return s }
        return nil
    }

    func testTogglesResolveAgainstTheTarget() {
        var q = IconsIntentQueue(state: .expanded(.plain))
        // A click and a CLI toggle before the engine reports anything: the second undoes the first.
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .click, now: 0)), .collapse)
        XCTAssertEqual(q.target, .collapsed)
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .cli, now: 0.1)), .expand(.plain))
        XCTAssertEqual(q.target, .expanded(.plain))
        XCTAssertEqual(step(q.submit(.command(.toggleAll), from: .click, now: 1)), .expand(.all))
        XCTAssertEqual(q.submit(.command(.showAll), from: .cli, now: 1.1), .noChange, "`show --all` at all: no-op")
        XCTAssertEqual(step(q.submit(.command(.toggleAll), from: .click, now: 2)), .collapse, "⌥-click at all")
        XCTAssertEqual(q.submit(.command(.hide), from: .cli, now: 2.1), .noChange)
    }

    func testCalibratingCountsAsCollapsed() {
        var q = IconsIntentQueue(state: .calibrating)
        XCTAssertEqual(q.submit(.command(.hide), from: .cli, now: 0), .noChange, "joins the collapse in flight")
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .click, now: 0)), .expand(.plain))
    }

    func testSequenceNumbersAndSettling() {
        var q = IconsIntentQueue(state: .expanded(.plain))
        guard case .run(.collapse, let first) = q.submit(.command(.hide), from: .timer, now: 0) else {
            return XCTFail("collapse")
        }
        guard case .run(.expand(.plain), let second) = q.submit(.command(.show), from: .cli, now: 0) else {
            return XCTFail("expand")
        }
        XCTAssertEqual(second, first + 1)
        // The superseded collapse settles late: ignored.
        q.settled(seq: first, state: .collapsed)
        XCTAssertEqual(q.target, .expanded(.plain))
        q.settled(seq: second, state: .expanded(.plain))
        XCTAssertEqual(q.target, .expanded(.plain))
    }

    func testARefusedCollapseCorrectsTheTarget() {
        var q = IconsIntentQueue(state: .expanded(.plain))
        guard case .run(.collapse, let seq) = q.submit(.command(.toggle), from: .click, now: 0) else {
            return XCTFail("collapse")
        }
        q.settled(seq: seq, state: .expanded(.plain))
        XCTAssertEqual(q.target, .expanded(.plain))
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .click, now: 1)), .collapse,
                       "the next click tries again instead of expanding")
    }

    func testEngineChangesMoveTheTarget() {
        var q = IconsIntentQueue(state: .collapsed)
        q.engineChanged(.calibrating)
        XCTAssertEqual(q.target, .collapsed)
        q.engineChanged(.expanded(.plain))
        XCTAssertEqual(q.target, .expanded(.plain))
        q.engineChanged(.unavailable(.timeouts))
        XCTAssertEqual(q.target, .expanded(.plain))
    }

    func testDebounceOnClickAndShortcutOnly() {
        var q = IconsIntentQueue(state: .expanded(.plain))
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .click, now: 10)), .collapse)
        XCTAssertEqual(q.submit(.command(.toggle), from: .click, now: 10.29), .dropped(.debounce))
        XCTAssertEqual(q.target, .collapsed)
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .shortcut, now: 10.29)), .expand(.plain),
                       "each source has its own window")
        XCTAssertEqual(q.submit(.command(.toggle), from: .shortcut, now: 10.5), .dropped(.debounce))
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .click, now: 10.3)), .collapse)
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .cli, now: 10.31)), .expand(.plain), "CLI: none")
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .cli, now: 10.32)), .collapse)
        XCTAssertEqual(step(q.submit(.command(.show), from: .hiddenList, now: 10.33)), .expand(.plain), "list: none")
    }

    func testHoverSuppressedAfterClickCollapseAndSpaceChange() {
        var q = IconsIntentQueue(state: .expanded(.plain))
        _ = q.submit(.command(.toggle), from: .click, now: 0)
        XCTAssertEqual(q.submit(.command(.show), from: .hover, now: 0.99), .dropped(.hoverSuppressed))
        XCTAssertEqual(step(q.submit(.command(.show), from: .hover, now: 1)), .expand(.plain))

        var r = IconsIntentQueue(state: .expanded(.plain))
        _ = r.submit(.command(.hide), from: .timer, now: 0)
        XCTAssertEqual(step(r.submit(.command(.show), from: .hover, now: 0.1)), .expand(.plain),
                       "only a click-collapse suppresses hover")

        var s = IconsIntentQueue(state: .collapsed)
        s.spaceChanged(now: 5)
        XCTAssertEqual(s.submit(.command(.show), from: .hover, now: 5.5), .dropped(.hoverSuppressed))
        XCTAssertEqual(step(s.submit(.command(.show), from: .hover, now: 6)), .expand(.plain))
    }

    func testTimerSuppressedAfterAHiddenListPress() {
        var q = IconsIntentQueue(state: .collapsed)
        _ = q.submit(.command(.show), from: .hiddenList, now: 100)
        XCTAssertEqual(q.submit(.command(.hide), from: .timer, now: 159), .dropped(.timerSuppressed))
        XCTAssertEqual(step(q.submit(.command(.hide), from: .timer, now: 160)), .collapse)

        var r = IconsIntentQueue(state: .expanded(.plain))
        r.hiddenListPressed(now: 0)
        XCTAssertEqual(r.submit(.command(.hide), from: .timer, now: 30), .dropped(.timerSuppressed))
        XCTAssertEqual(step(r.submit(.command(.hide), from: .cli, now: 30)), .collapse, "only the timer")
    }

    func testAnyUserIntentCancelsLaunchCollapse() {
        for source in IconsIntentSource.allCases {
            var q = IconsIntentQueue(state: .expanded(.plain))
            _ = q.submit(.command(.show), from: source, now: 0)
            let result = q.submit(.command(.hide), from: .launch, now: 20)
            if source.isUser {
                XCTAssertEqual(result, .dropped(.launchCancelled), source.rawValue)
            } else if source == .launch {
                XCTAssertEqual(step(result), .collapse)
            } else {
                XCTAssertEqual(step(result), .collapse, source.rawValue)
            }
        }
        XCTAssertEqual(IconsIntentSource.allCases.filter(\.isUser),
                       [.click, .shortcut, .cli, .menu, .hiddenList, .hover, .settings])
        XCTAssertEqual(IconsIntentSource.allCases.filter(\.isDebounced), [.click, .shortcut])
    }

    func testStopAndFailSafePreempt() {
        var q = IconsIntentQueue(state: .collapsed)
        // A debounce window doesn't hold them back.
        _ = q.submit(.command(.toggle), from: .click, now: 0)
        XCTAssertEqual(step(q.submit(.failSafe(.exam), from: .monitor, now: 0.1)), .failSafe(.exam))
        XCTAssertEqual(q.target, .expanded(.plain))
        XCTAssertEqual(step(q.submit(.stop, from: .monitor, now: 0.1)), .stop)
        XCTAssertTrue(q.stopped)
        XCTAssertEqual(q.submit(.command(.toggle), from: .cli, now: 1), .dropped(.stopped))
        XCTAssertEqual(q.submit(.failSafe(.session), from: .monitor, now: 1), .dropped(.stopped))
        XCTAssertEqual(step(q.submit(.stop, from: .monitor, now: 1)), .stop, "stop is always handed out")
        q.restart(state: .expanded(.plain))
        XCTAssertFalse(q.stopped)
        XCTAssertEqual(step(q.submit(.command(.toggle), from: .cli, now: 2)), .collapse)
    }

    /// Recovery re-collapses only if the last intent was to hide; fail-safes don't change it.
    func testIntentHidden() {
        var q = IconsIntentQueue(state: .expanded(.plain))
        XCTAssertFalse(q.intentHidden)
        _ = q.submit(.command(.hide), from: .cli, now: 0)
        XCTAssertTrue(q.intentHidden)
        _ = q.submit(.failSafe(.agentRestart), from: .monitor, now: 1)
        XCTAssertTrue(q.intentHidden, "a fail-safe keeps the intent, so the agent's relaunch re-collapses")
        XCTAssertEqual(IconsRecovery.plan(.agentLaunched, intentHidden: q.intentHidden).recollapseAfter, 2)
        _ = q.submit(.command(.show), from: .cli, now: 2)
        XCTAssertFalse(q.intentHidden)
        _ = q.submit(.command(.hide), from: .cli, now: 3)
        _ = q.submit(.command(.show), from: .cli, now: 4)
        _ = q.submit(.command(.show), from: .cli, now: 5)
        XCTAssertFalse(q.intentHidden, "show at shown")
        _ = q.submit(.command(.hide), from: .timer, now: 6)
        q.settled(seq: q.seq, state: .collapsed)
        _ = q.submit(.command(.hide), from: .cli, now: 7)
        XCTAssertTrue(q.intentHidden, "hide at hidden")
        _ = q.submit(.stop, from: .monitor, now: 8)
        XCTAssertFalse(q.intentHidden)
    }

    /// H9's expand cause: kept through a failed collapse, cleared once the bar is collapsed.
    func testExpandSource() {
        var q = IconsIntentQueue(state: .collapsed)
        XCTAssertNil(q.expandSource)
        _ = q.submit(.command(.toggle), from: .shortcut, now: 0)
        XCTAssertEqual(q.expandSource, .shortcut)
        guard case .run(.collapse, let seq) = q.submit(.command(.hide), from: .cli, now: 1) else {
            return XCTFail("collapse")
        }
        q.settled(seq: seq, state: .expanded(.plain))
        XCTAssertEqual(q.expandSource, .shortcut, "a failed collapse keeps the full menu bar")
        _ = q.submit(.command(.hide), from: .cli, now: 2)
        q.engineChanged(.calibrating)
        XCTAssertEqual(q.expandSource, .shortcut)
        q.engineChanged(.collapsed)
        XCTAssertNil(q.expandSource)
        _ = q.submit(.failSafe(.session), from: .monitor, now: 3)
        XCTAssertNil(q.expandSource, "a fail-safe expand never takes the full menu bar")
        _ = q.submit(.command(.toggleAll), from: .hover, now: 4)
        XCTAssertEqual(q.expandSource, .hover)
        XCTAssertEqual(IconsExpandCause(q.expandSource), .hover)
    }

    /// Every intent from every source at every state: the target always matches what the handed-out step implies,
    /// and only drops or no-ops leave it alone.
    func testMatrixKeepsTargetConsistent() {
        let intents: [IconsIntent] = [.command(.toggle), .command(.toggleAll), .command(.show), .command(.showAll),
                                      .command(.hide), .failSafe(.session), .stop]
        let states: [IconsEngineState] = [.collapsed, .calibrating, .expanded(.plain), .expanded(.all),
                                          .unavailable(.killSwitch)]
        var count = 0
        for state in states {
            for a in intents {
                for sa in IconsIntentSource.allCases {
                    for b in intents {
                        for sb in IconsIntentSource.allCases {
                            var q = IconsIntentQueue(state: state)
                            for (intent, source, now) in [(a, sa, 0.0), (b, sb, 0.5)] {
                                let before = q.target
                                let result = q.submit(intent, from: source, now: now)
                                switch result {
                                case .run(.collapse, _): XCTAssertEqual(q.target, .collapsed)
                                case .run(.expand(let m), _): XCTAssertEqual(q.target, .expanded(m))
                                case .run(.stop, _), .run(.failSafe, _): XCTAssertEqual(q.target, .expanded(.plain))
                                case .noChange, .dropped: XCTAssertEqual(q.target, before)
                                }
                                if case .run(.expand, _) = result { XCTAssertEqual(q.expandSource, source) }
                                count += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(count, 10_000)
    }
}
