import XCTest
@testable import SnapticKit

final class AffectedModelsTests: XCTestCase {
    private func host(_ chip: String, _ major: Int, _ minor: Int, model: String = "Mac17,1") -> HostDescription {
        HostDescription(modelIdentifier: model, chipName: chip, osMajor: major, osMinor: minor)
    }

    func testM5ProAndMaxAreAffectedFrom263WithNoUpperBound() {
        XCTAssertTrue(AffectedModels.gammaIsUnreliable(host("Apple M5 Pro", 26, 3)))
        XCTAssertTrue(AffectedModels.gammaIsUnreliable(host("Apple M5 Max", 26, 4)))
        XCTAssertTrue(AffectedModels.gammaIsUnreliable(host("Apple M5 Max", 27, 0)))
        XCTAssertTrue(AffectedModels.gammaIsUnreliable(host("Apple M5 Max", 30, 0)), "no upper bound")
        XCTAssertFalse(AffectedModels.gammaIsUnreliable(host("Apple M5 Max", 26, 2)))
        XCTAssertFalse(AffectedModels.gammaIsUnreliable(host("Apple M5 Max", 15, 9)))
    }

    func testOtherChipsAreNotAffected() {
        XCTAssertFalse(AffectedModels.gammaIsUnreliable(host("Apple M5", 27, 0)), "base M5 is not on the list")
        XCTAssertFalse(AffectedModels.gammaIsUnreliable(host("Apple M4 Max", 27, 0)))
        XCTAssertFalse(AffectedModels.gammaIsUnreliable(host("Intel(R) Core(TM) i9", 27, 0)))
        XCTAssertFalse(AffectedModels.gammaIsUnreliable(host("", 27, 0)))
    }

    func testMatchingIsCaseInsensitiveOnChip() {
        XCTAssertTrue(AffectedModels.gammaIsUnreliable(host("apple m5 pro", 26, 3)))
    }

    func testIssuesAndReasons() {
        XCTAssertEqual(AffectedModels.issues(for: host("Apple M5 Pro", 27, 1)), [.gammaNoOp])
        XCTAssertTrue(AffectedModels.issues(for: host("Apple M1", 27, 1)).isEmpty)
        for issue in AffectedModels.Issue.allCases { XCTAssertFalse(AffectedModels.reason(issue).isEmpty) }
        XCTAssertTrue(host("Apple M1", 14, 0).isAppleSilicon)
        XCTAssertFalse(host("Intel", 14, 0).isAppleSilicon)
    }

    func testEveryEntryNamesAChipOrModel() {
        for entry in AffectedModels.entries { XCTAssertTrue(entry.chipPrefix != nil || entry.modelPrefix != nil) }
    }

    func testXDRNeedsAppleSiliconFromStaticFactsOnly() {
        XCTAssertNil(AffectedModels.xdrUnavailableReason(host("Apple M1 Pro", 14, 0, model: "MacBookPro18,3")))
        XCTAssertNil(AffectedModels.xdrUnavailableReason(host("Apple M5 Max", 27, 0)))
        XCTAssertNil(AffectedModels.xdrUnavailableReason(host("Apple M2", 15, 0, model: "Mac14,2")), "Air + external HDR")
        XCTAssertNotNil(AffectedModels.xdrUnavailableReason(host("Intel(R) Core(TM) i9-9980HK", 15, 0, model: "MacBookPro16,1")))
        XCTAssertNotNil(AffectedModels.xdrUnavailableReason(host("", 14, 0, model: "MacPro7,1")))
        XCTAssertNil(AffectedModels.xdrUnavailableReason(host("", 14, 0, model: "Mac15,7")), "empty brand string, Apple model id")
        XCTAssertNotNil(AffectedModels.xdrUnavailableReason(host("", 14, 0, model: "")))
    }

    func testAppleSiliconOnlyModelIds() {
        XCTAssertTrue(AffectedModels.isAppleSiliconOnlyModel("Mac13,1"))
        XCTAssertTrue(AffectedModels.isAppleSiliconOnlyModel("Mac17,2"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel("Mac12,1"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel("MacBookPro16,1"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel("MacPro7,1"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel("Mac14"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel("Mac14,"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel("Macmini9,1"))
        XCTAssertFalse(AffectedModels.isAppleSiliconOnlyModel(""))
    }
}
