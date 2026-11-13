import AppKit
import Combine
import SwiftUI
import SnapticKit

/// The Dock Previews module (lead; PLAN 0.5 §2, H1, H10, §4.13, §4.22). A4a: the observer's selections go to
/// `DockPreviewController`, which shows the panel.
/// - Off costs nothing (ground rule 1): no lease, observer, timer or thread until `start()`, and `stop()` takes back
///   all of it.
/// - On, it holds a `WindowServices` lease with `.thumbnails` and `.otherSpaces` as its settings say, never `.recency`
///   (§2.3), plus `.freshness(pid)` for the app whose preview is shown (M32). The idle lease registers
///   notification-centre observers only.
/// - In Safe Mode `start()` sets `.degraded("Paused in Safe Mode")` and returns: no observer, tap, panel, capture or
///   lease (§4.13). The three `dock` verbs are A9's.
/// - `Dock.disable.<DockFeature>` kill switches are read once per start (H6).
/// - The live counters are Kit `DockLive` (§4.22); A3, A4a and A5 count up and down through `liveCount(_:up:)`.
@MainActor final class DockPreviewsModule: SnapticModule {
    let id: ModuleID = .dockPreviews
    let title = L("Dock Previews")
    let symbolName = "dock.rectangle"
    let summary = L("See an app’s windows when you point at it in the Dock.")
    private(set) var state: ModuleState = .stopped
    var tint: SettingsTint { .green }

    /// §4.22: what the module holds right now. Every value is 0 while it's off and in the selftest.
    private(set) static var live = DockLive()

    let config: ConfigStore<DockConfig>
    private let defaults: UserDefaults
    private var context: ModuleContext?
    private var lease: WindowLease?
    private var leaseNeeds: WindowNeeds = []
    private var sinks: [AnyCancellable] = []
    /// `Dock.disable.<feature>` as read at the last start (H6).
    private(set) var killSwitches: Set<DockFeature> = []
    /// Captures this module asked for since it started; A4a counts them (§4.22 "captures by path").
    private var captures = 0
    /// A3: the Dock observer, while the module runs and isn't paused.
    private var observer: DockObserver?
    /// A4a: the preview policy and panel, alongside the observer.
    private var controller: DockPreviewController?
    /// The app the lease holds `.freshness(pid)` for: the shown preview's (§2.3, M32).
    private var freshPID: Int32?

    /// §4.14: Accessibility, plus Screen Recording while Window thumbnails is on.
    var requiredPermissions: Set<Permission> { config.value.requiredPermissions }

    init(config: ConfigStore<DockConfig>, defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
    }

    // MARK: SnapticModule

