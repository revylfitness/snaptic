import XCTest
@testable import SnapticKit

final class ManagementIDsTests: XCTestCase {
    func testActionIDsUniqueAndPrefixed() {
        let ids = DisplayActionID.managementActions
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.rawValue.hasPrefix("d.") })
        XCTAssertEqual(ids.count, 21 + 5 + 9 + 8)
    }

    func testNumberedIDsClamp() {
        XCTAssertEqual(DisplayActionID.dFavorite(0), DisplayActionID.dFavorite(1))
        XCTAssertEqual(DisplayActionID.dFavorite(9).rawValue, "d.favorite5")
        XCTAssertEqual(DisplayActionID.dLayout(12).rawValue, "d.layout9")
        XCTAssertEqual(DisplayActionID.dVirtualToggle(3).rawValue, "d.virtualToggle3")
    }

    func testMenuIDsUnique() {
        let ids = DisplayMenuItemID.managementItems
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.rawValue.hasPrefix("d.") })
    }

    func testExitCodesDistinct() {
        let codes = [ManagementExit.usage, ManagementExit.notFound, ManagementExit.refused, ManagementExit.unavailable]
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertFalse(codes.contains(0))
    }
}
