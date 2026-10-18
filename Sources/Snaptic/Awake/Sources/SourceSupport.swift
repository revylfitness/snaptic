import CryptoKit
import Foundation
import Security
import SnapticKit

// Shared plumbing for J's Awake sources (owner: J; PLAN 0.3 §2.8): the continuous clock, a `.common`-mode timer,
// need counting by lifetime, a typed fan-out, and Awake's salted identifiers.

/// The continuous clock every source stamps with (CLOCK_MONOTONIC_RAW, the base of `AwakeModule.clockNow()`).
enum AwakeSourceClock {
    static func now() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9 }
}

/// A main-run-loop timer in `.common` modes (it keeps firing while a menu is open; lint L14). Repeating or one-shot;
/// `cancel()` is idempotent and the timer never outlives it.
@MainActor final class SourceTimer {
    private var timer: Timer?
    private(set) var interval: TimeInterval = 0

    init() {}

    var isRunning: Bool { timer != nil }

    func start(every interval: TimeInterval, tolerance: TimeInterval, _ tick: @escaping @MainActor () -> Void) {
        cancel()
        self.interval = interval
        let t = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        t.tolerance = tolerance
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func once(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        cancel()
        interval = delay
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                fire()
            }
        }
        t.tolerance = min(0.25, delay / 10)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

/// Requests bound to lifetimes ("sample per process while an untilIdle session runs"): needed while at least one
/// request's lifetime is alive. `onChange` runs whenever `isNeeded` flips.
@MainActor final class NeedCounter {
    private var live: Set<UInt64> = []
    private var next: UInt64 = 0
    var onChange: (@MainActor () -> Void)?

    init() {}

    var isNeeded: Bool { !live.isEmpty }

    func add(_ lifetime: Lifetime) {
        guard !lifetime.isEnded else { return }
        next &+= 1
        let id = next
        let was = isNeeded
        live.insert(id)
        lifetime.onEnd { [weak self] in
            guard let self, self.live.remove(id) != nil, !self.isNeeded else { return }
            self.onChange?()
        }
        if !was { onChange?() }
    }
}

/// ChangeFanout with a payload (SystemEventsMonitor's events, VolumeMonitor's will-unmount).
@MainActor final class EventFanout<Event> {
    private var handlers: [(id: UInt64, run: @MainActor (Event) -> Void)] = []
    private var next: UInt64 = 0

    init() {}

    func add(_ lifetime: Lifetime, _ handler: @escaping @MainActor (Event) -> Void) {
        guard !lifetime.isEnded else { return }
        next &+= 1
        let id = next
        handlers.append((id, handler))
        lifetime.onEnd { [weak self] in self?.handlers.removeAll { $0.id == id } }
    }

    func fire(_ event: Event) {
        for handler in handlers { handler.run(event) }
    }
}

/// Awake's salted identifiers (§2.7, §3.6): SHA-256(SnapticAwakeSalt ‖ material) in lowercase hex. The salt is 32
/// random bytes in its own persistent-domain key, created on first use, read from the persistent domain only (a
/// launch argument can't inject one) and never exported. Raw MACs and serials are hashed at once and never kept.
enum AwakeIdentity {
    @MainActor static func salt() -> Data {
        if let cached = cachedSalt { return cached }
        let domain = UserDefaults.standard.persistentDomain(forName: ConfigStore<AwakeConfig>.persistentDomainName)
        if let data = domain?[AwakeSaltRules.key] as? Data, AwakeSaltRules.isValid(data) {
            cachedSalt = data
            return data
        }
        var bytes = [UInt8](repeating: 0, count: AwakeSaltRules.length)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess || !bytes.contains(where: { $0 != 0 }) {
            var g = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: 1...255, using: &g) }
        }
        let data = Data(bytes)
        UserDefaults.standard.set(data, forKey: AwakeSaltRules.key)
        cachedSalt = data
        return data
    }

    @MainActor private static var cachedSalt: Data?

    static func hash(_ material: String, salt: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(material.utf8))
        return AwakeHashMaterial.hex(Array(hasher.finalize()))
    }

    /// The stored form of a router MAC ("Connected to this network"); nil unless the MAC normalizes.
    @MainActor static func routerHash(mac: String) -> String? {
        AwakeHashMaterial.router(mac: mac).map { hash($0, salt: salt()) }
    }

    /// The stored form of a Bluetooth device identity (`AwakeHashMaterial.bluetoothAudio` / `bluetoothInput`).
    @MainActor static func bluetoothHash(_ material: String) -> String {
        hash(material, salt: salt())
    }

    /// The stored form of a USB serial; nil for devices without a usable serial.
    @MainActor static func usbSerialHash(_ serial: String) -> String? {
        AwakeHashMaterial.usbSerial(serial).map { hash($0, salt: salt()) }
    }
}

/// The "Until Downloads and Tasks Finish" signals in one place (N9, R5-4), for SessionController: the `taskQuiet`
/// dynamic need activates cpu, disk and network; `request` adds the per-process CPU walk and network throughput while
/// the session's lifetime lives; `sample` reads the five signals now (unknown ones stay nil, which TaskQuiet treats as
/// busy); `observe` fires after every 5 s CPU sample (and after a wake reset), the tick TaskQuiet.step runs on.
@MainActor enum TaskActivityProbe {
    static func request(_ context: AwakeContext, lifetime: Lifetime) {
        context.cpu.requestTaskSampling(lifetime)
        context.network.requestTaskSampling(lifetime)
    }

    static func sample(_ context: AwakeContext) -> TaskActivitySample {
        TaskActivitySample(topProcessPercent: context.cpu.topProcessPercent, newProcesses: context.cpu.newProcesses,
                           totalCPUPercent: context.cpu.totalPercent, diskKBps: context.disk.kBps,
                           networkKBps: context.network.throughputKBps)
    }

    static func observe(_ context: AwakeContext, lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) {
        context.cpu.observe(lifetime, handler)
    }
}
