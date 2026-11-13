import XCTest
@testable import SnapticKit

// MARK: Fixture: one 1440×900 screen with a 25 pt menu bar. A bottom Dock 70 pt tall (items 64 pt, 3 pt from the
// edge, from x 400); a left Dock (items 64 pt from y 200, 3 pt from the left edge). Cocoa coordinates.

private let screenFrame = DockRect(x: 0, y: 0, width: 1440, height: 900)
private let main = DockScreen(id: 1, frame: screenFrame, visibleFrame: DockRect(x: 0, y: 70, width: 1440, height: 805),
                              scale: 2, isPrimary: true)
private let sideScreen = DockScreen(id: 1, frame: screenFrame,
                                    visibleFrame: DockRect(x: 70, y: 0, width: 1370, height: 875), scale: 2,
                                    isPrimary: true)

private func bottomItem(_ i: Int) -> DockRect { DockRect(x: 400 + Double(i) * 64, y: 3, width: 64, height: 64) }
private func leftItem(_ i: Int) -> DockRect { DockRect(x: 3, y: 200 + Double(i) * 64, width: 64, height: 64) }
private let bottomItems = (0..<8).map(bottomItem)
private let leftItems = (0..<8).map(leftItem)
private let bottomList = DockRect(x: 400, y: 0, width: 512, height: 70)
private let leftList = DockRect(x: 0, y: 200, width: 70, height: 512)

private func bottomSelection(_ i: Int, frame: DockRect? = nil, pid: Int32? = 42) -> DockSelection {
    DockSelection(kind: .app, pid: pid, itemFrame: frame ?? bottomItem(i), listFrame: bottomList)
}

private func leftSelection(_ i: Int, frame: DockRect? = nil) -> DockSelection {
    DockSelection(kind: .app, pid: 42, itemFrame: frame ?? leftItem(i), listFrame: leftList)
}

private let bottomSnapshot = DockGeometrySnapshot(items: bottomItems, screens: [main])
private let leftSnapshot = DockGeometrySnapshot(items: leftItems, screens: [sideScreen])

private func window(_ id: UInt32, pid: Int32 = 42, minimized: Bool = false, hidden: Bool = false) -> CatalogWindow {
    CatalogWindow(id: id, pid: pid, minimized: minimized, hidden: hidden, onScreen: !minimized && !hidden)
}

final class DockPreviewRulesTests: XCTestCase {

    // MARK: Live geometry

    func testEdgeComesFromTheItemsScreenAndDockShape() {
        XCTAssertEqual(DockPreviewRules.edge(bottomSelection(2), bottomSnapshot), .bottom)
        XCTAssertEqual(DockPreviewRules.edge(leftSelection(2), leftSnapshot), .left)
        let rightItems = leftItems.map { DockRect(x: 1440 - 67, y: $0.y, width: 64, height: 64) }
        let right = DockSelection(kind: .app, pid: 42, itemFrame: rightItems[3],
                                  listFrame: DockRect(x: 1370, y: 200, width: 70, height: 512))
        XCTAssertEqual(DockPreviewRules.edge(right, DockGeometrySnapshot(items: rightItems, screens: [sideScreen])),
                       .right)
    }

    func testWithoutAScreenTheGeometryFallsBackToThePlainStandIns() {
        let empty = DockGeometrySnapshot()
        let s = bottomSelection(2)
        XCTAssertEqual(DockPreviewRules.edge(s, empty), DockPolicyGeometry.plainEdge(s))
        XCTAssertEqual(DockPreviewRules.hitBand(s, empty), DockPolicyGeometry.plainHitBand(s))
    }

