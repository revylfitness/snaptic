import XCTest
@testable import SnapticKit

final class BuiltinDisconnectPolicyTests: XCTestCase {
    func testHazardTable() {
        for model in ["Mac15,3", "Mac15,4", "Mac15,5", "Mac15,12", "Mac15,13", "iMac21,1", "iMac20,2", "Mac16,2"] {
            XCTAssertFalse(BuiltinDisconnectPolicy.builtinAvailability(modelIdentifier: model).isAllowed, model)
        }
        for model in ["Mac14,2", "MacBookPro18,3", "Mac15,6", "Mac16,1", "Mac15,7"] {
            XCTAssertTrue(BuiltinDisconnectPolicy.builtinAvailability(modelIdentifier: model).isAllowed, model)
        }
        XCTAssertFalse(BuiltinDisconnectPolicy.builtinAvailability(modelIdentifier: "Mac99,1", modelName: "iMac (24-inch)").isAllowed)
        XCTAssertEqual(BuiltinDisconnectPolicy.builtinAvailability(modelIdentifier: "Mac15,3"),
                       .refused(BuiltinDisconnectPolicy.hazardReason))
    }

    func testAutoDisconnectNeedsAppleSilicon() {
        XCTAssertFalse(BuiltinDisconnectPolicy.autoDisconnectAvailability(modelIdentifier: "MacBookPro16,1", isAppleSilicon: false).isAllowed)
        XCTAssertTrue(BuiltinDisconnectPolicy.autoDisconnectAvailability(modelIdentifier: "Mac14,7", isAppleSilicon: true).isAllowed)
    }

    private func decide(lid: Bool? = true, strong: Bool = true, power: ExternalPowerReading = .on, apple: Bool = false,
                        noDDC: Bool = false, ignored: Bool = false, model: String = "Mac14,7") -> Bool {
        BuiltinDisconnectPolicy.autoDisconnectDecision(modelIdentifier: model, isAppleSilicon: true, lidOpen: lid,
                                                       externalStronglyVisible: strong, externalPower: power,
                                                       externalIsAppleNative: apple, userSaysNoDDC: noDDC,
                                                       builtinIgnored: ignored).isAllowed
    }

    func testAutoDisconnectDecision() {
        XCTAssertTrue(decide())
        XCTAssertFalse(decide(lid: nil))
        XCTAssertFalse(decide(lid: false))
        XCTAssertFalse(decide(strong: false))
        XCTAssertFalse(decide(power: .off))
        XCTAssertFalse(decide(power: .off, noDDC: true))
        XCTAssertFalse(decide(power: .unknown))
        XCTAssertFalse(decide(power: .unknown, noDDC: true))
        XCTAssertFalse(decide(power: .notReadable))
        XCTAssertTrue(decide(power: .notReadable, noDDC: true))
        XCTAssertTrue(decide(power: .notReadable, apple: true))
        XCTAssertFalse(decide(ignored: true))
        XCTAssertFalse(decide(model: "Mac15,12"))
        // Dummy plug: no DDC, not Apple, no override → refused (prevents blackouts).
        XCTAssertFalse(decide(power: .notReadable, apple: false, noDDC: false))
    }
}
