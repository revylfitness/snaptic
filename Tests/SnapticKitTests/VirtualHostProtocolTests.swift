import XCTest
@testable import SnapticKit

final class VirtualHostProtocolTests: XCTestCase {
    private let spec = VirtualScreenSpec(name: "A", aspectWidth: 16, aspectHeight: 9, sizeInches: 27, hiDPI: true,
                                         modes: [VirtualMode(width: 1920, height: 1080, hiDPI: true)])

    func testRoundTripMessages() {
        let messages: [VirtualHostMessage] = [
            .hello(protocolVersion: VirtualHostProtocol.version, build: "abc"),
            .create(requestID: 7, spec: spec, initialMode: spec.modes[0], serial: 42, backing: VirtualBacking(pixelsWide: 3840, pixelsHigh: 2160)),
            .setModes(requestID: 8, modes: spec.modes),
            .shutdown,
        ]
        for m in messages {
            let data = VirtualHostProtocol.encode(m)!
            XCTAssertFalse(data.contains(0x0A), "one JSON line")
            XCTAssertEqual(VirtualHostProtocol.decodeMessage(data), m)
        }
        let replies: [VirtualHostReply] = [
            .ready(protocolVersion: 1), .created(requestID: 7, displayID: 99), .modesSet(requestID: 8),
            .failed(requestID: nil, reason: .unavailable), .failed(requestID: 3, reason: .refused),
        ]
        for r in replies { XCTAssertEqual(VirtualHostProtocol.decodeReply(VirtualHostProtocol.encode(r)!), r) }
    }

    func testRejectsGarbage() {
        XCTAssertNil(VirtualHostProtocol.decodeMessage(Data("{}".utf8)))
        XCTAssertNil(VirtualHostProtocol.decodeMessage(Data("not json".utf8)))
        XCTAssertNil(VirtualHostProtocol.decodeReply(Data(#"{"failed":{"reason":"free text"}}"#.utf8)))
        var rng = SeededGenerator(seed: 0xF00D)
        for _ in 0..<2000 {
            let n = Int(rng.next() % 64)
            let bytes = (0..<n).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            _ = VirtualHostProtocol.decodeMessage(Data(bytes))
            _ = VirtualHostProtocol.decodeReply(Data(bytes))
        }
    }

    func testValidateCreate() {
        let ok = VirtualBacking(pixelsWide: 3840, pixelsHigh: 2160)
        XCTAssertNil(VirtualHostProtocol.validate(spec: spec, initialMode: spec.modes[0], backing: ok, maxDimension: 6144))
        XCTAssertEqual(VirtualHostProtocol.validate(spec: spec, initialMode: spec.modes[0], backing: ok, maxDimension: 3000), .invalidRequest)
        XCTAssertEqual(VirtualHostProtocol.validate(spec: spec, initialMode: spec.modes[0],
                                                    backing: VirtualBacking(pixelsWide: 1920, pixelsHigh: 1080), maxDimension: 6144),
                       .invalidRequest, "HiDPI mode needs 2× backing")
        var lo = spec
        lo.hiDPI = false
        XCTAssertEqual(VirtualHostProtocol.validate(spec: lo, initialMode: spec.modes[0], backing: ok, maxDimension: 6144), .invalidRequest)
        let fast = VirtualMode(width: 1920, height: 1080, hiDPI: true, refreshMilliHz: 500_000)
        XCTAssertEqual(VirtualHostProtocol.validate(spec: spec, initialMode: fast, backing: ok, maxDimension: 6144), .invalidRequest)
        XCTAssertEqual(VirtualHostProtocol.validate(spec: spec, initialMode: spec.modes[0],
                                                    backing: VirtualBacking(pixelsWide: 0, pixelsHigh: 0), maxDimension: 6144),
                       .invalidRequest)
    }

    func testValidateModes() {
        let b = VirtualBacking(pixelsWide: 5120, pixelsHigh: 2880)
        XCTAssertNil(VirtualHostProtocol.validate(modes: [VirtualMode(width: 2560, height: 1440, hiDPI: true)], backing: b))
        XCTAssertEqual(VirtualHostProtocol.validate(modes: [], backing: b), .invalidRequest)
        XCTAssertEqual(VirtualHostProtocol.validate(modes: [VirtualMode(width: 3000, height: 1440, hiDPI: true)], backing: b), .invalidRequest)
    }

    func testHiDPIVerification() {
        let m = VirtualMode(width: 1920, height: 1080, hiDPI: true)
        XCTAssertTrue(VirtualHostProtocol.hiDPIVerified(requested: m, pixelWidth: 3840, pointWidth: 1920))
        XCTAssertFalse(VirtualHostProtocol.hiDPIVerified(requested: m, pixelWidth: 1920, pointWidth: 1920))
        XCTAssertFalse(VirtualHostProtocol.hiDPIVerified(requested: m, pixelWidth: 0, pointWidth: 0))
        XCTAssertTrue(VirtualHostProtocol.hiDPIVerified(requested: VirtualMode(width: 1920, height: 1080, hiDPI: false),
                                                        pixelWidth: 1920, pointWidth: 1920))
    }

    func testFailureMessagesExist() {
        for f in VirtualHostFailure.allCases { XCTAssertFalse(f.message.isEmpty) }
    }
}
