import XCTest
@testable import SnapticKit

/// 0.5 §4.8, A3: the Dock reader's rules (item kind, item → app, back-off, re-attach ladder, health check, stats,
/// window-read cache, read timings).
final class DockReaderRulesTests: XCTestCase {
    private let safari = DockRunningApp(pid: 400, bundlePath: "/Applications/Safari.app", bundleID: "com.apple.Safari",
                                        name: "Safari")
    private let notes = DockRunningApp(pid: 300, bundlePath: "/System/Applications/Notes.app",
                                       bundleID: "com.apple.Notes", name: "Notes")

    // MARK: Kind

    func testKindFromSubrole() {
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXApplicationDockItem"), .app)
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXFolderDockItem"), .folder)
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXTrashDockItem"), .trash)
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXMinimizedWindowDockItem"), .minimizedWindow)
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXSeparatorDockItem"), .separator)
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXSpacerDockItem"), .separator)
        XCTAssertEqual(DockReaderRules.kind(subrole: "AXURLDockItem"), .other)
        XCTAssertEqual(DockReaderRules.kind(subrole: nil), .other)
        XCTAssertEqual(DockReaderRules.kind(subrole: ""), .other)
    }

    func testNormalizedPath() {
        XCTAssertEqual(DockReaderRules.normalizedPath("/Applications/Safari.app/"), "/Applications/Safari.app")
        XCTAssertEqual(DockReaderRules.normalizedPath("/Applications/Safari.app//"), "/Applications/Safari.app")
        XCTAssertEqual(DockReaderRules.normalizedPath("/Applications/Safari.app"), "/Applications/Safari.app")
        XCTAssertEqual(DockReaderRules.normalizedPath("/"), "/")
        XCTAssertEqual(DockReaderRules.normalizedPath(""), "")
    }

    // MARK: Item → app

    func testOnlyRunningItemsMap() {
        for running in [false, nil] as [Bool?] {
            XCTAssertNil(DockReaderRules.pid(running: running, urlPath: "/Applications/Safari.app", title: "Safari",
                                             apps: [safari], bundleIDAtURL: { "com.apple.Safari" }))
        }
    }

    func testURLMatchesBundlePathWithoutReadingInfoPlist() {
        var read = false
        let pid = DockReaderRules.pid(running: true, urlPath: "/Applications/Safari.app/", title: "Other",
                                      apps: [notes, safari], bundleIDAtURL: { read = true; return nil })
        XCTAssertEqual(pid, 400)
        XCTAssertFalse(read)
    }

    func testTwoCopiesAtOnePathGoToLowestPID() {
        var second = safari
        second.pid = 120
        XCTAssertEqual(DockReaderRules.pid(running: true, urlPath: "/Applications/Safari.app", title: nil,
                                           apps: [safari, second], bundleIDAtURL: { nil }), 120)
    }

    func testBundleIDFromInfoPlistIgnoresCase() {
        var moved = safari
        moved.bundlePath = "/Users/x/Applications/Safari.app"
        XCTAssertEqual(DockReaderRules.pid(running: true, urlPath: "/Applications/Safari.app", title: nil,
                                           apps: [notes, moved], bundleIDAtURL: { "COM.APPLE.SAFARI" }), 400)
    }

    func testNameMatchMustBeUnique() {
        let noURL = DockRunningApp(pid: 500, bundlePath: nil, bundleID: nil, name: "Tool")
        XCTAssertEqual(DockReaderRules.pid(running: true, urlPath: nil, title: "Tool", apps: [noURL, notes],
                                           bundleIDAtURL: { nil }), 500)
        let twin = DockRunningApp(pid: 501, bundlePath: nil, bundleID: nil, name: "Tool")
        XCTAssertNil(DockReaderRules.pid(running: true, urlPath: nil, title: "Tool", apps: [noURL, twin],
                                         bundleIDAtURL: { nil }))
        XCTAssertNil(DockReaderRules.pid(running: true, urlPath: nil, title: "tool", apps: [noURL],
                                         bundleIDAtURL: { nil }))
    }

