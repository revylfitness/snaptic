import AppKit
import Combine
import SnapticKit

/// Owns the modules, their config stores and the host services they share (PLAN §3.3).
/// - one ConfigStore per key for the app's lifetime (`SnapticModulesV1`,
///   `SnapticDisplaysV1`; the switcher keeps `SnapticConfig.v1` through AppSettings);
/// - starts and stops modules per ModulesConfig, collapsing toggle storms (300 ms);
/// - one permission request per launch, through PermissionFlow;
/// - stops modules in reverse start order and flushes every store on quit.
@MainActor final class ModuleHost: ObservableObject {
    static let modulesKey = "SnapticModulesV1"
    static let displaysKey = "SnapticDisplaysV1"
    static let didLaunchBeforeKey = "SnapticDidLaunchBefore"
    /// Collapses quick on/off/on toggles into one transition.
    static let applyDelay: TimeInterval = 0.3

    let safeMode: SafeModeState
    let modulesStore: ConfigStore<ModulesConfig>
    let displaysStore: ConfigStore<DisplaysConfig>
    let switcherSettings = AppSettings.shared

    let hotkeys = GlobalHotkeys()
    let commands = ControlCommandRegistry()
    let otherApps = OtherAppsMonitor()
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let spawner: HelperSpawner
    let relauncher: Relauncher

    let switcher: WindowSwitcherModule
    let displays: DisplaysModule

    /// This is the first launch ever (no earlier Snaptic ran for this user).
    let isFirstLaunch: Bool

    /// Bumped whenever modules start or stop or their pages change (Settings refresh).
    @Published private(set) var revision = 0

    private let lifetime = Lifetime()
    private var running: [ModuleID: Lifetime] = [:]
    private var applyWork: DispatchWorkItem?
    private var applying = false
    private var launchPermissionsRequested = false
    private var sinks: [AnyCancellable] = []
    private var isShutDown = false

    private(set) lazy var statusMenu = StatusMenu(host: self)
    private(set) lazy var settingsWindow = SettingsWindowHost(host: self)
    private(set) lazy var onboarding = Onboarding(host: self)
    private(set) lazy var controlServer = ControlServer(registry: commands)

    init(safeMode: SafeModeState, toasts: ToastPresenter, permissions: PermissionFlow, spawner: HelperSpawner,
         relauncher: Relauncher) {
        self.safeMode = safeMode
        self.toasts = toasts
        self.permissions = permissions
        self.spawner = spawner
        self.relauncher = relauncher

        // Upgrade rule (PLAN §3.4), decided before the store fills in defaults.
        let modulesExisted = ConfigStore<ModulesConfig>.persistentData(forKey: Self.modulesKey) != nil
        let domain = UserDefaults.standard.persistentDomain(forName: ConfigStore<ModulesConfig>.persistentDomainName)
        let launchedBefore = (domain?[Self.didLaunchBeforeKey] as? Bool) == true
        isFirstLaunch = !launchedBefore

        let store = ConfigStore<ModulesConfig>(key: Self.modulesKey)
        if !modulesExisted {
            // A fresh value equals init(), so nothing would be pending: force the write, or
            // a new user who quits at Welcome counts as an upgrader next launch (W1).
            store.value = ModulesConfig.firstRun(launchedBefore: launchedBefore)
            store.save(force: true)
        }
        modulesStore = store
        UserDefaults.standard.set(true, forKey: Self.didLaunchBeforeKey)

        let displaysConfig = ConfigStore<DisplaysConfig>(key: Self.displaysKey)
        displaysStore = displaysConfig
        switcher = WindowSwitcherModule()
        displays = DisplaysModule(config: displaysConfig)
    }

    // MARK: Lifecycle

