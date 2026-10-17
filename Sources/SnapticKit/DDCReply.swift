import Foundation

// DDC/CI reply parsing (PLAN §7, §4.10(4)): fixed lengths, checksum validation and
// the framing variants transports return. Device data is untrusted: every path is
// bounded and never traps.

/// A Get VCP reply's payload.
package struct DDCVCPValue: Equatable, Sendable {
    package var current: UInt16
    package var maximum: UInt16
    /// MCCS type byte: 0 = set parameter, 1 = momentary.
    package var type: UInt8

    package init(current: UInt16, maximum: UInt16, type: UInt8 = 0) {
        self.current = current
        self.maximum = maximum
        self.type = type
    }
}

package enum DDCReplyError: Error, Equatable, Sendable {
    case tooShort
    case allZero
    case badSource
    case badLength
    case badOpcode
    case unsupportedCode
    case wrongCode
    case badOffset
    case badChecksum
}

/// One capabilities fragment.
package struct DDCCapabilitiesFragment: Equatable, Sendable {
    package var offset: UInt16
    package var data: [UInt8]
    package init(offset: UInt16, data: [UInt8]) {
        self.offset = offset
        self.data = data
    }
}

package enum DDCReply {
    /// Get VCP reply: [0x6E][0x88][0x02][result][vcp][type][maxHi][maxLo][curHi][curLo][chk].
    package static let vcpReplyLength = 11
    /// Largest capabilities reply: address, length, opcode, 2 offset bytes, 32 data bytes, checksum.
    package static let maxCapabilitiesFragmentData = 32
    package static let capabilitiesReplyLength = 5 + maxCapabilitiesFragmentData + 1

    /// Normalizes the two framings transports return: with the display's source address
    /// first (Apple silicon) or without it (some I²C paths). Returns nil if neither fits.
    private static func frame(_ bytes: [UInt8], secondByteIsLength: Bool = true) -> [UInt8]? {
        guard let first = bytes.first else { return nil }
        if first == DDCPacket.destinationAddress { return bytes }
        if secondByteIsLength, first & 0x80 != 0 { return [DDCPacket.destinationAddress] + bytes }
        return nil
    }

    package static func parseVCP(_ raw: [UInt8], expecting code: UInt8,
                                 verifyChecksum: Bool = true) -> Result<DDCVCPValue, DDCReplyError> {
        let bytes = Array(raw.prefix(DDCPacket.maxBufferLength))
        guard bytes.count >= vcpReplyLength - 1 else { return .failure(.tooShort) }
        if bytes.allSatisfy({ $0 == 0 }) { return .failure(.allZero) }
        guard let f = frame(bytes) else { return .failure(.badSource) }
        guard f.count >= vcpReplyLength else { return .failure(.tooShort) }
        guard f[1] == 0x88 else { return .failure(.badLength) }
        guard f[2] == 0x02 else { return .failure(.badOpcode) }
        switch f[3] {
        case 0x00: break
        case 0x01: return .failure(.unsupportedCode)
        default: return .failure(.badOpcode)
        }
        guard f[4] == code else { return .failure(.wrongCode) }
        if verifyChecksum {
            let expected = DDCPacket.xor(f[0..<10], seed: DDCPacket.replyChecksumSeed)
            guard expected == f[10] else { return .failure(.badChecksum) }
        }
        let maximum = UInt16(f[6]) << 8 | UInt16(f[7])
        let current = UInt16(f[8]) << 8 | UInt16(f[9])
        return .success(DDCVCPValue(current: current, maximum: maximum, type: f[5]))
    }

    /// Capabilities reply: [0x6E][0x80|len][0xE3][offHi][offLo][data…][chk], len = 3 + data count.
    package static func parseCapabilitiesFragment(_ raw: [UInt8], expectingOffset offset: UInt16,
                                                  verifyChecksum: Bool = true)
        -> Result<DDCCapabilitiesFragment, DDCReplyError> {
        let bytes = Array(raw.prefix(DDCPacket.maxBufferLength))
        guard bytes.count >= 5 else { return .failure(.tooShort) }
        if bytes.allSatisfy({ $0 == 0 }) { return .failure(.allZero) }
        guard let f = frame(bytes) else { return .failure(.badSource) }
        guard f.count >= 6, f[1] & 0x80 != 0 else { return .failure(.badLength) }
        let length = Int(f[1] & 0x7F)
        guard length >= 3, length <= 3 + maxCapabilitiesFragmentData else { return .failure(.badLength) }
        guard f.count >= 2 + length + 1 else { return .failure(.tooShort) }
        guard f[2] == 0xE3 else { return .failure(.badOpcode) }
        let replyOffset = UInt16(f[3]) << 8 | UInt16(f[4])
        guard replyOffset == offset else { return .failure(.badOffset) }
        if verifyChecksum {
            let expected = DDCPacket.xor(f[0..<(2 + length)], seed: DDCPacket.replyChecksumSeed)
            guard expected == f[2 + length] else { return .failure(.badChecksum) }
        }
        return .success(DDCCapabilitiesFragment(offset: offset, data: Array(f[5..<(2 + length)])))
    }

    /// Builds a well-formed Get VCP reply (tests and the simulated transport).
    package static func makeVCPReply(code: UInt8, current: UInt16, maximum: UInt16, type: UInt8 = 0,
                                     result: UInt8 = 0) -> [UInt8] {
        var f: [UInt8] = [DDCPacket.destinationAddress, 0x88, 0x02, result, code, type,
                          UInt8(truncatingIfNeeded: maximum >> 8), UInt8(truncatingIfNeeded: maximum),
                          UInt8(truncatingIfNeeded: current >> 8), UInt8(truncatingIfNeeded: current)]
        f.append(DDCPacket.xor(f[0..<10], seed: DDCPacket.replyChecksumSeed))
        return f
    }

    /// Builds a well-formed capabilities fragment reply.
    package static func makeCapabilitiesReply(offset: UInt16, data: [UInt8]) -> [UInt8] {
        let payload = Array(data.prefix(maxCapabilitiesFragmentData))
        var f: [UInt8] = [DDCPacket.destinationAddress, 0x80 | UInt8(3 + payload.count), 0xE3,
                          UInt8(truncatingIfNeeded: offset >> 8), UInt8(truncatingIfNeeded: offset)]
        f.append(contentsOf: payload)
        f.append(DDCPacket.xor(f[0..<f.count], seed: DDCPacket.replyChecksumSeed))
        return f
    }
}

