import Foundation

// The resolutions a display submenu lists (PLAN 0.3 §5.2, owner: D): at most eight concrete modes — the current
// one, the default, the favorites, then evenly spaced recommended sizes — largest first. "Default" marks the default
// mode; "More Space" and "Larger Text" are subtitles on the largest and smallest listed sizes only (r3 product
// minor 10). Everything else is in Settings › Displays › Resolution ("More Resolutions…").

/// The subtitle a listed mode carries.
package enum ResolutionMenuRole: String, Equatable, Sendable {
    case defaultMode, moreSpace, largerText
}

package struct ResolutionMenuPick: Equatable, Sendable {
    package var mode: ModeRef
    package var isCurrent: Bool
    package var isFavorite: Bool
    package var role: ResolutionMenuRole?

    package init(mode: ModeRef, isCurrent: Bool, isFavorite: Bool, role: ResolutionMenuRole?) {
        self.mode = mode
        self.isCurrent = isCurrent
        self.isFavorite = isFavorite
        self.role = role
    }
}

package enum ResolutionMenuPicks {
    /// Most modes a display submenu lists (§5.2).
    package static let limit = 8
    /// Aspect ratios within this fraction count as the same shape ("native aspect").
    package static let aspectTolerance = 0.01

    /// One size per point shape (width × height × HiDPI); the refresh closest to the current mode's wins, and the
    /// current mode always represents its own shape.
    private struct Shape: Hashable {
        let width: Int, height: Int, hiDPI: Bool
        init(_ m: ModeRef) { width = m.pointWidth; height = m.pointHeight; hiDPI = m.isHiDPI }
    }

    /// `modes` is the display's filtered public list (any order); `current` the mode in use (listed even when it is
    /// missing from `modes`); `favorites` the display's favorites. At most `limit` picks, largest first.
    package static func picks(modes: [DisplayModeDescriptor], current: ModeRef?, favorites: [FavoriteMode],
                              limit: Int = limit) -> [ResolutionMenuPick] {
        let cap = max(0, limit)
        guard cap > 0 else { return [] }
        let usable = modes.filter { $0.ref.pointWidth > 0 && $0.ref.pointHeight > 0 }
        let defaultMode = usable.first(where: \.isDefault)?.ref
        let refresh = current?.refreshMilliHz ?? defaultMode?.refreshMilliHz ?? usable.map(\.ref.refreshMilliHz).max() ?? 0

        // Representatives per shape.
        var best: [Shape: ModeRef] = [:]
        var defaultShapes = Set<Shape>()
        for d in usable {
            let shape = Shape(d.ref)
            if d.isDefault { defaultShapes.insert(shape) }
            if let existing = best[shape] {
                if existing == current { continue }
                let better = d.ref == current
                    || abs(d.ref.refreshMilliHz - refresh) < abs(existing.refreshMilliHz - refresh)
                    || (abs(d.ref.refreshMilliHz - refresh) == abs(existing.refreshMilliHz - refresh)
                        && d.ref.refreshMilliHz > existing.refreshMilliHz)
                if better { best[shape] = d.ref }
            } else {
                best[shape] = d.ref
            }
        }
        if let current, current.pointWidth > 0, current.pointHeight > 0 { best[Shape(current)] = current }

        var chosen: [Shape] = []
        func choose(_ shape: Shape?) {
            guard let shape, best[shape] != nil, !chosen.contains(shape), chosen.count < cap else { return }
            chosen.append(shape)
        }
        choose(current.map(Shape.init))
        choose(defaultMode.map(Shape.init))
        let all = Array(best.values)
        var favoriteShapes = Set<Shape>()
        for f in favorites {
            guard let resolved = f.resolve(in: all) ?? f.resolve(in: usable.map(\.ref)) else { continue }
            favoriteShapes.insert(Shape(resolved))
            choose(Shape(resolved))
        }

        // Recommended: the current (else default) HiDPI class and aspect, evenly spaced, extremes first.
        let reference = [current, defaultMode].compactMap { $0 }.first { $0.pointWidth > 0 && $0.pointHeight > 0 }
            ?? all.max { $0.pointWidth < $1.pointWidth }
        if let reference, chosen.count < cap {
            let aspect = Double(reference.pointWidth) / Double(reference.pointHeight)
            let candidates = best.keys.filter { s in
                s.hiDPI == reference.isHiDPI
                    && abs(Double(s.width) / Double(s.height) - aspect) <= aspect * aspectTolerance
            }.sorted { ($0.width, $0.height) < ($1.width, $1.height) }
            // The extremes of the class come first (they carry the subtitles), then the interior evenly.
            let open = candidates.filter { !chosen.contains($0) }
            for index in spreadIndices(count: open.count, take: cap - chosen.count) { choose(open[index]) }
        }

        var result = chosen.compactMap { shape -> ResolutionMenuPick? in
            guard let mode = best[shape] else { return nil }
            return ResolutionMenuPick(mode: mode, isCurrent: mode == current, isFavorite: favoriteShapes.contains(shape),
                                      role: defaultShapes.contains(shape) ? .defaultMode : nil)
        }
        result.sort { a, b in
            if a.mode.pointWidth != b.mode.pointWidth { return a.mode.pointWidth > b.mode.pointWidth }
            if a.mode.pointHeight != b.mode.pointHeight { return a.mode.pointHeight > b.mode.pointHeight }
            return a.mode.isHiDPI && !b.mode.isHiDPI
        }
        if result.count >= 2 {
            if result[0].role == nil { result[0].role = .moreSpace }
            if result[result.count - 1].role == nil { result[result.count - 1].role = .largerText }
        }
        return result
    }

    /// `take` indices spread over `0..<count`: both ends first, then the interior evenly. Unique, in ascending order.
    package static func spreadIndices(count: Int, take: Int) -> [Int] {
        guard count > 0, take > 0 else { return [] }
        if take >= count { return Array(0..<count) }
        if take == 1 { return [count - 1] }
        var picked = Set<Int>()
        for k in 0..<take {
            let position = Double(k) * Double(count - 1) / Double(take - 1)
            picked.insert(Int(position.rounded()))
        }
        // Rounding can collide on small lists: fill from the nearest free slots, deterministically.
        var next = 0
        while picked.count < take, next < count {
            picked.insert(next)
            next += 1
        }
        return picked.sorted()
    }
}

