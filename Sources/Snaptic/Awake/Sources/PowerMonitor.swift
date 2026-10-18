import AppKit
import Combine
import IOKit.ps
import SnapticKit

// Power source, battery, Low Power Mode and thermal state (owner: J; PLAN 0.3 §2.6, §2.8, R5-6). Always active with
// `sessions` (guards need it). Events only: the IOPS run-loop source (power source and percent changes), the Low Power
// Mode and thermal notifications, and wake; a 60 s `.common` re-check runs only while `falling` is true so the flag
// ages out. The battery history lives in memory only.

@MainActor final class PowerMonitor: ObservableObject, CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.power] }
    weak var context: AwakeContext?
    /// nil until the first IOPS read and while inactive.
    @Published private(set) var facts: PowerFacts?
    /// The R5-6 window (in memory only).
    private(set) var history: [BatteryReading] = []
    private let changes = ChangeFanout()
    private var active = false
    private var source: CFRunLoopSource?
    private var refcon: UnsafeMutableRawPointer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private let recheck = SourceTimer()

    /// A battery seen once stays "present" for the process lifetime (r3 security M3): a read that later misses it is
    /// "unreadable", never "desktop".
    private static var batterySeen = false

    init() {}

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        startPowerSourceNotifications()
        let center = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let wake = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((workspace, wake))
        refresh()
    }

    func deactivate() {
        guard active else { return }
        active = false
        stopPowerSourceNotifications()
        for o in observers { o.center.removeObserver(o.token) }
        observers = []
        recheck.cancel()
        history = []
        facts = nil
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        facts.power = self.facts
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Reading

    /// Re-reads IOPS and the process-info states now (guards call it before deciding; also every notification).
    func refresh() {
        guard active else { return }
        let now = AwakeSourceClock.now()
        let read = Self.readPowerSources()
        if read.battery != nil { Self.batterySeen = true }
        if let battery = read.battery, let percent = battery.percent {
            history = PowerMath.appending(BatteryReading(percent: percent, charging: battery.charging,
                                                         currentMilliamps: battery.currentMilliamps, at: now), to: history)
        }
        let present = Self.batterySeen
        let falling = present && PowerMath.falling(history, now: now)
        let new = PowerFacts(batteryPresent: present,
                             onAC: read.onAC,
                             percent: read.battery?.percent,
                             charging: read.battery?.charging ?? false,
                             falling: falling,
                             lastRecovery: PowerMath.lastRecovery(history),
                             lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                             thermal: Self.thermalLevel(ProcessInfo.processInfo.thermalState))
        scheduleRecheck(falling: falling)
        guard new != facts else { return }
        facts = new
        changes.fire()
    }

    /// While `falling` holds, recompute every 60 s so it ages out without a new IOPS event (R5-6).
    private func scheduleRecheck(falling: Bool) {
        if falling {
            guard !recheck.isRunning else { return }
            recheck.start(every: PowerMath.recheckSeconds, tolerance: 5) { [weak self] in self?.refresh() }
        } else {
            recheck.cancel()
        }
    }

    private struct BatteryRead {
        var percent: Int?
        var charging: Bool
        var currentMilliamps: Int?
    }

    /// The providing source and the internal battery, if any. An unreadable IOPS blob reads as "not on AC" with the
    /// battery unknown (fail-safe: the battery rules apply when a battery was ever seen).
    private static func readPowerSources() -> (onAC: Bool, battery: BatteryRead?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (!batterySeen, nil) }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        // "AC Power" (kIOPMACPowerKey); "Battery Power" and "UPS Power" are not the adapter.
        let onAC = providing.map { $0 == "AC Power" } ?? !batterySeen
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d["Type"] as? String == "InternalBattery" else { continue }
            if let presentFlag = d["Is Present"] as? Bool, !presentFlag { continue }
            let percent = PowerMath.percent(current: d["Current Capacity"] as? Int, max: d["Max Capacity"] as? Int)
            return (onAC, BatteryRead(percent: percent, charging: d["Is Charging"] as? Bool ?? false,
                                      currentMilliamps: d["Current"] as? Int))
        }
        return (onAC, nil)
    }

    private static func thermalLevel(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .critical
        }
    }

    // MARK: IOPS notifications

    /// IOPSNotificationCreateRunLoopSource fires for power-source and percent changes; added to the main run loop in
    /// `.common` modes. The refcon is a retained CallbackTarget, released when the source is removed.
    private func startPowerSourceNotifications() {
        guard source == nil else { return }
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        let callback: IOPowerSourceCallbackType = { refcon in
            guard let refcon else { return }
            let box = Unmanaged<CallbackTarget<PowerMonitor>>.fromOpaque(refcon).takeUnretainedValue()
            // The source runs on the main run loop; hop anyway so the handler never runs inside IOKit's callout.
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.refresh() } }
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, box)?.takeRetainedValue() else {
            Unmanaged<CallbackTarget<PowerMonitor>>.fromOpaque(box).release()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
        refcon = box
    }

    private func stopPowerSourceNotifications() {
        if let s = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes)
            CFRunLoopSourceInvalidate(s)
        }
        source = nil
        if let box = refcon {
            // Queued hops retain the box themselves (takeUnretainedValue + capture), so this release is safe.
            Unmanaged<CallbackTarget<PowerMonitor>>.fromOpaque(box).release()
        }
        refcon = nil
    }
}
