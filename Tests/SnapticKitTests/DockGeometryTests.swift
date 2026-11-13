import XCTest
@testable import SnapticKit

// 0.5 K2 (§4.1–§4.3, §4.7; §6.1's K2 list). Fixtures follow S0-1 and S0-12 on the build host: a 2560 × 1440 main
// display at 1x with a bottom Dock (tile size 62, `AXList` at AX (219, 1348, 2122 × 82), items 66 × 82 at AX y 1353),
// and the 1728 × 1117 built-in display at 2x to its left. Side Docks, a Dock on the secondary display, a display
// arranged above and magnified frames follow the plan; S0-2 and S0-12 carry those legs to an owner session.

private let primaryHeight = 1440.0

private func screen(_ id: UInt32, _ frame: DockRect, visible: DockRect, scale: Double = 1,
                    primary: Bool = false) -> DockScreen {
    DockScreen(id: id, frame: frame, visibleFrame: visible, scale: scale, isPrimary: primary)
}

/// The main display, with the Dock on `edge` not hiding.
private func main(_ edge: DockEdge = .bottom) -> DockScreen {
    let frame = DockRect(x: 0, y: 0, width: 2560, height: 1440)
    switch edge {
    case .bottom: return screen(1, frame, visible: DockRect(x: 0, y: 88, width: 2560, height: 1322), primary: true)
    case .left: return screen(1, frame, visible: DockRect(x: 88, y: 0, width: 2472, height: 1410), primary: true)
    case .right: return screen(1, frame, visible: DockRect(x: 0, y: 0, width: 2472, height: 1410), primary: true)
    }
}

/// The built-in display at 2x, left of the main one (negative x), with a bottom Dock not hiding.
private let builtIn = screen(2, DockRect(x: -1728, y: 323, width: 1728, height: 1117),
                             visible: DockRect(x: -1728, y: 411, width: 1728, height: 992), scale: 2)

/// A display arranged above the main one (negative AX y).
private let above = screen(3, DockRect(x: 320, y: 1440, width: 1920, height: 1080),
                           visible: DockRect(x: 320, y: 1528, width: 1920, height: 967))

/// `count` item frames along `edge` of `s`, `inset` off the screen edge (S0-1: 5 pt), `depth` across (82) and `pitch`
/// along (66), `gap` apart.
private func items(_ count: Int, from start: Double, edge: DockEdge = .bottom, on s: DockScreen = main(),
                   pitch: Double = 66, gap: Double = 0, depth: Double = 82, inset: Double = 5) -> [DockRect] {
    (0..<count).map { i in
        let along = start + Double(i) * (pitch + gap)
        switch edge {
        case .bottom: return DockRect(x: along, y: s.frame.minY + inset, width: pitch, height: depth)
        case .left: return DockRect(x: s.frame.minX + inset, y: along, width: depth, height: pitch)
        case .right: return DockRect(x: s.frame.maxX - inset - depth, y: along, width: depth, height: pitch)
        }
    }
}

/// S0-1's bottom Dock: 30 abutting items from x 230; item 15 spans x 1220–1286, y 5–87.
private let bottomItems = items(30, from: 230)

private func point(_ x: Double, _ y: Double) -> DockPoint { DockPoint(x: x, y: y) }

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> DockRect {
    DockRect(x: x, y: y, width: w, height: h)
}

final class DockGeometryTests: XCTestCase {
    // MARK: Constants

    func testConstantsArePinned() {
        XCTAssertEqual(DockGeometry.zoneGrowth, 24)
        XCTAssertEqual(DockGeometry.panelGap, 6)
        XCTAssertEqual(DockGeometry.screenMargin, 8)
        XCTAssertEqual(DockGeometry.cardAspect, 1.6)
        XCTAssertEqual(DockGeometry.sideColumns, 2)
        XCTAssertEqual(DockGeometry.zoneRectCap, 32)
        XCTAssertEqual(DockCardSize.allCases.map(DockGeometry.cardWidth), [200, 280, 360])
        XCTAssertEqual(DockPanelMetrics.standard, DockPanelMetrics(padding: 12, spacing: 12, headerHeight: 32))
    }

    // MARK: AX → Cocoa (X-27)

    func testAXToCocoaRoundTrip() {
        // S0-1: the `AXList` sits 10 pt off the bottom, the items 5 pt.
        let list = rect(219, 1348, 2122, 82), item = rect(219, 1353, 66, 82)
        XCTAssertEqual(DockGeometry.cocoaRect(fromAX: list, primaryHeight: primaryHeight), rect(219, 10, 2122, 82))
        XCTAssertEqual(DockGeometry.cocoaRect(fromAX: item, primaryHeight: primaryHeight), rect(219, 5, 66, 82))
        // A display to the left keeps its negative x; one above has negative AX y.
        XCTAssertEqual(DockGeometry.cocoaRect(fromAX: rect(-1000, 1030, 66, 82), primaryHeight: primaryHeight),
                       rect(-1000, 328, 66, 82))
        XCTAssertEqual(DockGeometry.cocoaRect(fromAX: rect(1000, -87, 66, 82), primaryHeight: primaryHeight),
                       rect(1000, 1445, 66, 82))
        for r in [list, item, rect(-1728, -1080, 1728, 1117), rect(0.5, 0.25, 10.75, 3.5)] {
            let cocoa = DockGeometry.cocoaRect(fromAX: r, primaryHeight: primaryHeight)
            XCTAssertEqual(DockGeometry.axRect(fromCocoa: cocoa, primaryHeight: primaryHeight), r)
        }
        XCTAssertEqual(DockGeometry.cocoaPoint(fromAX: point(100, 0), primaryHeight: primaryHeight), point(100, 1440))
        XCTAssertEqual(DockGeometry.cocoaPoint(fromAX: point(-5, 1500), primaryHeight: primaryHeight), point(-5, -60))
        XCTAssertEqual(DockGeometry.axPoint(fromCocoa: point(-5, -60), primaryHeight: primaryHeight), point(-5, 1500))

        var rng = SeededGenerator(seed: 0xD0C_4A)
        for _ in 0..<1_000 {
            func value(_ span: UInt64) -> Double { Double(rng.next() % span) / 4 - Double(span) / 8 }
            let r = rect(value(40_000), value(40_000), value(20_000) + 2_500, value(20_000) + 2_500)
            let h = value(16_000) + 3_000
            let back = DockGeometry.axRect(fromCocoa: DockGeometry.cocoaRect(fromAX: r, primaryHeight: h),
                                           primaryHeight: h)
            XCTAssertEqual(back.x, r.x)
            XCTAssertEqual(back.y, r.y, accuracy: 1e-9)
            XCTAssertEqual(back.width, r.width)
            XCTAssertEqual(back.height, r.height)
        }
    }

