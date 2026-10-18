import Foundation

// Disk throughput math (owner: J; PLAN 0.3 §2.8). DiskIOSampler (app) reads IOBlockStorageDriver statistics.

package enum DiskMath {
    /// KB/s (1 KB = 1024 bytes) from per-driver "Bytes (Read)" + "Bytes (Write)" keyed by the registry entry id.
    /// Drivers present in both samples contribute their delta; a driver that appeared or vanished (hot-plug)
    /// contributes nothing, so it is neither a reset nor a spike; a counter that went down counts 0 for that driver.
    /// nil when `seconds` is invalid or no driver is in both samples (unknown).
    package static func throughputKBps(prev: [UInt64: UInt64], now: [UInt64: UInt64], seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        var total: UInt64 = 0
        var compared = false
        for (id, bytes) in now {
            guard let before = prev[id] else { continue }
            compared = true
            let delta = bytes >= before ? bytes - before : 0
            let sum = total.addingReportingOverflow(delta)
            total = sum.overflow ? UInt64.max : sum.partialValue
        }
        guard compared else { return nil }
        return Double(total) / 1024 / seconds
    }

    /// One driver's read + write total from its "Statistics" dictionary values (saturating; nil when neither is
    /// readable, so the driver is left out of the sample).
    package static func driverBytes(read: UInt64?, written: UInt64?) -> UInt64? {
        guard read != nil || written != nil else { return nil }
        let sum = (read ?? 0).addingReportingOverflow(written ?? 0)
        return sum.overflow ? UInt64.max : sum.partialValue
    }
}
