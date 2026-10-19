import AppKit
import SnapticKit

/// Explicit host services Awake uses (lead; PLAN 0.3 §2.11), built from ModuleContext.
@MainActor final class AwakeHost {
    let safeMode: SafeModeState
    let signals: HostSignals
    let hotkeys: GlobalHotkeys
    let commands: ControlCommandRegistry
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let requestMenuRebuild: @MainActor () -> Void
    /// Re-plans now (StatusMenu.applyPlan in this turn): called whenever `governing` changes active ↔ inactive.
    let requestStatusPlan: @MainActor () -> Void
    /// ⌘-drag removal and the "Don't Show" fallback write presence through the host.
    let setPresence: @MainActor (MenuPresence) -> Void
    /// Calls ModuleContext.openSettings(route?.id); the host parses "<root>.<route>".
    let openSettings: @MainActor (SettingsRoute?) -> Void
    /// The module's lifetime (one start…stop).
    let lifetime: Lifetime
    /// 0.3.1 B3.1, B3.3: lid-closed mode's osascript and `pmset displaysleepnow` go through the host's spawner.
    let spawner: HelperSpawner
    /// 0.3.1 B3.4: the host-level leftovers (nil only before AppDelegate wired the host).
    private(set) weak var lidRecovery: LidRecoveryState?
    /// 0.3.1 B3.4, E1: the host, for the rows Awake's own menu shares with the Snaptic menu
    /// (`StatusMenu.leftoverItems(host:)`, `StatusMenu.updateItems(host:)`).
    private(set) weak var moduleHost: ModuleHost?

    init(_ module: ModuleContext, moduleHost: ModuleHost? = nil) {
        safeMode = module.safeMode
        signals = module.hostSignals
        hotkeys = module.hotkeys
        commands = module.commands
        toasts = module.toasts
        permissions = module.permissions
        requestMenuRebuild = module.requestMenuRebuild
        requestStatusPlan = module.requestStatusPlan
        let setModulePresence = module.setPresence
        setPresence = { presence in setModulePresence(.awake, presence) }
        let open = module.openSettings
        openSettings = { route in open(route?.id) }
        lifetime = module.lifetime
        spawner = module.spawner
        self.moduleHost = moduleHost
        lidRecovery = moduleHost?.lidRecovery
    }
}

/// Services, controllers other controllers call, stores and runtime of one Awake start (lead; PLAN 0.3 §2.11).
/// Services hold it weakly.
@MainActor final class AwakeContext {
    let assertions: AssertionManager, power: PowerMonitor, system: SystemEventsMonitor, apps: AppMonitor
    let displays: DisplayPresence, usb: USBWatcher, volumes: VolumeMonitor, audio: AudioMonitor
    let cpu: CPUSampler, idle: IdleSampler, network: NetworkMonitor, bluetooth: BluetoothPresence
    let activity: ActivitySimulator, driveAlive: DriveAliveService, disk: DiskIOSampler, process: ProcessWatch
    let config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>, history: ConfigStore<AwakeHistory>
    let runtime: AwakeRuntimeState
    let host: AwakeHost
    /// Controllers other controllers call.
    let sessions: SessionController, triggers: TriggerController
    /// 0.3.1 B3: lid-closed mode (SessionController starts and stops it with the sessions feature).
    let lid: LidClosedController

    init(host: AwakeHost, config: ConfigStore<AwakeConfig>, state: ConfigStore<AwakeRuntimeSnapshot>,
         history: ConfigStore<AwakeHistory>, runtime: AwakeRuntimeState) {
        self.host = host
        self.config = config
        self.state = state
        self.history = history
        self.runtime = runtime
        assertions = AssertionManager()
        power = PowerMonitor()
        system = SystemEventsMonitor()
        apps = AppMonitor()
        displays = DisplayPresence()
        usb = USBWatcher()
        volumes = VolumeMonitor()
        audio = AudioMonitor()
        cpu = CPUSampler()
        idle = IdleSampler()
        network = NetworkMonitor()
        bluetooth = BluetoothPresence()
        activity = ActivitySimulator()
        driveAlive = DriveAliveService()
        disk = DiskIOSampler()
        process = ProcessWatch()
        sessions = SessionController()
        triggers = TriggerController()
        lid = LidClosedController()
    }

    func service(_ id: AwakeServiceID) -> any AwakeServiceLifecycle {
        switch id {
        case .assertions: return assertions
        case .power: return power
        case .system: return system
        case .apps: return apps
        case .displays: return displays
        case .usb: return usb
        case .volumes: return volumes
        case .audio: return audio
        case .cpu: return cpu
        case .disk: return disk
        case .idle: return idle
        case .network: return network
        case .bluetooth: return bluetooth
        case .activity: return activity
        case .driveAlive: return driveAlive
        case .process: return process
        }
    }

    /// nil for `.schedule` (TriggerController's Ticker; consistency M5).
    func source(for kind: AwakeCriterionKind) -> (any CriterionSource)? {
        switch kind {
        case .app: return apps
        case .display: return displays
        case .power: return power
        case .schedule: return nil
        case .cpu: return cpu
        case .audio: return audio
        case .idle: return idle
        case .volume: return volumes
        case .usb: return usb
        case .network, .networkActivity: return network
        case .bluetooth: return bluetooth
        }
    }
}
