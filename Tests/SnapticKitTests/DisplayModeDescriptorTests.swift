import XCTest
@testable import SnapticKit

final class DisplayModeDescriptorTests: XCTestCase {
    private func d(_ m: ModeRef) -> DisplayModeDescriptor {
        DisplayModeDescriptor(ref: m, isNative: false, isDefault: false, isUsableForDesktop: true, ioFlags: 0, bitDepth: 8)
    }

    func testResolvePrefersExactThenUniqueShape() {
        let a = BLayout.mode(1920, 1080, hidpi: true, id: 10)
        let b = BLayout.mode(1920, 1080, hidpi: true, id: 11)
        let list = [d(a), d(BLayout.mode(1280, 720, id: 12))]
        XCTAssertEqual(DisplayModeDescriptor.resolve(a, in: list)?.ref, a)
        XCTAssertEqual(DisplayModeDescriptor.resolve(b, in: list)?.ref, a, "ioModeID is only a hint")
        XCTAssertNil(DisplayModeDescriptor.resolve(BLayout.mode(800, 600), in: list))
        // Two duplicates with other ids: ambiguous, refuse.
        let dup = [d(a), d(b)]
        var c = a
        c.ioModeID = 99
        XCTAssertNil(DisplayModeDescriptor.resolve(c, in: dup))
        XCTAssertEqual(DisplayModeDescriptor.resolve(b, in: dup)?.ref, b)
    }

    func testDerivedValues() {
        let m = d(BLayout.mode(1600, 900, hz: 120))
        XCTAssertEqual(m.refreshHz, 120)
        XCTAssertEqual(m.aspect, 16.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(m.sizeLabel, "1600 × 900")
        XCTAssertFalse(m.isHiDPI)
    }

    private func record(width: UInt32, height: UInt32, refresh: UInt16, density: Float, mode: UInt32 = 3,
                        flags: UInt32 = DisplayModeDescriptor.nativeFlag) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: CGSModeRecord.length)
        func put(_ v: UInt32, _ o: Int) { for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) } }
        put(mode, 0); put(flags, 4); put(width, 8); put(height, 12); put(32, 16)
        b[0xBC] = UInt8(refresh & 0xFF); b[0xBD] = UInt8(refresh >> 8)
        put(density.bitPattern, 0xD0)
        return b
    }

    func testCGSRecordParse() {
        let r = CGSModeRecord.parse(record(width: 1440, height: 900, refresh: 60, density: 2))
        XCTAssertEqual(r?.width, 1440)
        XCTAssertEqual(r?.refreshHz, 60)
        XCTAssertEqual(r?.density, 2)
        let desc = r!.descriptor
        XCTAssertEqual(desc.ref.pixelWidth, 2880)
        XCTAssertTrue(desc.isHiDPI && desc.isNative)
        XCTAssertEqual(desc.cgsModeNumber, 3)
        XCTAssertFalse(desc.isUsableForDesktop)
        XCTAssertNil(CGSModeRecord.parse(record(width: 0, height: 900, refresh: 60, density: 1)))
        XCTAssertNil(CGSModeRecord.parse(record(width: 1440, height: 900, refresh: 60, density: .nan)))
        XCTAssertNil(CGSModeRecord.parse(record(width: 1440, height: 99999, refresh: 60, density: 1)))
        XCTAssertNil(CGSModeRecord.parse(Array(record(width: 1, height: 1, refresh: 1, density: 1).prefix(100))))
    }

    func testFuzzCGSRecords() {
        var rng = SeededGenerator(seed: 0xC65)
        for _ in 0..<5000 {
            let n = Int(rng.next() % 300)
            let bytes = (0..<n).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            if let r = CGSModeRecord.parse(bytes) {
                XCTAssertTrue((1...16384).contains(r.width) && (1...16384).contains(r.height))
                XCTAssertTrue(r.density >= 1 && r.density <= 4)
                _ = r.descriptor
            }
        }
    }
}
