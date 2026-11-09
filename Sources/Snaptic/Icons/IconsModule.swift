import AppKit
import Combine
import SwiftUI
import SnapticKit

/// The Hidden Icons module (lead; PLAN 0.4 §2, §4, H1, H3, H4, H6, H12; A5). It owns one `IconsEngineCore` per run
/// and feeds it the policy: every intent goes through `IconsIntentQueue`, every gate through Kit's policy types.
///
/// - The stores are `ModuleHost`'s (one owner); the module reads and writes them.
/// - Safe Mode skips the module (H6): `start` reports it and creates nothing.
/// - The engine is Native on macOS 27 and later (crash guard, encodings, identity first), Length on 14–26. When the
///   factory says unavailable the arrow still shows, and clicking it opens Settings.
/// - Kill switches are read at start and polled once a second: `DefaultsKeyObserver` refuses dotted keys (R3).
/// - `stop()` expands at once (the core invalidates without waiting), removes the items and stops every monitor,
///   timer and sink; nothing outlives it (A5's 20× on/off check).
/// - Logs never name an app (L20): counters, fixed text and enum raw values only.
@MainActor final class IconsModule: SnapticModule {
    let id: ModuleID = .hiddenIcons
    let title = L("Hidden Icons")
    let symbolName = "eye.slash.fill"
    let summary = L("Hide the menu bar icons you don’t need behind an arrow.")
    private(set) var state: ModuleState = .stopped
    var tint: SettingsTint { .teal }

    /// H4: constant per OS. Native can't collapse without the read; on 14–26 the list asks on demand.
    var requiredPermissions: Set<Permission> {
        Self.osMajor >= IconsEngineFactory.nativeMajor ? [.accessibility] : []
    }

    // MARK: Keys (§4.11)

    static let inFlightKey = "Icons.native.inFlight"
    static let disabledBuildKey = "Icons.native.disabledBuild"
    /// `"<CFBundleVersion>|<OS build>"` of the last start, for launch collapse's version and OS checks.
    static let launchSeenKey = "Icons.launch.seen"
    /// The 1 s poll: kill switches, Accessibility trust, Length's own-items guard, the stable gate.
    static let tickInterval: Double = 1

    // MARK: Stores and host facts

    let config: ConfigStore<IconsConfig>
    let apps: ConfigStore<IconsAppsState>
    private let defaults: UserDefaults

    /// Set by `ModuleHost`: a Displays resolution trial is pending (Length waits before re-applying lengths).
    var displayTrialPending: () -> Bool = { false }
    /// Set by `ModuleHost`: Awake keeps the Mac awake, or lid-closed mode is on (the own-items guard).
    var awakeHolding: () -> Bool = { false }
    /// Set by `ModuleHost`: Snaptic's other status items (`StatusMenu.iconsOwnItems`), for Length's guard.
    var ownItems: () -> [IconsOwnItem] = { [] }

    // MARK: Long-lived parts

    let items: IconsItems
    private let scheduler = IconsScheduler()
    private let monitors: IconsMonitors
    private let hiders = MenuBarHiderWatcher()
    private let watchdog = IconsWatchdog()
    /// The camera and microphone (R3-90).
    private let capture: IconsCaptureMonitor

    // MARK: One run

    private var context: ModuleContext?
    private var core: IconsEngineCore?
    private var native: NativeBackend?
    private var inventory: AXInventory?
    private(set) var engineKind: IconsEngineKind?
    private(set) var unavailableReason: IconsUnavailableReason?
    private var queue = IconsIntentQueue(state: .expanded(.plain))
    private var auto = IconsAutoCollapse(seconds: IconsConfig.defaultAutoCollapseSeconds)
    private var gate = IconsStableGate(startedAt: 0)
    private var access = IconsAccessTracker(trusted: false)
    private(set) var killSwitches: Set<IconsFeature> = []
    private var identityOK = true
    private var crashTripped = false
    private var osBuild = ""
    private var tick: IconsCancellable?
    private var autoTimer: IconsCancellable?
    private var recollapse: IconsCancellable?
    /// The hide that waits for the camera or microphone's dot to fade (R3-90).
    private var captureResume: IconsCancellable?
    /// `showDuringCapture` as last applied, to act on a change.
    private var keepCaptureVisible = true
    private var sinks: [AnyCancellable] = []
    /// The source of the collapse being run, for the gates (the stable gate holds launch collapse only).
    private var collapseSource: IconsIntentSource?
    private var lastPresented: IconsEngineState?
    private var launchWaiting = false
    private var lastGateRead: Double = 0
    private var knownOwnIDs: Set<String>?
    /// The Privacy pane [Open Privacy Settings] opened: watched until System Settings stops being frontmost.
    private var privacyPane: PrivacyPane = .closed
    private enum PrivacyPane { case closed, opened, front }
    /// The 27 first-collapse question was answered this process (§4.0).
    private var firstCollapseAsked = false
    private var firstCollapseAsking = false

    // MARK: Status (A6/A7 read these)

    private(set) var lastRefusal: IconsRefusal?
    private(set) var lastFailSafe: IconsFailSafeReason?
    /// Wall-clock time of `lastFailSafe` (X-25's "Icons were shown at 9:41 …").
    private(set) var lastFailSafeAt: Date?
    private(set) var ownItemsDecision: IconsOwnItemsDecision = .ok
    /// The arrow's own menu is open (A6 sets it): the auto-collapse timer waits.
    var ownMenuOpen = false
    private(set) var lastHiddenListPress: Double?
    /// The Snaptic-menu section and the arrow's menu (A6).
    private lazy var menuRows = IconsMenuRows(module: self)
    /// `snaptic icons …` and the shortcut (A9).
    private lazy var cli = IconsCLI(module: self)

    /// Launch collapse is decided once per process, at the first start (§4.6).
    private static var launchDecided = false
    /// The fail-safe toast shows once per launch (§4.17).
    private static var failSafeToastShown = false
    /// Read once per process, before the first start writes it.
    private static var launchMarks: (versionChanged: Bool, osBuildChanged: Bool)?

