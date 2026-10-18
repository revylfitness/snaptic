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

    func testQuickAndToolsConnectAllAreSeparateItems() {
        let ids = DisplayMenuItemID.managementItems
        XCTAssertTrue(ids.contains(.dConnectAll))
        XCTAssertTrue(ids.contains(.dConnectAllQuick))
        XCTAssertNotEqual(DisplayMenuItemID.dConnectAll, .dConnectAllQuick)
        XCTAssertEqual(DisplayMenuItemID.dConnectAllQuick.rawValue, "d.connectAll.quick")
        XCTAssertTrue(ids.contains(.dArrange))
        XCTAssertTrue(ids.contains(.dUnderscanMenu))
    }

    func testUnderscanSteps() {
        XCTAssertEqual(UnderscanSteps.values.first, 0)
        XCTAssertEqual(UnderscanSteps.values.last, 1)
        XCTAssertEqual(UnderscanSteps.values, UnderscanSteps.values.sorted())
        XCTAssertNil(UnderscanSteps.nearest(nil))
        XCTAssertNil(UnderscanSteps.nearest(.nan))
        XCTAssertNil(UnderscanSteps.nearest(.infinity))
        XCTAssertEqual(UnderscanSteps.nearest(0), 0)
        XCTAssertEqual(UnderscanSteps.nearest(0.1), 0)
        XCTAssertEqual(UnderscanSteps.nearest(0.13), 0.25)
        XCTAssertEqual(UnderscanSteps.nearest(0.125), 0, "ties go to the smaller step")
        XCTAssertEqual(UnderscanSteps.nearest(0.9), 1)
        XCTAssertEqual(UnderscanSteps.nearest(-3), 0)
        XCTAssertEqual(UnderscanSteps.nearest(7), 1)
        XCTAssertEqual(UnderscanSteps.title(0), L("Off"))
        XCTAssertEqual(UnderscanSteps.title(0.5), "50%")
    }
}
