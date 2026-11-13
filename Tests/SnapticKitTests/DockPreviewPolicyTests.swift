import XCTest
@testable import SnapticKit

// MARK: Fixture: a bottom Dock 70 pt tall with 64 pt items from x 0. A is item 9 (x 576–640), B is item 10.
// Cocoa coordinates: y grows up from the Dock, and the panel sits 6 pt above it.

private let flatList = DockRect(x: 0, y: 0, width: 1280, height: 70)
private let away = DockPoint(x: 100, y: 200)

private func itemFrame(_ i: Int) -> DockRect { DockRect(x: Double(i) * 64, y: 3, width: 64, height: 64) }
private func centre(_ i: Int) -> DockPoint { DockPoint(x: Double(i) * 64 + 32, y: 35) }
private func pid(_ i: Int) -> Int32 { Int32(100 + i) }
private func panelFrame(_ i: Int) -> DockRect { DockRect(x: centre(i).x - 300, y: 76, width: 600, height: 200) }

private func app(_ i: Int, byPointer: Bool = true) -> DockSelection {
    DockSelection(kind: .app, pid: pid(i), itemFrame: itemFrame(i), listFrame: flatList, byPointer: byPointer)
}

private func folder(_ i: Int) -> DockSelection {
    DockSelection(kind: .folder, pid: nil, itemFrame: itemFrame(i), listFrame: flatList)
}

private func isSchedule(_ c: DockCommand) -> Bool {
    if case .schedule = c { return true }
    return false
}

private func scheduled(_ out: [DockCommand]) -> [(after: Double, token: Int)] {
    out.compactMap { c -> (after: Double, token: Int)? in
        if case let .schedule(after, token) = c { return (after, token) }
        return nil
    }
}

/// Plays the app's part: delivers events at a time, keeps the one-shot timers the policy asks for, and fires each at
/// its own time, earliest first, as the clock passes it. Superseded timers still fire, as they would in the app.
private struct DockRig {
    var policy: DockPreviewPolicy
    var now = 0.0
    var timers: [(at: Double, token: Int)] = []
    var log: [(at: Double, command: DockCommand)] = []

    init(delay: Double = 0.2, dockAutoHides: Bool = false) {
        policy = DockPreviewPolicy(delay: delay, dockAutoHides: dockAutoHides)
    }

    @discardableResult
    mutating func send(_ event: DockEvent, at t: Double) -> [DockCommand] {
        run(to: t)
        return deliver(event)
    }

    mutating func run(to t: Double) {
        while let next = timers.indices.filter({ timers[$0].at <= t + 1e-9 })
            .min(by: { timers[$0].at < timers[$1].at }) {
            let timer = timers.remove(at: next)
            now = max(now, timer.at)
            deliver(.fired(token: timer.token))
        }
        now = max(now, t)
    }

    @discardableResult
    mutating func deliver(_ event: DockEvent) -> [DockCommand] {
        let out = policy.handle(event, now: now)
        for command in out {
            log.append((now, command))
            if case let .schedule(after, token) = command { timers.append((now + after, token)) }
        }
        return out
    }

    /// The pointer on `s`, the Dock selects it, the delay passes, and the controller places the panel.
    mutating func show(_ s: DockSelection, pointer: DockPoint, panel: DockRect, at t: Double) {
        send(.pointerMoved(pointer), at: t)
        send(.selectionChanged(s), at: t)
        run(to: t + policy.delay)
        send(.panelPlaced(panel), at: now)
    }

    mutating func showApp(_ i: Int, at t: Double) {
        show(app(i), pointer: centre(i), panel: panelFrame(i), at: t)
    }

    /// The pointer moves onto item `i` and the Dock selects it.
    mutating func hover(_ i: Int, at t: Double) {
        send(.pointerMoved(centre(i)), at: t)
        send(.selectionChanged(app(i)), at: t)
    }

    /// The pointer moves off the Dock and the selection empties.
    mutating func leave(to p: DockPoint, at t: Double) {
        send(.pointerMoved(p), at: t)
        send(.selectionChanged(nil), at: t)
    }

    var hides: [DockDismissReason] {
        log.compactMap { entry -> DockDismissReason? in
            if case let .hide(reason) = entry.command { return reason }
            return nil
        }
    }

    var shows: [(pid: Int32, at: Double)] {
        log.compactMap { entry -> (pid: Int32, at: Double)? in
            if case let .show(pid, _, _) = entry.command { return (pid, entry.at) }
            return nil
        }
    }

    var swaps: [(pid: Int32, at: Double)] {
        log.compactMap { entry -> (pid: Int32, at: Double)? in
            if case let .swap(pid, _, _) = entry.command { return (pid, entry.at) }
            return nil
        }
    }

    var keys: [Bool] {
        log.compactMap { entry -> Bool? in
            if case let .engageKeys(on) = entry.command { return on }
            return nil
        }
    }

    var lastWatch: Bool? {
        for entry in log.reversed() {
            if case let .watchPointer(on) = entry.command { return on }
        }
        return nil
    }
}

// MARK: S0-21's diagonals

private struct Diagonal: CustomStringConvertible {
    var magnified: Bool
    var right: Bool
    var inset: Double
    var startY: Double
    var speed: Double

    var description: String {
        "\(magnified ? "magnified" : "resting") \(right ? "right" : "left"), inset \(inset), y \(startY), \(speed) pt/s"
    }
}

/// The inset from A's edge, the height in the Dock, and the speed in points per second.
private let diagonalVariants: [(inset: Double, startY: Double, speed: Double)] = [
    (4, 12, 1200), (8, 20, 1600), (12, 28, 2000), (6, 16, 2400), (10, 24, 900),
]

