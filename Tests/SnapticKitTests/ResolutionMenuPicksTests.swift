import XCTest
@testable import SnapticKit

final class ResolutionMenuPicksTests: XCTestCase {
    private func mode(_ w: Int, _ h: Int, hiDPI: Bool = true, hz: Int = 60_000) -> ModeRef {
        ModeRef(ioModeID: Int32(w * 10 + (hiDPI ? 1 : 0)), pixelWidth: hiDPI ? w * 2 : w, pixelHeight: hiDPI ? h * 2 : h,
                pointWidth: w, pointHeight: h, refreshMilliHz: hz)
    }

    private func desc(_ m: ModeRef, native: Bool = false, isDefault: Bool = false) -> DisplayModeDescriptor {
        DisplayModeDescriptor(ref: m, isNative: native, isDefault: isDefault, isUsableForDesktop: true, ioFlags: 0, bitDepth: 8)
    }

    /// A 14" MacBook Pro: HiDPI sizes in its aspect, the LoDPI native, and an off-aspect size.
    private var laptop: [DisplayModeDescriptor] {
        [desc(mode(1024, 665)), desc(mode(1147, 745)), desc(mode(1312, 853)), desc(mode(1512, 982), isDefault: true),
         desc(mode(1512, 982, hz: 120_000)), desc(mode(1800, 1169)), desc(mode(2056, 1336)),
         desc(mode(3024, 1964, hiDPI: false), native: true), desc(mode(1280, 800))]
    }

    func testDefaultSetupListsCurrentDefaultAndTheExtremes() {
        let current = mode(1512, 982, hz: 120_000)
        let picks = ResolutionMenuPicks.picks(modes: laptop, current: current, favorites: [])
        XCTAssertLessThanOrEqual(picks.count, ResolutionMenuPicks.limit)
        // Largest first; one entry per size; the current refresh represents its size.
        XCTAssertEqual(picks.map(\.mode.pointWidth), [2056, 1800, 1512, 1312, 1147, 1024])
        XCTAssertEqual(picks.filter(\.isCurrent).map(\.mode), [current])
        XCTAssertEqual(picks.first?.role, .moreSpace)
        XCTAssertEqual(picks.last?.role, .largerText)
        XCTAssertEqual(picks.first { $0.mode.pointWidth == 1512 }?.role, .defaultMode)
        // Off-aspect and LoDPI sizes are not recommended.
        XCTAssertFalse(picks.contains { $0.mode.pointWidth == 1280 || !$0.mode.isHiDPI })
    }

    func testFavoritesAreListedEvenOutsideTheClass() {
        let favorite = FavoriteMode(mode(1280, 800))
        let picks = ResolutionMenuPicks.picks(modes: laptop, current: mode(1512, 982), favorites: [favorite])
        let listed = picks.first { $0.mode.pointWidth == 1280 }
        XCTAssertEqual(listed?.isFavorite, true)
        XCTAssertTrue(picks.contains { $0.isCurrent })
    }

    func testLimitIsRespectedAndCurrentAlwaysListed() {
        var modes: [DisplayModeDescriptor] = []
        for w in stride(from: 800, through: 4000, by: 160) { modes.append(desc(mode(w, w * 9 / 16, hiDPI: false))) }
        let current = mode(1760, 990, hiDPI: false)
        let picks = ResolutionMenuPicks.picks(modes: modes, current: current, favorites: [], limit: 8)
        XCTAssertEqual(picks.count, 8)
        XCTAssertTrue(picks.contains { $0.isCurrent && $0.mode == current })
        XCTAssertEqual(picks.first?.mode.pointWidth, 4000)
        XCTAssertEqual(picks.last?.mode.pointWidth, 800)
    }

    func testCurrentMissingFromTheListIsStillShown() {
        let odd = mode(1600, 1040)
        let picks = ResolutionMenuPicks.picks(modes: laptop, current: odd, favorites: [])
        XCTAssertTrue(picks.contains { $0.mode == odd && $0.isCurrent })
    }