    func testPrimaryHeightComesFromThePrimaryScreen() {
        XCTAssertEqual(DockGeometry.primaryHeight([builtIn, main(), above]), 1440)
        XCTAssertEqual(DockGeometry.primaryHeight([builtIn]), 1117)
        XCTAssertNil(DockGeometry.primaryHeight([]))
    }

    // MARK: Edge from the settled item frame

    func testEdgeFromSettledItemFrameForBottomLeftAndRight() {
        let screens = [main()]
        let bottom = DockGeometry.cocoaRect(fromAX: rect(219, 1353, 66, 82), primaryHeight: primaryHeight)
        XCTAssertEqual(DockGeometry.screen(holding: bottom, in: screens)?.id, 1)
        XCTAssertEqual(DockGeometry.edge(ofItem: bottom, on: main()), .bottom)
        XCTAssertEqual(DockGeometry.edge(ofItem: items(1, from: 700, edge: .left)[0], on: main(.left)), .left)
        XCTAssertEqual(DockGeometry.edge(ofItem: items(1, from: 700, edge: .right)[0], on: main(.right)), .right)
        // The Dock's frame decides bottom or side, so a side Dock's end item by the bottom corner reads as a side.
        let leftDock = items(20, from: 2, edge: .left)
        XCTAssertEqual(DockGeometry.edge(ofItem: leftDock[0], on: main(.left)), .bottom)
        XCTAssertEqual(DockGeometry.edge(ofItem: leftDock[0], dock: DockGeometry.dockFrame(items: leftDock),
                                         on: main(.left)), .left)
        let rightDock = items(20, from: 2, edge: .right)
        XCTAssertEqual(DockGeometry.edge(ofItem: rightDock[0], dock: DockGeometry.dockFrame(items: rightDock),
                                         on: main(.right)), .right)
        XCTAssertEqual(DockGeometry.edge(ofItem: bottomItems[0], dock: DockGeometry.dockFrame(items: bottomItems),
                                         on: main()), .bottom)
    }

    func testEdgeOnSecondaryScreenWithNegativeX() {
        let screens = [main(), builtIn]
        // AX (−1000, 1030) is 5 pt off the built-in display's bottom.
        let item = DockGeometry.cocoaRect(fromAX: rect(-1000, 1030, 66, 82), primaryHeight: primaryHeight)
        let s = DockGeometry.screen(holding: item, in: screens)
        XCTAssertEqual(s?.id, 2)
        XCTAssertEqual(s.map { DockGeometry.edge(ofItem: item, on: $0) }, .bottom)
        let left = items(1, from: 800, edge: .left, on: builtIn)[0]
        XCTAssertEqual(left.minX, -1723)
        XCTAssertEqual(DockGeometry.screen(holding: left, in: screens)?.id, 2)
        XCTAssertEqual(DockGeometry.edge(ofItem: left, on: builtIn), .left)
        let right = items(1, from: 800, edge: .right, on: builtIn)[0]
        XCTAssertEqual(DockGeometry.edge(ofItem: right, on: builtIn), .right)
    }

    func testEdgeOnScreenArrangedAbove() {
        let screens = [main(), builtIn, above]
        let item = DockGeometry.cocoaRect(fromAX: rect(1000, -87, 66, 82), primaryHeight: primaryHeight)
        XCTAssertEqual(DockGeometry.screen(holding: item, in: screens)?.id, 3)
        XCTAssertEqual(DockGeometry.edge(ofItem: item, on: above), .bottom)
        XCTAssertEqual(DockGeometry.edge(ofItem: items(1, from: 1900, edge: .left, on: above)[0], on: above), .left)
        XCTAssertEqual(DockGeometry.edge(ofItem: items(1, from: 1900, edge: .right, on: above)[0], on: above), .right)
        // An item on no screen has no screen to take an edge from.
        XCTAssertNil(DockGeometry.screen(holding: rect(9000, 9000, 66, 82), in: screens))
    }

    func testFramesSettleOnTwoEqualReads() {
        let item = bottomItems[15]
        XCTAssertTrue(DockGeometry.isSettled(previous: item, current: item))
        XCTAssertFalse(DockGeometry.isSettled(previous: nil, current: item))
        XCTAssertFalse(DockGeometry.isSettled(previous: rect(1220, 4, 66, 82), current: item))
        XCTAssertFalse(DockGeometry.isSettled(previous: rect(1220, 5, 0, 82), current: rect(1220, 5, 0, 82)))
    }

    // MARK: Placement (§4.7)