/// The discrete resolution slider (menu row and Settings, PLAN 0.3 §4.3 / §5.2): its value is an index into the
/// stops (smallest first), so every position is a real mode and the value text is that mode ("1512 × 982").
package enum ResolutionSliderStops {
    /// The stop whose width is closest to `width` (the lower one on a tie), or nil with no stops.
    package static func nearestIndex(width: Int, in widths: [Int]) -> Int? {
        guard !widths.isEmpty else { return nil }
        var best = 0
        var bestDistance = UInt.max
        for (i, w) in widths.enumerated() {
            // The exact distance: a wrapped difference of two Ints, read as UInt, never overflows.
            let distance = UInt(bitPattern: w >= width ? w &- width : width &- w)
            if i == 0 || distance < bestDistance {
                best = i
                bestDistance = distance
            }
        }
        return best
    }

    /// A slider position (any Double, also NaN or out of range) as a valid stop index, or nil with no stops.
    package static func index(_ position: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard position.isFinite else { return 0 }
        let rounded = position.rounded()
        if rounded <= 0 { return 0 }
        if rounded >= Double(count - 1) { return count - 1 }
        return Int(rounded)
    }

    /// The longest text (by characters; the first one on a tie), to size a value label so every stop fits.
    package static func widest(_ texts: [String]) -> String? {
        var best: String?
        var bestCount = -1
        for t in texts where t.count > bestCount {
            best = t
            bestCount = t.count
        }
        return best
    }
}
