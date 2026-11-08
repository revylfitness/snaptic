import XCTest
@testable import SnapticKit

/// 0.4 K4: `IconsPolicy` (§4.3, §4.5, §4.6, §4.10, §4.11, §4.12, §4.2.5).
final class IconsClickTests: XCTestCase {
    /// Hidden Bar's six click cases, remapped (§4.3).
    func testTheSixClickCases() {
        XCTAssertEqual(IconsClicks.action(for: nil), .toggle)                                    // VoiceOver press
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .left)), .toggle)
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .right)), .menu)
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .left, option: true)), .toggleAll)
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .right, option: true)), .toggleAll)
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .other)), .menu)
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .left, control: true)), .menu)
        // ⌥ + any button shows all, even with ⌃ or a third button.
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .other, option: true)), .toggleAll)
        XCTAssertEqual(IconsClicks.action(for: IconsClickEvent(button: .left, option: true, control: true)), .toggleAll)
    }

    /// The table in §4.3, every command × every target.
    func testTheResolveTable() {
        let collapsed = IconsTarget.collapsed, plain = IconsTarget.expanded(.plain), all = IconsTarget.expanded(.all)
        let table: [(IconsCommand, IconsTarget, IconsOperation?)] = [
            (.toggle, collapsed, .expand(.plain)), (.toggle, plain, .collapse), (.toggle, all, .collapse),
            (.toggleAll, collapsed, .expand(.all)), (.toggleAll, plain, .expand(.all)), (.toggleAll, all, .collapse),
            (.show, collapsed, .expand(.plain)), (.show, plain, nil), (.show, all, nil),
            (.showAll, collapsed, .expand(.all)), (.showAll, plain, .expand(.all)), (.showAll, all, nil),
            (.hide, collapsed, nil), (.hide, plain, .collapse), (.hide, all, .collapse),
        ]
        for (command, target, want) in table {
            XCTAssertEqual(IconsClicks.resolve(command, target: target), want, "\(command) at \(target)")
        }
    }

    func testTargetFromState() {
        XCTAssertEqual(IconsTarget(.collapsed), .collapsed)
        XCTAssertEqual(IconsTarget(.calibrating), .collapsed)
        XCTAssertEqual(IconsTarget(.expanded(.all)), .expanded(.all))
        XCTAssertEqual(IconsTarget(.unavailable(.killSwitch)), .expanded(.plain))
    }
}

final class IconsAutoCollapseTests: XCTestCase {
    func testEnabledNeedsArranged() {
        var c = IconsConfig()
        XCTAssertFalse(IconsAutoCollapse.enabled(c), "nothing hides on its own before the first collapse (§4.0)")
        c.arranged = true
        XCTAssertTrue(IconsAutoCollapse.enabled(c))
        c.autoCollapse = false
        XCTAssertFalse(IconsAutoCollapse.enabled(c))
    }

    func testClampAndRestart() {
        XCTAssertEqual(IconsAutoCollapse(seconds: 1).seconds, 5)
        XCTAssertEqual(IconsAutoCollapse(seconds: 999).seconds, 300)
        var t = IconsAutoCollapse(seconds: 10)
        t.setSeconds(20, now: 0)
        XCTAssertNil(t.deadline, "a stopped timer stays stopped")
        t.arm(now: 0)
        t.setSeconds(30, now: 5)
        XCTAssertEqual(t.deadline, 35, "a settings change restarts the timer")
    }

    func testCollapsesWhenNothingHolds() {
        var t = IconsAutoCollapse(seconds: 10)
        XCTAssertEqual(t.fire(now: 0, facts: IconsRearmFacts()), .idle)
        t.arm(now: 0)
        XCTAssertEqual(t.fire(now: 5, facts: IconsRearmFacts()), .wait(until: 10))
        XCTAssertEqual(t.fire(now: 10, facts: IconsRearmFacts()), .collapse)
        XCTAssertNil(t.deadline)
    }

