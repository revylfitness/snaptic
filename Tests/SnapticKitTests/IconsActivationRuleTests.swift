import XCTest
@testable import SnapticKit

/// 0.4 K4: the H9 activation-policy rule.
final class IconsActivationRuleTests: XCTestCase {
    /// The whole truth table of H9's right-hand side, with the window facts that only matter for demotion.
    func testTruthTable() {
        var rows = 0
        for settings in [false, true] {
            for onboarding in [false, true] {
                for fullBar in [false, true] {
                    for expanded in [false, true] {
                        for cause in IconsExpandCause.allCases {
                            for switcher in [false, true] {
                                for visible in [false, true] {
                                    var f = IconsActivationFacts()
                                    f.settingsOpen = settings
                                    f.onboardingOpen = onboarding
                                    f.fullBarOnExpand = fullBar
                                    f.expanded = expanded
                                    f.expandCause = cause
                                    f.switcherPanelOpen = switcher
                                    f.snapticWindowVisible = visible
                                    let want = settings || onboarding
                                        || (fullBar && expanded && cause.takesFullBar && !switcher)
                                    XCTAssertEqual(IconsActivationRule.wantsRegular(f), want, "\(f)")
                                    XCTAssertEqual(IconsActivationRule.next(current: .accessory, f),
                                                   want ? .regular : .accessory, "never promoted by a window alone")
                                    XCTAssertEqual(IconsActivationRule.next(current: .regular, f),
                                                   want || visible ? .regular : .accessory)
                                    rows += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(rows, 2 * 2 * 2 * 2 * IconsExpandCause.allCases.count * 2 * 2)
    }

    func testCausesThatTakeTheFullBar() {
        XCTAssertEqual(IconsExpandCause.allCases.filter(\.takesFullBar), [.click, .shortcut, .menu, .cli])
        XCTAssertEqual(IconsExpandCause(.click), .click)
        XCTAssertEqual(IconsExpandCause(.hover), .hover)
        XCTAssertEqual(IconsExpandCause(.hiddenList), .hiddenList)
        for source in [IconsIntentSource.timer, .launch, .settings, .monitor] {
            XCTAssertEqual(IconsExpandCause(source), .other)
        }
        XCTAssertEqual(IconsExpandCause(nil), .other)
    }

    func testHoverNeverTakesTheFullBar() {
        var f = IconsActivationFacts()
        f.fullBarOnExpand = true
        f.expanded = true
        f.expandCause = .hover
        XCTAssertFalse(IconsActivationRule.fullBar(f))
        f.expandCause = .click
        XCTAssertTrue(IconsActivationRule.fullBar(f))
        f.switcherPanelOpen = true
        XCTAssertFalse(IconsActivationRule.fullBar(f))
        XCTAssertFalse(IconsActivationRule.mayActivate(f))
    }

    func testDemotionWaitsForReasonsAndWindows() {
        var f = IconsActivationFacts()
        XCTAssertEqual(IconsActivationRule.next(current: .regular, f), .accessory)
        f.otherReasonHeld = true
        XCTAssertEqual(IconsActivationRule.next(current: .regular, f), .regular)
        f.otherReasonHeld = false
        f.snapticWindowKey = true
        XCTAssertEqual(IconsActivationRule.next(current: .regular, f), .regular)
        f.snapticWindowKey = false
        f.snapticWindowVisible = true
        XCTAssertEqual(IconsActivationRule.next(current: .regular, f), .regular)
        XCTAssertEqual(IconsActivationRule.next(current: .accessory, f), .accessory)
    }

    func testReactivateRemembered() {
        let f = IconsActivationFacts()
        XCTAssertTrue(IconsActivationRule.reactivateRemembered(hadRemembered: true, otherAppActivatedSinceExpand: false,
                                                               f))
        XCTAssertFalse(IconsActivationRule.reactivateRemembered(hadRemembered: false,
                                                                otherAppActivatedSinceExpand: false, f))
        XCTAssertFalse(IconsActivationRule.reactivateRemembered(hadRemembered: true, otherAppActivatedSinceExpand: true,
                                                                f))
        var g = f
        g.snapticWindowVisible = true
        XCTAssertFalse(IconsActivationRule.reactivateRemembered(hadRemembered: true,
                                                                otherAppActivatedSinceExpand: false, g))
        g = f
        g.settingsOpen = true
        XCTAssertFalse(IconsActivationRule.reactivateRemembered(hadRemembered: true,
                                                                otherAppActivatedSinceExpand: false, g))
    }

    /// The queue's cause feeds the rule end to end: a failed collapse keeps the full bar, a success drops it.
    func testWithTheQueue() {
        var q = IconsIntentQueue(state: .collapsed)
        _ = q.submit(.command(.toggle), from: .click, now: 0)
        var f = IconsActivationFacts()
        f.fullBarOnExpand = true
        f.expanded = true
        f.expandCause = IconsExpandCause(q.expandSource)
        XCTAssertEqual(IconsActivationRule.next(current: .accessory, f), .regular)
        guard case .run(.collapse, let seq) = q.submit(.command(.toggle), from: .click, now: 1) else {
            return XCTFail("collapse")
        }
        q.settled(seq: seq, state: .expanded(.plain))
        f.expandCause = IconsExpandCause(q.expandSource)
        XCTAssertEqual(IconsActivationRule.next(current: .regular, f), .regular, "failed collapse keeps it")
        q.engineChanged(.collapsed)
        f.expanded = false
        f.expandCause = IconsExpandCause(q.expandSource)
        XCTAssertEqual(IconsActivationRule.next(current: .regular, f), .accessory)
    }
}
