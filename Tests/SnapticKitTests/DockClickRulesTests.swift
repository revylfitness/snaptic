import XCTest
@testable import SnapticKit

/// 0.5 K3: `DockClickRules` and `DockTapBreaker` (§4.11; Y-15, D2-15, D2-20, X2-17).
final class DockClickRulesTests: XCTestCase {
    private let app: Int32 = 7
    private let other: Int32 = 8

    /// The app has been active since 1.0; the press is at 5.0.
    private func press(pid: Int32? = 7, history: DockActivationHistory? = nil, visibleOnSpace: Int = 1,
                       windowCount: Int = 2, minimizedCount: Int = 0, action: DockClickAction = .hideApp,
                       restoreAll: Bool = false) -> DockClickPress {
        DockClickRules.press(at: 5.0, pid: pid, history: history ?? DockActivationHistory([DockActivation(pid: 7, at: 1.0)]),
                             visibleOnSpace: visibleOnSpace, windowCount: windowCount, minimizedCount: minimizedCount,
                             action: action, restoreAll: restoreAll)
    }

    private func up(_ p: DockClickPress, at now: Double = 5.2, onSameItem: Bool = true,
                    history: DockActivationHistory? = nil, pause: DockPauseReason? = nil, breaker: Bool = false,
                    killSwitch: Bool = false) -> DockClickDecision {
        DockClickRules.mouseUp(p, at: now, onSameItem: onSameItem,
                               history: history ?? DockActivationHistory([DockActivation(pid: 7, at: 1.0)]),
                               pause: pause, breakerTripped: breaker, killSwitch: { killSwitch })
    }

    // MARK: The resolver table (Y-15): one case per rule, in the order they're tried

    func testResolverTable() {
        let base = press()
        let otherActive = DockActivationHistory([DockActivation(pid: 8, at: 1.0)])
        let cases: [(String, DockClickDecision, DockClickDecision)] = [
            ("acts", up(base), .wait(.hideApp, at: 5.3)),
            ("minimize acts", up(press(action: .minimizeWindows)), .wait(.minimizeWindows, at: 5.3)),
            ("1 not an app", up(press(pid: nil)), .skip(.notAnApp)),
            ("2 off", up(press(action: .doNothing)), .skip(.off)),
            ("2 off: Restore all without every window minimized", up(press(minimizedCount: 1, action: .doNothing,
                                                                          restoreAll: true)), .skip(.off)),
            ("3 paused by command", up(base, pause: .command), .skip(.paused)),
            ("3 paused in Safe Mode", up(base, pause: .safeMode), .skip(.paused)),
            ("3 paused for another tool", up(base, pause: .otherTool), .skip(.paused)),
            ("3 VoiceOver doesn't stop click actions", up(base, pause: .voiceOver), .wait(.hideApp, at: 5.3)),
            ("4 breaker", up(base, breaker: true), .skip(.breaker)),
            ("5 another item", up(base, onSameItem: false), .skip(.otherItem)),
            ("6 too late", up(base, at: 5.51), .skip(.tooLate)),
            ("6 just in time", up(base, at: 5.5), .wait(.hideApp, at: 5.6)),
            ("7 restore all", up(press(history: otherActive, visibleOnSpace: 0, minimizedCount: 2, action: .doNothing,
                                       restoreAll: true), history: otherActive), .restoreAll),
            ("7 restore all, kill switch", up(press(minimizedCount: 2, restoreAll: true), killSwitch: true),
             .skip(.killSwitch)),
            ("8 not active", up(press(history: otherActive), history: otherActive), .skip(.notActive)),
            ("9 ambiguous", up(base, history: DockActivationHistory([DockActivation(pid: 7, at: 1.0),
                                                                     DockActivation(pid: 8, at: 5.1)])),
             .skip(.ambiguous)),
            ("10 no visible window", up(press(visibleOnSpace: 0)), .skip(.noVisibleWindow)),
            ("11 kill switch", up(base, killSwitch: true), .skip(.killSwitch)),
        ]
        for (name, got, want) in cases {
            XCTAssertEqual(got, want, name)
        }
    }

    /// The kill switch is read only when the click would act (D2-15).
    func testKillSwitchIsReadOnlyWhenActing() {
        var reads = 0
        func run(_ p: DockClickPress, onSameItem: Bool = true) -> DockClickDecision {
            DockClickRules.mouseUp(p, at: 5.2, onSameItem: onSameItem,
                                   history: DockActivationHistory([DockActivation(pid: 7, at: 1.0)]), pause: nil,
                                   breakerTripped: false, killSwitch: { reads += 1; return false })
        }
        _ = run(press(pid: nil))
        _ = run(press(action: .doNothing))
        _ = run(press(), onSameItem: false)
        _ = run(press(visibleOnSpace: 0))
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(run(press()), .wait(.hideApp, at: 5.3))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(run(press(minimizedCount: 2, restoreAll: true)), .restoreAll)
        XCTAssertEqual(reads, 2)
    }