    /// Startup step 11–12: modules per settings, then the status items.
    func bootstrap() {
        permissions.relauncher = relauncher
        permissions.launchedBefore = !isFirstLaunch
        // Onboarding asks for permissions itself, afterwards (PLAN §3.7).
        permissions.holdAutomaticGuides = modulesStore.value.needsOnboarding
        setUpOtherApps()
        setUpControl()
        watchOutsideChanges()
        toasts.onRecentChange = { [weak self] in self?.statusMenu.requestRebuild() }
        modulesStore.$value
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleApply() } }
            .store(in: &sinks)
        // "Scroll on a slider to adjust" lives in the Displays menu settings (MenuConfig).
        MenuSliderItem.scrollToAdjust = displaysStore.value.menu.scrollAdjustsSliders
        displaysStore.$value
            .map(\.menu.scrollAdjustsSliders)
            .removeDuplicates()
            .sink { on in MainActor.assumeIsolated { MenuSliderItem.scrollToAdjust = on } }
            .store(in: &sinks)
        applyNow()
        statusMenu.install()
        _ = settingsWindow   // listens for "open this Settings page" from Displays UI
        if modulesStore.value.needsOnboarding {
            onboarding.showIfNeeded()
        } else {
            requestLaunchPermissions()
        }
    }

    /// Quit path: stops modules in reverse order and flushes every store.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        applyWork?.cancel()
        applyWork = nil
        sinks.removeAll()
        controlServer.stop()
        otherApps.stop()
        for id in ModuleID.allCases.reversed() where running[id] != nil { stopModule(id) }
        modulesStore.flush()
        displaysStore.flush()
        switcherSettings.flush()
        lifetime.end()
        statusMenu.remove()
    }

    /// Modules in start order.
    var modules: [any SnapticModule] { ModuleID.allCases.map { module($0) } }

    func module(_ id: ModuleID) -> any SnapticModule {
        switch id {
        case .windowSwitcher: return switcher
        case .displays: return displays
        }
    }

    var runningModules: Set<ModuleID> { Set(running.keys) }

    func isRunning(_ id: ModuleID) -> Bool { running[id] != nil }

    func setEnabled(_ enabled: Bool, _ id: ModuleID) {
        modulesStore.value.setEnabled(enabled, for: id)
    }

    func openSettings(page: String? = nil) {
        settingsWindow.show(page: page)
    }

    // MARK: Applying

    private func scheduleApply() {
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyNow() }
        }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay, execute: work)
    }

    private func applyNow() {
        guard !isShutDown else { return }
        guard !applying else {
            scheduleApply()   // a module changed settings while starting: apply again after
            return
        }
        applying = true
        defer { applying = false }
        applyWork = nil
        let config = modulesStore.value
        otherApps.policy = config.otherApps
        if config.commandLine.enabled { controlServer.start() } else { controlServer.stop() }
        let transitions = ModuleTransitions.plan(order: ModuleID.allCases, running: runningModules,
                                                 desired: Set(config.enabledModules))
        for id in transitions.stop { stopModule(id) }
        for id in transitions.start { startModule(id) }
        if !transitions.start.isEmpty && launchPermissionsRequested { requestPermissions(for: transitions.start) }
        statusMenu.applyPlan()
        revision &+= 1
    }

    private func startModule(_ id: ModuleID) {
        guard running[id] == nil else { return }
        let life = lifetime.child()
        running[id] = life
        let context = ModuleContext(
            safeMode: safeMode, hotkeys: hotkeys, commands: commands, toasts: toasts, permissions: permissions,
            spawner: spawner, relauncher: relauncher, otherApps: otherApps, lifetime: life,
            requestMenuRebuild: { [weak self] in self?.statusMenu.requestRebuild() },
            requestSettingsRefresh: { [weak self] in self?.revision &+= 1 },
            openSettings: { [weak self] page in self?.openSettings(page: page) })
        module(id).start(context)
        EventLog.shared.record(.modules, "Module \(id.rawValue) started")
    }

    private func stopModule(_ id: ModuleID) {
        guard let life = running[id] else { return }
        module(id).stop()
        life.end()
        running[id] = nil
        EventLog.shared.record(.modules, "Module \(id.rawValue) stopped")
    }

    // MARK: Other display apps (PLAN §3.8)

    private func setUpOtherApps() {
        otherApps.policy = modulesStore.value.otherApps
        otherApps.onAppsAppeared = { [weak self] apps in
            guard let self, self.isRunning(.displays), self.modulesStore.value.otherApps == .pauseOverlapping,
                  let first = apps.first else { return }
            self.toasts.show(first.name + L(" is running, so Snaptic paused the Displays features it also controls."),
                             action: ToastAction(title: L("Run Both")) { [weak self] in
                                 self?.modulesStore.value.otherApps = .runBoth
                             }, lifetime: self.lifetime)
        }
        otherApps.onRunningChange = { [weak self] in
            self?.revision &+= 1
            self?.statusMenu.requestRebuild()
        }
        otherApps.start()
    }

    // MARK: Command line (PLAN §11)

    private func setUpControl() {
        controlServer.skipConfirmationAllowed = { [weak self] in
            self?.modulesStore.value.commandLine.maySkipConfirmation ?? false
        }
        controlServer.onStatusChange = { [weak self] in self?.revision &+= 1 }
        commands.onChange = { [weak self] in self?.revision &+= 1 }
        registerHostCommands()
    }

    private func registerHostCommands() {
        commands.register("version", policy: .read, offOnly: false, cliAllowed: true,
                          summary: L("Show Snaptic's version"), lifetime: lifetime) { _ in
            let info = Bundle.main.infoDictionary
            let version = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
            return .ok("Snaptic " + version)
        }
        commands.register("modules", policy: .read, offOnly: false, cliAllowed: true,
                          summary: L("List the modules and whether they run"), lifetime: lifetime) { [weak self] request in
            guard let self else { return .failure(ControlExit.unavailable, "") }
            let rows: [(String, String)] = self.modules.map { module in
                let state: String
                switch module.state {
                case .running: state = "running"
                case .stopped: state = "off"
                case .degraded: state = "degraded"
                }
                return (module.id.rawValue, state)
            }
            if request.json {
                let object = Dictionary(uniqueKeysWithValues: rows)
                let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
                return .ok(String(decoding: data, as: UTF8.self))
            }
            return .ok(rows.map { $0.0 + "\t" + $0.1 }.joined(separator: "\n"))
        }
        commands.register("module disable", policy: .low, offOnly: true, cliAllowed: true,
                          summary: L("Turn a module off: module disable <windowSwitcher|displays>"),
                          lifetime: lifetime) { [weak self] request in
            guard let self else { return .failure(ControlExit.unavailable, "") }
            guard let name = request.arguments.first?.lowercased(),
                  let id = ModuleID.allCases.first(where: { $0.rawValue.lowercased() == name || (name == "switcher" && $0 == .windowSwitcher) })
            else { return .failure(ControlExit.notFound, L("No such module.")) }
            self.setEnabled(false, id)
            return .ok()
        }
        commands.register("open-settings", policy: .low, offOnly: false, cliAllowed: true,
                          summary: L("Open Snaptic's Settings, optionally at a page"), lifetime: lifetime) { [weak self] request in
            let page = request.arguments.first.flatMap(SettingsWindowHost.validPageID)
            self?.openSettings(page: page)
            return .ok()
        }
        commands.register("safe-mode", policy: .read, offOnly: false, cliAllowed: true,
                          summary: L("Show whether Snaptic runs in Safe Mode"), lifetime: lifetime) { [weak self] _ in
            .ok(self?.safeMode.isActive == true ? "on" : "off")
        }
        commands.register("list", policy: .read, offOnly: false, cliAllowed: true,
                          summary: L("List the displays (number, key, name, size, state)"),
                          lifetime: lifetime) { [weak self] request in
            self?.listDisplays(json: request.json) ?? .failure(ControlExit.unavailable, "")
        }
        commands.register("features", policy: .read, offOnly: false, cliAllowed: true,
                          summary: L("List the Displays features and whether they are on"), lifetime: lifetime) { [weak self] request in
            self?.listFeatures(json: request.json) ?? .failure(ControlExit.unavailable, "")
        }
        commands.register("feature disable", policy: .low, offOnly: true, cliAllowed: true,
                          summary: L("Turn a Displays feature off: feature disable <feature>"),
                          lifetime: lifetime) { [weak self] request in
            self?.disableFeature(request.arguments) ?? .failure(ControlExit.unavailable, "")
        }
    }

    /// `snaptic list`: numbers, names, keys and states only (no serials, EDID or window
    /// data). The number is the one bare CLI selectors and Identify use: the order of
    /// `DisplaySelectorResolver.ordered` (menu order, hidden displays included).
    private func listDisplays(json: Bool) -> ControlResponse {
        guard isRunning(.displays), let ctx = displays.pageEnvironment.context else {
            return .failure(ControlExit.unavailable, L("The Displays module is off."))
        }
        let list = DisplaySelectorResolver.ordered(ctx)
        let hidden = Set(ctx.config.value.menu.hiddenDisplays)
        if json {
            let rows: [[String: Any]] = list.enumerated().map { index, d in
                ["number": index + 1, "key": d.key.rawValue, "name": d.name, "main": d.isMain, "builtin": d.isBuiltin,
                 "online": d.isOnline, "active": d.isActive, "hiddenInMenu": hidden.contains(d.key),
                 "width": Int(d.bounds.width), "height": Int(d.bounds.height)]
            }
            let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])) ?? Data("[]".utf8)
            return .ok(String(decoding: data, as: UTF8.self))
        }
        guard !list.isEmpty else { return .ok(L("No displays.")) }
        return .ok(list.enumerated().map { index, d -> String in
            var flags: [String] = []
            if d.isMain { flags.append("main") }
            if d.isBuiltin { flags.append("built-in") }
            if !d.isActive { flags.append("off") }
            if d.mirrorOf != nil { flags.append("mirroring") }
            if hidden.contains(d.key) { flags.append("hidden") }
            let size = String(Int(d.bounds.width)) + "x" + String(Int(d.bounds.height))
            return [String(index + 1), d.key.rawValue, d.name, size, flags.joined(separator: ",")].joined(separator: "\t")
        }.joined(separator: "\n"))
    }

    /// `snaptic features`: the saved choice, whether it is in effect, and why not.
    private func listFeatures(json: Bool) -> ControlResponse {
        let raw = displaysStore.value.rawFeatures
        let runtime = displays.runtime
        let running = isRunning(.displays)
        let rows = DisplayFeature.allCases.map { feature -> (name: String, on: Bool, effective: Bool, note: String) in
            let note: String
            if case .unavailable(let reason)? = runtime.availability[feature] { note = reason }
            else if let reason = otherApps.pauseReason(for: feature) { note = reason }
            else { note = "" }
            return (feature.rawValue, FeatureGraph.rawState(feature, in: raw),
                    running && runtime.isEffective(feature), note)
        }
        if json {
            let objects: [[String: Any]] = rows.map { ["feature": $0.name, "on": $0.on, "effective": $0.effective, "note": $0.note] }
            let data = (try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])) ?? Data("[]".utf8)
            return .ok(String(decoding: data, as: UTF8.self))
        }
        return .ok(rows.map { row in
            let state = row.effective ? "active" : (row.on ? "on" : "off")
            return [row.name, state, row.note].filter { !$0.isEmpty }.joined(separator: "\t")
        }.joined(separator: "\n"))
    }

    /// `snaptic feature disable <feature>`: off only; protected features were refused by
    /// the registry before this runs.
    private func disableFeature(_ arguments: [String]) -> ControlResponse {
        guard arguments.count == 1, let feature = KitControl.feature(named: arguments[0]) else {
            return .failure(ControlExit.notFound, L("No such feature. Run “snaptic features” for the list."))
        }
        guard !FeatureGraph.alwaysOn.contains(feature) else {
            return .failure(ControlExit.refused, L("This feature is always on."))
        }
        displaysStore.value.features[feature] = false
        return .ok()
    }

    // MARK: Outside changes (PLAN §3.4)

    /// Hooks, actions and CLI settings changed by another process: say so (informational).
    private func watchOutsideChanges() {
        displaysStore.onExternalChange = { [weak self] old, new in
            guard let self else { return }
            if old.automation != new.automation {
                self.toasts.show(L("Hooks or custom actions were changed outside Snaptic."), lifetime: self.lifetime)
            }
        }
        modulesStore.onExternalChange = { [weak self] old, new in
            guard let self else { return }
            if old.commandLine != new.commandLine {
                self.toasts.show(L("Command-line settings were changed outside Snaptic."), lifetime: self.lifetime)
            }
        }
    }

    // MARK: Permissions

    /// One request per launch for what the running modules need (also when onboarding
    /// finishes).
    func requestLaunchPermissions() {
        guard !launchPermissionsRequested else { return }
        launchPermissionsRequested = true
        requestPermissions(for: Array(runningModules))
    }

    private func requestPermissions(for ids: [ModuleID]) {
        var reasons: [Permission: [String]] = [:]
        for id in ModuleID.allCases where ids.contains(id) {
            let m = self.module(id)
            for permission in m.requiredPermissions { reasons[permission, default: []].append(m.title) }
        }
        for permission in Permission.allCases {
            guard let names = reasons[permission], permissions.state(permission) != .granted else { continue }
            permissions.request(permission, reason: L("Needed by ") + names.joined(separator: L(" and ")) + ".",
                                lifetime: lifetime)
        }
    }

    // MARK: Reset

    /// General → Backup & Reset: every module stops, every setting goes back to its
    /// default, and Snaptic relaunches.
    func resetAllSettings() {
        let alert = NSAlert()
        alert.messageText = L("Reset all Snaptic settings?")
        alert.informativeText = L("Every module, shortcut, menu and display setting goes back to its default. Snaptic then restarts.")
        alert.addButton(withTitle: L("Reset"))
        alert.addButton(withTitle: L("Cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for id in ModuleID.allCases.reversed() where running[id] != nil { stopModule(id) }
        sinks.removeAll()
        modulesStore.value = ModulesConfig()
        displaysStore.value = DisplaysConfig()
        switcherSettings.reset()
        modulesStore.flush()
        displaysStore.flush()
        switcherSettings.flush()
        EventLog.shared.record(.modules, "All settings reset")
        relauncher.relaunch(reason: "settings reset")
    }
}
