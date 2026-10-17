import Foundation

/// The main thread stamps every 0.5 s; helper heartbeats read the age from any thread
/// (R2C §4.5). The clock is uptime (mach absolute time), which pauses during sleep, so a
/// long sleep never reads as a hang.
final class HostHeartbeat: @unchecked Sendable {
    static let shared = HostHeartbeat()
    private let lock = NSLock()
    private var lastStampNs = DispatchTime.now().uptimeNanoseconds
    private var timer: Timer?
    private var ticks: [@MainActor () -> Void] = []

    private init() {}

    /// Starts the 0.5 s `.common` timer (it keeps beating during menus and modal panels).
    /// `tick` runs on every beat, right after the stamp. Idempotent.
    @MainActor func start(_ tick: (@MainActor () -> Void)? = nil) {
        if let tick { ticks.append(tick) }
        guard timer == nil else { return }
        stamp()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stamp()
                for tick in self.ticks { tick() }
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @MainActor func stop() {
        timer?.invalidate()
        timer = nil
        ticks = []
    }

    /// Call on the main thread.
    func stamp() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock(); lastStampNs = now; lock.unlock()
    }

    /// How long ago the main thread last stamped. Any thread.
    func mainAgeMillis() -> UInt64 {
        lock.lock(); let last = lastStampNs; lock.unlock()
        let now = DispatchTime.now().uptimeNanoseconds
        return now > last ? (now - last) / 1_000_000 : 0
    }
}