/// Shows A, then moves the pointer in a straight line from just inside A's edge to a far card in the panel, sending
/// what the app would every 1/60 s: `pointerMoved` and `selectionChanged` over the Dock, `panelEntered` and
/// `pointerMovedInPanel` in the panel. Returns the rig and whether the walk selected another app on the way.
private func walk(_ d: Diagonal) -> (rig: DockRig, crossed: Bool) {
    let list: DockRect
    let frames: [(i: Int, frame: DockRect)]
    let panel: DockRect
    if d.magnified {
        list = DockRect(x: 0, y: 0, width: 1280, height: 128)
        frames = [(i: 7, frame: DockRect(x: 344, y: 0, width: 100, height: 100)),
                  (i: 8, frame: DockRect(x: 444, y: 0, width: 100, height: 100)),
                  (i: 9, frame: DockRect(x: 544, y: 0, width: 128, height: 128)),
                  (i: 10, frame: DockRect(x: 672, y: 0, width: 100, height: 100)),
                  (i: 11, frame: DockRect(x: 772, y: 0, width: 100, height: 100))]
        panel = DockRect(x: 308, y: 140, width: 600, height: 200)
    } else {
        list = flatList
        frames = (0..<20).map { (i: $0, frame: itemFrame($0)) }
        panel = panelFrame(9)
    }
    func selection(_ i: Int) -> DockSelection? {
        frames.first { $0.i == i }.map { DockSelection(kind: .app, pid: pid(i), itemFrame: $0.frame, listFrame: list) }
    }
    func under(_ p: DockPoint) -> Int? {
        guard list.contains(p) else { return nil }
        return frames.first { p.x >= $0.frame.minX && p.x < $0.frame.maxX }?.i
    }
    var r = DockRig()
    guard let a = selection(9) else { return (r, false) }
    r.show(a, pointer: DockPoint(x: a.itemFrame.midX, y: a.itemFrame.midY), panel: panel, at: 1.0)
    let target = DockPoint(x: d.right ? 850 : 366, y: panel.minY + 100)
    var p = DockPoint(x: d.right ? a.itemFrame.maxX - d.inset : a.itemFrame.minX + d.inset, y: d.startY)
    var current: Int? = 9
    var entered = false
    var crossed = false
    var t = 1.5
    for k in 0..<600 {
        t = 1.5 + Double(k) / 60
        if panel.contains(p) {
            if !entered {
                r.send(.panelEntered, at: t)
                entered = true
            }
            r.send(.pointerMovedInPanel(p), at: t)
        } else {
            r.send(.pointerMoved(p), at: t)
        }
        let item = under(p)
        if item != current {
            current = item
            r.send(.selectionChanged(item.flatMap(selection)), at: t)
            if let item, item != 9 { crossed = true }
        }
        let dx = target.x - p.x, dy = target.y - p.y
        let rest = (dx * dx + dy * dy).squareRoot()
        if rest < 1e-6 { break }
        let f = min(1, d.speed / 60 / rest)
        p = DockPoint(x: p.x + dx * f, y: p.y + dy * f)
    }
    r.run(to: t + 2)
    return (r, crossed)
}

/// 0.5 K3: `DockPreviewPolicy` (§2.4, §4.1, §4.2, §4.4, §4.6; X-10, X-11, X-25, X2-10, X2-15, X2-23, X3-11, G2-5,
/// Y-11, Y-14). Carried S0 rows: S0-2 (delay), S0-7 (auto-hide), S0-9 (clicks), S0-13 (safety net, activation,
/// Space, Mission Control), S0-16 (VoiceOver), S0-21 (diagonals), S0-22 (lockout), S0-25 (latch, Dock menu).
final class DockPreviewPolicyTests: XCTestCase {
    // MARK: Delay (S0-2)

