import AppKit
import Combine
import CoreImage
import IOKit.ps
import Metal
import QuartzCore
import SnapticKit

/// XDR extra brightness (PLAN §6.4, Beta). Method A multiplies the desktop with an EDR
/// overlay; method B keeps a tiny EDR layer on screen so the panel enters EDR and lets the
/// gamma service write tables above 1. k = min(target, current headroom), polled at 1 Hz.
/// Pauses on serious thermal state, Low Power Mode, low battery, lock, sleep and resign;
/// resumes after the conditions held for 60 s.
@MainActor final class EDRBoost: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .edr }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    enum Method: String, Sendable {
        /// A: EDR overlay multiply.
        case overlay
        /// B: EDR trigger + gamma above 1.
        case gamma
    }

    private struct Boost {
        var target: Double
        var method: Method
        var applied: Double = 1
        var overlay: OverlayToken?
        var trigger: NSWindow?
    }

    private var boosts: [DisplayKey: Boost] = [:]
    private var pollTimer: Timer?
    private(set) var pauseReason: String?
    private var okSince: TimeInterval?
    private var sessionPaused = false
    private var observers: [NSObjectProtocol] = []

    /// A calibration in progress ("Is it brighter?").
    private(set) var calibrating: (key: DisplayKey, method: Method)?
    /// Called after a calibration answer (XDRController re-applies the display).
    var onCalibrated: (@MainActor (DisplayKey) -> Void)?

    // MARK: Method choice and calibration (XDRController, Brightness page)

    /// The method for a display, or nil with the reason it's unavailable.
    func xdrMethod(for key: DisplayKey) -> (Method?, String) {
        guard let context, let display = context.registry.info(for: key) else { return (nil, L("Not connected")) }
        guard display.edrPotential > 1.01 || potential(for: key) > 1.01 else {
            return (nil, L("This display has no extra (EDR) brightness"))
        }
        let per = context.config.value.perDisplay[key]?.brightness ?? PerDisplayBrightness()
        let eff = context.runtime.effectiveFeatures
        let gammaOK = eff.contains(.brightnessGamma) && HostInfo.current.isAppleSilicon
            && !AffectedModels.gammaIsUnreliable(HostInfo.current) && per.xdrGammaWorks != false
            && context.gamma.isAllowed && display.mirrorOf == nil
        let overlayOK = eff.contains(.brightnessOverlay) && per.xdrOverlayWorks != false
        switch context.config.value.brightness.xdrMethod {
        case .gamma:
            return gammaOK ? (.gamma, L("Color table (B)")) : (nil, L("Method B needs the color-table method on Apple silicon"))
        case .overlay:
            return overlayOK ? (.overlay, L("Overlay (A)")) : (nil, L("Method A needs the overlay method"))
        case .automatic:
            if gammaOK { return (.gamma, L("Color table (B)")) }
            if overlayOK { return (.overlay, L("Overlay (A)")) }
            if per.xdrGammaWorks == false && per.xdrOverlayWorks == false {
                return (nil, L("Neither method made this display brighter"))
            }
            return (nil, L("Needs the color-table or overlay brightness method"))
        }
    }


    /// Boosts the display with `method` so the user can judge; answer with `finishCalibration`.
    func beginCalibration(_ key: DisplayKey, method: Method) {
        guard let context else { return }
        calibrating = (key, method)
        let boost = min(1.5, max(1.2, potential(for: key)))
        context.brightness.setXDR(enabled: true, max: boost, method: method, for: key)
        context.brightness.set(boost, for: key, source: .user)
    }

    func finishCalibration(brighter: Bool) {
        guard let context, let pending = calibrating else { return }
        let key = pending.key, method = pending.method
        calibrating = nil
        context.brightness.set(1, for: key, source: .user)
        PerDisplayEdit.update(context, key) { per in
            switch method {
            case .overlay: per.brightness.xdrOverlayWorks = brighter
            case .gamma: per.brightness.xdrGammaWorks = brighter
            }
        }
        EventLog.shared.record(.edr, "XDR calibration: method \(method.rawValue) \(brighter ? "works" : "had no effect")")
        onCalibrated?(key)
    }

    /// Called when XDR pauses or resumes (reason, or nil on resume).
    var onPauseChange: (@MainActor (String?) -> Void)?

    static let resumeAfter: TimeInterval = 60
    static let hardBatteryFloor = 0.2

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        context.registerSession(self, lifetime: lifetime)
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionPaused = true
                self?.evaluate()
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sessionPaused = !(self.context?.sessionGate.isOpen ?? false)
                self.evaluate()
            }
        })
    }

    func deactivate() {
        for key in Array(boosts.keys) { teardown(key) }
        boosts.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        pauseReason = nil
        okSince = nil
        calibrating = nil
        onCalibrated = nil
        context = nil
    }

    // MARK: Queries

    /// Static EDR potential of a display (1 = none).
    func potential(for key: DisplayKey) -> Double {
        guard let screen = screen(for: key) else { return 1 }
        let v = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        return v.isFinite ? max(1, v) : 1
    }

    /// Current headroom (rises while EDR content is on screen).
    func headroom(for key: DisplayKey) -> Double {
        guard let screen = screen(for: key) else { return 1 }
        let v = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        return v.isFinite ? max(1, v) : 1
    }

    /// The largest boost the slider offers: min(user max, potential).
    func maxBoost(for key: DisplayKey) -> Double {
        let p = potential(for: key)
        guard p > 1 else { return 1 }
        guard let config = context?.config.value else { return 1 }
        let user = config.perDisplay[key]?.brightness.xdrMax ?? config.brightness.xdrMaxScale
        return max(1, min(min(user, config.brightness.xdrMaxScale), p))
    }

    func isBoosting(_ key: DisplayKey) -> Bool { (boosts[key]?.applied ?? 1) > 1 }
    func appliedBoost(_ key: DisplayKey) -> Double { boosts[key]?.applied ?? 1 }
    func method(_ key: DisplayKey) -> Method? { boosts[key]?.method }

    // MARK: Control

    func setBoost(_ factor: Double, for key: DisplayKey) {
        setBoost(factor, for: key, method: boosts[key]?.method ?? .overlay)
    }

    func setBoost(_ factor: Double, for key: DisplayKey, method: Method) {
        let target = factor.isFinite ? min(maxBoost(for: key), max(1, factor)) : 1
        if target <= 1.0001 {
            teardown(key)
            boosts[key] = nil
            updatePolling()
            return
        }
        if let existing = boosts[key], existing.method != method { teardown(key) }
        var boost = boosts[key] ?? Boost(target: target, method: method)
        boost.target = target
        boost.method = method
        boosts[key] = boost
        updatePolling()
        evaluate()
    }

    /// Removes every boost (panic, stop).
    func removeAll() {
        for key in Array(boosts.keys) { teardown(key) }
        boosts.removeAll()
        updatePolling()
    }

    // MARK: Internals

    private func screen(for key: DisplayKey) -> NSScreen? {
        guard let info = context?.registry.info(for: key) else { return nil }
        return NSScreen.screen(for: info.mirrorOf ?? info.desktopID)
    }

    private func updatePolling() {
        if boosts.isEmpty {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
        }
    }

    /// Checks the pause conditions and refreshes k on every boosted display.
    private func evaluate() {
        let reason = currentPauseReason()
        let now = ProcessInfo.processInfo.systemUptime
        if let reason {
            okSince = nil
            if pauseReason != reason {
                pauseReason = reason
                for key in Array(boosts.keys) { teardown(key, keepEntry: true) }
                onPauseChange?(reason)
                EventLog.shared.record(.edr, "XDR paused")
            }
            return
        }
        if pauseReason != nil {
            if okSince == nil { okSince = now }
            guard let since = okSince, now - since >= Self.resumeAfter else { return }
            pauseReason = nil
            okSince = nil
            onPauseChange?(nil)
            EventLog.shared.record(.edr, "XDR resumed")
        }
        for key in Array(boosts.keys) { refresh(key) }
    }

    private func currentPauseReason() -> String? {
        if sessionPaused { return L("locked or asleep") }
        let info = ProcessInfo.processInfo
        if info.thermalState == .serious || info.thermalState == .critical { return L("the Mac is hot") }
        let config = context?.config.value.brightness ?? BrightnessConfig()
        if config.xdrPauseOnLowPower, info.isLowPowerModeEnabled { return L("Low Power Mode") }
        if let level = Self.batteryLevelOnBattery(), level < max(Self.hardBatteryFloor, config.xdrBatteryFloor) {
            return L("battery low")
        }
        return nil
    }

    /// Battery fraction while running on battery; nil on AC or without a battery.
    static func batteryLevelOnBattery() -> Double? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue else { continue }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                return Double(current) / Double(max)
            }
        }
        return nil
    }

    private func refresh(_ key: DisplayKey) {
        guard var boost = boosts[key], pauseReason == nil, let screen = screen(for: key) else { return }
        ensureTrigger(&boost, screen: screen)
        let k = max(1, min(boost.target, max(headroom(for: key), 1)))
        switch boost.method {
        case .overlay:
            guard let overlays = context?.overlays else { return }
            if boost.overlay == nil, let id = screen.displayID, let token = overlays.add(.edr, on: id) {
                overlays.setContentView(EDRLayerView(multiply: true), for: token)
                boost.overlay = token
            }
            if let token = boost.overlay, let view = overlays.contentView(for: token) as? EDRLayerView {
                view.value = k
            }
        case .gamma:
            context?.gamma.setXDRScale(k, for: key)
        }
        boost.applied = k
        boosts[key] = boost
        if let r = context?.runtime.runtime(for: key), abs(r.xdrScale - k) > 0.005 { r.xdrScale = k }
    }

    /// A small EDR surface keeps the panel in EDR mode so headroom is available (both methods).
    private func ensureTrigger(_ boost: inout Boost, screen: NSScreen) {
        if let trigger = boost.trigger, trigger.screen == screen { return }
        boost.trigger?.orderOut(nil)
        let frame = NSRect(x: screen.frame.maxX - 2, y: screen.frame.minY, width: 2, height: 2)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = EDRLayerView(multiply: false)
        view.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = view
        view.value = boost.target
        window.alphaValue = 0.02
        window.orderFrontRegardless()
        boost.trigger = window
    }

    private func teardown(_ key: DisplayKey, keepEntry: Bool = false) {
        guard var boost = boosts[key] else { return }
        if let token = boost.overlay { context?.overlays.remove(token) }
        boost.overlay = nil
        boost.trigger?.orderOut(nil)
        boost.trigger?.contentView = nil
        boost.trigger = nil
        if boost.method == .gamma { context?.gamma.setXDRScale(1, for: key) }
        boost.applied = 1
        context?.runtime.runtime(for: key).xdrScale = 1
        if keepEntry { boosts[key] = boost }
    }
}

extension EDRBoost: SessionParticipant {
    func sessionDidPause() {
        sessionPaused = true
        evaluate()
    }

    func sessionDidResume() {
        sessionPaused = false
        evaluate()
    }
}

/// A view whose CAMetalLayer shows one extended-range grey value. With `multiply` it
/// multiplies whatever is below it (XDR method A).
final class EDRLayerView: NSView {
    private let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()

    var value: Double = 1 {
        didSet { if abs(value - oldValue) > 0.001 { render() } }
    }

    init(multiply: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        // A constant color: a tiny drawable stretched over the layer costs almost nothing.
        metalLayer.drawableSize = CGSize(width: 16, height: 16)
        metalLayer.contentsGravity = .resize
        if multiply { metalLayer.compositingFilter = CIFilter(name: "CIMultiplyBlendMode") }
        layer = metalLayer
        render()
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { metalLayer }

    private func render() {
        guard let commandQueue, let drawable = metalLayer.nextDrawable(),
              let buffer = commandQueue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let v = max(0, min(16, value))
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
