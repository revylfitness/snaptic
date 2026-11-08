import XCTest
@testable import SnapticKit

/// 0.4 A1: the items' look and spoken text (§4.1, §4.13, §4.17) and the `Preferred Position` seeding (§4.1, P-10).
final class IconsItemsPresentationTests: XCTestCase {
    private typealias Look = IconsItemsLook
    private typealias Seed = IconsSeeding

    func testArrowGlyphPointsAtTheHiddenIconsAndMirrors() {
        XCTAssertEqual(Look.arrowSymbol(collapsed: true, rightToLeft: false), "chevron.compact.left")
        XCTAssertEqual(Look.arrowSymbol(collapsed: false, rightToLeft: false), "chevron.compact.right")
        XCTAssertEqual(Look.arrowSymbol(collapsed: true, rightToLeft: true), "chevron.compact.right")
        XCTAssertEqual(Look.arrowSymbol(collapsed: false, rightToLeft: true), "chevron.compact.left")
    }

    func testTitles() {
        XCTAssertNil(Look.title(.toggle))
        XCTAssertEqual(Look.title(.separator), "|")
        XCTAssertEqual(Look.title(.alwaysHidden), "⋮")
        XCTAssertEqual(Look.title(.alwaysHidden)?.unicodeScalars.map(\.value), [0x22EE])
        XCTAssertNotEqual(Look.title(.separator), Look.title(.alwaysHidden))
    }

    /// The §4.13 strings, verbatim.
    func testSpokenText() {
        XCTAssertEqual(Look.accessibilityLabel(.toggle), "Hidden Icons")
        XCTAssertEqual(Look.accessibilityLabel(.separator), "Hidden Icons divider")
        XCTAssertEqual(Look.accessibilityLabel(.alwaysHidden), "Always Hidden divider")
        XCTAssertEqual(Look.help(.toggle), "Click to show or hide icons. Option-click to include Always Hidden.")
        for role in [IconsItemRole.separator, .alwaysHidden] {
            XCTAssertEqual(Look.help(role), "Hold Command and drag icons across this divider to hide or show them.")
        }
        XCTAssertEqual(Set(IconsItemRole.allCases.map(Look.accessibilityLabel)).count, 3)
    }

    func testArrowValue() {
        XCTAssertEqual(Look.arrowValue(collapsed: true, hiddenCount: 7), "Hiding 7 icons")
        XCTAssertEqual(Look.arrowValue(collapsed: true, hiddenCount: 1), "Hiding 1 icon")
        XCTAssertEqual(Look.arrowValue(collapsed: true, hiddenCount: 0), "Hiding 0 icons")
        XCTAssertEqual(Look.arrowValue(collapsed: true, hiddenCount: nil), "Icons are hidden")
        XCTAssertEqual(Look.arrowValue(collapsed: true, hiddenCount: -1), "Icons are hidden")
        for n in [nil, 0, 3] as [Int?] {
            XCTAssertEqual(Look.arrowValue(collapsed: false, hiddenCount: n), "Showing all icons")
        }
    }

    func testFirstRunSeedsLeftOfTheLeftmostSnapticItem() {
        let seeded = Seed.firstRun(snapticPositions: [120, 260, 80], arrow: nil, separator: nil)
        XCTAssertEqual(seeded[.toggle], 260 + Seed.step)
        XCTAssertEqual(seeded[.separator], 260 + 2 * Seed.step)
        XCTAssertNil(seeded[.alwaysHidden])
        // `|` sits further left (a larger distance from the right edge) than the arrow.
        XCTAssertGreaterThan(seeded[.separator]!, seeded[.toggle]!)
        XCTAssertEqual(Seed.key("Snaptic.icons.toggle"), "NSStatusItem Preferred Position Snaptic.icons.toggle")
    }

    func testFirstRunKeepsPlacedItemsAndNeedsAnAnchor() {
        XCTAssertEqual(Seed.firstRun(snapticPositions: [], arrow: nil, separator: nil), [:])
        XCTAssertEqual(Seed.firstRun(snapticPositions: [.nan, -4, .infinity], arrow: nil, separator: nil), [:])
        XCTAssertEqual(Seed.firstRun(snapticPositions: [100], arrow: 400, separator: 500), [:])
        // A placed arrow anchors a missing `|`.
        XCTAssertEqual(Seed.firstRun(snapticPositions: [100], arrow: 400, separator: nil), [.separator: 400 + Seed.step])
        XCTAssertEqual(Seed.firstRun(snapticPositions: [], arrow: 400, separator: nil), [.separator: 400 + Seed.step])
        // A placed `|` with a missing arrow: only the arrow is seeded.
        XCTAssertEqual(Seed.firstRun(snapticPositions: [100], arrow: nil, separator: 500), [.toggle: 100 + Seed.step])
    }

    func testAlwaysHiddenSeedsLeftOfTheDivider() {
        XCTAssertEqual(Seed.alwaysHidden(separator: 300, current: nil), 300 + Seed.step)
        XCTAssertNil(Seed.alwaysHidden(separator: 300, current: 900))
        XCTAssertNil(Seed.alwaysHidden(separator: nil, current: nil))
        XCTAssertNil(Seed.alwaysHidden(separator: .nan, current: nil))
    }

    /// P-10: right of the arrow, so a new Snaptic item starts shown.
    func testOwnItemSeedsRightOfTheArrow() {
        let at = Seed.ownItem(arrow: 300, current: nil)
        XCTAssertEqual(at, 300 - Seed.step)
        XCTAssertLessThan(at!, 300)
        XCTAssertEqual(Seed.ownItem(arrow: 0, current: nil), 0)
        XCTAssertNil(Seed.ownItem(arrow: 300, current: 40))
        XCTAssertNil(Seed.ownItem(arrow: nil, current: nil))
        XCTAssertNil(Seed.ownItem(arrow: -2, current: nil))
    }
}
