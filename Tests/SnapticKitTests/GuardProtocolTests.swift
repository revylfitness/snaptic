import XCTest
@testable import SnapticKit

final class GuardProtocolTests: XCTestCase {
    private let op = UndoOp(displayID: 2, fingerprint: "uuid:X", property: .mode,
                            restore: .mode(BLayout.mode(1920, 1080)), expected: .mode(BLayout.mode(1280, 720)))

    func testEveryMessageRoundTripsAsOneLine() throws {
        let messages: [GuardMessage] = [
            .hello(protocolVersion: GuardProtocol.version, build: "B-1"),
            .armTrial(id: 7, seq: 1, undo: [op], deadlineSeconds: 30),
            .extend(id: 7, seconds: 5), .commitIntent(id: 7, seq: 2), .commit(id: 7), .disarm(id: 7),
            .long(seq: 8, undo: [op], restoreColorSync: true),
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
        let replies: [GuardReply] = [.ready(protocolVersion: 1, canMonitorPanel: true), .ack(seq: 3),
                                     .reverted(trial: nil, applied: 2, skipped: 1), .failed("x")]
        for r in replies {
            XCTAssertEqual(GuardProtocol.decodeReply(try XCTUnwrap(GuardProtocol.encode(r))), r)
        }
    }

    func testBoundsAreEnforced() {
        let raw = GuardProtocol.encodeUnchecked
        XCTAssertNil(GuardProtocol.decodeMessage(raw(.armTrial(id: 1, seq: 1, undo: [], deadlineSeconds: 1000))!))
        XCTAssertNil(GuardProtocol.decodeMessage(raw(.armTrial(id: 1, seq: 1, undo: Array(repeating: op, count: GuardProtocol.maxUndoOps + 1),
                                                               deadlineSeconds: 30))!))
        XCTAssertNil(GuardProtocol.decodeMessage(raw(.extend(id: 1, seconds: -1))!))
        // seq 0 is never sent: an ack for it could not be told apart from "no ack wanted".
        XCTAssertNil(GuardProtocol.decodeMessage(raw(.armTrial(id: 1, seq: 0, undo: [], deadlineSeconds: 30))!))
        XCTAssertNil(GuardProtocol.decodeMessage(raw(.commitIntent(id: 1, seq: 0))!))
        XCTAssertNil(GuardProtocol.decodeMessage(raw(.long(seq: 0, undo: [], restoreColorSync: false))!))
        XCTAssertNil(GuardProtocol.decodeMessage(Data("{not json".utf8)))
        XCTAssertNil(GuardProtocol.decodeMessage(Data(#"{"unknown":{}}"#.utf8)))
        let long = GuardProtocol.decodeReply(GuardProtocol.encode(.failed(String(repeating: "x", count: 1000)))!)
        XCTAssertEqual(long, .failed(String(repeating: "x", count: GuardProtocol.maxFailureLength)))
        XCTAssertEqual(GuardProtocol.clampedBusy(60), 10)
        XCTAssertEqual(GuardProtocol.clampedBusy(.infinity), 0)
        XCTAssertEqual(GuardProtocol.trialDeadline(panelSeconds: 15), 30)
    }

    /// FIXES-R3 7: the parent refuses what the guard would refuse, instead of sending it.
    func testParentRefusesOutOfBoundsMessages() {
        XCTAssertNil(GuardProtocol.encode(.armTrial(id: 1, seq: 1, undo: [], deadlineSeconds: 1000)))
        XCTAssertNil(GuardProtocol.encode(.armTrial(id: 1, seq: 1, undo: Array(repeating: op, count: GuardProtocol.maxUndoOps + 1),
                                                    deadlineSeconds: 30)))
        XCTAssertNil(GuardProtocol.encode(.long(seq: 0, undo: [], restoreColorSync: false)))
        XCTAssertNil(GuardProtocol.encode(.extend(id: 1, seconds: 500)))
        var longPrint = op
        longPrint.fingerprint = String(repeating: "f", count: GuardProtocol.maxFingerprintBytes + 1)
        XCTAssertNil(GuardProtocol.encode(.long(seq: 1, undo: [longPrint], restoreColorSync: false)))
        XCTAssertNil(GuardProtocol.decodeMessage(GuardProtocol.encodeUnchecked(.long(seq: 1, undo: [longPrint], restoreColorSync: false))!))
    }

    /// FIXES-R3 7: the largest message the parent can send still fits one guard line.
    func testWorstCaseMessagesFitOneLine() throws {
        let huge = ModeRef(ioModeID: .min, pixelWidth: .min, pixelHeight: .min, pointWidth: .min, pointHeight: .min,
                           refreshMilliHz: .min)
        let print = String(repeating: "u", count: GuardProtocol.maxFingerprintBytes)
        let worst = UndoOp(displayID: .max, fingerprint: print, property: .underscan, restore: .mode(huge), expected: .mode(huge))
        let ops = Array(repeating: worst, count: GuardProtocol.maxUndoOps)
        for m in [GuardMessage.armTrial(id: .max, seq: .max, undo: ops, deadlineSeconds: GuardProtocol.maxDeadlineSeconds),
                  .long(seq: .max, undo: ops, restoreColorSync: true)] {
            let data = try XCTUnwrap(GuardProtocol.encode(m), "the worst case must be sendable")
            XCTAssertLessThanOrEqual(data.count, LineSplitter.maxLine)
            // The guard's reader takes it as one line and decodes it.
            var splitter = LineSplitter()
            let lines = try XCTUnwrap(splitter.feed(data + Data([0x0A])))
            XCTAssertEqual(lines.count, 1)
            XCTAssertEqual(GuardProtocol.decodeMessage(lines[0]), m)
        }
        // Characters JSON would escape are out of bounds, so they can't inflate a line.
        for bad in ["a\"b", "a\\b", "a/b", "a b", "é", "a\u{01}"] {
            var o = worst
            o.fingerprint = bad
            XCTAssertNil(GuardProtocol.encode(.long(seq: 1, undo: [o], restoreColorSync: false)), bad)
        }
        // Real session fingerprints pass.
        for good in [Fingerprint.sessionFingerprint(uuid: "1E2A6B4C-0000-4000-8000-00000000ABCD", vendor: 1, model: 2, serial: 3),
                     Fingerprint.sessionFingerprint(uuid: nil, vendor: .max, model: .max, serial: .max)] {
            var o = worst
            o.fingerprint = good
            XCTAssertNotNil(GuardProtocol.encode(.long(seq: 1, undo: [o], restoreColorSync: false)), good)
        }
        // A reply over one line is refused rather than sent.
        XCTAssertNil(GuardProtocol.encode(.failed(String(repeating: "x", count: LineSplitter.maxLine + 1))))
    }

    /// FIXES-R1 B4: `extend` right before the panel makes the deadline now + panel + 10,
    /// however long the staged apply and settle took; it never shortens a deadline.
    func testExtendBeforePanel() throws {
        for panel in [Double(SafetyConfig.confirmSecondsRange.lowerBound), 10, 15, 60] {
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
        XCTAssertNil(GuardProtocol.decodeMessage(GuardProtocol.encodeUnchecked(.extend(id: 1, seconds: 500))!))
    }

    func testFuzzDecodeNeverTraps() {
        var rng = SeededGenerator(seed: 0x6A4D)
        let seed = GuardProtocol.encode(.armTrial(id: 7, seq: 3, undo: [op], deadlineSeconds: 30))!
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
