import XCTest
@testable import SnapticKit

final class ConfigLayoutsTests: XCTestCase {
    func testDefaults() throws {
        let c = LayoutsConfig()
        XCTAssertTrue(c.layouts.isEmpty)
        XCTAssertTrue(c.undoToast)
        XCTAssertEqual(try JSONDecoder().decode(LayoutsConfig.self, from: JSONEncoder().encode(c)), c)
        XCTAssertEqual(try JSONDecoder().decode(LayoutsConfig.self, from: Data("{}".utf8)), c)
    }

    func testAtMost32UniqueLayouts() {
        var c = LayoutsConfig()
        c.layouts = (0..<40).map { SavedLayout(name: "L\($0)") }
        c.layouts.insert(c.layouts[3], at: 0)
        let s = c.sanitized()
        XCTAssertEqual(s.layouts.count, LayoutPresetModel.maxLayouts)
        XCTAssertEqual(Set(s.layouts.map(\.id)).count, s.layouts.count)
        XCTAssertEqual(s.layouts.first?.name, "L3")
        XCTAssertEqual(s.layout(s.layouts[5].id), s.layouts[5])
        XCTAssertEqual(s.sanitized(), s)
    }

    func testLossyDecodeDropsBadLayouts() throws {
        let json = #"{"layouts":[{"name":"no id"},{"id":"00000000-0000-0000-0000-000000000009","name":"ok"}],"undoToast":"no"}"#
        let c = try JSONDecoder().decode(LayoutsConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.layouts.map(\.name), ["ok"])
        XCTAssertTrue(c.undoToast)
    }
}
