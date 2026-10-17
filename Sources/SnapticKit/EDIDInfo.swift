import Foundation

// Bounded EDID parser (owner: B). PLAN §4.10(4): at most 1024 bytes and 7 extension
// blocks; every read is bounds-checked, and strings are sanitized. Never logged.

/// CIE 1931 xy coordinates of the panel's primaries and white point.
package struct Chromaticity: Codable, Equatable, Sendable {
    package var redX: Double, redY: Double
    package var greenX: Double, greenY: Double
    package var blueX: Double, blueY: Double
    package var whiteX: Double, whiteY: Double

    package init(redX: Double, redY: Double, greenX: Double, greenY: Double, blueX: Double, blueY: Double,
                 whiteX: Double, whiteY: Double) {
        self.redX = redX
        self.redY = redY
        self.greenX = greenX
        self.greenY = greenY
        self.blueX = blueX
        self.blueY = blueY
        self.whiteX = whiteX
        self.whiteY = whiteY
    }

    /// All primaries inside the unit square and not all zero.
    package var isPlausible: Bool {
        let v = [redX, redY, greenX, greenY, blueX, blueY, whiteX, whiteY]
        return v.allSatisfy { $0 >= 0 && $0 <= 1 } && v.contains { $0 > 0 } && whiteY > 0
    }
}

