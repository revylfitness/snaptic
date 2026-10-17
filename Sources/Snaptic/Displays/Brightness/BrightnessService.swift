import AppKit
import Combine
import Darwin
import SnapticKit

/// The Mac Snaptic runs on (model, chip, OS), read once.
enum HostInfo {
    static let current: HostDescription = {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return HostDescription(modelIdentifier: sysctlString("hw.model") ?? "",
                               chipName: sysctlString("machdep.cpu.brand_string") ?? "",
                               osMajor: os.majorVersion, osMinor: os.minorVersion)
    }()

    /// Two-call sizing; nil on failure.
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// The combined brightness slider per display (PLAN §6.1): picks a hardware method
/// (Apple native, DDC) and a software method (gamma, overlay), splits the slider with
/// CombinedScale, extends into XDR when enabled, restores on launch/wake, and publishes
/// every change with its source.
@MainActor final class BrightnessService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .brightness }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    enum Source: Sendable { case user, keys, sync, restore, automation, cli }

    struct Change: Sendable {
        let key: DisplayKey
        let value: Double
        let source: Source
    }

    private struct State {
        var position: Double = 1
        var hardware: BrightnessMethod?
        var software: BrightnessMethod?
        var reason = ""
        var initialized = false
        var overlay: OverlayToken?
        var xdrEnabled = false
        var xdrMax: Double = 1
        var xdrMethod: EDRBoost.Method = .overlay
        var lastHardware: Double?
        var lastSetAt: TimeInterval = 0
        var appleVerified = false
    }

    private let subject = PassthroughSubject<Change, Never>()
    private var states: [DisplayKey: State] = [:]
    private var sinks: [AnyCancellable] = []
    private var observers: [NSObjectProtocol] = []
    private var lifetime: Lifetime?
    private var pollTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var ddcPending: [DisplayKey: UInt16] = [:]
    private var ddcWriting: Set<DisplayKey> = []
    private var appleBlocked: Set<DisplayKey> = []
    private let authWatcher = AuthWindowWatcher()
    /// Displays held at the dim-on-lock level (key → level).
    private var lockDim: [DisplayKey: Double] = [:]

    init() {}

    var changes: AnyPublisher<DisplayKey, Never> { subject.map(\.key).eraseToAnyPublisher() }
    /// Every change with its value and source (sync, OSD, menus).
    var changeEvents: AnyPublisher<Change, Never> { subject.eraseToAnyPublisher() }

    // MARK: Lifecycle

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        self.lifetime = lifetime
        authWatcher.onChange = { [weak self] present in
            guard let self, let context = self.context else { return }
            context.overlays.setAuthenticationHidden(present)
            context.gamma.setAuthenticationRaise(present)
        }
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.reevaluate() } }
            .store(in: &sinks)
        context.ddc.onChange = { [weak self] key in self?.hardwareInfoChanged(key) }
        context.appleBrightness.onChange = { [weak self] key in self?.hardwareInfoChanged(key) }
        context.gamma.onGiveUp = { [weak self] key in
            guard let self, let context = self.context else { return }
            context.toasts.show(L("Another app keeps changing this display's colors. Snaptic switched to overlay dimming."),
                                lifetime: self.lifetime)
            self.reevaluate(key)
        }
        context.gamma.onAllowedChange = { [weak self] in self?.reevaluate() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        let poll = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollHardware() }
        }
        poll.tolerance = 0.5
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
        reevaluate()
    }

    func deactivate() {
        flushSave()
        sinks.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        authWatcher.isEnabled = false
        authWatcher.onChange = nil
        if let context {
            for state in states.values { if let token = state.overlay { context.overlays.remove(token) } }
            if context.ddc.onChange != nil { context.ddc.onChange = nil }
            context.appleBrightness.onChange = nil
            context.gamma.onGiveUp = nil
            context.gamma.onAllowedChange = nil
            for key in states.keys { context.gamma.setSoftwareBrightness(1, for: key) }
        }
        states.removeAll()
        ddcPending.removeAll()
        ddcWriting.removeAll()
        appleBlocked.removeAll()
        lockDim.removeAll()
        lifetime = nil
        context = nil
    }

    // MARK: Queries

    /// Combined position (0…1, above 1 = XDR), nil when the display isn't managed.
    func value(for key: DisplayKey) -> Double? { states[key].map(\.position) }

    func methods(for key: DisplayKey) -> [BrightnessMethod] {
        guard let context, let display = context.registry.info(for: key) else { return [] }
        return BrightnessMethod.allCases.filter { isUsable($0, display: display, context: context) }
    }

    func activeMethod(for key: DisplayKey) -> BrightnessMethod? {
        guard let s = states[key] else { return nil }
        return s.hardware ?? s.software
    }

    func hardwareMethod(for key: DisplayKey) -> BrightnessMethod? { states[key]?.hardware }
    func softwareMethod(for key: DisplayKey) -> BrightnessMethod? { states[key]?.software }
    func methodReason(for key: DisplayKey) -> String { states[key]?.reason ?? L("Not managed") }

    func scale(for key: DisplayKey) -> CombinedScale? {
        guard let s = states[key], let context else { return nil }
        return scale(for: key, state: s, context: context)
    }

    func range(for key: DisplayKey) -> ClosedRange<Double> { scale(for: key)?.range ?? 0...1 }

    /// Levels the slider position produces right now.
    func output(for key: DisplayKey) -> CombinedScale.Output? {
        guard let s = states[key], let sc = scale(for: key) else { return nil }
        return sc.split(s.position)
    }

    /// Estimated luminance (nits) and whether it's an estimate.
    func nits(for key: DisplayKey) -> (value: Double, estimate: Bool)? {
        guard let context, let display = context.registry.info(for: key), let out = output(for: key) else { return nil }
        let range = nitsRange(for: display)
        return (NitsModel.nits(hardware: out.hardware, software: out.software, xdr: out.xdr, range: range), range.isEstimate)
    }

    func nitsRange(for display: DisplayInfo) -> NitsRange {
        if let custom = context?.config.value.perDisplay[display.key]?.brightness.nits { return custom.sanitized() }
        return NitsModel.defaultRange(isBuiltin: display.isBuiltin, isXDR: display.edrPotential > 1.01,
                                      chipName: HostInfo.current.chipName)
    }

    /// Whether dim to black applies to a display now (feature, invariant 3, guard).
    func allowsBlack(_ key: DisplayKey) -> Bool {
        guard let context, context.runtime.isEffective(.dimToBlack), context.guardClient.isAlive else { return false }
        return context.registry.displays.contains { $0.key != key && $0.isStronglyVisible }
    }

    var isDimToBlackActive: Bool {
        guard let context else { return false }
        return states.contains { key, s in
            guard allowsBlack(key) else { return false }
            return scale(for: key, state: s, context: context).split(s.position).software < BrightnessConfig.dimFloor
        }
    }

    // MARK: Changes

    func set(_ value: Double, for key: DisplayKey, source: Source) {
        guard var s = states[key], let context else { return }
        let sc = scale(for: key, state: s, context: context)
        var v = value.isFinite ? value : s.position
        v = min(sc.xdrMax, max(0, v))
        if source == .restore { v = max(v, BrightnessConfig.restoreFloor) }
        guard abs(v - s.position) > 0.0001 || !s.initialized else { return }
        s.position = v
        s.initialized = true
        s.lastSetAt = ProcessInfo.processInfo.systemUptime
        states[key] = s
        apply(key, animated: source == .keys || source == .sync || source == .restore, interactive: source != .sync && source != .restore && source != .automation)
        publish(key, v, source)
        if source != .restore { scheduleSave() }
    }

    func step(_ delta: Double, for key: DisplayKey, source: Source) {
        guard let s = states[key] else { return }
        set(s.position + delta, for: key, source: source)
    }

    /// The hardware level changed outside Snaptic (DDC readback, macOS keys, auto-brightness).
    func noteHardwareChanged(_ key: DisplayKey, hardware: Double) {
        guard var s = states[key], let context, s.hardware != nil else { return }
        if let last = s.lastHardware, abs(last - hardware) < 0.02 { return }
        s.lastHardware = hardware
        let sc = scale(for: key, state: s, context: context)
        let out = sc.split(s.position)
        let p = sc.position(hardware: hardware, software: out.software, xdr: out.xdr)
        guard abs(p - s.position) > 0.005 else {
            states[key] = s
            return
        }
        s.position = p
        states[key] = s
        context.runtime.runtime(for: key).brightness = min(1, p)
        publish(key, p, .automation)
    }

    /// XDR range for a display (XDRController). `max` ≤ 1 turns XDR off.
    func setXDR(enabled: Bool, max: Double, method: EDRBoost.Method, for key: DisplayKey) {
        guard var s = states[key] else { return }
        s.xdrEnabled = enabled && max > 1
        s.xdrMax = s.xdrEnabled ? max : 1
        s.xdrMethod = method
        if !s.xdrEnabled { s.position = Swift.min(s.position, 1) }
        states[key] = s
        apply(key, animated: false, interactive: true)
    }

    /// Panic and Restore All: overlays removed, gamma restored, XDR off, software neutral.
    func resetSoftware() {
        guard let context else { return }
        for key in Array(states.keys) {
            guard var s = states[key] else { continue }
            if let token = s.overlay { context.overlays.remove(token) }
            s.overlay = nil
            s.xdrEnabled = false
            s.xdrMax = 1
            let sc = scale(for: key, state: s, context: context)
            let out = sc.split(s.position)
            if s.hardware != nil, out.software < 1 { s.position = sc.position(hardware: out.hardware, software: 1) }
            if s.hardware == nil { s.position = 1 }
            states[key] = s
            context.runtime.runtime(for: key).brightness = min(1, s.position)
            context.runtime.runtime(for: key).xdrScale = 1
        }
        context.edr.removeAll()
        context.gamma.restoreAll()
        lockDim.removeAll()
        updateAuthWatcher()
    }

    /// Restore on launch or wake (brightnessRestore). Floor 15%; DDC only when the read-back differs.
    func restoreSaved() {
        guard let context, context.runtime.isEffective(.brightnessRestore), !context.safeMode.isActive,
              !context.panic.isLatched else { return }
        guard context.config.value.brightness.restoreMode == .brightness else { return }
        for key in Array(states.keys) {
            guard let saved = context.config.value.perDisplay[key]?.brightness.value else { continue }
            set(saved, for: key, source: .restore)
        }
    }

    /// Dim on lock (gamma, 10% floor): holds each gamma-dimmed display at `level` until resume.
    func setLockDim(_ level: Double?) {
        guard let context else { return }
        if let level {
            let l = max(BrightnessConfig.dimOnLockFloor, min(1, level))
            for (key, s) in states where s.software == .gamma {
                lockDim[key] = l
                context.gamma.setSoftwareBrightness(min(l, scale(for: key, state: s, context: context).split(s.position).software),
                                                    for: key, animated: true)
            }
        } else {
            let keys = Array(lockDim.keys)
            lockDim.removeAll()
            for key in keys { apply(key, animated: true, interactive: false) }
        }
    }

    // MARK: Method choice (PLAN §6.1)

    private func isUsable(_ method: BrightnessMethod, display: DisplayInfo, context: DisplaysContext) -> Bool {
        let eff = context.runtime.effectiveFeatures
        guard eff.contains(method.feature) else { return false }
        switch method {
        case .apple:
            return context.appleBrightness.isSupported(display.key) && !appleBlocked.contains(display.key)
        case .ddc:
            return context.ddc.isAvailable(display.key) && context.ddc.supportsBrightness(display.key)
        case .gamma:
            guard display.mirrorOf == nil, display.isBuiltin || display.transport == .wired || display.isSmartHiDPIPair
            else { return false }
            if AffectedModels.gammaIsUnreliable(HostInfo.current) { return false }
            if context.config.value.perDisplay[display.key]?.brightness.gammaWorks == false { return false }
            return context.gamma.isAllowed && !context.gamma.hasGivenUp(display.key)
        case .overlay:
            return display.mirrorOf == nil && display.isActive
        }
    }

    private func choose(_ display: DisplayInfo, context: DisplaysContext) -> (BrightnessMethod?, BrightnessMethod?, String) {
        let usable = Set(BrightnessMethod.allCases.filter { isUsable($0, display: display, context: context) })
        let override = context.config.value.perDisplay[display.key]?.brightness.method
        var hardware: BrightnessMethod?
        var software: BrightnessMethod?
        var reason: String
        if let override, usable.contains(override) {
            if override.isHardware {
                hardware = override
            } else {
                software = override
            }
            reason = L("Chosen in Settings")
        } else {
            if usable.contains(.apple) {
                hardware = .apple
                reason = display.isBuiltin ? L("Built-in display") : L("Apple display")
            } else if usable.contains(.ddc) {
                hardware = .ddc
                reason = L("The monitor answers DDC")
            } else {
                reason = display.isBuiltin || display.transport == .wired
                    ? L("No hardware control; software dimming") : L("Software dimming for this connection")
            }
            if let override {
                reason = L("The chosen method isn't available: ") + override.title
            }
        }
        if override == nil || override?.isHardware == true {
            if usable.contains(.gamma) { software = .gamma } else if usable.contains(.overlay) { software = .overlay }
        }
        if hardware == nil && software == nil {
            if AffectedModels.gammaIsUnreliable(HostInfo.current) {
                reason = AffectedModels.reason(.gammaNoOp)
            } else if !context.runtime.isEffective(.brightness) {
                reason = L("Choose a brightness method")
            } else {
                reason = L("No brightness method works on this display")
            }
        }
        return (hardware, software, reason)
    }

    private func scale(for key: DisplayKey, state s: State, context: DisplaysContext) -> CombinedScale {
        let per = context.config.value.perDisplay[key]?.brightness ?? PerDisplayBrightness()
        let switchover = per.switchover ?? CombinedScale.defaultSwitchover(hardware: s.hardware, xdrOn: s.xdrEnabled)
        return CombinedScale(hasHardware: s.hardware != nil, hasSoftware: s.software != nil, switchover: switchover,
                             minHardware: per.minHardware,
                             softwareFloor: allowsBlack(key) ? 0 : BrightnessConfig.dimFloor,
                             xdrMax: s.xdrEnabled ? s.xdrMax : 1)
    }

    /// Re-chooses methods for every online display (registry, features, config changed).
    func reevaluate() {
        guard let context else { return }
        let displays = context.registry.displays.filter { $0.isOnline }
        let keys = Set(displays.map(\.key))
        for key in Array(states.keys) where !keys.contains(key) {
            if let token = states[key]?.overlay { context.overlays.remove(token) }
            context.gamma.release(key)
            states[key] = nil
        }
        for display in displays { reevaluate(display.key) }
        updateAuthWatcher()
    }

    func reevaluate(_ key: DisplayKey) {
        guard let context, let display = context.registry.info(for: key), display.isOnline else { return }
        var s = states[key] ?? State()
        let (hardware, software, reason) = choose(display, context: context)
        let changed = hardware != s.hardware || software != s.software
        let oldSoftware = s.software
        s.hardware = hardware
        s.software = software
        s.reason = reason
        if oldSoftware == .overlay, software != .overlay, let token = s.overlay {
            context.overlays.remove(token)
            s.overlay = nil
        }
        if oldSoftware == .gamma, software != .gamma { context.gamma.setSoftwareBrightness(1, for: key) }
        let firstTime = !s.initialized
        states[key] = s
        if firstTime {
            initialize(key, display: display, context: context)
        } else if changed {
            apply(key, animated: false, interactive: false)
            EventLog.shared.record(.brightness, "Brightness method: \(hardware?.rawValue ?? "-") + \(software?.rawValue ?? "-")")
        }
    }

    /// First sight: restore the saved value, or start from the hardware's current level.
    private func initialize(_ key: DisplayKey, display: DisplayInfo, context: DisplaysContext) {
        guard var s = states[key], s.hardware != nil || s.software != nil else { return }
        let config = context.config.value
        let restoring = context.runtime.isEffective(.brightnessRestore) && config.brightness.restoreMode == .brightness
            && !context.safeMode.isActive && !context.panic.isLatched
        if restoring, let saved = config.perDisplay[key]?.brightness.value {
            s.position = 1
            states[key] = s
            set(saved, for: key, source: .restore)
            return
        }
        var hw: Double?
        switch s.hardware {
        case .apple?: hw = context.appleBrightness.brightness(of: key)
        case .ddc?: hw = context.ddc.lastReading(VCPPolicy.brightness, of: key)
            .map { context.config.value.perDisplay[key]?.ddc.tuning(VCPPolicy.brightness).fraction(raw: $0.current, displayMax: $0.max) ?? $0.fraction }
        default: hw = nil
        }
        s.lastHardware = hw
        s.initialized = true
        let sc = scale(for: key, state: s, context: context)
        s.position = hw.map { sc.position(hardware: $0, software: 1) } ?? 1
        states[key] = s
        context.runtime.runtime(for: key).brightness = min(1, s.position)
        publish(key, s.position, .automation)
    }

    private func hardwareInfoChanged(_ key: DisplayKey) {
        guard let context else { return }
        let before = states[key].map { ($0.hardware, $0.software) }
        reevaluate(key)
        let after = states[key].map { ($0.hardware, $0.software) }
        if before?.0 != after?.0 || before?.1 != after?.1 { context.requestMenuRebuild() }
    }

    // MARK: Applying

    private func apply(_ key: DisplayKey, animated: Bool, interactive: Bool) {
        guard var s = states[key], let context else { return }
        let sc = scale(for: key, state: s, context: context)
        let out = sc.split(s.position)
        let smooth = animated && context.config.value.brightness.smoothTransitions
        if let hw = out.hardware {
            if s.lastHardware.map({ abs($0 - hw) > 0.0005 }) ?? true {
                writeHardware(hw, method: s.hardware, key: key, interactive: interactive)
                s.lastHardware = hw
            }
        }
        var software = out.software
        if let lock = lockDim[key] { software = min(software, lock) }
        let black = allowsBlack(key)
        switch s.software {
        case .gamma?:
            context.gamma.setFloor(black ? 0 : BrightnessConfig.dimFloor, for: key)
            context.gamma.setSoftwareBrightness(software, for: key, animated: smooth)
        case .overlay?:
            if s.overlay == nil, software < 0.999, let display = context.registry.info(for: key) {
                s.overlay = context.overlays.add(.dim, on: display.desktopID)
            }
            if let token = s.overlay {
                context.overlays.setAllowsBlack(token, black)
                context.overlays.update(token, alpha: 1 - software)
            }
        default:
            break
        }
        if out.xdr > 1.0001 {
            context.edr.setBoost(out.xdr, for: key, method: s.xdrMethod)
        } else if context.edr.isBoosting(key) || context.edr.method(key) != nil {
            context.edr.setBoost(1, for: key)
        }
        states[key] = s
        context.runtime.runtime(for: key).brightness = min(1, s.position)
        if s.hardware == .apple, !s.appleVerified, interactive, let hw = out.hardware {
            verifyApple(key, value: hw)
        }
        updateAuthWatcher()
    }

    private func writeHardware(_ value: Double, method: BrightnessMethod?, key: DisplayKey, interactive: Bool) {
        guard let context else { return }
        switch method {
        case .apple?:
            context.appleBrightness.setBrightness(value, of: key)
        case .ddc?:
            let tuning = context.config.value.perDisplay[key]?.ddc.tuning(VCPPolicy.brightness) ?? DDCControlTuning()
            let maximum = context.ddc.lastReading(VCPPolicy.brightness, of: key)?.max ?? 100
            ddcPending[key] = tuning.raw(fraction: value, displayMax: maximum)
            pumpDDC(key, interactive: interactive)
        default:
            break
        }
    }

    /// One DDC write in flight per display; the latest value wins (the service coalesces too).
    private func pumpDDC(_ key: DisplayKey, interactive: Bool) {
        guard !ddcWriting.contains(key), let value = ddcPending.removeValue(forKey: key), let context,
              let lifetime else { return }
        ddcWriting.insert(key)
        let ddc = context.ddc
        let task = lifetime.spawn { [weak self] in
            let ok: Bool
            if interactive {
                ok = await ddc.write(VCPPolicy.brightness, value, to: key, interactive: true, token: nil)
            } else {
                ok = await ddc.writeIfDifferent(VCPPolicy.brightness, value, to: key)
            }
            guard let self else { return }
            self.ddcWriting.remove(key)
            if !ok { EventLog.shared.record(.brightness, "DDC brightness write failed") }
            self.pumpDDC(key, interactive: interactive)
        }
        if task == nil { ddcWriting.remove(key) }
    }

    /// An Apple preset with fixed brightness ignores DisplayServices: detect and fall back.
    private func verifyApple(_ key: DisplayKey, value: Double) {
        guard let context, let lifetime else { return }
        states[key]?.appleVerified = true
        let io = context.appleBrightness
        lifetime.spawn { [weak self] in
            let ok = await io.verifySet(value, of: key)
            guard let self, !ok, self.states[key]?.hardware == .apple else { return }
            EventLog.shared.record(.brightness, "Apple brightness didn't change (fixed-brightness preset?); falling back")
            self.appleBlocked.insert(key)
            self.reevaluate(key)
        }
    }

    private func publish(_ key: DisplayKey, _ value: Double, _ source: Source) {
        subject.send(Change(key: key, value: value, source: source))
    }

    private func updateAuthWatcher() {
        guard let context else { return }
        let strongOverlay = context.overlays.strongestDim > 0.5
        authWatcher.isEnabled = strongOverlay || isDimToBlackActive
    }

    // MARK: Persistence, polling, wake

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flushSave() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        guard let context else { return }
        var config = context.config.value
        var changed = false
        for (key, s) in states where s.initialized {
            let v = (min(1, s.position) * 1000).rounded() / 1000
            var per = config.perDisplay[key] ?? PerDisplayConfig()
            if per.brightness.value != v {
                per.brightness.value = v
                config.perDisplay[key] = per
                changed = true
            }
        }
        if changed { context.config.value = config }
    }

    /// Picks up changes macOS made to Apple displays (keys, auto-brightness).
    private func pollHardware() {
        guard let context, let lifetime, context.sessionGate.isOpen else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for (key, s) in states where s.hardware == .apple && now - s.lastSetAt > 2 {
            let io = context.appleBrightness
            lifetime.spawn { [weak self] in
                guard let value = await io.refresh(key) else { return }
                self?.noteHardwareChanged(key, hardware: value)
            }
        }
    }

    private func didWake() {
        guard let context else { return }
        // Software dimming re-applies at once (gamma re-applies itself); hardware via restore.
        for key in Array(states.keys) {
            states[key]?.lastHardware = nil
            apply(key, animated: false, interactive: false)
        }
        if context.config.value.ddc.restoreOnWake { restoreSaved() }
    }
}
