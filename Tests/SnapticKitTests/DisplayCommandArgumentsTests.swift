import XCTest
@testable import SnapticKit

final class DisplayCommandArgumentsTests: XCTestCase {
    private func split(_ args: [String], _ count: Int) -> DisplayCommandArguments.Split? {
        DisplayCommandArguments.split(args, valueCount: count)
    }

    func testValuesWithoutSelectorUseTheDefault() {
        XCTAssertEqual(split(["50"], 1), .init(values: ["50"], selector: nil))
        XCTAssertEqual(split([], 0), .init(values: [], selector: nil))
        XCTAssertEqual(split(["10", "50"], 2), .init(values: ["10", "50"], selector: nil))
    }

    func testTrailingSelector() {
        XCTAssertEqual(split(["50", "2"], 1), .init(values: ["50"], selector: "2"))
        XCTAssertEqual(split(["-10", "main"], 1), .init(values: ["-10"], selector: "main"), "relative values stay values")
        XCTAssertEqual(split(["id:5"], 0), .init(values: [], selector: "id:5"))
    }

    func testUnquotedNameWithSpacesIsOneSelector() {
        XCTAssertEqual(split(["50", "LG", "UltraFine"], 1), .init(values: ["50"], selector: "LG UltraFine"))
        XCTAssertEqual(split(["DELL", "U2723QE"], 0), .init(values: [], selector: "DELL U2723QE"))
    }

    func testDisplayOption() {
        XCTAssertEqual(split(["--display", "2", "50"], 1), .init(values: ["50"], selector: "2"))
        XCTAssertEqual(split(["50", "--display", "LG UltraFine"], 1), .init(values: ["50"], selector: "LG UltraFine"))
        XCTAssertEqual(split(["50", "--display=mouse"], 1), .init(values: ["50"], selector: "mouse"))
        XCTAssertNil(split(["50", "--display"], 1), "option without a selector")
        XCTAssertNil(split(["50", "--display="], 1), "empty selector")
        XCTAssertNil(split(["--display", "1", "--display", "2", "50"], 1), "given twice")
        XCTAssertNil(split(["50", "60", "--display", "2"], 1), "extra value with the option")
    }

    func testWrongValueCounts() {
        XCTAssertNil(split([], 1))
        XCTAssertNil(split(["10"], 2))
        XCTAssertNil(split(["50"], -1))
        XCTAssertNil(split(["50", "   "], 1), "blank selector")
    }

    func testSelectorIsTrimmed() {
        XCTAssertEqual(split(["50", " 2 "], 1)?.selector, "2")
    }

    func testFuzzNeverTrapsAndKeepsValueCount() {
        var rng = SeededGenerator(seed: 0xA59)
        let words = ["50", "-5", "+10", "--display", "--display=2", "main", "", " ", "LG", "id:7", "all", "--"]
        for _ in 0..<2000 {
            let n = Int(rng.next() % 6)
            let args = (0..<n).map { _ in words[Int(rng.next() % UInt64(words.count))] }
            let count = Int(rng.next() % 3)
            if let result = split(args, count) {
                XCTAssertEqual(result.values.count, count)
                if let s = result.selector { XCTAssertFalse(s.isEmpty) }
                XCTAssertFalse(result.values.contains(DisplayCommandArguments.displayOption))
            }
        }
    }
}
