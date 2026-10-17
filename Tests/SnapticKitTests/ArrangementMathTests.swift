import XCTest
@testable import SnapticKit

final class ArrangementMathTests: XCTestCase {
    private let main = ArrangeRect(x: 0, y: 0, width: 1512, height: 982)

    func testPlacements() {
        func check(_ p: ArrangementPlacement, _ x: Int32, _ y: Int32, line: UInt = #line) {
            let o = ArrangementMath.origin(width: 1920, height: 1080, relativeTo: main, placement: p)
            XCTAssertEqual(o.x, x, p.rawValue, line: line)
            XCTAssertEqual(o.y, y, p.rawValue, line: line)
        }
        check(.leftTop, -1920, 0)
        check(.leftBottom, -1920, -98)
        check(.leftCenter, -1920, -49)
        check(.rightTop, 1512, 0)
        check(.aboveLeft, 0, -1080)
        check(.aboveCenter, -204, -1080)
        check(.aboveRight, -408, -1080)
        check(.belowCenter, -204, 982)
        check(.topLeftCorner, -1920, -1080)
        check(.bottomRightCorner, 1512, 982)
        let br = ArrangementMath.belowRightOfMain(width: 1920, height: 1080, main: main)
        XCTAssertEqual(br.x, 1512)
        XCTAssertEqual(br.y, 982)
        XCTAssertEqual(ArrangementPlacement.allCases.count, 16)
        XCTAssertEqual(Set(ArrangementPlacement.allCases.map(\.title)).count, 16)
    }

    func testEveryNonCornerPlacementTouches() {
        for p in ArrangementPlacement.allCases {
            let o = ArrangementMath.origin(width: 800, height: 600, relativeTo: main, placement: p)
            let r = ArrangeRect(x: o.x, y: o.y, width: 800, height: 600)
            XCTAssertFalse(r.overlaps(main), p.rawValue)
            let corner = [ArrangementPlacement.topLeftCorner, .topRightCorner, .bottomLeftCorner, .bottomRightCorner].contains(p)
            XCTAssertEqual(r.touches(main), !corner, p.rawValue)
        }
    }

    func testSnapAttachesWithoutOverlap() {
        var rng = SeededGenerator(seed: 0xA11)
        let others = [main, ArrangeRect(x: 1512, y: -200, width: 2560, height: 1440)]
        for _ in 0..<2000 {
            let m = ArrangeRect(x: Int32(Int(rng.next() % 9000)) - 4500, y: Int32(Int(rng.next() % 6000)) - 3000,
                                width: 640 + Int(rng.next() % 3000), height: 480 + Int(rng.next() % 2000))
            let s = ArrangementMath.snap(m, others: others)
            XCTAssertFalse(others.contains { $0.overlaps(s) })
            XCTAssertTrue(others.contains { $0.touches(s) })
            XCTAssertEqual(s.width, m.width)
            XCTAssertTrue(ArrangementMath.isValid(others + [s]))
        }
    }

    func testSnapAlignsWhenClose() {
        let m = ArrangeRect(x: 1600, y: 10, width: 1920, height: 1080)
        let s = ArrangementMath.snap(m, others: [main])
        XCTAssertEqual(s.x, 1512)
        XCTAssertEqual(s.y, 0, "top edges aligned within the threshold")
        XCTAssertEqual(ArrangementMath.snap(m, others: []), m.moved(x: 0, y: 0))
    }

    func testNormalizeAndValidity() {
        let rects = ["a": ArrangeRect(x: 100, y: 50, width: 10, height: 10), "b": ArrangeRect(x: 110, y: 50, width: 10, height: 10)]
        let n = ArrangementMath.normalized(rects, main: "b")
        XCTAssertEqual(n["b"]?.x, 0)
        XCTAssertEqual(n["a"]?.x, -10)
        XCTAssertEqual(ArrangementMath.normalized(rects, main: "zz"), rects)
        XCTAssertTrue(ArrangementMath.isValid(Array(rects.values)))
        XCTAssertFalse(ArrangementMath.isValid([ArrangeRect(x: 0, y: 0, width: 10, height: 10), ArrangeRect(x: 5, y: 5, width: 10, height: 10)]))
        XCTAssertFalse(ArrangementMath.isValid([ArrangeRect(x: 0, y: 0, width: 10, height: 10), ArrangeRect(x: 50, y: 0, width: 10, height: 10)]))
        XCTAssertFalse(ArrangeRect(x: 0, y: 0, width: 10, height: 10).touches(ArrangeRect(x: 10, y: 10, width: 5, height: 5)), "corners only")
        XCTAssertTrue(ArrangementMath.isValid([]))
    }
}