    func testPlacementOnBottomDockCentredWithGapAndMargin() {
        let s = main()
        let thickness = DockGeometry.restingThickness(items: bottomItems, edge: .bottom, screen: s)
        XCTAssertEqual(thickness, 87)
        let panel = DockSize(width: 600, height: 300)
        func place(_ item: DockRect, _ p: DockSize = panel) -> DockRect? {
            DockGeometry.placement(panel: p, item: item, restingThickness: 87, edge: .bottom, screen: s)
        }
        // Centred on the item, 6 pt off the Dock's at-rest top (y 87).
        XCTAssertEqual(place(bottomItems[15]), rect(953, 93, 600, 300))
        // Clamped 8 pt inside the visible frame at either end.
        XCTAssertEqual(place(bottomItems[0])?.minX, 8)
        XCTAssertEqual(place(rect(2400, 5, 66, 82))?.maxX, 2552)
        // The tallest panel stops 8 pt under the visible top; the widest leaves 8 pt each side.
        XCTAssertEqual(place(bottomItems[15], DockSize(width: 2544, height: 1309)), rect(8, 93, 2544, 1309))
        XCTAssertNil(place(bottomItems[15], DockSize(width: 600, height: 1310)))
        XCTAssertNil(place(bottomItems[15], DockSize(width: 2545, height: 300)))
        XCTAssertNil(place(bottomItems[15], DockSize(width: 0, height: 300)))
    }

    func testPlacementOnSideDocksCentredWithGapAndMargin() {
        let panel = DockSize(width: 600, height: 300)
        let left = main(.left), right = main(.right)
        let leftItems = items(10, from: 400, edge: .left), rightItems = items(10, from: 400, edge: .right)
        XCTAssertEqual(DockGeometry.restingThickness(items: leftItems, edge: .left, screen: left), 87)
        XCTAssertEqual(DockGeometry.restingThickness(items: rightItems, edge: .right, screen: right), 87)
        func place(_ item: DockRect, _ edge: DockEdge) -> DockRect? {
            DockGeometry.placement(panel: panel, item: item, restingThickness: 87, edge: edge,
                                   screen: edge == .left ? left : right)
        }
        // Left: 6 pt right of the Dock, centred on the item (y 700–766), clamped 8 pt inside the top and bottom.
        XCTAssertEqual(place(rect(5, 700, 82, 66), .left), rect(93, 583, 600, 300))
        XCTAssertEqual(place(rect(5, 1350, 82, 66), .left)?.maxY, 1402)
        XCTAssertEqual(place(rect(5, 20, 82, 66), .left)?.minY, 8)
        // Right: 6 pt left of the Dock.
        XCTAssertEqual(place(rect(2473, 700, 82, 66), .right), rect(1867, 583, 600, 300))
        XCTAssertEqual(place(rect(2473, 1350, 82, 66), .right)?.maxY, 1402)
        XCTAssertEqual(place(rect(2473, 20, 82, 66), .right)?.minY, 8)
        // The far side keeps its 8 pt margin.
        XCTAssertEqual(DockGeometry.panelArea(restingThickness: 87, edge: .left, screen: left),
                       rect(93, 8, 2459, 1394))
        XCTAssertEqual(DockGeometry.panelArea(restingThickness: 87, edge: .right, screen: right),
                       rect(8, 8, 2459, 1394))
    }

    func testPlacementOnSecondaryScreens() {
        let panel = DockSize(width: 600, height: 300)
        let builtInItems = items(10, from: -1500, on: builtIn)
        XCTAssertEqual(DockGeometry.restingThickness(items: builtInItems, edge: .bottom, screen: builtIn), 87)
        let p = DockGeometry.placement(panel: panel, item: builtInItems[0], restingThickness: 87, edge: .bottom,
                                       screen: builtIn)
        XCTAssertEqual(p, rect(-1720, 416, 600, 300))
        let aboveItems = items(10, from: 1000, on: above)
        let q = DockGeometry.placement(panel: panel, item: aboveItems[2], restingThickness: 87, edge: .bottom,
                                       screen: above)
        XCTAssertEqual(q, rect(865, 1533, 600, 300))
    }

    func testPlacementNeverLeavesTheVisibleFrameOnTheDockSide() {
        // A visible frame that starts above the Dock's top + 6 holds the panel's near side.
        let s = screen(1, DockRect(x: 0, y: 0, width: 2560, height: 1440),
                       visible: DockRect(x: 0, y: 120, width: 2560, height: 1290))
        XCTAssertEqual(DockGeometry.placement(panel: DockSize(width: 600, height: 300), item: bottomItems[15],
                                              restingThickness: 87, edge: .bottom, screen: s)?.minY, 120)
        // An auto-hiding Dock leaves the visible frame at the screen edge; the gap still holds off the Dock's top.
        let hiding = screen(1, DockRect(x: 0, y: 0, width: 2560, height: 1440),
                            visible: DockRect(x: 0, y: 4, width: 2560, height: 1406))
        XCTAssertEqual(DockGeometry.placement(panel: DockSize(width: 600, height: 300), item: bottomItems[15],
                                              restingThickness: 87, edge: .bottom, screen: hiding)?.minY, 93)
    }

    func testMagnifiedFramesDoNotMoveThePanel() {
        let s = main()
        let panel = DockSize(width: 600, height: 300)
        let resting = bottomItems[15]
        // Magnification grows the item away from the Dock's edge and along it, about its centre.
        let magnified = rect(resting.minX - 33, resting.minY, 132, 164)
        var live = bottomItems
        live[14] = rect(1154 - 20, 5, 106, 130)
        live[15] = magnified
        live[16] = rect(1286 - 20, 5, 106, 130)
        XCTAssertEqual(DockGeometry.restingThickness(items: live, edge: .bottom, screen: s), 87)
        let before = DockGeometry.placement(panel: panel, item: resting, restingThickness: 87, edge: .bottom, screen: s)
        let after = DockGeometry.placement(panel: panel, item: magnified, restingThickness: 87, edge: .bottom,
                                           screen: s)
        XCTAssertNotNil(before)
        XCTAssertEqual(before, after)

        let left = main(.left)
        let leftResting = rect(5, 700, 82, 66), leftMagnified = rect(5, 667, 164, 132)
        XCTAssertEqual(
            DockGeometry.placement(panel: panel, item: leftResting, restingThickness: 87, edge: .left, screen: left),
            DockGeometry.placement(panel: panel, item: leftMagnified, restingThickness: 87, edge: .left, screen: left))
    }

