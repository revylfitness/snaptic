import XCTest
@testable import SnapticKit

final class KitLossyTests: XCTestCase {
    private enum Color: String, Codable, CaseIterable { case red, green, blue }

    private struct Holder: Codable, Equatable {
        var map: LossyMap<Color, Int>
    }

    private func decode(_ json: String) throws -> LossyMap<Color, Int> {
        try JSONDecoder().decode(Holder.self, from: Data(#"{"map":\#(json)}"#.utf8)).map
    }

    func testBadValuesAreDroppedIndividually() throws {
        let m = try decode(#"{"red":1,"green":"x","blue":3}"#)
        XCTAssertEqual(m.values, [.red: 1, .blue: 3])
    }

    func testUnknownKeysSurviveRoundTrip() throws {
        let m = try decode(#"{"red":1,"purple":9}"#)
        XCTAssertEqual(m.values, [.red: 1])
        let back = try JSONDecoder().decode(Holder.self, from: JSONEncoder().encode(Holder(map: m))).map
        XCTAssertEqual(back, m)
        let text = String(decoding: try JSONEncoder().encode(Holder(map: m)), as: UTF8.self)
        XCTAssertTrue(text.contains("purple"))
    }

    func testDropUnknownKeepsSortedPrefix() throws {
        var m = try decode(#"{"zz":1,"aa":2,"mm":3,"red":4}"#)
        m.dropUnknown(keepingAtMost: 1)
        let text = String(decoding: try JSONEncoder().encode(Holder(map: m)), as: UTF8.self)
        XCTAssertTrue(text.contains("aa"))
        XCTAssertFalse(text.contains("zz"))
        XCTAssertFalse(text.contains("mm"))
        m.dropUnknown(keepingAtMost: 0)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(Holder(map: m)), as: UTF8.self).contains("aa"))
        XCTAssertEqual(m.values, [.red: 4])
    }

    func testEntriesAreCappedDeterministically() throws {
        let body = (0..<300).map { "\"k\(String(format: "%03d", $0))\":\($0)" }.joined(separator: ",")
        let m1 = try decode("{" + body + "}")
        let m2 = try decode("{" + body + "}")
        XCTAssertEqual(m1, m2)
        let text = String(decoding: try JSONEncoder().encode(Holder(map: m1)), as: UTF8.self)
        XCTAssertTrue(text.contains("k000"))
        XCTAssertFalse(text.contains("k299"))
    }

    func testSubscript() {
        var m = LossyMap<Color, Int>()
        m[.green] = 2
        XCTAssertEqual(m[.green], 2)
        m[.green] = nil
        XCTAssertNil(m[.green])
    }

    func testLossyFieldFallback() throws {
        struct S: Decodable {
            var a: Int
            enum CodingKeys: String, CodingKey { case a }
            init(from decoder: Decoder) throws {
                a = try decoder.container(keyedBy: CodingKeys.self).lossy(.a, 7)
            }
        }
        XCTAssertEqual(try JSONDecoder().decode(S.self, from: Data(#"{"a":"x"}"#.utf8)).a, 7)
        XCTAssertEqual(try JSONDecoder().decode(S.self, from: Data(#"{}"#.utf8)).a, 7)
        XCTAssertEqual(try JSONDecoder().decode(S.self, from: Data(#"{"a":null}"#.utf8)).a, 7)
        XCTAssertEqual(try JSONDecoder().decode(S.self, from: Data(#"{"a":3}"#.utf8)).a, 3)
    }
}