    func testEachReasonRearms() {
        let cases: [(IconsRearmReason, (inout IconsRearmFacts) -> Void)] = [
            (.pointerInBand, { $0.pointerInBand = true }),
            (.snapticWindow, { $0.snapticWindowVisible = true }),
            (.menuOpen, { $0.menuOpen = true }),
            (.popoverNearBand, { $0.popoverNearBand = true }),
            (.hiddenListPress, { $0.lastHiddenListPress = 50 }),
            (.voiceOverOnExtra, { $0.voiceOverOnExtra = true }),
            (.ownMenuOpen, { $0.ownMenuOpen = true }),
        ]
        XCTAssertEqual(cases.map(\.0), IconsRearmReason.allCases)
        for (reason, set) in cases {
            var facts = IconsRearmFacts()
            set(&facts)
            var t = IconsAutoCollapse(seconds: 10)
            t.arm(now: 90)
            XCTAssertEqual(t.fire(now: 100, facts: facts), .rearm([reason], until: 110), reason.rawValue)
        }
    }

    func testPointerInFullScreenDoesNotCount() {
        var facts = IconsRearmFacts()
        facts.pointerInBand = true
        facts.fullScreen = true
        XCTAssertEqual(facts.reasons(now: 0), [])
    }

    func testHiddenListGraceIs60s() {
        var facts = IconsRearmFacts()
        facts.lastHiddenListPress = 0
        XCTAssertEqual(facts.reasons(now: 59.9), [.hiddenListPress])
        XCTAssertEqual(facts.reasons(now: 60), [])
    }

    /// Window-based reasons stop after 120 s in a row; the others never do.
    func testWindowReasonsCapAt120s() {
        var t = IconsAutoCollapse(seconds: 10)
        var facts = IconsRearmFacts()
        facts.menuOpen = true
        t.arm(now: 0)
        var now = 10.0
        while now < 130 {
            XCTAssertEqual(t.fire(now: now, facts: facts), .rearm([.menuOpen], until: now + 10), "\(now)")
            now += 10
        }
        XCTAssertEqual(t.fire(now: 130, facts: facts), .collapse, "120 s after the first window-based re-arm")

        // A pointer in the band still holds after the cap.
        t.arm(now: 0)
        facts.pointerInBand = true
        for now in stride(from: 10.0, through: 300, by: 10) {
            guard case .rearm(let reasons, _) = t.fire(now: now, facts: facts) else { return XCTFail("\(now)") }
            XCTAssertTrue(reasons.contains(.pointerInBand))
            XCTAssertEqual(reasons.contains(.menuOpen), now - 10 < 120, "\(now)")
        }
    }

    func testCapResetsWhenWindowReasonsStop() {
        var t = IconsAutoCollapse(seconds: 10)
        var held = IconsRearmFacts()
        held.popoverNearBand = true
        var pointer = IconsRearmFacts()
        pointer.pointerInBand = true
        t.arm(now: 0)
        for now in stride(from: 10.0, through: 100, by: 10) { _ = t.fire(now: now, facts: held) }
        _ = t.fire(now: 110, facts: pointer)
        XCTAssertNil(t.windowSince)
        XCTAssertEqual(t.fire(now: 120, facts: held), .rearm([.popoverNearBand], until: 130))
        XCTAssertEqual(t.windowSince, 120)
    }
}

final class IconsHoverTests: XCTestCase {
    func testActive() {
        XCTAssertTrue(IconsHoverDwell.active(hover: true, collapsed: true, killSwitches: []))
        XCTAssertFalse(IconsHoverDwell.active(hover: false, collapsed: true, killSwitches: []))
        XCTAssertFalse(IconsHoverDwell.active(hover: true, collapsed: false, killSwitches: []))
        XCTAssertFalse(IconsHoverDwell.active(hover: true, collapsed: true, killSwitches: [.hover]))
    }

    func testDwellFiresOncePerEntry() {
        var d = IconsHoverDwell()
        XCTAssertFalse(d.sample(inBand: true, now: 0))
        XCTAssertEqual(d.due, 0.5)
        XCTAssertFalse(d.sample(inBand: true, now: 0.49))
        XCTAssertTrue(d.sample(inBand: true, now: 0.5))
        XCTAssertFalse(d.sample(inBand: true, now: 2))
        XCTAssertNil(d.due)
        XCTAssertFalse(d.sample(inBand: false, now: 2.1))
        XCTAssertFalse(d.sample(inBand: true, now: 3))
        XCTAssertTrue(d.sample(inBand: true, now: 3.6))
    }

