import Foundation

/// The only way to write to a helper's stdin (R3C §5.1). Owns a CLOEXEC duplicate of
/// the descriptor, never blocks the caller, coalesces heartbeats, and reports a broken
/// pipe once, on main.
final class HelperPipeWriter: @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "app.snaptic.helper-writer")
    private let lock = NSLock()
    private var closed = false
    private var broken = false
    private var heartbeatQueued = false
    private let onBroken: @Sendable () -> Void

    /// Takes its own duplicate; the caller closes the original right away.
    init?(duplicating original: Int32, onBroken: @escaping @Sendable () -> Void) {
        let d = fcntl(original, F_DUPFD_CLOEXEC, 3)
        guard d >= 0 else { return nil }
        _ = fcntl(d, F_SETNOSIGPIPE, 1)
        fd = d
        self.onBroken = onBroken
    }

    func send(_ line: Data, isHeartbeat: Bool = false) {
        lock.lock()
        if closed || broken || (isHeartbeat && heartbeatQueued) {
            lock.unlock()
            return
        }
        if isHeartbeat { heartbeatQueued = true }
        lock.unlock()

        queue.async { [self] in
            if isHeartbeat {
                lock.lock(); heartbeatQueued = false; lock.unlock()
            }
            lock.lock()
            let skip = closed || broken
            lock.unlock()
            if skip { return }
            var payload = line
            if payload.last != 0x0A { payload.append(0x0A) }
            let ok = payload.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return true }
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(fd, base + offset, raw.count - offset)
                    if n > 0 {
                        offset += n
                    } else if n < 0 && errno == EINTR {
                        continue
                    } else {
                        return false
                    }
                }
                return true
            }
            if !ok {
                lock.lock()
                let first = !broken
                broken = true
                lock.unlock()
                if first { DispatchQueue.main.async(execute: onBroken) }
            }
        }
    }

    /// Idempotent. Pending writes drain first (serial queue), then the descriptor closes.
    func close() {
        lock.lock()
        let first = !closed
        closed = true
        lock.unlock()
        if first { queue.async { [fd] in _ = Darwin.close(fd) } }
    }

    /// Waits for queued writes (quit path).
    @discardableResult
    func flush(timeout: DispatchTimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        return done.wait(timeout: .now() + timeout) == .success
    }

    deinit { if !closed { _ = Darwin.close(fd) } }
}
