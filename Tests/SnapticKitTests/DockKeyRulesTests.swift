import XCTest
@testable import SnapticKit

/// 0.5 K3: `DockEngagement` and `DockKeyRules` (§4.5; D2-3, X2-2, X2-5, X3-4, X3-5).
final class DockKeyRulesTests: XCTestCase {
    private func down(_ char: DockKeyChar, _ modifiers: DockKeyModifiers = .command) -> DockKeyEvent {
        DockKeyEvent(.down, keyCode: code(char), char: char, modifiers: modifiers)
    }

    private func repeat_(_ char: DockKeyChar, _ modifiers: DockKeyModifiers = .command) -> DockKeyEvent {
        DockKeyEvent(.autorepeat, keyCode: code(char), char: char, modifiers: modifiers)
    }

    private func up(_ char: DockKeyChar, _ modifiers: DockKeyModifiers = .command) -> DockKeyEvent {
        DockKeyEvent(.up, keyCode: code(char), char: char, modifiers: modifiers)
    }

    private func code(_ char: DockKeyChar) -> Int {
        switch char {
        case .w: DockKeyEvent.keyCodeW
        case .m: DockKeyEvent.keyCodeM
        case .h: DockKeyEvent.keyCodeH
        case .q: DockKeyEvent.keyCodeQ
        case .escape: DockKeyEvent.keyCodeEscape
        case .other: DockKeyEvent.keyCodeA
        }
    }

    private func snapshot(_ e: DockEngagement, target: DockKeyTarget = .card(hasAXElement: true, minimized: false))
        -> DockKeySnapshot {
        DockKeySnapshot(engaged: e.engaged, target: target)
    }

    /// Entered at 0, then 5 pt by 0.3 s: engaged.
    private func engaged() -> DockEngagement {
        var e = DockEngagement()
        e.entered(at: 0)
        e.moved(to: DockPoint(x: 100, y: 100), at: 0.05)
        e.moved(to: DockPoint(x: 105, y: 100), at: 0.3)
        return e
    }

    // MARK: Engagement (X3-5)

    /// Drift under 4 pt passes ⌘W through.
    func testDriftUnder4PointsPassesCommandW() {
        var e = DockEngagement()
        e.entered(at: 0)
        e.moved(to: DockPoint(x: 100, y: 100), at: 0.1)
        e.moved(to: DockPoint(x: 101, y: 101), at: 0.4)
        e.moved(to: DockPoint(x: 102, y: 102), at: 0.7)
        XCTAssertFalse(e.engaged)
        var rules = DockKeyRules()
        let s = snapshot(e)
        XCTAssertFalse(rules.tapEnabled(s, at: 0.8))
        XCTAssertEqual(rules.decide(down(.w), s, at: 0.8), .pass)
    }

    /// 4 pt of movement and 250 ms inside the panel, then ⌘Q, quits the previewed app.
    func testMovementAndDwellThenCommandQQuits() {
        let e = engaged()
        XCTAssertTrue(e.engaged)
        var rules = DockKeyRules()
        XCTAssertTrue(rules.tapEnabled(snapshot(e), at: 0.4))
        XCTAssertEqual(rules.decide(down(.q), snapshot(e), at: 0.4), .swallow(.quitApp))
    }

