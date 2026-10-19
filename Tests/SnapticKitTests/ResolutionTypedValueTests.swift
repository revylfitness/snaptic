import XCTest
@testable import SnapticKit

/// Typing into the Resolution slider's field (review 4 ui-correctness F6, PLAN §4.1: a discrete slider snaps a typed
/// value to the nearest position). Labels as ResolutionController.sliderValueText makes them.
final class ResolutionTypedValueTests: XCTestCase {
    private let percent = ["80%", "100%", "120%", "150%"]
    private let sizes = ["1280 × 800 HiDPI · 60 Hz", "1512 × 982 HiDPI · 60 Hz", "1800 × 1169 HiDPI · 60 Hz"]

    func testPercentModeSnapsToTheNearestLabel() {
        XCTAssertEqual(SliderLabels.parse("100%", percent), 1)
        XCTAssertEqual(SliderLabels.parse("100", percent), 1)
        XCTAssertEqual(SliderLabels.parse(" 125 % ", percent), 2)
        XCTAssertEqual(SliderLabels.parse("110%", percent), 1)  // a tie keeps the smaller (first) stop
        XCTAssertEqual(SliderLabels.parse("1000", percent), 3)
        XCTAssertEqual(SliderLabels.parse("-5", percent), 0)
        XCTAssertEqual(SliderLabels.parse("99.6", percent), 1)
        XCTAssertNil(SliderLabels.parse("%", percent))
        XCTAssertNil(SliderLabels.parse("lots", percent))
        XCTAssertNil(SliderLabels.parse("1512x982", percent))
    }

    func testSizeModeSnapsDespiteTheLabelSuffix() {
        XCTAssertEqual(SliderLabels.parse("1512 × 982 HiDPI · 60 Hz", sizes), 1)
        XCTAssertEqual(SliderLabels.parse("1512x982", sizes), 1)
        XCTAssertEqual(SliderLabels.parse("1700 x 1100", sizes), 2)
        XCTAssertEqual(SliderLabels.parse("1300x800 hidpi", sizes), 0)
        XCTAssertNil(SliderLabels.parse("1512", sizes))  // a bare number isn't a size
        XCTAssertNil(SliderLabels.parse("1512x", sizes))
    }

    func testSeededGarbageNeverEscapesTheLabels() {
        var rng = SeededGenerator(seed: 0xD06)
        let alphabet = Array("0123456789.%x× -HiDPz·")
        for _ in 0..<2_000 {
            let n = Int(rng.next() % 20)
            let text = String((0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            for labels in [percent, sizes] {
                if let i = SliderLabels.parse(text, labels) {
                    XCTAssertTrue(labels.indices.contains(Int(i)), text)
                    XCTAssertEqual(i, i.rounded(), text)
                }
            }
        }
    }
}