    func testShowsAfterTheDelay() {
        var r = DockRig()
        r.hover(9, at: 1.0)
        r.run(to: 1.19)
        XCTAssertTrue(r.shows.isEmpty)
        XCTAssertEqual(r.policy.pendingPID, pid(9))
        r.run(to: 1.2)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9)])
        XCTAssertEqual(r.shows.first?.at ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertTrue(r.log.contains { $0.command == .show(pid: pid(9), anchor: itemFrame(9), edge: .bottom) })
        XCTAssertEqual(r.policy.shownPID, pid(9))
        XCTAssertNil(r.policy.pendingPID)
    }

    func testANewSelectionRestartsTheDelay() {
        var r = DockRig()
        r.hover(9, at: 1.0)
        r.hover(10, at: 1.1)
        r.run(to: 1.29)
        XCTAssertTrue(r.shows.isEmpty)
        r.run(to: 1.3)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(10)])
        XCTAssertEqual(r.shows.first?.at ?? 0, 1.3, accuracy: 1e-9)
    }

    func testDelayZeroShowsAtOnce() {
        var r = DockRig(delay: 0)
        r.send(.pointerMoved(centre(9)), at: 1.0)
        let out = r.send(.selectionChanged(app(9)), at: 1.0)
        XCTAssertTrue(out.contains(.show(pid: pid(9), anchor: itemFrame(9), edge: .bottom)))
        XCTAssertFalse(out.contains(where: isSchedule))
    }

    /// Along the Dock, not into the panel: the swap is immediate, with no delay.
    func testNoDelayWhileShown() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.hover(10, at: 1.5)
        XCTAssertEqual(r.swaps.map { $0.pid }, [pid(10)])
        XCTAssertEqual(r.swaps.first?.at ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(r.shows.count, 1)
        XCTAssertEqual(r.policy.shownPID, pid(10))
    }

    // MARK: Stale selections (X2-10)

    /// The selection arrives after the pointer has gone: it never agrees, and is dropped after 500 ms.
    func testAStaleSelectionNeverShows() {
        var r = DockRig()
        r.send(.pointerMoved(DockPoint(x: 608, y: 300)), at: 1.0)
        r.send(.selectionChanged(app(9)), at: 1.01)
        XCTAssertEqual(r.policy.pendingPID, pid(9))
        r.run(to: 1.51)
        XCTAssertNil(r.policy.pendingPID)
        r.run(to: 3)
        XCTAssertTrue(r.shows.isEmpty)
        XCTAssertEqual(r.lastWatch, false)
    }

    func testLeavingTheZoneDropsAPendingShow() {
        var r = DockRig()
        r.hover(9, at: 1.0)
        r.send(.pointerMoved(DockPoint(x: 608, y: 300)), at: 1.1)
        XCTAssertNil(r.policy.pendingPID)
        r.run(to: 2)
        XCTAssertTrue(r.shows.isEmpty)
    }

    // MARK: Swap intent (S0-21, X2-23)

    func testDiagonalsIntoThePanelNeverSwap() {
        var cases: [Diagonal] = []
        for magnified in [false, true] {
            for right in [true, false] {
                for v in diagonalVariants {
                    cases.append(Diagonal(magnified: magnified, right: right, inset: v.inset, startY: v.startY,
                                          speed: v.speed))
                }
            }
        }
        XCTAssertEqual(cases.count, 20)
        for d in cases {
            let (r, crossed) = walk(d)
            XCTAssertTrue(crossed, "\(d)")
            XCTAssertTrue(r.swaps.isEmpty, "\(d)")
            XCTAssertTrue(r.hides.isEmpty, "\(d)")
            XCTAssertEqual(r.policy.shownPID, pid(9), "\(d)")
        }
    }

    /// Shows A, then moves up and right from (630, 20) by (4, 3) every 16 ms, into B at (642, 29) at 2.048.
    private func crossingIntoB() -> DockRig {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        for k in 0...3 {
            r.send(.pointerMoved(DockPoint(x: 630 + 4 * Double(k), y: 20 + 3 * Double(k))), at: 2.0 + 0.016 * Double(k))
        }
        r.send(.selectionChanged(app(10)), at: 2.048)
        return r
    }

    /// X2-23: the held swap is checked again on each move, and runs 120 ms after the pointer last headed in.
    func testAHeldSwapRunsOnceThePointerStopsHeadingIn() {
        var r = crossingIntoB()
        XCTAssertEqual(r.policy.pendingPID, pid(10))
        XCTAssertTrue(r.swaps.isEmpty)
        for j in 1...12 {
            let jd = Double(j)
            r.send(.pointerMoved(DockPoint(x: 642 + 2 * jd, y: 29 + 1.5 * jd)), at: 2.048 + 0.016 * jd)
            if j == 7 {
                r.run(to: 2.17)     // past the first hold's end
                XCTAssertTrue(r.swaps.isEmpty)
            }
        }
        XCTAssertTrue(r.swaps.isEmpty)
        XCTAssertEqual(r.policy.pendingPID, pid(10))
        r.send(.pointerMoved(DockPoint(x: 666, y: 30)), at: 2.256)     // turns down, away from the panel
        r.run(to: 2.359)
        XCTAssertTrue(r.swaps.isEmpty)
        r.run(to: 2.361)
        XCTAssertEqual(r.swaps.map { $0.pid }, [pid(10)])
        XCTAssertEqual(r.swaps.first?.at ?? 0, 2.36, accuracy: 1e-6)
    }

    func testEnteringThePanelDropsAHeldSwap() {
        var r = crossingIntoB()
        r.send(.panelEntered, at: 2.06)
        r.send(.pointerMovedInPanel(DockPoint(x: 650, y: 80)), at: 2.06)
        XCTAssertNil(r.policy.pendingPID)
        r.run(to: 3)
        XCTAssertTrue(r.swaps.isEmpty)
        XCTAssertTrue(r.hides.isEmpty)
        XCTAssertEqual(r.policy.shownPID, pid(9))
    }

    // MARK: Corridor, grace and safety net (X-10, S0-13)

    func testTheCorridorKeepsThePanel() {
        let corridor = DockPolicyGeometry.plainCorridor(itemFrame(9), panelFrame(9), .bottom)
        XCTAssertTrue(DockPolicyGeometry.contains(corridor, DockPoint(x: 650, y: 72)))
        XCTAssertTrue(DockPolicyGeometry.contains(corridor, DockPoint(x: 800, y: 74)))
        XCTAssertFalse(DockPolicyGeometry.contains(corridor, DockPoint(x: 700, y: 10)))
        XCTAssertFalse(DockPolicyGeometry.contains(corridor, away))

        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.leave(to: DockPoint(x: 650, y: 72), at: 1.5)
        r.run(to: 3.5)
        XCTAssertTrue(r.hides.isEmpty)
        XCTAssertEqual(r.policy.shownPID, pid(9))
    }

    func testGrace() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.leave(to: away, at: 1.5)
        r.run(to: 1.74)
        XCTAssertTrue(r.hides.isEmpty)
        r.run(to: 1.75)
        XCTAssertEqual(r.hides, [.left])
        XCTAssertNil(r.policy.shownPID)
        XCTAssertEqual(r.lastWatch, false)
    }

    func testReturningInsideTheGraceCancelsTheHide() {
        var item = DockRig()
        item.showApp(9, at: 1.0)
        item.leave(to: away, at: 1.5)
        item.hover(9, at: 1.7)
        item.run(to: 4)
        XCTAssertTrue(item.hides.isEmpty)

        var panel = DockRig()
        panel.showApp(9, at: 1.0)
        panel.leave(to: away, at: 1.5)
        panel.send(.panelEntered, at: 1.7)
        panel.run(to: 4)
        XCTAssertTrue(panel.hides.isEmpty)
    }

    /// A magnified icon above the resting frame doesn't trip the safety net; leaving the zone for 1 s does, even
    /// inside the corridor.
    func testTheSafetyNetAndMagnification() {
        let list = DockRect(x: 0, y: 0, width: 1280, height: 128)
        let magnified = DockSelection(kind: .app, pid: pid(9), itemFrame: DockRect(x: 544, y: 0, width: 128, height: 128),
                                      listFrame: list)
        var r = DockRig()
        r.show(magnified, pointer: DockPoint(x: 608, y: 64), panel: DockRect(x: 308, y: 140, width: 600, height: 200), at: 1.0)
        r.send(.pointerMoved(DockPoint(x: 608, y: 110)), at: 1.5)
        r.send(.selectionChanged(app(9)), at: 1.6)      // the same item at its resting frame
        r.run(to: 3.6)
        XCTAssertTrue(r.hides.isEmpty)
        r.leave(to: DockPoint(x: 800, y: 135), at: 3.6)
        r.run(to: 4.59)
        XCTAssertTrue(r.hides.isEmpty)
        r.run(to: 4.6)
        XCTAssertEqual(r.hides, [.safetyNet])
    }

    // MARK: The latch (S0-25, Y-14)

    func testClickOutsideLatchesTheItem() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.mouseDownOutside, at: 1.5)
        XCTAssertEqual(r.hides, [.clickOutside])
        XCTAssertEqual(r.policy.latchedItem?.pid, pid(9))
        XCTAssertEqual(r.lastWatch, true)       // the monitor runs until the latch ends
        r.send(.selectionChanged(app(9)), at: 1.6)
        r.run(to: 2)
        XCTAssertEqual(r.shows.count, 1)
        r.hover(10, at: 2)
        XCTAssertNil(r.policy.latchedItem)
        r.run(to: 2.2)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])
    }

    func testLeavingTheZoneEndsTheLatch() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.mouseDownOutside, at: 1.5)
        r.send(.pointerMoved(DockPoint(x: 608, y: 300)), at: 1.6)
        XCTAssertNil(r.policy.latchedItem)
        XCTAssertEqual(r.lastWatch, false)
        r.hover(9, at: 2)
        r.run(to: 2.2)
        XCTAssertEqual(r.shows.count, 2)
    }

    func testAMouseDownOnTheItemOrADragLatches() {
        var click = DockRig()
        click.showApp(9, at: 1.0)
        click.send(.mouseDownOnItem(app(9)), at: 1.5)
        XCTAssertEqual(click.hides, [.itemClicked])
        XCTAssertEqual(click.policy.latchedItem?.pid, pid(9))

        var drag = DockRig()
        drag.showApp(9, at: 1.0)
        drag.send(.dragStarted, at: 1.5)
        XCTAssertEqual(drag.hides, [.clickOutside])
        XCTAssertEqual(drag.policy.latchedItem?.pid, pid(9))
    }

    /// Y-14: a mouse-down on the Dock cancels a pending show, and the next item starts its own delay.
    func testAMouseDownOnTheDockCancelsAPendingShow() {
        var r = DockRig()
        r.hover(9, at: 1.0)
        r.send(.mouseDownOnItem(app(9)), at: 1.1)
        XCTAssertNil(r.policy.pendingPID)
        r.run(to: 1.5)
        XCTAssertTrue(r.shows.isEmpty)
        XCTAssertTrue(r.hides.isEmpty)
        r.hover(10, at: 1.5)
        r.run(to: 1.69)
        XCTAssertTrue(r.shows.isEmpty)
        r.run(to: 1.7)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(10)])
    }

    // MARK: Menus (X-25, X3-11)

    func testOwnMenusPauseTheTimersAndClosingRestartsThem() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.leave(to: away, at: 1.5)
        r.send(.ownMenuOpened, at: 1.6)
        r.run(to: 3.5)
        XCTAssertTrue(r.hides.isEmpty)
        r.send(.ownMenuClosed, at: 3.5)
        r.run(to: 3.74)
        XCTAssertTrue(r.hides.isEmpty)
        r.run(to: 3.75)
        XCTAssertEqual(r.hides, [.left])
    }

    func testTheDocksMenuHidesAndLatches() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.dockMenuOpened, at: 1.5)
        XCTAssertEqual(r.hides, [.dockMenu])
        XCTAssertEqual(r.policy.latchedItem?.pid, pid(9))
        r.hover(10, at: 1.6)
        r.run(to: 2)
        XCTAssertNil(r.policy.pendingPID)
        XCTAssertEqual(r.shows.count, 1)
        r.send(.dockMenuClosed, at: 2)
        r.send(.selectionChanged(app(10)), at: 2.1)
        r.run(to: 2.3)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])
    }

    // MARK: Dismissal (§2.4)

    func testEveryDismissReasonOneToOne() {
        for reason in DockDismissReason.allCases {
            var r = DockRig()
            r.showApp(9, at: 1.0)
            let t = 1.5
            switch reason {
            case .left: r.leave(to: away, at: t)
            case .safetyNet: r.leave(to: DockPoint(x: 800, y: 74), at: t)
            case .clickOutside: r.send(.mouseDownOutside, at: t)
            case .itemClicked: r.send(.mouseDownOnItem(app(9)), at: t)
            case .dockMenu: r.send(.dockMenuOpened, at: t)
            case .raised: r.send(.actionDone(.raise), at: t)
            case .hidApp: r.send(.actionDone(.hideApp), at: t)
            case .quitApp: r.send(.actionDone(.quitApp), at: t)
            case .escape: r.send(.keyHandled(.escape), at: t)
            case .appTerminated: r.send(.appTerminated(pid: pid(9)), at: t)
            case .activation: r.send(.appActivated(pid: 42, byUs: false), at: t)
            case .space: r.send(.spaceChanged, at: t)
            case .display: r.send(.displaysChanged, at: t)
            case .lock: r.send(.locked, at: t)
            case .sleep: r.send(.screensSlept, at: t)
            case .session: r.send(.sessionResigned, at: t)
            case .switcherOpened: r.send(.switcherOpened, at: t)
            case .paused: r.send(.pauseChanged(.command), at: t)
            case .stopped: r.send(.moduleStopped, at: t)
            case .noItem:
                r.send(.pointerMoved(centre(2)), at: t)
                r.send(.selectionChanged(folder(2)), at: t)
            }
            r.run(to: t + 2)
            XCTAssertEqual(r.hides, [reason], "\(reason)")
            XCTAssertNil(r.policy.shownPID, "\(reason)")
        }
    }

    /// Mission Control, App Exposé and Launchpad have no reason: the panel is `.transient` (X-16).
    func testOtherEndingsAndNoMissionControl() {
        for name in ["missionControl", "appExpose", "launchpad"] {
            XCTAssertNil(DockDismissReason(rawValue: name), name)
        }
        var sleep = DockRig()
        sleep.showApp(9, at: 1.0)
        sleep.send(.willSleep, at: 1.5)
        XCTAssertEqual(sleep.hides, [.sleep])

        var ours = DockRig()
        ours.showApp(9, at: 1.0)
        ours.send(.appActivated(pid: 42, byUs: true), at: 1.5)
        ours.run(to: 3)
        XCTAssertTrue(ours.hides.isEmpty)

        // With nothing shown, an ending drops a pending show quietly.
        var pending = DockRig()
        pending.hover(9, at: 1.0)
        pending.send(.spaceChanged, at: 1.1)
        XCTAssertNil(pending.policy.pendingPID)
        pending.run(to: 2)
        XCTAssertTrue(pending.shows.isEmpty)
        XCTAssertTrue(pending.hides.isEmpty)
    }

    func testOurOwnActions() {
        let hiding: [(DockAction, DockDismissReason, Bool)] = [
            (.raise, .raised, false), (.activateApp, .raised, false), (.hideApp, .hidApp, true), (.quitApp, .quitApp, true),
        ]
        for (action, reason, locks) in hiding {
            var r = DockRig()
            r.showApp(9, at: 1.0)
            r.send(.actionDone(action), at: 1.5)
            XCTAssertEqual(r.hides, [reason], "\(action)")
            XCTAssertEqual(r.policy.latchedItem?.pid, pid(9), "\(action)")
            XCTAssertEqual(r.policy.isLockedOut, locks, "\(action)")
        }
        for action in [DockAction.close, .minimize, .restore, .fullScreen, .minimizeAll, .closeAll, .showApp] {
            var r = DockRig()
            r.showApp(9, at: 1.0)
            XCTAssertEqual(r.send(.actionDone(action), at: 1.5), [.refresh(pid: pid(9))], "\(action)")
            XCTAssertEqual(r.policy.shownPID, pid(9), "\(action)")
        }
    }

    // MARK: Auto-hide (S0-7)

    /// The Dock slides up; the selection arrives with each frame. The show waits until the frame has held for 100 ms
    /// and anchors on the settled frame.
    func testAutoHideShowsOnceTheDockSettles() {
        func sliding(_ y: Double) -> DockSelection {
            DockSelection(kind: .app, pid: pid(9), itemFrame: DockRect(x: 576, y: y + 3, width: 64, height: 64),
                          listFrame: DockRect(x: 0, y: y, width: 1280, height: 70))
        }
        var r = DockRig(delay: 0, dockAutoHides: true)
        r.send(.pointerMoved(DockPoint(x: 608, y: 1)), at: 0)
        r.send(.selectionChanged(sliding(-50)), at: 0)
        r.send(.selectionChanged(sliding(-25)), at: 0.03)
        r.send(.selectionChanged(sliding(0)), at: 0.06)
        r.run(to: 0.159)
        XCTAssertTrue(r.shows.isEmpty)
        r.run(to: 0.16)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9)])
        XCTAssertEqual(r.shows.first?.at ?? 0, 0.16, accuracy: 1e-9)
        XCTAssertTrue(r.log.contains { $0.command == .show(pid: pid(9), anchor: itemFrame(9), edge: .bottom) })

        // In the panel the Dock hides again and the selection empties: the panel stays.
        r.send(.panelPlaced(panelFrame(9)), at: 0.16)
        r.send(.panelEntered, at: 0.5)
        r.send(.pointerMovedInPanel(DockPoint(x: 608, y: 100)), at: 0.5)
        r.send(.selectionChanged(nil), at: 0.55)
        r.run(to: 2.5)
        XCTAssertTrue(r.hides.isEmpty)

        // Out of the panel: left after the grace.
        r.send(.panelExited, at: 2.5)
        r.send(.pointerMoved(DockPoint(x: 608, y: 400)), at: 2.5)
        r.run(to: 2.74)
        XCTAssertTrue(r.hides.isEmpty)
        r.run(to: 2.75)
        XCTAssertEqual(r.hides, [.left])
    }

    // MARK: Races (X-11)

    func testRaceADiagonalCrossing() {
        let (r, crossed) = walk(Diagonal(magnified: false, right: true, inset: 4, startY: 12, speed: 1200))
        XCTAssertTrue(crossed)
        XCTAssertTrue(r.swaps.isEmpty)
        XCTAssertEqual(r.policy.shownPID, pid(9))
    }

    /// Quit from the panel: B slides into A's place under a still pointer and doesn't show until the pointer moves
    /// 8 pt (S0-22).
    func testRaceAReflowUnderAStillPointer() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.actionDone(.quitApp), at: 1.5)
        r.send(.appTerminated(pid: pid(9)), at: 1.6)
        let b = DockSelection(kind: .app, pid: pid(10), itemFrame: itemFrame(9), listFrame: flatList)
        r.send(.selectionChanged(b), at: 1.7)
        r.run(to: 2)
        XCTAssertEqual(r.shows.count, 1)
        XCTAssertTrue(r.policy.isLockedOut)
        r.send(.pointerMoved(DockPoint(x: 611, y: 35)), at: 2)
        r.run(to: 2.5)
        XCTAssertEqual(r.shows.count, 1)
        XCTAssertTrue(r.policy.isLockedOut)
        r.send(.pointerMoved(DockPoint(x: 616, y: 35)), at: 2.5)
        XCTAssertFalse(r.policy.isLockedOut)
        r.run(to: 2.69)
        XCTAssertEqual(r.shows.count, 1)
        r.run(to: 2.7)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])
        XCTAssertEqual(r.hides, [.quitApp])
    }

    /// A click on B within the lockout latches it: the 8 pt move ends the lockout but B still doesn't show.
    func testRaceAClickWithinTheLockout() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.actionDone(.quitApp), at: 1.5)
        r.send(.appTerminated(pid: pid(9)), at: 1.6)
        let b = DockSelection(kind: .app, pid: pid(10), itemFrame: itemFrame(9), listFrame: flatList)
        r.send(.selectionChanged(b), at: 1.7)
        r.send(.mouseDownOnItem(b), at: 1.8)
        XCTAssertEqual(r.policy.latchedItem?.pid, pid(10))
        r.send(.pointerMoved(DockPoint(x: 616, y: 35)), at: 2.5)
        XCTAssertFalse(r.policy.isLockedOut)
        r.run(to: 3.5)
        XCTAssertEqual(r.shows.count, 1)
        XCTAssertEqual(r.hides, [.quitApp])
    }

    func testRaceHoverLeaveHoverInOneTick() {
        var r = DockRig()
        r.hover(9, at: 1.0)
        r.leave(to: DockPoint(x: 608, y: 300), at: 1.0)
        r.hover(9, at: 1.0)
        r.run(to: 2)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9)])
        XCTAssertEqual(r.shows.first?.at ?? 0, 1.2, accuracy: 1e-9)
    }

    /// B is selected in the tick the grace hides A: it's a show after the delay, never a swap. A held swap dies
    /// with the panel.
    func testRaceASwapDuringHide() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.leave(to: away, at: 1.5)
        r.hover(10, at: 1.75)
        XCTAssertEqual(r.hides, [.left])
        r.run(to: 2.5)
        XCTAssertTrue(r.swaps.isEmpty)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])
        XCTAssertEqual(r.shows.last?.at ?? 0, 1.95, accuracy: 1e-9)

        var held = crossingIntoB()
        held.send(.appActivated(pid: 42, byUs: false), at: 2.1)
        XCTAssertEqual(held.hides, [.activation])
        XCTAssertNil(held.policy.pendingPID)
        held.run(to: 3)
        XCTAssertTrue(held.swaps.isEmpty)
        XCTAssertEqual(held.shows.count, 1)
    }

    func testRaceRefreshAfterHide() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        XCTAssertEqual(r.send(.actionDone(.close), at: 1.4), [.refresh(pid: pid(9))])
        r.send(.spaceChanged, at: 1.5)
        XCTAssertEqual(r.send(.windowsChanged(pid: pid(9)), at: 1.6), [])
        XCTAssertEqual(r.send(.actionDone(.close), at: 1.7), [])
    }

    // MARK: Windowless apps (Y-11)

    func testAWindowlessAppSwapsAndNeverKeepsThePreviousPanel() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.hover(10, at: 1.5)
        XCTAssertEqual(r.swaps.map { $0.pid }, [pid(10)])
        XCTAssertEqual(r.policy.shownPID, pid(10))
        XCTAssertEqual(r.send(.windowsChanged(pid: pid(9)), at: 1.6), [])
        XCTAssertEqual(r.send(.windowsChanged(pid: pid(10)), at: 1.7), [.refresh(pid: pid(10))])
    }

    // MARK: The switcher and pauses (X2-15)

    func testTheSwitcherHidesAndHoldsUntilItCloses() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.switcherOpened, at: 1.5)
        XCTAssertEqual(r.hides, [.switcherOpened])
        XCTAssertEqual(r.lastWatch, false)
        r.hover(10, at: 1.6)
        XCTAssertNil(r.policy.pendingPID)
        r.run(to: 2.5)
        XCTAssertEqual(r.shows.count, 1)
        XCTAssertTrue(r.swaps.isEmpty)
        r.send(.switcherClosed, at: 2.5)
        r.run(to: 3)
        XCTAssertEqual(r.shows.count, 1)
        r.send(.selectionChanged(app(10)), at: 3)
        r.run(to: 3.2)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])
    }

    func testAPauseHidesAndHoldsUntilItEnds() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.pauseChanged(.command), at: 1.5)
        XCTAssertEqual(r.hides, [.paused])
        r.hover(10, at: 1.6)
        r.run(to: 2)
        XCTAssertNil(r.policy.pendingPID)
        XCTAssertEqual(r.shows.count, 1)
        r.send(.pauseChanged(nil), at: 2)
        r.send(.selectionChanged(app(10)), at: 2.1)
        r.run(to: 2.3)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])
    }

    // MARK: VoiceOver (G2-5, S0-16)

    func testVoiceOverSelectionsSkipThePointerRules() {
        var r = DockRig()
        r.send(.selectionChanged(app(9, byPointer: false)), at: 1.0)
        r.run(to: 1.2)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9)])
        let shownAt = r.log.count
        r.send(.panelPlaced(panelFrame(9)), at: 1.2)
        r.send(.pointerMoved(DockPoint(x: 100, y: 500)), at: 1.5)
        r.run(to: 4)
        XCTAssertTrue(r.hides.isEmpty)
        XCTAssertFalse(r.log.dropFirst(shownAt).contains { isSchedule($0.command) })

        // The selection moving hides with noItem; the new item shows after the delay.
        r.send(.selectionChanged(app(10, byPointer: false)), at: 4)
        XCTAssertEqual(r.hides, [.noItem])
        r.run(to: 4.2)
        XCTAssertEqual(r.shows.map { $0.pid }, [pid(9), pid(10)])

        // The selection emptying hides with noItem.
        r.send(.selectionChanged(nil), at: 5)
        XCTAssertEqual(r.hides, [.noItem, .noItem])
    }

    func testVoiceOverFocusInThePanelKeepsItUp() {
        var r = DockRig()
        r.send(.selectionChanged(app(9, byPointer: false)), at: 1.0)
        r.run(to: 1.2)
        r.send(.voiceOverFocusInPanel(true), at: 1.5)
        r.send(.selectionChanged(nil), at: 1.6)
        r.run(to: 3)
        XCTAssertTrue(r.hides.isEmpty)
        XCTAssertEqual(r.policy.shownPID, pid(9))
        r.send(.voiceOverFocusInPanel(false), at: 3)
        XCTAssertEqual(r.hides, [.noItem])

        // Focus leaving the panel while the selection is still on the item keeps it.
        var still = DockRig()
        still.send(.selectionChanged(app(9, byPointer: false)), at: 1.0)
        still.run(to: 1.2)
        still.send(.voiceOverFocusInPanel(true), at: 1.5)
        still.send(.voiceOverFocusInPanel(false), at: 1.6)
        XCTAssertTrue(still.hides.isEmpty)
    }

    // MARK: Clicks (§4.4, S0-9)

    func testCardAndHeaderClicks() {
        var r = DockRig()
        XCTAssertNil(r.policy.resolveClick(.left, on: .card(hasAXElement: true), now: 0.5))
        r.showApp(9, at: 1.0)
        let p = r.policy
        XCTAssertEqual(p.resolveClick(.left, on: .card(hasAXElement: true), now: 1.25), .raise)
        XCTAssertEqual(p.resolveClick(.middle, on: .card(hasAXElement: true), now: 1.25), .close)
        XCTAssertEqual(p.resolveClick(.left, on: .card(hasAXElement: false), now: 1.25), .raise)
        XCTAssertNil(p.resolveClick(.middle, on: .card(hasAXElement: false), now: 1.25))
        XCTAssertEqual(p.resolveClick(.left, on: .smallCard, now: 1.25), .activateApp)
        XCTAssertNil(p.resolveClick(.middle, on: .smallCard, now: 1.25))

        // The header ignores clicks for 300 ms after a show.
        XCTAssertNil(p.resolveClick(.left, on: .header(.quitApp), now: 1.4))
        XCTAssertEqual(p.resolveClick(.left, on: .header(.quitApp), now: 1.5), .quitApp)
        XCTAssertNil(p.resolveClick(.left, on: .header(.quitApp), appIsFinder: true, now: 1.5))
        XCTAssertEqual(p.resolveClick(.left, on: .header(.minimizeAll), now: 1.5), .minimizeAll)
        XCTAssertEqual(p.resolveClick(.left, on: .header(.hideApp), now: 1.5), .hideApp)
        XCTAssertEqual(p.resolveClick(.left, on: .header(.showApp), now: 1.5), .showApp)
        XCTAssertNil(p.resolveClick(.middle, on: .header(.minimizeAll), now: 2))

        // ... and after a swap.
        r.hover(10, at: 2)
        XCTAssertEqual(r.swaps.count, 1)
        XCTAssertNil(r.policy.resolveClick(.left, on: .header(.hideApp), now: 2.2))
        XCTAssertEqual(r.policy.resolveClick(.left, on: .header(.hideApp), now: 2.3), .hideApp)
    }

    /// A card without an AX element offers only Bring Forward (D2-25).
    func testCardActions() {
        XCTAssertEqual(DockPreviewPolicy.cardActions(hasAXElement: true, minimized: false),
                       [.raise, .close, .minimize, .fullScreen])
        XCTAssertEqual(DockPreviewPolicy.cardActions(hasAXElement: true, minimized: true),
                       [.raise, .close, .restore, .fullScreen])
        XCTAssertEqual(DockPreviewPolicy.cardActions(hasAXElement: false, minimized: false), [.raise])
    }

    // MARK: The hovered app quitting

    func testTheHoveredAppQuitting() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.appTerminated(pid: pid(12)), at: 1.4)
        XCTAssertTrue(r.hides.isEmpty)
        r.send(.appTerminated(pid: pid(9)), at: 1.5)
        XCTAssertEqual(r.hides, [.appTerminated])
        XCTAssertTrue(r.policy.isLockedOut)
        XCTAssertEqual(r.lastWatch, true)

        var pending = DockRig()
        pending.hover(9, at: 1.0)
        pending.send(.appTerminated(pid: pid(9)), at: 1.1)
        XCTAssertNil(pending.policy.pendingPID)
        pending.run(to: 2)
        XCTAssertTrue(pending.shows.isEmpty)
        XCTAssertTrue(pending.hides.isEmpty)
    }

    // MARK: Generation tokens

    func testAStaleTokenIsIgnored() {
        var p = DockPreviewPolicy()
        _ = p.handle(.pointerMoved(centre(9)), now: 1.0)
        let first = scheduled(p.handle(.selectionChanged(app(9)), now: 1.0))
        _ = p.handle(.pointerMoved(centre(10)), now: 1.1)
        let second = scheduled(p.handle(.selectionChanged(app(10)), now: 1.1))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        guard let t1 = first.first, let t2 = second.first else { return }
        XCTAssertEqual(t1.after, 0.2, accuracy: 1e-9)
        XCTAssertNotEqual(t1.token, t2.token)

        XCTAssertEqual(p.handle(.fired(token: t1.token), now: 1.2), [])
        XCTAssertNil(p.shownPID)
        XCTAssertEqual(p.handle(.fired(token: 999), now: 1.25), [])

        // Early: the rest is scheduled under a new token, and the early one is dead.
        let early = scheduled(p.handle(.fired(token: t2.token), now: 1.25))
        XCTAssertEqual(early.count, 1)
        guard let t3 = early.first else { return }
        XCTAssertEqual(t3.after, 0.05, accuracy: 1e-9)
        XCTAssertNotEqual(t3.token, t2.token)
        XCTAssertEqual(p.handle(.fired(token: t2.token), now: 1.3), [])
        XCTAssertEqual(p.handle(.fired(token: t3.token), now: 1.3),
                       [.show(pid: pid(10), anchor: itemFrame(10), edge: .bottom)])
        XCTAssertEqual(p.shownPID, pid(10))
    }

    // MARK: Keys and the pointer monitor

    func testKeysEngageOnMovementInThePanel() {
        var r = DockRig()
        r.showApp(9, at: 1.0)
        r.send(.panelEntered, at: 1.5)
        r.send(.pointerMovedInPanel(DockPoint(x: 600, y: 150)), at: 1.5)
        r.send(.pointerMovedInPanel(DockPoint(x: 603, y: 150)), at: 1.6)
        XCTAssertEqual(r.keys, [])
        r.send(.pointerMovedInPanel(DockPoint(x: 606, y: 150)), at: 1.8)
        XCTAssertEqual(r.keys, [true])
        XCTAssertTrue(r.policy.keysEngagedNow)
        r.send(.tick, at: 3.29)
        XCTAssertEqual(r.keys, [true])
        r.send(.tick, at: 3.31)
        XCTAssertEqual(r.keys, [true, false])
        r.send(.pointerMovedInPanel(DockPoint(x: 612, y: 150)), at: 3.5)
        XCTAssertEqual(r.keys, [true, false, true])
        r.send(.keyNotHandled, at: 3.6)
        XCTAssertEqual(r.keys, [true, false, true, false])
        r.send(.pointerMovedInPanel(DockPoint(x: 618, y: 150)), at: 3.7)
        r.send(.panelExited, at: 3.8)
        XCTAssertEqual(r.keys, [true, false, true, false, true, false])
        XCTAssertTrue(r.hides.isEmpty)

        // A hide disengages.
        r.send(.panelEntered, at: 4)
        r.send(.panelClicked, at: 4)
        XCTAssertEqual(r.keys.last, true)
        r.send(.mouseDownOutside, at: 4.1)
        XCTAssertEqual(r.keys.last, false)
        XCTAssertFalse(r.policy.keysEngagedNow)
    }

    func testThePointerMonitorFollowsTheState() {
        var r = DockRig()
        r.hover(9, at: 1.0)
        XCTAssertEqual(r.lastWatch, true)
        r.send(.pointerMoved(DockPoint(x: 608, y: 300)), at: 1.1)
        XCTAssertEqual(r.lastWatch, false)
        r.showApp(9, at: 2)
        XCTAssertEqual(r.lastWatch, true)
        r.leave(to: away, at: 2.5)
        r.run(to: 3)
        XCTAssertEqual(r.hides, [.left])
        XCTAssertEqual(r.lastWatch, false)

        // Stopping ends everything, and nothing comes out after.
        r.showApp(9, at: 4)
        XCTAssertEqual(r.send(.moduleStopped, at: 4.5), [.hide(.stopped), .watchPointer(false)])
        XCTAssertEqual(r.send(.selectionChanged(app(10)), at: 5), [])
        XCTAssertEqual(r.send(.pointerMoved(centre(10)), at: 5), [])
    }
}
