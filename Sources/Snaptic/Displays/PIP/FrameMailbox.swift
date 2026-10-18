import CoreVideo
import Foundation
import IOSurface

/// One captured (or filtered) frame. The pixel buffer is retained, so neither the
/// capture pool nor the filter pool reuses it while it is on screen.
struct PIPFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    /// The part of the buffer that holds content (unit rect, top-left origin).
    let contentRect: CGRect
    let sequence: UInt64

    var surface: IOSurface? { CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() }
}

/// Latest-frame mailbox between a capture queue and the main thread (nonisolated,
/// PLAN A.6). It holds at most one frame: a newer frame replaces an unread one, and
/// the consumer is signalled once per batch, so a slow main thread never queues work.
final class FrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: PIPFrame?
    private var signalPending = false
    private var sequence: UInt64 = 0
    private var deliveredCount: UInt64 = 0
    private var droppedCount: UInt64 = 0
    private var closed = false

    init() {}

    /// Stores the newest frame. True when the caller should signal the consumer.
    func put(_ buffer: CVPixelBuffer, contentRect: CGRect) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        sequence &+= 1
        if frame != nil { droppedCount &+= 1 }
        frame = PIPFrame(buffer: buffer, contentRect: contentRect, sequence: sequence)
        guard !signalPending else { return false }
        signalPending = true
        return true
    }

    /// The newest frame, if any; re-arms the signal.
    func take() -> PIPFrame? {
        lock.lock()
        defer { lock.unlock() }
        signalPending = false
        guard let f = frame else { return nil }
        frame = nil
        deliveredCount &+= 1
        return f
    }

    /// Drops any unread frame (privacy: lock, sleep, stop).
    func clear() {
        lock.lock()
        frame = nil
        signalPending = false
        lock.unlock()
    }

    /// Clears and refuses further frames; for a session that is ending.
    func close() {
        lock.lock()
        frame = nil
        signalPending = false
        closed = true
        lock.unlock()
    }

    func reopen() {
        lock.lock()
        closed = false
        lock.unlock()
    }

    var counters: (delivered: UInt64, dropped: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (deliveredCount, droppedCount)
    }
}
