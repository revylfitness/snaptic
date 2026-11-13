import Foundation

// Dock Previews' shared Kit types (lead; PLAN 0.5 §2.1, H6). K1 adds the kill-switch features; K4 adds `DockRect` for
// `CatalogWindow.bounds`; the hover, click and key rules arrive in K3 as their own files.

/// Per-feature kill switches (H6): `Dock.disable.<rawValue>` = true in Snaptic's persistent domain turns the feature
/// off, read with `KillSwitches.read(domain, prefix: "Dock", as: DockFeature.self)` once per batch (no polling).
/// `Modules.disable.dockPreviews` turns off the whole module.
package enum DockFeature: String, Codable, CaseIterable, Sendable {
    /// The opt-in Dock click actions (§4.11); also read on each mouse-up the resolver would act on (D2-15).
    case clickActions
    /// Keyboard shortcuts in previews (§4.5).
    case keys
}

/// A rectangle in Cocoa's global space (bottom-left origin on the primary screen), in points (§2.1).
package struct DockRect: Equatable, Sendable {
    package var x: Double
    package var y: Double
    package var w: Double
    package var h: Double

    package init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    package static let zero = DockRect(x: 0, y: 0, w: 0, h: 0)

    package var midX: Double { x + w / 2 }
    package var midY: Double { y + h / 2 }

    /// Like `CGRect.contains(_: CGPoint)`: the minimum edges are inside, the maximum edges are not, and an empty
    /// rectangle contains nothing.
    package func contains(x px: Double, y py: Double) -> Bool {
        let minX = min(x, x + w), maxX = max(x, x + w)
        let minY = min(y, y + h), maxY = max(y, y + h)
        return px >= minX && px < maxX && py >= minY && py < maxY
    }
}
