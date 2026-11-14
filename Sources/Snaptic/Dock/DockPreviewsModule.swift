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
/// - In Safe Mode `start()` sets `.degraded("Paused in Safe Mode")`, registers the `dock` verbs and returns: no
///   observer, tap, panel, capture or lease (§4.13).
/// - A9: `DockCLI`'s three `dock` verbs are registered whenever the module is on (Safe Mode included) and end with
///   `stop()` (§4.21). The module is their `DockCLITarget`.
/// - A6b: another Dock preview tool, VoiceOver and `dock pause` pause it (`DockPauseSources`, Kit `DockPauseRules`).
///   The state stays `.running`. A pause takes the engine (lease, observer, controller) down, except VoiceOver's
///   while Dock click actions work (§4.11, §4.16). Each pause change is one EventLog line, enums only (§4.22).
/// - A6b: while a Window Switcher session is open (`WindowServices.switcherSessionActive`) nothing shows or swaps.
/// - `Dock.disable.<DockFeature>` kill switches are read once per start (H6).
/// - The live counters are Kit `DockLive` (§4.22); A3, A4a and A5 count up and down through `liveCount(_:up:)`.
/// - A7: the Settings page (`DockPage`), the Snaptic menu section (`DockMenuRows`) and the attention mark, all from Kit
///   `DockPageRules` over `pageFacts()`. A change to the observer's read state, a permission, a stopped window
///   feature or a breaker rebuilds the menu; row 5's mark comes from a one-shot timer two minutes after it shows.
@MainActor final class DockPreviewsModule: SnapticModule, DockCLITarget {
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
    /// A6b: what can pause the module while it runs (§4.15, §4.16, §4.21); nil in Safe Mode and while off.
    private var pauseSources: DockPauseSources?
    /// A6b: the pause the module holds (Kit `DockPauseRules.effective`); `.safeMode` in Safe Mode.
    private(set) var pause: DockPauseReason?
    /// A5: the listen-only Dock click tap (§4.11), while click actions or Restore all are on, and the observer's
    /// latest selection, raw, for a tap made mid-run.
    private var clickTap: DockClickTap?
    private var dockSelection: DockSelection?
    /// A7: fires when row 5's attention mark is due (X2-16), to rebuild the menu; counted in `.timers`.
    private var attentionTimer: Timer?
    /// A9: `snaptic dock …`, registered from `start()` to `stop()`.
    private lazy var cli = DockCLI(target: self)

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
            pause = .safeMode
            cli.registerVerbs(on: context.commands, lifetime: context.lifetime)   // A9 (P3-2)
            return
        }
        killSwitches = Self.readKillSwitches(defaults)
        let sources = DockPauseSources()
        sources.onChange = { [weak self] in self?.syncPause() }
        pauseSources = sources
        sources.start()
        WindowServices.shared.observeSwitcherSession(id) { [weak self] open in self?.controller?.switcher(open: open) }
        config.$value
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.configChanged(value) }
            .store(in: &sinks)
        // A7: the page's and menu's rows follow a stopped window feature and a permission (§4.17).
        NotificationCenter.default.publisher(for: PrivateWindowAPI.stopsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readChanged() }
            .store(in: &sinks)
        context.permissions.observe(lifetime: context.lifetime) { [weak self] permission, granted in
            guard let self else { return }
            // Row 4 ends: attach now rather than at the ladder's next step. The click tap that trust took (or never
            // got) comes back too; the keys tap is made again at the next show.
            if permission == .accessibility, granted {
                self.observer?.reattach()
                self.syncClickTap(self.config.value)
            }
            self.readChanged()
        }
        state = .running
        EventLog.shared.record(.dock, "dock.started")
        // The engine starts here unless a pause holds already.
        syncPause()
        cli.registerVerbs(on: context.commands, lifetime: context.lifetime)   // A9
        context.requestMenuRebuild()
    }

    func stop() {
        guard let context else { return }
        let wasRunning = state == .running
        cli.stop()   // A9: rows 1 and 2 have no verbs
        sinks.removeAll()
        WindowServices.shared.observeSwitcherSession(id, nil)
        stopEngine()
        pauseSources?.stop()
        pauseSources = nil
        pause = nil
        killSwitches = []
        captures = 0
        self.context = nil
        state = .stopped
        if wasRunning {
            EventLog.shared.record(.dock, "dock.stopped")
            context.requestMenuRebuild()
        }
    }

    // MARK: Engine (A6b)

    /// The lease, the observer and the controller (§2.3, §2.4). A3, A4a and A5 set up here.
    private func startEngine() {
        guard state == .running, controller == nil else { return }
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
        observer.onReadChanged = { [weak self] in self?.readChanged() }   // A7
        self.observer = observer
        observer.start()
        Self.liveCount(.observer, up: true)
        let controller = DockPreviewController(observer: observer, config: config.value,
                                               keysKilled: killSwitches.contains(.keys),
                                               onFreshness: { [weak self] pid in self?.freshnessChanged(pid) },
                                               onCapture: { [weak self] count in self?.captures += count })
        controller.onKeysBreakerTripped = { [weak self] in self?.readChanged() }   // A7
        self.controller = controller
        // Before any selection arrives: the VoiceOver pause the engine runs under, and an open switcher session.
        if let pause { controller.pauseChanged(pause) }
        if WindowServices.shared.switcherSessionActive { controller.switcher(open: true) }
        syncClickTap(config.value)   // A5
    }

    /// Everything `startEngine()` made, at once and with no fade. A3, A4a and A5 tear down here.
    private func stopEngine() {
        cancelAttentionTimer()   // A7
        stopClickTap()   // A5
        dockSelection = nil   // A5
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
    }

    // MARK: Pauses (A6b; §4.15, §4.16, §4.21)

    /// A pause source or a setting changed: the pause is worked out again, logged when it changes, and the engine
    /// follows it (ground rule 1, M49).
    private func syncPause() {
        guard state == .running, pauseSources != nil else { return }
        let old = pause
        let new = DockPauseRules.effective(pageFacts())
        pause = new
        if let line = DockPauseRules.eventLine(from: old, to: new) { EventLog.shared.record(.dock, line) }
        if DockPauseRules.engineRuns(pause: new, clicksWork: clicksWork) {
            if controller == nil {
                startEngine()
            } else if new != old {
                controller?.pauseChanged(new)
            }
            clickTap?.pause = new   // A5: the VoiceOver pause doesn't stop click actions

        } else {
            stopEngine()
        }
        if new != old { context?.requestMenuRebuild() }
        // A7: rows 6 to 8 name the tool or the clock, which can change while the pause stays the same.
        context?.requestSettingsRefresh()
    }

    /// A click action or Restore All is on, `Dock.disable.clickActions` isn't set (§4.11) and the click breaker
    /// hasn't tripped (§4.17).
    private var clicksWork: Bool {
        let value = config.value
        return (value.clickActions != .doNothing || value.restoreAllMinimized) && !killSwitches.contains(.clickActions)
            && !Self.clickBreakerTripped
    }

    /// A9's `dock pause` and the menu's Pause for 1 Hour: holds a command pause, never shortening one (G2-12).
    /// Returns its end in Unix seconds; nil while the module doesn't run or is in Safe Mode. `DockCLI` checks the row
    /// first.
    @discardableResult
    func pauseByCommand(seconds: Int) -> Double? {
        pauseSources?.pause(seconds: seconds)
    }

    /// A9's `dock resume` and the page's and menu's Resume: clears a held command pause. False when none was held.
    @discardableResult
    func resumeCommandPause() -> Bool {
        pauseSources?.resume() ?? false
    }

    /// §4.17's facts as the module sees them now: for the pause, `dock status`, the page and the menu. The page passes
    /// rows 1 and 2's facts; while the module runs neither holds. The stopped window features are the ones shown on
    /// both pages (`WindowStopRows.dockPage`).
    func pageFacts(killSwitch: Bool = false, enabled: Bool = true) -> DockPageFacts {
        let value = config.value
        let read = DockPauseRules.read(observer?.stats)
        let stopped = PrivateWindowAPI.stoppedFeatures()
        let shown = WindowStopRows.dockPage(crashGuard: stopped.crashGuard, poisoned: stopped.poisoned)
        return DockPageFacts(killSwitch: killSwitch, enabled: enabled, safeMode: pausedInSafeMode,
                             accessibility: granted(.accessibility),
                             read: read.read, loginLadderEnded: read.ladderEnded, unreadableSince: read.unreadableSince,
                             now: ProcessInfo.processInfo.systemUptime,
                             runningBundleIDs: pauseSources?.runningToolIDs ?? [],
                             runAlongsideOtherTools: value.runAlongsideOtherTools,
                             voiceOverOn: pauseSources?.voiceOverOn ?? false, showWithVoiceOver: value.showWithVoiceOver,
                             clickActionOn: value.clickActions != .doNothing, restoreAllOn: value.restoreAllMinimized,
                             commandPause: pauseSources?.commandPause, paneName: PermissionFlow.paneName(.accessibility),
                             thumbnailsOn: value.thumbnails, screenRecording: granted(.screenRecording),
                             clickBreakerTripped: Self.clickBreakerTripped,
                             keysBreakerTripped: Self.keysBreakerTripped,
                             crashGuardStops: shown.crashGuard.map(\.displayName),
                             poisoned: shown.poisoned.map(\.displayName))
    }

    /// A permission now: through the context's `PermissionFlow` while on (a self-test's never asks macOS, R5.5),
    /// else macOS's answer.
    private func granted(_ permission: Permission) -> Bool {
        guard let context else { return PermissionFlow.isGranted(permission) }
        return context.permissions.state(permission) == .granted
    }

    /// `dock status`'s facts (§4.21); nil while the module is off.
    func statusFacts() -> DockStatusFacts? {
        guard context != nil else { return nil }
        let live = Self.live
        let counts = DockStatusLiveCounts(observer: live[.observer], clickTap: live[.clickTap], keys: live[.keys],
                                          panel: live[.panel], timers: live[.timers],
                                          leases: WindowServices.shared.liveLeases)
        return DockPauseRules.status(pageFacts(), keysOn: config.value.keys, killed: killSwitches,
                                     clickBreakerTripped: Self.clickBreakerTripped,
                                     keysBreakerTripped: Self.keysBreakerTripped,
                                     cacheEntries: ThumbnailStore.shared.liveEntries,
                                     cacheBytes: ThumbnailStore.shared.liveBytes,
                                     observerAttached: live[.observer] > 0 && observer?.stats.attached == true,
                                     live: counts)
    }

    // MARK: Menu and Settings (A7; §4.17, §4.18, §4.19)

    /// §4.19: built fresh on each open; empty while the module is off.
    func menuSection() -> [NSMenuItem] {
        guard context != nil else { return [] }
        return DockMenuRows(module: self).items()
    }

    /// Row 4, row 5 two minutes after it shows, or a tripped breaker (§4.17).
    var menuAttention: Bool {
        context != nil && DockPageRules.attention(pageFacts())
    }

    var highlights: [FeatureHighlight] { DockPage.highlights }

    func settingsRoot() -> SettingsRoot { DockPage.settingsRoot(module: self) }

    func settingsIndex() -> [SettingsSearchEntry] { DockPage.searchEntries() }

    /// Row 4's and the Screen Recording row's [Open Privacy Settings…], and the menu's Open … Settings….
    func openPrivacy(_ permission: Permission) {
        guard let context else { return }
        if permission == .accessibility {
            context.permissions.presentGuide(.accessibility, reason: L("Dock Previews needs it to read the Dock."))
        } else {
            context.permissions.presentGuide(permission)
        }
    }

    /// Row 5's [Try Again]: the observer attaches again at once (and a debug build's M47 hook ends).
    func tryAgain() {
        observer?.retry()
        readChanged()
    }

    /// A stopped window feature's [Try Again] (§4.17): clears that feature's disabled builds.
    func tryAgain(_ feature: WindowFeature) {
        PrivateWindowAPI.tryAgain(feature)
    }

    /// A breaker row's [Relaunch Snaptic].
    func relaunch() {
        context?.relauncher.relaunch(reason: "dock breaker")
    }

    func openSettings(_ page: String) {
        context?.openSettings(page)
    }

    /// The observer's read state, a permission, a stopped window feature or a breaker changed: the menu (its rows and
    /// attention mark) and the page follow, and row 5's attention timer is set again (§4.17, X2-16).
    private func readChanged() {
        guard let context else { return }
        syncAttentionTimer()
        context.requestMenuRebuild()
        context.requestSettingsRefresh()
    }

    private func syncAttentionTimer() {
        cancelAttentionTimer()
        guard state == .running, observer != nil, let due = DockPageRules.attentionDue(pageFacts()) else { return }
        let wait = max(0, due - ProcessInfo.processInfo.systemUptime)
        let timer = Timer(fire: Date(timeIntervalSinceNow: wait), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.attentionTimerFired() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        attentionTimer = timer
        Self.liveCount(.timers, up: true)
    }

    private func attentionTimerFired() {
        cancelAttentionTimer()
        context?.requestMenuRebuild()
    }

    private func cancelAttentionTimer() {
        guard let attentionTimer else { return }
        attentionTimer.invalidate()
        self.attentionTimer = nil
        Self.liveCount(.timers, up: false)
    }

    /// §4.22: counts, booleans and enums only; no bundle id, app name or window title.
    func diagnosticsLines() -> [String] {
        var lines: [String] = []
        lines.append("State: " + Self.stateName(state))
        lines.append(DockPauseRules.pauseLine(pause))
        lines += (observer?.stats ?? DockObserverStats()).diagnosticsLines(observerLive: Self.live[.observer] > 0)
        lines += controller?.diagnosticsLines ?? DockPreviewCounts().lines
        lines += clickAndKeyLines   // A5
        lines.append("Leases: \(lease == nil ? 0 : 1)")
        lines.append("Captures: \(captures)")
        lines.append("Cache entries: \(ThumbnailStore.shared.liveEntries)")
        lines.append("Cache bytes: \(ThumbnailStore.shared.liveBytes)")
        lines.append("Thumbnails: " + (config.value.thumbnails ? "on" : "off"))
        let switches = killSwitches.map(\.rawValue).sorted()
        lines.append("Kill switches: " + (switches.isEmpty ? "none" : switches.joined(separator: ", ")))
        lines.append("Live: " + DockLiveCounter.allCases.map { "\($0.rawValue) \(Self.live[$0])" }
            .joined(separator: ", "))
        lines += Self.symbolLines(safeMode: pausedInSafeMode)
        return lines
    }

    /// §4.12, §4.22: each window symbol's state, from the lookups, the guards and the probe cache only (no private
    /// call, no probe). `hwCapture: safeMode` in Safe Mode (M33).
    private static func symbolLines(safeMode: Bool) -> [String] {
        let defaults = UserDefaults.standard
        var probed: [WindowSymbolID: String] = [:]
        for id in WindowSymbolID.allCases {
            probed[id] = defaults.string(forKey: CrashGuard.probedKey(id.rawValue))
        }
        return DockPauseRules.symbolLines(PrivateWindowAPI.launchReports(), probedBuilds: probed,
                                          currentBuild: InflightMarkers.build, safeMode: safeMode)
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
        dockSelection = selection   // A5
        clickTap?.selection = selection   // A5
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
        guard state == .running else { return }
        // Run alongside other tools, Show with VoiceOver and the click settings can start or end a pause.
        syncPause()
        guard let lease else { return }
        let needs = Self.windowNeeds(value, freshness: freshPID)
        if needs != leaseNeeds {
            leaseNeeds = needs
            // Dropping `.thumbnails` purges this client's entries at once (§2.3).
            WindowServices.shared.update(lease, needs: needs)
        }
        controller?.configChanged(value)
        syncClickTap(value)   // A5
    }

    // MARK: A5 keys and clicks

    /// §4.17: true once three disables by macOS in 60 s turned keys off, until relaunch.
    static var keysBreakerTripped: Bool { DockKeys.breaker.tripped }
    /// §4.17: true once three disables by macOS in 60 s turned click actions off, until relaunch.
    static var clickBreakerTripped: Bool { DockClickTap.breaker.tripped }

    /// The click tap runs while the settings ask for it, with no `Dock.disable.clickActions` at start and no tripped
    /// breaker; a settings change creates or removes it.
    private func syncClickTap(_ value: DockConfig) {
        let wanted = observer != nil && DockClickTap.wanted(value) && !killSwitches.contains(.clickActions)
            && !DockClickTap.breaker.tripped
        guard wanted else {
            stopClickTap()
            return
        }
        if let clickTap {
            clickTap.config = value
            clickTap.pause = pause
            return
        }
        let defaults = defaults
        let geometry = observer?.geometry
        clickTap = DockClickTap(config: value,
                                geometry: { geometry?.snapshot ?? DockGeometrySnapshot() },
                                killSwitch: { Self.readKillSwitches(defaults).contains(.clickActions) },
                                onStopped: { [weak self] tripped in
                                    // A tripped breaker can end the VoiceOver pause's reason to run (§4.17).
                                    self?.clickTap = nil
                                    self?.syncPause()
                                    if tripped { self?.readChanged() }   // A7: its row and attention mark
                                })
        clickTap?.selection = dockSelection
        clickTap?.pause = pause
    }

    private func stopClickTap() {
        clickTap?.stop()
        clickTap = nil
    }

    /// §4.22: booleans, counts and enums only.
    private var clickAndKeyLines: [String] {
        var lines = ["Keys breaker: " + (Self.keysBreakerTripped ? "tripped" : "ok"),
                     "Click tap: " + (clickTap?.isRunning == true ? "on" : "off")
                        + ", breaker " + (Self.clickBreakerTripped ? "tripped" : "ok")]
        lines += clickTap?.diagnosticsLines ?? []
        return lines
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
