import XCTest
@testable import SnapticKit

final class GuardProtocolTests: XCTestCase {
    private let op = UndoOp(displayID: 2, fingerprint: "uuid:X", property: .mode,
                            restore: .mode(BLayout.mode(1920, 1080)), expected: .mode(BLayout.mode(1280, 720)))

    func testEveryMessageRoundTripsAsOneLine() throws {
        let messages: [GuardMessage] = [
            .hello(protocolVersion: GuardProtocol.version, build: "B-1"),
            .armTrial(id: 7, undo: [op], deadlineSeconds: 30),
            .extend(id: 7, seconds: 5), .commitIntent(id: 7), .commit(id: 7), .disarm(id: 7),
            .long(id: 8, undo: [op], restoreColorSync: true),
            .impairment(dimToBlack: true, overlayBelowFloor: false),
            .busy(seconds: 3),
            .classification([GuardDisplayClass(id: 1, transport: .builtin, strong: true, weak: false),
                             GuardDisplayClass(id: 9, transport: .snapticVirtual, strong: false, weak: false, hostPID: 42, hostStartTime: 99)]),
            .heartbeat(mainAgeMillis: 12), .shutdown,
        ]
        for m in messages {
            let data = try XCTUnwrap(GuardProtocol.encode(m))
            XCTAssertFalse(data.contains(0x0A), "JSON lines never contain a raw newline")
            XCTAssertEqual(GuardProtocol.decodeMessage(data), m)
        }
        let replies: [GuardReply] = [.ready(protocolVersion: 1, canMonitorPanel: true), .ack(id: 3),
                                     .reverted(trial: nil, applied: 2, skipped: 1), .failed("x")]
        for r in replies {
            XCTAssertEqual(GuardProtocol.decodeReply(try XCTUnwrap(GuardProtocol.encode(r))), r)
        }
    }

    func testBoundsAreEnforced() {
        XCTAssertNil(GuardProtocol.decodeMessage(GuardProtocol.encode(.armTrial(id: 1, undo: [], deadlineSeconds: 1000))!))
        XCTAssertNil(GuardProtocol.decodeMessage(GuardProtocol.encode(.armTrial(id: 1, undo: Array(repeating: op, count: 300),
                                                                                deadlineSeconds: 30))!))
        XCTAssertNil(GuardProtocol.decodeMessage(GuardProtocol.encode(.extend(id: 1, seconds: -1))!))
        XCTAssertNil(GuardProtocol.decodeMessage(Data("{not json".utf8)))
        XCTAssertNil(GuardProtocol.decodeMessage(Data(#"{"unknown":{}}"#.utf8)))
        let long = GuardProtocol.decodeReply(GuardProtocol.encode(.failed(String(repeating: "x", count: 1000)))!)
        XCTAssertEqual(long, .failed(String(repeating: "x", count: GuardProtocol.maxFailureLength)))
        XCTAssertEqual(GuardProtocol.clampedBusy(60), 10)
        XCTAssertEqual(GuardProtocol.clampedBusy(.infinity), 0)
        XCTAssertEqual(GuardProtocol.trialDeadline(panelSeconds: 15), 30)
    }

    /// FIXES-R1 B4: `extend` right before the panel makes the deadline now + panel + 10,
    /// however long the staged apply and settle took; it never shortens a deadline.
    func testExtendBeforePanel() throws {
        for panel in [10.0, 15, 60] {
            let ext = GuardProtocol.panelExtension(panelSeconds: panel)
            XCTAssertEqual(ext, panel + 10)
            XCTAssertNotNil(GuardProtocol.decodeMessage(try XCTUnwrap(GuardProtocol.encode(.extend(id: 1, seconds: ext)))),
                            "the panel extension must pass the protocol bounds")
            let armedAt = 100.0
            let deadline = armedAt + GuardProtocol.trialDeadline(panelSeconds: panel)
            // A slow apply (rotation + HDR) used most of the original deadline.
            let panelAt = armedAt + 24
            let extended = GuardProtocol.extendedDeadline(current: deadline, now: panelAt, seconds: ext)
            XCTAssertEqual(extended, max(deadline, panelAt + panel + 10))
            XCTAssertGreaterThanOrEqual(extended - panelAt, panel + 10, "the whole countdown fits before the guard acts")
        }
        XCTAssertEqual(GuardProtocol.extendedDeadline(current: 500, now: 100, seconds: 20), 500, "never shortened")
        XCTAssertEqual(GuardProtocol.extendedDeadline(current: 0, now: 100, seconds: 1000), 100 + GuardProtocol.maxExtendSeconds)
        XCTAssertEqual(GuardProtocol.extendedDeadline(current: 0, now: 100, seconds: .nan), 100)
        XCTAssertNil(GuardProtocol.decodeMessage(GuardProtocol.encode(.extend(id: 1, seconds: 500))!))
    }

    func testFuzzDecodeNeverTraps() {
        var rng = SeededGenerator(seed: 0x6A4D)
        let seed = GuardProtocol.encode(.armTrial(id: 7, undo: [op], deadlineSeconds: 30))!
        for _ in 0..<5000 {
            var bytes = [UInt8](seed)
            for _ in 0..<Int(rng.next() % 6) {
                bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next())
            }
            if let m = GuardProtocol.decodeMessage(Data(bytes)) { XCTAssertTrue(GuardProtocol.isValid(m)) }
            _ = GuardProtocol.decodeReply(Data(bytes))
        }
    }

    func testHangDetector() {
        var h = HangDetector()
        XCTAssertNil(h.hangSeconds(at: 100), "no heartbeat yet")
        XCTAssertTrue(h.isHeartbeatStale(at: 100))
        h.heartbeat(mainAgeMillis: 100, at: 100)
        XCTAssertNil(h.hangSeconds(at: 105))
        XCTAssertFalse(h.isHeartbeatStale(at: 102))
        XCTAssertTrue(h.isHeartbeatStale(at: 104))
        XCTAssertNotNil(h.hangSeconds(at: 111), "silence over 10 s")
        // The main thread is wedged while the heartbeat thread still reports.
        h.heartbeat(mainAgeMillis: 11_000, at: 120)
        XCTAssertNotNil(h.hangSeconds(at: 120))
        // A busy window covers a long CG configure...
        h.heartbeat(mainAgeMillis: 100, at: 130)
        XCTAssertTrue(h.busy(seconds: 8, at: 130))
        h.heartbeat(mainAgeMillis: 7_000, at: 137)
        XCTAssertNil(h.hangSeconds(at: 137))
        // ...but can't be extended while the age keeps growing.
        XCTAssertFalse(h.busy(seconds: 8, at: 137))
        h.heartbeat(mainAgeMillis: 11_500, at: 141)
        XCTAssertNotNil(h.hangSeconds(at: 141))
        // Wake grace suppresses everything for 15 s.
        h.didWake(at: 200)
        XCTAssertNil(h.hangSeconds(at: 214))
        XCTAssertNotNil(h.hangSeconds(at: 216))
    }
}
