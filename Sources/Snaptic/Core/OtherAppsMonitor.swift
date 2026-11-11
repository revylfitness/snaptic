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

/// The second watcher (PLAN 0.4 §4.10, P-15, A3): other menu bar hiders, only while Hidden Icons runs. A running app
/// matches a `KnownMenuBarHiders` row by bundle id **and** its code-signing team, read from the running process off
/// main and only for a listed bundle id (a renamed app with a listed id but another team is not paused for).
/// `pausedFor` is the hider Hidden Icons pauses for under the policy; `onChange` runs when it changes.
@MainActor final class MenuBarHiderWatcher {
    private(set) var pausedFor: KnownMenuBarHider?
    var onChange: ((KnownMenuBarHider?) -> Void)?

    var policy: IconsOtherHiderPolicy = .pause {
        didSet { if policy != oldValue { recompute() } }
    }

    private var tokens: [NSObjectProtocol] = []
    private var running: [IconsRunningApp] = []
    private var generation: UInt64 = 0
    private let queue = DispatchQueue(label: "com.snaptic.icons.hiders", qos: .utility)

    init() {}

    var isStarted: Bool { !tokens.isEmpty }

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
        generation &+= 1
        running = []
        recompute()
    }

    /// Lists the running listed-id apps on main, reads their teams on `queue`, and decides on main.
    func scan() {
        guard isStarted else { return }
        generation &+= 1
        let gen = generation
        let candidates: [(pid: pid_t, bundleID: String)] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, let id = app.bundleIdentifier, KnownMenuBarHiders.candidate(bundleID: id) else {
                return nil
            }
            return (app.processIdentifier, id)
        }
        guard !candidates.isEmpty else {
            apply([], gen)
            return
        }
        queue.async { [weak self] in
            let apps = candidates.map { IconsRunningApp(bundleID: $0.bundleID, teamID: Self.teamID(pid: $0.pid)) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(apps, gen) } }
        }
    }

    private func apply(_ apps: [IconsRunningApp], _ gen: UInt64) {
        guard gen == generation else { return }
        running = apps
        recompute()
    }

    private func recompute() {
        let now = IconsHiderPause.pausedFor(policy: policy, running: running)
        guard now != pausedFor else { return }
        pausedFor = now
        EventLog.shared.record(.modules, "Icons: other hider \(now.map { "running: \($0.name)" } ?? "none")")
        onChange?(now)
    }

    /// The team a running process is validly signed by, or nil (unsigned, ad hoc, invalid, or gone).
    nonisolated private static func teamID(pid: pid_t) -> String? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