    /// 4 pt within the first 249 ms, then a rest, then ⌘Q, passes through: movement is checked when it happens.
    func testMovementOnlyInTheFirst249MillisecondsPasses() {
        var e = DockEngagement()
        e.entered(at: 0)
        e.moved(to: DockPoint(x: 100, y: 100), at: 0.05)
        e.moved(to: DockPoint(x: 106, y: 100), at: 0.249)
        XCTAssertFalse(e.engaged)
        // A report of the same point (no movement) doesn't engage either.
        e.moved(to: DockPoint(x: 106, y: 100), at: 0.6)
        XCTAssertFalse(e.engaged)
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(down(.q), snapshot(e), at: 0.7), .pass)
    }

    /// After 1.5 s still, a 1 pt drift, then ⌘Q, passes through.
    func testStillFor1500MillisecondsThenDriftPasses() {
        var e = engaged()
        XCTAssertFalse(e.expire(at: 1.79))
        XCTAssertTrue(e.engaged)
        e.moved(to: DockPoint(x: 106, y: 100), at: 1.8)       // expires first: 1.5 s since 0.3
        XCTAssertFalse(e.engaged)
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(down(.q), snapshot(e), at: 1.9), .pass)

        var ticked = engaged()
        XCTAssertTrue(ticked.expire(at: 1.8))
        XCTAssertFalse(ticked.engaged)
    }

    /// 'a', then ⌘Q, passes through: a key-down outside the table disengages.
    func testAThenCommandQPasses() {
        var e = engaged()
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(down(.other, []), snapshot(e), at: 0.4), .passNotInTable)
        XCTAssertTrue(e.notInTable())
        XCTAssertEqual(rules.decide(down(.q), snapshot(e), at: 0.5), .pass)
        // It engages again only by the same rule.
        e.moved(to: DockPoint(x: 110, y: 100), at: 0.6)
        XCTAssertTrue(e.engaged)
    }

    /// A click in the panel engages at once (D2-3); leaving the panel or the panel hiding disengages.
    func testClickEngagesAndExitDisengages() {
        var e = DockEngagement()
        e.entered(at: 0)
        XCTAssertTrue(e.clicked(at: 0.01))
        XCTAssertTrue(e.engaged)
        XCTAssertTrue(e.exited())
        XCTAssertFalse(e.engaged)
        var f = engaged()
        XCTAssertTrue(f.hidden())
        XCTAssertFalse(f.engaged)
        // Re-entering restarts the dwell.
        f.entered(at: 5)
        f.moved(to: DockPoint(x: 0, y: 0), at: 5.01)
        f.moved(to: DockPoint(x: 10, y: 0), at: 5.1)
        XCTAssertFalse(f.engaged)
        f.moved(to: DockPoint(x: 11, y: 0), at: 5.25)
        XCTAssertTrue(f.engaged)
    }

    // MARK: Held keys (X3-4)

    /// A held ⌘W (autorepeat for 1 s) closes one window.
    func testHeldCommandWClosesOneWindow() {
        let s = snapshot(engaged())
        var rules = DockKeyRules()
        var decisions = [rules.decide(down(.w), s, at: 1.0)]
        var t = 1.5
        while t <= 2.0 {
            decisions.append(rules.decide(repeat_(.w), s, at: t))
            t += 0.05
        }
        decisions.append(rules.decide(up(.w), s, at: 2.0))
        XCTAssertEqual(decisions.filter { $0 == .swallow(.close) }.count, 1)
        XCTAssertEqual(decisions.filter { $0 == .swallow(nil) }.count, decisions.count - 1)
        XCTAssertNil(rules.heldKeyCode)
    }

    /// Holding ⌘W for 3 s closes one window, though the next card slides under the pointer.
    func testHoldingCommandWForThreeSecondsClosesOneWindow() {
        let s = snapshot(engaged())
        var rules = DockKeyRules()
        var closes = rules.decide(down(.w), s, at: 1.0) == .swallow(.close) ? 1 : 0
        var t = 1.5
        while t <= 4.0 {
            let d = rules.decide(repeat_(.w), s, at: t)
            XCTAssertEqual(d, .swallow(nil), "\(t)")
            if d == .swallow(.close) { closes += 1 }
            t += 0.083
        }
        XCTAssertEqual(rules.decide(up(.w), s, at: 4.0), .swallow(nil))
        XCTAssertEqual(closes, 1)
    }

    /// A swallowed key's repeats and key-up are swallowed until release, even after the panel hides; the 1 s cap
    /// restarts at each repeat.
    func testRepeatsAndKeyUpAreSwallowedAfterThePanelHides() {
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(down(.w), snapshot(engaged()), at: 0), .swallow(.close))
        let hidden = DockKeySnapshot(engaged: false, target: .none)
        XCTAssertTrue(rules.tapEnabled(hidden, at: 0.5))
        XCTAssertEqual(rules.decide(repeat_(.w), hidden, at: 0.9), .swallow(nil))
        XCTAssertEqual(rules.decide(repeat_(.w), hidden, at: 1.8), .swallow(nil))       // the cap restarted at 0.9
        XCTAssertEqual(rules.holdEndsAt ?? 0, 2.8, accuracy: 1e-9)
        XCTAssertEqual(rules.decide(repeat_(.w), hidden, at: 2.7), .swallow(nil))
        XCTAssertEqual(rules.decide(up(.w), hidden, at: 2.75), .swallow(nil))
        XCTAssertFalse(rules.tapEnabled(hidden, at: 2.76))
        // Released: the next press goes to the app.
        XCTAssertEqual(rules.decide(down(.w), hidden, at: 3.0), .pass)
    }

    /// A lost key-up: the hold ends 1 s after the key-down or the last repeat.
    func testTheHoldEndsAfterTheCap() {
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(down(.w), snapshot(engaged()), at: 0), .swallow(.close))
        let hidden = DockKeySnapshot(engaged: false, target: .none)
        XCTAssertTrue(rules.holding(at: 0.99))
        XCTAssertFalse(rules.holding(at: 1.0))
        XCTAssertFalse(rules.tapEnabled(hidden, at: 1.0))
        XCTAssertEqual(rules.decide(up(.w), hidden, at: 1.2), .pass)
        XCTAssertNil(rules.heldKeyCode)
    }

    /// With "Delay until repeat" on Long (about 1.8 s), the hold outlasts the first repeat, so a held ⌘Q never
    /// reaches the app that came forward (§R4 A5).
    func testALongRepeatDelayKeepsTheHoldUntilTheFirstRepeat() {
        var rules = DockKeyRules(repeatDelay: 1.8)
        XCTAssertEqual(rules.cap, 2.0, accuracy: 1e-9)
        XCTAssertEqual(rules.decide(down(.q), snapshot(engaged()), at: 1.0), .swallow(.quitApp))
        let hidden = DockKeySnapshot(engaged: false, target: .none)
        XCTAssertTrue(rules.holding(at: 2.7))
        XCTAssertEqual(rules.decide(repeat_(.q), hidden, at: 2.8), .swallow(nil))
        XCTAssertEqual(rules.decide(up(.q), hidden, at: 3.0), .swallow(nil))
        XCTAssertEqual(DockKeyRules(repeatDelay: 0.25).cap, DockKeyRules.holdCap)
    }

    /// Holding ⌘Q over the last card quits one app, and nothing reaches the next app.
    func testHoldingCommandQQuitsOneApp() {
        var rules = DockKeyRules()
        var decisions = [rules.decide(down(.q), snapshot(engaged()), at: 1.0)]
        // The app quits and the panel hides; the next app comes forward under the held key.
        let hidden = DockKeySnapshot(engaged: false, target: .none)
        var t = 1.5
        while t <= 4.0 {
            decisions.append(rules.decide(repeat_(.q), hidden, at: t))
            t += 0.083
        }
        decisions.append(rules.decide(up(.q), hidden, at: 4.0))
        XCTAssertEqual(decisions.first, .swallow(.quitApp))
        XCTAssertEqual(decisions.filter { $0 == .swallow(.quitApp) }.count, 1)
        XCTAssertFalse(decisions.contains(.pass))
        XCTAssertFalse(decisions.contains(.passNotInTable))
    }

    /// Another key while one is held is decided on its own.
    func testAnotherKeyWhileHeld() {
        var rules = DockKeyRules()
        let s = snapshot(engaged())
        XCTAssertEqual(rules.decide(down(.w), s, at: 0), .swallow(.close))
        XCTAssertEqual(rules.decide(down(.m), s, at: 0.2), .swallow(.minimize))
        XCTAssertEqual(rules.heldKeyCode, DockKeyEvent.keyCodeM)
    }

    // MARK: Reflow, targets and Esc

    /// Table keys do nothing for 300 ms after a card closes or minimizes.
    func testReflowSwallowsFor300Milliseconds() {
        var rules = DockKeyRules()
        var s = snapshot(engaged())
        s.reflowStartedAt = 1.0
        XCTAssertEqual(rules.decide(down(.w), s, at: 1.1), .swallow(nil))
        XCTAssertEqual(rules.decide(up(.w), s, at: 1.15), .swallow(nil))
        XCTAssertEqual(rules.decide(down(.w), s, at: 1.29), .swallow(nil))
        XCTAssertEqual(rules.decide(up(.w), s, at: 1.295), .swallow(nil))
        XCTAssertEqual(rules.decide(down(.w), s, at: 1.3), .swallow(.close))
    }

    /// Esc is swallowed as `escape`; the policy hides with it (see `DockPreviewPolicyTests`).
    func testEscape() {
        var rules = DockKeyRules()
        let s = snapshot(engaged())
        XCTAssertEqual(rules.decide(down(.escape, []), s, at: 1), .swallow(.escape))
        XCTAssertEqual(rules.decide(up(.escape, []), s, at: 1.1), .swallow(nil))
        XCTAssertEqual(rules.decide(down(.escape, .command), s, at: 2), .passNotInTable)
    }

    /// ⌘Q on Finder and a key with no target are swallowed and do nothing.
    func testFinderAndKeysWithNoTarget() {
        var finder = snapshot(engaged())
        finder.appIsFinder = true
        XCTAssertEqual(DockKeyRules.action(.q, finder), nil)
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(down(.q), finder, at: 1), .swallow(nil))

        let e = engaged()
        for target in [DockKeyTarget.header, .gap, .none, .card(hasAXElement: false, minimized: false)] {
            XCTAssertEqual(DockKeyRules.action(.w, snapshot(e, target: target)), nil, "\(target)")
            XCTAssertEqual(DockKeyRules.action(.m, snapshot(e, target: target)), nil, "\(target)")
            var r = DockKeyRules()
            XCTAssertEqual(r.decide(down(.w), snapshot(e, target: target), at: 1), .swallow(nil), "\(target)")
        }
        XCTAssertEqual(DockKeyRules.action(.m, snapshot(e, target: .card(hasAXElement: true, minimized: true))), .restore)
        // ⌘H acts on the app, so it works over the header or a gap.
        XCTAssertEqual(DockKeyRules.action(.h, snapshot(e, target: .header)), .hideApp)
        var hidden = snapshot(e, target: .gap)
        hidden.appHidden = true
        XCTAssertEqual(DockKeyRules.action(.h, hidden), .showApp)
        // M23: ⌘Q quits the previewed app only with a card under the pointer (any card, even one that offers only
        // Bring Forward); over the header, a gap or nothing it's swallowed and does nothing.
        for target in [DockKeyTarget.header, .gap, .none] {
            XCTAssertEqual(DockKeyRules.action(.q, snapshot(e, target: target)), nil, "\(target)")
            var r = DockKeyRules()
            XCTAssertEqual(r.decide(down(.q), snapshot(e, target: target), at: 1), .swallow(nil), "\(target)")
        }
        XCTAssertEqual(DockKeyRules.action(.q, snapshot(e, target: .card(hasAXElement: false, minimized: false))),
                       .quitApp)
        XCTAssertEqual(DockKeyRules.action(.q, snapshot(e, target: .card(hasAXElement: true, minimized: true))),
                       .quitApp)
    }

    // MARK: When the tap runs

    /// Secure input on or unknown never engages (X2-2).
    func testSecureInputOnOrUnknownNeverEngages() {
        for secure in [DockSecureInput.on, .unknown] {
            var s = snapshot(engaged())
            s.secureInput = secure
            var rules = DockKeyRules()
            XCTAssertFalse(DockKeyRules.active(s), "\(secure)")
            XCTAssertFalse(rules.tapEnabled(s, at: 1), "\(secure)")
            XCTAssertEqual(rules.decide(down(.w), s, at: 1), .pass, "\(secure)")
        }
    }

    /// Never engaged while the switcher is active, even with a key held.
    func testNeverEngagedWhileTheSwitcherIsActive() {
        var rules = DockKeyRules()
        var s = snapshot(engaged())
        XCTAssertEqual(rules.decide(down(.w), s, at: 0), .swallow(.close))
        s.switcherActive = true
        XCTAssertFalse(DockKeyRules.active(s))
        XCTAssertFalse(rules.tapEnabled(s, at: 0.1))
        XCTAssertEqual(rules.decide(repeat_(.w), s, at: 0.2), .pass)
        XCTAssertNil(rules.heldKeyCode)
    }

    /// Keys don't work with the setting off, a kill switch or a tripped breaker.
    func testKeysOff() {
        var s = snapshot(engaged())
        s.keysWork = false
        var rules = DockKeyRules()
        XCTAssertFalse(rules.tapEnabled(s, at: 1))
        XCTAssertEqual(rules.decide(down(.w), s, at: 1), .pass)
    }

    /// The five table keys: ⌘ alone with W, M, H or Q, and Esc alone (M40).
    func testTableKeys() {
        XCTAssertTrue(down(.w).isTableKey)
        XCTAssertTrue(down(.m).isTableKey)
        XCTAssertTrue(down(.h).isTableKey)
        XCTAssertTrue(down(.q).isTableKey)
        XCTAssertTrue(down(.escape, []).isTableKey)
        XCTAssertFalse(down(.w, []).isTableKey)
        XCTAssertFalse(down(.w, [.command, .shift]).isTableKey)
        XCTAssertFalse(down(.q, [.command, .option]).isTableKey)
        XCTAssertFalse(down(.escape, .control).isTableKey)
        XCTAssertFalse(down(.other).isTableKey)
        // An autorepeat of a key that wasn't swallowed passes.
        var rules = DockKeyRules()
        XCTAssertEqual(rules.decide(repeat_(.other), snapshot(engaged()), at: 1), .pass)
        XCTAssertEqual(rules.decide(up(.other), snapshot(engaged()), at: 1), .pass)
    }
}
