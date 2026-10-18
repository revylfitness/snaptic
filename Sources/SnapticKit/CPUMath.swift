import Foundation

// CPU math for Awake (owner: J; PLAN 0.3 §2.8, R5-4). Pure, unit-tested on Linux. CPUSampler (app) reads the counters.

/// host_statistics HOST_CPU_LOAD_INFO, UInt32 tick counters.
package struct CPUTicks: Equatable, Sendable {
    package var user, system, idle, nice: UInt32
    package init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// `mach_timebase_info`: rusage times are Mach absolute units (Apple silicon 125/3, Intel 1/1).
package struct CPUTimebase: Equatable, Sendable {
    package var numer: UInt32
    package var denom: UInt32
    package init(numer: UInt32, denom: UInt32) {
        self.numer = numer
        self.denom = denom
    }

    /// The 1/1 timebase (Intel), also the fallback when mach_timebase_info fails.
    package static let identity = CPUTimebase(numer: 1, denom: 1)

    /// ticks · numer / denom with a full-width product, so nothing traps: a zero numer or denom is read as 1, and a
    /// result beyond UInt64 saturates.
    package func nanos(_ ticks: UInt64) -> UInt64 {
        let n = UInt64(numer == 0 ? 1 : numer)
        let d = UInt64(denom == 0 ? 1 : denom)
        let product = ticks.multipliedFullWidth(by: n)
        guard product.high < d else { return UInt64.max }
        return d.dividingFullWidth(product).quotient
    }
}

/// One pid's counters at one sample (R5-4).
package struct ProcessCPUSample: Equatable, Sendable {
    package var pid: Int32
    /// rusage_info_v2.ri_proc_start_abstime (Mach absolute units, same call). Identity = pid + startAbs.
    package var startAbs: UInt64
    /// user + system + child user + child system (Mach units).
    package var cpuTicks: UInt64
    package init(pid: Int32, startAbs: UInt64, cpuTicks: UInt64) {
        self.pid = pid
        self.startAbs = startAbs
        self.cpuTicks = cpuTicks
    }
}

package enum CPUMath {
    /// Busy share of all cores, 0...100, from two HOST_CPU_LOAD_INFO samples. Each counter's delta is a wrapping
    /// UInt32 subtraction (the kernel's counters wrap); nil when no ticks elapsed.
    package static func load(prev: CPUTicks, now: CPUTicks) -> Double? {
        let user = UInt64(now.user &- prev.user)
        let system = UInt64(now.system &- prev.system)
        let nice = UInt64(now.nice &- prev.nice)
        let idle = UInt64(now.idle &- prev.idle)
        let busy = user + system + nice
        let total = busy + idle
        guard total > 0 else { return nil }
        return min(100, max(0, Double(busy) * 100 / Double(total)))
    }

    /// One process's CPU as % of one core (100 = one core) from rusage tick deltas over `seconds` of wall time.
    /// A counter that went down reads 0; nil when `seconds` is not a positive finite number.
    package static func processPercent(prevTicks: UInt64, nowTicks: UInt64, seconds: Double,
                                       timebase: CPUTimebase) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let delta = nowTicks >= prevTicks ? nowTicks - prevTicks : 0
        return percent(ticks: delta, seconds: seconds, timebase: timebase)
    }

    /// The busiest same-user process and the churn over one window (R5-4).
    ///
    /// `windowStartAbs` = mach_absolute_time() read right before the PREVIOUS sample's pid walk; `seconds` = the
    /// continuous-clock delta between the two samples. Same pid + startAbs in both → tick delta (a counter that went
    /// down → 0). First seen now with startAbs ≥ windowStartAbs → all its ticks, and it counts in `newProcesses`.
    /// First seen now with an older startAbs → nothing (it existed before the window but wasn't readable then).
    /// `top` = the largest per-process share (100 = one core); a reap spike may exceed 100, which only reads as busy.
    /// `top` is nil when `seconds` is invalid or `now` is empty (nothing readable: unknown, never "quiet").
    /// Duplicate pids in a sample keep their first entry.
    package static func window(prev: [ProcessCPUSample], now: [ProcessCPUSample], windowStartAbs: UInt64,
                               seconds: Double, timebase: CPUTimebase) -> (top: Double?, newProcesses: Int) {
        var before: [Int32: ProcessCPUSample] = [:]
        for s in prev where before[s.pid] == nil { before[s.pid] = s }
        var seen = Set<Int32>()
        var newProcesses = 0
        var topTicks: UInt64?
        for s in now {
            guard seen.insert(s.pid).inserted else { continue }
            let ticks: UInt64
            if let p = before[s.pid], p.startAbs == s.startAbs {
                ticks = s.cpuTicks >= p.cpuTicks ? s.cpuTicks - p.cpuTicks : 0
            } else if s.startAbs >= windowStartAbs {
                ticks = s.cpuTicks
                newProcesses += 1
            } else {
                ticks = 0
            }
            topTicks = max(topTicks ?? 0, ticks)
        }
        guard seconds.isFinite, seconds > 0, let topTicks else { return (nil, newProcesses) }
        return (percent(ticks: topTicks, seconds: seconds, timebase: timebase), newProcesses)
    }

    /// The average of the per-interval loads, for the "10 s window" total: nil entries (no ticks) are skipped.
    package static func average(_ loads: [Double?]) -> Double? {
        let known = loads.compactMap { $0 }.filter(\.isFinite)
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +) / Double(known.count)
    }

    private static func percent(ticks: UInt64, seconds: Double, timebase: CPUTimebase) -> Double {
        Double(timebase.nanos(ticks)) / 1e9 / seconds * 100
    }
}
