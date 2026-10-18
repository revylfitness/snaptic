import Foundation

// Virtual-display size limits per chip class and RAM (owner: D). PLAN §9.2, §3.4.

/// The chip family that decides the largest framebuffer a virtual display may use.
package enum SoCClass: String, Codable, CaseIterable, Sendable {
    /// Base Apple silicon (M1, M2, M3, …): 6K-wide framebuffers.
    case appleEntry
    /// Apple silicon Pro, Max and Ultra: 8K-wide framebuffers.
    case applePro
    /// Intel Macs: bounded by the GPU; 8192 is the conservative limit.
    case intel
}

package enum SoCCaps {
    /// Largest backing width (and height) in pixels for one virtual display.
    package static func maxBackingDimension(_ soc: SoCClass) -> Int {
        switch soc {
        case .appleEntry: return 6144
        case .applePro: return 7680
        case .intel: return 8192
        }
    }

    /// Classifies a CPU brand string (`machdep.cpu.brand_string`). Apple silicon brands
    /// look like "Apple M2" or "Apple M3 Max"; anything that isn't Apple silicon is Intel.
    package static func classify(cpuBrand: String, isAppleSilicon: Bool) -> SoCClass {
        guard isAppleSilicon else { return .intel }
        let brand = cpuBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        // ^Apple M\d+ (Pro|Max|Ultra)$
        let words = brand.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count == 3, words[0] == "Apple", isChipName(words[1]) else { return .appleEntry }
        switch words[2] {
        case "Pro", "Max", "Ultra": return .applePro
        default: return .appleEntry
        }
    }

    private static func isChipName(_ word: Substring) -> Bool {
        guard word.count >= 2, word.first == "M" else { return false }
        return word.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Bytes WindowServer keeps for one virtual display: 4 bytes per pixel, triple-buffered.
    /// An estimate shown on the Safety page and used for the total budget.
    package static func backingBytes(pixelsWide: Int, pixelsHigh: Int) -> UInt64 {
        guard pixelsWide > 0, pixelsHigh > 0 else { return 0 }
        // Saturates (an unsanitized size must not trap; the budget then simply refuses it).
        let (area, o1) = UInt64(pixelsWide).multipliedReportingOverflow(by: UInt64(pixelsHigh))
        let (bytes, o2) = area.multipliedReportingOverflow(by: 12)
        return o1 || o2 ? UInt64.max : bytes
    }

    /// Total backing budget for all Snaptic virtual displays together: 1/16 of RAM,
    /// at least 256 MiB and at most 4 GiB.
    package static func maxBackingBytes(ram: UInt64) -> UInt64 {
        let floor: UInt64 = 256 << 20
        let ceiling: UInt64 = 4 << 30
        return min(ceiling, max(floor, ram / 16))
    }

    /// Whether adding `additional` bytes to `existing` stays within the RAM budget.
    package static func fitsBudget(existing: UInt64, additional: UInt64, ram: UInt64) -> Bool {
        let (sum, overflow) = existing.addingReportingOverflow(additional)
        return !overflow && sum <= maxBackingBytes(ram: ram)
    }

    /// Whether a backing size is within the chip's per-display limit.
    package static func fitsChip(pixelsWide: Int, pixelsHigh: Int, soc: SoCClass) -> Bool {
        let limit = maxBackingDimension(soc)
        return pixelsWide > 0 && pixelsHigh > 0 && pixelsWide <= limit && pixelsHigh <= limit
    }

    /// The largest point width a HiDPI (2×) mode can have on this chip.
    package static func maxHiDPIPointDimension(_ soc: SoCClass) -> Int { maxBackingDimension(soc) / 2 }
}
