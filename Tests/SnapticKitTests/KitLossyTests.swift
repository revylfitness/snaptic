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

    // MARK: LossyArray and helpers (R5-3)

    private struct Item: Codable, Equatable, Identifiable {
        var id: Int
        var name: String
    }

    private struct ListHolder: Codable, Equatable {
        var list: LossyArray<Item>
    }

    func testLossyArrayDropsOneBadElementAndKeepsTheRest() throws {
        let json = #"{"list":[{"id":1,"name":"a"},{"id":"x"},null,7,{"id":2,"name":"b"}]}"#
        let decoded = try JSONDecoder().decode(ListHolder.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.list.items, [Item(id: 1, name: "a"), Item(id: 2, name: "b")])
        let again = try JSONDecoder().decode(ListHolder.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }

    func testLossyArrayCapsElements() throws {
        let body = (0..<1_100).map { "{\"id\":\($0),\"name\":\"n\"}" }.joined(separator: ",")
        let decoded = try JSONDecoder().decode(ListHolder.self, from: Data(("{\"list\":[" + body + "]}").utf8))
        XCTAssertEqual(decoded.list.items.count, LossyArray<Item>.maxElements)
    }

    private struct Fields: Decodable {
        var items: [Item]
        var unique: [Item]
        enum CodingKeys: String, CodingKey { case items, unique }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items = c.lossyArray(.items, [Item(id: 9, name: "default")])
            unique = c.lossyUniqueArray(.unique, [])
        }
    }

    func testLossyArrayFieldFallsBackOnlyWhenMissingOrNotAList() throws {
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data("{}".utf8)).items, [Item(id: 9, name: "default")])
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data(#"{"items":5}"#.utf8)).items,
                       [Item(id: 9, name: "default")])
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data(#"{"items":[]}"#.utf8)).items, [])
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data(#"{"items":[{"id":1}]}"#.utf8)).items, [])
    }

    func testDuplicateIDsKeepTheFirstAndNeverTrap() throws {
        let json = #"{"unique":[{"id":1,"name":"first"},{"id":2,"name":"b"},{"id":1,"name":"second"}]}"#
        let f = try JSONDecoder().decode(Fields.self, from: Data(json.utf8))
        XCTAssertEqual(f.unique, [Item(id: 1, name: "first"), Item(id: 2, name: "b")])
        XCTAssertEqual([Item(id: 3, name: "x"), Item(id: 3, name: "y")].uniquedByID(), [Item(id: 3, name: "x")])
        XCTAssertEqual([3, 1, 3, 2, 1].uniqued(), [3, 1, 2])
        XCTAssertEqual([Int]().uniqued(), [])
    }
}
