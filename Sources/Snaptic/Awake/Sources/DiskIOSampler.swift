import AppKit
import IOKit
import SnapticKit

// Disk throughput for "Until Downloads and Tasks Finish" (owner: J; PLAN 0.3 §2.8, N9). Active only while `taskQuiet`
// needs it; a 5 s `.common` timer then reads every IOBlockStorageDriver's "Statistics" ("Bytes (Read)" + "Bytes
// (Write)") keyed by registry entry id → DiskMath. Read-only registry properties: no device is opened, no TCC. The
// counters are system-wide, so Spotlight and Time Machine I/O count as busy (HW-23).

@MainActor final class DiskIOSampler: AwakeServiceLifecycle {
    static let intervalSeconds: TimeInterval = 5

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private let timer = SourceTimer()
    private var wakeObserver: NSObjectProtocol?
    private var last: (bytes: [UInt64: UInt64], at: Double)?

    /// KB/s over the last interval; nil until two samples exist and after a wake.
    private(set) var kBps: Double?

    init() {}

    /// Multicast like the criterion sources: TaskQuiet re-steps on every sample.
    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetBaseline() }
        }
        timer.start(every: Self.intervalSeconds, tolerance: 0.5) { [weak self] in self?.sample() }
        sample()
    }

    func deactivate() {
        guard active else { return }
        active = false
        timer.cancel()
        if let token = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        wakeObserver = nil
        last = nil
        kBps = nil
        context = nil
    }

    // MARK: Sampling

    private func resetBaseline() {
        last = nil
        kBps = nil
        if active { changes.fire() }
    }

    private func sample() {
        guard active else { return }
        let now = AwakeSourceClock.now()
        let bytes = Self.readDrivers()
        if let last, let bytes {
            kBps = DiskMath.throughputKBps(prev: last.bytes, now: bytes, seconds: now - last.at)
        } else {
            kBps = nil
        }
        if let bytes { last = (bytes: bytes, at: now) } else { last = nil }
        changes.fire()
    }

    /// Registry entry id → read + write bytes for every block storage driver; nil when the registry can't be read.
    private nonisolated static func readDrivers() -> [UInt64: UInt64]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var out: [UInt64: UInt64] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)
            guard let stats = property?.takeRetainedValue() as? [String: Any] else { continue }
            let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value
            let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value
            if let total = DiskMath.driverBytes(read: read, written: written) { out[id] = total }
        }
        return out
    }
}