    func testLeavingTheBandResets() {
        var d = IconsHoverDwell()
        _ = d.sample(inBand: true, now: 0)
        _ = d.sample(inBand: false, now: 0.3)
        XCTAssertFalse(d.sample(inBand: true, now: 0.6))
        XCTAssertTrue(d.sample(inBand: true, now: 1.1))
    }
}

final class IconsLaunchTests: XCTestCase {
    let sections: [String: IconsSection] = ["com.a": .hidden, "com.b": .shown]

    func testGatePasses() {
        var g = IconsStableGate(startedAt: 0)
        XCTAssertEqual(g.read(sections, at: 1, uptime: 500), .pending)
        XCTAssertEqual(g.read(sections, at: 2, uptime: 501), .pending, "less than 2 s apart")
        XCTAssertEqual(g.read(sections, at: 3, uptime: 502), .passed, "2 s after the first matching read")
        XCTAssertEqual(g.read(nil, at: 4, uptime: 503), .passed, "final")
    }

    func testGateNeedsMatchingReads() {
        var g = IconsStableGate(startedAt: 0)
        _ = g.read(sections, at: 1, uptime: 500)
        XCTAssertEqual(g.read(["com.a": .shown], at: 3, uptime: 502), .pending)
        XCTAssertEqual(g.read(sections, at: 5, uptime: 504), .pending)
        XCTAssertEqual(g.read(sections, at: 7, uptime: 506), .passed)
    }

    func testUnusableReadBreaksTheRun() {
        var g = IconsStableGate(startedAt: 0)
        _ = g.read(sections, at: 1, uptime: 500)
        _ = g.read(nil, at: 2, uptime: 501)
        XCTAssertEqual(g.read(sections, at: 3, uptime: 502), .pending)
        XCTAssertEqual(g.read(sections, at: 5, uptime: 504), .passed)
    }

    func testGateNeedsUptimeAndFailsAfter30s() {
        var g = IconsStableGate(startedAt: 0)
        _ = g.read(sections, at: 1, uptime: 20)
        XCTAssertEqual(g.read(sections, at: 3, uptime: 22), .pending, "uptime ≤ 60 s")
        XCTAssertEqual(g.read(sections, at: 30, uptime: 49), .pending)
        XCTAssertEqual(g.read(sections, at: 30.5, uptime: 61), .failed, "the cap ran out first")
        var h = IconsStableGate(startedAt: 0)
        XCTAssertEqual(h.expire(at: 30), .pending)
        XCTAssertEqual(h.expire(at: 30.1), .failed)
    }

    func testLaunchDecision() {
        func facts(_ edit: (inout IconsLaunchFacts) -> Void = { _ in }) -> IconsLaunchFacts {
            var f = IconsLaunchFacts(collapseAtLaunch: true, arranged: true, gate: .passed)
            edit(&f)
            return f
        }
        XCTAssertEqual(IconsLaunchCollapse.decide(facts()), .collapse)
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.gate = .pending }), .wait)
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.gate = .failed }), .skip(.unstableInventory))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.collapseAtLaunch = false }), .skip(.off))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.arranged = false }), .skip(.notArranged))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.alreadyDecided = true }), .skip(.alreadyDecided))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.versionChanged = true }), .skip(.versionChanged))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.osBuildChanged = true }), .skip(.osBuildChanged))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.unstableLaunch = true }), .skip(.unstableLaunch))
        XCTAssertEqual(IconsLaunchCollapse.decide(facts { $0.userActed = true }), .skip(.userActed))
    }
}

final class IconsNewIconsTests: XCTestCase {
    let day = 86_400.0

    func testFirstSightingIsNewAndKnownLaunchIsNot() {
        let read = IconsSighting(placed: ["com.a": .hidden, "com.b": .shown], present: [])
        let first = IconsNewIcons.unrestrictedRead(read, now: 1000, state: IconsAppsState())
        XCTAssertEqual(first.new, ["com.a", "com.b"])
        XCTAssertEqual(first.state.knownBundles["com.a"],
                       IconsKnownBundle(section: .hidden, firstSeen: 1000, lastSeen: 1000))
        let again = IconsNewIcons.unrestrictedRead(read, now: 2000, state: first.state)
        XCTAssertEqual(again.new, [], "a known bundle is never new (no login-item burst)")
        XCTAssertEqual(again.state.knownBundles["com.a"]?.firstSeen, 1000)
        XCTAssertEqual(again.state.knownBundles["com.a"]?.lastSeen, 2000)
    }

