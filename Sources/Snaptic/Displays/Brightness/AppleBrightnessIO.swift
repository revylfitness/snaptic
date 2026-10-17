import AppKit
import Combine
import SnapticKit

// DisplayServices brightness for built-in and Apple displays (PLAN §6.1). Private C
// functions are resolved only through PrivateDisplayAPI (kill switches, availability).

extension PrivateSymbol {
    static let dsFramework = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    static let dsGetBrightness = PrivateSymbol(function: "DisplayServicesGetBrightness", framework: dsFramework,
                                               features: [.brightnessApple])
    static let dsSetBrightness = PrivateSymbol(function: "DisplayServicesSetBrightness", framework: dsFramework,
                                               features: [.brightnessApple])
    static let dsCanChangeBrightness = PrivateSymbol(function: "DisplayServicesCanChangeBrightness", framework: dsFramework,
                                                     features: [.brightnessApple])
    static let dsBrightnessChanged = PrivateSymbol(function: "DisplayServicesBrightnessChanged", framework: dsFramework,
                                                   features: [])
    static let dsHasAmbientLight = PrivateSymbol(function: "DisplayServicesHasAmbientLightCompensation",
                                                 framework: dsFramework, features: [.autoBrightness])
    static let dsAmbientLightEnabled = PrivateSymbol(function: "DisplayServicesAmbientLightCompensationEnabled",
                                                     framework: dsFramework, features: [.autoBrightness])
    static let dsEnableAmbientLight = PrivateSymbol(function: "DisplayServicesEnableAmbientLightCompensation",
                                                    framework: dsFramework, features: [.autoBrightness])
}

final class AppleBrightnessIO: @unchecked Sendable {
    /// Touched only on the main thread.
    weak var context: DisplaysContext?

    typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    typealias CanChangeFn = @convention(c) (UInt32) -> Bool
    typealias ChangedFn = @convention(c) (UInt32, Double) -> Void
    typealias HasALCFn = @convention(c) (UInt32) -> Bool
    typealias ALCEnabledFn = @convention(c) (UInt32, UnsafeMutablePointer<Bool>) -> Int32
    typealias EnableALCFn = @convention(c) (UInt32, Bool) -> Int32

    private struct Functions {
        var get: GetFn?
        var set: SetFn?
        var canChange: CanChangeFn?
        var changed: ChangedFn?
        var hasALC: HasALCFn?
        var alcEnabled: ALCEnabledFn?
        var enableALC: EnableALCFn?
    }

    private struct Entry {
        var hardwareID: UInt32
        var supported: Bool?
        var value: Double?
        var autoBrightness: Bool?
    }

    private let queue = DispatchQueue(label: "app.snaptic.displayservices", qos: .userInitiated)
    private let lock = NSLock()
    // Lock-protected.
    private var functions = Functions()
    private var entries: [DisplayKey: Entry] = [:]
    private var active = false
    // Queue only.
    private var pendingSet: [DisplayKey: Double] = [:]
    private var lastSetAt: [DisplayKey: UInt64] = [:]
    private var setScheduled: Set<DisplayKey> = []
    // Main only.
    private var sinks: [AnyCancellable] = []

    /// Called on main when a display's support or value changed.
    var onChange: (@MainActor (DisplayKey) -> Void)?

    /// ≤ 20 Hz per display.
    private static let minInterval: UInt64 = 50_000_000

    init() {}

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: Queries (any thread)

    /// DisplayKey → hardware display (the physical of a Smart HiDPI pair).
    func isSupported(_ key: DisplayKey) -> Bool { locked { active && entries[key]?.supported == true } }

    /// Last known brightness, 0…1 (non-blocking).
    func brightness(of key: DisplayKey) -> Double? { locked { entries[key]?.value } }

    /// True once the probe has finished for this display.
    func isProbed(_ key: DisplayKey) -> Bool { locked { entries[key]?.supported != nil } }

    var hasAutoBrightnessControl: Bool { locked { functions.hasALC != nil && functions.alcEnabled != nil && functions.enableALC != nil } }

    func autoBrightness(of key: DisplayKey) -> Bool? { locked { entries[key]?.autoBrightness } }

    // MARK: Writes

    /// Queues a coalesced write (latest wins, ≤ 20 Hz). Returns false when unsupported.
    @discardableResult
    func setBrightness(_ value: Double, of key: DisplayKey) -> Bool {
        guard isSupported(key), value.isFinite else { return false }
        let v = min(1, max(0, value))
        locked { entries[key]?.value = v }
        queue.async { [self] in
            self.pendingSet[key] = v
            self.scheduleSet(key, after: 0)
        }
        return true
    }

    private func scheduleSet(_ key: DisplayKey, after ns: UInt64) {
        guard !setScheduled.contains(key) else { return }
        setScheduled.insert(key)
        let work = { [self] in
            self.setScheduled.remove(key)
            self.flushSet(key)
        }
        if ns == 0 { queue.async(execute: work) } else { queue.asyncAfter(deadline: .now() + .nanoseconds(Int(ns)), execute: work) }
    }

    private func flushSet(_ key: DisplayKey) {
        guard let value = pendingSet[key] else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastSetAt[key], now >= last, now - last < Self.minInterval {
            scheduleSet(key, after: Self.minInterval - (now - last))
            return
        }
        pendingSet[key] = nil
        let (fn, changed, id) = locked { (functions.set, functions.changed, entries[key]?.hardwareID) }
        guard let fn, let id else { return }
        _ = fn(id, Float(value))
        changed?(id, value)
        lastSetAt[key] = DispatchTime.now().uptimeNanoseconds
    }