    init(config: ConfigStore<IconsConfig>, apps: ConfigStore<IconsAppsState>, defaults: UserDefaults = .standard) {
        self.config = config
        self.apps = apps
        self.defaults = defaults
        items = IconsItems(defaults: defaults)
        monitors = IconsMonitors(scheduler: scheduler)
        capture = IconsCaptureMonitor(scheduler: scheduler)
    }

    // MARK: Facts

    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// `kern.osversion`, e.g. "27C5040b".
    static func currentOSBuild() -> String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    private static var uptime: Double { ProcessInfo.processInfo.systemUptime }
    private static var wall: Double { Date().timeIntervalSince1970 }

    /// The engine's state, or unavailable while the module is off.
    var engineState: IconsEngineState {
        if let core { return core.state }
        return .unavailable(unavailableReason ?? .stopped)
    }

    var layout: IconsLayout? { core?.layout }
    var accessState: IconsAccessState { access.state }
    var pausedFor: KnownMenuBarHider? { hiders.pausedFor }
    var examPaused: Bool { engineKind == .native && monitors.examReported }
    /// R3-90: hiding waits while the camera or microphone is on.
    var capturePaused: Bool {
        IconsCaptureGuard.pauses(engine: engineKind, keepVisible: config.value.showDuringCapture,
                                 inUse: capture.reported)
    }

    // MARK: SnapticModule

    func start(_ context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        if context.safeMode.isActive {
            // H6: Safe Mode skips Hidden Icons. Nothing is created.
            state = .degraded(L("Paused in Safe Mode"))
            return
        }
        osBuild = Self.currentOSBuild()
        killSwitches = PrivateMenuBarAPI.killSwitches(defaults)
        let major = Self.osMajor
        var inputs = IconsFactoryInputs(osMajor: major, currentBuild: osBuild, killSwitches: killSwitches)
        crashTripped = false
        if major >= IconsEngineFactory.nativeMajor {
            let guardResult = IconsCrashGuard.atStart(inFlight: defaults.string(forKey: Self.inFlightKey),
                                                      disabledBuild: defaults.string(forKey: Self.disabledBuildKey),
                                                      currentBuild: osBuild)
            if let disabled = guardResult.disabledBuild {
                defaults.set(disabled, forKey: Self.disabledBuildKey)
            } else {
                defaults.removeObject(forKey: Self.disabledBuildKey)
            }
            if guardResult.clearInFlight { defaults.removeObject(forKey: Self.inFlightKey) }
            crashTripped = guardResult.tripped
            if crashTripped { EventLog.shared.record(.icons, "Icons: the last activation didn't finish") }
            let probe = PrivateMenuBarAPI.verify()
            inputs.shimAvailable = probe.present
            inputs.shimVerified = probe.mismatches.isEmpty
            inputs.shimPoisoned = probe.state == .poisoned
            inputs.disabledBuild = guardResult.disabledBuild
            identityOK = IconsIdentity.passes()
            inputs.identityOK = identityOK
        } else {
            identityOK = true
        }
        let kind: IconsEngineKind = major >= IconsEngineFactory.nativeMajor ? .native : .length
        let value = config.value
        items.onClick = { [weak self] action in self?.clicked(action) }
        items.onVisibilityLost = { [weak self] role in self?.visibilityLost(role) }
        items.onDirectionChange = { [weak self] _ in self?.inputsChanged() }
        items.menuProvider = { [weak self] in self?.menuRows.arrowMenu() }
        items.start(engine: kind, alwaysHidden: value.alwaysHidden, dividers: value.dividers)

        switch IconsEngineFactory.choose(inputs) {
        case .unavailable(let reason):
            unavailableReason = reason
            engineKind = nil
            EventLog.shared.record(.icons, "Icons: unavailable, \(reason.rawValue)")
        case .engine(let engine):
            unavailableReason = nil
            engineKind = engine
            startEngine(engine)
        }
        subscribe()
        state = .running
        cli.start(context)
        refreshPresentation()
        decideLaunch()
    }

    private func startEngine(_ engine: IconsEngineKind) {
        var visibility: NativeBackend?
        if engine == .native {
            let backend = NativeBackend()
            backend.onCount = { [weak self] counter in self?.count(counter) }
            backend.onActivated = { [weak self] in self?.watchdog.debugHangIfRequested() }
            visibility = backend
        }
        if engine == .native || !killSwitches.contains(.inventory) {
            let reader = AXInventory()
            reader.onCount = { [weak self] counter in self?.count(counter) }
            inventory = reader
        }
        native = visibility
        var appsValue = apps.value
        let kept = IconsNewIcons.expired(appsValue.newShown, now: Self.wall)
        if kept != appsValue.newShown {
            appsValue.newShown = kept
            apps.value = appsValue
        }
        access = IconsAccessTracker(trusted: AXIsProcessTrusted())
        auto = IconsAutoCollapse(seconds: config.value.autoCollapseSeconds)
        gate = IconsStableGate(startedAt: Self.uptime)
        let core = IconsEngineCore(engine: engine, items: items, visibility: visibility, inventory: inventory,
                                   scheduler: scheduler, host: self, inputs: engineInputs(), cache: appsValue.layout)
        self.core = core
        queue.restart(state: core.state)
        startMonitors(engine)
        core.start()
        if engine == .native { watchdog.start() }
        scheduleTick()
    }

    private func startMonitors(_ engine: IconsEngineKind) {
        monitors.displayTrialPending = { [weak self] in self?.displayTrialPending() ?? false }
        monitors.onHoverDwell = { [weak self] in self?.submit(.command(.show), from: .hover) }
        monitors.onNewAppReread = { [weak self] in self?.newAppReread() }
        monitors.onScreenParameters = { [weak self] in self?.core?.screenParametersChanged() }
        monitors.onDisplayTrialPending = { [weak self] pending in self?.core?.setDisplayTrialPending(pending) }
        monitors.onRecovery = { [weak self] event in self?.recover(event) }
        monitors.onExamChange = { [weak self] active in self?.examChanged(active) }
        monitors.start()
        keepCaptureVisible = config.value.showDuringCapture
        capture.onChange = { [weak self] inUse in self?.captureChanged(inUse) }
        hiders.policy = config.value.otherHiders
        hiders.onChange = { [weak self] hider in self?.hiderChanged(hider) }
        hiders.start()
        watchdog.onRelease = { [weak self] in
            self?.count(.hangExpand)
            self?.submit(.failSafe(.hang), from: .monitor)
        }
    }