package struct EDIDInfo: Codable, Equatable, Sendable {
    package static let blockSize = 128
    package static let maxBytes = 1024
    package static let maxExtensions = 7
    private static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    /// Three-letter PNP id, e.g. "DEL".
    package var manufacturerID: String = ""
    package var productCode: UInt16 = 0
    /// Numeric serial from the base block (often 0).
    package var serialNumber: UInt32 = 0
    /// Display serial number descriptor (0xFF), sanitized.
    package var serialString: String?
    /// Display product name descriptor (0xFC), sanitized.
    package var name: String?
    package var week: Int = 0
    package var year: Int = 0
    package var version: Int = 0
    package var revision: Int = 0
    /// Image size from the base block (cm → mm), 0 when unknown or a ratio.
    package var physicalWidthMM: Int = 0
    package var physicalHeightMM: Int = 0
    package var chromaticity: Chromaticity?
    /// From the first detailed timing descriptor.
    package var nativePixelWidth: Int?
    package var nativePixelHeight: Int?
    /// Extension blocks present (counted, ≤ 7).
    package var extensionCount: Int = 0
    /// Every parsed block's checksum is valid.
    package var checksumValid: Bool = false
    /// A CTA-861 HDR static metadata block was found.
    package var hasHDRStaticMetadata: Bool = false
    package var isDigital: Bool = false

    package init() {}

    /// Nil unless the base block has a valid header. Bytes beyond `maxBytes` are ignored.
    package static func parse(_ data: [UInt8]) -> EDIDInfo? {
        let bytes = Array(data.prefix(maxBytes))
        guard bytes.count >= blockSize, Array(bytes[0..<8]) == header else { return nil }
        var info = EDIDInfo()
        let b = ByteReader(bytes)

        let mfg = UInt16(b.u8(8)) << 8 | UInt16(b.u8(9))
        let letters = [(mfg >> 10) & 0x1F, (mfg >> 5) & 0x1F, mfg & 0x1F].map { v -> Character in
            (1...26).contains(v) ? Character(UnicodeScalar(UInt8(v) + 0x40)) : "?"
        }
        info.manufacturerID = String(letters)
        info.productCode = UInt16(b.u8(10)) | UInt16(b.u8(11)) << 8
        info.serialNumber = UInt32(b.u8(12)) | UInt32(b.u8(13)) << 8 | UInt32(b.u8(14)) << 16 | UInt32(b.u8(15)) << 24
        info.week = Int(b.u8(16))
        info.year = Int(b.u8(17)) > 0 ? 1990 + Int(b.u8(17)) : 0
        info.version = Int(b.u8(18))
        info.revision = Int(b.u8(19))
        info.isDigital = b.u8(20) & 0x80 != 0
        let wcm = Int(b.u8(21)), hcm = Int(b.u8(22))
        if wcm > 0 && hcm > 0 {
            info.physicalWidthMM = wcm * 10
            info.physicalHeightMM = hcm * 10
        }
        info.chromaticity = parseChromaticity(b)

        // Four 18-byte descriptors.
        for offset in stride(from: 54, through: 108, by: 18) {
            let pixelClock = UInt16(b.u8(offset)) | UInt16(b.u8(offset + 1)) << 8
            if pixelClock != 0 {
                if info.nativePixelWidth == nil {
                    let hActive = Int(b.u8(offset + 2)) | Int(b.u8(offset + 4) >> 4) << 8
                    let vActive = Int(b.u8(offset + 5)) | Int(b.u8(offset + 7) >> 4) << 8
                    if hActive > 0 && vActive > 0 {
                        info.nativePixelWidth = hActive
                        info.nativePixelHeight = vActive
                    }
                    let wmm = Int(b.u8(offset + 12)) | Int(b.u8(offset + 14) >> 4) << 8
                    let hmm = Int(b.u8(offset + 13)) | Int(b.u8(offset + 14) & 0x0F) << 8
                    if wmm > 0 && hmm > 0 && wmm < 5000 && hmm < 5000 {
                        info.physicalWidthMM = wmm
                        info.physicalHeightMM = hmm
                    }
                }
                continue
            }
            let tag = b.u8(offset + 3)
            let text = descriptorText(b, offset: offset + 5)
            switch tag {
            case 0xFC: if info.name == nil { info.name = text }
            case 0xFF: if info.serialString == nil { info.serialString = text }
            default: break
            }
        }

        // Extensions.
        let available = bytes.count / blockSize - 1
        info.extensionCount = min(Int(b.u8(126)), maxExtensions, max(0, available))
        var checksumsOK = checksum(bytes, block: 0)
        for ext in 0..<info.extensionCount {
            let base = (ext + 1) * blockSize
            checksumsOK = checksumsOK && checksum(bytes, block: ext + 1)
            if b.u8(base) == 0x02 && parseCTAForHDR(b, base: base) { info.hasHDRStaticMetadata = true }
        }
        info.checksumValid = checksumsOK
        return info
    }

    package static func parse(_ data: Data) -> EDIDInfo? { parse([UInt8](data.prefix(maxBytes))) }

    private static func parseChromaticity(_ b: ByteReader) -> Chromaticity? {
        let lo1 = b.u8(25), lo2 = b.u8(26)
        func coord(_ hi: Int, _ lo: UInt8) -> Double { Double(Int(b.u8(hi)) << 2 | Int(lo & 0x03)) / 1024 }
        let c = Chromaticity(redX: coord(27, lo1 >> 6), redY: coord(28, lo1 >> 4),
                             greenX: coord(29, lo1 >> 2), greenY: coord(30, lo1),
                             blueX: coord(31, lo2 >> 6), blueY: coord(32, lo2 >> 4),
                             whiteX: coord(33, lo2 >> 2), whiteY: coord(34, lo2))
        return c.isPlausible ? c : nil
    }

    /// Up to 13 bytes, ended by 0x0A, printable ASCII only.
    private static func descriptorText(_ b: ByteReader, offset: Int) -> String? {
        var scalars = ""
        for i in 0..<13 {
            let c = b.u8(offset + i)
            if c == 0x0A || c == 0x00 { break }
            if c >= 0x20 && c < 0x7F { scalars.append(Character(UnicodeScalar(c))) }
        }
        let trimmed = scalars.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(13))
    }

    private static func checksum(_ bytes: [UInt8], block: Int) -> Bool {
        let start = block * blockSize
        guard start + blockSize <= bytes.count else { return false }
        var sum: UInt8 = 0
        for i in start..<(start + blockSize) { sum = sum &+ bytes[i] }
        return sum == 0
    }

    /// Walks a CTA-861 data block collection (bounded by the DTD offset and the block end)
    /// for the extended tag 6 (HDR static metadata).
    private static func parseCTAForHDR(_ b: ByteReader, base: Int) -> Bool {
        let dtdOffset = Int(b.u8(base + 2))
        guard dtdOffset >= 4, dtdOffset <= 127 else { return false }
        var i = base + 4
        let end = base + dtdOffset
        var steps = 0
        while i < end && steps < 64 {
            steps += 1
            let header = b.u8(i)
            let tag = header >> 5, length = Int(header & 0x1F)
            if tag == 7 && length >= 1 && b.u8(i + 1) == 6 { return true }
            i += 1 + length
        }
        return false
    }
}

/// Bounds-checked byte access: out-of-range reads return 0 instead of trapping.
private struct ByteReader {
    let bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }
    func u8(_ i: Int) -> UInt8 { i >= 0 && i < bytes.count ? bytes[i] : 0 }
}
