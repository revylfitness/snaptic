import Foundation

// Virtual screen specification (owner: D). PLAN §9.2, R5.6.

package struct VirtualMode: Codable, Hashable, Sendable {
    /// Points.
    package var width: Int
    package var height: Int
    package var hiDPI: Bool
    package var refreshMilliHz: Int
    package init(width: Int, height: Int, hiDPI: Bool, refreshMilliHz: Int = 60_000) {
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
        self.refreshMilliHz = refreshMilliHz
    }

    /// Backing pixels (2× points for HiDPI).
    package var pixelWidth: Int { hiDPI ? width * 2 : width }
    package var pixelHeight: Int { hiDPI ? height * 2 : height }
    package var refreshHz: Double { Double(refreshMilliHz) / 1000 }
    package var label: String {
        let base = "\(width) × \(height)"
        return hiDPI ? base + " HiDPI" : base
    }
}

/// CIE xy chromaticities for the virtual display's EDID-like descriptor.
package struct VirtualPrimaries: Codable, Equatable, Sendable {
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

    /// From a panel's EDID chromaticity (R5.6: EDID first), or nil when it isn't plausible.
    package init?(edid c: Chromaticity) {
        self.init(redX: c.redX, redY: c.redY, greenX: c.greenX, greenY: c.greenY, blueX: c.blueX, blueY: c.blueY,
                  whiteX: c.whiteX, whiteY: c.whiteY)
        guard isPlausible else { return nil }
    }

    package static let sRGB = VirtualPrimaries(redX: 0.64, redY: 0.33, greenX: 0.30, greenY: 0.60,
                                               blueX: 0.15, blueY: 0.06, whiteX: 0.3127, whiteY: 0.3290)
    package static let displayP3 = VirtualPrimaries(redX: 0.680, redY: 0.320, greenX: 0.265, greenY: 0.690,
                                                    blueX: 0.150, blueY: 0.060, whiteX: 0.3127, whiteY: 0.3290)

    /// Every coordinate inside the xy unit square and not degenerate.
    package var isPlausible: Bool {
        let all = [redX, redY, greenX, greenY, blueX, blueY, whiteX, whiteY]
        return all.allSatisfy { $0.isFinite && $0 > 0 && $0 < 1 }
    }
}

/// When an associated virtual screen connects by itself (PLAN §9.4).
package enum VirtualAutoConnect: String, Codable, CaseIterable, Sendable {
    /// Only by hand.
    case never
    /// While the associated display is connected.
    case whilePresent
    /// While every associated display is absent (KVM use).
    case whileAbsent
}

/// How a virtual screen shows up on its associated display.
package enum VirtualPresentation: String, Codable, CaseIterable, Sendable {
    case none
    /// The physical display mirrors the virtual one (Smart HiDPI path).
    case mirror
    /// A full-screen stream of the virtual screen onto the display (PIP module).
    case stream
    /// A horizontally flipped stream (teleprompter).
    case flippedStream
}

package struct VirtualAssociation: Codable, Equatable, Sendable {
    package var target: DisplayKey
    package var autoConnect: VirtualAutoConnect
    package var presentation: VirtualPresentation

    package init(target: DisplayKey, autoConnect: VirtualAutoConnect = .whilePresent, presentation: VirtualPresentation = .none) {
        self.target = target
        self.autoConnect = autoConnect
        self.presentation = presentation
    }

    private enum CodingKeys: String, CodingKey { case target, autoConnect, presentation }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decode(DisplayKey.self, forKey: .target)
        autoConnect = c.lossy(.autoConnect, .whilePresent)
        presentation = c.lossy(.presentation, .none)
    }
}

/// Where a newly connected virtual screen goes in the arrangement.
package enum VirtualPlacement: String, Codable, CaseIterable, Sendable {
    /// Wherever macOS puts it (or its remembered place).
    case automatic
    /// Below and to the right of the main display, so the pointer doesn't drift into it.
    case belowRightOfMain
}