    func stop() {
        guard context != nil else { return }
        cli.stop()
        if let core {
            _ = queue.submit(.stop, from: .monitor, now: Self.uptime)
            core.stop()
        }
        core = nil
        native = nil
        inventory = nil
        engineKind = nil
        tick?.cancel()
        tick = nil
        autoTimer?.cancel()
        autoTimer = nil
        recollapse?.cancel()
        recollapse = nil
        captureResume?.cancel()
        captureResume = nil
        capture.stop()
        auto.disarm()
        sinks.removeAll()
        watchdog.stop()
        watchdog.onRelease = nil
        // `stop()` recomputes and would call back mid-teardown.
        hiders.onChange = nil
        hiders.stop()
        monitors.stop()
        clearMonitorCallbacks()
        items.stop()
        items.onClick = nil
        items.onVisibilityLost = nil
        items.onDirectionChange = nil
        items.menuProvider = nil
        defaults.removeObject(forKey: Self.inFlightKey)
        ActivationPolicyController.shared.iconsShown(false, cause: .other, fullBarOnExpand: false)
        launchWaiting = false
        collapseSource = nil
        lastPresented = nil
        knownOwnIDs = nil
        ownItemsDecision = .ok
        unavailableReason = nil
        ownMenuOpen = false
        state = .stopped
        context = nil
    }

    private func clearMonitorCallbacks() {
        monitors.displayTrialPending = nil
        monitors.onHoverDwell = nil
        monitors.onNewAppReread = nil
        monitors.onScreenParameters = nil
        monitors.onDisplayTrialPending = nil
        monitors.onRecovery = nil
        monitors.onExamChange = nil
    }

    /// The Snaptic menu lists it only with Arrow and Snaptic Menu (the plan's `shared`, H2); it stays even when the
    /// list is empty.
    func menuSection() -> [NSMenuItem] {
        guard state == .running else { return [] }
        return menuRows.items(arrow: false)
    }

    func settingsRoot() -> SettingsRoot { IconsPage.settingsRoot(module: self) }

    /// Sections › (§4.9).
    func settingsDestination(_ route: SettingsRoute) -> AnyView? {
        guard route.id == IconsSectionsPageControls.surface else { return nil }
        return AnyView(IconsSectionsPage(module: self))
    }

    var highlights: [FeatureHighlight] { IconsPage.highlights }
    func settingsIndex() -> [SettingsSearchEntry] { IconsPage.searchEntries() }

    /// §4.12: the tab's attention mark shows for needs-permission (27), unavailable and paused.
    var menuAttention: Bool {
        guard state == .running else { return false }
        if case .unavailable(let reason) = engineState, reason != .stopped { return true }
        if pausedFor != nil || examPaused { return true }
        return engineKind == .native && access.state.needsPermission
    }

    // MARK: Commands (the menu, the CLI and Settings use this; A6, A7, A8)

    /// One intent from `source`, through the queue. `done` gets the collapse's result once it finished, or nil when
    /// the intent ran no collapse (an expand, no change, a drop); it is called exactly once.
    func perform(_ command: IconsCommand, from source: IconsIntentSource,
                 done: ((IconsCollapseResult?) -> Void)? = nil) {
        submit(.command(command), from: source, done: done)
    }

    /// Sections › Refresh (A7). Native while the read is limited is **Show All Icons and Refresh**: it expands with ⌥
    /// (the read follows the expand) and leaves the icons shown; auto-collapse re-arms.
    func refreshLayout() {
        guard let core else { return }
        if layoutLimited {
            perform(.showAll, from: .settings)
        } else {
            core.refreshLayout()
        }
    }

    /// Native's read is restricted or the icons are hidden, so Sections shows the cached list.
    var layoutLimited: Bool {
        guard let core, core.engine == .native else { return false }
        return core.isRestricted || core.state.isCollapsed
    }

    // MARK: Settings (A7)

    /// What decides the status row.
    func pageFacts() -> IconsPageFacts {
        let value = config.value
        let all = screens()
        let toggle = items.frame(of: .toggle)
        let separator = items.frame(of: .separator)
        var facts = IconsPageFacts(engine: engineKind, state: engineState, access: access.state,
                                   pausedFor: pausedFor, examPaused: examPaused, capturePaused: capturePaused)
        facts.arrowVisible = items.isVisible(.toggle)
        facts.dividerVisible = engineKind != .length || items.isVisible(.separator)
        facts.alwaysHidden = value.alwaysHidden
        facts.alwaysHiddenVisible = !value.alwaysHidden || items.isVisible(.alwaysHidden)
        // A collapsed bar was valid when it collapsed; Length's wide `|` makes frames meaningless until it expands.
        if let engineKind, !engineState.isCollapsed {
            facts.arrangementValid = IconsGuards.arrangementValid(engine: engineKind, toggle: toggle,
                                                                  separator: separator,
                                                                  rightToLeft: items.rightToLeft)
            if value.alwaysHidden {
                let screen = toggle.flatMap { IconsGeometry.screen(holding: $0, in: all) } ?? all.first
                facts.alwaysHiddenPlaced = IconsGuards.alwaysHiddenPlaced(
                    engine: engineKind, toggle: toggle, separator: separator,
                    alwaysHidden: items.frame(of: .alwaysHidden), screen: screen?.frame,
                    rightToLeft: items.rightToLeft)
            }
        }
        facts.arranged = value.arranged
        facts.hiddenCount = hiddenCount
        facts.refusal = lastRefusal
        facts.ownItems = ownItemsDecision.row
        facts.failSafe = lastFailSafe
        facts.failSafeTime = lastFailSafeAt.map { DateFormatter.localizedString(from: $0, dateStyle: .none,
                                                                                timeStyle: .short) }
        if let readAt = apps.value.layout?.readAt, readAt > 0 { facts.cacheAge = max(Self.wall - readAt, 0) }
        return facts
    }

