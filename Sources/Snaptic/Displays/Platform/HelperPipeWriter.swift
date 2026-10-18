import Foundation
import SnapticKit

/// The only way to write to a helper's stdin (R3C §5.1). Owns a CLOEXEC, non-blocking
/// duplicate of the descriptor, never blocks the caller, coalesces heartbeats, and reports
/// a broken pipe once, on main. A reader that stops reading can't make Snaptic buffer
/// without bound: more than `maxQueuedBytes` waiting counts as a broken pipe.
final class HelperPipeWriter: @unchecked Sendable {
    /// Bytes that may wait for a slow reader before the pipe counts as broken.
    static let maxQueuedBytes = 1 << 20

    private let fd: Int32
    private let queue = DispatchQueue(label: "app.snaptic.helper-writer")
    /// Guards everything below. Writes are non-blocking, so holding it across one is short.
    private let lock = NSLock()
    /// False once close() is called: new sends are refused, queued ones still go out.
    private var accepting = true
    private var closed = false
    private var broken = false
    /// Lines waiting, partial writes, heartbeat coalescing and the cap (Kit, tested).
    private var pending = PipeWriteQueue(capacity: HelperPipeWriter.maxQueuedBytes)
    /// Fires while the pipe is full and something waits; suspended otherwise.
    private var writeSource: DispatchSourceWrite?
    private var sourceRunning = false
    private var drainWaiters: [DispatchSemaphore] = []
    private let onBroken: @Sendable () -> Void

    /// Takes its own duplicate; the caller closes the original right away. The duplicate
    /// shares the open file description, so the original becomes non-blocking too.
    init?(duplicating original: Int32, onBroken: @escaping @Sendable () -> Void) {
        let d = fcntl(original, F_DUPFD_CLOEXEC, 3)
        guard d >= 0 else { return nil }
        _ = fcntl(d, F_SETNOSIGPIPE, 1)
        let flags = fcntl(d, F_GETFL)
        guard flags >= 0, fcntl(d, F_SETFL, flags | O_NONBLOCK) == 0 else {
            _ = Darwin.close(d)
            return nil
        }
        fd = d
        self.onBroken = onBroken
    }

    /// Bytes waiting to be written (diagnostics, tests).
    var pendingBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.queuedBytes
    }

    var isBroken: Bool {
        lock.lock(); defer { lock.unlock() }
        return broken
    }

    func send(_ line: Data, isHeartbeat: Bool = false) {
        lock.lock()
        if !accepting || broken {
            lock.unlock()
            return
        }
        switch pending.enqueue(line, isHeartbeat: isHeartbeat) {
        case .queued:
            lock.unlock()
            queue.async { [self] in pump() }
        case .coalesced:
            lock.unlock()
        case .overCap:
            // The reader stopped reading: as good as a broken pipe.
            let first = markBrokenLocked()
            lock.unlock()
            if first { DispatchQueue.main.async(execute: onBroken) }
        }
    }

    /// Idempotent. Pending writes drain first, then the descriptor closes.
    func close() {
        lock.lock()
        let first = accepting
        accepting = false
        lock.unlock()
        if first { queue.async { [self] in pump() } }
    }

    /// Waits for queued writes (quit path). True when nothing is left to write (also when
    /// the pipe broke and the rest was dropped).
    @discardableResult
    func flush(timeout: DispatchTimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        lock.lock()
        if pending.isEmpty || broken || closed {
            lock.unlock()
            return true
        }
        drainWaiters.append(done)
        lock.unlock()
        queue.async { [self] in pump() }
        return done.wait(timeout: .now() + timeout) == .success
    }

    // MARK: Queue

    private enum Drain { case drained, wouldBlock, failed }

    /// Writes what it can without blocking; waits for writability when the pipe is full.
    private func pump() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        var notifyBroken = false
        switch drainLocked() {
        case .drained:
            pauseSourceLocked()
        case .wouldBlock:
            resumeSourceLocked()
        case .failed:
            notifyBroken = markBrokenLocked()
            pauseSourceLocked()
        }
        var waiters: [DispatchSemaphore] = []
        if pending.isEmpty {
            waiters = drainWaiters
            drainWaiters = []
            if !accepting { closeLocked() }
        }
        lock.unlock()
        waiters.forEach { $0.signal() }
        if notifyBroken { DispatchQueue.main.async(execute: onBroken) }
    }

    private func drainLocked() -> Drain {
        while let head = pending.head {
            let n = head.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.write(fd, base, raw.count)
            }
            if n > 0 {
                pending.consume(n)
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 && errno == EAGAIN {
                return .wouldBlock
            } else {
                return .failed
            }
        }
        return .drained
    }

    /// True the first time. Drops whatever was still queued.
    private func markBrokenLocked() -> Bool {
        let first = !broken
        broken = true
        pending.removeAll()
        return first
    }

    private func resumeSourceLocked() {
        if writeSource == nil {
            let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.pump() }
            // The source owns the descriptor once it exists: it closes after cancellation.
            let descriptor = fd
            source.setCancelHandler { _ = Darwin.close(descriptor) }
            writeSource = source
        }
        if !sourceRunning, let writeSource {
            sourceRunning = true
            writeSource.resume()
        }
    }

    private func pauseSourceLocked() {
        if sourceRunning, let writeSource {
            sourceRunning = false
            writeSource.suspend()
        }
    }

    private func closeLocked() {
        guard !closed else { return }
        closed = true
        if let source = writeSource {
            writeSource = nil
            // A suspended source never runs its cancel handler.
            if !sourceRunning { source.resume() }
            sourceRunning = false
            source.cancel()
        } else {
            _ = Darwin.close(fd)
        }
    }

    // A queued block retains self, so deinit runs only after every queued block.
    deinit {
        lock.lock()
        closeLocked()
        lock.unlock()
    }
}