    func testURLMissFallsBackToName() {
        XCTAssertEqual(DockReaderRules.pid(running: true, urlPath: "/Elsewhere/Notes.app", title: "Notes",
                                           apps: [notes, safari], bundleIDAtURL: { "org.example.other" }), 300)
        XCTAssertNil(DockReaderRules.pid(running: true, urlPath: "/Elsewhere/X.app", title: nil, apps: [notes],
                                         bundleIDAtURL: { nil }))
    }

    // MARK: Window lists

    func testAllowUntitledDropsOnlyUntitledListOnlyWindows() {
        let listOnly = CatalogWindow(id: 9, pid: 1, hasTitle: false, onScreen: false, hasAXElement: false)
        XCTAssertTrue(DockReaderRules.listed(listOnly, allowUntitled: true))
        XCTAssertFalse(DockReaderRules.listed(listOnly, allowUntitled: false))
        let ax = CatalogWindow(id: 9, pid: 1, hasTitle: false)
        XCTAssertTrue(DockReaderRules.listed(ax, allowUntitled: false))
        let titled = CatalogWindow(id: 9, pid: 1, hasTitle: true, onScreen: false, hasAXElement: false)
        XCTAssertTrue(DockReaderRules.listed(titled, allowUntitled: false))
    }

    func testTimeoutListsOnScreenListOnlyWindows() {
        let w = CatalogWindow(id: 9, pid: 1, onScreen: true, hasAXElement: false)
        XCTAssertTrue(DockReaderRules.listedOnTimeout(w, options: .dock))
        var untitled = w
        untitled.hasTitle = false
        XCTAssertTrue(DockReaderRules.listedOnTimeout(untitled, options: .dock))
        XCTAssertFalse(DockReaderRules.listedOnTimeout(untitled, options: .switcher))
        var small = w
        small.bounds = DockRect(x: 0, y: 0, width: 99, height: 400)
        XCTAssertFalse(DockReaderRules.listedOnTimeout(small, options: .dock))
        var menu = w
        menu.layer = 25
        XCTAssertFalse(DockReaderRules.listedOnTimeout(menu, options: .dock))
        var clear = w
        clear.alpha = 0
        XCTAssertFalse(DockReaderRules.listedOnTimeout(clear, options: .dock))
        var off = w
        off.onScreen = false
        XCTAssertFalse(DockReaderRules.listedOnTimeout(off, options: .dock))
        var synthetic = w
        synthetic.id = CatalogWindow.firstSyntheticID
        XCTAssertFalse(DockReaderRules.listedOnTimeout(synthetic, options: .dock))
        XCTAssertFalse(DockReaderRules.listedOnTimeout(CatalogWindow(id: 9, pid: 1), options: .dock))
    }

    // MARK: Back-off

