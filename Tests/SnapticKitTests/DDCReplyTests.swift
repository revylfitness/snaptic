import XCTest
@testable import SnapticKit

final class DDCReplyTests: XCTestCase {
    func testParsesWellFormedReply() {
        let reply = DDCReply.makeVCPReply(code: 0x10, current: 0x0032, maximum: 0x0064)
        XCTAssertEqual(reply.count, 11)
        XCTAssertEqual(DDCReply.parseVCP(reply, expecting: 0x10), .success(DDCVCPValue(current: 50, maximum: 100)))
    }

    func testMaxAndCurrentOffsets() {
        // Bytes 6–7 are the maximum, 8–9 the current value (m1ddc 2026-06 fix).
        let reply = DDCReply.makeVCPReply(code: 0x62, current: 0x0102, maximum: 0x0304)
        guard case .success(let v) = DDCReply.parseVCP(reply, expecting: 0x62) else { return XCTFail() }
        XCTAssertEqual(v.maximum, 0x0304)
        XCTAssertEqual(v.current, 0x0102)
    }

    func testReplyWithoutSourceByte() {
        let reply = Array(DDCReply.makeVCPReply(code: 0x12, current: 70, maximum: 100).dropFirst())
        XCTAssertEqual(reply.count, 10)
        XCTAssertEqual(DDCReply.parseVCP(reply, expecting: 0x12), .success(DDCVCPValue(current: 70, maximum: 100)))
    }

    func testErrors() {
        var reply = DDCReply.makeVCPReply(code: 0x10, current: 1, maximum: 2)
        XCTAssertEqual(DDCReply.parseVCP([], expecting: 0x10), .failure(.tooShort))
        XCTAssertEqual(DDCReply.parseVCP([UInt8](repeating: 0, count: 11), expecting: 0x10), .failure(.allZero))
        XCTAssertEqual(DDCReply.parseVCP(reply, expecting: 0x12), .failure(.wrongCode))
        let unsupported = DDCReply.makeVCPReply(code: 0x10, current: 0, maximum: 0, result: 1)
        XCTAssertEqual(DDCReply.parseVCP(unsupported, expecting: 0x10), .failure(.unsupportedCode))
        reply[10] ^= 0xFF
        XCTAssertEqual(DDCReply.parseVCP(reply, expecting: 0x10), .failure(.badChecksum))
        if case .success = DDCReply.parseVCP(reply, expecting: 0x10, verifyChecksum: false) {} else {
            XCTFail("ignoring checksum errors should accept the value")
        }
        var badOpcode = DDCReply.makeVCPReply(code: 0x10, current: 1, maximum: 2)
        badOpcode[2] = 0x03
        XCTAssertEqual(DDCReply.parseVCP(badOpcode, expecting: 0x10, verifyChecksum: false), .failure(.badOpcode))
        var badLength = DDCReply.makeVCPReply(code: 0x10, current: 1, maximum: 2)
        badLength[1] = 0x87
        XCTAssertEqual(DDCReply.parseVCP(badLength, expecting: 0x10, verifyChecksum: false), .failure(.badLength))
        XCTAssertEqual(DDCReply.parseVCP([0x12] + [UInt8](repeating: 1, count: 10), expecting: 0x10), .failure(.badSource))
    }

    func testCapabilitiesFragmentRoundTrip() {
        let data = Array("(prot(monitor)".utf8)
        let reply = DDCReply.makeCapabilitiesReply(offset: 0, data: data)
        XCTAssertEqual(DDCReply.parseCapabilitiesFragment(reply, expectingOffset: 0),
                       .success(DDCCapabilitiesFragment(offset: 0, data: data)))
        XCTAssertEqual(DDCReply.parseCapabilitiesFragment(reply, expectingOffset: 32), .failure(.badOffset))
        var bad = reply
        bad[bad.count - 1] ^= 1
        XCTAssertEqual(DDCReply.parseCapabilitiesFragment(bad, expectingOffset: 0), .failure(.badChecksum))
        let empty = DDCReply.makeCapabilitiesReply(offset: 64, data: [])
        XCTAssertEqual(DDCReply.parseCapabilitiesFragment(empty, expectingOffset: 64),
                       .success(DDCCapabilitiesFragment(offset: 64, data: [])))
    }

