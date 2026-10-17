import XCTest
@testable import SnapticKit

final class DDCCapabilitiesTests: XCTestCase {
    private let dell = "(prot(monitor)type(LCD)model(U2723QE)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B) 16 18 1A 52 60(0F 11 12 1B) AA(01 02) AC AE B2 B6 C6 C8 C9 D6(01 04 05) DC(00 02 03 05) DF E0 E1 E2(00 1D) F0(0C) F1 F2 FD)mswhql(1)asset_eep(40)mccs_ver(2.1))"

    func testParsesTypicalString() throws {
        let caps = try XCTUnwrap(DDCCapabilities.parse(dell))
        XCTAssertEqual(caps.model, "U2723QE")
        XCTAssertEqual(caps.type, "LCD")
        XCTAssertEqual(caps.mccsVersion, "2.1")
        XCTAssertEqual(caps.commands, [0x01, 0x02, 0x03, 0x07, 0x0C, 0xE3, 0xF3])
        XCTAssertTrue(caps.supports(0x10))
        XCTAssertTrue(caps.supports(0x12))
        XCTAssertFalse(caps.supports(0x62))
        XCTAssertEqual(caps.vcp[0x14], [0x05, 0x08, 0x0B])
        XCTAssertEqual(caps.inputSources, [0x0F, 0x11, 0x12, 0x1B])
        XCTAssertEqual(caps.vcp[0xD6], [0x01, 0x04, 0x05])
        XCTAssertEqual(caps.vcp[0x10], [])
        XCTAssertNil(caps.values(for: 0x10))
        XCTAssertEqual(caps.values(for: 0xDC), [0x00, 0x02, 0x03, 0x05])
    }

    func testToleratesMissingOuterParensAndTruncation() throws {
        let caps = try XCTUnwrap(DDCCapabilities.parse("vcp(10 12 62)model(X)"))
        XCTAssertTrue(caps.supports(0x62))
        XCTAssertEqual(caps.model, "X")
        let truncated = try XCTUnwrap(DDCCapabilities.parse("(vcp(10 12 60(0F 11))model(Y)"))
        XCTAssertEqual(truncated.inputSources, [0x0F, 0x11])
    }

    func testLowercaseHexAndSpacing() throws {
        let caps = try XCTUnwrap(DDCCapabilities.parse("( vcp( 10  12 14 ( 05  0b ) ) )"))
        XCTAssertEqual(caps.vcp[0x14], [0x05, 0x0B])
    }

    func testRejectsTooDeepNesting() {
        let deep = "(vcp(10" + String(repeating: "(", count: 12) + String(repeating: ")", count: 12) + "))"
        XCTAssertNil(DDCCapabilities.parse(deep))
    }

    func testRejectsUnbalancedGroups() {
        XCTAssertNil(DDCCapabilities.parse("(vcp(10 12 14(05)"))
        XCTAssertNil(DDCCapabilities.parse(""))
        XCTAssertNil(DDCCapabilities.parse("garbage"))
    }

    func testBoundsInputLength() {
        let huge = "(vcp(" + String(repeating: "10 ", count: 5_000) + "))"
        // Truncated at 4096 bytes: unbalanced afterwards, but it must not hang or trap.
        _ = DDCCapabilities.parse(huge)
        var many = "(vcp("
        for i in 0..<256 { many += VCPPolicy.hex(UInt8(i)) + "(" + String(repeating: "01 02 03 ", count: 30) + ") " }
        many += "))"
        if let caps = DDCCapabilities.parse(many) {
            XCTAssertLessThanOrEqual(caps.vcp.count, DDCCapabilities.maxCodes)
            for (_, values) in caps.vcp { XCTAssertLessThanOrEqual(values.count, DDCCapabilities.maxValuesPerCode) }
        }
    }

    func testIgnoresOversizedTokens() throws {
        let caps = try XCTUnwrap(DDCCapabilities.parse("(vcp(10 123 1FFFF 12))"))
        XCTAssertEqual(Set(caps.vcp.keys), [0x10, 0x12])
    }

    func testModelTextIsSanitized() throws {
        let caps = try XCTUnwrap(DDCCapabilities.parse("(model(" + String(repeating: "A", count: 200) + "\u{7}))"))
        XCTAssertEqual(caps.model?.count, DDCCapabilities.maxTextLength)
    }

    func testCodableRoundTripAndLossyDecode() throws {
        let caps = try XCTUnwrap(DDCCapabilities.parse(dell))
        let data = try JSONEncoder().encode(caps)
        XCTAssertEqual(try JSONDecoder().decode(DDCCapabilities.self, from: data), caps)
        let partial = try JSONDecoder().decode(DDCCapabilities.self, from: Data(#"{"model":"Z","vcp":"bad"}"#.utf8))
        XCTAssertEqual(partial.model, "Z")
        XCTAssertTrue(partial.vcp.isEmpty)
    }

    func testFuzzedInputNeverTraps() {
        var rng = SeededGenerator(seed: 0xCAFE)
        let alphabet = Array("()0123456789ABCDEFabcdef vcpmodeltyp_(()))\u{0}\n".utf8)
        for _ in 0..<3_000 {
            let n = Int(rng.next() % 300)
            let bytes = (0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }
            let text = String(decoding: bytes, as: UTF8.self)
            if let caps = DDCCapabilities.parse(text) {
                XCTAssertLessThanOrEqual(caps.vcp.count, DDCCapabilities.maxCodes)
                XCTAssertLessThanOrEqual(caps.model?.count ?? 0, DDCCapabilities.maxTextLength)
            }
        }
    }

    func testFuzzedWellFormedStringsRoundTripCodes() {
        var rng = SeededGenerator(seed: 99)
        for _ in 0..<500 {
            var codes: [UInt8: [UInt16]] = [:]
            var text = "(prot(monitor)vcp("
            for _ in 0..<Int(rng.next() % 20) {
                let code = UInt8(truncatingIfNeeded: rng.next())
                guard codes[code] == nil else { continue }
                if rng.next() % 2 == 0 {
                    let values = (0..<Int(rng.next() % 5 + 1)).map { _ in UInt16(rng.next() % 256) }
                    var unique: [UInt16] = []
                    for v in values where !unique.contains(v) { unique.append(v) }
                    codes[code] = unique
                    text += VCPPolicy.hex(code) + "(" + unique.map { VCPPolicy.hex(UInt8($0)) }.joined(separator: " ") + ") "
                } else {
                    codes[code] = []
                    text += VCPPolicy.hex(code) + " "
                }
            }
            text += "))"
            guard let caps = DDCCapabilities.parse(text) else { return XCTFail(text) }
            XCTAssertEqual(caps.vcp, codes, text)
        }
    }
}
