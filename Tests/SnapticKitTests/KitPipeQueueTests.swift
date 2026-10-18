import XCTest
@testable import SnapticKit

final class KitPipeQueueTests: XCTestCase {
    private func text(_ data: Data?) -> String? { data.map { String(decoding: $0, as: UTF8.self) } }

    func testLinesAreNewlineTerminatedAndWrittenInOrder() {
        var q = PipeWriteQueue(capacity: 100)
        XCTAssertEqual(q.enqueue(Data("a".utf8)), .queued)
        XCTAssertEqual(q.enqueue(Data("bc\n".utf8)), .queued)
        XCTAssertEqual(q.queuedBytes, 5)
        XCTAssertEqual(text(q.head), "a\n")
        q.consume(2)
        XCTAssertEqual(text(q.head), "bc\n")
        q.consume(3)
        XCTAssertNil(q.head)
        XCTAssertTrue(q.isEmpty)
        XCTAssertEqual(q.queuedBytes, 0)
    }

    func testPartialWritesAndOverlongConsume() {
        var q = PipeWriteQueue(capacity: 100)
        _ = q.enqueue(Data("hello".utf8))
        _ = q.enqueue(Data("x".utf8))
        q.consume(2)
        XCTAssertEqual(text(q.head), "llo\n")
        XCTAssertEqual(q.queuedBytes, 6)
        q.consume(0)
        q.consume(-3)
        XCTAssertEqual(q.queuedBytes, 6)
        q.consume(50)   // more than queued: everything is gone, nothing goes negative
        XCTAssertTrue(q.isEmpty)
        XCTAssertEqual(q.queuedBytes, 0)
    }

    func testCapIsABrokenPipeNotATruncation() {
        var q = PipeWriteQueue(capacity: 10)
        XCTAssertEqual(q.enqueue(Data("12345678".utf8)), .queued)   // 9 bytes
        XCTAssertEqual(q.enqueue(Data("x".utf8)), .overCap)          // would be 11
        XCTAssertEqual(q.queuedBytes, 9)
        q.consume(9)
        XCTAssertEqual(q.enqueue(Data("123456789".utf8)), .queued)  // exactly 10
        XCTAssertEqual(q.enqueue(Data(), isHeartbeat: true), .overCap)
        var big = PipeWriteQueue(capacity: 4)
        XCTAssertEqual(big.enqueue(Data("toolong".utf8)), .overCap)
        XCTAssertTrue(big.isEmpty)
    }

    func testHeartbeatsCoalesceUntilOneStartsGoingOut() {
        var q = PipeWriteQueue(capacity: 100)
        XCTAssertEqual(q.enqueue(Data("hb".utf8), isHeartbeat: true), .queued)
        XCTAssertEqual(q.enqueue(Data("hb".utf8), isHeartbeat: true), .coalesced)
        XCTAssertEqual(q.enqueue(Data("cmd".utf8)), .queued)
        q.consume(1)   // the first heartbeat is half written: a new one may queue
        XCTAssertEqual(q.enqueue(Data("hb".utf8), isHeartbeat: true), .queued)
        XCTAssertEqual(q.enqueue(Data("hb".utf8), isHeartbeat: true), .coalesced)
    }

    func testRemoveAll() {
        var q = PipeWriteQueue(capacity: 100)
        _ = q.enqueue(Data("abc".utf8))
        q.consume(1)
        q.removeAll()
        XCTAssertTrue(q.isEmpty)
        XCTAssertEqual(q.queuedBytes, 0)
        XCTAssertNil(q.head)
    }

    func testFuzzKeepsCountsConsistent() {
        var rng = SeededGenerator(seed: 0xA6)
        var q = PipeWriteQueue(capacity: 300)
        var expected = Data()   // bytes queued and not yet consumed, in order
        for _ in 0..<5_000 {
            if rng.next() % 2 == 0 {
                let n = Int(rng.next() % 41)
                let line = Data((0..<n).map { _ in UInt8(0x61 + rng.next() % 26) })
                let heartbeat = rng.next() % 5 == 0
                let before = q.queuedBytes
                switch q.enqueue(line, isHeartbeat: heartbeat) {
                case .queued: expected.append(line); expected.append(0x0A)
                case .coalesced: XCTAssertTrue(heartbeat); XCTAssertEqual(q.queuedBytes, before)
                case .overCap: XCTAssertGreaterThan(before + line.count + 1, 300); XCTAssertEqual(q.queuedBytes, before)
                }
            } else if let head = q.head {
                let n = Int(rng.next() % UInt64(head.count + 1))
                XCTAssertEqual(head, expected.prefix(head.count))
                q.consume(n)
                expected.removeFirst(n)
            }
            XCTAssertEqual(q.queuedBytes, expected.count)
            XCTAssertLessThanOrEqual(q.queuedBytes, 300)
            XCTAssertEqual(q.isEmpty, expected.isEmpty)
        }
    }
}