    func testPresentButUnplacedKeepsItsSection() {
        let placed = IconsSighting(placed: ["com.a": .hidden], present: [])
        let s = IconsNewIcons.unrestrictedRead(placed, now: 1, state: IconsAppsState()).state
        let offScreen = IconsSighting(placed: [:], present: ["com.a"])
        let t = IconsNewIcons.unrestrictedRead(offScreen, now: 2, state: s).state
        XCTAssertEqual(t.knownBundles["com.a"]?.section, .hidden)
        XCTAssertEqual(t.knownBundles["com.a"]?.missedReads, 0)
    }

    func testDroppedAfterThreeMissedReads() {
        var s = IconsNewIcons.unrestrictedRead(IconsSighting(placed: ["com.a": .shown, "com.b": .shown], present: []),
                                               now: 1, state: IconsAppsState()).state
        let onlyB = IconsSighting(placed: ["com.b": .shown], present: [])
        for i in 1...2 {
            let u = IconsNewIcons.unrestrictedRead(onlyB, now: Double(1 + i), state: s)
            XCTAssertEqual(u.dropped, [])
            XCTAssertEqual(u.state.knownBundles["com.a"]?.missedReads, i)
            s = u.state
        }
        // Seen again: the count resets.
        let back = IconsNewIcons.unrestrictedRead(IconsSighting(placed: [:], present: ["com.a", "com.b"]), now: 4,
                                                  state: s)
        XCTAssertEqual(back.state.knownBundles["com.a"]?.missedReads, 0)
        s = back.state
        for i in 1...3 {
            let u = IconsNewIcons.unrestrictedRead(onlyB, now: Double(4 + i), state: s)
            XCTAssertEqual(u.dropped, i == 3 ? ["com.a"] : [])
            s = u.state
        }
        XCTAssertNil(s.knownBundles["com.a"])
        XCTAssertEqual(IconsNewIcons.unrestrictedRead(IconsSighting(placed: ["com.a": .shown], present: []), now: 9,
                                                      state: s).new, ["com.a"])
    }

    func testInvalidBundlesAreIgnored() {
        let u = IconsNewIcons.unrestrictedRead(IconsSighting(placed: ["not a bundle": .shown], present: [""]), now: 1,
                                               state: IconsAppsState())
        XCTAssertEqual(u.new, [])
        XCTAssertTrue(u.state.knownBundles.isEmpty)
    }

    /// Native Show: a new bundle seen while restricted joins `newShown`; the next unrestricted read that places it
    /// takes it out.
    func testShowKeepsNewIconsUntilPlaced() {
        var s = IconsAppsState()
        s.knownBundles["com.known"] = IconsKnownBundle(section: .hidden, firstSeen: 1, lastSeen: 1)
        let restricted = IconsSighting(placed: [:], present: ["com.known", "com.new"])
        let u = IconsNewIcons.restrictedRead(restricted, now: 10, policy: .show, state: s)
        XCTAssertEqual(u.new, ["com.new"])
        XCTAssertEqual(u.state.newShown, ["com.new": 10])
        XCTAssertTrue(u.newShownChanged)
        XCTAssertNil(u.state.knownBundles["com.new"], "restricted reads record nothing")
        let again = IconsNewIcons.restrictedRead(restricted, now: 20, policy: .show, state: u.state)
        XCTAssertEqual(again.state.newShown, ["com.new": 20], "seen again: last seen moves")
        XCTAssertFalse(again.newShownChanged, "same bundles: the allow-list is unchanged")

        let present = IconsNewIcons.unrestrictedRead(IconsSighting(placed: [:], present: ["com.new"]), now: 30,
                                                     state: again.state)
        XCTAssertEqual(present.state.newShown, ["com.new": 30], "present but not placed: still shown")
        let placed = IconsNewIcons.unrestrictedRead(IconsSighting(placed: ["com.new": .hidden], present: []), now: 40,
                                                    state: present.state)
        XCTAssertEqual(placed.state.newShown, [:])
        XCTAssertTrue(placed.newShownChanged)
        XCTAssertEqual(placed.state.knownBundles["com.new"]?.section, .hidden)
    }

