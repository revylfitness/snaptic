import XCTest
@testable import SnapticKit

final class VirtualScreenSpecTests: XCTestCase {
    private func spec(_ modes: [VirtualMode], hiDPI: Bool = true) -> VirtualScreenSpec {
        VirtualScreenSpec(name: "Test", aspectWidth: 16, aspectHeight: 9, sizeInches: 27, hiDPI: hiDPI, modes: modes)
    }

    func testDerivedSizes() {
        let s = spec([VirtualMode(width: 1920, height: 1080, hiDPI: true), VirtualMode(width: 2560, height: 1440, hiDPI: true)])
        XCTAssertEqual(s.initialMode, VirtualMode(width: 1920, height: 1080, hiDPI: true))
        XCTAssertEqual(s.largestMode, VirtualMode(width: 2560, height: 1440, hiDPI: true))
        XCTAssertEqual(s.maxPixels.wide, 5120)
        XCTAssertEqual(s.maxPixels.high, 2880)
        XCTAssertEqual(s.fallbackMaxPixels.wide, 3840)
        let mm = s.sizeInMillimeters
        XCTAssertEqual(mm.width, 597.7, accuracy: 0.5)
        XCTAssertEqual(mm.height, 336.2, accuracy: 0.5)
        var p = s
        p.portrait = true
        XCTAssertEqual(p.sizeInMillimeters.width, mm.height, accuracy: 1e-9)
        XCTAssertEqual(s.estimatedBackingBytes, SoCCaps.backingBytes(pixelsWide: 5120, pixelsHigh: 2880))
        XCTAssertEqual(spec([]).maxPixels.wide, 0)
    }

    func testSerialIsStableNonZero() {
        let id = StableID(UUID(uuidString: "6F1C3F9A-1D2B-4C5E-8F70-112233445566")!)
        XCTAssertEqual(VirtualScreenSpec.serial(for: id.rawValue), VirtualScreenSpec.serial(for: id.rawValue))
        XCTAssertNotEqual(VirtualScreenSpec.serial(for: "a"), VirtualScreenSpec.serial(for: "b"))
        XCTAssertNotEqual(VirtualScreenSpec.serial(for: ""), 0)
        XCTAssertEqual(VirtualScreenSpec.serial(for: ""), 0x811C_9DC5)
    }