    /// `snaptic icons status` (A9): engine, state and counts of the live read.
    func cliFacts() -> IconsStatusFacts {
        IconsCLIRules.facts(engine: engineKind, state: engineState,
                            needsPermission: engineKind == .native && access.state.needsPermission,
                            paused: pausedFor != nil, layout: core?.layout,
                            ownBundleID: Bundle.main.bundleIdentifier ?? "", now: Self.wall)
    }

    /// The Settings status row's text (the CLI's line for a refusal it has none of its own for).
    func statusText() -> String { IconsPageRules.status(pageFacts()).text }

    /// Hidden and Always Hidden icons in the last read; nil without one.
    var hiddenCount: Int? {
        core?.layout.map { layout in layout.sections.values.filter { $0 != .shown }.count }
    }

    /// The Sections page's lists: the live layout, else the cached one (Native while limited).
    func sectionsList() -> IconsSectionsList {
        let appsValue = apps.value
        let sections = core?.layout?.sections ?? appsValue.layout?.sections ?? [:]
        let system = core?.layout?.systemBundles ?? []
        let own = Bundle.main.bundleIdentifier ?? ""
        var names: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier, sections[bundle] != nil, names[bundle] == nil else { continue }
            names[bundle] = app.localizedName ?? ""
        }
        return IconsPageRules.sections(sections.filter { $0.key != own }, system: system,
                                       choices: appsValue.choices, newShown: Set(appsValue.newShown.keys),
                                       engine: engineKind ?? .length, names: names)
    }

    /// A Sections pop-up: nil is Where It Is.
    func setChoice(_ choice: IconsAppChoice?, for bundle: String) {
        var value = apps.value
        value.choices[bundle] = choice
        if choice != nil { value.newShown[bundle] = nil }
        apps.value = value
    }

    /// [Show Arrow] / [Show Divider] (G-4).
    func showItem(_ role: IconsItemRole) {
        items.show(role)
        refreshPresentation()
        requestRefresh()
    }

    /// [Show Arrow] for whichever item is missing.
    func showMissingItems() {
        for role in IconsItemRole.allCases where !items.isVisible(role) {
            if role == .separator, engineKind != .length { continue }
            if role == .alwaysHidden, !config.value.alwaysHidden { continue }
            items.show(role)
        }
        refreshPresentation()
        requestRefresh()
    }

    /// Advanced › Reset Arrow Position… (§4.2.5): expand, remove the items, clear their position and visibility
    /// keys, re-seed and recreate them (the next start does both), and arrange again.
    func resetArrowPosition() {
        guard let context else { return }
        stop()
        for role in IconsItemRole.allCases {
            defaults.removeObject(forKey: IconsSeeding.key(role.autosaveName))
            defaults.removeObject(forKey: "NSStatusItem Visible " + role.autosaveName)
        }
        var value = config.value
        value.arranged = false
        config.value = value
        firstCollapseAsked = false
        EventLog.shared.record(.icons, "Icons: arrow position reset")
        start(context)
    }

    /// [Open Privacy Settings]: the pane opens, and its closing starts the 5 s not-effective check (§4.12).
    func openPrivacy() {
        privacyPane = .opened
        context?.permissions.presentGuide(.accessibility, reason: L("Needed by Hidden Icons."))
    }

    /// [Relaunch Snaptic].
    func relaunch() {
        context?.relauncher.relaunch(reason: "icons permission")
    }

    /// A hidden-list row was pressed (A6): the auto-collapse timer waits a minute.
    func hiddenListPressed() {
        lastHiddenListPress = Self.uptime
        queue.hiddenListPressed(now: Self.uptime)
    }

    // MARK: The hidden list (§4.8, A6)

    func openSettings(_ page: String) {
        context?.openSettings(page)
    }

    /// Rows may be pressed: AXPress isn't turned off and there is an inventory to press through.
    var pressEnabled: Bool { inventory != nil && !killSwitches.contains(.axpress) }

    func listFacts() -> IconsListFacts {
        IconsListFacts(engine: engineKind, state: engineState, access: access.state, pausedFor: pausedFor,
                       examPaused: examPaused, capturePaused: capturePaused, inventoryOff: inventory == nil)
    }

    /// The rows of the last good layout, named after their running apps.
    func hiddenList() -> IconsHiddenList {
        let layout = core?.layout
        var names: [Int32: String] = [:]
        for pid in (layout?.extras.map(\.extra.pid) ?? []) + (layout?.offScreen.map(\.pid) ?? [])
        where names[pid] == nil {
            names[pid] = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        }
        return IconsHiddenListRules.list(layout, names: names, screens: screens(), rightToLeft: items.rightToLeft)
    }

    /// A menu with the list opened: a background re-read where one can be trusted.
    func listOpened() {
        core?.listOpened()
    }

    /// A row was chosen (§4.8): the same app instance still runs (pid, bundle, launch date), the icons it needs are
    /// shown first, then the inventory waits for the icon, checks it and presses it. A mismatch does nothing; the next
    /// open re-reads.
    func press(_ row: IconsListRow, launchDate: Date?) {
        guard pressEnabled, let inventory, let core else { return }
        guard let app = NSRunningApplication(processIdentifier: row.extra.pid), !app.isTerminated,
              app.bundleIdentifier == row.extra.bundleID, app.launchDate == launchDate else { return }
        // The expand below must not be collapsed again by the timer while the menu opens.
        hiddenListPressed()
        if let mode = IconsHiddenListRules.expand(for: row.section, state: core.state) {
            perform(mode == .all ? .showAll : .show, from: .hiddenList)
        }
        let all = screens()
        let arrowScreen = items.frame(of: .toggle).flatMap { IconsGeometry.screen(holding: $0, in: all) }
        guard let screen = (arrowScreen ?? all.first)?.frame else { return }
        inventory.press(row, screen: screen) { [weak self] outcome in
            guard outcome == .pressed else { return }
            self?.hiddenListPressed()
        }
    }

    /// The Privacy pane Snaptic opened has closed (A7).
    func permissionPaneClosed() {
        access.paneClosed(at: Self.uptime)
    }

    /// [Try Again] on the crash-guard row: Native may run on this build again, from the next start.
    func clearDisabledBuild() {
        defaults.removeObject(forKey: Self.disabledBuildKey)
        guard let context else { return }
        stop()
        start(context)
    }

    // MARK: Intents

    private func submit(_ intent: IconsIntent, from source: IconsIntentSource,
                        done: ((IconsCollapseResult?) -> Void)? = nil) {
        guard let core else {
            done?(.unavailable)
            return
        }
        if case .command(let command) = intent, asksFirst(command, from: source, core: core) {
            // The CLI never asks (`asksFirst`); `done` still gets its one answer, after the alert.
            askBeforeFirstCollapse(intent, from: source, done: done)
            return
        }
        let result = queue.submit(intent, from: source, now: Self.uptime)
        switch result {
        case .run(let step, let seq):
            run(step, seq: seq, source: source, core: core, done: done)
        case .noChange:
            if case .command = intent, source == .timer || source == .launch { auto.disarm() }
            // A hide while a collapse is still calibrating joins it, so its caller hears how it ended.
            if let done, case .calibrating = core.state {
                core.collapse { done($0) }
                return
            }
            done?(nil)
        case .dropped(let drop):
            if drop == .timerSuppressed { armAuto() }
            done?(nil)
        }
    }

    /// §4.0 on 27: a collapse a person asks for (not the CLI, which can't answer) that would hide every other app.
    private func asksFirst(_ command: IconsCommand, from source: IconsIntentSource, core: IconsEngineCore) -> Bool {
        guard source.isUser, source != .cli, source != .hover, !firstCollapseAsking else { return false }
        switch command {
        case .hide: break
        case .toggle, .toggleAll: if queue.target.isCollapsed { return false }
        case .show, .showAll: return false
        }
        let appsValue = apps.value
        return IconsPageRules.asksBeforeFirstCollapse(engine: core.engine, arranged: config.value.arranged,
                                                      asked: firstCollapseAsked, layout: core.layout,
                                                      ownBundleID: Bundle.main.bundleIdentifier ?? "",
                                                      choices: appsValue.choices,
                                                      newShown: Set(appsValue.newShown.keys))
    }

    private func askBeforeFirstCollapse(_ intent: IconsIntent, from source: IconsIntentSource,
                                        done: ((IconsCollapseResult?) -> Void)?) {
        firstCollapseAsking = true
        let alert = NSAlert()
        alert.messageText = IconsPageRules.firstCollapseTitle
        alert.informativeText = IconsPageRules.firstCollapseMessage
        let hide = alert.addButton(withTitle: L("Hide Icons"))
        let cancel = alert.addButton(withTitle: L("Cancel"))
        hide.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        SettingsAlert.present(alert) { [weak self] response in
            guard let self else {
                done?(nil)
                return
            }
            self.firstCollapseAsking = false
            self.firstCollapseAsked = true
            guard response == .alertFirstButtonReturn, self.core != nil else {
                done?(nil)
                return
            }
            self.submit(intent, from: source, done: done)
        }
    }

    private func run(_ step: IconsStep, seq: UInt64, source: IconsIntentSource, core: IconsEngineCore,
                     done: ((IconsCollapseResult?) -> Void)? = nil) {
        switch step {
        case .collapse:
            collapseSource = source
            autoTimer?.cancel()
            autoTimer = nil
            core.collapse { [weak self, weak core] result in
                // Runs after `collapsed` below, so the refusal and the status row are current for the CLI.
                defer { done?(result) }
                guard let self, let core, self.core === core else { return }
                self.collapseSource = nil
                self.collapsed(result, source: source)
                self.queue.settled(seq: seq, state: core.state)
                self.refreshPresentation()
            }
            return
        case .expand(let mode):
            core.expand(mode)
            queue.settled(seq: seq, state: core.state)
            refreshPresentation()
            armAuto()
        case .stop:
            core.stop()
            queue.settled(seq: seq, state: core.state)
        case .failSafe(let reason):
            core.failSafe(reason)
            queue.settled(seq: seq, state: core.state)
            refreshPresentation()
        }
        done?(nil)
    }

    private func collapsed(_ result: IconsCollapseResult, source: IconsIntentSource) {
        switch result {
        case .collapsed:
            lastRefusal = nil
            lastFailSafe = nil
            lastFailSafeAt = nil
            auto.disarm()
            if source.isUser, !config.value.arranged {
                // §4.0: the first collapse a person asks for.
                var c = config.value
                c.arranged = true
                config.value = c
            }
        case .refused(let refusal):
            lastRefusal = refusal
            EventLog.shared.record(.icons, "Icons: collapse refused, \(refusal.rawValue)")
            if refusal == .needsPermission, source == .click { context?.openSettings(SettingsRootID.hiddenIcons) }
            if refusal == .capture { capture.gateFoundInUse() }
            armAuto()
        case .failed:
            armAuto()
        case .unavailable, .superseded:
            break
        }
    }

    private func clicked(_ action: IconsClickAction) {
        guard let core else {
            context?.openSettings(SettingsRootID.hiddenIcons)
            return
        }
        if core.engine == .native, access.state.arrowOpensSettings, !core.state.isCollapsed {
            context?.openSettings(SettingsRootID.hiddenIcons)
            return
        }
        switch action {
        case .toggle: submit(.command(.toggle), from: .click)
        case .toggleAll: submit(.command(.toggleAll), from: .click)
        case .menu: break
        }
    }

    private func visibilityLost(_ role: IconsItemRole) {
        guard let core else { return }
        if role == .toggle, core.state.isCollapsed {
            submit(.failSafe(.arrowHidden), from: .monitor)
        } else {
            refreshPresentation()
        }
    }

    // MARK: Auto-collapse (§4.6)

    private func armAuto() {
        autoTimer?.cancel()
        autoTimer = nil
        guard core != nil, IconsAutoCollapse.enabled(config.value), !queue.target.isCollapsed else {
            auto.disarm()
            return
        }
        let deadline = auto.arm(now: Self.uptime)
        scheduleAuto(at: deadline)
    }

    private func scheduleAuto(at deadline: Double) {
        autoTimer?.cancel()
        autoTimer = scheduler.after(max(deadline - Self.uptime, 0)) { [weak self] in self?.autoFired() }
    }

    private func autoFired() {
        autoTimer = nil
        guard let core else { return }
        let pids = Set((core.layout?.extras ?? []).map(\.extra.pid))
        monitors.rearmFacts(snapticWindowVisible: IconsMonitors.snapticWindowVisible(), ownMenuOpen: ownMenuOpen,
                            lastHiddenListPress: lastHiddenListPress, extraPIDs: pids) { [weak self] facts in
            guard let self, self.core === core else { return }
            switch self.auto.fire(now: Self.uptime, facts: facts) {
            case .idle: break
            case .wait(let until), .rearm(_, let until): self.scheduleAuto(at: until)
            case .collapse: self.submit(.command(.hide), from: .timer)
            }
        }
    }

    // MARK: Launch collapse (§4.6)

    private func decideLaunch() {
        guard !Self.launchDecided, core != nil else { return }
        let marks = Self.readLaunchMarks(defaults, osBuild: osBuild)
        let value = config.value
        var facts = IconsLaunchFacts(collapseAtLaunch: value.collapseAtLaunch, arranged: value.arranged,
                                     gate: gate.status)
        facts.versionChanged = marks.versionChanged
        facts.osBuildChanged = marks.osBuildChanged
        facts.unstableLaunch = crashTripped
        facts.userActed = queue.userActed
        switch IconsLaunchCollapse.decide(facts) {
        case .wait:
            launchWaiting = true
        case .collapse:
            Self.launchDecided = true
            launchWaiting = false
            submit(.command(.hide), from: .launch)
        case .skip(let reason):
            Self.launchDecided = true
            launchWaiting = false
            if reason != .off { EventLog.shared.record(.icons, "Icons: launch collapse skipped, \(reason.rawValue)") }
        }
    }

    /// Compares this start with the last one's marker, once per process, then writes the new marker.
    private static func readLaunchMarks(_ defaults: UserDefaults, osBuild: String) -> (versionChanged: Bool,
                                                                                        osBuildChanged: Bool) {
        if let launchMarks { return launchMarks }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let seen = defaults.string(forKey: launchSeenKey)?.split(separator: "|", omittingEmptySubsequences: false)
        let marks: (versionChanged: Bool, osBuildChanged: Bool)
        if let seen, seen.count == 2 {
            marks = (String(seen[0]) != version, String(seen[1]) != osBuild)
        } else {
            marks = (true, true)
        }
        defaults.set(version + "|" + osBuild, forKey: launchSeenKey)
        launchMarks = marks
        return marks
    }

    // MARK: The 1 s tick

    private func scheduleTick() {
        tick?.cancel()
        tick = scheduler.after(Self.tickInterval) { [weak self] in
            guard let self, self.core != nil else { return }
            self.ticked()
            self.scheduleTick()
        }
    }

    private func ticked() {
        guard let core else { return }
        // H3: a kill switch turned on while running.
        let switches = PrivateMenuBarAPI.killSwitches(defaults)
        let added = switches.subtracting(killSwitches)
        let changed = switches != killSwitches
        killSwitches = switches
        let relevant: Set<IconsFeature> = core.engine == .native ? [.native, .inventory] : [.length]
        if !added.isDisjoint(with: relevant) {
            EventLog.shared.record(.icons, "Icons: kill switch turned on")
            core.killSwitchTurnedOn()
            unavailableReason = .killSwitch
            refreshPresentation()
            return
        }
        if changed { refreshPresentation() }
        watchPrivacyPane()
        let before = access.state
        access.trust(AXIsProcessTrusted(), at: Self.uptime)
        if access.state != before { requestRefresh() }
        if core.engine == .length { checkOwnItems(core) }
        driveGate(core)
    }

    private func watchPrivacyPane() {
        guard privacyPane != .closed else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
        switch (privacyPane, front) {
        case (.opened, true): privacyPane = .front
        case (.front, false):
            privacyPane = .closed
            permissionPaneClosed()
        default: break
        }
    }

    /// Length's own-items guard (§4.2.5): window frames only, re-checked every second.
    private func checkOwnItems(_ core: IconsEngineCore) {
        let own = ownItems()
        let ids = Set(own.map(\.id))
        let appeared = knownOwnIDs.map { !ids.subtracting($0).isEmpty } ?? false
        knownOwnIDs = ids
        let placement = IconsGuards.ownItemsPlacement(toggle: items.frame(of: .toggle),
                                                      separator: items.frame(of: .separator), items: own,
                                                      rightToLeft: items.rightToLeft)
        let decision = IconsOwnItemsGuard.decide(placement, awakeHolding: awakeHolding(),
                                                 collapsed: core.state.isCollapsed, appeared: appeared)
        if decision != ownItemsDecision {
            ownItemsDecision = decision
            requestRefresh()
        }
        if decision.expand { submit(.command(.show), from: .monitor) }
    }

    /// The stable-inventory gate for launch collapse (§4.6): a read every 2 s until it passes or 30 s run out.
    private func driveGate(_ core: IconsEngineCore) {
        guard launchWaiting else { return }
        let now = Self.uptime
        if gate.status == .pending, now - lastGateRead >= IconsStableGate.spacing {
            lastGateRead = now
            if core.engine == .length, inventory == nil || !AXIsProcessTrusted() {
                // Without Accessibility, Length has nothing to read: the bar is as stable as it can be known.
                _ = gate.read([:], at: now, uptime: now)
            } else if !core.isRestricted, !core.state.isCollapsed {
                core.refreshLayout()
            }
        }
        _ = gate.expire(at: now)
        decideLaunch()
    }

    // MARK: Monitors

    private func newAppReread() {
        guard let core else { return }
        if core.engine == .native, core.isRestricted {
            guard let held = core.heldBundles, let inventory else { return }
            let skip = skipRules()
            inventory.read(scope: .restricted(allowed: Set(held))) { [weak self] read in
                guard let self, self.core === core, !read.failed else { return }
                let sighting = IconsSighting(inventory: read, skip: skip)
                let update = IconsNewIcons.restrictedRead(sighting, now: Self.wall, policy: self.config.value.newApps,
                                                          state: self.apps.value)
                self.storeApps(update)
            }
        } else {
            core.refreshLayout()
        }
    }

    private func recover(_ event: IconsRecoveryEvent) {
        guard core != nil else { return }
        let plan = IconsRecovery.plan(event, intentHidden: queue.intentHidden)
        if let reason = plan.failSafe { submit(.failSafe(reason), from: .monitor) }
        if let delay = plan.recollapseAfter {
            recollapse?.cancel()
            recollapse = scheduler.after(delay) { [weak self] in
                guard let self else { return }
                self.recollapse = nil
                if self.queue.intentHidden { self.submit(.command(.hide), from: .monitor) }
            }
        }
    }

    private func examChanged(_ active: Bool) {
        if active, let core, core.state.isCollapsed || core.isRestricted {
            submit(.failSafe(.exam), from: .monitor)
        }
        requestRefresh()
    }

    /// R3-90: show while capture runs (if the setting says so), and hide again once it ended.
    private func captureChanged(_ inUse: Bool) {
        guard let core else { return }
        captureResume?.cancel()
        captureResume = nil
        let action = IconsCaptureGuard.action(inUse: inUse, keepVisible: config.value.showDuringCapture,
                                              engine: core.engine, hiding: core.state.isCollapsed || core.isRestricted,
                                              intentHidden: queue.intentHidden)
        switch action {
        case .show:
            submit(.failSafe(.capture), from: .monitor)
        case .resume:
            captureResume = scheduler.after(IconsCaptureGuard.resumeDelay) { [weak self] in
                guard let self else { return }
                self.captureResume = nil
                if self.queue.intentHidden { self.submit(.command(.hide), from: .monitor) }
            }
        case .none:
            break
        }
        requestRefresh()
    }

    /// The Advanced toggle changed: turned on while hidden with capture running shows the icons; turned off while a
    /// hide waits for capture hides them now.
    private func captureSettingChanged() {
        let keep = config.value.showDuringCapture
        guard keep != keepCaptureVisible else { return }
        keepCaptureVisible = keep
        guard let core, core.engine == .native else { return }
        let hiding = core.state.isCollapsed || core.isRestricted
        if keep {
            if hiding, capture.inUseNow() { submit(.failSafe(.capture), from: .monitor) }
        } else {
            captureResume?.cancel()
            captureResume = nil
            if !hiding, queue.intentHidden, capture.reported || lastRefusal == .capture {
                submit(.command(.hide), from: .monitor)
            }
        }
    }

    private func hiderChanged(_ hider: KnownMenuBarHider?) {
        if hider != nil, let core, core.state.isCollapsed {
            submit(.command(.show), from: .monitor)
        }
        requestRefresh()
    }

    // MARK: Settings

    private func subscribe() {
        sinks.removeAll()
        config.$value.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.configChanged() }
        }.store(in: &sinks)
        apps.$value.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.inputsChanged() }
        }.store(in: &sinks)
    }

    private func configChanged() {
        guard context != nil else { return }
        let value = config.value
        items.setAlwaysHidden(value.alwaysHidden)
        hiders.policy = value.otherHiders
        auto.setSeconds(value.autoCollapseSeconds, now: Self.uptime)
        if IconsAutoCollapse.enabled(value) {
            if autoTimer == nil { armAuto() }
        } else {
            autoTimer?.cancel()
            autoTimer = nil
            auto.disarm()
        }
        cli.shortcutChanged()
        captureSettingChanged()
        inputsChanged()
        refreshPresentation()
        requestRefresh()
    }

    private func inputsChanged() {
        core?.update(engineInputs())
    }

    private func engineInputs() -> IconsEngineInputs {
        let value = config.value
        let appsValue = apps.value
        return IconsEngineInputs(ownBundleID: Bundle.main.bundleIdentifier ?? "", alwaysHidden: value.alwaysHidden,
                                 dividers: value.dividers, newShown: Set(appsValue.newShown.keys),
                                 choices: appsValue.choices, rightToLeft: items.rightToLeft)
    }

    private func storeApps(_ update: IconsNewIconsUpdate) {
        if update.state != apps.value { apps.value = update.state }
        if update.newShownChanged { inputsChanged() }
    }

    // MARK: Presentation

    private func refreshPresentation() {
        guard let core else {
            items.update(collapsed: false, hiddenCount: nil)
            return
        }
        let engineState = core.state
        let collapsed = engineState.isCollapsed
        items.update(collapsed: collapsed, hiddenCount: hiddenCount)
        ActivationPolicyController.shared.iconsShown(!collapsed, cause: IconsExpandCause(queue.expandSource),
                                                     fullBarOnExpand: config.value.fullBarOnExpand)
        monitors.setHover(IconsHoverDwell.active(hover: config.value.hover, collapsed: collapsed,
                                                 killSwitches: killSwitches))
        monitors.setWatchesLaunches(IconsNewIcons.watchesLaunches(engine: core.engine,
                                                                 assertionActive: core.isRestricted,
                                                                 collapsed: collapsed))
        monitors.setExamPolling(IconsExamGuard.polls(engine: core.engine, assertionActive: core.isRestricted))
        capture.setPolling(IconsCaptureGuard.polls(engine: core.engine, assertionActive: core.isRestricted,
                                                   intentHidden: queue.intentHidden))
        if case .unavailable(let reason) = engineState, reason != .stopped { unavailableReason = reason }
        if lastPresented != engineState {
            lastPresented = engineState
            requestRefresh()
        }
    }

    private func requestRefresh() {
        context?.requestMenuRebuild()
        context?.requestSettingsRefresh()
    }

    private func showFailSafeToast(_ reason: IconsFailSafeReason) {
        guard !Self.failSafeToastShown, ![.session, .agentRestart, .capture].contains(reason), let context else {
            return
        }
        Self.failSafeToastShown = true
        context.toasts.show(L("Snaptic couldn’t hide icons, so they’re shown. Details are in Hidden Icons settings."),
                            action: ToastAction(title: L("Open Settings")) { [weak context] in
                                context?.openSettings(SettingsRootID.hiddenIcons)
                            }, lifetime: context.lifetime)
    }

    // MARK: Diagnostics (H12)

    /// "Label: value" lines for General › Diagnostics. No bundle ids.
    func diagnosticsLines() -> [String] {
        var lines: [String] = []
        let engine = engineKind.map { $0 == .native ? "Native" : "Length" } ?? "unavailable"
        lines.append("Engine: " + engine)
        if let unavailableReason { lines.append("Unavailable: " + unavailableReason.rawValue) }
        lines.append("State: " + Self.stateName(engineState))
        for (label, value) in PrivateMenuBarAPI.diagnosticsRows() { lines.append(label + ": " + value) }
        let switches = killSwitches.map(\.rawValue).sorted()
        lines.append("Kill switches: " + (switches.isEmpty ? "none" : switches.joined(separator: ", ")))
        if let disabled = defaults.string(forKey: Self.disabledBuildKey) {
            lines.append("Native disabled on build: " + disabled)
        }
        if let layout = core?.layout, layout.readAt > 0 {
            lines.append("Layout age: \(Int(max(Self.wall - layout.readAt, 0))) s")
            let counts = IconsSection.allCases.map { section in
                "\(section.rawValue) \(layout.sections.values.filter { $0 == section }.count)"
            }
            lines.append("Sections: " + counts.joined(separator: ", "))
        } else {
            lines.append("Layout age: none")
        }
        if let lastFailSafe, let at = lastFailSafeAt {
            lines.append("Last fail-safe: " + lastFailSafe.rawValue + " at " + ISO8601DateFormatter().string(from: at))
        } else {
            lines.append("Last fail-safe: none")
        }
        if let lastRefusal { lines.append("Last refusal: " + lastRefusal.rawValue) }
        lines.append("Accessibility: " + access.state.rawValue)
        if engineKind == .native {
            let keep = config.value.showDuringCapture ? "shows icons" : "stays hidden"
            lines.append("Camera or microphone: " + (capture.inUseNow() ? "in use" : "not in use") + " (" + keep + ")")
        }
        return lines
    }

    static func stateName(_ state: IconsEngineState) -> String {
        switch state {
        case .expanded(let mode): return "expanded (" + mode.rawValue + ")"
        case .calibrating: return "calibrating"
        case .collapsed: return "collapsed"
        case .unavailable(let reason): return "unavailable (" + reason.rawValue + ")"
        }
    }
}

