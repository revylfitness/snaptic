import XCTest
@testable import SnapticKit

final class NitsModelTests: XCTestCase {
    func testDefaultTable() {
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: true, isXDR: true, chipName: "Apple M1 Pro").maximum, 500)
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: true, isXDR: true, chipName: "Apple M3 Max").maximum, 500)
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: true, isXDR: true, chipName: "Apple M4 Pro").maximum, 1000)
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: true, isXDR: true, chipName: "Apple M5").maximum, 1000)
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: true, isXDR: true, chipName: "Apple M4 Pro").peak, 1600)
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: true, isXDR: false, chipName: "Apple M2").maximum, 500)
        XCTAssertEqual(NitsModel.defaultRange(isBuiltin: false, isXDR: false, chipName: "Apple M2").maximum, 300)
        XCTAssertTrue(NitsModel.defaultRange(isBuiltin: false, isXDR: false, chipName: "").isEstimate)
    }

    func testChipGeneration() {
        XCTAssertEqual(NitsModel.chipGeneration("Apple M3 Pro"), 3)
        XCTAssertEqual(NitsModel.chipGeneration("Apple M10"), 10)
        XCTAssertNil(NitsModel.chipGeneration("Intel(R) Core(TM)"))
        XCTAssertNil(NitsModel.chipGeneration("Apple M"))
    }

    func testNitsCurve() {
        let r = NitsRange(minimum: 20, maximum: 300, peak: 600, isEstimate: true)
        XCTAssertEqual(NitsModel.nits(hardware: 1, software: 1, xdr: 1, range: r), 300, accuracy: 1e-9)
        XCTAssertEqual(NitsModel.nits(hardware: 0, software: 1, xdr: 1, range: r), 20, accuracy: 1e-9)
        XCTAssertEqual(NitsModel.nits(hardware: nil, software: 0.5, xdr: 1, range: r), 300 * pow(0.5, 2.2), accuracy: 1e-9)
        XCTAssertEqual(NitsModel.nits(hardware: 1, software: 1, xdr: 1.5, range: r), 450, accuracy: 1e-9)
        XCTAssertEqual(NitsModel.nits(hardware: 1, software: 1, xdr: 3, range: r), 600, accuracy: 1e-9, "capped at the peak")
        XCTAssertEqual(NitsModel.nits(hardware: .nan, software: .nan, xdr: .nan, range: r), 300, accuracy: 1e-9)
    }

    func testRangeSanitizeOrders() {
        let bad = NitsRange(minimum: 900, maximum: 100, peak: 50, isEstimate: false).sanitized()
        XCTAssertLessThan(bad.minimum, bad.maximum)
        XCTAssertGreaterThanOrEqual(bad.peak, bad.maximum)
        let nan = NitsRange(minimum: .nan, maximum: .infinity, peak: -1, isEstimate: false).sanitized()
        XCTAssertTrue(nan.minimum.isFinite && nan.maximum.isFinite && nan.peak.isFinite)
        let decoded = try? JSONDecoder().decode(NitsRange.self, from: Data(#"{"maximum":"x"}"#.utf8))
        XCTAssertEqual(decoded?.maximum, 300)
    }

    func testLabel() {
        XCTAssertEqual(NitsModel.label(347, estimate: false), "350 nits")
        XCTAssertEqual(NitsModel.label(42.4, estimate: true), "≈42 nits")
        XCTAssertEqual(NitsModel.label(.nan, estimate: false), "0 nits")
    }
}