    func testHideAndChoicesNeverJoin() {
        let read = IconsSighting(placed: [:], present: ["com.new"])
        let hide = IconsNewIcons.restrictedRead(read, now: 1, policy: .hide, state: IconsAppsState())
        XCTAssertEqual(hide.new, ["com.new"], "listed as New in the hidden list")
        XCTAssertEqual(hide.state.newShown, [:])
        var s = IconsAppsState()
        s.choices["com.new"] = .alwaysHide
        XCTAssertEqual(IconsNewIcons.restrictedRead(read, now: 1, policy: .show, state: s).state.newShown, [:])
    }

    func testChoosingAndExpiry() {
        var s = IconsAppsState()
        s.newShown = ["com.a": 0 + day, "com.b": 31 * day]
        XCTAssertEqual(IconsNewIcons.chose("com.a", state: s).newShown, ["com.b": 31 * day])
        XCTAssertEqual(IconsNewIcons.expired(s.newShown, now: 31 * day), s.newShown, "exactly 30 days: kept")
        XCTAssertEqual(IconsNewIcons.expired(s.newShown, now: 31 * day + 1), ["com.b": 31 * day])
        let u = IconsNewIcons.restrictedRead(IconsSighting(placed: [:], present: []), now: 40 * day, policy: .show,
                                             state: s)
        XCTAssertEqual(u.state.newShown, ["com.b": 31 * day])
        XCTAssertTrue(u.newShownChanged)
    }

    func testLRUAtTheCap() {
        var shown: [String: Double] = [:]
        for i in 0..<IconsAppsState.newShownCap { shown["com.app\(i)"] = Double(100 + i) }
        shown["com.tie"] = 100
        shown["com.app0"] = nil
        let out = IconsNewIcons.inserting("com.newest", at: 1000, into: shown)
        XCTAssertEqual(out.count, IconsAppsState.newShownCap)
        XCTAssertEqual(out["com.newest"], 1000)
        XCTAssertNil(out["com.tie"], "the least recently seen goes")
        XCTAssertEqual(out["com.app1"], 101)
    }

    func testDailyToast() {
        let s = IconsAppsState()
        XCTAssertFalse(IconsNewIcons.toastDue("com.a", now: day, inventoryExists: false, state: s))
        XCTAssertTrue(IconsNewIcons.toastDue("com.a", now: day, inventoryExists: true, state: s))
        let t = IconsNewIcons.toasted("com.a", now: day + 10, state: s)
        XCTAssertEqual(t.toasts["com.a"], 1)
        XCTAssertFalse(IconsNewIcons.toastDue("com.a", now: 2 * day - 1, inventoryExists: true, state: t))
        XCTAssertTrue(IconsNewIcons.toastDue("com.a", now: 2 * day, inventoryExists: true, state: t))
        XCTAssertTrue(IconsNewIcons.toastDue("com.b", now: day, inventoryExists: true, state: t))
    }

    func testWatchAndRereads() {
        XCTAssertEqual(IconsNewIcons.rereadDelays, [2, 10, 30])
        XCTAssertTrue(IconsNewIcons.watchesLaunches(engine: .native, assertionActive: true, collapsed: false))
        XCTAssertFalse(IconsNewIcons.watchesLaunches(engine: .native, assertionActive: false, collapsed: true))
        XCTAssertTrue(IconsNewIcons.watchesLaunches(engine: .length, assertionActive: false, collapsed: true))
        XCTAssertFalse(IconsNewIcons.watchesLaunches(engine: .length, assertionActive: true, collapsed: false))
    }