// MARK: - The engine's host

extension IconsModule: @preconcurrency IconsEngineHost {
    func collapseRefusal(engine: IconsEngineKind) -> IconsRefusal? {
        var facts = IconsCollapseFacts(engine: engine)
        facts.exam = monitors.examActive()
        if engine == .native, config.value.showDuringCapture { facts.capture = capture.inUseNow() }
        facts.pausedFor = hiders.pausedFor
        facts.access = access.state
        if collapseSource == .launch { facts.gate = gate.status }
        if engine == .length { facts.ownItems = ownItemsDecision }
        facts.identityOK = identityOK
        return IconsCollapseGates.refusal(facts)
    }

    func killSwitchOn(engine: IconsEngineKind) -> Bool {
        let switches = PrivateMenuBarAPI.killSwitches(defaults)
        switch engine {
        case .native: return switches.contains(.native) || switches.contains(.inventory)
        case .length: return switches.contains(.length)
        }
    }

    func screens() -> [IconsScreen] { LengthBackend.screens() }

    func skipRules() -> IconsSkipRules {
        IconsSkipRules(ownPID: getpid(), ownBundlePath: Bundle.main.bundleURL.path)
    }

    func setActivationInFlight(_ inFlight: Bool) {
        if inFlight {
            defaults.set(osBuild, forKey: Self.inFlightKey)
        } else {
            defaults.removeObject(forKey: Self.inFlightKey)
        }
    }