    // MARK: Dock zone and corridor (§4.1, §4.2)

    func testDockZoneIsTheItemsUnionPlusTheHoveredItemGrown() throws {
        let dock = try XCTUnwrap(DockGeometry.dockFrame(items: bottomItems))
        XCTAssertEqual(dock, rect(230, 5, 1980, 82))
        let zone = DockZone().adding(dock: dock, hoveredItem: bottomItems[15])
        // §R4 S0-1: between the items' bottom (y 5) and the `AXList`'s (y 10) is on the Dock.
        XCTAssertTrue(zone.contains(point(300, 6)))
        XCTAssertTrue(zone.contains(point(300, 87)))
        XCTAssertFalse(zone.contains(point(300, 88)))
        // The hovered item, grown by 24 pt on every side.
        XCTAssertTrue(zone.contains(point(1253, 111)))
        XCTAssertFalse(zone.contains(point(1253, 112)))
        XCTAssertTrue(zone.contains(point(1196, 50)))
        XCTAssertTrue(zone.contains(point(1253, -19)))

        // A union over the session: it only grows.
        let moved = zone.adding(dock: dock, hoveredItem: bottomItems[2])
        XCTAssertTrue(moved.contains(point(395, 100)))
        XCTAssertTrue(moved.contains(point(1253, 111)))
        // A read that fails keeps the last known zone.
        XCTAssertEqual(moved.adding(dock: nil, hoveredItem: nil), moved)
        XCTAssertEqual(moved.adding(dock: rect(0, 0, 0, 82), hoveredItem: rect(.nan, 5, 66, 82)), moved)
        // A rectangle the zone already holds adds nothing.
        XCTAssertEqual(moved.adding(dock: rect(300, 10, 10, 10), hoveredItem: nil), moved)
        // A new session starts empty.
        XCTAssertTrue(DockZone().isEmpty)
        XCTAssertFalse(DockZone().contains(point(1253, 50)))
    }

    func testDockZoneFoldsPastItsCapWithoutShrinking() {
        var zone = DockZone()
        var probes: [DockPoint] = []
        for i in 0..<(DockGeometry.zoneRectCap + 8) {
            let item = rect(Double(i) * 200, Double(i % 3) * 300, 66, 82)
            zone = zone.adding(dock: nil, hoveredItem: item)
            probes.append(item.mid)
            XCTAssertLessThanOrEqual(zone.rects.count, DockGeometry.zoneRectCap)
            for p in probes { XCTAssertTrue(zone.contains(p)) }
        }
    }

    func testCorridorHull() {
        // Bottom: item 15 and the panel's bottom edge.
        let item = bottomItems[15], panel = rect(953, 93, 600, 300)
        let hull = DockGeometry.corridor(item: item, panel: panel, edge: .bottom)
        XCTAssertEqual(hull.points, [point(953, 93), point(1220, 5), point(1286, 5), point(1553, 93)])
        XCTAssertTrue(hull.contains(point(1253, 50)))
        XCTAssertTrue(hull.contains(point(1253, 92)))
        XCTAssertTrue(hull.contains(point(970, 92)))
        XCTAssertTrue(hull.contains(point(953, 93)))
        XCTAssertFalse(hull.contains(point(940, 92)))
        XCTAssertFalse(hull.contains(point(1600, 92)))
        XCTAssertFalse(hull.contains(point(1253, 94)))
        XCTAssertFalse(hull.contains(point(1253, 4)))
        XCTAssertFalse(hull.contains(point(1000, 20)))

        // Left: the panel's left edge.
        let left = DockGeometry.corridor(item: rect(5, 700, 82, 66), panel: rect(93, 583, 600, 300), edge: .left)
        XCTAssertTrue(left.contains(point(90, 600)))
        XCTAssertTrue(left.contains(point(50, 733)))
        XCTAssertFalse(left.contains(point(50, 600)))
        XCTAssertFalse(left.contains(point(95, 733)))
        // Right: the panel's right edge.
        let right = DockGeometry.corridor(item: rect(2473, 700, 82, 66), panel: rect(1867, 583, 600, 300),
                                          edge: .right)
        XCTAssertTrue(right.contains(point(2470, 600)))
        XCTAssertTrue(right.contains(point(2510, 733)))
        XCTAssertFalse(right.contains(point(2550, 600)))
        XCTAssertFalse(right.contains(point(2465, 733)))

        // Counter-clockwise; a hull with no area holds nothing.
        var area = 0.0
        for i in hull.points.indices {
            let a = hull.points[i], b = hull.points[(i + 1) % hull.points.count]
            area += a.x * b.y - b.x * a.y
        }
        XCTAssertGreaterThan(area, 0)
        XCTAssertFalse(DockHull(of: [point(0, 0), point(5, 5), point(10, 10)]).contains(point(5, 5)))
    }

    // MARK: Hit band (X2-10)

