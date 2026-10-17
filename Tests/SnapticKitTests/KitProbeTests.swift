import Foundation
import XCTest
import SnapticKit

final class KitProbeTests: XCTestCase {
    func testSelfCheck() {
        XCTAssertTrue(KitProbe.selfCheck())
    }

    func testLossyMapKeepsUnknownKeysAndDropsBadValues() throws {
        let json = #"{"map":{"red":1,"blue":7,"green":"oops"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KitProbe.Sample.self, from: json)
        XCTAssertEqual(decoded.map[.red], 1)
        XCTAssertNil(decoded.map[.green])

        // The unknown "blue" entry survives a round-trip.
        let data = try JSONEncoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: Int]]
        XCTAssertEqual(object?["map"]?["blue"], 7)
        XCTAssertEqual(object?["map"]?["red"], 1)
    }

    func testLossyFieldFallback() throws {
        struct Holder: Decodable {
            var value: Int
            enum CodingKeys: String, CodingKey { case value }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = c.lossy(.value, 42)
            }
        }
        let bad = try JSONDecoder().decode(Holder.self, from: #"{"value":"x"}"#.data(using: .utf8)!)
        XCTAssertEqual(bad.value, 42)
        let good = try JSONDecoder().decode(Holder.self, from: #"{"value":3}"#.data(using: .utf8)!)
        XCTAssertEqual(good.value, 3)
    }
}