    func testCapabilitiesFragmentRejectsOversizedLength() {
        var reply = DDCReply.makeCapabilitiesReply(offset: 0, data: [UInt8](repeating: 0x41, count: 32))
        reply[1] = 0x80 | 40
        XCTAssertEqual(DDCReply.parseCapabilitiesFragment(reply, expectingOffset: 0, verifyChecksum: false),
                       .failure(.badLength))
    }

    func testAssemblerStopsOnEmptyFragment() {
        var a = DDCCapabilitiesAssembler()
        XCTAssertTrue(a.append(DDCCapabilitiesFragment(offset: 0, data: Array("abc".utf8))))
        XCTAssertEqual(a.nextOffset, 3)
        XCTAssertFalse(a.append(DDCCapabilitiesFragment(offset: 3, data: [])))
        XCTAssertTrue(a.isComplete)
        XCTAssertFalse(a.isTruncated)
        XCTAssertEqual(a.string, "abc")
    }

    func testAssemblerStopsOnTerminatorAndOrder() {
        var a = DDCCapabilitiesAssembler()
        XCTAssertFalse(a.append(DDCCapabilitiesFragment(offset: 0, data: [0x61, 0x00, 0x62])))
        XCTAssertEqual(a.string, "a")
        var b = DDCCapabilitiesAssembler()
        XCTAssertFalse(b.append(DDCCapabilitiesFragment(offset: 5, data: [0x61])))
        XCTAssertTrue(b.isTruncated)
    }

    func testAssemblerBounds() {
        var a = DDCCapabilitiesAssembler()
        var count = 0
        while a.append(DDCCapabilitiesFragment(offset: a.nextOffset, data: [UInt8](repeating: 0x41, count: 32))) {
            count += 1
            XCTAssertLessThan(count, 1_000)
        }
        XCTAssertLessThanOrEqual(a.bytes.count, DDCCapabilitiesAssembler.maxBytes)
        XCTAssertLessThanOrEqual(a.fragments, DDCCapabilitiesAssembler.maxFragments)
        XCTAssertTrue(a.isTruncated)

        var tiny = DDCCapabilitiesAssembler()
        var n = 0
        while tiny.append(DDCCapabilitiesFragment(offset: tiny.nextOffset, data: [0x41])) { n += 1 }
        XCTAssertEqual(tiny.fragments, DDCCapabilitiesAssembler.maxFragments)
        XCTAssertTrue(tiny.isTruncated)
    }

    func testFuzzedRepliesNeverTrap() {
        var rng = SeededGenerator(seed: 0xBEEF)
        for _ in 0..<5_000 {
            let n = Int(rng.next() % 80)
            var bytes = (0..<n).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            if n > 2, rng.next() % 3 == 0 { bytes[0] = 0x6E; bytes[1] = 0x88 }
            if n > 3, rng.next() % 3 == 0 { bytes[0] = 0x6E; bytes[1] = 0x80 | UInt8(rng.next() % 50); bytes[2] = 0xE3 }
            _ = DDCReply.parseVCP(bytes, expecting: UInt8(truncatingIfNeeded: rng.next()))
            if case .success(let f) = DDCReply.parseCapabilitiesFragment(bytes, expectingOffset: 0, verifyChecksum: false) {
                XCTAssertLessThanOrEqual(f.data.count, DDCReply.maxCapabilitiesFragmentData)
            }
        }
    }

    func testFuzzedValidRepliesDecodeExactly() {
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<2_000 {
            let code = UInt8(truncatingIfNeeded: rng.next())
            let cur = UInt16(truncatingIfNeeded: rng.next()), max = UInt16(truncatingIfNeeded: rng.next())
            let reply = DDCReply.makeVCPReply(code: code, current: cur, maximum: max)
            XCTAssertEqual(DDCReply.parseVCP(reply, expecting: code), .success(DDCVCPValue(current: cur, maximum: max)))
        }
    }
}
