import Foundation

// Hidden Icons' own items, as Kit decides them (lead; PLAN 0.4 §4.1, §4.13, §4.17; A1): the glyphs, titles and
// spoken text of the arrow, `|` and `⋮`, and the first-run `Preferred Position` seeding. `IconsItems` (app) only
// executes these.

package enum IconsItemsLook {
    /// The arrow points at what a click does: collapsed it points toward the hidden icons (left in LTR), expanded
    /// away from them. Mirrored in RTL. A refused or failed collapse keeps the expanded glyph (the caller passes the
    /// state that actually holds).
    package static func arrowSymbol(collapsed: Bool, rightToLeft: Bool) -> String {
        collapsed != rightToLeft ? "chevron.compact.left" : "chevron.compact.right"
    }

    /// `|` and `⋮` are text titles (U+22EE differs from `|` by shape, not by alpha). Nil for the arrow (a glyph).
    package static func title(_ role: IconsItemRole) -> String? {
        switch role {
        case .toggle: nil
        case .separator: "|"
        case .alwaysHidden: "\u{22EE}"
        }
    }

    /// §4.2.4: `⋮` is created at 20 pt; the arrow sizes to its glyph.
    package static let dividerLength = 20.0

    package static func accessibilityLabel(_ role: IconsItemRole) -> String {
        switch role {
        case .toggle: L("Hidden Icons")
        case .separator: L("Hidden Icons divider")
        case .alwaysHidden: L("Always Hidden divider")
        }
    }

    /// Tooltip and VoiceOver hint.
    package static func help(_ role: IconsItemRole) -> String {
        switch role {
        case .toggle: L("Click to show or hide icons. Option-click to include Always Hidden.")
        case .separator, .alwaysHidden: L("Hold Command and drag icons across this divider to hide or show them.")
        }
    }

    /// The arrow's accessibility value. `hiddenCount` is nil when the count is unknown (14–26 without
    /// Accessibility); the status row uses the same collapsed text.
    package static func arrowValue(collapsed: Bool, hiddenCount: Int?) -> String {
        guard collapsed else { return L("Showing all icons") }
        guard let n = hiddenCount, n >= 0 else { return L("Icons are hidden") }
        return n == 1 ? L("Hiding 1 icon") : L("Hiding \(n) icons")
    }
}

/// `NSStatusItem Preferred Position <autosave name>` seeding (§4.1, P-10). Positions are distances from the right
/// edge of the menu bar, so a larger value sits further left (LTR). Only an item that has never been placed (no key
/// yet) is seeded; S0-13 checks the effect on macOS 15.
package enum IconsSeeding {
    package static let keyPrefix = "NSStatusItem Preferred Position "
    /// The gap between seeded neighbours; macOS orders by the value and packs the items itself.
    package static let step = 1.0

    package static func key(_ autosaveName: String) -> String { keyPrefix + autosaveName }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// The arrow and `|` just left of Snaptic's existing items (left of the leftmost one), `|` left of the arrow.
    /// Nothing is seeded without an anchor (the system then puts new items left of everything, which hides nothing),
    /// and an item already placed keeps its place; `|` is seeded only next to a seeded or placed arrow.
    package static func firstRun(snapticPositions: [Double], arrow: Double?, separator: Double?) -> [IconsItemRole: Double] {
        var out: [IconsItemRole: Double] = [:]
        let anchor = snapticPositions.compactMap { usable($0) }.max()
        var arrowAt = usable(arrow)
        if arrow == nil, let anchor {
            arrowAt = anchor + step
            out[.toggle] = arrowAt
        }
        if separator == nil, let arrowAt { out[.separator] = arrowAt + step }
        return out
    }

    /// `⋮` when Always Hidden is first turned on: just left of `|` (an empty Always Hidden section). Nil when it was
    /// placed before or `|` has no position.
    package static func alwaysHidden(separator: Double?, current: Double?) -> Double? {
        guard current == nil, let s = usable(separator) else { return nil }
        return s + step
    }

    /// P-10 (Length only): another Snaptic item created for the first time while Hidden Icons runs lands between the
    /// arrow and the system items, so it starts shown. Nil when it was placed before or the arrow has no position.
    package static func ownItem(arrow: Double?, current: Double?) -> Double? {
        guard current == nil, let a = usable(arrow) else { return nil }
        return max(0, a - step)
    }
}
