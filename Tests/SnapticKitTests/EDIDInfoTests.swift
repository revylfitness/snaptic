import XCTest
@testable import SnapticKit

final class EDIDInfoTests: XCTestCase {
    /// A minimal valid EDID 1.4 base block ("DEL", "U2720Q", serial "ABC123"), plus optional CTA extension.
    static func sample(withCTA: Bool = false, hdr: Bool = true) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 128)
        b[0..<8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        // "DEL": D=4 E=5 L=12 → 00100 00101 01100
        let mfg: UInt16 = (4 << 10) | (5 << 5) | 12
        b[8] = UInt8(mfg >> 8); b[9] = UInt8(mfg & 0xFF)
        b[10] = 0x34; b[11] = 0x12                       // product 0x1234
        b[12] = 0x78; b[13] = 0x56; b[14] = 0x34; b[15] = 0x12
        b[16] = 10; b[17] = 30                           // week 10, 2020
        b[18] = 1; b[19] = 4
        b[20] = 0xA5
        b[21] = 60; b[22] = 34                           // 60 × 34 cm
        // Chromaticity: red (0.640, 0.330), green (0.300, 0.600), blue (0.150, 0.060), white (0.3125, 0.3291)
        func c10(_ v: Double) -> Int { Int((v * 1024).rounded()) }
        let vals = [c10(0.640), c10(0.330), c10(0.300), c10(0.600), c10(0.150), c10(0.060), c10(0.3125), c10(0.3291)]
        b[25] = UInt8((vals[0] & 3) << 6 | (vals[1] & 3) << 4 | (vals[2] & 3) << 2 | (vals[3] & 3))
        b[26] = UInt8((vals[4] & 3) << 6 | (vals[5] & 3) << 4 | (vals[6] & 3) << 2 | (vals[7] & 3))
        for (i, v) in vals.enumerated() { b[27 + i] = UInt8(v >> 2) }
        // DTD: 3840 × 2160, 597 × 336 mm
        b[54] = 0x01; b[55] = 0x1D
        b[56] = UInt8(3840 & 0xFF); b[58] = UInt8((3840 >> 8) << 4)
        b[59] = UInt8(2160 & 0xFF); b[61] = UInt8((2160 >> 8) << 4)
        b[66] = UInt8(597 & 0xFF); b[67] = UInt8(336 & 0xFF); b[68] = UInt8((597 >> 8) << 4 | (336 >> 8))
        // Name and serial descriptors
        func text(_ offset: Int, _ tag: UInt8, _ s: String) {
            b[offset + 3] = tag
            var bytes = Array(s.utf8) + [0x0A]
            while bytes.count < 13 { bytes.append(0x20) }
            for (i, c) in bytes.prefix(13).enumerated() { b[offset + 5 + i] = c }
        }
        text(72, 0xFC, "DELL U2720Q")
        text(90, 0xFF, "ABC123")
        b[126] = withCTA ? 1 : 0
        b[127] = checksum(b)
        guard withCTA else { return b }
        var e = [UInt8](repeating: 0, count: 128)
        e[0] = 0x02; e[1] = 0x03; e[2] = 10
        e[4] = hdr ? (7 << 5 | 3) : (2 << 5 | 3)
        e[5] = hdr ? 6 : 0
        e[127] = checksum(e)
        return b + e
    }

    static func checksum(_ block: [UInt8]) -> UInt8 {
        var s: UInt8 = 0
        for v in block.prefix(127) { s = s &+ v }
        return 0 &- s
    }

    func testParsesBaseBlock() throws {
        let info = try XCTUnwrap(EDIDInfo.parse(Self.sample()))
        XCTAssertEqual(info.manufacturerID, "DEL")
        XCTAssertEqual(info.productCode, 0x1234)
        XCTAssertEqual(info.serialNumber, 0x1234_5678)
        XCTAssertEqual(info.name, "DELL U2720Q")
        XCTAssertEqual(info.serialString, "ABC123")
        XCTAssertEqual(info.year, 2020)
        XCTAssertEqual(info.week, 10)
        XCTAssertEqual(info.version, 1)
        XCTAssertEqual(info.revision, 4)
        XCTAssertTrue(info.isDigital)
        XCTAssertEqual(info.nativePixelWidth, 3840)
        XCTAssertEqual(info.nativePixelHeight, 2160)
        XCTAssertEqual(info.physicalWidthMM, 597)
        XCTAssertEqual(info.physicalHeightMM, 336)
        XCTAssertTrue(info.checksumValid)
        let c = try XCTUnwrap(info.chromaticity)
        XCTAssertEqual(c.redX, 0.640, accuracy: 0.002)
        XCTAssertEqual(c.whiteY, 0.3291, accuracy: 0.002)
        XCTAssertEqual(info.extensionCount, 0)
        XCTAssertFalse(info.hasHDRStaticMetadata)
    }

    func testCTAHDRAndExtensions() throws {
        let info = try XCTUnwrap(EDIDInfo.parse(Self.sample(withCTA: true)))
        XCTAssertEqual(info.extensionCount, 1)
        XCTAssertTrue(info.hasHDRStaticMetadata)
        XCTAssertTrue(info.checksumValid)
        XCTAssertFalse(try XCTUnwrap(EDIDInfo.parse(Self.sample(withCTA: true, hdr: false))).hasHDRStaticMetadata)
        // Claims 200 extensions but only one is present: bounded.
        var claim = Self.sample(withCTA: true)
        claim[126] = 200
        XCTAssertEqual(EDIDInfo.parse(claim)?.extensionCount, 1)
    }

    func testRejectsAndBounds() {
        XCTAssertNil(EDIDInfo.parse([UInt8](repeating: 0, count: 128)))
        XCTAssertNil(EDIDInfo.parse(Array(Self.sample().prefix(127))))
        var bad = Self.sample()
        bad[127] &+= 1
        XCTAssertEqual(EDIDInfo.parse(bad)?.checksumValid, false)
        // Over 1024 bytes: the excess is ignored.
        let huge = Self.sample(withCTA: true) + [UInt8](repeating: 0xAB, count: 4000)
        XCTAssertNotNil(EDIDInfo.parse(huge))
        XCTAssertNotNil(EDIDInfo.parse(Data(Self.sample())))
    }

    func testFuzzNeverTrapsAndStaysBounded() {
        var rng = SeededGenerator(seed: 0xED1D)
        let base = Self.sample(withCTA: true)
        for i in 0..<20_000 {
            var bytes: [UInt8]
            if i % 2 == 0 {
                bytes = base
                for _ in 0..<Int(rng.next() % 20) {
                    let at = Int(rng.next() % UInt64(bytes.count))
                    bytes[at] = UInt8(truncatingIfNeeded: rng.next())
                }
                if rng.next() % 4 == 0 { bytes = Array(bytes.prefix(Int(rng.next() % UInt64(bytes.count + 1)))) }
            } else {
                bytes = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
                    + (0..<Int(rng.next() % 1200)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            }
            guard let info = EDIDInfo.parse(bytes) else { continue }
            XCTAssertLessThanOrEqual(info.extensionCount, EDIDInfo.maxExtensions)
            XCTAssertLessThanOrEqual(info.name?.count ?? 0, 13)
            XCTAssertLessThanOrEqual(info.serialString?.count ?? 0, 13)
            XCTAssertEqual(info.manufacturerID.count, 3)
            if let c = info.chromaticity { XCTAssertTrue(c.isPlausible) }
            XCTAssertTrue(info.name?.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F } ?? true)
        }
    }
}
