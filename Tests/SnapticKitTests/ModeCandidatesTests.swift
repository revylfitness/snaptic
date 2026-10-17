import XCTest
@testable import SnapticKit

final class ModeCandidatesTests: XCTestCase {
    private func d(_ w: Int, _ h: Int, hidpi: Bool = false, hz: Int = 60, native: Bool = false, def: Bool = false,
                   usable: Bool = true, cgs: Int32? = nil) -> DisplayModeDescriptor {
        DisplayModeDescriptor(ref: BLayout.mode(w, h, hidpi: hidpi, hz: hz, id: Int32(w)), isNative: native, isDefault: def,
                              isUsableForDesktop: usable, ioFlags: 0, bitDepth: 8, cgsModeNumber: cgs)
    }

    private var sample: [DisplayModeDescriptor] {
        [d(2560, 1440, native: true), d(2560, 1440, hz: 144), d(1280, 720, hidpi: true, def: true), d(1280, 720),
         d(1920, 1080), d(1920, 1080, hidpi: true), d(1024, 768), d(800, 600, usable: false), d(3008, 1692, usable: false, cgs: 9)]
    }

    func testNativeAndDefault() {
        XCTAssertEqual(ModeCandidates.native(sample)?.ref.pointWidth, 2560)
        XCTAssertEqual(ModeCandidates.defaultMode(sample)?.ref.pointWidth, 1280)
        XCTAssertEqual(ModeCandidates.native([d(1024, 768), d(1920, 1080)])?.ref.pointWidth, 1920, "largest when unflagged")
        XCTAssertNil(ModeCandidates.native([]))
    }

    func testSliderOneStopPerSizePreferringHiDPIAndNativeAspect() {
        let stops = ModeCandidates.slider(sample, current: BLayout.mode(2560, 1440))
        XCTAssertEqual(stops.map(\.ref.pointWidth), [1280, 1920, 2560], "4:3 and unusable modes are dropped")
        XCTAssertTrue(stops[0].isHiDPI && stops[1].isHiDPI)
        XCTAssertEqual(stops[2].ref.refreshMilliHz, 60000, "closest to the current refresh")
        let never = ModeCandidates.slider(sample, current: nil, options: SliderOptions(hiDPI: .never))
        XCTAssertTrue(never.allSatisfy { !$0.isHiDPI })
        let only = ModeCandidates.slider(sample, current: nil, options: SliderOptions(hiDPI: .only))
        XCTAssertEqual(only.map(\.ref.pointWidth), [1280, 1920])
        let all = ModeCandidates.slider(sample, current: nil, options: SliderOptions(nativeAspectOnly: false, includeHidden: true))
        XCTAssertEqual(all.map(\.ref.pointWidth), [1024, 1280, 1920, 2560, 3008])
        let limited = ModeCandidates.slider(sample, current: nil, options: SliderOptions(minPointWidth: 1300, maxPointWidth: 2000))
        XCTAssertEqual(limited.map(\.ref.pointWidth), [1920])
    }

    func testPositions() {
        let stops = ModeCandidates.slider(sample, current: nil)
        XCTAssertEqual(ModeCandidates.index(of: BLayout.mode(1920, 1080), in: stops), 1)
        XCTAssertEqual(ModeCandidates.index(of: BLayout.mode(2000, 1125), in: stops), 1, "nearest")
        XCTAssertEqual(ModeCandidates.stop(at: 0, in: stops)?.ref.pointWidth, 1280)
        XCTAssertEqual(ModeCandidates.stop(at: 1, in: stops)?.ref.pointWidth, 2560)
        XCTAssertEqual(ModeCandidates.stop(at: .nan, in: stops)?.ref.pointWidth, 1280)
        XCTAssertEqual(ModeCandidates.stop(at: 7, in: stops)?.ref.pointWidth, 2560)
        XCTAssertEqual(ModeCandidates.fraction(of: 1, count: 3), 0.5)
        XCTAssertEqual(ModeCandidates.fraction(of: 0, count: 1), 0)
        XCTAssertNil(ModeCandidates.stop(at: 0.5, in: []))
    }

    func testGroupsVariantsAndToggle() {
        let groups = ModeCandidates.grouped(sample)
        XCTAssertEqual(groups.first?.pointWidth, 3008)
        let g2560 = groups.first { $0.pointWidth == 2560 }
        XCTAssertEqual(g2560?.modes.map(\.ref.refreshMilliHz), [144000, 60000])
        let variants = ModeCandidates.refreshVariants(of: BLayout.mode(2560, 1440), in: sample)
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(ModeCandidates.hiDPIToggle(of: BLayout.mode(1920, 1080), in: sample)?.isHiDPI, true)
        XCTAssertEqual(ModeCandidates.hiDPIToggle(of: BLayout.mode(1920, 1080, hidpi: true), in: sample)?.isHiDPI, false)
        XCTAssertNil(ModeCandidates.hiDPIToggle(of: BLayout.mode(1024, 768), in: sample))
    }

    func testFuzzSliderIsSortedAndUnique() {
        var rng = SeededGenerator(seed: 0x51DE)
        for _ in 0..<500 {
            let modes = (0..<Int(rng.next() % 30)).map { _ in
                d(Int(rng.next() % 4000) + 1, Int(rng.next() % 3000) + 1, hidpi: rng.next() % 2 == 0,
                  hz: [30, 60, 120][Int(rng.next() % 3)], native: rng.next() % 10 == 0, usable: rng.next() % 5 != 0)
            }
            let stops = ModeCandidates.slider(modes, current: modes.first?.ref,
                                              options: SliderOptions(nativeAspectOnly: rng.next() % 2 == 0))
            let sizes = stops.map { "\($0.ref.pointWidth)x\($0.ref.pointHeight)" }
            XCTAssertEqual(Set(sizes).count, sizes.count)
            XCTAssertEqual(stops.map(\.ref.pointWidth), stops.map(\.ref.pointWidth).sorted())
            XCTAssertTrue(stops.allSatisfy(\.isUsableForDesktop))
        }
    }
}
