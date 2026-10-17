import Foundation

// DDC/CI request framing (PLAN §7, macos-display-apis §7.3). Pure byte logic so the
// framing variants, checksums and fixed lengths are unit-tested on Linux.

/// Which checksum seed a display accepts for read requests. Remembered per display.
package enum DDCFraming: String, Codable, CaseIterable, Sendable {
    /// Field-proven (MonitorControl, m1ddc): Get VCP and capabilities requests seed the
    /// checksum with 0x6E only. Set VCP always uses the spec seed.
    case field
    /// MCCS spec: every request seeds the checksum with 0x6E ^ 0x51.
    case spec

    package var other: DDCFraming { self == .field ? .spec : .field }
}

/// A host → display request. Only these opcodes can be built: "save current
/// settings" (0x0C) and every other opcode are unrepresentable (VCP policy, §7.4).
package enum DDCRequest: Equatable, Sendable {
    case getVCP(UInt8)
    case setVCP(UInt8, UInt16)
    case capabilities(offset: UInt16)

    package var opcode: UInt8 {
        switch self {
        case .getVCP: return 0x01
        case .setVCP: return 0x03
        case .capabilities: return 0xF3
        }
    }

    /// Opcode plus arguments, without length byte or checksum.
    package var body: [UInt8] {
        switch self {
        case .getVCP(let code):
            return [0x01, code]
        case .setVCP(let code, let value):
            return [0x03, code, UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        case .capabilities(let offset):
            return [0xF3, UInt8(truncatingIfNeeded: offset >> 8), UInt8(truncatingIfNeeded: offset)]
        }
    }

    package var vcpCode: UInt8? {
        switch self {
        case .getVCP(let code), .setVCP(let code, _): return code
        case .capabilities: return nil
        }
    }
}

package enum DDCPacket {
    /// The display's 8-bit write address (7-bit 0x37 shifted).
    package static let destinationAddress: UInt8 = 0x6E
    /// The host's source address; on Apple silicon it is sent as the I²C data address.
    package static let sourceAddress: UInt8 = 0x51
    /// LG's alternate input addressing uses 0x50 as the data address.
    package static let alternateSourceAddress: UInt8 = 0x50
    /// Virtual host address used to seed reply checksums.
    package static let replyChecksumSeed: UInt8 = 0x50
    /// 7-bit DDC/CI chip address.
    package static let chipAddress: UInt8 = 0x37
    /// MCDP29xx DP→HDMI converters (M1 / entry M2 built-in HDMI).
    package static let mcdpChipAddress: UInt8 = 0xB7
    /// Nothing Snaptic sends or reads is longer than this (the shim refuses more, in C).
    package static let maxBufferLength = 64

    package static func isAllowedChip(_ chip: UInt8) -> Bool { chip == chipAddress || chip == mcdpChipAddress }

    package static func isAllowedDataAddress(_ address: UInt8) -> Bool {
        address == sourceAddress || address == alternateSourceAddress
    }

    /// Apple silicon buffer, written after the data address: [0x80|n, body…, checksum].
    package static func encode(_ request: DDCRequest, framing: DDCFraming,
                               dataAddress: UInt8 = sourceAddress) -> [UInt8] {
        let body = request.body
        var bytes: [UInt8] = [0x80 | UInt8(body.count)]
        bytes.append(contentsOf: body)
        var checksum = destinationAddress
        let seedWithSource: Bool
        switch request {
        case .setVCP: seedWithSource = true
        case .getVCP, .capabilities: seedWithSource = framing == .spec
        }
        if seedWithSource { checksum ^= dataAddress }
        for byte in bytes { checksum ^= byte }
        bytes.append(checksum)
        return bytes
    }

    /// Intel buffer: the source byte is on the wire, so the checksum is always spec-exact:
    /// [0x51, 0x80|n, body…, checksum].
    package static func encodeWithSource(_ request: DDCRequest, dataAddress: UInt8 = sourceAddress) -> [UInt8] {
        [dataAddress] + encode(request, framing: .spec, dataAddress: dataAddress)
    }

    /// Fixed wire length of the Apple silicon buffer (length byte + body + checksum).
    package static func wireLength(_ request: DDCRequest) -> Int { request.body.count + 2 }

    /// XOR checksum helper (also used for replies).
    package static func xor(_ bytes: ArraySlice<UInt8>, seed: UInt8) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }

    /// Spec delays: ≥ 40 ms between a request and its reply on slow displays; field default 10 ms.
    package static let defaultReplyDelayMs = 10
    package static let slowReplyDelayMs = 40
    package static let mcdpReplyDelayMs = 50
    package static let defaultRetries = 4
    /// Pause between capability fragments.
    package static let capabilitiesFragmentDelayMs = 50
}