    func testHitBandCountsAPointerJustOutsideTheRestingFrame() throws {
        let s = main()
        let item = bottomItems[15]
        let band = DockGeometry.hitBand(item: item, items: bottomItems, edge: .bottom, screen: s)
        // Abutting neighbours: no gap to share. Across: from the screen edge to 24 pt past the item's top.
        XCTAssertEqual(band, rect(1220, 0, 66, 111))
        let zone = DockZone().adding(dock: DockGeometry.dockFrame(items: bottomItems), hoveredItem: item)
        // 2 pt outside the resting frame, the selection arriving before the frame grows.
        XCTAssertTrue(DockGeometry.pointerAgrees(point(1253, 89), zone: zone, band: band))
        // Over a magnified icon before its frame grows.
        XCTAssertTrue(DockGeometry.pointerAgrees(point(1253, 107), zone: zone, band: band))
        // On the screen's last row.
        XCTAssertTrue(DockGeometry.pointerAgrees(point(1253, 0), zone: zone, band: band))
        // Over the neighbour, or past the band, it isn't.
        XCTAssertFalse(DockGeometry.pointerAgrees(point(1290, 50), zone: zone, band: band))
        XCTAssertFalse(DockGeometry.pointerAgrees(point(1253, 130), zone: zone, band: band))
        // Once the frame grows, the zone and band grow with it.
        let magnified = rect(1187, 5, 132, 164)
        let grown = DockGeometry.hitBand(item: magnified, items: bottomItems, edge: .bottom, screen: s)
        XCTAssertTrue(DockGeometry.pointerAgrees(point(1253, 150), zone: zone.adding(dock: nil, hoveredItem: magnified),
                                                 band: grown))

        // With a 6 pt gap, half of it is the item's on each side.
        let spaced = items(30, from: 230, gap: 6)
        let spacedBand = DockGeometry.hitBand(item: spaced[15], items: spaced, edge: .bottom, screen: s)
        XCTAssertEqual(spacedBand, rect(1307, 0, 72, 111))
        let spacedZone = DockZone().adding(dock: DockGeometry.dockFrame(items: spaced), hoveredItem: spaced[15])
        XCTAssertTrue(DockGeometry.pointerAgrees(point(spaced[15].maxX + 2, 50), zone: spacedZone, band: spacedBand))
        XCTAssertTrue(DockGeometry.pointerAgrees(point(spaced[15].minX - 2, 50), zone: spacedZone, band: spacedBand))
        XCTAssertFalse(DockGeometry.pointerAgrees(point(spaced[15].maxX + 4, 50), zone: spacedZone, band: spacedBand))

        // An end item reaches 24 pt past the Dock's end, as the zone does.
        let end = DockGeometry.hitBand(item: bottomItems[0], items: bottomItems, edge: .bottom, screen: s)
        XCTAssertEqual(end.minX, 206)
        XCTAssertEqual(end.maxX, 296)
    }

    func testHitBandOnSideDocks() {
        let left = main(.left), right = main(.right)
        let leftItems = items(10, from: 400, edge: .left), rightItems = items(10, from: 400, edge: .right)
        let lb = DockGeometry.hitBand(item: leftItems[4], items: leftItems, edge: .left, screen: left)
        XCTAssertEqual(lb, rect(0, 664, 111, 66))
        let lz = DockZone().adding(dock: DockGeometry.dockFrame(items: leftItems), hoveredItem: leftItems[4])
        XCTAssertTrue(DockGeometry.pointerAgrees(point(89, 697), zone: lz, band: lb))
        XCTAssertTrue(DockGeometry.pointerAgrees(point(107, 697), zone: lz, band: lb))
        XCTAssertFalse(DockGeometry.pointerAgrees(point(40, 731), zone: lz, band: lb))

        let rb = DockGeometry.hitBand(item: rightItems[4], items: rightItems, edge: .right, screen: right)
        XCTAssertEqual(rb, rect(2449, 664, 111, 66))
        let rz = DockZone().adding(dock: DockGeometry.dockFrame(items: rightItems), hoveredItem: rightItems[4])
        XCTAssertTrue(DockGeometry.pointerAgrees(point(2471, 697), zone: rz, band: rb))
        XCTAssertTrue(DockGeometry.pointerAgrees(point(2453, 697), zone: rz, band: rb))
        XCTAssertTrue(DockGeometry.pointerAgrees(point(2559, 697), zone: rz, band: rb))
        XCTAssertFalse(DockGeometry.pointerAgrees(point(2447, 697), zone: rz, band: rb))
    }

    // MARK: Cards and grid (§4.3)