    func testSanitizeClampsAndDropsBadModes() {
        var s = spec([
            VirtualMode(width: 100, height: 100, hiDPI: true),        // too small
            VirtualMode(width: 4000, height: 2250, hiDPI: true),      // 8000 px > 6144
            VirtualMode(width: 1920, height: 1080, hiDPI: true, refreshMilliHz: 1),
            VirtualMode(width: 1920, height: 1080, hiDPI: true, refreshMilliHz: 24_000), // duplicate after clamp
        ])
        s.name = "\u{202E}Evil\u{0007}" + String(repeating: "x", count: 100)
        s.sizeInches = .infinity
        s.aspectWidth = 0
        s.aspectHeight = 99_999
        let k = DisplayKey(rawValue: String(repeating: "c", count: 32))!
        s.associations = [VirtualAssociation(target: k), VirtualAssociation(target: k, presentation: .mirror)]
        s.primaries = VirtualPrimaries(redX: 2, redY: 0, greenX: 0, greenY: 0, blueX: 0, blueY: 0, whiteX: 0, whiteY: 0)
        let c = s.sanitized(soc: .appleEntry)
        XCTAssertEqual(c.modes, [VirtualMode(width: 1920, height: 1080, hiDPI: true, refreshMilliHz: 24_000)])
        XCTAssertFalse(c.name.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0x07 })
        XCTAssertLessThanOrEqual(c.name.unicodeScalars.count, VirtualScreenSpec.maxNameScalars)
        XCTAssertEqual(c.sizeInches, 27)
        XCTAssertEqual(c.aspectWidth, 1)
        XCTAssertEqual(c.aspectHeight, VirtualScreenSpec.maxAspectComponent)
        XCTAssertEqual(c.associations.count, 1)
        XCTAssertNil(c.primaries)
        XCTAssertEqual(c.sanitized(soc: .appleEntry), c)
    }

    func testSanitizeFallsBackToLadderAndLoDPI() {
        var s = spec([VirtualMode(width: 10, height: 10, hiDPI: true)], hiDPI: false)
        s.name = "   "
        let c = s.sanitized()
        XCTAssertFalse(c.modes.isEmpty)
        XCTAssertTrue(c.modes.allSatisfy { !$0.hiDPI })
        XCTAssertEqual(c.name, L("Virtual Screen"))
    }

    func testLadder() {
        let l = VirtualScreenSpec.ladder(aspectWidth: 16, aspectHeight: 9, hiDPI: true, soc: .appleEntry)
        XCTAssertTrue(l.contains(VirtualMode(width: 2560, height: 1440, hiDPI: true)))
        XCTAssertTrue(l.allSatisfy { $0.pixelWidth <= 6144 && $0.height >= 360 && $0.height % 2 == 0 })
        XCTAssertEqual(l.first?.width, 3008, "largest first, within the chip limit")
        let portrait = VirtualScreenSpec.ladder(aspectWidth: 16, aspectHeight: 9, hiDPI: false, portrait: true)
        XCTAssertTrue(portrait.allSatisfy { $0.height > $0.width })
        let extreme = VirtualScreenSpec.ladder(aspectWidth: 16384, aspectHeight: 1, hiDPI: true)
        XCTAssertEqual(extreme.count, 1)
        XCTAssertGreaterThanOrEqual(extreme[0].height, VirtualScreenSpec.minModeDimension)
    }

    func testModesLimitedToInitial() {
        let s = spec([VirtualMode(width: 1920, height: 1080, hiDPI: true), VirtualMode(width: 2560, height: 1440, hiDPI: true),
                      VirtualMode(width: 1280, height: 720, hiDPI: true)])
        XCTAssertEqual(s.modesLimited(toInitial: true).map(\.width), [1920, 1280])
        XCTAssertEqual(s.modesLimited(toInitial: false).count, 3)
    }

    func testLossyDecodeKeepsGoodFields() throws {
        let json = """
        {"id":"6F1C3F9A-1D2B-4C5E-8F70-112233445566","name":5,"aspectWidth":"x","hiDPI":false,
         "modes":[{"width":1920,"height":1080,"hiDPI":false,"refreshMilliHz":60000}],
         "associations":[{"target":"bad"},{"target":"\(String(repeating: "d", count: 32))","presentation":"mirror"}],
         "placement":"nowhere"}
        """
        let s = try JSONDecoder().decode(VirtualScreenSpec.self, from: Data(json.utf8))
        XCTAssertEqual(s.name, L("Virtual Screen"))
        XCTAssertEqual(s.aspectWidth, 16)
        XCTAssertFalse(s.hiDPI)
        XCTAssertEqual(s.modes.count, 1)
        XCTAssertEqual(s.associations.count, 1)
        XCTAssertEqual(s.associations.first?.presentation, .mirror)
        XCTAssertEqual(s.placement, .automatic)
        let again = try JSONDecoder().decode(VirtualScreenSpec.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(again, s)
        XCTAssertThrowsError(try JSONDecoder().decode(VirtualScreenSpec.self, from: Data(#"{"name":"x"}"#.utf8)))
    }

    func testPrimaries() {
        XCTAssertTrue(VirtualPrimaries.sRGB.isPlausible)
        XCTAssertTrue(VirtualPrimaries.displayP3.isPlausible)
        let p3 = Chromaticity(redX: 0.680, redY: 0.320, greenX: 0.265, greenY: 0.690, blueX: 0.150, blueY: 0.060,
                              whiteX: 0.3127, whiteY: 0.3290)
        XCTAssertEqual(VirtualPrimaries(edid: p3), .displayP3)
        // A blank EDID block (zeros) or an edge value isn't copied onto the virtual.
        XCTAssertNil(VirtualPrimaries(edid: Chromaticity(redX: 0, redY: 0, greenX: 0, greenY: 0, blueX: 0, blueY: 0,
                                                         whiteX: 0.3127, whiteY: 0.3290)))
        XCTAssertNil(VirtualPrimaries(edid: Chromaticity(redX: 1, redY: 0.3, greenX: 0.3, greenY: 0.6, blueX: 0.15, blueY: 0.06,
                                                         whiteX: 0.3127, whiteY: 0.3290)))
    }
}