    /// Everything is sampled at mouse-down: the Dock activating the clicked app before mouse-up doesn't make it the
    /// active app, and Restore all is decided from the counts at mouse-down (D2-20).
    func testStateIsSampledAtMouseDown() {
        var history = DockActivationHistory([DockActivation(pid: 8, at: 1.0)])
        let p = press(history: history)
        XCTAssertEqual(p.activePID, 8)
        history.record(pid: 7, at: 5.15)       // the Dock activates the clicked app
        XCTAssertEqual(up(p, history: history), .skip(.notActive))

        let minimized = press(windowCount: 3, minimizedCount: 3, action: .doNothing, restoreAll: true)
        XCTAssertTrue(minimized.allMinimized)
        XCTAssertEqual(up(minimized), .restoreAll)
        XCTAssertFalse(press(windowCount: 0, minimizedCount: 0).allMinimized)
    }

    /// An activation in the 150 ms before mouse-down: another app makes it ambiguous; the clicked app itself
    /// makes it not active. Either way nothing happens (D2-20).
    func testActivationJustBeforeMouseDown() {
        let otherJustBefore = DockActivationHistory([DockActivation(pid: 7, at: 1.0), DockActivation(pid: 8, at: 4.9)])
        let p = press(history: otherJustBefore)
        XCTAssertEqual(p.activePID, 7)
        XCTAssertEqual(up(p, history: otherJustBefore), .skip(.ambiguous))

        let selfJustBefore = DockActivationHistory([DockActivation(pid: 8, at: 1.0), DockActivation(pid: 7, at: 4.9)])
        let q = press(history: selfJustBefore)
        XCTAssertEqual(q.activePID, 8)
        XCTAssertEqual(up(q, history: selfJustBefore), .skip(.notActive))

        // 150 ms or more before is history: the app is active.
        let settled = DockActivationHistory([DockActivation(pid: 8, at: 1.0), DockActivation(pid: 7, at: 4.85)])
        XCTAssertEqual(up(press(history: settled), history: settled), .wait(.hideApp, at: 5.3))
    }

    /// At mouse-up + 100 ms (X2-17).
    func testConfirm() {
        let p = press()
        let quiet = DockActivationHistory([DockActivation(pid: 7, at: 1.0)])
        XCTAssertEqual(DockClickRules.confirm(p, .hideApp, at: 5.3, history: quiet, layer0Grew: false), .act(.hideApp))
        var late = quiet
        late.record(pid: 8, at: 5.25)
        XCTAssertEqual(DockClickRules.confirm(p, .hideApp, at: 5.3, history: late, layer0Grew: false), .skip(.ambiguous))
        XCTAssertEqual(DockClickRules.confirm(p, .hideApp, at: 5.3, history: quiet, layer0Grew: true),
                       .skip(.windowCreated))
        XCTAssertEqual(DockClickRules.confirm(p, .minimizeWindows, at: 5.3, history: quiet, layer0Grew: true),
                       .act(.minimizeWindows))
        // The app re-activating itself isn't another app.
        var again = quiet
        again.record(pid: 7, at: 5.2)
        XCTAssertEqual(DockClickRules.confirm(p, .hideApp, at: 5.3, history: again, layer0Grew: false), .act(.hideApp))
    }

    // MARK: History

    func testHistoryKeepsTheLast32InOrder() {
        var h = DockActivationHistory()
        for i in 0..<40 { h.record(pid: Int32(i), at: Double(i)) }
        XCTAssertEqual(h.records.count, DockActivationHistory.capacity)
        XCTAssertEqual(h.records.first?.pid, 8)
        XCTAssertEqual(h.active(at: 39.5), 39)
        XCTAssertNil(DockActivationHistory().active(at: 1))

        var late = DockActivationHistory()
        late.record(pid: 1, at: 2.0)
        late.record(pid: 2, at: 1.0)        // delivered out of order
        XCTAssertEqual(late.records.map(\.pid), [2, 1])
        XCTAssertEqual(late.active(at: 1.5), 2)
        XCTAssertTrue(late.otherActivation(than: 2, from: 1.5, through: 2.0))
        XCTAssertFalse(late.otherActivation(than: 1, from: 1.5, through: 2.0))
    }

    // MARK: Breaker

    func testBreakerTripsOnThreeDisablesIn60Seconds() {
        var b = DockTapBreaker()
        XCTAssertFalse(b.disabled(at: 0))
        XCTAssertFalse(b.disabled(at: 10))
        XCTAssertTrue(b.disabled(at: 59))
        XCTAssertTrue(b.tripped)
        // It stays tripped until relaunch.
        XCTAssertTrue(b.disabled(at: 1_000))
        XCTAssertTrue(b.tripped)
    }

    func testBreakerIgnoresDisablesSpreadOverMoreThan60Seconds() {
        var b = DockTapBreaker()
        b.disabled(at: 0)
        b.disabled(at: 30)
        XCTAssertFalse(b.disabled(at: 61))     // 0 is more than 60 s back
        XCTAssertFalse(b.disabled(at: 91))     // so is 30
        XCTAssertFalse(b.tripped)
        XCTAssertTrue(b.disabled(at: 120))     // 61, 91 and 120
    }
}
