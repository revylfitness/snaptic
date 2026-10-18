import Foundation

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.8 + R5-4 (kind S): safe returns.

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
    /// multipliedFullWidth, no overflow trap. Stub: 0.
    package func nanos(_ ticks: UInt64) -> UInt64 { 0 }
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
    /// Busy share of all cores, 0...100; nil when no ticks elapsed. Stub: nil.
    package static func load(prev: CPUTicks, now: CPUTicks) -> Double? { nil }
    /// One process's CPU as % of one core. Stub: nil.
    package static func processPercent(prevTicks: UInt64, nowTicks: UInt64, seconds: Double,
                                       timebase: CPUTimebase) -> Double? { nil }
    /// The busiest same-user process and the churn over one window (R5-4). Stub: unknown.
    package static func window(prev: [ProcessCPUSample], now: [ProcessCPUSample], windowStartAbs: UInt64,
                               seconds: Double, timebase: CPUTimebase) -> (top: Double?, newProcesses: Int) {
        (nil, 0)
    }
}