    func testGridOneRowForBottomDockTwoColumnsForSideDock() throws {
        let area = DockSize(width: 2000, height: 1000)
        let bottom = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .medium,
                                                       edge: .bottom, area: area, rightToLeft: false))
        XCTAssertEqual(bottom.rows, 1)
        XCTAssertEqual(bottom.columns, 3)
        XCTAssertEqual(bottom.frames, [rect(0, 0, 280, 175), rect(292, 0, 280, 175), rect(584, 0, 280, 175)])
        XCTAssertNil(bottom.scrollAxis)
        XCTAssertEqual(bottom.panel, DockSize(width: 888, height: 231))
        // The header is the panel's top strip; the cards sit under it.
        XCTAssertEqual(bottom.header, rect(0, 199, 888, 32))
        XCTAssertEqual(bottom.viewportFrame, rect(12, 12, 864, 175))

        for edge in [DockEdge.left, .right] {
            let side = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .medium,
                                                         edge: edge, area: area, rightToLeft: false))
            XCTAssertEqual(side.columns, 2)
            XCTAssertEqual(side.rows, 2)
            // The first row is the top one.
            XCTAssertEqual(side.frames, [rect(0, 187, 280, 175), rect(292, 187, 280, 175), rect(0, 0, 280, 175)])
            XCTAssertEqual(side.content, DockSize(width: 572, height: 362))
        }
        // One card needs one column.
        let single = DockGeometry.layout(windows: 1, moreWindows: false, preferred: .medium, edge: .left, area: area,
                                         rightToLeft: false)
        XCTAssertEqual(single?.columns, 1)
        // No cells, no grid.
        XCTAssertNil(DockGeometry.layout(windows: 0, moreWindows: false, preferred: .medium, edge: .bottom, area: area,
                                         rightToLeft: false))
    }

    func testCardsDropOneSizeThenScrollHorizontallyForBottomDock() throws {
        func layout(_ preferred: DockCardSize, width: Double) throws -> DockPanelLayout {
            try XCTUnwrap(DockGeometry.layout(windows: 5, moreWindows: false, preferred: preferred, edge: .bottom,
                                              area: DockSize(width: width, height: 400), rightToLeft: false))
        }
        // Five Large cards need 1872 pt.
        let large = try layout(.large, width: 2000)
        XCTAssertEqual(large.cardSize, .large)
        XCTAssertNil(large.scrollAxis)
        // Not enough room: one size down.
        let medium = try layout(.large, width: 1600)
        XCTAssertEqual(medium.cardSize, .medium)
        XCTAssertNil(medium.scrollAxis)
        XCTAssertEqual(medium.panel.width, 1472)
        // Still not enough: Medium scrolls; it doesn't drop a second size.
        let scrolled = try layout(.large, width: 1000)
        XCTAssertEqual(scrolled.cardSize, .medium)
        XCTAssertEqual(scrolled.scrollAxis, .horizontal)
        XCTAssertEqual(scrolled.viewport, DockSize(width: 976, height: 175))
        XCTAssertEqual(scrolled.panel, DockSize(width: 1000, height: 231))
        XCTAssertEqual(scrolled.maxScrollOffset, 1448 - 976)
        // Medium drops to Small, which scrolls; Small only scrolls.
        let fromMedium = try layout(.medium, width: 1000)
        XCTAssertEqual(fromMedium.cardSize, .small)
        XCTAssertEqual(fromMedium.scrollAxis, .horizontal)
        XCTAssertEqual(try layout(.small, width: 1000).cardSize, .small)
        XCTAssertNil(try layout(.small, width: 1100).scrollAxis)
        // No “+N more”: one cell per window.
        for l in [large, medium, scrolled, fromMedium] {
            XCTAssertEqual(l.cells, (0..<5).map(DockCell.window))
        }
        // Not even one card fits in view.
        XCTAssertNil(DockGeometry.layout(windows: 5, moreWindows: false, preferred: .small, edge: .bottom,
                                         area: DockSize(width: 200, height: 400), rightToLeft: false))
    }

    func testCardsDropOneSizeThenScrollVerticallyForSideDock() throws {
        for edge in [DockEdge.left, .right] {
            let fits = try XCTUnwrap(DockGeometry.layout(windows: 4, moreWindows: false, preferred: .large,
                                                         edge: edge, area: DockSize(width: 800, height: 1000),
                                                         rightToLeft: false))
            XCTAssertEqual(fits.cardSize, .large)
            XCTAssertNil(fits.scrollAxis)
            let l = try XCTUnwrap(DockGeometry.layout(windows: 9, moreWindows: false, preferred: .large, edge: edge,
                                                      area: DockSize(width: 800, height: 700), rightToLeft: false))
            XCTAssertEqual(l.cardSize, .medium)
            XCTAssertEqual(l.scrollAxis, .vertical)
            XCTAssertEqual(l.viewport, DockSize(width: 572, height: 644))
            XCTAssertEqual(l.content, DockSize(width: 572, height: 923))
            XCTAssertEqual(l.panel, DockSize(width: 596, height: 700))
            XCTAssertEqual(l.cells, (0..<9).map(DockCell.window))
            // Offset 0 shows the top row.
            XCTAssertTrue(l.visibleContent(at: 0).contains(l.frames[0]))
            XCTAssertEqual(l.offset(revealing: 8), l.maxScrollOffset)
        }
    }

    func testFixedSixteenByTenCardWithLetterboxedThumbnail() throws {
        for size in DockCardSize.allCases {
            let c = DockGeometry.card(size)
            XCTAssertEqual(c.width / c.height, 1.6, accuracy: 1e-12)
        }
        XCTAssertEqual(DockGeometry.card(.medium), DockSize(width: 280, height: 175))
        let card = rect(0, 0, 280, 175)
        // A very wide window: full width, centred top to bottom.
        XCTAssertEqual(DockGeometry.letterbox(image: DockSize(width: 4000, height: 500), in: card),
                       rect(0, 70, 280, 35))
        // A very tall one: full height, centred left to right.
        XCTAssertEqual(DockGeometry.letterbox(image: DockSize(width: 300, height: 3000), in: card),
                       rect(131.25, 0, 17.5, 175))
        // 16:10 fills the card; the card's own frame never changes with the image.
        XCTAssertEqual(DockGeometry.letterbox(image: DockSize(width: 1600, height: 1000), in: card), card)
        XCTAssertEqual(DockGeometry.letterbox(image: DockSize(width: 32, height: 64), in: rect(10, 20, 200, 125)),
                       rect(78.75, 20, 62.5, 125))
        XCTAssertNil(DockGeometry.letterbox(image: DockSize(width: 0, height: 500), in: card))
        XCTAssertNil(DockGeometry.letterbox(image: DockSize(width: .infinity, height: 500), in: card))
        XCTAssertNil(DockGeometry.letterbox(image: DockSize(width: 100, height: 50), in: rect(0, 0, 0, 0)))
        let l = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .large, edge: .bottom,
                                                  area: DockSize(width: 2000, height: 1000), rightToLeft: false))
        XCTAssertTrue(l.frames.allSatisfy { $0.width == 360 && $0.height == 225 })
    }

    func testMoreWindowsIsTheLastCellInsideTheScrollRange() throws {
        for edge in DockEdge.allCases {
            for rtl in [false, true] {
                let l = try XCTUnwrap(DockGeometry.layout(windows: 40, moreWindows: true, preferred: .medium,
                                                          edge: edge, area: DockSize(width: 1000, height: 800),
                                                          rightToLeft: rtl))
                XCTAssertEqual(l.cells.count, 41)
                XCTAssertEqual(l.cells.last, .moreWindows)
                XCTAssertEqual(l.cells.filter { $0 == .moreWindows }.count, 1)
                XCTAssertNotNil(l.scrollAxis)
                let last = try XCTUnwrap(l.frames.last)
                XCTAssertTrue(rect(0, 0, l.content.width, l.content.height).contains(last))
                let offset = try XCTUnwrap(l.offset(revealing: 40))
                XCTAssertLessThanOrEqual(offset, l.maxScrollOffset)
                XCTAssertTrue(l.visibleContent(at: offset).contains(last))
            }
        }
        let small = DockGeometry.layout(windows: 2, moreWindows: true, preferred: .medium, edge: .bottom,
                                        area: DockSize(width: 2000, height: 800), rightToLeft: false)
        XCTAssertEqual(small?.cells, [.window(0), .window(1), .moreWindows])
        XCTAssertNil(small?.scrollAxis)
    }

    func testRightToLeftMirrors() throws {
        let area = DockSize(width: 2000, height: 1000)
        let ltr = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .medium, edge: .bottom,
                                                    area: area, rightToLeft: false))
        let rtl = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .medium, edge: .bottom,
                                                    area: area, rightToLeft: true))
        XCTAssertEqual(rtl.frames.map(\.minX), [584, 292, 0])
        for (a, b) in zip(ltr.frames, rtl.frames) {
            XCTAssertEqual(b.minX, ltr.content.width - a.maxX)
            XCTAssertEqual(b.minY, a.minY)
        }
        XCTAssertEqual(rtl.panel, ltr.panel)
        XCTAssertEqual(rtl.header, ltr.header)
        XCTAssertEqual(rtl.viewportFrame, ltr.viewportFrame)

        // Scrolling starts at the right end.
        let scrolled = try XCTUnwrap(DockGeometry.layout(windows: 20, moreWindows: true, preferred: .small,
                                                         edge: .bottom, area: DockSize(width: 1000, height: 400),
                                                         rightToLeft: true))
        XCTAssertEqual(scrolled.frames[0].maxX, scrolled.content.width)
        XCTAssertTrue(scrolled.visibleContent(at: 0).contains(scrolled.frames[0]))
        XCTAssertEqual(scrolled.frames[20].minX, 0)
        XCTAssertEqual(scrolled.offset(revealing: 20), scrolled.maxScrollOffset)
        XCTAssertTrue(scrolled.visibleContent(at: scrolled.maxScrollOffset).contains(scrolled.frames[20]))

        // A side Dock's first card is in the right column.
        let side = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .medium, edge: .left,
                                                     area: area, rightToLeft: true))
        XCTAssertEqual(side.frames, [rect(292, 187, 280, 175), rect(0, 187, 280, 175), rect(292, 0, 280, 175)])
    }

    func testThumbnailsForCardsInViewPlusOneBeyondEachEdge() throws {
        let l = try XCTUnwrap(DockGeometry.layout(windows: 20, moreWindows: false, preferred: .small, edge: .bottom,
                                                  area: DockSize(width: 1000, height: 400), rightToLeft: false))
        XCTAssertEqual(l.viewport.width, 976)
        XCTAssertEqual(l.thumbnailWindows(at: 0), Array(0...5))
        XCTAssertEqual(l.thumbnailWindows(at: 1060), Array(4...10))
        XCTAssertEqual(l.thumbnailWindows(at: l.maxScrollOffset), Array(14...19))
        XCTAssertEqual(l.thumbnailWindows(at: 1e9), Array(14...19))
        // “More windows…” has no thumbnail.
        let more = try XCTUnwrap(DockGeometry.layout(windows: 20, moreWindows: true, preferred: .small, edge: .bottom,
                                                     area: DockSize(width: 1000, height: 400), rightToLeft: false))
        XCTAssertEqual(more.thumbnailWindows(at: more.maxScrollOffset), Array(15...19))
        // Everything in view when nothing scrolls.
        let fits = try XCTUnwrap(DockGeometry.layout(windows: 3, moreWindows: false, preferred: .small, edge: .bottom,
                                                     area: DockSize(width: 2000, height: 400), rightToLeft: false))
        XCTAssertEqual(fits.thumbnailWindows(at: 0), [0, 1, 2])
    }

    // MARK: Capture scale (X-27, X2-20)

    func testCaptureScaleFromTheScreenHoldingTheWindow() {
        let screens = [main(), builtIn]
        XCTAssertEqual(DockGeometry.captureScale(window: rect(-1500, 500, 800, 600), screens: screens), 2)
        XCTAssertEqual(DockGeometry.captureScale(window: rect(100, 500, 800, 600), screens: screens), 1)
        // Mostly on the main display, centre included.
        XCTAssertEqual(DockGeometry.captureScale(window: rect(-200, 500, 1000, 600), screens: screens), 1)
        // Minimized, or on no screen: the largest scale.
        XCTAssertEqual(DockGeometry.captureScale(window: nil, screens: screens), 2)
        XCTAssertEqual(DockGeometry.captureScale(window: rect(9000, 9000, 800, 600), screens: screens), 2)
        XCTAssertEqual(DockGeometry.captureScale(window: nil, screens: []), 1)
    }

    // MARK: Fuzz

    func testFuzzPanelInsideVisibleFrameNeverOverItemAndEveryCardReachable() throws {
        var rng = SeededGenerator(seed: 0xD0C_6E0)
        func unit() -> Double { Double(rng.next() % 1_000_001) / 1_000_000 }
        func between(_ lo: Double, _ hi: Double) -> Double { lo + unit() * (hi - lo) }
        func pick<T>(_ xs: [T]) -> T { xs[Int(rng.next() % UInt64(xs.count))] }
        var checkedCells = 0

        for n in 0..<10_000 {
            let edge = pick(DockEdge.allCases)
            let primary = rng.next() % 3 == 0
            let frame = DockRect(x: primary ? 0 : between(-6000, 6000).rounded(),
                                 y: primary ? 0 : between(-3000, 3000).rounded(),
                                 width: between(1024, 6016).rounded(), height: between(640, 3384).rounded())
            let menu = pick([0.0, 24, 30, 37])
            let depth = between(30, 150), inset = between(0, 6), pitch = between(depth * 0.6, depth * 0.95)
            let gap = pick([0.0, 0, 2, 6, 12])
            let hides = rng.next() % 4 == 0
            let reserved = hides ? 4 : inset + depth + between(0, 6)
            var visible = DockRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menu)
            switch edge {
            case .bottom: visible.y += reserved; visible.height -= reserved
            case .left: visible.x += reserved; visible.width -= reserved
            case .right: visible.width -= reserved
            }
            let s = DockScreen(id: 1, frame: frame, visibleFrame: visible, scale: pick([1.0, 2]), isPrimary: primary)
            let length = edge.isHorizontal ? frame.width : frame.height - menu
            var count = Int(rng.next() % 59) + 2
            while count > 2 && Double(count) * (pitch + gap) > length - 40 { count -= 1 }
            let start = (edge.isHorizontal ? frame.minX : frame.minY)
                + (length - Double(count) * (pitch + gap) + gap) / 2
            let dock = items(count, from: start, edge: edge, on: s, pitch: pitch, gap: gap, depth: depth, inset: inset)
            let item = dock[Int(rng.next() % UInt64(count))]
            let windows = Int(rng.next() % 151)
            let more = windows == 0 || rng.next() % 4 == 0
            let preferred = pick(DockCardSize.allCases)
            let rtl = rng.next() % 2 == 0
            let context = "case \(n): \(edge) \(frame) item \(item) windows \(windows) more \(more) \(preferred)"

            let dockFrame = try XCTUnwrap(DockGeometry.dockFrame(items: dock), context)
            XCTAssertEqual(DockGeometry.edge(ofItem: item, dock: dockFrame, on: s), edge, context)
            let thickness = try XCTUnwrap(DockGeometry.restingThickness(items: dock, edge: edge, screen: s), context)
            let area = try XCTUnwrap(DockGeometry.panelArea(restingThickness: thickness, edge: edge, screen: s),
                                     context)
            let l = try XCTUnwrap(DockGeometry.layout(windows: windows, moreWindows: more, preferred: preferred,
                                                      edge: edge, area: DockSize(width: area.width,
                                                                                 height: area.height),
                                                      rightToLeft: rtl), context)
            let panel = try XCTUnwrap(DockGeometry.placement(panel: l.panel, item: item, restingThickness: thickness,
                                                             edge: edge, screen: s), context)

            // Inside the visible frame, 8 pt off its edges away from the Dock, and clear of every item by 6 pt.
            XCTAssertTrue(visible.outset(by: 1e-6).contains(panel), context)
            let v = visible.outset(by: -DockGeometry.screenMargin + 1e-6)
            switch edge {
            case .bottom:
                XCTAssertTrue(panel.minX >= v.minX && panel.maxX <= v.maxX && panel.maxY <= v.maxY, context)
                XCTAssertGreaterThanOrEqual(panel.minY - item.maxY, DockGeometry.panelGap - 1e-6, context)
            case .left:
                XCTAssertTrue(panel.minY >= v.minY && panel.maxY <= v.maxY && panel.maxX <= v.maxX, context)
                XCTAssertGreaterThanOrEqual(panel.minX - item.maxX, DockGeometry.panelGap - 1e-6, context)
            case .right:
                XCTAssertTrue(panel.minY >= v.minY && panel.maxY <= v.maxY && panel.minX >= v.minX, context)
                XCTAssertGreaterThanOrEqual(item.minX - panel.maxX, DockGeometry.panelGap - 1e-6, context)
            }
            XCTAssertFalse(dock.contains { $0.intersects(panel) }, context)

            // Every window has a cell, “More windows…” is last, and every cell is reachable by scrolling.
            XCTAssertEqual(l.cells.count, windows + (more ? 1 : 0), context)
            if more { XCTAssertEqual(l.cells.last, .moreWindows, context) }
            let contentRect = DockRect(x: 0, y: 0, width: l.content.width, height: l.content.height).outset(by: 1e-6)
            for i in l.frames.indices {
                let offset = try XCTUnwrap(l.offset(revealing: i), context)
                XCTAssertTrue(offset >= 0 && offset <= l.maxScrollOffset, context)
                XCTAssertTrue(contentRect.contains(l.frames[i]), context)
                XCTAssertTrue(l.visibleContent(at: offset).outset(by: 1e-6).contains(l.frames[i]), "\(context) cell \(i)")
                checkedCells += 1
            }

            // The pointer 2 pt past the resting frame's far side agrees with the selection.
            let band = DockGeometry.hitBand(item: item, items: dock, edge: edge, screen: s)
            let zone = DockZone().adding(dock: dockFrame, hoveredItem: item)
            let outside: DockPoint
            switch edge {
            case .bottom: outside = point(item.midX, item.maxY + 2)
            case .left: outside = point(item.maxX + 2, item.midY)
            case .right: outside = point(item.minX - 2, item.midY)
            }
            XCTAssertTrue(DockGeometry.pointerAgrees(outside, zone: zone, band: band), context)
            XCTAssertTrue(DockGeometry.corridor(item: item, panel: panel, edge: edge).contains(item.mid), context)
        }
        XCTAssertGreaterThan(checkedCells, 10_000)
    }
}
