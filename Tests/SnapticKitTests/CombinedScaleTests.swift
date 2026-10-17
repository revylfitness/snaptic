import XCTest
@testable import SnapticKit

final class CombinedScaleTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(CombinedScale.defaultSwitchover(hardware: .apple, xdrOn: false), 0.25)
        XCTAssertEqual(CombinedScale.defaultSwitchover(hardware: .ddc, xdrOn: false), 0)
        XCTAssertEqual(CombinedScale.defaultSwitchover(hardware: .apple, xdrOn: true), 0.2)
        XCTAssertEqual(CombinedScale.defaultSwitchover(hardware: nil, xdrOn: false), 0)
    }

    func testCombinedSplit() {
        let s = CombinedScale(hasHardware: true, hasSoftware: true, switchover: 0.25, minHardware: 0.1, softwareFloor: 0.08)
        XCTAssertEqual(s.split(1).hardware ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(s.split(1).software, 1)
        XCTAssertEqual(s.split(0.25), .init(hardware: 0.1, software: 1, xdr: 1))
        let low = s.split(0)
        XCTAssertEqual(low.hardware, 0.1)
        XCTAssertEqual(low.software, 0.08, accuracy: 1e-12)
        let mid = s.split(0.125)
        XCTAssertEqual(mid.software, 0.54, accuracy: 1e-9)
        XCTAssertEqual(s.split(0.625).hardware ?? 0, 0.1 + 0.5 * 0.9, accuracy: 1e-9)
    }

    func testPureHardwareAndPureSoftware() {
        let hw = CombinedScale(hasHardware: true, hasSoftware: true, switchover: 0)
        XCTAssertFalse(hw.isCombined)
        XCTAssertEqual(hw.split(0.3), .init(hardware: 0.3, software: 1, xdr: 1))
        let hwOnly = CombinedScale(hasHardware: true, hasSoftware: false, switchover: 0.5)
        XCTAssertEqual(hwOnly.split(0), .init(hardware: 0, software: 1, xdr: 1))
        let sw = CombinedScale(hasHardware: false, hasSoftware: true, switchover: 0.25, softwareFloor: 0)
        XCTAssertEqual(sw.split(0.4), .init(hardware: nil, software: 0.4, xdr: 1))
    }

    func testXDRRange() {
        let s = CombinedScale(hasHardware: true, hasSoftware: true, switchover: 0.2, xdrMax: 1.6)
        XCTAssertEqual(s.range, 0...1.6)
        XCTAssertEqual(s.split(1.4), .init(hardware: 1, software: 1, xdr: 1.4))
        XCTAssertEqual(s.split(9).xdr, 1.6)
        XCTAssertEqual(CombinedScale(hasHardware: true, hasSoftware: false, switchover: 0, xdrMax: 99).xdrMax, 4)
        XCTAssertEqual(s.snapMarks, [0.2, 1])
    }

    func testInverseRoundTrips() {
        var rng = SeededGenerator(seed: 0x5CA1E)
        for _ in 0..<2_000 {
            let hasHW = rng.next() % 4 != 0
            let hasSW = !hasHW || rng.next() % 2 == 0
            let s = CombinedScale(hasHardware: hasHW, hasSoftware: hasSW,
                                  switchover: Double(rng.next() % 90) / 100,
                                  minHardware: Double(rng.next() % 50) / 100,
                                  softwareFloor: rng.next() % 2 == 0 ? 0.08 : 0,
                                  xdrMax: rng.next() % 3 == 0 ? 1.6 : 1)
            let p = Double(rng.next() % 10_000) / 10_000 * s.xdrMax
            let out = s.split(p)
            XCTAssertEqual(s.position(hardware: out.hardware, software: out.software, xdr: out.xdr), p, accuracy: 1e-6,
                           "\(s) at \(p)")
            XCTAssertGreaterThanOrEqual(out.software, s.softwareFloor - 1e-12)
            if let h = out.hardware { XCTAssertGreaterThanOrEqual(h, s.minHardware - 1e-12) }
        }
    }

    func testSplitIsMonotonic() {
        let s = CombinedScale(hasHardware: true, hasSoftware: true, switchover: 0.3, minHardware: 0.2, xdrMax: 2)
        var last = s.split(0)
        for i in 1...200 {
            let out = s.split(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(out.software, last.software)
            XCTAssertGreaterThanOrEqual(out.hardware ?? 0, last.hardware ?? 0)
            XCTAssertGreaterThanOrEqual(out.xdr, last.xdr)
            last = out
        }
    }

    func testSnapping() {
        let s = CombinedScale(hasHardware: true, hasSoftware: true, switchover: 0.25, xdrMax: 1.5)
        XCTAssertEqual(s.snapped(0.26), 0.25)
        XCTAssertEqual(s.snapped(0.995), 1)
        XCTAssertEqual(s.snapped(0.5), 0.5)
        XCTAssertEqual(s.snapped(-1), 0)
    }

    func testDetentNeedsASecondPress() {
        let first = CombinedScale.applyDetent(from: 0.95, to: 1.05, armed: false)
        XCTAssertEqual(first.value, 1)
        XCTAssertTrue(first.armDetent)
        let second = CombinedScale.applyDetent(from: 1, to: 1.06, armed: true)
        XCTAssertEqual(second.value, 1.06)
        let down = CombinedScale.applyDetent(from: 1.1, to: 0.9, armed: false)
        XCTAssertEqual(down.value, 1)
        XCTAssertEqual(CombinedScale.applyDetent(from: 0.5, to: 0.6, armed: false).value, 0.6)
    }

    func testNonFiniteInputsAreClamped() {
        let s = CombinedScale(hasHardware: true, hasSoftware: true, switchover: .nan, minHardware: .infinity, xdrMax: .nan)
        XCTAssertEqual(s.switchover, 0)
        XCTAssertEqual(s.xdrMax, 1)
        XCTAssertEqual(s.split(.nan).software, 1)
    }
}
