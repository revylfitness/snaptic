import AppKit
import Combine
import SnapticKit
import SnapticShims

/// Gamma composer (PLAN §6.2, §4.9): baseline ∘ adjustments × brightness × xdrScale per
/// display, written with CGSetDisplayTransferByTable. Owns the zero-table watchdog, fight
/// detection, ColorSync restore and the Apple silicon redraw nudge.
@MainActor final class GammaService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .gamma }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?
    /// The running color controller, for the Color page (set in start, cleared in stop).
    weak var colorController: ColorController?

    private struct State {
        var adjustments = ColorAdjustments()
        var brightness: Double = 1
        var xdrScale: Double = 1
        var floor: Double = BrightnessConfig.dimFloor
        /// Last table written (nil = not managing this display).
        var written: GammaTable?
        var writtenTo: UInt32 = 0
        var collapses = 0
        var fights = GammaFightTracker()
        var gaveUp = false
        var ramp: (from: Double, to: Double, start: TimeInterval)?

        var inputs: GammaMath.Inputs {
            GammaMath.Inputs(adjustments: adjustments, brightness: brightness, xdrScale: xdrScale, floor: floor)
        }
    }

    private var states: [DisplayKey: State] = [:]
    /// Baseline (ColorSync) table per CG display id, captured after our own restore.
    private var baselines: [UInt32: GammaTable] = [:]
    private var baselinesValid = false
    private var watchdog: Timer?
    private var rampTimer: Timer?
    private var paused = false
    private var authRaise = false
    private var sinks: [AnyCancellable] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var nudgeWindows: [UInt32: NSWindow] = [:]
    private var nudgeToggle = false
    private var reapplyWork: DispatchWorkItem?

    /// Gamma writes are refused while false (custom-profile safeguard, kill switch).
    private(set) var isAllowed = true {
        didSet {
            guard isAllowed != oldValue else { return }
            if !isAllowed { releaseAll() }
            onAllowedChange?()
        }
    }
    /// True while a custom ColorSync profile blocks gamma (and the user didn't override).
    private(set) var blockedByCustomProfile = false
    /// Called when `isAllowed` changes (BrightnessService re-chooses methods).
    var onAllowedChange: (@MainActor () -> Void)?

    /// The custom-profile safeguard (PLAN §6.1, parity §5.8): while any display uses a
    /// custom profile, gamma is off on all displays unless the user overrides it.
    func refreshSafeguard() {
        guard let context else { return }
        let custom = context.registry.displays.contains { $0.isOnline && SNColorSync.hasCustomProfile(forDisplay: $0.hardwareID) }
        blockedByCustomProfile = custom && !context.config.value.color.allowGammaWithCustomProfile
        isAllowed = !blockedByCustomProfile
    }
    /// Called when gamma gave up on a display (3 fights in 60 s): suggest the overlay method.
    var onGiveUp: (@MainActor (DisplayKey) -> Void)?

    static let watchdogInterval: TimeInterval = 3
    static let rampDuration: TimeInterval = 0.15
    /// While an authentication window is on screen, dim to black is raised to this.
    static let authFloor = 0.3

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        baselinesValid = false
        context.registerSession(self, lifetime: lifetime)
        context.registry.changes
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleReapply(recapture: true, delay: 0.5) } }
            .store(in: &sinks)
        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.paused = false
                self?.reapplyAll(recapture: true)
                self?.updateWatchdog()
            }
        }))
        observers.append((ws, ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.paused = true
                self?.updateWatchdog()
            }
        }))
        let dnc = DistributedNotificationCenter.default()
        let profileChanged = Notification.Name(SNColorSync.displayProfilesNotificationName())
        observers.append((dnc, dnc.addObserver(forName: profileChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSafeguard()
                self?.scheduleReapply(recapture: true, delay: 0.3)
            }
        }))
        context.config.$value
            .map(\.color.allowGammaWithCustomProfile)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refreshSafeguard() } }
            .store(in: &sinks)
        refreshSafeguard()
    }

    func deactivate() {
        sinks.removeAll()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        reapplyWork?.cancel()
        reapplyWork = nil
        restoreAll()
        nudgeWindows.values.forEach { $0.orderOut(nil) }
        nudgeWindows.removeAll()
        onAllowedChange = nil
        onGiveUp = nil
        isAllowed = true
        context = nil
    }

    // MARK: API

    func setAdjustments(_ adjustments: ColorAdjustments, for key: DisplayKey) {
        var s = states[key] ?? State()
        s.adjustments = adjustments.sanitized()
        states[key] = s
        apply(key)
    }

    func setSoftwareBrightness(_ value: Double, for key: DisplayKey) {
        setSoftwareBrightness(value, for: key, animated: false)
    }

    /// 150 ms ramp when `animated` (never with Reduce Motion).
    func setSoftwareBrightness(_ value: Double, for key: DisplayKey, animated: Bool) {
        var s = states[key] ?? State()
        let target = value.isFinite ? min(1, max(0, value)) : 1
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, abs(s.brightness - target) > 0.01 {
            s.ramp = (s.brightness, target, ProcessInfo.processInfo.systemUptime)
            states[key] = s
            startRamp()
            return
        }
        s.ramp = nil
        s.brightness = target
        states[key] = s
        apply(key)
    }

    func setXDRScale(_ scale: Double, for key: DisplayKey) {
        var s = states[key] ?? State()
        s.xdrScale = scale.isFinite ? max(1, min(GammaMath.maxXDRScale, scale)) : 1
        states[key] = s
        apply(key)
    }

    /// Software dimming floor (0.08, or 0 with dim to black).
    func setFloor(_ floor: Double, for key: DisplayKey) {
        var s = states[key] ?? State()
        s.floor = min(1, max(0, floor))
        states[key] = s
        apply(key)
    }

    /// Raises dim to black to ≥ 30% while an authentication window shows (R5.7).
    func setAuthenticationRaise(_ on: Bool) {
        guard authRaise != on else { return }
        authRaise = on
        for key in states.keys where states[key]?.floor ?? 1 < BrightnessConfig.dimFloor { apply(key) }
    }

    var isDimmingToBlack: Bool {
        states.values.contains { $0.written != nil && $0.floor < BrightnessConfig.dimFloor && $0.brightness < BrightnessConfig.dimFloor }
    }

    func isManaging(_ key: DisplayKey) -> Bool { states[key]?.written != nil }
    func hasGivenUp(_ key: DisplayKey) -> Bool { states[key]?.gaveUp ?? false }
    func softwareBrightness(of key: DisplayKey) -> Double { states[key]?.brightness ?? 1 }

    /// Lets gamma try again on a display (after the user picked it explicitly).
    func resetGiveUp(_ key: DisplayKey) {
        states[key]?.gaveUp = false
        states[key]?.fights.reset()
        apply(key)
    }

    /// Stops managing one display and restores its baseline.
    func release(_ key: DisplayKey) {
        guard let s = states.removeValue(forKey: key), s.written != nil else { return }
        if let base = baselines[s.writtenTo] { write(base, to: s.writtenTo) } else { CGDisplayRestoreColorSyncSettings() }
        updateWatchdog()
    }

    /// ColorSync restore: every display back to its profile, all state cleared (panic, stop).
    func restoreAll() {
        let wasManaging = states.values.contains { $0.written != nil }
        states.removeAll()
        rampTimer?.invalidate()
        rampTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        if wasManaging { CGDisplayRestoreColorSyncSettings() }
        baselinesValid = false
    }

    private func releaseAll() {
        let keys = Array(states.keys)
        for key in keys { states[key]?.written = nil }
        CGDisplayRestoreColorSyncSettings()
        baselinesValid = false
        updateWatchdog()
    }

    func diagnostics(for key: DisplayKey) -> String {
        guard let s = states[key] else { return "not managed" }
        if s.gaveUp { return "stopped after repeated interference" }
        return s.written == nil ? "neutral" : String(format: "brightness %.2f, xdr %.2f, floor %.2f", s.brightness, s.xdrScale, s.floor)
    }

    // MARK: Writing

    /// The CG display gamma applies to: the virtual of a Smart HiDPI pair, else the panel.
    private func targetID(_ key: DisplayKey) -> UInt32? {
        guard let info = context?.registry.info(for: key), info.isOnline else { return nil }
        return info.isSmartHiDPIPair ? info.desktopID : info.hardwareID
    }

    private func apply(_ key: DisplayKey) {
        guard var s = states[key], let id = targetID(key) else { return }
        guard isAllowed, !s.gaveUp else {
            if s.written != nil { release(key) }
            return
        }
        var inputs = s.inputs
        if authRaise, s.floor < BrightnessConfig.dimFloor { inputs.brightness = max(inputs.brightness, Self.authFloor) }
        if inputs.isNeutral {
            if s.written != nil {
                if let base = baselines[s.writtenTo] { write(base, to: s.writtenTo) }
                s.written = nil
                states[key] = s
                updateWatchdog()
            }
            return
        }
        ensureBaselines()
        let table = GammaMath.compose(baseline: baselines[id], inputs: inputs)
        guard write(table, to: id) else { return }
        s.written = table
        s.writtenTo = id
        s.collapses = 0
        states[key] = s
        updateWatchdog()
    }

    @discardableResult
    private func write(_ table: GammaTable, to id: UInt32) -> Bool {
        guard table.isValid else { return false }
        let n = UInt32(table.count)
        let result = table.red.withUnsafeBufferPointer { r in
            table.green.withUnsafeBufferPointer { g in
                table.blue.withUnsafeBufferPointer { b in
                    CGSetDisplayTransferByTable(id, n, r.baseAddress, g.baseAddress, b.baseAddress)
                }
            }
        }
        if result != .success {
            EventLog.shared.record(.gamma, "Gamma write failed (\(result.rawValue))")
            return false
        }
        nudge(id)
        return true
    }

    private static func read(_ id: UInt32) -> GammaTable? {
        let capacity = Int(CGDisplayGammaTableCapacity(id))
        guard capacity >= 2, capacity <= GammaMath.maxSamples else { return nil }
        var r = [CGGammaValue](repeating: 0, count: capacity)
        var g = [CGGammaValue](repeating: 0, count: capacity)
        var b = [CGGammaValue](repeating: 0, count: capacity)
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, UInt32(capacity), &r, &g, &b, &count) == .success,
              count >= 2, Int(count) <= capacity else { return nil }
        let n = Int(count)
        let table = GammaTable(red: Array(r.prefix(n)), green: Array(g.prefix(n)), blue: Array(b.prefix(n)))
        return table.isValid ? table : nil
    }

    /// Restores ColorSync once, then captures every online display's baseline.
    private func ensureBaselines() {
        guard !baselinesValid else { return }
        CGDisplayRestoreColorSyncSettings()
        baselines.removeAll()
        for id in CGDirectDisplayID.online() {
            if let table = Self.read(id), !table.isAllZero { baselines[id] = table }
        }
        baselinesValid = true
    }

    private func scheduleReapply(recapture: Bool, delay: TimeInterval) {
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reapplyAll(recapture: recapture) }
        }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// After a ColorSync restore (ours or the system's), re-apply every managed display.
    private func reapplyAll(recapture: Bool) {
        guard states.values.contains(where: { $0.written != nil }) else {
            if recapture { baselinesValid = false }
            return
        }
        if recapture { baselinesValid = false }
        for key in Array(states.keys) where states[key]?.written != nil { apply(key) }
    }

    // MARK: Ramps

    private func startRamp() {
        guard rampTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rampTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
        rampTick()
    }

    private func rampTick() {
        let now = ProcessInfo.processInfo.systemUptime
        var active = false
        for key in Array(states.keys) {
            guard var s = states[key], let ramp = s.ramp else { continue }
            let t = min(1, max(0, (now - ramp.start) / Self.rampDuration))
            s.brightness = ramp.from + (ramp.to - ramp.from) * t
            if t >= 1 { s.ramp = nil } else { active = true }
            states[key] = s
            apply(key)
        }
        if !active {
            rampTimer?.invalidate()
            rampTimer = nil
        }
    }

    // MARK: Watchdog (PLAN §4.9)

    private func updateWatchdog() {
        let needed = !paused && states.values.contains { $0.written != nil }
        if needed, watchdog == nil {
            let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.watchdogTick() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        } else if !needed {
            watchdog?.invalidate()
            watchdog = nil
        }
    }

    private func watchdogTick() {
        guard !paused, context?.sessionGate.isOpen ?? false else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var needsRestore = false
        for key in Array(states.keys) {
            guard var s = states[key], let expected = s.written, s.ramp == nil else { continue }
            guard let readback = Self.read(s.writtenTo) else { continue }
            switch GammaMath.check(readback: readback, expected: expected) {
            case .ok:
                s.collapses = 0
                states[key] = s
            case .collapsed:
                s.collapses += 1
                states[key] = s
                EventLog.shared.record(.gamma, "Zeroed gamma table detected; re-applying")
                if s.collapses >= 2 { needsRestore = true } else { write(expected, to: s.writtenTo) }
            case .foreign:
                if s.fights.record(at: now) {
                    s.gaveUp = true
                    states[key] = s
                    EventLog.shared.record(.gamma, "Gamma changed by something else 3 times in 60 s; stopping on this display")
                    release(key)
                    states[key] = State(adjustments: s.adjustments, brightness: s.brightness, xdrScale: s.xdrScale,
                                        floor: s.floor, written: nil, writtenTo: 0, collapses: 0, fights: s.fights,
                                        gaveUp: true, ramp: nil)
                    onGiveUp?(key)
                } else {
                    states[key] = s
                    write(expected, to: s.writtenTo)
                }
            }
        }
        if needsRestore {
            // Last good table didn't stick: restore ColorSync and rebuild from fresh baselines.
            reapplyAll(recapture: true)
        }
    }

    // MARK: Redraw nudge (Apple silicon shows gamma changes only after a composite)

    private func nudge(_ id: UInt32) {
        guard HostInfo.current.isAppleSilicon, let screen = NSScreen.screen(for: id) else { return }
        let window: NSWindow
        if let existing = nudgeWindows[id] {
            window = existing
        } else {
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isOpaque = false
            window.sharingType = .none
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.orderFrontRegardless()
            nudgeWindows[id] = window
        }
        nudgeToggle.toggle()
        window.alphaValue = nudgeToggle ? 0.02 : 0.01
    }
}

extension GammaService: SessionParticipant {
    func sessionDidPause() {
        paused = true
        updateWatchdog()
    }

    func sessionDidResume() {
        paused = false
        reapplyAll(recapture: true)
        updateWatchdog()
    }
}