    /// Reads the hardware value off main and updates the cache.
    func refresh(_ key: DisplayKey) async -> Double? {
        let value: Double? = await withCheckedContinuation { (c: CheckedContinuation<Double?, Never>) in
            queue.async { [self] in c.resume(returning: self.readNow(key)) }
        }
        return value
    }

    /// On the queue.
    private func readNow(_ key: DisplayKey) -> Double? {
        let (fn, id) = locked { (functions.get, entries[key]?.hardwareID) }
        guard let fn, let id else { return nil }
        var v: Float = -1
        guard fn(id, &v) == 0, v.isFinite, v >= 0 else { return nil }
        let value = Double(min(1, v))
        locked { entries[key]?.value = value }
        return value
    }

    /// Sets, then reads back: false when the display ignored the change (an Apple preset
    /// with fixed brightness, PLAN §6.1). The caller falls back to another method.
    func verifySet(_ value: Double, of key: DisplayKey) async -> Bool {
        guard isSupported(key) else { return false }
        let ok: Bool = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                let (set, get, id) = self.locked { (self.functions.set, self.functions.get, self.entries[key]?.hardwareID) }
                guard let set, let get, let id else { return c.resume(returning: false) }
                let target = Float(min(1, max(0, value)))
                _ = set(id, target)
                usleep(80_000)
                var v: Float = -1
                let readOK = get(id, &v) == 0
                c.resume(returning: readOK && abs(v - target) < 0.03)
            }
        }
        return ok
    }

    @discardableResult
    func setAutoBrightness(_ on: Bool, of key: DisplayKey) -> Bool {
        let (enable, id) = locked { (functions.enableALC, entries[key]?.hardwareID) }
        guard let enable, let id else { return false }
        locked { entries[key]?.autoBrightness = on }
        queue.async { _ = enable(id, on) }
        return true
    }

    // MARK: Probing (main → queue)

    @MainActor private func updateDisplays() {
        guard let context else { return }
        let displays = context.registry.displays.filter { $0.isOnline }
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        var next: [DisplayKey: Entry] = [:]
        var toProbe: [(DisplayKey, UInt32, Bool)] = []
        locked {
            for d in displays {
                // Only physical Apple-capable panels: built-in, or wired (Studio Display, Pro Display XDR, UltraFine).
                guard d.isBuiltin || d.transport == .wired else { continue }
                if var existing = entries[d.key], existing.hardwareID == d.hardwareID {
                    existing.hardwareID = d.hardwareID
                    next[d.key] = existing
                } else {
                    next[d.key] = Entry(hardwareID: d.hardwareID, supported: nil, value: nil, autoBrightness: nil)
                    // Non-Apple HDR displays report DisplayServices success but don't follow it on 15+.
                    let excluded = osMajor >= 15 && !d.isBuiltin && d.hardwareID.vendorNumber != 0x610 && d.hdrEnabled == true
                    toProbe.append((d.key, d.hardwareID, excluded))
                }
            }
            entries = next
        }
        guard !toProbe.isEmpty else { return }
        queue.async { [self] in
            for (key, id, excluded) in toProbe {
                let (get, canChange, hasALC, alcEnabled) = self.locked {
                    (self.functions.get, self.functions.canChange, self.functions.hasALC, self.functions.alcEnabled)
                }
                var supported = false
                var value: Double?
                if !excluded, let get {
                    var v: Float = -1
                    if get(id, &v) == 0, v.isFinite, v >= 0 {
                        supported = canChange?(id) ?? true
                        value = Double(min(1, v))
                    }
                }
                var auto: Bool?
                if supported, let hasALC, let alcEnabled, hasALC(id) {
                    var on = false
                    if alcEnabled(id, &on) == 0 { auto = on }
                }
                self.locked {
                    self.entries[key]?.supported = supported
                    self.entries[key]?.value = value
                    self.entries[key]?.autoBrightness = auto
                }
                DispatchQueue.main.async { [weak self] in self?.onChange?(key) }
            }
        }
    }
}

extension AppleBrightnessIO: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .appleBrightness }
    static var privateSymbols: [PrivateSymbol] {
        [.dsGetBrightness, .dsSetBrightness, .dsCanChangeBrightness, .dsBrightnessChanged, .dsHasAmbientLight,
         .dsAmbientLightEnabled, .dsEnableAmbientLight]
    }

    @MainActor func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        let api = context.privateAPI
        let f = Functions(get: api.function(.dsGetBrightness, as: GetFn.self),
                          set: api.function(.dsSetBrightness, as: SetFn.self),
                          canChange: api.function(.dsCanChangeBrightness, as: CanChangeFn.self),
                          changed: api.function(.dsBrightnessChanged, as: ChangedFn.self),
                          hasALC: api.function(.dsHasAmbientLight, as: HasALCFn.self),
                          alcEnabled: api.function(.dsAmbientLightEnabled, as: ALCEnabledFn.self),
                          enableALC: api.function(.dsEnableAmbientLight, as: EnableALCFn.self))
        locked {
            functions = f
            active = true
            entries = [:]
        }
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateDisplays() } }
            .store(in: &sinks)
        updateDisplays()
    }

    @MainActor func deactivate() {
        sinks.removeAll()
        locked {
            active = false
            entries = [:]
            functions = Functions()
        }
        queue.async { [self] in
            self.pendingSet = [:]
            self.lastSetAt = [:]
        }
        context = nil
    }
}
