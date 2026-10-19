import AppKit
import SnapticKit

/// Watches for BetterDisplay, MonitorControl and Lunar (PLAN §3.8). With "Pause overlapping
/// Snaptic features" (the default) the Displays features they also drive are paused while
/// they run; "Run both anyway" pauses nothing.
@MainActor final class OtherAppsMonitor {
    /// Known display apps running now, in Kit order.
    private(set) var running: [OtherDisplayApp] = []
    private var paused: [DisplayFeature: OtherDisplayApp] = [:]
    private var tokens: [NSObjectProtocol] = []

    var policy: OtherAppsPolicy = .pauseOverlapping {
        didSet { if policy != oldValue { recompute() } }
    }

    init() {}

    /// Displays features paused because an overlapping display app runs (PLAN §3.8).
    var pausedDisplayFeatures: Set<DisplayFeature> { Set(paused.keys) }

    /// User-facing reason for a paused feature, e.g. "Paused while MonitorControl runs".
    func pauseReason(for feature: DisplayFeature) -> String? {
        paused[feature].map(OtherDisplayApps.pauseReason)
    }

    /// The same reason in Title Case for a menu status row, e.g. "Paused While MonitorControl Runs".
    func menuPauseReason(for feature: DisplayFeature) -> String? {
        paused[feature].map(OtherDisplayApps.menuPauseReason)
    }

    /// Set by DisplaysModule; called when the paused set changes.
    var onChange: (@MainActor () -> Void)?
    /// Set by the host: apps that just started (banner/toast), and any change at all.
    var onAppsAppeared: (@MainActor ([OtherDisplayApp]) -> Void)?
    var onRunningChange: (@MainActor () -> Void)?

    var isStarted: Bool { !tokens.isEmpty }

    /// Scans now and on every app launch and quit. Idempotent.
    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            })
        }
        scan()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = []
    }

    /// Re-reads the running apps (also used at Displays start).
    func scan() {
        let ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let now = OtherDisplayApps.detect(bundleIDs: ids)
        guard now != running else { return }
        let appeared = now.filter { app in !running.contains(app) }
        running = now
        EventLog.shared.record(.modules, "Other display apps running: \(now.count)")
        recompute()
        onRunningChange?()
        if !appeared.isEmpty { onAppsAppeared?(appeared) }
    }

    private func recompute() {
        let new = OtherDisplayApps.paused(running: running, policy: policy)
        let changed = Set(new.keys) != Set(paused.keys) || new.contains { paused[$0.key] != $0.value }
        paused = new
        if changed { onChange?() }
    }
}
