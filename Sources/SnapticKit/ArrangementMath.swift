import Foundation

// Arrangement geometry: the 16 Position/Align placements, canvas snapping and
// normalisation (owner: D). PLAN §9.6, §3.7. CoreGraphics coordinates: y grows downward,
// the main display's origin is (0, 0).

package struct ArrangeRect: Codable, Equatable, Sendable {
    package var x: Int32
    package var y: Int32
    package var width: Int
    package var height: Int

    package init(x: Int32, y: Int32, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = max(1, width)
        self.height = max(1, height)
    }

    package var maxX: Int64 { Int64(x) + Int64(width) }
    package var maxY: Int64 { Int64(y) + Int64(height) }

    package func moved(x: Int32, y: Int32) -> ArrangeRect { ArrangeRect(x: x, y: y, width: width, height: height) }

    package func overlaps(_ o: ArrangeRect) -> Bool {
        Int64(x) < o.maxX && Int64(o.x) < maxX && Int64(y) < o.maxY && Int64(o.y) < maxY
    }

    /// Shares an edge segment of positive length (touching corners don't count).
    package func touches(_ o: ArrangeRect) -> Bool {
        let vertical = (maxX == Int64(o.x) || Int64(x) == o.maxX) && Int64(y) < o.maxY && Int64(o.y) < maxY
        let horizontal = (maxY == Int64(o.y) || Int64(y) == o.maxY) && Int64(x) < o.maxX && Int64(o.x) < maxX
        return vertical || horizontal
    }
}

/// The 16 placements of the Position/Align form: three alignments on each side, plus corners.
package enum ArrangementPlacement: String, Codable, CaseIterable, Sendable {
    case leftTop, leftCenter, leftBottom
    case rightTop, rightCenter, rightBottom
    case aboveLeft, aboveCenter, aboveRight
    case belowLeft, belowCenter, belowRight
    case topLeftCorner, topRightCorner, bottomLeftCorner, bottomRightCorner

    package var title: String {
        switch self {
        case .leftTop: return L("Left, Top Aligned")
        case .leftCenter: return L("Left, Centered")
        case .leftBottom: return L("Left, Bottom Aligned")
        case .rightTop: return L("Right, Top Aligned")
        case .rightCenter: return L("Right, Centered")
        case .rightBottom: return L("Right, Bottom Aligned")
        case .aboveLeft: return L("Above, Left Aligned")
        case .aboveCenter: return L("Above, Centered")
        case .aboveRight: return L("Above, Right Aligned")
        case .belowLeft: return L("Below, Left Aligned")
        case .belowCenter: return L("Below, Centered")
        case .belowRight: return L("Below, Right Aligned")
        case .topLeftCorner: return L("Top-Left Corner")
        case .topRightCorner: return L("Top-Right Corner")
        case .bottomLeftCorner: return L("Bottom-Left Corner")
        case .bottomRightCorner: return L("Bottom-Right Corner")
        }
    }
}