    func testSightingFromALayout() {
        let screen = IconsRect(x: 0, y: 0, width: 1000, height: 24)
        func extra(_ pid: Int32, _ id: String, x: Double) -> IconsExtra {
            IconsExtra(pid: pid, bundleID: id, index: 0, frame: IconsRect(x: x, y: 0, width: 20, height: 22))
        }
        let inventory = IconsInventory(apps: [
            IconsAppRead(pid: 2, bundleID: "com.shown", bundlePath: "/Applications/S.app", result: .ok,
                         extras: [extra(2, "com.shown", x: 900)]),
            IconsAppRead(pid: 3, bundleID: "com.hidden", bundlePath: "/Applications/H.app", result: .ok,
                         extras: [extra(3, "com.hidden", x: 400)]),
            IconsAppRead(pid: 4, bundleID: "com.off", bundlePath: "/Applications/O.app", result: .ok,
                         extras: [extra(4, "com.off", x: -5000)]),
            IconsAppRead(pid: 5, bundleID: "com.slow", bundlePath: "/Applications/T.app", result: .timedOut),
            IconsAppRead(pid: 6, bundleID: "com.apple.x", bundlePath: "/System/Library/X.app", result: .ok,
                         extras: [extra(6, "com.apple.x", x: 950)]),
        ])
        let boundaries = IconsBoundaries(hidden: IconsRect(x: 600, y: 0, width: 20, height: 22))
        guard let layout = IconsLayoutResolver.resolve(inventory, boundaries: boundaries, screen: screen,
                                                       skip: IconsSkipRules(ownPID: 1, ownBundlePath: nil),
                                                       previous: ["com.slow": .hidden]).layout else {
            return XCTFail("usable")
        }
        let sighting = IconsSighting(layout: layout)
        XCTAssertEqual(sighting.placed, ["com.shown": .shown, "com.hidden": .hidden])
        XCTAssertEqual(sighting.present, ["com.shown", "com.hidden", "com.off", "com.slow"])

        let restricted = IconsSighting(inventory: inventory, skip: IconsSkipRules(ownPID: 1, ownBundlePath: nil))
        XCTAssertEqual(restricted.placed, [:])
        XCTAssertEqual(restricted.present, ["com.shown", "com.hidden", "com.off"])
    }
}

final class IconsOwnItemsGuardTests: XCTestCase {
    func placement(toggleBeyond: Bool = false, beyond: [String] = [], awake: Bool = false,
                   known: Bool = true) -> IconsOwnItemsPlacement {
        IconsOwnItemsPlacement(known: known, toggleBeyond: toggleBeyond, beyond: beyond, awakeBeyond: awake,
                               unplaced: [])
    }

    func testTheRules() {
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(), awakeHolding: false, collapsed: false), .ok)
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(known: false), awakeHolding: false, collapsed: false),
                       IconsOwnItemsDecision(refuse: true, expand: false, row: nil))
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(toggleBeyond: true), awakeHolding: false, collapsed: false),
                       IconsOwnItemsDecision(refuse: true, expand: false, row: .arrowHidden))
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(beyond: ["Snaptic.main"]), awakeHolding: false,
                                                 collapsed: true),
                       IconsOwnItemsDecision(refuse: false, expand: false, row: .someHidden))
        // Awake holding: any Snaptic item beyond refuses, and expands at once if collapsed.
        for collapsed in [false, true] {
            XCTAssertEqual(IconsOwnItemsGuard.decide(placement(beyond: ["Snaptic.main"]), awakeHolding: true,
                                                     collapsed: collapsed),
                           IconsOwnItemsDecision(refuse: true, expand: collapsed, row: .awakeHidden))
            XCTAssertEqual(IconsOwnItemsGuard.decide(placement(beyond: ["Snaptic.awake"], awake: true),
                                                     awakeHolding: true, collapsed: collapsed),
                           IconsOwnItemsDecision(refuse: true, expand: collapsed, row: .awakeHidden))
        }
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(beyond: ["Snaptic.awake"], awake: true),
                                                 awakeHolding: false, collapsed: true).row, .someHidden)
    }

    func testANewItemWhileCollapsedExpands() {
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(), awakeHolding: false, collapsed: true, appeared: true),
                       IconsOwnItemsDecision(refuse: false, expand: true, row: nil))
        XCTAssertEqual(IconsOwnItemsGuard.decide(placement(), awakeHolding: false, collapsed: false, appeared: true),
                       .ok)
    }

    /// End to end with K2's placement.
    func testWithThePlacement() {
        let sep = IconsRect(x: 500, y: 0, width: 20, height: 22)
        let toggle = IconsRect(x: 600, y: 0, width: 20, height: 22)
        let items = [IconsOwnItem(id: "Snaptic.main", frame: IconsRect(x: 700, y: 0, width: 20, height: 22)),
                     IconsOwnItem(id: "Snaptic.awake", frame: IconsRect(x: 300, y: 0, width: 20, height: 22),
                                  isAwake: true)]
        let p = IconsGuards.ownItemsPlacement(toggle: toggle, separator: sep, items: items, rightToLeft: false)
        XCTAssertEqual(IconsOwnItemsGuard.decide(p, awakeHolding: true, collapsed: false).row, .awakeHidden)
        XCTAssertEqual(IconsOwnItemsGuard.decide(.unknown, awakeHolding: false, collapsed: false).refuse, true)
    }
}

