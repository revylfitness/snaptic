import XCTest
@testable import SnapticKit

/// §4.5: what a point in the panel is over, for the keys' target.
final class DockPanelHitTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> DockPoint { DockPoint(x: x, y: y) }

    private func layout(windows: Int, more: Bool = false, edge: DockEdge = .bottom, width: Double = 2000,
                        height: Double = 1000, rtl: Bool = false) throws -> DockPanelLayout {
        try XCTUnwrap(DockGeometry.layout(windows: windows, moreWindows: more, preferred: .medium, edge: edge,
                                          area: DockSize(width: width, height: height), rightToLeft: rtl))
    }

    /// Where cell `i`'s centre is in the panel at `offset`, if it's in view.
    private func panelPoint(of i: Int, in l: DockPanelLayout, offset: Double) -> DockPoint? {
        let view = l.visibleContent(at: offset)
        let mid = l.frames[i].mid
        guard view.contains(mid) else { return nil }
        return point(l.viewportFrame.minX + mid.x - view.minX, l.viewportFrame.minY + mid.y - view.minY)
    }

    func testHeaderPaddingSpacingAndCards() throws {
        // Three Medium cards (280 × 175, 12 apart); the viewport is (12, 12, 864, 175), the header (0, 199, 888, 32).
        let l = try layout(windows: 3)
        XCTAssertEqual(l.hit(point(100, 210), scrollOffset: 0), .header)
        XCTAssertEqual(l.hit(point(887, 230), scrollOffset: 0), .header)
        // The padding around the cards, and the strip between the cards and the header.
        XCTAssertEqual(l.hit(point(5, 5), scrollOffset: 0), .gap)
        XCTAssertEqual(l.hit(point(100, 192), scrollOffset: 0), .gap)
        XCTAssertEqual(l.hit(point(880, 100), scrollOffset: 0), .gap)
        // The cards, and the spacing between them.
        XCTAssertEqual(l.hit(point(22, 22), scrollOffset: 0), .window(0))
        XCTAssertEqual(l.hit(point(12 + 286, 100), scrollOffset: 0), .gap)
        XCTAssertEqual(l.hit(point(12 + 300, 100), scrollOffset: 0), .window(1))
        XCTAssertEqual(l.hit(point(12 + 600, 100), scrollOffset: 0), .window(2))
        // Outside the panel.
        XCTAssertEqual(l.hit(point(-5, 100), scrollOffset: 0), .gap)
        XCTAssertEqual(l.hit(point(100, 400), scrollOffset: 0), .gap)
    }

    func testScrolledCardsFollowTheOffset() throws {
        // Five Medium cards don't fit 1000 pt, so they drop to Small (200 × 125, 12 apart) and scroll horizontally:
        // content 1048 wide, viewport 976, so the scroll range is 0…72.
        let l = try layout(windows: 5, width: 1000, height: 400)
        XCTAssertEqual(l.scrollAxis, .horizontal)
        XCTAssertEqual(l.maxScrollOffset, 72)
        XCTAssertEqual(l.hit(point(12 + 150, 100), scrollOffset: 0), .window(0))
        // Scrolled 72: viewport x 150 is content x 222, inside window 1 (212…412).
        XCTAssertEqual(l.hit(point(12 + 150, 100), scrollOffset: 72), .window(1))
        // Past the end clamps to the scroll range: viewport x 970 is content x 1042, inside window 4 (848…1048).
        XCTAssertEqual(l.hit(point(12 + 970, 100), scrollOffset: 10_000), .window(4))
        for offset in [0, 30, 50, l.maxScrollOffset] {
            for i in 0..<5 {
                guard let p = panelPoint(of: i, in: l, offset: offset) else { continue }
                XCTAssertEqual(l.hit(p, scrollOffset: offset), .window(i), "card \(i) at \(offset)")
            }
        }
    }

    func testRightToLeftAndSideDocks() throws {
        let rtl = try layout(windows: 5, width: 1000, height: 400, rtl: true)
        // Offset 0 shows the start of the scroll axis: the right end, where window 0 sits.
        XCTAssertEqual(rtl.hit(point(12 + 966, 100), scrollOffset: 0), .window(0))
        var seen = 0
        for offset in [0, 200, rtl.maxScrollOffset] {
            for i in 0..<5 {
                guard let p = panelPoint(of: i, in: rtl, offset: offset) else { continue }
                XCTAssertEqual(rtl.hit(p, scrollOffset: offset), .window(i), "RTL card \(i) at \(offset)")
                seen += 1
            }
        }
        XCTAssertGreaterThan(seen, 5)

        // A side Dock with more cards than fit scrolls vertically, from the top.
        let side = try layout(windows: 12, edge: .left, width: 1000, height: 600)
        XCTAssertEqual(side.scrollAxis, .vertical)
        seen = 0
        for offset in [0, 250, side.maxScrollOffset] {
            for i in 0..<12 {
                guard let p = panelPoint(of: i, in: side, offset: offset) else { continue }
                XCTAssertEqual(side.hit(p, scrollOffset: offset), .window(i), "side card \(i) at \(offset)")
                seen += 1
            }
        }
        XCTAssertGreaterThan(seen, 6)
    }

    func testMoreWindowsIsAGap() throws {
        let l = try layout(windows: 2, more: true)
        XCTAssertEqual(l.cells.last, .moreWindows)
        let p = try XCTUnwrap(panelPoint(of: 2, in: l, offset: 0))
        XCTAssertEqual(l.hit(p, scrollOffset: 0), .gap)
        XCTAssertEqual(l.hit(try XCTUnwrap(panelPoint(of: 1, in: l, offset: 0)), scrollOffset: 0), .window(1))
    }

    func testKeyTarget() {
        let facts: (Int) -> (hasAXElement: Bool, minimized: Bool)? = { i in
            switch i {
            case 0: return (true, false)
            case 1: return (false, false)
            case 2: return (true, true)
            default: return nil
            }
        }
        XCTAssertEqual(DockPanelHit.keyTarget(nil, card: facts), DockKeyTarget.none)
        XCTAssertEqual(DockPanelHit.keyTarget(.header, card: facts), .header)
        XCTAssertEqual(DockPanelHit.keyTarget(.gap, card: facts), .gap)
        XCTAssertEqual(DockPanelHit.keyTarget(.window(0), card: facts), .card(hasAXElement: true, minimized: false))
        XCTAssertEqual(DockPanelHit.keyTarget(.window(1), card: facts), .card(hasAXElement: false, minimized: false))
        XCTAssertEqual(DockPanelHit.keyTarget(.window(2), card: facts), .card(hasAXElement: true, minimized: true))
        // A window the panel no longer lists.
        XCTAssertEqual(DockPanelHit.keyTarget(.window(7), card: facts), .gap)
    }
}
