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
            store.value = launchedBefore ? ModulesConfig.upgradeDefaults() : ModulesConfig()
            store.flush()
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
        requestLaunchPermissions()
    }

    /// Quit path: stops modules in reverse order and flushes every store.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        applyWork?.cancel()
        applyWork = nil
        sinks.removeAll()
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

    // MARK: Permissions

    /// One request per launch for what the running modules need.
    private func requestLaunchPermissions() {
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
