import Foundation

/// What a point in the panel is over (§4.5): a window's card, the header strip, or neither (padding, the spacing
/// between cards, or “More windows…”).
package enum DockPanelHit: Equatable, Sendable {
    /// The window at this index of the panel's window list.
    case window(Int)
    case header
    case gap
}

extension DockPanelLayout {
    /// What `p` is over. `p` is in panel coordinates (origin at the panel's bottom-left, y up); `scrollOffset` is the
    /// scroll view's offset as K2 measures it. A point outside the panel is a gap.
    package func hit(_ p: DockPoint, scrollOffset: Double) -> DockPanelHit {
        if header.contains(p) { return .header }
        guard viewportFrame.contains(p) else { return .gap }
        let view = visibleContent(at: scrollOffset)
        let c = DockPoint(x: view.minX + p.x - viewportFrame.minX, y: view.minY + p.y - viewportFrame.minY)
        for (i, frame) in frames.enumerated() where cells.indices.contains(i) && frame.contains(c) {
            if case let .window(w) = cells[i] { return .window(w) }
            return .gap
        }
        return .gap
    }
}

extension DockPanelHit {
    /// §4.5: the key target for this hit. `card(i)` gives the facts for window `i`; nil (a window the panel no longer
    /// lists) is a gap. A nil hit (no panel, or the small card) is `.none`.
    package static func keyTarget(_ hit: DockPanelHit?,
                                  card: (Int) -> (hasAXElement: Bool, minimized: Bool)?) -> DockKeyTarget {
        switch hit {
        case nil: return .none
        case .header?: return .header
        case .gap?: return .gap
        case let .window(i)?:
            guard let facts = card(i) else { return .gap }
            return .card(hasAXElement: facts.hasAXElement, minimized: facts.minimized)
        }
    }
}
