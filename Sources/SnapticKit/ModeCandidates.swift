import Foundation

// Resolution slider candidates and mode grouping (owner: B). PLAN §5 "slider candidates in Kit".

package enum HiDPIPreference: String, Codable, CaseIterable, Sendable {
    /// One stop per point size: the HiDPI variant when one exists.
    case prefer
    /// Only HiDPI modes.
    case only
    /// Only 1× modes.
    case never
}

/// Options for the resolution slider.
package struct SliderOptions: Equatable, Sendable {
    package var hiDPI: HiDPIPreference
    /// Keep only modes with the native aspect ratio (±1.5%).
    package var nativeAspectOnly: Bool
    package var minPointWidth: Int
    package var maxPointWidth: Int
    /// Include hidden (CGS) modes.
    package var includeHidden: Bool

    package init(hiDPI: HiDPIPreference = .prefer, nativeAspectOnly: Bool = true, minPointWidth: Int = 0,
                 maxPointWidth: Int = Int.max, includeHidden: Bool = false) {
        self.hiDPI = hiDPI
        self.nativeAspectOnly = nativeAspectOnly
        self.minPointWidth = minPointWidth
        self.maxPointWidth = maxPointWidth
        self.includeHidden = includeHidden
    }
}

/// Modes that share a point size (refresh-rate and HiDPI variants).
package struct ModeGroup: Equatable, Sendable {
    package var pointWidth: Int
    package var pointHeight: Int
    package var modes: [DisplayModeDescriptor]
}

