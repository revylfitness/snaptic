import XCTest
@testable import SnapticKit

/// 0.5 §4.15: the fixed table of other Dock preview tools (ids from S0-15).
final class KnownDockToolsTests: XCTestCase {
    func testTheTable() {
        XCTAssertEqual(KnownDockTools.all.map(\.name), ["DockDoor", "DockDoor Pro", "HyperDock", "Dock Mate", "DockView 2"])
        XCTAssertEqual(KnownDockTools.all.map(\.bundleID),
                       ["com.ethanbills.DockDoor", "com.ejbills.DockDoorPro", "de.bahoom.HyperDock",
                        "com.macenhance.dockmate", "com.macplus-software.com.DockView-2"])
        for tool in KnownDockTools.all {
            XCTAssertTrue(AwakeBundleID.isValid(tool.bundleID), tool.name)
            XCTAssertFalse(tool.name.isEmpty)
        }
    }

    func testIDsAndNamesAreUnique() {
        let ids = KnownDockTools.all.map(\.bundleID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids.map { $0.lowercased() }).count, ids.count, "no two ids differ only in case")
        let names = KnownDockTools.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testEveryListedIDMatchesItself() {
        for tool in KnownDockTools.all { XCTAssertEqual(KnownDockTools.match(bundleID: tool.bundleID), tool) }
    }

    func testExactMatchOnly() {
        XCTAssertNil(KnownDockTools.match(bundleID: "com.ethanbills.DockDoor.helper"), "no prefix match")
        XCTAssertNil(KnownDockTools.match(bundleID: "com.ethanbills"), "no partial match")
        XCTAssertNil(KnownDockTools.match(bundleID: "com.ethanbills.dockdoor"), "no case folding")
        XCTAssertNil(KnownDockTools.match(bundleID: "COM.BAHOOM.HYPERDOCK"))
        XCTAssertNil(KnownDockTools.match(bundleID: " de.bahoom.HyperDock"))
        XCTAssertNil(KnownDockTools.match(bundleID: nil))
        XCTAssertNil(KnownDockTools.match(bundleID: ""))
    }

    /// Snaptic never pauses for itself: its own id (Resources/Info.plist) isn't in the table.
    func testSnapticsOwnIDIsExcluded() throws {
        let own = "app.snaptic.Snaptic"
        XCTAssertNil(KnownDockTools.match(bundleID: own))
        XCTAssertFalse(KnownDockTools.all.contains { $0.bundleID.lowercased().hasPrefix("app.snaptic") })
        // The id above is the shipped one, when the plist is next to the sources.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")) else {
            throw XCTSkip("Resources/Info.plist isn't next to the sources")
        }
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let shipped = try XCTUnwrap(plist?["CFBundleIdentifier"] as? String)
        XCTAssertEqual(shipped, own)
        XCTAssertNil(KnownDockTools.match(bundleID: shipped))
    }
}