package struct VirtualScreenSpec: Codable, Equatable, Sendable {
    package var id: StableID
    package var name: String
    package var aspectWidth: Int
    package var aspectHeight: Int
    package var sizeInches: Double
    package var hiDPI: Bool
    /// Points; the first one is the initial mode.
    package var modes: [VirtualMode]
    package var portrait: Bool
    package var recreateOnLaunch: Bool
    /// Only the Headless recipe sets this; such a screen counts as weakly visible (§4.1).
    package var headlessPrimary: Bool
    package var primaries: VirtualPrimaries?
    package var associations: [VirtualAssociation]
    /// HDR (PQ) modes; needs `hdrVirtual`.
    package var hdr: Bool
    package var placement: VirtualPlacement
    /// The recording recipe also wants a PIP configuration.
    package var wantsPIP: Bool

    package init(id: StableID = StableID(), name: String, aspectWidth: Int, aspectHeight: Int, sizeInches: Double,
                 hiDPI: Bool, modes: [VirtualMode], portrait: Bool = false, recreateOnLaunch: Bool = false,
                 headlessPrimary: Bool = false, primaries: VirtualPrimaries? = nil, associations: [VirtualAssociation] = [],
                 hdr: Bool = false, placement: VirtualPlacement = .automatic, wantsPIP: Bool = false) {
        self.id = id
        self.name = name
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.sizeInches = sizeInches
        self.hiDPI = hiDPI
        self.modes = modes
        self.portrait = portrait
        self.recreateOnLaunch = recreateOnLaunch
        self.headlessPrimary = headlessPrimary
        self.primaries = primaries
        self.associations = associations
        self.hdr = hdr
        self.placement = placement
        self.wantsPIP = wantsPIP
    }

    /// Our virtual displays' vendor id: bit 15 set, so never a valid PNP id.
    package static let vendorID: UInt32 = 0xD354
    package static let productID: UInt32 = 0x0001
    package static let maxNameScalars = 64
    package static let maxModesHiDPI = 100
    package static let maxModesLoDPI = 200
    package static let minRefreshMilliHz = 24_000
    package static let maxRefreshMilliHz = 240_000
    package static let minSizeInches = 0.1
    package static let maxSizeInches = 1000.0
    package static let maxAspectComponent = 16384
    package static let minModeDimension = 160

    private enum CodingKeys: String, CodingKey {
        case id, name, aspectWidth, aspectHeight, sizeInches, hiDPI, modes, portrait, recreateOnLaunch, headlessPrimary,
             primaries, associations, hdr, placement, wantsPIP
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StableID.self, forKey: .id)
        name = c.lossy(.name, L("Virtual Screen"))
        aspectWidth = c.lossy(.aspectWidth, 16)
        aspectHeight = c.lossy(.aspectHeight, 9)
        sizeInches = c.lossy(.sizeInches, 27)
        hiDPI = c.lossy(.hiDPI, true)
        modes = c.lossy(.modes, [])
        portrait = c.lossy(.portrait, false)
        recreateOnLaunch = c.lossy(.recreateOnLaunch, false)
        headlessPrimary = c.lossy(.headlessPrimary, false)
        primaries = c.lossy(.primaries, nil)
        associations = (try? c.decodeIfPresent(TolerantArray<VirtualAssociation>.self, forKey: .associations))?.values ?? []
        hdr = c.lossy(.hdr, false)
        placement = c.lossy(.placement, .automatic)
        wantsPIP = c.lossy(.wantsPIP, false)
    }

    // MARK: Derived values

    /// The mode the screen is created with (R5.6: single-mode creation).
    package var initialMode: VirtualMode? { modes.first }

    package var largestMode: VirtualMode? {
        modes.max { ($0.pixelWidth * $0.pixelHeight, $0.width) < ($1.pixelWidth * $1.pixelHeight, $1.width) }
    }

    /// Backing size the descriptor reserves: 2 × the largest mode's points (R5.6), or the
    /// largest mode's pixels for LoDPI-only screens.
    package var maxPixels: (wide: Int, high: Int) {
        guard let m = largestMode else { return (0, 0) }
        return hiDPI ? (m.width * 2, m.height * 2) : (m.width, m.height)
    }

    /// Fallback when the HiDPI check fails: backing for the initial mode only.
    package var fallbackMaxPixels: (wide: Int, high: Int) {
        guard let m = initialMode else { return (0, 0) }
        return hiDPI ? (m.width * 2, m.height * 2) : (m.width, m.height)
    }

    /// Physical size reported to macOS (sets DPI and the default scale). Portrait swaps.
    package var sizeInMillimeters: (width: Double, height: Double) {
        let aw = Double(max(1, aspectWidth)), ah = Double(max(1, aspectHeight))
        let diagonal = sizeInches * 25.4
        let k = diagonal / (aw * aw + ah * ah).squareRoot()
        let w = aw * k, h = ah * k
        return portrait ? (h, w) : (w, h)
    }

    /// Estimated WindowServer memory for this screen (Safety page, budget).
    package var estimatedBackingBytes: UInt64 {
        let p = maxPixels
        return SoCCaps.backingBytes(pixelsWide: p.wide, pixelsHigh: p.high)
    }

    /// Stable, unsalted serial number for the descriptor (§4.10(7)): FNV-1a of the id,
    /// never 0. Smart HiDPI passes the physical display's fingerprint instead.
    package static func serial(for seed: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in seed.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash == 0 ? 1 : hash
    }

    package var serial: UInt32 { Self.serial(for: id.rawValue) }

    /// Modes sorted largest first, deduplicated (used by the UI and the slider).
    package var sortedModes: [VirtualMode] {
        var seen = Set<VirtualMode>()
        return modes.filter { seen.insert($0).inserted }
            .sorted { ($0.width, $0.height, $0.refreshMilliHz) > ($1.width, $1.height, $1.refreshMilliHz) }
    }

    /// Clamps everything to what the editor can produce and the chip can drive. Modes that
    /// don't fit are dropped; if none survives, a default ladder for the aspect is used.
    package func sanitized(soc: SoCClass = .appleEntry) -> VirtualScreenSpec {
        var s = self
        let cleanName = TextSanitizer.clean(name, maxScalars: Self.maxNameScalars).trimmingCharacters(in: .whitespaces)
        s.name = cleanName.isEmpty ? L("Virtual Screen") : cleanName
        s.aspectWidth = min(Self.maxAspectComponent, max(1, aspectWidth))
        s.aspectHeight = min(Self.maxAspectComponent, max(1, aspectHeight))
        s.sizeInches = sizeInches.isFinite ? min(Self.maxSizeInches, max(Self.minSizeInches, sizeInches)) : 27
        let limit = SoCCaps.maxBackingDimension(soc)
        var seen = Set<VirtualMode>()
        var kept: [VirtualMode] = []
        for var m in modes {
            m.hiDPI = s.hiDPI && m.hiDPI
            m.refreshMilliHz = min(Self.maxRefreshMilliHz, max(Self.minRefreshMilliHz, m.refreshMilliHz))
            guard m.width >= Self.minModeDimension, m.height >= Self.minModeDimension,
                  m.pixelWidth <= limit, m.pixelHeight <= limit, seen.insert(m).inserted else { continue }
            kept.append(m)
        }
        let cap = s.hiDPI ? Self.maxModesHiDPI : Self.maxModesLoDPI
        if kept.count > cap { kept = Array(kept.prefix(cap)) }
        if kept.isEmpty {
            kept = Self.ladder(aspectWidth: s.aspectWidth, aspectHeight: s.aspectHeight, hiDPI: s.hiDPI, soc: soc,
                               portrait: s.portrait)
        }
        s.modes = kept
        if let p = primaries, !p.isPlausible { s.primaries = nil }
        var targets = Set<DisplayKey>()
        s.associations = associations.filter { targets.insert($0.target).inserted }.prefix(8).map { $0 }
        return s
    }

    /// Standard point widths offered for a custom aspect ratio.
    package static let ladderWidths = [800, 960, 1024, 1152, 1280, 1366, 1440, 1600, 1680, 1920, 2048, 2304, 2560,
                                       2880, 3008, 3200, 3360, 3840, 4096, 5120, 6016, 6144, 7680]

    /// A default mode list for an aspect ratio: every ladder width whose height is a whole
    /// number of points at least 360, within the chip limit. Portrait swaps the axes.
    package static func ladder(aspectWidth: Int, aspectHeight: Int, hiDPI: Bool, soc: SoCClass = .appleEntry,
                               portrait: Bool = false, refreshMilliHz: Int = 60_000) -> [VirtualMode] {
        let aw = max(1, aspectWidth), ah = max(1, aspectHeight)
        let limit = SoCCaps.maxBackingDimension(soc) / (hiDPI ? 2 : 1)
        var result: [VirtualMode] = []
        for w in ladderWidths.reversed() {
            let exact = Double(w) * Double(ah) / Double(aw)
            var h = Int(exact.rounded())
            if h % 2 == 1 { h += 1 }
            guard h >= 360, w <= limit, h <= limit else { continue }
            let mode = portrait ? VirtualMode(width: h, height: w, hiDPI: hiDPI, refreshMilliHz: refreshMilliHz)
                : VirtualMode(width: w, height: h, hiDPI: hiDPI, refreshMilliHz: refreshMilliHz)
            if !result.contains(mode) { result.append(mode) }
        }
        if result.isEmpty {
            // Extreme aspect ratios: one mode that fits.
            let w = min(limit, 1920)
            let h = max(Self.minModeDimension, min(limit, w * ah / aw))
            result = [portrait ? VirtualMode(width: h, height: w, hiDPI: hiDPI, refreshMilliHz: refreshMilliHz)
                      : VirtualMode(width: w, height: h, hiDPI: hiDPI, refreshMilliHz: refreshMilliHz)]
        }
        return result
    }

    /// Modes the slider may offer after a HiDPI fallback (R5.6): no larger than the initial one.
    package func modesLimited(toInitial: Bool) -> [VirtualMode] {
        guard toInitial, let first = initialMode else { return modes }
        return modes.filter { $0.width <= first.width && $0.height <= first.height }
    }
}