package enum ModeCandidates {
    /// The panel's native mode: the flagged one, else the largest pixel area 1× usable mode.
    package static func native(_ modes: [DisplayModeDescriptor]) -> DisplayModeDescriptor? {
        if let flagged = modes.first(where: { $0.isNative && $0.cgsModeNumber == nil }) { return flagged }
        return modes.filter { $0.isUsableForDesktop }.max { a, b in
            let pa = a.ref.pixelWidth * a.ref.pixelHeight, pb = b.ref.pixelWidth * b.ref.pixelHeight
            return pa != pb ? pa < pb : a.ref.refreshMilliHz < b.ref.refreshMilliHz
        }
    }

    /// The default mode macOS picks (flagged), else native.
    package static func defaultMode(_ modes: [DisplayModeDescriptor]) -> DisplayModeDescriptor? {
        modes.first { $0.isDefault && $0.cgsModeNumber == nil } ?? native(modes)
    }

    /// Modes grouped by point size, largest first; each group sorted HiDPI-first, then by refresh (high first).
    package static func grouped(_ modes: [DisplayModeDescriptor]) -> [ModeGroup] {
        var order: [String] = []
        var groups: [String: ModeGroup] = [:]
        for m in modes {
            let k = "\(m.ref.pointWidth)x\(m.ref.pointHeight)"
            if groups[k] == nil {
                order.append(k)
                groups[k] = ModeGroup(pointWidth: m.ref.pointWidth, pointHeight: m.ref.pointHeight, modes: [])
            }
            groups[k]?.modes.append(m)
        }
        return order.compactMap { groups[$0] }
            .map { g in
                var g = g
                g.modes.sort { a, b in
                    if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
                    return a.ref.refreshMilliHz > b.ref.refreshMilliHz
                }
                return g
            }
            .sorted { a, b in
                a.pointWidth != b.pointWidth ? a.pointWidth > b.pointWidth : a.pointHeight > b.pointHeight
            }
    }

    /// Slider stops, smallest point size first: one mode per point size, at the refresh rate
    /// closest to `current`'s (or native's), honoring the HiDPI and aspect options.
    package static func slider(_ modes: [DisplayModeDescriptor], current: ModeRef?,
                               options: SliderOptions = SliderOptions()) -> [DisplayModeDescriptor] {
        let usable = modes.filter { m in
            (m.isUsableForDesktop || (options.includeHidden && m.cgsModeNumber != nil))
                && m.ref.pointWidth >= options.minPointWidth && m.ref.pointWidth <= options.maxPointWidth
                && m.ref.pointWidth > 0 && m.ref.pointHeight > 0
        }
        let nat = native(modes)
        let targetRefresh = current?.refreshMilliHz ?? nat?.ref.refreshMilliHz ?? 0
        let nativeAspect = nat?.aspect ?? 0
        var stops: [DisplayModeDescriptor] = []
        for group in grouped(usable) {
            var candidates = group.modes
            if options.nativeAspectOnly, nativeAspect > 0 {
                let a = Double(group.pointWidth) / Double(group.pointHeight)
                if abs(a - nativeAspect) / nativeAspect > 0.015 { continue }
            }
            switch options.hiDPI {
            case .only: candidates = candidates.filter(\.isHiDPI)
            case .never: candidates = candidates.filter { !$0.isHiDPI }
            case .prefer:
                if candidates.contains(where: \.isHiDPI) { candidates = candidates.filter(\.isHiDPI) }
            }
            // Prefer public modes over hidden duplicates, then the closest refresh, then higher refresh.
            let best = candidates.min { a, b in
                if (a.cgsModeNumber == nil) != (b.cgsModeNumber == nil) { return a.cgsModeNumber == nil }
                let da = abs(a.ref.refreshMilliHz - targetRefresh), db = abs(b.ref.refreshMilliHz - targetRefresh)
                return da != db ? da < db : a.ref.refreshMilliHz > b.ref.refreshMilliHz
            }
            if let best { stops.append(best) }
        }
        return stops.sorted { a, b in
            a.ref.pointWidth != b.ref.pointWidth ? a.ref.pointWidth < b.ref.pointWidth : a.ref.pointHeight < b.ref.pointHeight
        }
    }

    /// Index of the stop for `mode` (same point size), else the nearest by point width.
    package static func index(of mode: ModeRef?, in stops: [DisplayModeDescriptor]) -> Int? {
        guard !stops.isEmpty else { return nil }
        guard let mode else { return nil }
        if let i = stops.firstIndex(where: { $0.ref.pointWidth == mode.pointWidth && $0.ref.pointHeight == mode.pointHeight }) {
            return i
        }
        return stops.indices.min { abs(stops[$0].ref.pointWidth - mode.pointWidth) < abs(stops[$1].ref.pointWidth - mode.pointWidth) }
    }

    /// The stop for a slider position in 0…1.
    package static func stop(at fraction: Double, in stops: [DisplayModeDescriptor]) -> DisplayModeDescriptor? {
        guard !stops.isEmpty else { return nil }
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let i = Int((f * Double(stops.count - 1)).rounded())
        return stops[min(max(i, 0), stops.count - 1)]
    }

    /// The slider position (0…1) of a stop index.
    package static func fraction(of index: Int, count: Int) -> Double {
        count > 1 ? Double(min(max(index, 0), count - 1)) / Double(count - 1) : 0
    }

    /// Refresh-rate variants of `mode` (same pixel and point size), high first.
    package static func refreshVariants(of mode: ModeRef, in modes: [DisplayModeDescriptor]) -> [DisplayModeDescriptor] {
        modes.filter {
            $0.ref.pixelWidth == mode.pixelWidth && $0.ref.pixelHeight == mode.pixelHeight
                && $0.ref.pointWidth == mode.pointWidth && $0.ref.pointHeight == mode.pointHeight
        }.sorted { $0.ref.refreshMilliHz > $1.ref.refreshMilliHz }
    }

    /// The HiDPI (or 1×) twin of `mode` at the same point size and refresh, if any.
    package static func hiDPIToggle(of mode: ModeRef, in modes: [DisplayModeDescriptor]) -> DisplayModeDescriptor? {
        let wantHiDPI = !mode.isHiDPI
        return modes.filter {
            $0.ref.pointWidth == mode.pointWidth && $0.ref.pointHeight == mode.pointHeight && $0.isHiDPI == wantHiDPI
                && $0.isUsableForDesktop
        }.min { abs($0.ref.refreshMilliHz - mode.refreshMilliHz) < abs($1.ref.refreshMilliHz - mode.refreshMilliHz) }
    }
}
