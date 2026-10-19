import AppKit
import Darwin
import SnapticKit

// CPU load (owner: J; PLAN 0.3 §2.8, N9, R5-4). A 5 s `.common` timer while active: HOST_CPU_LOAD_INFO tick deltas →
// CPUMath.load, averaged over a 10 s window (the `cpu` criterion and TaskQuiet's total). Per-process sampling runs
// only while a task-sampling request lives (an untilIdle session): proc_listallpids + proc_pid_rusage(RUSAGE_INFO_V2)
// for every pid, own plus reaped-children CPU, converted with mach_timebase_info → CPUMath.window (busiest same-user
// process, new-process churn). Other users' processes aren't readable and are skipped. The previous sample is
// transient and in memory only: no names, no lists; no TCC.

@MainActor final class CPUSampler: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.cpu] }
    static let intervalSeconds: TimeInterval = 5
    /// Total load averages the last two intervals (10 s).
    static let totalWindowIntervals = 2

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private let timer = SourceTimer()
    private let taskRequests = NeedCounter()
    private var wakeObserver: NSObjectProtocol?
    private var host: mach_port_t = 0
    private let timebase = CPUSampler.readTimebase()

    private var lastTicks: CPUTicks?
    private var recentLoads: [Double?] = []
    private var lastProcesses: [ProcessCPUSample]?
    /// mach_absolute_time() right before the previous pid walk (R5-4).
    private var lastWalkStartAbs: UInt64 = 0
    private var lastWalkAt: Double = 0

    /// Busy share of all cores, 0...100, over the last 10 s; nil until two samples exist.
    private(set) var totalPercent: Double?
    /// Busiest same-user process, % of one core (own + reaped children), over the last 5 s window; nil while not
    /// sampling per process or before the second walk.
    private(set) var topProcessPercent: Double?
    /// Same-user processes first seen in the last window that started inside it; nil like `topProcessPercent`.
    private(set) var newProcesses: Int?

    init() {}

    /// Per-process sampling while `lifetime` lives (SessionController, for an untilIdle session; R5-4).
    func requestTaskSampling(_ lifetime: Lifetime) { taskRequests.add(lifetime) }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        host = mach_host_self()
        taskRequests.onChange = { [weak self] in self?.taskSamplingChanged() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetBaselines() }
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
        taskRequests.onChange = nil
        if host != 0 { mach_port_deallocate(mach_task_self_, host) }
        host = 0
        resetBaselines()
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active else { return }
        facts.cpuPercent = totalPercent
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Sampling

    /// A wake (the first delta after it is discarded) or a stop: every baseline goes, values read unknown.
    private func resetBaselines() {
        lastTicks = nil
        recentLoads = []
        lastProcesses = nil
        totalPercent = nil
        topProcessPercent = nil
        newProcesses = nil
        if active { changes.fire() }
    }

    private func taskSamplingChanged() {
        guard active else { return }
        if !taskRequests.isNeeded {
            lastProcesses = nil
            topProcessPercent = nil
            newProcesses = nil
            changes.fire()
        } else {
            sampleProcesses()
        }
    }

    private func sample() {
        guard active else { return }
        if let ticks = readTicks() {
            if let prev = lastTicks {
                recentLoads.append(CPUMath.load(prev: prev, now: ticks))
                if recentLoads.count > Self.totalWindowIntervals { recentLoads.removeFirst(recentLoads.count - Self.totalWindowIntervals) }
            }
            lastTicks = ticks
            totalPercent = CPUMath.average(recentLoads)
        } else {
            lastTicks = nil
            recentLoads = []
            totalPercent = nil
        }
        if taskRequests.isNeeded { sampleProcesses(fire: false) }
        changes.fire()
    }

    private func sampleProcesses(fire: Bool = true) {
        let walkStart = mach_absolute_time()
        let now = AwakeSourceClock.now()
        let samples = Self.readProcesses()
        if let prev = lastProcesses, !samples.isEmpty {
            let w = CPUMath.window(prev: prev, now: samples, windowStartAbs: lastWalkStartAbs, seconds: now - lastWalkAt,
                                   timebase: timebase)
            topProcessPercent = w.top
            newProcesses = w.top == nil ? nil : w.newProcesses
        } else {
            topProcessPercent = nil
            newProcesses = nil
        }
        lastProcesses = samples.isEmpty ? nil : samples
        lastWalkStartAbs = walkStart
        lastWalkAt = now
        if fire { changes.fire() }
    }

    private func readTicks() -> CPUTicks? {
        guard host != 0 else { return nil }
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)   // CPU_STATE_USER, SYSTEM, IDLE, NICE
    }

    /// Every readable pid's counters. proc_pid_rusage fails (EPERM) for other users' processes, which are skipped.
    private nonisolated static func readProcesses() -> [ProcessCPUSample] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let got = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.stride))
        }
        guard got > 0 else { return [] }
        var out: [ProcessCPUSample] = []
        out.reserveCapacity(Int(got))
        for pid in pids.prefix(Int(min(got, Int32(pids.count)))) where pid > 0 {
            var info = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard status == 0 else { continue }
            let own = info.ri_user_time &+ info.ri_system_time
            let children = info.ri_child_user_time &+ info.ri_child_system_time
            out.append(ProcessCPUSample(pid: pid, startAbs: info.ri_proc_start_abstime, cpuTicks: own &+ children))
        }
        return out
    }

    private nonisolated static func readTimebase() -> CPUTimebase {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer != 0, info.denom != 0 else { return .identity }
        return CPUTimebase(numer: info.numer, denom: info.denom)
    }
}