/// Collects capabilities fragments with the §4.10(4) bounds: ≤ 4096 bytes, ≤ 128 fragments.
/// The 2 s time bound is enforced by the reader (DDCService).
package struct DDCCapabilitiesAssembler: Equatable, Sendable {
    package static let maxBytes = 4096
    package static let maxFragments = 128

    package private(set) var bytes: [UInt8] = []
    package private(set) var fragments = 0
    package private(set) var isComplete = false
    /// True when the string was cut short by a bound.
    package private(set) var isTruncated = false

    package init() {}

    /// Offset to request next.
    package var nextOffset: UInt16 { UInt16(clamping: bytes.count) }

    /// Adds a fragment; returns false once no more fragments should be requested.
    @discardableResult
    package mutating func append(_ fragment: DDCCapabilitiesFragment) -> Bool {
        guard !isComplete else { return false }
        guard fragment.offset == nextOffset else {
            // Out-of-order data can't be placed; stop rather than guess.
            isComplete = true
            isTruncated = true
            return false
        }
        fragments += 1
        if fragment.data.isEmpty {
            isComplete = true
            return false
        }
        var data = fragment.data
        var sawTerminator = false
        if let nul = data.firstIndex(of: 0) {
            data = Array(data[..<nul])
            sawTerminator = true
        }
        let room = Self.maxBytes - bytes.count
        if data.count > room {
            bytes.append(contentsOf: data.prefix(room))
            isComplete = true
            isTruncated = true
            return false
        }
        bytes.append(contentsOf: data)
        if sawTerminator || bytes.count >= Self.maxBytes {
            isComplete = true
            isTruncated = !sawTerminator && bytes.count >= Self.maxBytes
            return false
        }
        if fragments >= Self.maxFragments {
            isComplete = true
            isTruncated = true
            return false
        }
        return true
    }

    /// Gives up (timeout, transport failure).
    package mutating func abandon() {
        isComplete = true
        isTruncated = true
    }

    /// Printable ASCII only.
    package var string: String {
        String(decoding: bytes.filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
    }
}
