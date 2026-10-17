import Foundation
import SnapticKit
import SnapticShims

/// One display's DDC link (PLAN §7): framing (field first, spec on retry, remembered),
/// timing (10 / 40 / 50 ms), retries, fixed-length replies and bounded capability reads.
/// Used only on DDCService's serial queue; every call blocks.
final class DDCTransport: @unchecked Sendable {
    struct Tuning: Equatable, Sendable {
        var framing: DDCFraming?
        var replyDelayMs: Int
        var retries: Int
        var writeCount: Int
        var ignoreChecksum: Bool

        init(framing: DDCFraming? = nil, replyDelayMs: Int = DDCPacket.defaultReplyDelayMs,
             retries: Int = DDCPacket.defaultRetries, writeCount: Int = 1, ignoreChecksum: Bool = false) {
            self.framing = framing
            self.replyDelayMs = replyDelayMs
            self.retries = retries
            self.writeCount = writeCount
            self.ignoreChecksum = ignoreChecksum
        }

        init(_ config: PerDisplayDDC) {
            self.init(framing: config.framing, replyDelayMs: config.replyDelayMs, retries: config.retries,
                      writeCount: config.writeCount, ignoreChecksum: config.ignoreChecksum)
        }
    }

    enum Failure: Error, Equatable {
        case transport
        case reply(DDCReplyError)
        case unsupported
    }

    let endpoint: SNDDCEndpoint
    private(set) var tuning: Tuning
    /// The framing that last worked; nil until a read succeeds.
    private(set) var learnedFraming: DDCFraming?
    private(set) var consecutiveFailures = 0

    init(endpoint: SNDDCEndpoint, tuning: Tuning) {
        self.endpoint = endpoint
        self.tuning = tuning
        learnedFraming = tuning.framing
    }

    func update(_ tuning: Tuning) {
        self.tuning = tuning
        if let framing = tuning.framing { learnedFraming = framing }
    }

    var isIntel: Bool { endpoint.kind == .intel }
    var isMCDP: Bool { endpoint.kind == .appleSiliconMCDP }

    var kindDescription: String {
        switch endpoint.kind {
        case .appleSilicon: return "Apple silicon (IOAVService)"
        case .appleSiliconMCDP: return "Apple silicon MCDP (0xB7, Beta)"
        case .intel: return "Intel (I2C)"
        @unknown default: return "Unknown"
        }
    }

    private var replyDelayMicroseconds: UInt32 {
        let ms = max(tuning.replyDelayMs, isMCDP ? DDCPacket.mcdpReplyDelayMs : 0)
        return UInt32(min(500, max(1, ms))) * 1000
    }

    private var attempts: Int { max(1, min(9, tuning.retries + 1)) }

    private func bytes(_ request: DDCRequest, framing: DDCFraming, dataAddress: UInt8) -> [UInt8] {
        isIntel ? DDCPacket.encodeWithSource(request, dataAddress: dataAddress)
            : DDCPacket.encode(request, framing: framing, dataAddress: dataAddress)
    }

    private func send(_ request: [UInt8], dataAddress: UInt8, replyLength: Int) -> [UInt8]? {
        guard request.count <= DDCPacket.maxBufferLength, replyLength <= DDCPacket.maxBufferLength,
              DDCPacket.isAllowedChip(endpoint.chipAddress), DDCPacket.isAllowedDataAddress(dataAddress) else { return nil }
        guard let data = try? SNDDC.transact(Data(request), endpoint: endpoint, dataAddress: dataAddress,
                                             replyLength: UInt(replyLength),
                                             replyDelayMicroseconds: replyLength > 0 ? replyDelayMicroseconds : 0)
        else { return nil }
        return [UInt8](data)
    }

    private static func pause(milliseconds: Int) { usleep(UInt32(max(0, milliseconds)) * 1000) }

    /// Get VCP with retries. Alternates framing variants on Apple silicon until one works.
    func read(_ code: UInt8, dataAddress: UInt8 = DDCPacket.sourceAddress) -> Result<DDCVCPValue, Failure> {
        let preferred = learnedFraming ?? .field
        var lastFailure: Failure = .transport
        for attempt in 0..<attempts {
            if attempt > 0 { Self.pause(milliseconds: 20) }
            let framing = (isIntel || attempt % 2 == 0) ? preferred : preferred.other
            guard let reply = send(bytes(.getVCP(code), framing: framing, dataAddress: dataAddress), dataAddress: dataAddress,
                                   replyLength: DDCReply.vcpReplyLength) else {
                lastFailure = .transport
                continue
            }
            switch DDCReply.parseVCP(reply, expecting: code, verifyChecksum: !tuning.ignoreChecksum) {
            case .success(let value):
                if !isIntel { learnedFraming = framing }
                consecutiveFailures = 0
                return .success(value)
            case .failure(.unsupportedCode):
                consecutiveFailures = 0
                if !isIntel { learnedFraming = framing }
                return .failure(.unsupported)
            case .failure(let error):
                lastFailure = .reply(error)
            }
        }
        consecutiveFailures += 1
        return .failure(lastFailure)
    }

    /// Set VCP (single write by default; `writeCount` 2 for flaky displays).
    func write(_ code: UInt8, _ value: UInt16, dataAddress: UInt8 = DDCPacket.sourceAddress) -> Bool {
        let request = bytes(.setVCP(code, value), framing: learnedFraming ?? .field, dataAddress: dataAddress)
        for attempt in 0..<attempts {
            if attempt > 0 { Self.pause(milliseconds: 20) }
            var ok = true
            for n in 0..<max(1, min(2, tuning.writeCount)) {
                if n > 0 { Self.pause(milliseconds: DDCPacket.defaultReplyDelayMs) }
                if send(request, dataAddress: dataAddress, replyLength: 0) == nil { ok = false }
            }
            if ok {
                consecutiveFailures = 0
                return true
            }
        }
        consecutiveFailures += 1
        return false
    }

    /// Reads the capabilities string, bounded by the assembler's limits and `deadline`.
    func readCapabilities(deadline: DispatchTime) -> String? {
        var assembler = DDCCapabilitiesAssembler()
        let framing = learnedFraming ?? .field
        while !assembler.isComplete {
            if DispatchTime.now() >= deadline {
                assembler.abandon()
                break
            }
            let offset = assembler.nextOffset
            var fragment: DDCCapabilitiesFragment?
            for attempt in 0..<attempts {
                if attempt > 0 { Self.pause(milliseconds: 20) }
                guard DispatchTime.now() < deadline else { break }
                let f = (isIntel || attempt % 2 == 0) ? framing : framing.other
                guard let reply = send(bytes(.capabilities(offset: offset), framing: f, dataAddress: DDCPacket.sourceAddress),
                                       dataAddress: DDCPacket.sourceAddress,
                                       replyLength: DDCReply.capabilitiesReplyLength) else { continue }
                if case .success(let parsed) = DDCReply.parseCapabilitiesFragment(
                    reply, expectingOffset: offset, verifyChecksum: !tuning.ignoreChecksum) {
                    fragment = parsed
                    break
                }
            }
            guard let fragment else {
                assembler.abandon()
                break
            }
            if !assembler.append(fragment) { break }
            Self.pause(milliseconds: DDCPacket.capabilitiesFragmentDelayMs)
        }
        let text = assembler.string
        return text.isEmpty ? nil : text
    }
}
