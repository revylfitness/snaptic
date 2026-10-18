import Combine
import Foundation
import SnapticKit

/// Live values for one display, observed by pages, menus and the floating panel.
@MainActor final class DisplayRuntime: ObservableObject {
    let key: DisplayKey
    /// 0…1, nil when unknown.
    @Published var brightness: Double?
    @Published var contrast: Double?
    @Published var volume: Double?
    @Published var muted: Bool?
    /// 1 = SDR; above 1 = XDR boost factor.
    @Published var xdrScale: Double = 1
    @Published var input: UInt16?
    @Published var powerOn: Bool?
    @Published var statusText: String?
    /// 0.3 §4.5: the full brightness range incl. XDR (C writes it; pages never read BrightnessService.states).
    @Published var brightnessPosition: Double?
    @Published var brightnessRange: ClosedRange<Double> = 0...1
    @Published var contrastRange: ClosedRange<Double> = 0...1
    @Published var volumeRange: ClosedRange<Double> = 0...1

    init(key: DisplayKey) { self.key = key }
}

/// Module-wide live state (lead). Owned by DisplaysModule across starts.
@MainActor final class DisplaysRuntimeState: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var effectiveFeatures: Set<DisplayFeature> = []
    @Published var availability: [DisplayFeature: FeatureAvailability] = [:]
    @Published var moduleState: ModuleState = .stopped
    @Published var isPanicLatched = false
    @Published var lastPanicSummary: String?
    private var perDisplay: [DisplayKey: DisplayRuntime] = [:]
    private var revisions: [DisplayControllerID: ControllerRevision] = [:]

    init() {}

    /// One revision object per controller id (0.3 §4.5), kept across module starts.
    func revision(_ id: DisplayControllerID) -> ControllerRevision {
        if let r = revisions[id] { return r }
        let r = ControllerRevision()
        revisions[id] = r
        return r
    }

    func runtime(for key: DisplayKey) -> DisplayRuntime {
        if let r = perDisplay[key] { return r }
        let r = DisplayRuntime(key: key)
        perDisplay[key] = r
        return r
    }

    func isEffective(_ feature: DisplayFeature) -> Bool { effectiveFeatures.contains(feature) }

    /// Drops live values for displays that are gone (keeps settings, which live in config).
    func prune(keeping keys: Set<DisplayKey>) {
        perDisplay = perDisplay.filter { keys.contains($0.key) }
    }

    func reset() {
        displays = []
        effectiveFeatures = []
        availability = [:]
        perDisplay = [:]
        isPanicLatched = false
        lastPanicSummary = nil
    }
}

/// What every Displays settings page receives (R5.1).
@MainActor final class DisplaysPageEnvironment: ObservableObject {
    let config: ConfigStore<DisplaysConfig>
    let runtime: DisplaysRuntimeState
    /// Nil while the module is stopped; pages then show their settings without live controls.
    @Published private(set) var context: DisplaysContext?
    /// Turns a feature on together with what it requires; used by "Turn on" buttons.
    let enableFeature: @MainActor (DisplayFeature) -> Void
    private var forward: [AnyCancellable] = []

    init(config: ConfigStore<DisplaysConfig>, runtime: DisplaysRuntimeState,
         enableFeature: @escaping @MainActor (DisplayFeature) -> Void) {
        self.config = config
        self.runtime = runtime
        self.enableFeature = enableFeature
        forward.append(config.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        forward.append(runtime.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
    }

    func setContext(_ context: DisplaysContext?) { self.context = context }
}
