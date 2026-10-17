import Foundation
import SnapticKit

/// Everything a Displays controller or service can reach (lead; teams never edit).
/// Built once per module start. Owns the services; services hold it weakly.
@MainActor final class DisplaysContext {
    // Services (one per DisplayServiceID, constructed eagerly, activated by refcount).
    let registry: DisplayRegistry
    let sessionGate: SessionGate
    let guardClient: DisplayGuardClient
    let transactions: DisplayTransactionQueue
    let appleBrightness: AppleBrightnessIO
    let ddc: DDCService
    let gamma: GammaService
    let overlays: OverlayService
    let edr: EDRBoost
    let brightness: BrightnessService
    let osd: OSDPresenter
    let colorSync: ColorSyncService
    let monitorPanel: MonitorPanelService
    let mediaKeys: MediaKeyService
    let virtualHosts: VirtualHostsService
    let capture: CaptureService
    let spawner: SpawnerService

    // Platform and safety objects that are not refcounted services.
    /// Owned by DisplaysModule (symbols are registered once, at module construction).
    let privateAPI: PrivateDisplayAPI
    let preConfirm: PreConfirmPresenter
    let panic: PanicCoordinator
    let connectPlanner: ConnectPlanner

    // Registries and state (lead).
    let actions: DisplayActionRegistry
    let menus: DisplayMenuRegistry
    let diagnostics: DiagnosticsRegistry
    let config: ConfigStore<DisplaysConfig>
    let runtime: DisplaysRuntimeState

    // Host services, from the ModuleContext.
    let safeMode: SafeModeState
    let hotkeys: GlobalHotkeys
    let commands: ControlCommandRegistry
    let toasts: ToastPresenter
    let permissions: PermissionFlow
    let helpers: HelperSpawner
    let relauncher: Relauncher
    let otherApps: OtherAppsMonitor
    let requestMenuRebuild: @MainActor () -> Void
    /// Ends when the Displays module stops.
    let lifetime: Lifetime

    private struct WeakPanic { weak var value: (any PanicParticipant)? }
    private struct WeakSession { weak var value: (any SessionParticipant)? }
    private var panicList: [WeakPanic] = []
    private var sessionList: [WeakSession] = []

    init(module: ModuleContext, privateAPI: PrivateDisplayAPI, config: ConfigStore<DisplaysConfig>,
         runtime: DisplaysRuntimeState, lifetime: Lifetime) {
        registry = DisplayRegistry()
        sessionGate = SessionGate()
        guardClient = DisplayGuardClient()
        transactions = DisplayTransactionQueue()
        appleBrightness = AppleBrightnessIO()
        ddc = DDCService()
        gamma = GammaService()
        overlays = OverlayService()
        edr = EDRBoost()
        brightness = BrightnessService()
        osd = OSDPresenter()
        colorSync = ColorSyncService()
        monitorPanel = MonitorPanelService()
        mediaKeys = MediaKeyService()
        virtualHosts = VirtualHostsService()
        capture = CaptureService()
        spawner = SpawnerService()

        self.privateAPI = privateAPI
        preConfirm = PreConfirmPresenter()
        panic = PanicCoordinator()
        connectPlanner = ConnectPlanner()

        actions = DisplayActionRegistry()
        menus = DisplayMenuRegistry()
        diagnostics = DiagnosticsRegistry()
        self.config = config
        self.runtime = runtime

        safeMode = module.safeMode
        hotkeys = module.hotkeys
        commands = module.commands
        toasts = module.toasts
        permissions = module.permissions
        helpers = module.spawner
        relauncher = module.relauncher
        otherApps = module.otherApps
        requestMenuRebuild = module.requestMenuRebuild
        self.lifetime = lifetime
    }

    /// The service object for an id (total over DisplayServiceID).
    func service(_ id: DisplayServiceID) -> any DisplayServiceLifecycle {
        switch id {
        case .registry: return registry
        case .sessionGate: return sessionGate
        case .guardProcess: return guardClient
        case .transactions: return transactions
        case .appleBrightness: return appleBrightness
        case .ddc: return ddc
        case .gamma: return gamma
        case .overlays: return overlays
        case .edr: return edr
        case .brightness: return brightness
        case .osd: return osd
        case .colorSync: return colorSync
        case .monitorPanel: return monitorPanel
        case .mediaKeys: return mediaKeys
        case .virtualHosts: return virtualHosts
        case .capture: return capture
        case .spawner: return spawner
        }
    }

    // MARK: Participants (weak; removed when the registering lifetime ends)

    func registerPanic(_ participant: any PanicParticipant, lifetime: Lifetime) {
        panicList.removeAll { $0.value == nil }
        panicList.append(WeakPanic(value: participant))
        lifetime.onEnd { [weak self, weak participant] in
            self?.panicList.removeAll { $0.value == nil || $0.value === participant }
        }
    }

    func registerSession(_ participant: any SessionParticipant, lifetime: Lifetime) {
        sessionList.removeAll { $0.value == nil }
        sessionList.append(WeakSession(value: participant))
        lifetime.onEnd { [weak self, weak participant] in
            self?.sessionList.removeAll { $0.value == nil || $0.value === participant }
        }
    }

    var panicParticipants: [any PanicParticipant] { panicList.compactMap(\.value) }
    var sessionParticipants: [any SessionParticipant] { sessionList.compactMap(\.value) }
}
