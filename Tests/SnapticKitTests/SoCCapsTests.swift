import XCTest
@testable import SnapticKit

final class SoCCapsTests: XCTestCase {
    func testClassifiesChips() {
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M1", isAppleSilicon: true), .appleEntry)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M3 Pro", isAppleSilicon: true), .applePro)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M2 Max", isAppleSilicon: true), .applePro)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M1 Ultra", isAppleSilicon: true), .applePro)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M10 Max", isAppleSilicon: true), .applePro)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "  Apple M4 Pro\n", isAppleSilicon: true), .applePro)
        // Not exactly the pattern: treated as entry (the safe, smaller limit).
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M4 Pro Extra", isAppleSilicon: true), .appleEntry)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple MX Pro", isAppleSilicon: true), .appleEntry)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M Pro", isAppleSilicon: true), .appleEntry)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "", isAppleSilicon: true), .appleEntry)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Intel(R) Core(TM) i9", isAppleSilicon: false), .intel)
        XCTAssertEqual(SoCCaps.classify(cpuBrand: "Apple M3 Max", isAppleSilicon: false), .intel)
    }

    func testDimensionLimits() {
        XCTAssertEqual(SoCCaps.maxBackingDimension(.appleEntry), 6144)
        XCTAssertEqual(SoCCaps.maxBackingDimension(.applePro), 7680)
        XCTAssertEqual(SoCCaps.maxBackingDimension(.intel), 8192)
        XCTAssertEqual(SoCCaps.maxHiDPIPointDimension(.appleEntry), 3072)
        XCTAssertTrue(SoCCaps.fitsChip(pixelsWide: 6144, pixelsHigh: 3456, soc: .appleEntry))
        XCTAssertFalse(SoCCaps.fitsChip(pixelsWide: 6145, pixelsHigh: 100, soc: .appleEntry))
        XCTAssertTrue(SoCCaps.fitsChip(pixelsWide: 7680, pixelsHigh: 4320, soc: .applePro))
        XCTAssertFalse(SoCCaps.fitsChip(pixelsWide: 0, pixelsHigh: 100, soc: .intel))
    }

    func testBackingBudget() {
        XCTAssertEqual(SoCCaps.backingBytes(pixelsWide: 100, pixelsHigh: 10), 12_000)
        XCTAssertEqual(SoCCaps.backingBytes(pixelsWide: -1, pixelsHigh: 10), 0)
        let gib: UInt64 = 1 << 30
        XCTAssertEqual(SoCCaps.maxBackingBytes(ram: 0), 256 << 20)
        XCTAssertEqual(SoCCaps.maxBackingBytes(ram: 8 * gib), 512 << 20)
        XCTAssertEqual(SoCCaps.maxBackingBytes(ram: 16 * gib), gib)
        XCTAssertEqual(SoCCaps.maxBackingBytes(ram: 512 * gib), 4 * gib)
        XCTAssertEqual(SoCCaps.maxBackingBytes(ram: .max), 4 * gib)
        let fiveK = SoCCaps.backingBytes(pixelsWide: 5120, pixelsHigh: 2880)
        XCTAssertTrue(SoCCaps.fitsBudget(existing: 0, additional: fiveK, ram: 8 * gib))
        XCTAssertFalse(SoCCaps.fitsBudget(existing: fiveK * 3, additional: fiveK, ram: 8 * gib))
        XCTAssertFalse(SoCCaps.fitsBudget(existing: .max, additional: 1, ram: .max))
    }
}