package enum ArrangementMath {
    private static func clamp(_ v: Int64) -> Int32 { Int32(max(Int64(Int32.min), min(Int64(Int32.max), v))) }

    /// Origin that puts a display of `width × height` at `placement` relative to `reference`.
    package static func origin(width: Int, height: Int, relativeTo r: ArrangeRect,
                               placement: ArrangementPlacement) -> (x: Int32, y: Int32) {
        let w = Int64(max(1, width)), h = Int64(max(1, height))
        let rx = Int64(r.x), ry = Int64(r.y), rw = Int64(r.width), rh = Int64(r.height)
        let left = rx - w, right = rx + rw, above = ry - h, below = ry + rh
        let alignTop = ry, alignMiddle = ry + (rh - h) / 2, alignBottom = ry + rh - h
        let alignLeft = rx, alignCenter = rx + (rw - w) / 2, alignRight = rx + rw - w
        let p: (Int64, Int64)
        switch placement {
        case .leftTop: p = (left, alignTop)
        case .leftCenter: p = (left, alignMiddle)
        case .leftBottom: p = (left, alignBottom)
        case .rightTop: p = (right, alignTop)
        case .rightCenter: p = (right, alignMiddle)
        case .rightBottom: p = (right, alignBottom)
        case .aboveLeft: p = (alignLeft, above)
        case .aboveCenter: p = (alignCenter, above)
        case .aboveRight: p = (alignRight, above)
        case .belowLeft: p = (alignLeft, below)
        case .belowCenter: p = (alignCenter, below)
        case .belowRight: p = (alignRight, below)
        case .topLeftCorner: p = (left, above)
        case .topRightCorner: p = (right, above)
        case .bottomLeftCorner: p = (left, below)
        case .bottomRightCorner: p = (right, below)
        }
        return (clamp(p.0), clamp(p.1))
    }

    /// Below and to the right of the main display, so the pointer doesn't drift into it (§9.4).
    package static func belowRightOfMain(width: Int, height: Int, main: ArrangeRect) -> (x: Int32, y: Int32) {
        origin(width: width, height: height, relativeTo: main, placement: .bottomRightCorner)
    }

    /// Where a dragged display lands: attached to the nearest edge of another display with
    /// no overlap, with alignment snapping within `threshold` points.
    package static func snap(_ moving: ArrangeRect, others: [ArrangeRect], threshold: Int = 24) -> ArrangeRect {
        guard !others.isEmpty else { return moving.moved(x: 0, y: 0) }
        var candidates: [ArrangeRect] = []
        let w = Int64(moving.width), h = Int64(moving.height)
        let mx = Int64(moving.x), my = Int64(moving.y)
        for o in others {
            // Free coordinate clamped so the edges share at least one point of length.
            let yFree = min(max(my, Int64(o.y) - h + 1), o.maxY - 1)
            let xFree = min(max(mx, Int64(o.x) - w + 1), o.maxX - 1)
            candidates.append(moving.moved(x: clamp(Int64(o.x) - w), y: clamp(alignSnap(yFree, h, o.y, o.height, threshold))))
            candidates.append(moving.moved(x: clamp(o.maxX), y: clamp(alignSnap(yFree, h, o.y, o.height, threshold))))
            candidates.append(moving.moved(x: clamp(alignSnap(xFree, w, o.x, o.width, threshold)), y: clamp(Int64(o.y) - h)))
            candidates.append(moving.moved(x: clamp(alignSnap(xFree, w, o.x, o.width, threshold)), y: clamp(o.maxY)))
        }
        let valid = candidates.filter { c in !others.contains { $0.overlaps(c) } }
        let pool = valid.isEmpty ? candidates : valid
        return pool.min { distance($0, moving) < distance($1, moving) } ?? moving
    }

    /// Snaps the free coordinate to start/center/end alignment with the neighbour when close.
    private static func alignSnap(_ v: Int64, _ size: Int64, _ start: Int32, _ length: Int, _ threshold: Int) -> Int64 {
        let s = Int64(start), l = Int64(length), t = Int64(max(0, threshold))
        let options = [s, s + l - size, s + (l - size) / 2]
        var best = v
        var bestD = t + 1
        for o in options where abs(o - v) <= t && abs(o - v) < bestD {
            best = o
            bestD = abs(o - v)
        }
        return best
    }

    private static func distance(_ a: ArrangeRect, _ b: ArrangeRect) -> Int64 {
        abs(Int64(a.x) - Int64(b.x)) + abs(Int64(a.y) - Int64(b.y))
    }

    /// Translates every origin so the main display sits at (0, 0).
    package static func normalized<K: Hashable>(_ rects: [K: ArrangeRect], main: K) -> [K: ArrangeRect] {
        guard let m = rects[main] else { return rects }
        let dx = Int64(m.x), dy = Int64(m.y)
        return rects.mapValues { $0.moved(x: clamp(Int64($0.x) - dx), y: clamp(Int64($0.y) - dy)) }
    }

    /// Every display touches another (a connected arrangement) and none overlap.
    package static func isValid(_ rects: [ArrangeRect]) -> Bool {
        guard rects.count > 1 else { return true }
        for i in rects.indices {
            for j in rects.indices where j > i && rects[i].overlaps(rects[j]) { return false }
        }
        var reached: Set<Int> = [0]
        var frontier = [0]
        while let i = frontier.popLast() {
            for j in rects.indices where !reached.contains(j) && rects[i].touches(rects[j]) {
                reached.insert(j)
                frontier.append(j)
            }
        }
        return reached.count == rects.count
    }
}

/// The underscan presets of the per-display menu (the page keeps a free slider).
package enum UnderscanSteps {
    /// 0 = off … 1 = the most underscan macOS offers.
    package static let values: [Double] = [0, 0.25, 0.5, 0.75, 1]

    /// The preset closest to a live value (ties go to the smaller), or nil when unknown.
    package static func nearest(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        let v = min(1, max(0, value))
        return values.min { abs($0 - v) < abs($1 - v) || (abs($0 - v) == abs($1 - v) && $0 < $1) }
    }

    package static func title(_ step: Double) -> String {
        step <= 0 ? L("Off") : "\(Int((step * 100).rounded()))%"
    }
}
