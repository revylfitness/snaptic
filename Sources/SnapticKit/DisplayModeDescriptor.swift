import Foundation

// A display mode as plain values (owner: B).

package struct DisplayModeDescriptor: Codable, Hashable, Sendable {
    package var ref: ModeRef
    package var isNative: Bool
    package var isDefault: Bool
    package var isUsableForDesktop: Bool
    package var ioFlags: UInt32
    package var bitDepth: Int
    /// Set for modes that come from the private CGS list (`hiddenModes`); nil for public modes.
    package var cgsModeNumber: Int32?

    package init(ref: ModeRef, isNative: Bool, isDefault: Bool, isUsableForDesktop: Bool, ioFlags: UInt32, bitDepth: Int,
                 cgsModeNumber: Int32? = nil) {
        self.ref = ref
        self.isNative = isNative
        self.isDefault = isDefault
        self.isUsableForDesktop = isUsableForDesktop
        self.ioFlags = ioFlags
        self.bitDepth = bitDepth
        self.cgsModeNumber = cgsModeNumber
    }

    package var isHiDPI: Bool { ref.isHiDPI }

    /// Refresh rate in Hz (0 for panels that don't report one).
    package var refreshHz: Double { Double(ref.refreshMilliHz) / 1000 }

    /// Point width ÷ height (0 if degenerate).
    package var aspect: Double { ref.pointHeight > 0 ? Double(ref.pointWidth) / Double(ref.pointHeight) : 0 }

    /// "1920 × 1080" (points).
    package var sizeLabel: String { "\(ref.pointWidth) × \(ref.pointHeight)" }

    /// IOKit display mode flags (IOGraphicsTypes.h).
    package static let nativeFlag: UInt32 = 0x0200_0000
    package static let defaultFlag: UInt32 = 0x0000_0004
    package static let safeFlag: UInt32 = 0x0000_0001

    /// Resolves a ModeRef against a fresh list (R2C m10): exact match first; otherwise the
    /// unique mode with the same shape (ioModeIDs aren't unique across HiDPI duplicates and
    /// can change after HDR or rotation). Nil when nothing or several modes match.
    package static func resolve(_ ref: ModeRef, in list: [DisplayModeDescriptor]) -> DisplayModeDescriptor? {
        if let exact = list.first(where: { $0.ref == ref }) { return exact }
        let shaped = list.filter { $0.ref.sameShape(as: ref) }
        if shaped.count == 1 { return shaped[0] }
        // Several duplicates: prefer the one whose ioModeID matches the hint.
        let hinted = shaped.filter { $0.ref.ioModeID == ref.ioModeID }
        return hinted.count == 1 ? hinted[0] : nil
    }
}

/// One record from the private CGS mode list (`CGSGetDisplayModeDescriptionOfLength`,
/// 0xD4 bytes; layout agreed by displayplacer and BetterDummy). Parsed in Kit so the bounds
/// checks are fuzz-tested; any record that fails a sanity check disables the CGS path.
package struct CGSModeRecord: Equatable, Sendable {
    package static let length = 0xD4

    package var modeNumber: Int32
    package var flags: UInt32
    package var width: Int
    package var height: Int
    package var depth: Int
    package var refreshHz: Int
    package var density: Double

    package init(modeNumber: Int32, flags: UInt32, width: Int, height: Int, depth: Int, refreshHz: Int, density: Double) {
        self.modeNumber = modeNumber
        self.flags = flags
        self.width = width
        self.height = height
        self.depth = depth
        self.refreshHz = refreshHz
        self.density = density
    }

    /// Nil unless the record is complete and sane (sizes 1…16384, density 1…4, refresh ≤ 1000).
    package static func parse(_ bytes: [UInt8]) -> CGSModeRecord? {
        guard bytes.count >= length else { return nil }
        func u32(_ o: Int) -> UInt32 {
            UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
        }
        let width = Int(u32(0x08)), height = Int(u32(0x0C)), depth = Int(u32(0x10))
        let refresh = Int(UInt16(bytes[0xBC]) | UInt16(bytes[0xBD]) << 8)
        let density = Double(Float(bitPattern: u32(0xD0)))
        guard (1...16384).contains(width), (1...16384).contains(height), depth <= 64,
              refresh <= 1000, density.isFinite, density >= 1, density <= 4 else { return nil }
        return CGSModeRecord(modeNumber: Int32(bitPattern: u32(0x00)), flags: u32(0x04), width: width, height: height,
                             depth: depth, refreshHz: refresh, density: density)
    }

    /// As a descriptor (pixel size = point size × density).
    package var descriptor: DisplayModeDescriptor {
        let pw = Int((Double(width) * density).rounded()), ph = Int((Double(height) * density).rounded())
        let ref = ModeRef(ioModeID: modeNumber, pixelWidth: pw, pixelHeight: ph, pointWidth: width, pointHeight: height,
                          refreshMilliHz: refreshHz * 1000)
        return DisplayModeDescriptor(ref: ref, isNative: flags & DisplayModeDescriptor.nativeFlag != 0,
                                     isDefault: flags & DisplayModeDescriptor.defaultFlag != 0,
                                     isUsableForDesktop: false, ioFlags: flags, bitDepth: depth,
                                     cgsModeNumber: modeNumber)
    }
}
