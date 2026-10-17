import XCTest
@testable import SnapticKit

final class KitTextTests: XCTestCase {
    func testCleanDropsControlAndDirectionCharacters() {
        XCTAssertEqual(TextSanitizer.clean("a\u{0}b\u{1B}c\u{202E}d\u{2066}e\u{7F}f\u{9F}g"), "abcdefg")
        XCTAssertEqual(TextSanitizer.clean("line\nbreak\ttab"), "linebreaktab")
    }

    func testCleanLimitsByScalars() {
        XCTAssertEqual(TextSanitizer.clean(String(repeating: "é", count: 10), maxScalars: 4).unicodeScalars.count, 4)
        // A huge combining cluster is still bounded.
        let zalgo = "a" + String(repeating: "\u{0301}", count: 10_000)
        XCTAssertEqual(TextSanitizer.clean(zalgo, maxScalars: 64).unicodeScalars.count, 64)
        XCTAssertEqual(TextSanitizer.clean("", maxScalars: 5), "")
        XCTAssertEqual(TextSanitizer.clean("abc", maxScalars: 0), "")
    }

    func testPrivateMarkers() {
        XCTAssertTrue(TextSanitizer.hasPrivateMarker("Mozilla Firefox Private Browsing"))
        XCTAssertTrue(TextSanitizer.hasPrivateMarker("New Tab - INCOGNITO"))
        XCTAssertTrue(TextSanitizer.hasPrivateMarker("Seite — Privater Modus"))
        XCTAssertFalse(TextSanitizer.hasPrivateMarker("Privacy policy"))
        XCTAssertFalse(TextSanitizer.hasPrivateMarker(""))
    }

    func testMarkerFoundBeyondTheCleanLimit() {
        let title = String(repeating: "x", count: 600) + " private browsing"
        XCTAssertTrue(TextSanitizer.hasPrivateMarker(title))
        XCTAssertFalse(TextSanitizer.hasPrivateMarker(TextSanitizer.clean(title, maxScalars: 512)))
    }

    func testFuzzNeverReturnsBannedScalars() {
        var rng = SeededGenerator(seed: 0x7E57)
        let banned: (Unicode.Scalar) -> Bool = { s in
            (0x00...0x1F).contains(s.value) || (0x7F...0x9F).contains(s.value) || s.value == 0x200E || s.value == 0x200F
                || (0x202A...0x202E).contains(s.value) || (0x2066...0x2069).contains(s.value)
        }
        for _ in 0..<2_000 {
            var scalars = String.UnicodeScalarView()
            for _ in 0..<Int(rng.next() % 40) {
                let v = UInt32(rng.next() % 0x2100)
                if let s = Unicode.Scalar(v) { scalars.append(s) }
            }
            let out = TextSanitizer.clean(String(scalars), maxScalars: 16)
            XCTAssertLessThanOrEqual(out.unicodeScalars.count, 16)
            XCTAssertFalse(out.unicodeScalars.contains(where: banned))
        }
    }
}
