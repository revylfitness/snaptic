import Foundation

// Dock Previews' shared Kit types (lead; PLAN 0.5 §2.1, H6). K1 adds the kill-switch features; K4 and K2 add the
// geometry value types (`DockRect`, also `CatalogWindow.bounds`; `DockPoint`, `DockScreen`, `DockEdge`); K3 adds the
// selection the hover, click and key rules take. Kit never sees an AXUIElement, an NSPanel or a clock: the app
// converts what it reads into these and passes `now` in.

/// Per-feature kill switches (H6): `Dock.disable.<rawValue>` = true in Snaptic's persistent domain turns the feature
/// off, read with `KillSwitches.read(domain, prefix: "Dock", as: DockFeature.self)` once per batch (no polling).
/// `Modules.disable.dockPreviews` turns off the whole module.
package enum DockFeature: String, Codable, CaseIterable, Sendable {
    /// The opt-in Dock click actions (§4.11); also read on each mouse-up the resolver would act on (D2-15).
    case clickActions
    /// Keyboard shortcuts in previews (§4.5).
    case keys
}

/// A point in AppKit global coordinates: origin at the primary display's bottom-left corner, y up (§2.1).
package struct DockPoint: Codable, Equatable, Hashable, Sendable {
    package var x: Double
    package var y: Double

    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    package func distance(to other: DockPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// A rectangle in AppKit global coordinates: origin at the primary display's bottom-left corner, y up (§2.1). AX and
/// `CGWindowList` frames are top-left and y-down; `DockGeometry` converts them (X-27).
package struct DockRect: Codable, Equatable, Hashable, Sendable {
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double

    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package static let zero = DockRect(x: 0, y: 0, width: 0, height: 0)

    package var minX: Double { x }
    package var maxX: Double { x + width }
    package var midX: Double { x + width / 2 }
    package var minY: Double { y }
    package var maxY: Double { y + height }
    package var midY: Double { y + height / 2 }
    package var mid: DockPoint { DockPoint(x: midX, y: midY) }

    /// Not finite, or with no area: AX hands these back for items that are mid-animation or gone.
    package var isDegenerate: Bool {
        !(x.isFinite && y.isFinite && width.isFinite && height.isFinite) || width <= 0 || height <= 0
    }

    /// Edges included, so a pointer on the screen's last row or column still counts.
    package func contains(_ p: DockPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    /// Like `CGRect.contains(_: CGPoint)`: the minimum edges are inside, the maximum edges are not, a negative size
    /// is standardized, and an empty rectangle contains nothing. The catalog's screen scope uses this (K4).
    package func contains(x px: Double, y py: Double) -> Bool {
        let x0 = min(x, x + width), x1 = max(x, x + width)
        let y0 = min(y, y + height), y1 = max(y, y + height)
        return px >= x0 && px < x1 && py >= y0 && py < y1
    }

    package func contains(_ r: DockRect) -> Bool {
        r.minX >= minX && r.maxX <= maxX && r.minY >= minY && r.maxY <= maxY
    }

    /// A shared area (touching edges don't count).
    package func intersects(_ r: DockRect) -> Bool {
        r.minX < maxX && r.maxX > minX && r.minY < maxY && r.maxY > minY
    }

    /// The shared area, or 0.
    package func overlapArea(_ r: DockRect) -> Double {
        max(0, min(maxX, r.maxX) - max(minX, r.minX)) * max(0, min(maxY, r.maxY) - max(minY, r.minY))
    }

    /// The smallest rectangle holding both.
    package func union(_ r: DockRect) -> DockRect {
        let x0 = min(minX, r.minX), y0 = min(minY, r.minY)
        return DockRect(x: x0, y: y0, width: max(maxX, r.maxX) - x0, height: max(maxY, r.maxY) - y0)
    }

    /// Grown by `d` on every side (negative shrinks).
    package func outset(by d: Double) -> DockRect {
        DockRect(x: x - d, y: y - d, width: width + 2 * d, height: height + 2 * d)
    }
}

/// One display, in AppKit global coordinates (`NSScreen.frame`, `visibleFrame`, `backingScaleFactor`).
package struct DockScreen: Codable, Hashable, Sendable {
    /// The `CGDirectDisplayID`.
    package var id: UInt32
    package var frame: DockRect
    /// The frame less the menu bar and a Dock that doesn't hide.
    package var visibleFrame: DockRect
    package var scale: Double
    /// The display whose frame has its origin at (0, 0): the one AX and `CGWindowList` coordinates hang from.
    package var isPrimary: Bool

    package init(id: UInt32, frame: DockRect, visibleFrame: DockRect, scale: Double, isPrimary: Bool) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.isPrimary = isPrimary
    }
}

/// The screen edge the Dock sits on. macOS has no top Dock.
package enum DockEdge: String, Codable, CaseIterable, Sendable {
    case bottom, left, right

    /// Bottom: the Dock runs along x. Left and right: along y.
    package var isHorizontal: Bool { self == .bottom }
}

/// What a Dock item is (§4.1 rule 3; §4.8).
package enum DockItemKind: String, CaseIterable, Sendable {
    case app
    case folder
    case trash
    case minimizedWindow
    case separator
    case other
}

/// The Dock's selection, as `DockObserver` reads it (§2.1, §4.1).
package struct DockSelection: Hashable, Sendable {
    package var kind: DockItemKind
    /// The running app's pid; nil when the item's app isn't running (S0-1: `AXIsApplicationRunning` = 1 only).
    package var pid: Int32?
    /// The item's live frame (magnified while the Dock magnifies).
    package var itemFrame: DockRect
    /// The Dock's frame. S0-1 (§R4): the hit area is the union of item frames, which the app passes here.
    package var listFrame: DockRect
    /// False when the VoiceOver cursor moved the selection and VoiceOver previews are on (§4.1 rule 5, G2-5).
    package var byPointer: Bool

    package init(kind: DockItemKind, pid: Int32?, itemFrame: DockRect, listFrame: DockRect, byPointer: Bool = true) {
        self.kind = kind
        self.pid = pid
        self.itemFrame = itemFrame
        self.listFrame = listFrame
        self.byPointer = byPointer
    }

    /// A running app's item: the only kind that shows a panel (§4.1 rules 1 and 3).
    package var showsPanel: Bool { kind == .app && pid != nil }

    /// The same Dock item: the same app, or for other kinds the same frame centre (a magnified frame keeps its
    /// centre along the Dock).
    package func sameItem(as other: DockSelection) -> Bool {
        guard kind == other.kind else { return false }
        if let pid, let otherPID = other.pid { return pid == otherPID }
        if pid != nil || other.pid != nil { return false }
        return itemFrame.midX == other.itemFrame.midX && itemFrame.midY == other.itemFrame.midY
    }
}
