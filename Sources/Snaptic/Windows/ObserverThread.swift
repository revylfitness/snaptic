import Foundation

/// A dedicated thread whose run loop hosts the AX observers, so a slow or
/// hostile app can never stall the main thread (and with it the keyboard).
/// One thread per focus-tracking session; never restarted.
final class ObserverThread: Thread {
    private let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var loop: CFRunLoop?

    override func main() {
        lock.lock(); loop = CFRunLoopGetCurrent(); lock.unlock()
        RunLoop.current.add(NSMachPort(), forMode: .default)   // keeps the run loop alive
        ready.signal()
        while !isCancelled {
            _ = RunLoop.current.run(mode: .default, before: .distantFuture)
        }
        lock.lock(); loop = nil; lock.unlock()
    }

    func waitUntilReady() {
        ready.wait()
    }

    /// Runs `block` on this thread (dropped once the thread has exited).
    func perform(_ block: @escaping () -> Void) {
        lock.lock()
        let runLoop = loop
        lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
