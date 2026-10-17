import Foundation

// Resolution settings (owner: D). PLAN §9.1, §4.3, R5.3.

// "Confirm resolution changes" (§4.3) is B's `SafetyConfig.confirmResolution`: the queue's
// RiskClassifier reads it, so there is exactly one setting.

package enum SliderLabelStyle: String, Codable, CaseIterable, Sendable { case percent, size }

package enum ModeDPIFilter: String, Codable, CaseIterable, Sendable { case all, hiDPIOnly, loDPIOnly }

package struct ResolutionConfig: ConfigModel {
    /// Offer modes under 720p lines.
    package var allowBelow720p: Bool
    package var sliderLabel: SliderLabelStyle
    /// Snap the slider to favorite, current, default and native (⌥ bypasses).
    package var sliderSnapping: Bool
    /// Only modes with the panel's native aspect ratio on the slider.
    package var sliderNativeAspectOnly: Bool
    /// Apply the persisted choice through the ConnectPlanner (step 4).
    package var persistedChoice: Bool
    /// UI-size match tolerance (fraction).
    package var scaleMatchTolerance: Double
    /// Reference display for "Match UI size" (nil = main).
    package var scaleMatchReference: DisplayKey?

    package static let maxUndo = 10

    package init() {
        allowBelow720p = false
        sliderLabel = .size
        sliderSnapping = true
        sliderNativeAspectOnly = true
        persistedChoice = true
        scaleMatchTolerance = 0.10
        scaleMatchReference = nil
    }

    private enum CodingKeys: String, CodingKey {
        case allowBelow720p, sliderLabel, sliderSnapping, sliderNativeAspectOnly, persistedChoice,
             scaleMatchTolerance, scaleMatchReference
    }

    package init(from decoder: Decoder) throws {
        let d = ResolutionConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowBelow720p = c.lossy(.allowBelow720p, d.allowBelow720p)
        sliderLabel = c.lossy(.sliderLabel, d.sliderLabel)
        sliderSnapping = c.lossy(.sliderSnapping, d.sliderSnapping)
        sliderNativeAspectOnly = c.lossy(.sliderNativeAspectOnly, d.sliderNativeAspectOnly)
        persistedChoice = c.lossy(.persistedChoice, d.persistedChoice)
        scaleMatchTolerance = c.lossy(.scaleMatchTolerance, d.scaleMatchTolerance)
        scaleMatchReference = c.lossy(.scaleMatchReference, nil)
    }

    package func sanitized() -> ResolutionConfig {
        var c = self
        c.scaleMatchTolerance = scaleMatchTolerance.isFinite ? min(0.5, max(0.01, scaleMatchTolerance)) : 0.10
        return c
    }
}

/// A favorite mode (parity §2.7): matched on size + HiDPI + refresh.
package struct FavoriteMode: Codable, Hashable, Sendable {
    /// Points.
    package var width: Int
    package var height: Int
    package var hiDPI: Bool
    package var refreshMilliHz: Int

    package init(width: Int, height: Int, hiDPI: Bool, refreshMilliHz: Int) {
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
        self.refreshMilliHz = refreshMilliHz
    }

    package init(_ mode: ModeRef) {
        self.init(width: mode.pointWidth, height: mode.pointHeight, hiDPI: mode.isHiDPI, refreshMilliHz: mode.refreshMilliHz)
    }

    /// The live mode this favorite refers to (refresh may differ by < 0.5 Hz).
    package func resolve(in modes: [ModeRef]) -> ModeRef? {
        let same = modes.filter { $0.pointWidth == width && $0.pointHeight == height && $0.isHiDPI == hiDPI }
        return same.first { abs($0.refreshMilliHz - refreshMilliHz) < 500 }
            ?? (refreshMilliHz == 0 ? same.first : nil)
    }

    package var label: String { "\(width) × \(height)" + (hiDPI ? " HiDPI" : "") }
}

/// The mode the user chose, with the mode it replaced (R5.3, §4.11 step 4).
package struct PersistedModeChoice: Codable, Equatable, Sendable {
    package var mode: ModeRef
    /// The mode before Keep: the planner restores `mode` only while the display still shows this.
    package var preKeepMode: ModeRef
    /// Wall-clock seconds (UI only).
    package var recordedAt: Double

    package init(mode: ModeRef, preKeepMode: ModeRef, recordedAt: Double) {
        self.mode = mode
        self.preKeepMode = preKeepMode
        self.recordedAt = recordedAt
    }
}

package struct PerDisplayResolution: ConfigModel {
    package var favorites: [FavoriteMode]
    /// Range limit for the slider and shortcuts (points). Nil = no limit.
    package var minWidth: Int?
    package var maxWidth: Int?
    package var dpiFilter: ModeDPIFilter
    /// Only this refresh (milli-Hz) in the mode list; nil = all.
    package var refreshFilter: Int?
    /// Only this bit depth in the mode list; nil = all.
    package var bitDepthFilter: Int?
    package var persisted: PersistedModeChoice?
    /// Take part in "Match UI size".
    package var matchUIScale: Bool

    package static let maxFavorites = 5

    package init() {
        favorites = []
        minWidth = nil
        maxWidth = nil
        dpiFilter = .all
        refreshFilter = nil
        bitDepthFilter = nil
        persisted = nil
        matchUIScale = true
    }

    private enum CodingKeys: String, CodingKey {
        case favorites, minWidth, maxWidth, dpiFilter, refreshFilter, bitDepthFilter, persisted, matchUIScale
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? c.decodeIfPresent(TolerantArray<FavoriteMode>.self, forKey: .favorites))?.values ?? []
        minWidth = c.lossy(.minWidth, nil)
        maxWidth = c.lossy(.maxWidth, nil)
        dpiFilter = c.lossy(.dpiFilter, .all)
        refreshFilter = c.lossy(.refreshFilter, nil)
        bitDepthFilter = c.lossy(.bitDepthFilter, nil)
        persisted = c.lossy(.persisted, nil)
        matchUIScale = c.lossy(.matchUIScale, true)
    }

    package func sanitized() -> PerDisplayResolution {
        var c = self
        var seen = Set<FavoriteMode>()
        c.favorites = favorites.filter { f in
            f.width > 0 && f.height > 0 && f.width <= 16384 && f.height <= 16384 && f.refreshMilliHz >= 0
                && f.refreshMilliHz <= 1_000_000 && seen.insert(f).inserted
        }
        if c.favorites.count > Self.maxFavorites { c.favorites = Array(c.favorites.prefix(Self.maxFavorites)) }
        c.minWidth = minWidth.map { min(16384, max(320, $0)) }
        c.maxWidth = maxWidth.map { min(16384, max(320, $0)) }
        if let lo = c.minWidth, let hi = c.maxWidth, lo > hi { c.minWidth = hi; c.maxWidth = lo }
        if let r = refreshFilter, r <= 0 || r > 1_000_000 { c.refreshFilter = nil }
        if let b = bitDepthFilter, ![8, 10, 16, 30, 32].contains(b) { c.bitDepthFilter = nil }
        if let p = persisted, p.mode.pointWidth <= 0 || p.preKeepMode.pointWidth <= 0 { c.persisted = nil }
        return c
    }

    /// Whether a mode passes the range limit.
    package func inRange(_ mode: ModeRef) -> Bool {
        if let lo = minWidth, mode.pointWidth < lo { return false }
        if let hi = maxWidth, mode.pointWidth > hi { return false }
        return true
    }
}