    func testThreeTimeoutsInTenSecondsPauseOneSecond() {
        var b = DockReadBackoff()
        b.timedOut(now: 100)
        b.timedOut(now: 104)
        XCTAssertEqual(b.wait(now: 104), 0)
        XCTAssertEqual(b.slowCount, 0)
        b.timedOut(now: 109)
        XCTAssertEqual(b.slowCount, 1)
        XCTAssertEqual(b.wait(now: 109), 1, accuracy: 1e-9)
        XCTAssertEqual(b.wait(now: 109.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(b.wait(now: 110), 0)
        XCTAssertTrue(b.timeouts.isEmpty)
    }

    func testOldTimeoutsExpire() {
        var b = DockReadBackoff()
        b.timedOut(now: 0)
        b.timedOut(now: 5)
        b.timedOut(now: 10)
        XCTAssertEqual(b.slowCount, 0)
        XCTAssertEqual(b.timeouts, [5, 10])
        b.timedOut(now: 14)
        XCTAssertEqual(b.slowCount, 1)
    }

    // MARK: Ladder

    func testLadderSteps() {
        let after = (0..<6).map { DockReattachLadder.delay(attempt: $0, sinceLogin: 600) }
        XCTAssertEqual(after, [0.1, 0.25, 0.5, 1, 2, nil])
        XCTAssertEqual((0..<6).map { DockReattachLadder.delay(attempt: $0, sinceLogin: nil) }, after)
        XCTAssertNil(DockReattachLadder.delay(attempt: -1, sinceLogin: nil))
    }

    func testLadderAddsLoginSteps() {
        let early = (0..<8).map { DockReattachLadder.delay(attempt: $0, sinceLogin: 30) }
        XCTAssertEqual(early, [0.1, 0.25, 0.5, 1, 2, 5, 10, nil])
        XCTAssertNil(DockReattachLadder.delay(attempt: 5, sinceLogin: 120))
        XCTAssertNil(DockReattachLadder.delay(attempt: 5, sinceLogin: -1))
    }

    func testRebuildChecksLandWithinTwoSeconds() {
        XCTAssertFalse(DockReattachLadder.rebuildChecks.isEmpty)
        XCTAssertTrue(DockReattachLadder.rebuildChecks.allSatisfy { $0 > 0 && $0 < 2 })
        XCTAssertEqual(DockReattachLadder.rebuildChecks, DockReattachLadder.rebuildChecks.sorted())
    }

    // MARK: Health

    func testHealthVerdicts() {
        let frame = DockRect(x: 0, y: 0, width: 1000, height: 70)
        let inside = DockPoint(x: 500, y: 30)
        let outside = DockPoint(x: 500, y: 300)
        XCTAssertEqual(DockHealthRules.verdict(listValid: false, pointer: outside, lastDockFrame: frame,
                                               selectionSame: true), .silentDeath)
        XCTAssertEqual(DockHealthRules.verdict(listValid: true, pointer: inside, lastDockFrame: frame,
                                               selectionSame: false), .silentDeath)
        XCTAssertEqual(DockHealthRules.verdict(listValid: true, pointer: inside, lastDockFrame: frame,
                                               selectionSame: true), .ok)
        XCTAssertEqual(DockHealthRules.verdict(listValid: true, pointer: outside, lastDockFrame: frame,
                                               selectionSame: false), .ok)
        XCTAssertEqual(DockHealthRules.verdict(listValid: true, pointer: nil, lastDockFrame: frame,
                                               selectionSame: false), .ok)
        XCTAssertEqual(DockHealthRules.verdict(listValid: true, pointer: inside, lastDockFrame: nil,
                                               selectionSame: false), .ok)
        XCTAssertEqual(DockHealthRules.verdict(listValid: true, pointer: .init(x: 0, y: 0), lastDockFrame: .zero,
                                               selectionSame: false), .ok)
    }

    // MARK: Stats

    func testStatsCountReattachesOnlyForANewDock() {
        var s = DockObserverStats()
        XCTAssertEqual(s.read, .starting)
        s.didAttach(pid: 90)
        XCTAssertEqual(s.reattaches, 0)
        s.didDetach()
        s.didRebuild()
        s.didAttach(pid: 90)
        XCTAssertEqual(s.reattaches, 0)
        XCTAssertEqual(s.rebuilds, 1)
        for pid in 91...100 {
            s.didDetach()
            s.didAttach(pid: Int32(pid))
        }
        XCTAssertEqual(s.reattaches, 10)
        XCTAssertTrue(s.attached)
        XCTAssertEqual(s.read, .attached)
    }

    func testStatsUnreadable() {
        var s = DockObserverStats()
        s.attachFailed(now: 10, ladderEnded: false)
        XCTAssertEqual(s.read, .unreadable)
        XCTAssertEqual(s.unreadableSince, 10)
        XCTAssertNil(s.ladderEndedAt)
        XCTAssertFalse(s.ladderEnded)
        s.attachFailed(now: 15, ladderEnded: true)
        XCTAssertEqual(s.unreadableSince, 10)
        XCTAssertEqual(s.ladderEndedAt, 15)
        XCTAssertTrue(s.ladderEnded)
        // Row 5's attention wait runs from the ladder's end; later checks and Try Again don't restart it (X2-16).
        s.attachFailed(now: 45, ladderEnded: true)
        s.attachFailed(now: 50, ladderEnded: false)
        XCTAssertEqual(s.ladderEndedAt, 15)
        XCTAssertEqual(DockPauseRules.read(s).unreadableSince, 15)
        s.didAttach(pid: 5)
        XCTAssertNil(s.unreadableSince)
        XCTAssertNil(s.ladderEndedAt)
        XCTAssertFalse(s.ladderEnded)
        XCTAssertEqual(s.read, .attached)
    }

    func testStatsSelections() {
        var s = DockObserverStats()
        s.didRead(nil)
        XCTAssertEqual(s.selections, 0)
        XCTAssertNil(s.lastKind)
        let frame = DockRect(x: 0, y: 0, width: 60, height: 60)
        s.didRead(DockSelection(kind: .folder, pid: nil, itemFrame: frame, listFrame: frame))
        s.didRead(nil)
        s.didRead(DockSelection(kind: .app, pid: 4, itemFrame: frame, listFrame: frame))
        XCTAssertEqual(s.selections, 2)
        XCTAssertEqual(s.lastKind, .app)
    }

    func testStatsLines() {
        var s = DockObserverStats()
        XCTAssertEqual(s.diagnosticsLines(observerLive: false), [
            "Observer attached: no", "Dock read: none", "Re-attaches: 0", "Silent re-attaches: 0",
            "Observer rebuilds: 0", "Dock slow: 0", "Selections: 0", "Last item kind: none",
        ])
        s.didAttach(pid: 1)
        s.didAttach(pid: 2)
        s.didSilentReattach()
        s.dockSlow = 3
        let frame = DockRect(x: 0, y: 0, width: 60, height: 60)
        s.didRead(DockSelection(kind: .trash, pid: nil, itemFrame: frame, listFrame: frame))
        XCTAssertEqual(s.diagnosticsLines(observerLive: true), [
            "Observer attached: yes", "Dock read: attached", "Re-attaches: 1", "Silent re-attaches: 1",
            "Observer rebuilds: 0", "Dock slow: 3", "Selections: 1", "Last item kind: trash",
        ])
        XCTAssertEqual(s.diagnosticsLines(observerLive: false).first, "Observer attached: no")
    }

    // MARK: Window cache

    func testCacheTTLAndDirty() {
        var c = DockWindowCache<Int>()
        c.store(7, for: 10, now: 100)
        XCTAssertEqual(c.value(for: 10, now: 101.9), 7)
        XCTAssertNil(c.value(for: 10, now: 102))
        XCTAssertNil(c.value(for: 11, now: 100))
        XCTAssertNil(c.value(for: 10, now: 99))
        c.markDirty(10)
        XCTAssertNil(c.value(for: 10, now: 100.5))
        c.store(8, for: 10, now: 101)
        XCTAssertEqual(c.value(for: 10, now: 101), 8)
        c.markDirty(99)
        XCTAssertEqual(c.count, 1)
    }

    func testCacheTimeoutSkip() {
        var c = DockWindowCache<Int>()
        XCTAssertFalse(c.isSkipped(10, now: 0))
        c.timedOut(10, now: 50)
        XCTAssertTrue(c.isSkipped(10, now: 50))
        XCTAssertTrue(c.isSkipped(10, now: 79.9))
        XCTAssertFalse(c.isSkipped(10, now: 80))
        XCTAssertFalse(c.isSkipped(11, now: 60))
    }

    func testCachePruneAndRemoveAll() {
        var c = DockWindowCache<Int>()
        c.store(1, for: 1, now: 0)
        c.store(2, for: 2, now: 1.5)
        c.store(3, for: 3, now: 1.5)
        c.markDirty(3)
        c.timedOut(4, now: 0)
        c.timedOut(5, now: 10)
        c.prune(now: 2.5)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c.value(for: 2, now: 2.5), 2)
        XCTAssertEqual(c.skippedCount, 2)
        c.prune(now: 35)
        XCTAssertEqual(c.count, 0)
        XCTAssertEqual(c.skippedCount, 1)
        c.store(1, for: 1, now: 35)
        c.removeAll()
        XCTAssertEqual(c.count, 0)
        XCTAssertEqual(c.skippedCount, 0)
    }

    // MARK: Timings

    func testTimingsP95() {
        var t = DockReadTimings()
        XCTAssertNil(t.p95)
        for ms in 1...100 { t.add(Double(ms)) }
        XCTAssertEqual(t.p95, 95)
        XCTAssertEqual(t.total, 100)
        t.add(-1)
        t.add(.nan)
        XCTAssertEqual(t.total, 100)
        t.add(500)
        XCTAssertEqual(t.samples.count, DockReadTimings.capacity)
        XCTAssertEqual(t.samples.first, 2)
        XCTAssertEqual(t.total, 101)
        XCTAssertEqual(t.p95, 96)

        var one = DockReadTimings()
        one.add(12)
        XCTAssertEqual(one.p95, 12)
    }
}