final class IconsSafetyPolicyTests: XCTestCase {
    func testHiderPause() {
        let hb = IconsRunningApp(bundleID: "com.dwarvesv.minimalbar", teamID: "W777S7V8TN")
        let spoof = IconsRunningApp(bundleID: "com.dwarvesv.minimalbar", teamID: "AAAAAAAAAA")
        let other = IconsRunningApp(bundleID: "com.example.app", teamID: nil)
        XCTAssertEqual(IconsHiderPause.pausedFor(policy: .pause, running: [other, hb])?.name, "Hidden Bar")
        XCTAssertNil(IconsHiderPause.pausedFor(policy: .runBoth, running: [hb]))
        XCTAssertNil(IconsHiderPause.pausedFor(policy: .pause, running: [other, spoof]))
        XCTAssertNil(IconsHiderPause.pausedFor(policy: .pause, running: []))
        XCTAssertEqual(IconsHiderPause.pausedFor(policy: .pause,
                                                 running: [IconsRunningApp(bundleID: "com.stonerl.Thaw.beta",
                                                                           teamID: "A7CKWF99ML")])?.name, "Thaw")
    }

    func testExamGuard() {
        XCTAssertFalse(IconsExamGuard.active(system: []))
        for flag in IconsPresentationFlag.allCases {
            XCTAssertTrue(IconsExamGuard.active(system: [flag]), flag.rawValue)
            XCTAssertFalse(IconsExamGuard.active(system: [flag], own: [flag]), "Snaptic's own isn't an exam")
        }
        XCTAssertTrue(IconsExamGuard.active(system: [.disableForceQuit, .disableProcessSwitching],
                                            own: [.disableForceQuit]))
        XCTAssertTrue(IconsExamGuard.polls(engine: .native, assertionActive: true))
        XCTAssertFalse(IconsExamGuard.polls(engine: .native, assertionActive: false))
        XCTAssertFalse(IconsExamGuard.polls(engine: .length, assertionActive: true))
    }

    func testRecovery() {
        XCTAssertEqual(IconsRecovery.plan(.agentTerminated, intentHidden: true),
                       IconsRecoveryPlan(failSafe: .agentRestart, recollapseAfter: nil))
        XCTAssertEqual(IconsRecovery.plan(.agentLaunched, intentHidden: true),
                       IconsRecoveryPlan(failSafe: nil, recollapseAfter: 2))
        XCTAssertEqual(IconsRecovery.plan(.agentLaunched, intentHidden: false),
                       IconsRecoveryPlan(failSafe: nil, recollapseAfter: nil))
        XCTAssertEqual(IconsRecovery.plan(.session, intentHidden: true),
                       IconsRecoveryPlan(failSafe: .session, recollapseAfter: 2))
        XCTAssertEqual(IconsRecovery.plan(.session, intentHidden: false),
                       IconsRecoveryPlan(failSafe: .session, recollapseAfter: nil))
    }

