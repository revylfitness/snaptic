import Foundation

// Dock Previews' geometry (lead; PLAN 0.5 §2.1, §4.1–§4.3, §4.7). Pure: the AX → Cocoa conversion (X-27), the Dock's
// edge from a settled item frame, the Dock zone and hit band, the corridor hull, placement, the capture scale, and the
// card grid (drop a size, then scroll; RTL). Every rectangle is in AppKit global coordinates unless its name says
// otherwise.

/// A width and height in points.
package struct DockSize: Codable, Equatable, Sendable {
    package var width: Double
    package var height: Double

    package init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// §4.1: where the pointer counts as on the Dock, for one hover session. It only grows; the controller starts a new
/// one (`DockZone()`) when the panel hides.
package struct DockZone: Equatable, Sendable {
    /// The zone is the union of these.
    package private(set) var rects: [DockRect] = []

    package init() {}

    package var isEmpty: Bool { rects.isEmpty }

    package func contains(_ p: DockPoint) -> Bool {
        rects.contains { $0.contains(p) }
    }

    /// One read: the Dock's frame (the union of its item frames, §R4 S0-1) and the hovered item's live frame, which
    /// grows by `DockGeometry.zoneGrowth` on every side to cover magnification. A frame that can't be read (nil or
    /// degenerate) adds nothing, so the last known zone stands.
    package func adding(dock: DockRect?, hoveredItem: DockRect?) -> DockZone {
        var zone = self
        for r in [dock, hoveredItem.map { $0.outset(by: DockGeometry.zoneGrowth) }] {
            guard let r, !r.isDegenerate, !zone.rects.contains(where: { $0.contains(r) }) else { continue }
            zone.rects.removeAll { r.contains($0) }
            zone.rects.append(r)
        }
        if zone.rects.count > DockGeometry.zoneRectCap, let first = zone.rects.first {
            // Folding into the bounding box keeps every point the zone held.
            zone.rects = [zone.rects.dropFirst().reduce(first) { $0.union($1) }]
        }
        return zone
    }
}

/// A convex polygon, counter-clockwise (§4.2's corridor).
package struct DockHull: Equatable, Sendable {
    package let points: [DockPoint]

    /// The convex hull of `points` (monotone chain): counter-clockwise from the lowest-x point, with no repeated or
    /// collinear points.
    package init(of points: [DockPoint]) {
        let sorted = Array(Set(points.filter { $0.x.isFinite && $0.y.isFinite }))
            .sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count > 2 else {
            self.points = sorted
            return
        }
        var lower: [DockPoint] = []
        for p in sorted {
            while lower.count >= 2 && Self.cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [DockPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && Self.cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        self.points = Array(lower.dropLast() + upper.dropLast())
    }

    /// Inside or on the boundary. A hull with no area holds nothing.
    package func contains(_ p: DockPoint) -> Bool {
        guard points.count > 2 else { return false }
        for i in points.indices where Self.cross(points[i], points[(i + 1) % points.count], p) < -1e-9 {
            return false
        }
        return true
    }

    /// > 0 when `o → a → b` turns left.
    private static func cross(_ o: DockPoint, _ a: DockPoint, _ b: DockPoint) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
}

/// One cell of the panel's grid (§4.3).
package enum DockCell: Equatable, Sendable {
    /// The window at this index of the panel's window list.
    case window(Int)
    /// “More windows…” (§4.8, X3-12): always the last cell, inside the scroll range.
    case moreWindows
}

package enum DockScrollAxis: String, Equatable, Sendable {
    /// A bottom Dock's panel.
    case horizontal
    /// A side Dock's panel.
    case vertical
}

/// The panel's chrome around the cards. The plan names no values; these are K2's.
package struct DockPanelMetrics: Equatable, Sendable {
    /// Around the scroll view, inside the panel.
    package var padding: Double
    /// Between cards.
    package var spacing: Double
    /// The header strip (§4.4), at the panel's top.
    package var headerHeight: Double

    package init(padding: Double, spacing: Double, headerHeight: Double) {
        self.padding = padding
        self.spacing = spacing
        self.headerHeight = headerHeight
    }

    package static let standard = DockPanelMetrics(padding: 12, spacing: 12, headerHeight: 32)
}

/// The panel's card grid (§4.3). Cell frames are in content coordinates (origin at the content's bottom-left, y up;
/// the first row is the top one); the header and viewport frames are in panel coordinates. A scroll offset is the
/// distance from the start of the scroll axis: the left end (the right end in RTL) for a bottom Dock, the top for a
/// side Dock.
package struct DockPanelLayout: Equatable, Sendable {
    /// The size the cards use, after any drop.
    package var cardSize: DockCardSize
    package var card: DockSize
    package var columns: Int
    package var rows: Int
    package var cells: [DockCell]
    /// One per cell.
    package var frames: [DockRect]
    package var content: DockSize
    /// The scroll view: the part of the content in view.
    package var viewport: DockSize
    /// Nil when every card fits.
    package var scrollAxis: DockScrollAxis?
    package var panel: DockSize
    package var header: DockRect
    package var viewportFrame: DockRect
    package var rightToLeft: Bool

    package var maxScrollOffset: Double {
        switch scrollAxis {
        case .horizontal: max(0, content.width - viewport.width)
        case .vertical: max(0, content.height - viewport.height)
        case nil: 0
        }
    }

    /// The part of the content in view at `offset` (clamped to the scroll range).
    package func visibleContent(at offset: Double) -> DockRect {
        let o = min(max(offset.isFinite ? offset : 0, 0), maxScrollOffset)
        switch scrollAxis {
        case .horizontal:
            let x = rightToLeft ? content.width - viewport.width - o : o
            return DockRect(x: x, y: 0, width: viewport.width, height: viewport.height)
        case .vertical:
            return DockRect(x: 0, y: content.height - viewport.height - o, width: viewport.width,
                            height: viewport.height)
        case nil:
            return DockRect(x: 0, y: 0, width: content.width, height: content.height)
        }
    }

    /// The least offset that brings cell `index` wholly into view; nil past the cells.
    package func offset(revealing index: Int) -> Double? {
        guard frames.indices.contains(index) else { return nil }
        let f = frames[index]
        let farEnd: Double, along: Double
        switch scrollAxis {
        case .horizontal:
            farEnd = rightToLeft ? content.width - f.minX : f.maxX
            along = viewport.width
        case .vertical:
            farEnd = content.height - f.minY
            along = viewport.height
        case nil:
            return 0
        }
        return min(max(0, farEnd - along), maxScrollOffset)
    }

    /// §4.3: the windows to request thumbnails for at `offset`: the cards in view, plus one beyond each edge.
    package func thumbnailWindows(at offset: Double) -> [Int] {
        let view = visibleContent(at: offset)
        let shown = frames.indices.filter { frames[$0].intersects(view) }
        guard let first = shown.first, let last = shown.last else { return [] }
        return (max(0, first - 1)...min(cells.count - 1, last + 1)).compactMap {
            if case .window(let w) = cells[$0] { return w }
            return nil
        }
    }
}

package enum DockGeometry {
    /// §4.1: the hovered item's live frame grows by this on every side in the Dock zone; the hit band reaches this far
    /// past the item's far side, and this far along the Dock past an end item.
    package static let zoneGrowth = 24.0
    /// §4.7: the panel's gap off the Dock's at-rest thickness.
    package static let panelGap = 6.0
    /// §4.7: the panel's margin from the screen's visible edges.
    package static let screenMargin = 8.0
    /// §4.3 (Y-12): every card is a fixed 16:10 frame.
    package static let cardAspect = 16.0 / 10.0
    /// §4.1: past this many rectangles the Dock zone folds into their bounding box.
    package static let zoneRectCap = 32
    /// §4.3: a side Dock's panel has two columns.
    package static let sideColumns = 2

    // MARK: Coordinates (X-27)

    /// An AX (or `CGWindowList`) frame, top-left origin and y down from the primary display, in AppKit global
    /// coordinates: the `Screens.cocoaRect` rule, y = primary height − y − height. It's its own inverse.
    package static func cocoaRect(fromAX r: DockRect, primaryHeight: Double) -> DockRect {
        DockRect(x: r.x, y: primaryHeight - r.y - r.height, width: r.width, height: r.height)
    }

    package static func axRect(fromCocoa r: DockRect, primaryHeight: Double) -> DockRect {
        cocoaRect(fromAX: r, primaryHeight: primaryHeight)
    }

    /// A point (a `CGEvent` location) in AppKit global coordinates: y = primary height − y.
    package static func cocoaPoint(fromAX p: DockPoint, primaryHeight: Double) -> DockPoint {
        DockPoint(x: p.x, y: primaryHeight - p.y)
    }

    package static func axPoint(fromCocoa p: DockPoint, primaryHeight: Double) -> DockPoint {
        cocoaPoint(fromAX: p, primaryHeight: primaryHeight)
    }

    /// The primary display's height, which AX coordinates hang from; the first screen's when none says it's primary.
    package static func primaryHeight(_ screens: [DockScreen]) -> Double? {
        (screens.first(where: \.isPrimary) ?? screens.first)?.frame.height
    }

    // MARK: Screens and the Dock's edge

    package static func screen(holding p: DockPoint, in screens: [DockScreen]) -> DockScreen? {
        screens.first { $0.frame.contains(p) }
    }

    /// The screen holding the rectangle's centre, else the one sharing the most area with it, else nil.
    package static func screen(holding r: DockRect, in screens: [DockScreen]) -> DockScreen? {
        if let s = screen(holding: r.mid, in: screens) { return s }
        let best = screens.max { $0.frame.overlapArea(r) < $1.frame.overlapArea(r) }
        return best.flatMap { $0.frame.overlapArea(r) > 0 ? $0 : nil }
    }

    /// §4.7: a frame settles on two equal reads, one or two display frames apart.
    package static func isSettled(previous: DockRect?, current: DockRect) -> Bool {
        guard let previous, !current.isDegenerate else { return false }
        return previous == current
    }

    /// The Dock's frame: the union of its item frames, which reach 5 pt past the `AXList` frame (§R4 S0-1).
    /// Degenerate frames are skipped; nil when none is left.
    package static func dockFrame(items: [DockRect]) -> DockRect? {
        let usable = items.filter { !$0.isDegenerate }
        guard let first = usable.first else { return nil }
        return usable.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The Dock's edge from a settled item frame: the edge of `screen` it's nearest, bottom first on a tie. When the
    /// Dock's frame is known and longer one way, that decides bottom or side, so a side Dock's end item near the
    /// bottom corner still reads as a side.
    package static func edge(ofItem item: DockRect, dock: DockRect? = nil, on screen: DockScreen) -> DockEdge {
        let f = screen.frame
        let bottom = item.minY - f.minY, left = item.minX - f.minX, right = f.maxX - item.maxX
        if let dock, !dock.isDegenerate, dock.width != dock.height {
            if dock.width > dock.height { return .bottom }
            return left <= right ? .left : .right
        }
        if bottom <= left && bottom <= right { return .bottom }
        return left <= right ? .left : .right
    }

    /// §4.7: the Dock's at-rest thickness, from its screen edge to the items' far side. Magnification only grows
    /// items away from the edge, so the least far side among them is the resting one.
    package static func restingThickness(items: [DockRect], edge: DockEdge, screen: DockScreen) -> Double? {
        let f = screen.frame
        let sides: [Double] = items.filter { !$0.isDegenerate }.map {
            switch edge {
            case .bottom: $0.maxY - f.minY
            case .left: $0.maxX - f.minX
            case .right: f.maxX - $0.minX
            }
        }
        return sides.min().map { max(0, $0) }
    }

    // MARK: Hover (§4.1, §4.2)

    /// §4.1 rule 5 (X2-10): the item's frame grown along the Dock by half the gap to each neighbour (by `zoneGrowth`
    /// past an end item), and stretched across the Dock from the screen edge to `zoneGrowth` past the item's far
    /// side, so a pointer just outside the resting frame, or over a magnified icon before its frame grows, is on it.
    /// `items` is every item frame; the item itself and degenerate frames are skipped.
    package static func hitBand(item: DockRect, items: [DockRect], edge: DockEdge, screen: DockScreen) -> DockRect {
        let horizontal = edge.isHorizontal
        func lo(_ r: DockRect) -> Double { horizontal ? r.minX : r.minY }
        func hi(_ r: DockRect) -> Double { horizontal ? r.maxX : r.maxY }
        let mid = (lo(item) + hi(item)) / 2
        let others = items.filter { !$0.isDegenerate && $0 != item }
        let before = others.filter { (lo($0) + hi($0)) / 2 < mid }.map(hi).max()
        let after = others.filter { (lo($0) + hi($0)) / 2 > mid }.map(lo).min()
        let start = before.map { lo(item) - max(0, lo(item) - $0) / 2 } ?? lo(item) - zoneGrowth
        let end = after.map { hi(item) + max(0, $0 - hi(item)) / 2 } ?? hi(item) + zoneGrowth
        let f = screen.frame
        switch edge {
        case .bottom:
            return DockRect(x: start, y: f.minY, width: end - start, height: item.maxY + zoneGrowth - f.minY)
        case .left:
            return DockRect(x: f.minX, y: start, width: item.maxX + zoneGrowth - f.minX, height: end - start)
        case .right:
            let x = item.minX - zoneGrowth
            return DockRect(x: x, y: start, width: f.maxX - x, height: end - start)
        }
    }

    /// §4.1 rule 5: a selection change shows or swaps only with the pointer in the Dock zone and the item's hit band.
    package static func pointerAgrees(_ p: DockPoint, zone: DockZone, band: DockRect) -> Bool {
        zone.contains(p) && band.contains(p)
    }

    /// §4.2: the corridor, the convex hull of the item frame and the panel's near edge (the one facing the Dock).
    package static func corridor(item: DockRect, panel: DockRect, edge: DockEdge) -> DockHull {
        let near: [DockPoint]
        switch edge {
        case .bottom: near = [DockPoint(x: panel.minX, y: panel.minY), DockPoint(x: panel.maxX, y: panel.minY)]
        case .left: near = [DockPoint(x: panel.minX, y: panel.minY), DockPoint(x: panel.minX, y: panel.maxY)]
        case .right: near = [DockPoint(x: panel.maxX, y: panel.minY), DockPoint(x: panel.maxX, y: panel.maxY)]
        }
        let corners = [DockPoint(x: item.minX, y: item.minY), DockPoint(x: item.maxX, y: item.minY),
                       DockPoint(x: item.minX, y: item.maxY), DockPoint(x: item.maxX, y: item.maxY)]
        return DockHull(of: corners + near)
    }

    // MARK: Placement (§4.7)

    /// Where the panel may sit: from `panelGap` past the Dock's at-rest thickness (and never outside the visible
    /// frame) to `screenMargin` inside the visible frame's other edges. Nil when that leaves no room.
    package static func panelArea(restingThickness: Double, edge: DockEdge, screen: DockScreen) -> DockRect? {
        let f = screen.frame, v = screen.visibleFrame.outset(by: -screenMargin)
        let r: DockRect
        switch edge {
        case .bottom:
            let near = max(f.minY + restingThickness + panelGap, screen.visibleFrame.minY)
            r = DockRect(x: v.minX, y: near, width: v.width, height: v.maxY - near)
        case .left:
            let near = max(f.minX + restingThickness + panelGap, screen.visibleFrame.minX)
            r = DockRect(x: near, y: v.minY, width: v.maxX - near, height: v.height)
        case .right:
            let near = min(f.maxX - restingThickness - panelGap, screen.visibleFrame.maxX)
            r = DockRect(x: v.minX, y: v.minY, width: near - v.minX, height: v.height)
        }
        return r.isDegenerate ? nil : r
    }

    /// §4.7: the panel against the Dock in `panelArea`, centred on the item along the Dock and clamped into the area.
    /// The across position comes from the at-rest thickness, never the item's live frame, so a magnified item doesn't
    /// move the panel. Nil when the panel doesn't fit the area.
    package static func placement(panel: DockSize, item: DockRect, restingThickness: Double, edge: DockEdge,
                                  screen: DockScreen) -> DockRect? {
        let tolerance = 1e-9
        guard let area = panelArea(restingThickness: restingThickness, edge: edge, screen: screen),
              panel.width > 0, panel.height > 0,
              panel.width <= area.width + tolerance, panel.height <= area.height + tolerance else { return nil }
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), max(lo, hi)) }
        switch edge {
        case .bottom:
            let x = clamp(item.midX - panel.width / 2, area.minX, area.maxX - panel.width)
            return DockRect(x: x, y: area.minY, width: panel.width, height: panel.height)
        case .left, .right:
            let y = clamp(item.midY - panel.height / 2, area.minY, area.maxY - panel.height)
            let x = edge == .left ? area.minX : area.maxX - panel.width
            return DockRect(x: x, y: y, width: panel.width, height: panel.height)
        }
    }

    /// §4.7 (X-27, X2-20): the capture scale comes from the screen that holds the window. A window no screen holds
    /// (minimized, passed as nil, or on a Space of a display that's gone) takes the largest scale among the screens;
    /// 1 with no screens.
    package static func captureScale(window: DockRect?, screens: [DockScreen]) -> Double {
        if let window, let s = screen(holding: window, in: screens) { return s.scale }
        return screens.map(\.scale).max() ?? 1
    }

    // MARK: Cards (§4.3)

    package static func cardWidth(_ size: DockCardSize) -> Double {
        switch size {
        case .small: 200
        case .medium: 280
        case .large: 360
        }
    }

    /// A fixed 16:10 frame.
    package static func card(_ size: DockCardSize) -> DockSize {
        let w = cardWidth(size)
        return DockSize(width: w, height: w / cardAspect)
    }

    /// One size down (Large → Medium → Small); Small stays.
    package static func smaller(_ size: DockCardSize) -> DockCardSize {
        switch size {
        case .large: .medium
        case .medium, .small: .small
        }
    }

    /// §4.3 (Y-12, PC-2): the thumbnail letterboxed in the card, at the captured image's aspect ratio, as large as
    /// fits and centred. Nil for an image or card with no area.
    package static func letterbox(image: DockSize, in card: DockRect) -> DockRect? {
        guard image.width > 0, image.height > 0, image.width.isFinite, image.height.isFinite,
              !card.isDegenerate else { return nil }
        let scale = min(card.width / image.width, card.height / image.height)
        let w = image.width * scale, h = image.height * scale
        return DockRect(x: card.midX - w / 2, y: card.midY - h / 2, width: w, height: h)
    }

    /// §4.3: the card grid for `windows` windows (plus “More windows…” as the last cell) in `area`, the room
    /// `panelArea` leaves. A bottom Dock gets one row; a side Dock two columns. When the cards don't fit they drop one
    /// size (G-12); if they still don't, the panel scrolls (horizontally for a bottom Dock, vertically for a side
    /// Dock) and every cell stays in the scroll range. There's no “+N more”. RTL mirrors the order across the panel.
    /// Nil with no cells, or when not even one card fits in view.
    package static func layout(windows: Int, moreWindows: Bool, preferred: DockCardSize, edge: DockEdge,
                               area: DockSize, rightToLeft: Bool,
                               metrics: DockPanelMetrics = .standard) -> DockPanelLayout? {
        let cells = (0..<max(0, windows)).map(DockCell.window) + (moreWindows ? [.moreWindows] : [])
        let n = cells.count
        guard n > 0 else { return nil }
        let columns = edge.isHorizontal ? n : min(sideColumns, n)
        let rows = (n + columns - 1) / columns
        let room = DockSize(width: area.width - 2 * metrics.padding,
                            height: area.height - 2 * metrics.padding - metrics.headerHeight)
        func extent(_ count: Int, _ length: Double) -> Double {
            Double(count) * length + Double(count - 1) * metrics.spacing
        }
        func content(_ size: DockCardSize) -> DockSize {
            let c = card(size)
            return DockSize(width: extent(columns, c.width), height: extent(rows, c.height))
        }
        func fits(_ s: DockSize) -> Bool { s.width <= room.width && s.height <= room.height }

        let size = fits(content(preferred)) ? preferred : smaller(preferred)
        let c = card(size), full = content(size)
        var viewport = full
        var axis: DockScrollAxis?
        if !fits(full) {
            axis = edge.isHorizontal ? .horizontal : .vertical
            if edge.isHorizontal {
                guard full.height <= room.height, room.width >= c.width else { return nil }
                viewport.width = room.width
            } else {
                guard full.width <= room.width, room.height >= c.height else { return nil }
                viewport.height = room.height
            }
        }
        let frames = cells.indices.map { i -> DockRect in
            let col = i % columns, row = i / columns
            let x = Double(col) * (c.width + metrics.spacing)
            let top = full.height - Double(row) * (c.height + metrics.spacing)
            return DockRect(x: rightToLeft ? full.width - x - c.width : x, y: top - c.height, width: c.width,
                            height: c.height)
        }
        let panel = DockSize(width: viewport.width + 2 * metrics.padding,
                             height: viewport.height + 2 * metrics.padding + metrics.headerHeight)
        return DockPanelLayout(
            cardSize: size, card: c, columns: columns, rows: rows, cells: cells, frames: frames, content: full,
            viewport: viewport, scrollAxis: axis, panel: panel,
            header: DockRect(x: 0, y: panel.height - metrics.headerHeight, width: panel.width,
                             height: metrics.headerHeight),
            viewportFrame: DockRect(x: metrics.padding, y: metrics.padding, width: viewport.width,
                                    height: viewport.height),
            rightToLeft: rightToLeft)
    }
}
