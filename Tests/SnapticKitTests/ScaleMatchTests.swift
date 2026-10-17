import XCTest
@testable import SnapticKit

final class ScaleMatchTests: XCTestCase {
    private func key(_ c: Character) -> DisplayKey { DisplayKey(rawValue: String(repeating: c, count: 32))! }
    private func mode(_ w: Int, _ h: Int, hiDPI: Bool = true, hz: Int = 60_000) -> ModeRef {
        ModeRef(ioModeID: Int32(w), pixelWidth: hiDPI ? w * 2 : w, pixelHeight: hiDPI ? h * 2 : h, pointWidth: w, pointHeight: h,
                refreshMilliHz: hz)
    }

    func testMMPerPoint() {
        XCTAssertEqual(ScaleMatch.mmPerPoint(widthMM: 300, mode: mode(1500, 1000))!, 0.2, accuracy: 1e-9)
        XCTAssertNil(ScaleMatch.mmPerPoint(widthMM: 0, mode: mode(1500, 1000)))
        XCTAssertNil(ScaleMatch.mmPerPoint(widthMM: .nan, mode: mode(1500, 1000)))
    }

    func testPlanMatchesPhysicalSize() {
        // Reference: 14" laptop, 302 mm wide at 1512 points ≈ 0.2 mm/pt.
        let laptop = ScaleMatchDisplay(key: key("a"), widthMM: 302, current: mode(1512, 982), candidates: [mode(1512, 982)])
        // 27" 4K, 597 mm wide; at 1920 pt it is 0.31 mm/pt (too big). 2560 → 0.233, 3008 → 0.198.
        let candidates = [mode(1920, 1080), mode(2560, 1440), mode(3008, 1692), mode(3840, 2160, hiDPI: false)]
        let external = ScaleMatchDisplay(key: key("b"), widthMM: 597, current: mode(1920, 1080), candidates: candidates)
        let plan = ScaleMatch.plan(reference: laptop, targets: [laptop, external])
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.to, mode(3008, 1692))
        XCTAssertEqual(plan.first?.key, key("b"))
        XCTAssertEqual(plan.first!.ratio, 1.0, accuracy: 0.02)
    }

    func testWithinToleranceNoProposal() {
        let a = ScaleMatchDisplay(key: key("a"), widthMM: 300, current: mode(1500, 1000), candidates: [])
        let b = ScaleMatchDisplay(key: key("b"), widthMM: 310, current: mode(1500, 1000), candidates: [mode(1600, 1000)])
        XCTAssertTrue(ScaleMatch.plan(reference: a, targets: [b]).isEmpty)
    }

    func testPrefersSameHiDPIClassAndRefresh() {
        let pick = ScaleMatch.bestMode(targetMMPerPoint: 0.2, widthMM: 400, current: mode(2000, 1000),
                                       candidates: [mode(2000, 1000, hiDPI: false), mode(2000, 1000), mode(2000, 1000, hz: 120_000)])
        XCTAssertEqual(pick?.mode, mode(2000, 1000))
    }

    func testNoCandidates() {
        XCTAssertNil(ScaleMatch.bestMode(targetMMPerPoint: 0.2, widthMM: 400, current: mode(2000, 1000), candidates: []))
        XCTAssertNil(ScaleMatch.bestMode(targetMMPerPoint: 0, widthMM: 400, current: mode(2000, 1000), candidates: [mode(1, 1)]))
    }

    func testFuzzNeverProposesWorse() {
        var rng = SeededGenerator(seed: 0x5CA1E)
        for _ in 0..<2000 {
            let refW = 200 + Int(rng.next() % 500)
            let ref = ScaleMatchDisplay(key: key("a"), widthMM: Double(refW), current: mode(1000 + Int(rng.next() % 2000), 900),
                                        candidates: [])
            var cands: [ModeRef] = []
            for _ in 0..<(1 + Int(rng.next() % 8)) { cands.append(mode(640 + Int(rng.next() % 4000), 600, hiDPI: rng.next() % 2 == 0)) }
            let t = ScaleMatchDisplay(key: key("b"), widthMM: Double(200 + Int(rng.next() % 900)), current: cands[0], candidates: cands)
            for p in ScaleMatch.plan(reference: ref, targets: [t]) {
                let refMM = ScaleMatch.mmPerPoint(widthMM: ref.widthMM, mode: ref.current)!
                let before = abs(log(ScaleMatch.mmPerPoint(widthMM: t.widthMM, mode: p.from)! / refMM))
                let after = abs(log(ScaleMatch.mmPerPoint(widthMM: t.widthMM, mode: p.to)! / refMM))
                XCTAssertLessThan(after, before)
                XCTAssertTrue(cands.contains(p.to))
            }
        }
    }
}