    func disableNativeOnThisBuild() {
        defaults.set(osBuild, forKey: Self.disabledBuildKey)
    }

    func expectsSystemItemChanges() -> Bool {
        capture.expectsSystemItemChanges()
    }

    func count(_ counter: IconsCounter) {
        EventLog.shared.count(counter.name)
        if case .failSafe(let reason) = counter { failedSafe(reason) }
        switch counter {
        case .activateTimeout: failedSafe(.activateTimeout)
        case .systemItemHidden: failedSafe(.systemItemHidden)
        case .agentRestart: failedSafe(.agentRestart)
        default: break
        }
    }

    private func failedSafe(_ reason: IconsFailSafeReason) {
        lastFailSafe = reason
        lastFailSafeAt = Date()
        showFailSafeToast(reason)
    }

    func engineStateChanged(_ state: IconsEngineState) {
        queue.engineChanged(state)
        refreshPresentation()
    }

    func layoutRead(_ layout: IconsLayout) {
        guard let core else { return }
        let now = Self.wall
        switch layout.scope {
        case .unrestricted:
            var update = IconsNewIcons.unrestrictedRead(IconsSighting(layout: layout), now: now, state: apps.value)
            update.state.layout = layout.cache
            if core.engine == .length, core.state.isCollapsed {
                for bundle in update.new where IconsNewIcons.toastDue(bundle, now: now, inventoryExists: true,
                                                                       state: update.state) {
                    update.state = IconsNewIcons.toasted(bundle, now: now, state: update.state)
                    showNewIconToast()
                }
            }
            storeApps(update)
        case .restricted:
            let sighting = IconsSighting(placed: [:], present: IconsSighting(layout: layout).present)
            storeApps(IconsNewIcons.restrictedRead(sighting, now: now, policy: config.value.newApps,
                                                   state: apps.value))
        }
        let uptime = Self.uptime
        _ = gate.read(layout.sections, at: uptime, uptime: uptime)
        let thirdParty = layout.sections.keys.filter { !layout.systemBundles.contains($0) }.count
        if access.read(.thirdParty(thirdParty), collapsed: core.state.isCollapsed) {
            submit(.command(.show), from: .monitor)
        }
        if launchWaiting { decideLaunch() }
        refreshPresentation()
    }

    /// Length's new-icon toast (§4.5): once per app per day; the text never names the app.
    private func showNewIconToast() {
        guard let context else { return }
        context.toasts.show(L("A new icon may be hidden. ⌘-drag it to the right of the arrow to keep it shown."),
                            action: ToastAction(title: L("Show Icons")) { [weak self] in
                                self?.perform(.show, from: .menu)
                            }, lifetime: context.lifetime)
    }
}