/// An array that decodes element by element, dropping the ones that fail.
package struct TolerantArray<Element: Decodable>: Decodable {
    package var values: [Element]
    package init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !c.isAtEnd {
            if let v = try? c.decode(Element.self) {
                out.append(v)
            } else {
                do { _ = try c.decode(SkipValue.self) } catch { break }
            }
            if out.count >= 4096 { break }
        }
        values = out
    }

    private struct SkipValue: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// Edits the virtual display editor makes to a draft (Settings › Virtual Displays › Details…). Every mode shares the
/// spec's HiDPI flag and one refresh rate; `sanitized(soc:)` still runs when the draft is saved.
package enum VirtualSpecEdit {
    package static let defaultRefreshMilliHz = 60_000
    /// The refresh rates the editor offers (millihertz); a stored rate outside the list is offered too.
    package static let refreshChoices = [24_000, 30_000, 48_000, 50_000, 60_000, 75_000, 90_000, 100_000, 120_000, 144_000]

    /// The draft's refresh rate: the first mode's, else 60 Hz.
    package static func refreshMilliHz(_ spec: VirtualScreenSpec) -> Int {
        spec.modes.first?.refreshMilliHz ?? defaultRefreshMilliHz
    }

    /// The choices for a draft, with its own rate included and sorted.
    package static func refreshOptions(_ spec: VirtualScreenSpec) -> [Int] {
        let current = refreshMilliHz(spec)
        return refreshChoices.contains(current) ? refreshChoices : (refreshChoices + [current]).sorted()
    }

    package static func settingRefresh(_ spec: VirtualScreenSpec, milliHz: Int) -> VirtualScreenSpec {
        let hz = min(VirtualScreenSpec.maxRefreshMilliHz, max(VirtualScreenSpec.minRefreshMilliHz, milliHz))
        var s = spec
        s.modes = s.modes.map { VirtualMode(width: $0.width, height: $0.height, hiDPI: $0.hiDPI, refreshMilliHz: hz) }
        return s
    }

    package static func settingHiDPI(_ spec: VirtualScreenSpec, _ on: Bool) -> VirtualScreenSpec {
        var s = spec
        s.hiDPI = on
        s.modes = s.modes.map { VirtualMode(width: $0.width, height: $0.height, hiDPI: on, refreshMilliHz: $0.refreshMilliHz) }
        return s
    }

    /// Appends a size (points) unless it is already there or below the minimum; the spec's HiDPI and refresh apply.
    package static func addingSize(_ spec: VirtualScreenSpec, width: Int, height: Int) -> VirtualScreenSpec {
        guard width >= VirtualScreenSpec.minModeDimension, height >= VirtualScreenSpec.minModeDimension,
              width <= VirtualScreenSpec.maxAspectComponent, height <= VirtualScreenSpec.maxAspectComponent,
              !spec.modes.contains(where: { $0.width == width && $0.height == height }) else { return spec }
        var s = spec
        s.modes.append(VirtualMode(width: width, height: height, hiDPI: spec.hiDPI, refreshMilliHz: refreshMilliHz(spec)))
        return s
    }

    package static func removingSize(_ spec: VirtualScreenSpec, at index: Int) -> VirtualScreenSpec {
        guard spec.modes.indices.contains(index) else { return spec }
        var s = spec
        s.modes.remove(at: index)
        return s
    }

    /// The standard ladder for the draft's aspect, HiDPI flag, orientation and refresh rate.
    package static func fillingSizes(_ spec: VirtualScreenSpec, soc: SoCClass) -> VirtualScreenSpec {
        var s = spec
        s.modes = VirtualScreenSpec.ladder(aspectWidth: spec.aspectWidth, aspectHeight: spec.aspectHeight, hiDPI: spec.hiDPI,
                                           soc: soc, portrait: spec.portrait, refreshMilliHz: refreshMilliHz(spec))
        return s
    }
}