    func testCollapseGatesInOrder() {
        var f = IconsCollapseFacts(engine: .native)
        XCTAssertNil(IconsCollapseGates.refusal(f))
        f.identityOK = false
        XCTAssertEqual(IconsCollapseGates.refusal(f), .identity)
        f.ownItems = IconsOwnItemsDecision(refuse: true, expand: false, row: .arrowHidden)
        XCTAssertEqual(IconsCollapseGates.refusal(f), .identity, "Native has no own-items guard")
        f.gate = .pending
        XCTAssertEqual(IconsCollapseGates.refusal(f), .unstableInventory)
        f.access = .revoked
        XCTAssertEqual(IconsCollapseGates.refusal(f), .needsPermission)
        f.pausedFor = KnownMenuBarHiders.all[0]
        XCTAssertEqual(IconsCollapseGates.refusal(f), .paused)
        f.exam = true
        XCTAssertEqual(IconsCollapseGates.refusal(f), .exam)

        var l = IconsCollapseFacts(engine: .length)
        l.access = .notGranted
        l.identityOK = false
        XCTAssertNil(IconsCollapseGates.refusal(l), "on 14–26 permission and identity don't gate the collapse")
        l.ownItems = IconsOwnItemsDecision(refuse: true, expand: false, row: .arrowHidden)
        XCTAssertEqual(IconsCollapseGates.refusal(l), .ownItems)
        l.gate = .passed
        XCTAssertEqual(IconsCollapseGates.refusal(l), .ownItems)
    }
}

/// §4.12's state table.
final class IconsAccessTests: XCTestCase {
    func testTheTable() {
        XCTAssertEqual(IconsAccessState.allCases.filter(\.needsPermission), [.notGranted, .notEffective, .revoked])
        XCTAssertEqual(IconsAccessState.allCases.filter(\.arrowOpensSettings), [.notGranted, .notEffective, .revoked])
        XCTAssertNil(IconsAccessState.granted.cliState)
        XCTAssertEqual(IconsAccessState.revoked.cliState, "needsPermission")
        XCTAssertEqual(IconsAccessState.allCases.filter(\.offersRelaunch), [.notEffective])
        XCTAssertTrue(IconsAccessTracker.blocksCollapse(engine: .native, state: .notGranted))
        XCTAssertFalse(IconsAccessTracker.blocksCollapse(engine: .native, state: .granted))
        XCTAssertFalse(IconsAccessTracker.blocksCollapse(engine: .length, state: .notGranted))
    }

    func testGrantAndNotEffective() {
        var t = IconsAccessTracker(trusted: false)
        XCTAssertEqual(t.state, .notGranted)
        t.paneClosed(at: 10)
        XCTAssertEqual(t.trust(false, at: 14.9), .notGranted)
        XCTAssertEqual(t.trust(false, at: 15), .notEffective)
        XCTAssertEqual(t.trust(false, at: 20), .notEffective)
        XCTAssertEqual(t.trust(true, at: 21), .granted)
        XCTAssertEqual(IconsAccessTracker(trusted: true).state, .granted)
    }

    func testAReadFailureWhileCollapsedRevokes() {
        var t = IconsAccessTracker(trusted: true)
        XCTAssertFalse(t.read(.failed, collapsed: false), "expanded: just an unusable read")
        XCTAssertEqual(t.state, .granted)
        XCTAssertTrue(t.read(.failed, collapsed: true))
        XCTAssertEqual(t.state, .revoked)
        XCTAssertEqual(t.trust(true, at: 1), .revoked, "the trust flag can stay true after a revoke")
        XCTAssertFalse(t.read(.failed, collapsed: true), "expands once")
        XCTAssertFalse(t.read(.thirdParty(3), collapsed: false))
        XCTAssertEqual(t.state, .granted)
    }

    func testTwoEmptyReadsAfterAGoodOneRevoke() {
        var t = IconsAccessTracker(trusted: true)
        XCTAssertFalse(t.read(.thirdParty(0), collapsed: true), "no good read yet: an empty bar may be the truth")
        XCTAssertFalse(t.read(.thirdParty(0), collapsed: true))
        XCTAssertFalse(t.read(.thirdParty(4), collapsed: true))
        XCTAssertFalse(t.read(.thirdParty(0), collapsed: true))
        XCTAssertTrue(t.read(.thirdParty(0), collapsed: true))
        XCTAssertEqual(t.state, .revoked)

        var u = IconsAccessTracker(trusted: true)
        _ = u.read(.thirdParty(4), collapsed: false)
        _ = u.read(.thirdParty(0), collapsed: false)
        XCTAssertFalse(u.read(.thirdParty(0), collapsed: false), "only while collapsed")
        XCTAssertEqual(u.state, .granted)
    }
}