    func start(_ context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        if context.safeMode.isActive {
            // §4.13: paused in Safe Mode. Nothing is created.
            state = .degraded(L("Paused in Safe Mode"))
            return
        }
        killSwitches = Self.readKillSwitches(defaults)
        leaseNeeds = Self.windowNeeds(config.value)
        lease = WindowServices.shared.acquire(id, needs: leaseNeeds, onPurge: { [weak self] in
            self?.controller?.purged()
        }, onWindowsChanged: { [weak self] pid in
            WindowManager.shared.markWindowsDirty(pid)
            self?.controller?.windowsChanged(pid)
        })
        let observer = DockObserver()
        observer.onSelection = { [weak self] selection in self?.selectionChanged(selection) }
        observer.onDockMenu = { [weak self] open in self?.controller?.dockMenu(open) }
        self.observer = observer
        observer.start()
        Self.liveCount(.observer, up: true)
        controller = DockPreviewController(observer: observer, config: config.value,
                                           keysKilled: killSwitches.contains(.keys),
                                           onFreshness: { [weak self] pid in self?.freshnessChanged(pid) },
                                           onCapture: { [weak self] count in self?.captures += count })
        config.$value
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.configChanged(value) }
            .store(in: &sinks)
        state = .running
        EventLog.shared.record(.dock, "dock.started")
        context.requestMenuRebuild()
    }

    func stop() {
        guard let context else { return }
        let wasRunning = state == .running
        sinks.removeAll()
        controller?.stop()
        controller = nil
        freshPID = nil
        if let observer {
            observer.stop()
            self.observer = nil
            Self.liveCount(.observer, up: false)
            WindowManager.shared.endWindowReads()
        }
        if let lease { WindowServices.shared.release(lease) }
        lease = nil
        leaseNeeds = []
        killSwitches = []
        captures = 0
        self.context = nil
        state = .stopped
        if wasRunning {
            EventLog.shared.record(.dock, "dock.stopped")
            context.requestMenuRebuild()
        }
    }

    func menuSection() -> [NSMenuItem] { [] }

    func settingsRoot() -> SettingsRoot {
        let module = self
        return SettingsRoot(id: SettingsRootID.dockPreviews, title: title, symbol: symbolName, tint: tint) {
            AnyView(DockShellPage(title: module.title, summary: module.summary, symbol: module.symbolName,
                                  tint: module.tint))
        }
    }

    /// §4.22: counts, booleans and enums only; no bundle id, app name or window title.
    func diagnosticsLines() -> [String] {
        var lines: [String] = []
        lines.append("State: " + Self.stateName(state))
        lines.append("Pause reason: " + (pausedInSafeMode ? "safeMode" : "none"))
        lines += (observer?.stats ?? DockObserverStats()).diagnosticsLines(observerLive: Self.live[.observer] > 0)
        lines += controller?.diagnosticsLines ?? DockPreviewCounts().lines
        lines.append("Leases: \(lease == nil ? 0 : 1)")
        lines.append("Captures: \(captures)")
        lines.append("Cache entries: \(ThumbnailStore.shared.liveEntries)")
        lines.append("Cache bytes: \(ThumbnailStore.shared.liveBytes)")
        lines.append("Thumbnails: " + (config.value.thumbnails ? "on" : "off"))
        let switches = killSwitches.map(\.rawValue).sorted()
        lines.append("Kill switches: " + (switches.isEmpty ? "none" : switches.joined(separator: ", ")))
        lines.append("Live: " + DockLiveCounter.allCases.map { "\($0.rawValue) \(Self.live[$0])" }
            .joined(separator: ", "))
        return lines
    }

    #if DEBUG
    /// G3-5: the state and diagnostics, for A6a's Safe Mode check (`ModuleHost.debugDockSafeModeProbe`).
    var debugState: (state: ModuleState, diagnostics: [String]) { (state, diagnosticsLines()) }
    #endif

    // MARK: Live counters (§4.22)

    /// A3, A4a and A5 call this once when they create one of these and once when they tear it down.
    static func liveCount(_ counter: DockLiveCounter, up: Bool) {
        if up {
            live.increment(counter)
        } else {
            live.decrement(counter)
        }
    }

    // MARK: Dock

    /// The Dock's selection, coalesced to the latest (§2.4): the preview policy takes it from here.
    private func selectionChanged(_ selection: DockSelection?) {
        guard observer != nil else { return }
        controller?.selectionChanged(selection)
    }

    /// The controller's shown app changed: the lease follows it (§2.3, M32).
    private func freshnessChanged(_ pid: Int32?) {
        freshPID = pid
        guard state == .running, let lease else { return }
        let needs = Self.windowNeeds(config.value, freshness: pid)
        guard needs != leaseNeeds else { return }
        leaseNeeds = needs
        WindowServices.shared.update(lease, needs: needs)
    }

    // MARK: Settings

    private var pausedInSafeMode: Bool { context?.safeMode.isActive == true }

    private func configChanged(_ value: DockConfig) {
        guard state == .running, let lease else { return }
        let needs = Self.windowNeeds(value, freshness: freshPID)
        if needs != leaseNeeds {
            leaseNeeds = needs
            // Dropping `.thumbnails` purges this client's entries at once (§2.3).
            WindowServices.shared.update(lease, needs: needs)
        }
        controller?.configChanged(value)
    }

    /// The Dock's lease (§2.3): `.thumbnails` and `.otherSpaces` as its settings say, never `.recency`, and
    /// `.freshness(pid)` while a preview is shown.
    static func windowNeeds(_ config: DockConfig, freshness pid: Int32? = nil) -> WindowNeeds {
        var needs: WindowNeeds = []
        if config.thumbnails { needs.insert(.thumbnails) }
        if config.otherSpaces { needs.insert(.otherSpaces) }
        if let pid { needs.insert(.freshness(pid)) }
        return needs
    }

    /// H6: `Dock.disable.<feature>` in Snaptic's persistent domain, read once per batch (here: each start).
    static func readKillSwitches(_ defaults: UserDefaults) -> Set<DockFeature> {
        KillSwitches.read(defaults.persistentDomain(forName: ConfigStore<DockConfig>.persistentDomainName),
                          prefix: "Dock", as: DockFeature.self)
    }

    private static func stateName(_ state: ModuleState) -> String {
        switch state {
        case .stopped: return "stopped"
        case .running: return "running"
        case .degraded: return "paused"
        }
    }
}

/// The K1 placeholder page; A7 replaces it with `DockPage`.
private struct DockShellPage: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: SettingsTint

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.dockPreviews)) {
            SettingsPageHeader(title, summary: summary, symbol: symbol, tint: tint)
        }
    }
}