    func testEmptyAndDegenerateInput() {
        XCTAssertEqual(ResolutionMenuPicks.picks(modes: [], current: nil, favorites: []), [])
        XCTAssertEqual(ResolutionMenuPicks.picks(modes: laptop, current: nil, favorites: [], limit: 0), [])
        let single = ResolutionMenuPicks.picks(modes: [desc(mode(1920, 1080, hiDPI: false), isDefault: true)],
                                               current: mode(1920, 1080, hiDPI: false), favorites: [])
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.first?.role, .defaultMode)
        // Zero-sized modes are ignored rather than dividing by zero.
        XCTAssertEqual(ResolutionMenuPicks.picks(modes: [desc(mode(0, 0))], current: nil, favorites: []), [])
    }

    func testDefaultKeepsItsSubtitleAtTheExtremes() {
        let modes = [desc(mode(2560, 1440, hiDPI: false), isDefault: true), desc(mode(1920, 1080, hiDPI: false))]
        let picks = ResolutionMenuPicks.picks(modes: modes, current: mode(1920, 1080, hiDPI: false), favorites: [])
        XCTAssertEqual(picks.map(\.role), [.defaultMode, .largerText])
    }

    func testSpreadIndices() {
        XCTAssertEqual(ResolutionMenuPicks.spreadIndices(count: 10, take: 3), [0, 5, 9])
        XCTAssertEqual(ResolutionMenuPicks.spreadIndices(count: 3, take: 5), [0, 1, 2])
        XCTAssertEqual(ResolutionMenuPicks.spreadIndices(count: 4, take: 1), [3])
        XCTAssertEqual(ResolutionMenuPicks.spreadIndices(count: 0, take: 2), [])
        XCTAssertEqual(ResolutionMenuPicks.spreadIndices(count: 5, take: 0), [])
        for count in 1...40 {
            for take in 1...10 {
                let r = ResolutionMenuPicks.spreadIndices(count: count, take: take)
                XCTAssertEqual(r.count, min(count, take))
                XCTAssertEqual(r, Array(Set(r)).sorted())
                XCTAssertTrue(r.allSatisfy { (0..<count).contains($0) })
                if take >= 2 && count >= 2 { XCTAssertEqual(r.first, 0); XCTAssertEqual(r.last, count - 1) }
            }
        }
    }

    /// Seeded fuzz: any list keeps the invariants (≤ limit, unique sizes, sorted, current listed, roles placed right).
    func testFuzzInvariants() {
        var rng = SeededGenerator(seed: 0x5EED_0D)
        func int(_ n: Int) -> Int { Int(rng.next() % UInt64(max(1, n))) }
        for _ in 0..<500 {
            var modes: [DisplayModeDescriptor] = []
            for _ in 0..<int(30) {
                let w = int(5000) - 10, h = int(3000) - 10
                let m = mode(w, h, hiDPI: int(2) == 0, hz: [0, 50_000, 60_000, 120_000][int(4)])
                modes.append(desc(m, native: int(9) == 0, isDefault: int(9) == 0))
            }
            let current: ModeRef? = modes.isEmpty || int(5) == 0 ? nil : modes[int(modes.count)].ref
            let favorites = (0..<int(6)).compactMap { _ in modes.isEmpty ? nil : FavoriteMode(modes[int(modes.count)].ref) }
            let limit = int(10)
            let picks = ResolutionMenuPicks.picks(modes: modes, current: current, favorites: favorites, limit: limit)
            XCTAssertLessThanOrEqual(picks.count, max(0, limit))
            let shapes = picks.map { "\($0.mode.pointWidth)x\($0.mode.pointHeight)\($0.mode.isHiDPI)" }
            XCTAssertEqual(shapes.count, Set(shapes).count)
            XCTAssertEqual(picks.map(\.mode.pointWidth), picks.map(\.mode.pointWidth).sorted(by: >))
            XCTAssertTrue(picks.allSatisfy { $0.mode.pointWidth > 0 && $0.mode.pointHeight > 0 })
            if let current, current.pointWidth > 0, current.pointHeight > 0, limit > 0 {
                XCTAssertTrue(picks.contains { $0.mode == current && $0.isCurrent })
            }
            XCTAssertLessThanOrEqual(picks.filter(\.isCurrent).count, 1)
            for (i, p) in picks.enumerated() {
                if p.role == .moreSpace { XCTAssertEqual(i, 0) }
                if p.role == .largerText { XCTAssertEqual(i, picks.count - 1) }
            }
        }
    }

    // MARK: Discrete slider stops

    func testSliderNearestIndex() {
        XCTAssertNil(ResolutionSliderStops.nearestIndex(width: 1000, in: []))
        let widths = [1024, 1147, 1312, 1512, 1800]
        XCTAssertEqual(ResolutionSliderStops.nearestIndex(width: 1512, in: widths), 3)
        XCTAssertEqual(ResolutionSliderStops.nearestIndex(width: 1, in: widths), 0)
        XCTAssertEqual(ResolutionSliderStops.nearestIndex(width: 9999, in: widths), 4)
        XCTAssertEqual(ResolutionSliderStops.nearestIndex(width: 1300, in: widths), 2)
        // A tie picks the lower stop.
        XCTAssertEqual(ResolutionSliderStops.nearestIndex(width: 1100, in: [1000, 1200]), 0)
        XCTAssertEqual(ResolutionSliderStops.nearestIndex(width: Int.min, in: [Int.max, 0]), 1)
    }

    func testSliderIndexClampsAnyPosition() {
        XCTAssertNil(ResolutionSliderStops.index(2, count: 0))
        XCTAssertEqual(ResolutionSliderStops.index(-3, count: 5), 0)
        XCTAssertEqual(ResolutionSliderStops.index(1.4, count: 5), 1)
        XCTAssertEqual(ResolutionSliderStops.index(1.6, count: 5), 2)
        XCTAssertEqual(ResolutionSliderStops.index(99, count: 5), 4)
        XCTAssertEqual(ResolutionSliderStops.index(.nan, count: 5), 0)
        XCTAssertEqual(ResolutionSliderStops.index(.infinity, count: 5), 0)
        XCTAssertEqual(ResolutionSliderStops.index(0.4, count: 1), 0)
    }

    func testSliderWidestText() {
        XCTAssertNil(ResolutionSliderStops.widest([]))
        XCTAssertEqual(ResolutionSliderStops.widest(["800 × 600", "1512 × 982", "2056 × 1336", "1800 × 1169"]), "2056 × 1336")
        XCTAssertEqual(ResolutionSliderStops.widest(["ab", "cd"]), "ab")
    }

    func testSliderStopsFuzz() {
        var rng = SeededGenerator(seed: 0x5D3)
        for _ in 0..<500 {
            let count = Int.random(in: 0...12, using: &rng)
            let widths = (0..<count).map { _ in Int.random(in: 0...8000, using: &rng) }.sorted()
            let target = Int.random(in: -100...9000, using: &rng)
            if let i = ResolutionSliderStops.nearestIndex(width: target, in: widths) {
                let best = widths.map { abs($0 - target) }.min()!
                XCTAssertEqual(abs(widths[i] - target), best)
            } else {
                XCTAssertTrue(widths.isEmpty)
            }
            let position = Double.random(in: -5...20, using: &rng)
            if let i = ResolutionSliderStops.index(position, count: count) {
                XCTAssertTrue((0..<count).contains(i))
            } else {
                XCTAssertEqual(count, 0)
            }
        }
    }
}
