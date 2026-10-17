import XCTest
@testable import SnapticKit

final class RecipesTests: XCTestCase {
    func testHeadless() {
        let s = Recipes.spec(for: .headless)
        XCTAssertTrue(s.headlessPrimary)
        XCTAssertTrue(s.recreateOnLaunch)
        XCTAssertTrue(s.hiDPI)
        XCTAssertEqual(s.aspectWidth, 16)
        XCTAssertEqual(s.aspectHeight, 9)
        XCTAssertEqual(s.sizeInches, 27)
        XCTAssertEqual(s.modes, [VirtualMode(width: 2560, height: 1440, hiDPI: true), VirtualMode(width: 1920, height: 1080, hiDPI: true)])
    }

    func testOnlyHeadlessIsHeadlessPrimary() {
        for kind in RecipeKind.allCases where kind != .headless {
            XCTAssertFalse(Recipes.spec(for: kind).headlessPrimary, kind.rawValue)
        }
    }

    func testRecording() {
        let s = Recipes.spec(for: .recording)
        XCTAssertFalse(s.hiDPI)
        XCTAssertEqual(s.modes, [VirtualMode(width: 1920, height: 1080, hiDPI: false)])
        XCTAssertEqual(s.placement, .belowRightOfMain)
        XCTAssertTrue(s.wantsPIP)
        XCTAssertTrue(Recipes.defaultRecreateOnLaunch(s))
    }

    func testTeleprompterUsesTargetAspect() {
        let k = DisplayKey(rawValue: String(repeating: "e", count: 32))!
        let s = Recipes.spec(for: .teleprompter, target: k, targetAspect: (2732, 2048))
        XCTAssertEqual(s.aspectWidth, 683)
        XCTAssertEqual(s.aspectHeight, 512)
        XCTAssertEqual(s.associations, [VirtualAssociation(target: k, autoConnect: .whilePresent, presentation: .flippedStream)])
        XCTAssertFalse(s.modes.isEmpty)
        XCTAssertTrue(Recipes.spec(for: .teleprompter).associations.isEmpty)
    }

    func testPortrait() {
        let s = Recipes.spec(for: .portrait)
        XCTAssertEqual(s.aspectWidth, 9)
        XCTAssertEqual(s.aspectHeight, 16)
        XCTAssertTrue(s.hiDPI)
        XCTAssertTrue(s.modes.allSatisfy { $0.height > $0.width })
    }

    func testPresetsProduceValidSpecs() {
        for soc in SoCClass.allCases {
            for p in Recipes.presets {
                let s = Recipes.spec(preset: p, soc: soc)
                XCTAssertFalse(s.modes.isEmpty, p.title)
                XCTAssertEqual(s, s.sanitized(soc: soc), p.title)
                XCTAssertTrue(s.modes.allSatisfy { SoCCaps.fitsChip(pixelsWide: $0.pixelWidth, pixelsHigh: $0.pixelHeight, soc: soc) })
                XCTAssertLessThanOrEqual(s.modes.count, VirtualScreenSpec.maxModesHiDPI)
            }
        }
        XCTAssertEqual(Set(Recipes.presets.map(\.title)).count, Recipes.presets.count)
    }

    func testReduced() {
        func check(_ w: Int, _ h: Int, _ ew: Int, _ eh: Int, line: UInt = #line) {
            let r = Recipes.reduced((width: w, height: h))
            XCTAssertEqual(r.width, ew, line: line)
            XCTAssertEqual(r.height, eh, line: line)
        }
        check(1920, 1080, 16, 9)
        check(0, 0, 1, 1)
        check(-4, 3, 4, 3)
        check(16384 * 3 + 1, 1, 16, 9)
    }

    func testRecipeTexts() {
        for k in RecipeKind.allCases {
            XCTAssertFalse(k.title.isEmpty)
            XCTAssertFalse(k.summary.isEmpty)
        }
    }
}