    func testHitBandReachesHalfwayToTheNeighboursAndDownToTheScreenEdge() {
        let spaced = [DockRect(x: 400, y: 3, width: 60, height: 60), DockRect(x: 470, y: 3, width: 60, height: 60),
                      DockRect(x: 540, y: 3, width: 60, height: 60)]
        let s = DockSelection(kind: .app, pid: 42, itemFrame: spaced[1], listFrame: bottomList)
        let band = DockPreviewRules.hitBand(s, DockGeometrySnapshot(items: spaced, screens: [main]))
        XCTAssertEqual(band.minX, 465, accuracy: 1e-9)
        XCTAssertEqual(band.maxX, 535, accuracy: 1e-9)
        XCTAssertEqual(band.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(band.maxY, 63 + DockGeometry.zoneGrowth, accuracy: 1e-9)
    }

    func testHitBandIgnoresStaleFramesInsideTheMagnifiedItem() {
        // The item magnified to 96 pt around its centre; the cache still holds its resting frame and neighbours that
        // have since moved under it. Those don't shrink the band to the item's edge.
        let magnified = DockRect(x: 512, y: 3, width: 96, height: 96)
        let s = bottomSelection(2, frame: magnified)
        let band = DockPreviewRules.hitBand(s, bottomSnapshot)
        // Items 1, 2 and 3 overlap it; items 0 (ends at 464) and 4 (starts at 656) are its neighbours.
        XCTAssertEqual(band.minX, 488, accuracy: 1e-9)
        XCTAssertEqual(band.maxX, 632, accuracy: 1e-9)
        XCTAssertTrue(band.contains(DockPoint(x: magnified.midX, y: 10)))
    }

    func testNeighboursDropTheItemAndFramesOverlappingIt() {
        let item = bottomItem(2)
        let stale = DockRect(x: item.minX + 4, y: 3, width: 56, height: 56)
        let kept = DockPreviewRules.neighbours(of: item, bottomItems + [stale, .zero], edge: .bottom)
        XCTAssertFalse(kept.contains(item))
        XCTAssertFalse(kept.contains(stale))
        XCTAssertEqual(kept.count, bottomItems.count - 1)
    }

    func testZoneHoldsTheDockAndTheGrownItem() {
        let s = bottomSelection(2)
        let rects = DockPreviewRules.zone(s, bottomSnapshot)
        XCTAssertTrue(rects.contains { $0.contains(bottomList) })
        XCTAssertTrue(rects.contains { $0.contains(DockPoint(x: bottomItem(2).midX, y: 67 + 20)) })
        XCTAssertFalse(rects.contains { $0.contains(DockPoint(x: 100, y: 300)) })
    }

    func testZoneLeavesOutItemFramesFromAnotherScreen() {
        let second = DockScreen(id: 2, frame: DockRect(x: 1440, y: 0, width: 1920, height: 1080),
                                visibleFrame: DockRect(x: 1440, y: 0, width: 1920, height: 1055), scale: 1,
                                isPrimary: false)
        let elsewhere = DockRect(x: 2000, y: 3, width: 64, height: 64)
        let snap = DockGeometrySnapshot(items: bottomItems + [elsewhere], screens: [main, second])
        let dock = DockPreviewRules.dockFrame(bottomSelection(2), snap)
        XCTAssertEqual(dock?.maxX ?? 0, bottomList.maxX, accuracy: 1e-9)
    }

    func testLiveGeometryReadsTheLatestSnapshotOnEachCall() {
        final class Box: @unchecked Sendable { var snapshot = DockGeometrySnapshot() }
        let box = Box()
        let geometry = DockPreviewRules.liveGeometry { box.snapshot }
        let s = leftSelection(2)
        XCTAssertEqual(geometry.edge(s), DockPolicyGeometry.plainEdge(s))
        box.snapshot = leftSnapshot
        XCTAssertEqual(geometry.edge(s), .left)
        XCTAssertEqual(geometry.hitBand(s).minX, 0, accuracy: 1e-9)
        let panel = DockRect(x: 80, y: 150, width: 300, height: 400)
        let corridor = geometry.corridor(leftItem(2), panel, .left)
        XCTAssertTrue(DockPolicyGeometry.contains(corridor, DockPoint(x: 75, y: leftItem(2).midY)))
    }

    func testLiveGeometryDrivesThePolicyShow() {
        let geometry = DockPreviewRules.liveGeometry { bottomSnapshot }
        var policy = DockPreviewPolicy(delay: 0, geometry: geometry)
        let s = bottomSelection(2)
        _ = policy.handle(.selectionChanged(s), now: 0)
        let out = policy.handle(.pointerMoved(DockPoint(x: s.itemFrame.midX, y: 30)), now: 0.01)
        XCTAssertTrue(out.contains { if case .show(42, _, .bottom) = $0 { return true } else { return false } })
    }

    // MARK: Cards

    func testNothingReadAfterATimeoutIsTheCantReadCard() {
        let plan = DockPreviewRules.plan(windows: [], titles: [], config: DockConfig(), pid: 42, unreadRemain: false,
                                         timedOut: true, zOrder: [:])
        XCTAssertEqual(plan, DockCardPlan(small: .cantRead))
        var off = DockConfig()
        off.windowlessApps = false
        XCTAssertEqual(DockPreviewRules.plan(windows: [], titles: [], config: off, pid: 42, unreadRemain: false,
                                             timedOut: true, zOrder: [:]).small, .cantRead)
    }

    func testNoWindowsIsTheNoOpenWindowsCardUnlessTheSwitchIsOff() {
        XCTAssertEqual(DockPreviewRules.plan(windows: [], titles: [], config: DockConfig(), pid: 42,
                                             unreadRemain: false, timedOut: false, zOrder: [:]).small, .noOpenWindows)
        var off = DockConfig()
        off.windowlessApps = false
        let plan = DockPreviewRules.plan(windows: [], titles: [], config: off, pid: 42, unreadRemain: false,
                                         timedOut: false, zOrder: [:])
        XCTAssertTrue(plan.isEmpty)
    }

    func testEveryWindowFilteredOutIsTheNoWindowsShownCard() {
        var config = DockConfig()
        config.includeMinimizedAndHidden = false
        let windows = [window(1, minimized: true), window(2, hidden: true)]
        let plan = DockPreviewRules.plan(windows: windows, titles: ["a", "b"], config: config, pid: 42,
                                         unreadRemain: false, timedOut: false, zOrder: [:])
        XCTAssertEqual(plan, DockCardPlan(small: .noWindowsShown))
        config.windowlessApps = false
        XCTAssertTrue(DockPreviewRules.plan(windows: windows, titles: ["a", "b"], config: config, pid: 42,
                                            unreadRemain: false, timedOut: false, zOrder: [:]).isEmpty)
    }

    func testCardsFollowTheSortAndKeepReadIndices() {
        var config = DockConfig()
        config.includeMinimizedAndHidden = false
        config.sort = .title
        let windows = [window(1), window(2, minimized: true), window(3), window(4, pid: 7), window(5)]
        let plan = DockPreviewRules.plan(windows: windows, titles: ["Zeta", "Alpha", "beta", "Aardvark", "Écho"],
                                         config: config, pid: 42, unreadRemain: false, timedOut: false, zOrder: [:])
        XCTAssertEqual(plan.order, [2, 4, 0])
        XCTAssertFalse(plan.moreWindows)
        XCTAssertNil(plan.small)
    }

    func testRecentlyUsedFollowsTheStackingOrder() {
        let windows = [window(1), window(2), window(3, minimized: true)]
        let plan = DockPreviewRules.plan(windows: windows, titles: ["", "", ""], config: DockConfig(), pid: 42,
                                         unreadRemain: false, timedOut: false, zOrder: [2: 0, 1: 1])
        XCTAssertEqual(plan.order, [1, 0, 2])
    }

    func testABudgetThatRanOutAddsMoreWindowsLast() {
        let plan = DockPreviewRules.plan(windows: [window(1)], titles: ["a"], config: DockConfig(), pid: 42,
                                         unreadRemain: true, timedOut: false, zOrder: [:])
        XCTAssertEqual(plan, DockCardPlan(order: [0], moreWindows: true))
        var config = DockConfig()
        config.includeMinimizedAndHidden = false
        let filtered = DockPreviewRules.plan(windows: [window(1, minimized: true)], titles: ["a"], config: config,
                                             pid: 42, unreadRemain: true, timedOut: false, zOrder: [:])
        XCTAssertEqual(filtered, DockCardPlan(moreWindows: true))
        XCTAssertFalse(filtered.isEmpty)
    }

    func testATimedOutReadWithWindowsShowsThem() {
        let plan = DockPreviewRules.plan(windows: [window(1)], titles: ["a"], config: DockConfig(), pid: 42,
                                         unreadRemain: false, timedOut: true, zOrder: [:])
        XCTAssertEqual(plan.order, [0])
    }

    // MARK: Placement

    func testABottomPanelSitsPastTheRestingDockCentredOnTheItem() throws {
        let site = try XCTUnwrap(DockPreviewRules.site(anchor: bottomItem(2), edge: .bottom, snapshot: bottomSnapshot))
        XCTAssertEqual(site.restingThickness, 67, accuracy: 1e-9)
        XCTAssertEqual(site.area.minY, 73, accuracy: 1e-9)
        let frame = try XCTUnwrap(DockPreviewRules.frame(panel: DockSize(width: 300, height: 200),
                                                         anchor: bottomItem(2), site: site))
        XCTAssertEqual(frame.midX, bottomItem(2).midX, accuracy: 1e-9)
        XCTAssertEqual(frame.minY, 73, accuracy: 1e-9)
    }

    func testAMagnifiedAnchorDoesntMoveThePanelAcross() throws {
        let magnified = DockRect(x: 512, y: 3, width: 128, height: 128)
        let site = try XCTUnwrap(DockPreviewRules.site(anchor: magnified, edge: .bottom, snapshot: bottomSnapshot))
        XCTAssertEqual(site.restingThickness, 67, accuracy: 1e-9)
    }

    func testWithoutCachedItemsTheAnchorSetsTheThickness() throws {
        let snap = DockGeometrySnapshot(items: [], screens: [main])
        let site = try XCTUnwrap(DockPreviewRules.site(anchor: bottomItem(2), edge: .bottom, snapshot: snap))
        XCTAssertEqual(site.restingThickness, 67, accuracy: 1e-9)
    }

    func testALeftPanelSitsRightOfTheDock() throws {
        let site = try XCTUnwrap(DockPreviewRules.site(anchor: leftItem(3), edge: .left, snapshot: leftSnapshot))
        let frame = try XCTUnwrap(DockPreviewRules.frame(panel: DockSize(width: 300, height: 200), anchor: leftItem(3),
                                                         site: site))
        XCTAssertEqual(frame.minX, 73, accuracy: 1e-9)
        XCTAssertEqual(frame.midY, leftItem(3).midY, accuracy: 1e-9)
    }

    func testNoScreenOrNoRoomHasNoSite() {
        XCTAssertNil(DockPreviewRules.site(anchor: bottomItem(2), edge: .bottom, snapshot: DockGeometrySnapshot()))
        XCTAssertNil(DockPreviewRules.site(anchor: .zero, edge: .bottom, snapshot: bottomSnapshot))
        let tiny = DockScreen(id: 3, frame: DockRect(x: 0, y: 0, width: 100, height: 80),
                              visibleFrame: DockRect(x: 0, y: 70, width: 100, height: 10), scale: 1, isPrimary: true)
        XCTAssertNil(DockPreviewRules.site(anchor: DockRect(x: 10, y: 3, width: 64, height: 64), edge: .bottom,
                                           snapshot: DockGeometrySnapshot(screens: [tiny])))
    }

    func testThePanelThatDoesntFitHasNoFrame() throws {
        let site = try XCTUnwrap(DockPreviewRules.site(anchor: bottomItem(2), edge: .bottom, snapshot: bottomSnapshot))
        XCTAssertNil(DockPreviewRules.frame(panel: DockSize(width: 5000, height: 200), anchor: bottomItem(2),
                                            site: site))
    }

    func testTheSmallPanelIsTheCardAndPadding() {
        let size = DockPreviewRules.smallPanel()
        XCTAssertEqual(size.width, DockPreviewRules.smallCard.width + 24, accuracy: 1e-9)
        XCTAssertEqual(size.height, DockPreviewRules.smallCard.height + 24, accuracy: 1e-9)
    }

    // MARK: Events

    func testByUsWindows() {
        XCTAssertTrue(DockPreviewRules.isByUs(action: .raise, at: 10, now: 11.5))
        XCTAssertFalse(DockPreviewRules.isByUs(action: .raise, at: 10, now: 11.6))
        XCTAssertTrue(DockPreviewRules.isByUs(action: .quitApp, at: 10, now: 14.9))
        XCTAssertFalse(DockPreviewRules.isByUs(action: .quitApp, at: 10, now: 15.1))
        XCTAssertFalse(DockPreviewRules.isByUs(action: nil, at: nil, now: 10))
        XCTAssertFalse(DockPreviewRules.isByUs(action: .raise, at: 10, now: 9))
    }

    func testHiddenAppsAndPressedButtonsLoseTheirPid() {
        let s = bottomSelection(2)
        XCTAssertEqual(DockPreviewRules.mapped(s, hiddenFromDock: false, buttonDown: false), s)
        XCTAssertNil(DockPreviewRules.mapped(s, hiddenFromDock: true, buttonDown: false)?.pid)
        XCTAssertNil(DockPreviewRules.mapped(s, hiddenFromDock: false, buttonDown: true)?.pid)
        XCTAssertEqual(DockPreviewRules.mapped(s, hiddenFromDock: true, buttonDown: false)?.itemFrame, s.itemFrame)
        XCTAssertNil(DockPreviewRules.mapped(nil, hiddenFromDock: false, buttonDown: false))
    }

    func testVoiceOverSelectionsAreNotByPointer() {
        let s = bottomSelection(2)
        XCTAssertEqual(DockPreviewRules.mapped(s, hiddenFromDock: false, buttonDown: false)?.byPointer, true)
        let mapped = DockPreviewRules.mapped(s, hiddenFromDock: false, buttonDown: false, voiceOver: true)
        XCTAssertEqual(mapped?.byPointer, false)
        XCTAssertEqual(mapped?.pid, 42)
        XCTAssertNil(DockPreviewRules.mapped(s, hiddenFromDock: true, buttonDown: false, voiceOver: true)?.pid)
    }

    func testMouseDownOnTheItemOrItsBandLatchesTheItem() {
        let s = bottomSelection(2)
        let band = DockPreviewRules.hitBand(s, bottomSnapshot)
        XCTAssertEqual(DockPreviewRules.mouseDown(at: DockPoint(x: s.itemFrame.midX, y: 30), selection: s,
                                                  hitBand: band), .mouseDownOnItem(s))
        XCTAssertEqual(DockPreviewRules.mouseDown(at: DockPoint(x: s.itemFrame.midX, y: 1), selection: s,
                                                  hitBand: band), .mouseDownOnItem(s))
        XCTAssertEqual(DockPreviewRules.mouseDown(at: DockPoint(x: 100, y: 500), selection: s, hitBand: band),
                       .mouseDownOutside)
        XCTAssertEqual(DockPreviewRules.mouseDown(at: DockPoint(x: 100, y: 500), selection: nil, hitBand: nil),
                       .mouseDownOutside)
    }

    // MARK: Throttle

    func testTheThrottleSendsOneMovePerFrameAndKeepsTheLast() {
        var t = DockMoveThrottle()
        let a = DockPoint(x: 1, y: 1), b = DockPoint(x: 2, y: 2), c = DockPoint(x: 3, y: 3)
        XCTAssertEqual(t.moved(to: a, now: 0), a)
        XCTAssertNil(t.moved(to: b, now: 0.005))
        XCTAssertNil(t.moved(to: c, now: 0.01))
        XCTAssertTrue(t.isHolding)
        XCTAssertEqual(t.flushAt ?? 0, DockMoveThrottle.interval, accuracy: 1e-12)
        XCTAssertNil(t.flush(now: 0.012))
        XCTAssertEqual(t.flush(now: 0.017), c)
        XCTAssertFalse(t.isHolding)
        XCTAssertNil(t.flushAt)
        XCTAssertNil(t.flush(now: 1))
        XCTAssertEqual(t.moved(to: a, now: 1), a)
        t.reset()
        XCTAssertEqual(t.moved(to: b, now: 1.001), b)
    }

    // MARK: Words (A4b)

    func testCardLabelsAreTitleAndAppPlusOneState() {
        let plain = window(1)
        XCTAssertEqual(DockPreviewRules.cardLabel(plain, privacy: .none, title: "Notes", app: "Safari"),
                       "Notes, Safari")
        XCTAssertEqual(DockPreviewRules.cardLabel(window(1, minimized: true), privacy: .none, title: "Notes",
                                                  app: "Safari"), "Notes, Safari, minimized")
        XCTAssertEqual(DockPreviewRules.cardLabel(window(1, hidden: true), privacy: .none, title: "Notes",
                                                  app: "Safari"), "Notes, Safari, hidden")
        XCTAssertEqual(DockPreviewRules.cardLabel(window(1, minimized: true, hidden: true), privacy: .none,
                                                  title: "Notes", app: "Safari"), "Notes, Safari, minimized")
        let full = CatalogWindow(id: 1, pid: 42, fullscreen: true)
        XCTAssertEqual(DockPreviewRules.cardLabel(full, privacy: .none, title: "Notes", app: "Safari"),
                       "Notes, Safari, full screen")
        let away = CatalogWindow(id: 1, pid: 42, onScreen: false)
        XCTAssertTrue(away.onOtherSpace)
        XCTAssertEqual(DockPreviewRules.cardLabel(away, privacy: .none, title: "Notes", app: "Safari"),
                       "Notes, Safari, on another Space")
    }

    func testPrivateAndUntitledCardsNeverFallBackToTheTitle() {
        for privacy in [CatalogPrivacy.protectedApp, .privateMarker, .untitledBrowser] {
            XCTAssertEqual(DockPreviewRules.cardLabel(window(1), privacy: privacy, title: "Secret", app: "1Password"),
                           "Private window, 1Password")
        }
        XCTAssertEqual(DockPreviewRules.cardLabel(window(1, minimized: true), privacy: .privateMarker, title: "",
                                                  app: "Safari"), "Private window, Safari, minimized")
        let untitled = CatalogWindow(id: 1, pid: 42, hasTitle: false)
        XCTAssertEqual(DockPreviewRules.cardLabel(untitled, privacy: .none, title: "", app: "Notes"), "Notes")
        // An untitled other-Space card without an AX element says where it is once.
        let away = CatalogWindow(id: 1, pid: 42, hasTitle: false, onScreen: false, hasAXElement: false)
        XCTAssertEqual(DockPreviewRules.cardLabel(away, privacy: .none, title: "", app: "Notes"),
                       "Window on another Space, Notes")
    }

    func testSmallCardLabelsAndTheAnnouncement() {
        XCTAssertEqual(DockPreviewRules.smallCardLabel(.noOpenWindows, app: "Safari"), "No open windows, Safari")
        XCTAssertEqual(DockPreviewRules.smallCardLabel(.noWindowsShown, app: "Safari"), "No windows shown, Safari")
        XCTAssertEqual(DockPreviewRules.smallCardLabel(.cantRead, app: "Safari"),
                       "Windows can’t be read right now, Safari")
        XCTAssertEqual(DockPreviewRules.announcement(app: "Safari", windows: 3, small: nil), "Safari, 3 windows")
        XCTAssertEqual(DockPreviewRules.announcement(app: "Safari", windows: 1, small: nil), "Safari, 1 window")
        XCTAssertEqual(DockPreviewRules.announcement(app: "Safari", windows: 0, small: .noOpenWindows),
                       "No open windows, Safari")
        XCTAssertEqual(DockPreviewRules.panelLabel(app: "Safari"), "Safari windows")
        XCTAssertEqual(DockPreviewRules.windowCount(2), "2 windows")
    }

    func testHeaderWordsCarryTheKeyOnlyWhileKeysWork() {
        XCTAssertEqual(DockPreviewRules.headerHelp(.minimizeAll, app: "Safari", keysWork: true), "Minimize All")
        XCTAssertEqual(DockPreviewRules.headerHelp(.hideApp, app: "Safari", keysWork: false), "Hide Safari")
        XCTAssertEqual(DockPreviewRules.headerHelp(.hideApp, app: "Safari", keysWork: true), "Hide Safari (⌘H)")
        XCTAssertEqual(DockPreviewRules.headerHelp(.showApp, app: "Safari", keysWork: true), "Show Safari (⌘H)")
        XCTAssertEqual(DockPreviewRules.headerHelp(.quitApp, app: "Safari", keysWork: true), "Quit Safari (⌘Q)")
        XCTAssertEqual(DockPreviewRules.headerLabel(.quitApp, app: "Safari"), "Quit Safari")
        XCTAssertEqual(DockPreviewRules.hideButton(appHidden: true), .showApp)
        XCTAssertEqual(DockPreviewRules.hideButton(appHidden: false), .hideApp)
    }

    func testHoverWords() {
        XCTAssertEqual(DockPreviewRules.hoverHelp(.close, minimized: false, fullScreen: false, keysWork: false), "Close")
        XCTAssertEqual(DockPreviewRules.hoverHelp(.close, minimized: false, fullScreen: false, keysWork: true),
                       "Close (⌘W)")
        XCTAssertEqual(DockPreviewRules.hoverHelp(.minimize, minimized: false, fullScreen: false, keysWork: true),
                       "Minimize (⌘M)")
        XCTAssertEqual(DockPreviewRules.hoverHelp(.minimize, minimized: true, fullScreen: false, keysWork: false),
                       "Restore")
        XCTAssertEqual(DockPreviewRules.hoverHelp(.fullScreen, minimized: false, fullScreen: false, keysWork: true),
                       "Enter Full Screen")
        XCTAssertEqual(DockPreviewRules.hoverLabel(.fullScreen, minimized: false, fullScreen: true),
                       "Exit Full Screen")
        XCTAssertEqual(DockPreviewRules.hoverLabel(.close, minimized: false, fullScreen: false), "Close")
        XCTAssertEqual(DockPreviewRules.action(for: .minimize, minimized: true), .restore)
        XCTAssertEqual(DockPreviewRules.action(for: .minimize, minimized: false), .minimize)
        XCTAssertEqual(DockPreviewRules.action(for: .close, minimized: false), .close)
        XCTAssertEqual(DockPreviewRules.action(for: .fullScreen, minimized: false), .fullScreen)
    }

    func testCardMenuFollowsTheWindowAndTheApp() {
        XCTAssertEqual(DockPreviewRules.cardMenu(hasAXElement: false, minimized: false, fullScreen: false,
                                                 appHidden: false, appIsFinder: false), [.bringForward])
        XCTAssertEqual(DockPreviewRules.cardMenu(hasAXElement: true, minimized: false, fullScreen: false,
                                                 appHidden: false, appIsFinder: false),
                       [.closeWindow, .minimizeWindow, .enterFullScreen, .separator, .hideApp, .quitApp])
        XCTAssertEqual(DockPreviewRules.cardMenu(hasAXElement: true, minimized: true, fullScreen: true,
                                                 appHidden: true, appIsFinder: true),
                       [.closeWindow, .restoreWindow, .exitFullScreen, .separator, .showApp])
        XCTAssertEqual(DockPreviewRules.headerMenu(appHidden: false, appIsFinder: false),
                       [.minimizeAll, .closeAll, .separator, .hideApp, .quitApp])
        XCTAssertEqual(DockPreviewRules.headerMenu(appHidden: true, appIsFinder: true),
                       [.minimizeAll, .closeAll, .separator, .showApp])
    }

    func testMenuTitlesKeysAndActions() {
        XCTAssertEqual(DockPreviewRules.menuTitle(.closeWindow, app: "Safari"), "Close Window")
        XCTAssertEqual(DockPreviewRules.menuTitle(.restoreWindow, app: "Safari"), "Restore Window")
        XCTAssertEqual(DockPreviewRules.menuTitle(.showApp, app: "Safari"), "Show Safari")
        XCTAssertEqual(DockPreviewRules.menuTitle(.quitApp, app: "Safari"), "Quit Safari")
        XCTAssertEqual(DockPreviewRules.menuTitle(.bringForward, app: "Safari"), "Bring Forward")
        XCTAssertEqual(DockPreviewRules.menuTitle(.closeAll, app: "Safari"), "Close All")
        for item in DockPanelMenuItem.allCases {
            XCTAssertEqual(DockPreviewRules.menuKey(item, keysWork: false), "")
            XCTAssertEqual(DockPreviewRules.action(for: item) == nil, item == .separator)
        }
        XCTAssertEqual(DockPreviewRules.menuKey(.closeWindow, keysWork: true), "w")
        XCTAssertEqual(DockPreviewRules.menuKey(.restoreWindow, keysWork: true), "m")
        XCTAssertEqual(DockPreviewRules.menuKey(.showApp, keysWork: true), "h")
        XCTAssertEqual(DockPreviewRules.menuKey(.quitApp, keysWork: true), "q")
        XCTAssertEqual(DockPreviewRules.menuKey(.closeAll, keysWork: true), "")
        XCTAssertEqual(DockPreviewRules.action(for: .exitFullScreen), .fullScreen)
        XCTAssertEqual(DockPreviewRules.action(for: .bringForward), .raise)
    }

    func testKeysMapToActionsAndOnlyWindowActionsNeedAnElement() {
        XCTAssertNil(DockPreviewRules.action(for: DockKeyAction.escape))
        XCTAssertEqual(DockPreviewRules.action(for: DockKeyAction.close), .close)
        XCTAssertEqual(DockPreviewRules.action(for: DockKeyAction.showApp), .showApp)
        XCTAssertEqual(DockAction.allCases.filter(DockPreviewRules.needsAXElement),
                       [.close, .minimize, .restore, .fullScreen])
    }
}
