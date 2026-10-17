import XCTest
@testable import SnapticKit

final class KitEncodingTests: XCTestCase {
    func testTokens() {
        XCTAssertEqual(KitEncoding.tokens("v20@0:8B16"), ["v", "@", ":", "B"])
        XCTAssertEqual(KitEncoding.tokens("@24@0:8@\"NSString\"16"), ["@", "@", ":", "@"])
        XCTAssertEqual(KitEncoding.tokens("{CGPoint=dd}16@0:8"), ["{CGPoint}", "@", ":"])
        XCTAssertEqual(KitEncoding.tokens("v32@0:8^{CGRect={CGPoint=dd}{CGSize=dd}}16r*24"), ["v", "@", ":", "^{CGRect}", "*"])
        XCTAssertEqual(KitEncoding.tokens("v24@0:8@?16"), ["v", "@", ":", "@?"])
        XCTAssertEqual(KitEncoding.tokens("[4i]"), ["[4i]"])
        XCTAssertNil(KitEncoding.tokens(""))
        XCTAssertNil(KitEncoding.tokens("{unclosed=dd"))
        XCTAssertNil(KitEncoding.tokens("v20@0:8%16"))
    }

    func testBoolEquivalenceAcrossArchitectures() {
        XCTAssertTrue(KitEncoding.matches(actual: "v20@0:8c16", expected: "v20@0:8B16"))
        XCTAssertTrue(KitEncoding.matches(actual: "B16@0:8", expected: "c16@0:8"))
        XCTAssertFalse(KitEncoding.matches(actual: "v20@0:8c16", expected: "v20@0:8B16", boolAware: false))
        XCTAssertFalse(KitEncoding.matches(actual: "v20@0:8I16", expected: "v20@0:8B16"), "setHiDPI: is unsigned, not BOOL")
        XCTAssertTrue(KitEncoding.matches(actual: "v20@0:8i16", expected: "v@:i"), "offsets don't matter")
        XCTAssertFalse(KitEncoding.matches(actual: "v@:i", expected: "v@:ii"))
        XCTAssertEqual(KitEncoding.normalized("c24@0:8@16"), "c@:@")
    }

    func testFailures() {
        let reqs = [KitEncoding.Requirement("orientation", "i16@0:8"), KitEncoding.Requirement("setOrientation:", "v20@0:8i16"),
                    KitEncoding.Requirement("missing", "v16@0:8")]
        let table = ["orientation": "i16@0:8", "setOrientation:": "v20@0:8f16"]
        XCTAssertEqual(KitEncoding.failures(reqs, actual: { table[$0] }), ["setOrientation:", "missing"])
    }

    func testFuzzNeverTraps() {
        var rng = SeededGenerator(seed: 0xE4C)
        let alphabet = Array("v@:Bcifd{}()[]^\"=0123456789?rnNoORVb*#")
        for _ in 0..<20_000 {
            let s = String((0..<Int(rng.next() % 40)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            if let t = KitEncoding.tokens(s) { XCTAssertFalse(t.isEmpty) }
            _ = KitEncoding.matches(actual: s, expected: "v20@0:8B16")
        }
        XCTAssertNil(KitEncoding.tokens(String(repeating: "^", count: 40) + "i"), "nesting is bounded")
    }
}
