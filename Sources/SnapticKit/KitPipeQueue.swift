import Foundation

/// Bookkeeping of HelperPipeWriter (R3C §5.1, FIXES-R1 A6): lines waiting for a
/// non-blocking pipe, partial writes, heartbeat coalescing, and a byte cap. A reader that
/// stops reading must not make Snaptic buffer without bound: the writer treats `.overCap`
/// as a broken pipe.
package struct PipeWriteQueue: Sendable {
    package enum Enqueue: Equatable, Sendable {
        case queued
        /// A heartbeat that hasn't started going out yet already says the same.
        case coalesced
        /// Taking the line would exceed `capacity`; nothing was queued.
        case overCap
    }

    private struct Chunk: Sendable {
        let data: Data
        let isHeartbeat: Bool
    }

    package let capacity: Int
    private var chunks: [Chunk] = []
    /// Bytes of `chunks[0]` already written.
    private var offset = 0
    package private(set) var queuedBytes = 0

    package init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    package var isEmpty: Bool { chunks.isEmpty }

    /// Queues `line`, newline-terminated.
    package mutating func enqueue(_ line: Data, isHeartbeat: Bool = false) -> Enqueue {
        var payload = Data(line)
        if payload.last != 0x0A { payload.append(0x0A) }
        if isHeartbeat && chunks.indices.contains(where: { chunks[$0].isHeartbeat && !($0 == 0 && offset > 0) }) {
            return .coalesced
        }
        guard payload.count <= capacity - queuedBytes else { return .overCap }
        chunks.append(Chunk(data: payload, isHeartbeat: isHeartbeat))
        queuedBytes += payload.count
        return .queued
    }

    /// The unwritten rest of the oldest line, or nil when nothing waits.
    package var head: Data? {
        guard let first = chunks.first else { return nil }
        return first.data.subdata(in: first.data.startIndex + offset..<first.data.endIndex)
    }

    /// Records that `count` bytes of `head` were written (a partial write is fine).
    package mutating func consume(_ count: Int) {
        var left = max(0, count)
        while left > 0, let first = chunks.first {
            let rest = first.data.count - offset
            let used = min(rest, left)
            offset += used
            queuedBytes -= used
            left -= used
            if offset >= first.data.count {
                chunks.removeFirst()
                offset = 0
            }
        }
    }

    /// Drops everything (the pipe broke).
    package mutating func removeAll() {
        chunks = []
        offset = 0
        queuedBytes = 0
    }
}
