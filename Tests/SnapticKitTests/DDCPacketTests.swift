import XCTest
@testable import SnapticKit

final class DDCPacketTests: XCTestCase {
    func testSetVCPMatchesFieldBytes() {
        // m1ddc / MonitorControl: 0x84 0x03 vcp hi lo chk with chk = 0x6E ^ 0x51 ^ …
        let bytes = DDCPacket.encode(.setVCP(0x10, 0x0032), framing: .field)
        XCTAssertEqual(Array(bytes.prefix(5)), [0x84, 0x03, 0x10, 0x00, 0x32])
        XCTAssertEqual(bytes.count, 6)
        XCTAssertEqual(bytes[5], 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32)
        // Set ignores the framing choice: both variants use the spec seed.
        XCTAssertEqual(bytes, DDCPacket.encode(.setVCP(0x10, 0x0032), framing: .spec))
    }

    func testGetVCPFramingVariants() {
        let field = DDCPacket.encode(.getVCP(0x10), framing: .field)
        let spec = DDCPacket.encode(.getVCP(0x10), framing: .spec)
        XCTAssertEqual(Array(field.prefix(3)), [0x82, 0x01, 0x10])
        XCTAssertEqual(field[3], 0x6E ^ 0x82 ^ 0x01 ^ 0x10)
        XCTAssertEqual(spec[3], 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10)
        XCTAssertNotEqual(field, spec)
        XCTAssertEqual(DDCFraming.field.other, .spec)
        XCTAssertEqual(DDCFraming.spec.other, .field)
    }

    func testCapabilitiesRequest() {
        let bytes = DDCPacket.encode(.capabilities(offset: 0x0120), framing: .spec)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x83, 0xF3, 0x01, 0x20])
        XCTAssertEqual(bytes[4], 0x6E ^ 0x51 ^ 0x83 ^ 0xF3 ^ 0x01 ^ 0x20)
    }

    func testIntelBufferStartsWithSourceAndUsesSpecChecksum() {
        let bytes = DDCPacket.encodeWithSource(.getVCP(0x12))
        XCTAssertEqual(bytes.first, 0x51)
        XCTAssertEqual(bytes.count, 5)
        // Checksum over the whole buffer, seeded with the destination address.
        XCTAssertEqual(DDCPacket.xor(bytes[0..<4], seed: 0x6E), bytes[4])
    }

    func testAlternateDataAddressChangesSeed() {
        let lg = DDCPacket.encode(.setVCP(0xF4, 0x0090), framing: .field, dataAddress: 0x50)
        XCTAssertEqual(lg.last, 0x6E ^ 0x50 ^ 0x84 ^ 0x03 ^ 0xF4 ^ 0x00 ^ 0x90)
    }

    func testFixedLengths() {
        XCTAssertEqual(DDCPacket.wireLength(.getVCP(0)), 4)
        XCTAssertEqual(DDCPacket.wireLength(.setVCP(0, 0)), 6)
        XCTAssertEqual(DDCPacket.wireLength(.capabilities(offset: 0)), 5)
        for request in [DDCRequest.getVCP(1), .setVCP(2, 3), .capabilities(offset: 4)] {
            for framing in DDCFraming.allCases {
                XCTAssertEqual(DDCPacket.encode(request, framing: framing).count, DDCPacket.wireLength(request))
            }
            XCTAssertLessThanOrEqual(DDCPacket.encodeWithSource(request).count, DDCPacket.maxBufferLength)
        }
    }

    func testOnlyThreeOpcodesExist() {
        XCTAssertEqual(DDCRequest.getVCP(0).opcode, 0x01)
        XCTAssertEqual(DDCRequest.setVCP(0, 0).opcode, 0x03)
        XCTAssertEqual(DDCRequest.capabilities(offset: 0).opcode, 0xF3)
        XCTAssertNil(DDCRequest.capabilities(offset: 0).vcpCode)
        XCTAssertEqual(DDCRequest.setVCP(0x62, 5).vcpCode, 0x62)
    }

    func testChipAndDataAddressAllowList() {
        for chip in 0...255 {
            let allowed = DDCPacket.isAllowedChip(UInt8(chip))
            XCTAssertEqual(allowed, chip == 0x37 || chip == 0xB7, "chip \(chip)")
        }
        XCTAssertFalse(DDCPacket.isAllowedChip(0x50), "EDID EEPROM must never be addressable")
        XCTAssertTrue(DDCPacket.isAllowedDataAddress(0x51))
        XCTAssertTrue(DDCPacket.isAllowedDataAddress(0x50))
        XCTAssertFalse(DDCPacket.isAllowedDataAddress(0x30))
    }

    func testChecksumRoundTripFuzzed() {
        var rng = SeededGenerator(seed: 0xDDC)
        for _ in 0..<2_000 {
            let code = UInt8(truncatingIfNeeded: rng.next())
            let value = UInt16(truncatingIfNeeded: rng.next())
            let framing: DDCFraming = rng.next() % 2 == 0 ? .field : .spec
            let request: DDCRequest
            switch rng.next() % 3 {
            case 0: request = .getVCP(code)
            case 1: request = .setVCP(code, value)
            default: request = .capabilities(offset: value)
            }
            let bytes = DDCPacket.encode(request, framing: framing)
            let seeded: UInt8
            if case .setVCP = request { seeded = 0x6E ^ 0x51 } else { seeded = framing == .spec ? 0x6E ^ 0x51 : 0x6E }
            XCTAssertEqual(DDCPacket.xor(bytes[0..<(bytes.count - 1)], seed: seeded), bytes.last)
            XCTAssertEqual(bytes[0] & 0x7F, UInt8(request.body.count))
        }
    }
}
