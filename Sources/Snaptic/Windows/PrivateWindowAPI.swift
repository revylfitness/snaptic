import AppKit
import ApplicationServices
import os
import SnapticKit
import SnapticShims

// A few undocumented macOS functions every serious window switcher relies on, under PLAN 0.5 §4.12's contract (lead;
// H3, H6; B1b). They're looked up at runtime with dlsym, so if Apple removes one, Snaptic falls back to public APIs
// instead of failing to launch. Kit `WindowSymbolContract` holds the rules (the gate, the image check, the result
// classes, poisoning); this file holds the C names, the lookups, the probes and the calls. The capture symbol is the
// one exception: `SNWindowServer.m` looks it up and calls it, and this file guards it like the rest.
//
// The focus technique (_SLPSSetFrontProcessWithOptions + a synthetic
// "make key window" event record) follows the public reverse-engineering
// documented by the yabai project (MIT licensed).

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
// Absolute path on the sealed system volume; a platform binary, so it also
// passes library validation under the hardened runtime.
private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private struct ProcessSerialNumberRaw {
    var high: UInt32 = 0
    var low: UInt32 = 0
}

enum PrivateWindowAPI {
    // MARK: Symbol table (§4.12; the C names live here only, L2)

    struct Symbol {
        let id: WindowSymbolID
        let name: String
        /// The `CGS…` twin of an `SLS…` name, looked up when the SkyLight name is missing.
        let alias: String?

        /// The selftest name: an alias pair drops its `SLS`/`CGS` prefix and reports the variant found.
        var reportName: String { alias == nil ? name : String(name.dropFirst(3)) }
    }

    /// In `WindowSymbolID.allCases` order.
    static let table: [Symbol] = [
        Symbol(id: .hwCapture, name: "CGSHWCaptureWindowList", alias: nil),
        Symbol(id: .axGetWindow, name: "_AXUIElementGetWindow", alias: nil),
        Symbol(id: .getProcessForPID, name: "GetProcessForPID", alias: nil),
        Symbol(id: .setFrontProcess, name: "_SLPSSetFrontProcessWithOptions", alias: nil),
        Symbol(id: .postEventRecord, name: "SLPSPostEventRecordTo", alias: nil),
        Symbol(id: .mainConnection, name: "SLSMainConnectionID", alias: "CGSMainConnectionID"),
        Symbol(id: .copySpaces, name: "SLSCopySpacesForWindows", alias: "CGSCopySpacesForWindows"),
        Symbol(id: .isSymbolicHotKeyEnabled, name: "SLSIsSymbolicHotKeyEnabled", alias: "CGSIsSymbolicHotKeyEnabled"),
        Symbol(id: .setSymbolicHotKeyEnabled, name: "SLSSetSymbolicHotKeyEnabled",
               alias: "CGSSetSymbolicHotKeyEnabled"),
        Symbol(id: .layoutType, name: "KBGetLayoutType", alias: nil),
        Symbol(id: .kbdType, name: "LMGetKbdType", alias: nil),
    ]

    /// The selftest's check that this table and Kit's agree.
    static func tableProblems() -> [String] {
        var problems: [String] = []
        if table.map(\.id) != WindowSymbolID.allCases { problems.append("window symbol table order differs from Kit") }
        for symbol in table where (symbol.alias != nil) != symbol.id.hasAlias {
            problems.append("window symbol " + symbol.id.rawValue + " alias differs from Kit")
        }
        return problems
    }

    // MARK: Lookup

    private struct Resolved {
        let pointer: UnsafeMutableRawPointer?
        let lookup: WindowSymbolLookup
    }

    private static func imagePath(of pointer: UnsafeMutableRawPointer) -> String? {
        var info = Dl_info()
        guard dladdr(pointer, &info) != 0, let name = info.dli_fname else { return nil }
        return String(cString: name)
    }

    private static func resolve(_ symbol: Symbol) -> Resolved {
        if symbol.id == .hwCapture {
            return Resolved(pointer: nil, lookup: WindowSymbolLookup(present: SNWindowServer.isCapturePresent(),
                                                                     imagePath: SNWindowServer.captureImagePath()))
        }
        let handle = symbol.id.image == .skyLight ? (skyLight ?? rtldDefault) : rtldDefault
        if let pointer = dlsym(handle, symbol.name) {
            return Resolved(pointer: pointer, lookup: WindowSymbolLookup(
                present: true, imagePath: imagePath(of: pointer), variant: symbol.alias == nil ? nil : .sls))
        }
        if let alias = symbol.alias, let pointer = dlsym(rtldDefault, alias) {
            return Resolved(pointer: pointer, lookup: WindowSymbolLookup(
                present: true, imagePath: imagePath(of: pointer), variant: .cgs))
        }
        return Resolved(pointer: nil, lookup: .absent)
    }

    private static let resolved: [WindowSymbolID: Resolved] = {
        var found: [WindowSymbolID: Resolved] = [:]
        for symbol in table { found[symbol.id] = resolve(symbol) }
        return found
    }()

    private static func function<T>(_ id: WindowSymbolID, as type: T.Type) -> T? {
        guard let pointer = resolved[id]?.pointer else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias SetFrontFn = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32
    private typealias PostEventFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Int32
    private typealias SetHotKeyFn = @convention(c) (Int32, Bool) -> Int32
    private typealias MainConnectionFn = @convention(c) () -> Int32
    /// Returns a +1 `CFTypeRef` (Create rule), read as raw so its type is checked before use.
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> UnsafeRawPointer?
    private typealias SecureInputFn = @convention(c) () -> UInt8
    private typealias IsHotKeyEnabledFn = @convention(c) (Int32) -> Bool
    private typealias KbdTypeFn = @convention(c) () -> UInt8
    private typealias LayoutTypeFn = @convention(c) (Int16) -> UInt32

    private static let axGetWindowFn = function(.axGetWindow, as: AXGetWindowFn.self)
    private static let getPSNFn = function(.getProcessForPID, as: GetPSNFn.self)
    private static let setFrontFn = function(.setFrontProcess, as: SetFrontFn.self)
    private static let postEventFn = function(.postEventRecord, as: PostEventFn.self)
    private static let mainConnectionFn = function(.mainConnection, as: MainConnectionFn.self)
    private static let copySpacesFn = function(.copySpaces, as: CopySpacesFn.self)
    private static let isHotKeyEnabledFn = function(.isSymbolicHotKeyEnabled, as: IsHotKeyEnabledFn.self)
    private static let setHotKeyFn = function(.setSymbolicHotKeyEnabled, as: SetHotKeyFn.self)
    private static let layoutTypeFn = function(.layoutType, as: LayoutTypeFn.self)
    private static let kbdTypeFn = function(.kbdType, as: KbdTypeFn.self)
    /// The connection probe compares both variants when both exist.
    private static let cgsMainConnectionFn: MainConnectionFn? = dlsym(rtldDefault, "CGSMainConnectionID")
        .map { unsafeBitCast($0, to: MainConnectionFn.self) }
    // Public Carbon API, loaded dynamically to avoid importing all of Carbon; exempt from the contract (X2-2).
    private static let secureInputFn: SecureInputFn? = dlsym(rtldDefault, "IsSecureEventInputEnabled")
        .map { unsafeBitCast($0, to: SecureInputFn.self) }

    // MARK: Guards (gate, crash guard, poison, kill switches)

    private struct Guards {
        var health: [WindowSymbolID: WindowSymbolHealth] = [:]
        /// Starts empty, so the first read logs every switch that's on.
        var killSwitches: Set<WindowFeature> = []
        /// The crash guard's disabled builds that match this build.
        var disabled: Set<WindowSymbolID> = []
        /// `Windows.verifiedBuild.<symbol>` matches this build.
        var verified: Set<WindowSymbolID> = []
        /// Probes between their start and `finishProbe`.
        var running: Set<WindowSymbolID> = []
        var captureWaiters: [@Sendable (Bool) -> Void] = []
        /// Fixed at launch (§4.13): no private capture, the probe included.
        var safeMode = false
        /// `CGSHWCaptureWindowList` calls this run, the probe and its rechecks included (§4.13, M33).
        var privateCaptures = 0
    }

    private static let guards = OSAllocatedUnfairLock(uncheckedState: initialGuards())
    private static let markerWriteFailedKey = "windows.markerWriteFailed"
    private static let probeQueue = DispatchQueue(label: "snaptic.windows.probe", qos: .utility)
    private static var uptime: Double { ProcessInfo.processInfo.systemUptime }

    private static func initialGuards() -> Guards {
        var g = Guards()
        let defaults = UserDefaults.standard
        for id in WindowSymbolID.allCases {
            g.health[id] = WindowSymbolHealth(id, probedBuild: defaults.string(forKey: CrashGuard.probedKey(id.rawValue)),
                                              currentBuild: InflightMarkers.build)
        }
        (g.disabled, g.verified) = buildSets()
        return g
    }

    private static func buildSets() -> (disabled: Set<WindowSymbolID>, verified: Set<WindowSymbolID>) {
        let build = InflightMarkers.build
        var disabled = Set<WindowSymbolID>(), verified = Set<WindowSymbolID>()
        for id in WindowSymbolID.allCases {
            if InflightMarkers.isDisabled(id.rawValue) { disabled.insert(id) }
            if !build.isEmpty && UserDefaults.standard.string(forKey: CrashGuard.verifiedKey(id.rawValue)) == build {
                verified.insert(id)
            }
        }
        return (disabled, verified)
    }

    /// After launch step 3b and after Try Again: re-reads the disabled and verified builds.
    static func reloadGuards() {
        let sets = buildSets()
        guards.withLockUnchecked { g in
            g.disabled = sets.disabled
            g.verified = sets.verified
        }
    }

    private static func state(_ id: WindowSymbolID, _ g: Guards, honorKillSwitch: Bool = true,
                              includePoison: Bool = true) -> WindowSymbolState {
        let disabled = g.disabled.contains(id) || (honorKillSwitch && g.killSwitches.contains(id.feature))
        return WindowSymbolContract.state(id, lookup: resolved[id]?.lookup ?? .absent, major: InflightMarkers.major,
                                          disabled: disabled,
                                          poisoned: includePoison && (g.health[id]?.poisoned ?? false))
    }

    /// Whether a call would be let through now, without starting a probe: available, not poisoned for the process,
    /// and any poisoning's retry due.
    private static func usable(_ id: WindowSymbolID, _ g: Guards, now: Double) -> Bool {
        guard state(id, g, includePoison: false) == .available, let health = g.health[id], !health.lasting else {
            return false
        }
        if health.poisoned, case .retry(let at) = health.phase { return now >= at }
        return true
    }

    /// Reads `Windows.disable.<feature>` (H6) once per batch: enumeration, a raise, the tap's start, the selftest.
    @discardableResult
    static func readKillSwitches() -> Set<WindowFeature> {
        let domainName = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let now = KillSwitches.read(UserDefaults.standard.persistentDomain(forName: domainName), prefix: "Windows",
                                    as: WindowFeature.self)
        let before = guards.withLockUnchecked { g -> Set<WindowFeature> in
            let before = g.killSwitches
            g.killSwitches = now
            return before
        }
        for feature in WindowFeature.allCases where now.contains(feature) != before.contains(feature) {
            EventLog.shared.record(.safety, "windows.killSwitch." + feature.rawValue
                                   + (now.contains(feature) ? " on" : " off"))
        }
        return now
    }

    // MARK: Admission and results

    private struct Ticket {
        let id: WindowSymbolID
        let marked: Bool
    }

    /// The contract in front of one call: the state (gate, image check, crash guard, kill switch), the probe, then
    /// the marker. Nil is the fallback for this call. `inlineProbe` runs a due synchronous probe (the connection and
    /// the layout) here; callers pass it only from the probe queue. A presence-only probe always runs here.
    private static func admit(_ id: WindowSymbolID, honorKillSwitch: Bool = true,
                              inlineProbe: Bool = false) -> Ticket? {
        let now = uptime
        // A presence-only probe makes no call, so it runs wherever it's due.
        let inlineCapable = id.presenceOnlyProbe || (inlineProbe && (id == .mainConnection || id == .layoutType))
        enum Next { case call, probeHere, probeLater, fallback }
        let next: Next = guards.withLockUnchecked { g in
            guard state(id, g, honorKillSwitch: honorKillSwitch, includePoison: false) == .available else {
                return .fallback
            }
            if inlineCapable, g.health[id]?.phase == .probing, !g.running.contains(id) { return .probeHere }
            switch g.health[id]?.nextUse(now: now) {
            case .call?: return .call
            case .probe?: return inlineCapable ? .probeHere : .probeLater
            default: return .fallback
            }
        }
        switch next {
        case .fallback: return nil
        case .probeLater:
            probeQueue.async { performProbe(id) }
            return nil
        case .probeHere:
            performProbe(id)
            return admit(id, honorKillSwitch: honorKillSwitch)
        case .call: break
        }
        let build = InflightMarkers.build
        let verified = guards.withLockUnchecked { $0.verified.contains(id) }
        let marked = !build.isEmpty && CrashGuard.needsMarker(id, verifiedBuild: verified ? build : nil,
                                                              currentBuild: build)
        if marked && !InflightMarkers.ledger.begin(id.rawValue) {
            EventLog.shared.count(markerWriteFailedKey)
            return nil
        }
        #if DEBUG
        InflightMarkers.trapIfAsked(id.rawValue)
        #endif
        return Ticket(id: id, marked: marked)
    }

    /// Ends a call: the marker, the success count, the poison bookkeeping, and `verifiedBuild` once.
    private static func finish(_ ticket: Ticket, _ result: WindowResultClass) {
        let id = ticket.id
        let succeeded = result != .impossible
        let successes: Int
        if ticket.marked {
            successes = InflightMarkers.ledger.end(id.rawValue, succeeded: succeeded)
        } else {
            successes = succeeded ? InflightMarkers.ledger.noteSuccess(id.rawValue) : 0
        }
        let now = uptime
        let (poisoned, lasting, markVerified) = guards.withLockUnchecked { g -> (Bool, Bool, Bool) in
            let poisoned = g.health[id]?.record(result, now: now) ?? false
            let markVerified = CrashGuard.shouldMarkVerified(id, successes: successes, major: InflightMarkers.major,
                                                             alreadyVerified: g.verified.contains(id))
            if markVerified { g.verified.insert(id) }
            return (poisoned, g.health[id]?.lasting ?? false, markVerified)
        }
        if poisoned {
            EventLog.shared.record(.privateAPI, "windows.poisoned " + id.rawValue)
            // A second poisoning adds a row to the Window Switcher page (§4.17).
            if lasting { postStopsChanged() }
        }
        if markVerified && !InflightMarkers.build.isEmpty {
            UserDefaults.standard.set(InflightMarkers.build, forKey: CrashGuard.verifiedKey(id.rawValue))
        }
    }

    /// A ticket whose call never ran.
    private static func cancel(_ ticket: Ticket) {
        if ticket.marked { InflightMarkers.ledger.end(ticket.id.rawValue, succeeded: false) }
    }

    // MARK: Probes (§4.12 step 4)

    /// Runs on the probe queue, once per due probe.
    private static func performProbe(_ id: WindowSymbolID) {
        let start = guards.withLockUnchecked { g -> Bool in
            guard g.health[id]?.phase == .probing, !g.running.contains(id) else { return false }
            g.running.insert(id)
            return true
        }
        guard start else { return }
        switch id {
        case .axGetWindow:
            withProbeWindow(id) { number in runMarked(id) { probeAX(expected: number) } }
        case .copySpaces:
            withProbeWindow(id) { number in
                guard let connection = connection(inlineProbe: true) else { return .noAnswer }
                return runMarked(id) { probeSpaces(connection: connection, windowNumber: number) }
            }
        case .hwCapture:
            withCaptureWindow { finishProbe(.hwCapture, $0) }
        case .mainConnection:
            finishProbe(id, runMarked(id) { probeConnection() })
        case .layoutType:
            finishProbe(id, runMarked(id) { probeLayout() })
        default:
            finishProbe(id, resolved[id]?.lookup.present == true ? .answer : .noAnswer)
        }
    }

    /// The probe's call under its marker. A failed marker write is no answer (retried in a minute).
    private static func runMarked(_ id: WindowSymbolID, _ body: () -> WindowResultClass) -> WindowResultClass {
        let marked = !InflightMarkers.build.isEmpty
        if marked && !InflightMarkers.ledger.begin(id.rawValue) {
            EventLog.shared.count(markerWriteFailedKey)
            return .noAnswer
        }
        #if DEBUG
        InflightMarkers.trapIfAsked(id.rawValue)
        #endif
        let result = body()
        if marked { InflightMarkers.ledger.end(id.rawValue, succeeded: false) }
        return result
    }

    private static func finishProbe(_ id: WindowSymbolID, _ result: WindowResultClass) {
        let now = uptime
        let (outcome, waiters) = guards.withLockUnchecked { g -> (WindowSymbolHealth.ProbeOutcome?,
                                                                   [@Sendable (Bool) -> Void]) in
            g.running.remove(id)
            let outcome = g.health[id]?.probeFinished(result, now: now)
            guard id == .hwCapture else { return (outcome, []) }
            let waiters = g.captureWaiters
            g.captureWaiters = []
            return (outcome, waiters)
        }
        var passed = false
        switch outcome {
        case .passed?:
            passed = true
            if !id.presenceOnlyProbe && !InflightMarkers.build.isEmpty {
                UserDefaults.standard.set(InflightMarkers.build, forKey: CrashGuard.probedKey(id.rawValue))
            }
        case .poisoned(let lasting)?:
            EventLog.shared.record(.privateAPI, "windows.poisoned " + id.rawValue + (lasting ? " until quit" : ""))
            if lasting { postStopsChanged() }
        default:
            break
        }
        for waiter in waiters { waiter(passed) }
    }

    /// Orders the off-screen probe window in on main, runs `body` on the probe queue, then orders it out.
    private static func withProbeWindow(_ id: WindowSymbolID,
                                        _ body: @escaping @Sendable (UInt32) -> WindowResultClass) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let number = ProbeWindows.acquire()
                probeQueue.async {
                    let result = number > 0 ? body(UInt32(number)) : .noAnswer
                    DispatchQueue.main.async { MainActor.assumeIsolated { ProbeWindows.release() } }
                    finishProbe(id, result)
                }
            }
        }
    }

    /// PC-1: a second 64 × 64 window inside the main screen, never ordered in, drawn with the pattern. `done` gets
    /// the result on the probe queue: the probe's, or a content-check recheck's (A2b).
    private static func withCaptureWindow(_ done: @escaping @Sendable (WindowResultClass) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let made = ProbeWindows.makeCaptureWindow()
                probeQueue.async {
                    var result = WindowResultClass.noAnswer
                    if let made, made.number > 0, let connection = connection(honorKillSwitch: false,
                                                                              inlineProbe: true) {
                        result = runMarked(.hwCapture) {
                            probeCapture(connection: connection, windowNumber: UInt32(made.number), scale: made.scale)
                        }
                    }
                    DispatchQueue.main.async { MainActor.assumeIsolated { ProbeWindows.closeCaptureWindow() } }
                    done(result)
                }
            }
        }
    }

    private static func probeAX(expected: UInt32) -> WindowResultClass {
        guard let axGetWindowFn else { return .noAnswer }
        let app = AXUIElementCreateApplication(getpid())
        // Our own windows, answered by our main thread; the probe queue can wait longer than enumeration does.
        AXUIElementSetMessagingTimeout(app, 1.0)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return .noAnswer }
        var results: [(error: Int32, windowID: UInt32)] = []
        for window in windows {
            var windowID: CGWindowID = 0
            let error = axGetWindowFn(window, &windowID)
            results.append((error: error.rawValue, windowID: windowID))
        }
        return WindowResults.axProbe(results, expected: expected)
    }

    private static func probeSpaces(connection: Int32, windowNumber: UInt32) -> WindowResultClass {
        guard let copySpacesFn else { return .noAnswer }
        let raw = copySpacesFn(connection, 0x7, [NSNumber(value: windowNumber)] as CFArray)
        return WindowResults.copySpaces(numberArrayShape(retained(raw)))
    }

    private static func probeConnection() -> WindowResultClass {
        let variant = resolved[.mainConnection]?.lookup.variant
        let sls = variant == .sls ? mainConnectionFn?() : nil
        let cgs = (variant == .cgs ? mainConnectionFn : cgsMainConnectionFn)?()
        return WindowResults.mainConnectionProbe(sls: sls, cgs: cgs)
    }

    private static func probeLayout() -> WindowResultClass {
        guard let layoutTypeFn, let kbdTypeFn else { return .noAnswer }
        return WindowResults.layout(layoutTypeFn(Int16(kbdTypeFn())))
    }

    private static func probeCapture(connection: Int32, windowNumber: UInt32, scale: Double) -> WindowResultClass {
        guard let object = hwCapture(connection: connection, windowID: windowNumber) else { return .noAnswer }
        let (shape, first) = imageArrayShape(object.value)
        let side = Double(CapturePattern.side)
        let probe = WindowCaptureProbeResult(shape: shape, sample: first.flatMap(patternSample))
        return WindowResults.captureProbe(probe, pixelLimit: WindowResults.pixelLimit(windowWidth: side,
                                                                                       windowHeight: side,
                                                                                       maxScale: scale))
    }

    // MARK: Result shapes

    private static func retained(_ raw: UnsafeRawPointer?) -> CFTypeRef? {
        raw.map { Unmanaged<CFTypeRef>.fromOpaque($0).takeRetainedValue() }
    }

    private static func elements(of object: CFTypeRef) -> [CFTypeRef]? {
        guard CFGetTypeID(object) == CFArrayGetTypeID() else { return nil }
        let array = unsafeBitCast(object, to: CFArray.self)
        var items: [CFTypeRef] = []
        for index in 0..<CFArrayGetCount(array) {
            // A NULL slot counts as a wrong element.
            guard let raw = CFArrayGetValueAtIndex(array, index) else {
                items.append(kCFNull)
                continue
            }
            items.append(Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue())
        }
        return items
    }

    private static func numberArrayShape(_ object: CFTypeRef?) -> WindowArrayShape {
        guard let object else { return .null }
        guard let items = elements(of: object) else { return .notArray }
        if items.isEmpty { return .empty }
        return items.allSatisfy({ CFGetTypeID($0) == CFNumberGetTypeID() }) ? .elements([]) : .wrongElement
    }

    private static func imageArrayShape(_ object: CFTypeRef?) -> (WindowArrayShape, CGImage?) {
        guard let object else { return (.null, nil) }
        guard let items = elements(of: object) else { return (.notArray, nil) }
        if items.isEmpty { return (.empty, nil) }
        var images: [CGImage] = []
        for item in items {
            guard CFGetTypeID(item) == CGImage.typeID else { return (.wrongElement, nil) }
            images.append(unsafeBitCast(item, to: CGImage.self))
        }
        return (.elements(images.map { WindowImageSize(width: $0.width, height: $0.height) }), images.first)
    }

    /// The 16 × 16 greyscale downsample the pattern check compares.
    private static func patternSample(_ image: CGImage) -> [UInt8]? {
        graySample(image, side: CapturePattern.sampleSide, quality: .none)
    }

    /// The content check's 16 × 16 luma (§4.9; X-5), averaged rather than point-sampled, so a sparse page of text
    /// isn't read as one colour. A transparent capture draws as black: flat, so suspect.
    static func lumaSample(_ image: CGImage) -> [UInt8]? {
        graySample(image, side: CaptureContentCheck.sampleSide, quality: .medium)
    }

    private static func graySample(_ image: CGImage, side: Int, quality: CGInterpolationQuality) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = quality
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    // MARK: Window ids, Spaces, raise

    /// The CGWindowID behind an AX window element (`axWindowID`). Nil is the fallback.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        if case .id(let windowID) = lookUpWindowID(of: element) { return windowID }
        return nil
    }

    enum WindowIDLookup {
        case id(CGWindowID)
        /// The call ran and gave no id.
        case noAnswer
        /// The call wasn't made (missing, kill switch, crash guard, poisoning, a probe not yet passed): the caller
        /// matches by title and frame (§4.12, `WindowCatalogRules.matchByTitleAndFrame`).
        case refused
    }

    static func lookUpWindowID(of element: AXUIElement) -> WindowIDLookup {
        guard let axGetWindowFn, let ticket = admit(.axGetWindow) else { return .refused }
        var windowID: CGWindowID = 0
        let error = axGetWindowFn(element, &windowID)
        let result = WindowResults.ax(error: error.rawValue, windowID: windowID)
        finish(ticket, result)
        return result == .answer ? .id(windowID) : .noAnswer
    }

    /// The window server connection; nil is the fallback.
    private static func connection(honorKillSwitch: Bool = true, inlineProbe: Bool = false) -> Int32? {
        guard let mainConnectionFn,
              let ticket = admit(.mainConnection, honorKillSwitch: honorKillSwitch, inlineProbe: inlineProbe) else {
            return nil
        }
        let value = mainConnectionFn()
        let result = WindowResults.mainConnection(value)
        finish(ticket, result)
        return result == .answer ? value : nil
    }

    /// Whether a window belongs to any Space. Off-screen windows that belong to
    /// none are things like inactive native tabs and hidden helper windows.
    /// Returns nil when the private call isn't available (the fallback).
    static func isOnAnySpace(_ windowID: CGWindowID) -> Bool? {
        guard let copySpacesFn, let ticket = admit(.copySpaces) else { return nil }
        guard let connection = connection() else {
            cancel(ticket)
            return nil
        }
        let raw = copySpacesFn(connection, 0x7, [NSNumber(value: windowID)] as CFArray)
        let shape = numberArrayShape(retained(raw))
        finish(ticket, WindowResults.copySpaces(shape))
        switch shape {
        case .elements: return true
        case .null, .empty: return false
        case .notArray, .wrongElement: return nil
        }
    }

    /// Brings one specific window of a process to the front and makes it key,
    /// even though Snaptic itself is a background app. Returns false if the
    /// private functions are unavailable, so callers can fall back.
    @discardableResult
    static func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        readKillSwitches()
        guard let getPSNFn, let setFrontFn, let postEventFn else { return false }
        let now = uptime
        let trio: [WindowSymbolID] = [.getProcessForPID, .setFrontProcess, .postEventRecord]
        // All three first, so a refusal never leaves a raise half done. Safe Mode never calls the trio (§4.13): the
        // caller falls back to activate and kAXRaiseAction.
        guard guards.withLockUnchecked({ g in !g.safeMode && trio.allSatisfy { usable($0, g, now: now) } }) else {
            return false
        }
        var psn = ProcessSerialNumberRaw()
        return withUnsafeMutablePointer(to: &psn) { psnPointer -> Bool in
            let raw = UnsafeMutableRawPointer(psnPointer)
            guard let found = admit(.getProcessForPID) else { return false }
            let psnError = getPSNFn(pid, raw)
            finish(found, WindowResults.raise(error: psnError))
            guard psnError == 0, let front = admit(.setFrontProcess) else { return false }
            // 0x200 = kCPSUserGenerated
            let frontError = setFrontFn(raw, windowID, 0x200)
            finish(front, WindowResults.raise(error: frontError))
            guard frontError == 0 else { return false }
            guard windowID != 0 else { return true }

            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x3a] = 0x10
            bytes[0x3c] = UInt8(windowID & 0xff)
            bytes[0x3d] = UInt8((windowID >> 8) & 0xff)
            bytes[0x3e] = UInt8((windowID >> 16) & 0xff)
            bytes[0x3f] = UInt8((windowID >> 24) & 0xff)
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            guard let post = admit(.postEventRecord) else { return false }
            var postError: Int32 = 0
            for kind: UInt8 in [0x01, 0x02] {
                bytes[0x08] = kind
                let error = bytes.withUnsafeMutableBytes { buffer in
                    postEventFn(raw, buffer.baseAddress!)
                }
                if postError == 0 { postError = error }
            }
            finish(post, WindowResults.raise(error: postError))
            return true
        }
    }

    // MARK: Symbolic hotkeys (⌘⇥)

    /// Whether a built-in system shortcut is currently on (nil if unknown or refused).
    static func isSymbolicHotKeyEnabled(_ id: Int32) -> Bool? {
        guard let isHotKeyEnabledFn, let ticket = admit(.isSymbolicHotKeyEnabled) else { return nil }
        let value = isHotKeyEnabledFn(id)
        finish(ticket, .answer)
        return value
    }

    /// Whether the take may run now (the kill switch, the crash guard, poison and availability of both symbols).
    static func canTakeSymbolicHotKeys() -> Bool {
        let now = uptime
        return guards.withLockUnchecked { g in
            usable(.setSymbolicHotKeyEnabled, g, now: now) && usable(.isSymbolicHotKeyEnabled, g, now: now)
        }
    }

    /// Turns one built-in shortcut off under the full contract, then reads it back (§4.12 step 4). False: not taken,
    /// and macOS keeps it. A read-back that isn't off turns it back on and poisons the take for the process.
    static func takeSymbolicHotKey(_ id: Int32) -> Bool {
        guard let setHotKeyFn, let ticket = admit(.setSymbolicHotKeyEnabled) else { return false }
        let error = setHotKeyFn(id, false)
        let readBack = error == 0 ? isSymbolicHotKeyEnabled(id) : nil
        let result = WindowResults.setSymbolicHotKey(error: error, readBack: readBack, wanted: false)
        finish(ticket, result)
        guard result != .answer else { return true }
        let marked = beginGiveBack()
        giveBackSymbolicHotKey(id)
        endGiveBack(marked)
        if readBack == true {
            guards.withLockUnchecked { g in
                g.health[.setSymbolicHotKeyEnabled]?.poisonForProcess()
                g.health[.isSymbolicHotKeyEnabled]?.poisonForProcess()
            }
            EventLog.shared.record(.privateAPI, "windows.poisoned "
                                   + WindowSymbolID.setSymbolicHotKeyEnabled.rawValue + " until quit")
        }
        return false
    }

    /// The give-back's own marker (X3-2), before its calls. False when the write failed: that's counted, and the
    /// give-back runs anyway (it's what keeps ⌘⇥ working).
    static func beginGiveBack() -> Bool {
        guard !InflightMarkers.build.isEmpty else { return false }
        guard InflightMarkers.ledger.begin(CrashGuard.giveBackMarker) else {
            EventLog.shared.count(markerWriteFailedKey)
            return false
        }
        #if DEBUG
        InflightMarkers.trapIfAsked(CrashGuard.giveBackMarker)
        #endif
        return true
    }

    /// Turns one shortcut back on: exempt from the gate, the image check, poisoning and the kill switch.
    static func giveBackSymbolicHotKey(_ id: Int32) {
        _ = setHotKeyFn?(id, true)
    }

    static func endGiveBack(_ marked: Bool) {
        if marked { InflightMarkers.ledger.end(CrashGuard.giveBackMarker) }
    }

    /// Resolves every pointer before the signal handlers exist, so they never run `dlsym` (D2-11).
    static func prepareForSignals() {
        _ = resolved
        _ = setHotKeyFn
    }

    /// The signal handler's give-back: the pre-resolved pointer, called bare (no marker, no defaults).
    static func giveBackFromSignal(_ id: Int32) {
        _ = setHotKeyFn?(id, true)
    }

    // MARK: Keyboard layout

    /// `KBGetLayoutType` for one keyboard type, on the probe queue (the probe may run inline there). `done` gets nil
    /// for no answer or the fallback.
    static func lookUpLayout(keyboardType: Int64, done: @escaping @Sendable (UInt32?) -> Void) {
        probeQueue.async {
            guard let layoutTypeFn, let ticket = admit(.layoutType, inlineProbe: true) else { return done(nil) }
            let value = layoutTypeFn(Int16(truncatingIfNeeded: keyboardType))
            let result = WindowResults.layout(value)
            finish(ticket, result)
            done(result == .answer ? value : nil)
        }
    }

    /// `LMGetKbdType` (the keyboard type when no key event says it), on the probe queue.
    static func lookUpKeyboardType(done: @escaping @Sendable (Int64?) -> Void) {
        probeQueue.async {
            guard let kbdTypeFn, let ticket = admit(.kbdType) else { return done(nil) }
            let value = kbdTypeFn()
            finish(ticket, .answer)
            done(Int64(value))
        }
    }

    // MARK: Secure input (public; exempt, X2-2)

    /// `on` while some app (a password field, Terminal's Secure Keyboard Entry) has blocked event taps from seeing
    /// key presses; `unknown` when the symbol is missing.
    static var secureInputState: SecureInputState {
        guard let secureInputFn else { return .unknown }
        return secureInputFn() != 0 ? .on : .off
    }

    // MARK: Capture (A2b)

    /// 1x pixels (STEP0-NOTES: 0x200 gives 1x on the built-in display).
    static let captureOptions: UInt32 = 0x200

    /// The stopped rows and diagnostics follow this: a lasting poisoning, and Try Again (§4.17).
    static let stopsChanged = Notification.Name("PrivateWindowAPI.stopsChanged")

    /// The result of one `CGSHWCaptureWindowList` call, NULL included.
    private struct CaptureObject: @unchecked Sendable {
        let value: CFTypeRef?
    }

    /// Every `CGSHWCaptureWindowList` call goes through here: nil in Safe Mode (§4.13; nothing is called, the probe
    /// included), otherwise the call's result, counted.
    private static func hwCapture(connection: Int32, windowID: UInt32) -> CaptureObject? {
        let allowed = guards.withLockUnchecked { g -> Bool in
            guard !g.safeMode else { return false }
            g.privateCaptures += 1
            return true
        }
        guard allowed else { return nil }
        var id = windowID
        let object = SNWindowServer.capture(connection: connection, windowIDs: &id, count: 1, options: captureOptions)
        return CaptureObject(value: object.map { $0 as AnyObject })
    }

    /// Launch step 6 (§4.13): Safe Mode is fixed for the run.
    static func setSafeMode(_ on: Bool) {
        guards.withLockUnchecked { $0.safeMode = on }
    }

    /// Whether the private path may be tried now, without starting a probe: not Safe Mode, and `hwCapture` not
    /// refused by the gate, the crash guard, a kill switch or a poisoning. A due probe still runs at the capture.
    static var capturePathOpen: Bool {
        readKillSwitches()
        let now = uptime
        return guards.withLockUnchecked { g in !g.safeMode && usable(.hwCapture, g, now: now) }
    }

    /// Whether private capture may run, probing first if it's due. `done` runs once, on any thread: true when the
    /// probe passed on this build, false for the fallback. Safe Mode never starts the probe (§4.13).
    static func ensureCaptureProbed(_ done: @escaping @Sendable (Bool) -> Void) {
        readKillSwitches()
        let now = uptime
        enum Next { case ready, wait, start, fallback }
        let next: Next = guards.withLockUnchecked { g in
            guard !g.safeMode, state(.hwCapture, g, includePoison: false) == .available else { return .fallback }
            if g.health[.hwCapture]?.phase == .probing {
                g.captureWaiters.append(done)
                return .wait
            }
            switch g.health[.hwCapture]?.nextUse(now: now) {
            case .call?: return .ready
            case .probe?:
                g.captureWaiters.append(done)
                return .start
            default: return .fallback
            }
        }
        switch next {
        case .ready: done(true)
        case .start: probeQueue.async { performProbe(.hwCapture) }
        case .wait: break
        case .fallback: done(false)
        }
    }

    /// One private capture of one window under the full contract; nil is the fallback. Its connection ignores the
    /// `spaces` kill switch, which turns off the other-Space list only.
    static func capture(_ windowID: CGWindowID, pixelLimit: Double?) -> CGImage? {
        guard !guards.withLockUnchecked({ $0.safeMode }), let ticket = admit(.hwCapture) else { return nil }
        guard let connection = connection(honorKillSwitch: false),
              let object = hwCapture(connection: connection, windowID: windowID) else {
            cancel(ticket)
            return nil
        }
        let (shape, first) = imageArrayShape(object.value)
        let result = WindowResults.capture(shape, pixelLimit: pixelLimit)
        finish(ticket, result)
        return result == .answer ? first : nil
    }

    /// The content check's recheck (§4.9; X2-8, X3-9): the probe-window capture runs again. `done` runs once, on
    /// any thread. A pattern pass is `.patternPass`; an impossible result poisons the symbol (§4.12 step 5) and is
    /// `.failed`. No answer, or a recheck that can't run now (Safe Mode, the path closed, a probe or recheck under
    /// way), is `.noAnswer` and leaves the probe's pass as it is.
    static func recheckCapture(_ done: @escaping @Sendable (CaptureContentCheck.Recheck) -> Void) {
        readKillSwitches()
        let now = uptime
        let start = guards.withLockUnchecked { g -> Bool in
            guard !g.safeMode, usable(.hwCapture, g, now: now), g.health[.hwCapture]?.phase == .passed,
                  !g.running.contains(.hwCapture) else { return false }
            g.running.insert(.hwCapture)
            return true
        }
        guard start else { return done(.noAnswer) }
        withCaptureWindow { result in
            let now = uptime
            let outcome = guards.withLockUnchecked { g -> WindowSymbolHealth.ProbeOutcome? in
                g.running.remove(.hwCapture)
                // Only a failure changes the health: a pass confirms what's there, and no answer isn't a failure.
                return result == .impossible ? g.health[.hwCapture]?.probeFinished(result, now: now) : nil
            }
            if case .poisoned(let lasting)? = outcome {
                EventLog.shared.record(.privateAPI, "windows.poisoned " + WindowSymbolID.hwCapture.rawValue
                                       + (lasting ? " until quit" : ""))
                if lasting { postStopsChanged() }
            }
            switch result {
            case .answer: done(.patternPass)
            case .noAnswer: done(.noAnswer)
            case .impossible: done(.failed)
            }
        }
    }

    private static func postStopsChanged() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: stopsChanged, object: nil) }
    }

    // MARK: Stopped features and diagnostics (§4.17, §4.13)

    /// The features the crash guard stopped on this build, and those poisoned until quit (§4.17's rows).
    static func stoppedFeatures() -> (crashGuard: Set<WindowFeature>, poisoned: Set<WindowFeature>) {
        guards.withLockUnchecked { g in
            var crashGuard = Set<WindowFeature>(), poisoned = Set<WindowFeature>()
            for id in WindowSymbolID.allCases {
                if g.disabled.contains(id) { crashGuard.insert(id.feature) }
                if g.health[id]?.lasting == true { poisoned.insert(id.feature) }
            }
            return (crashGuard, poisoned)
        }
    }

    /// The Diagnostics report's window lines: `hwCapture: <state>`, the private-capture count (M1, M33) and the
    /// `Windows.disable.*` switches that are set.
    static func diagnosticsLines() -> [String] {
        let killSwitches = readKillSwitches()
        let (value, count) = guards.withLockUnchecked { g -> (String, Int) in
            let phase = g.health[.hwCapture]?.phase ?? .needsProbe
            let value = PrivateCaptureDiagnostics.hwCapture(safeMode: g.safeMode, state: state(.hwCapture, g),
                                                            phase: phase)
            return (value, g.privateCaptures)
        }
        return PrivateCaptureDiagnostics.lines(hwCapture: value, privateCaptures: count, killSwitches: killSwitches)
    }

    // MARK: Diagnostics, selftest, Try Again

    /// One report per symbol in table order, from the lookups and guards only (no private call, no AX).
    static func launchReports() -> [WindowSymbolReport] {
        readKillSwitches()
        return guards.withLockUnchecked { g in
            table.map { symbol in
                let lookup = resolved[symbol.id]?.lookup ?? .absent
                return WindowSymbolReport(name: symbol.reportName, state: state(symbol.id, g),
                                          variant: lookup.variant,
                                          imageMoved: WindowSymbolContract.imageMoved(symbol.id, lookup: lookup))
            }
        }
    }

    #if DEBUG
    /// The selftest's poison path: every symbol poisoned for the process, then reported. Nothing after it in the
    /// selftest uses a window symbol.
    static func forcePoisonForSelfTest() -> [WindowSymbolReport] {
        guards.withLockUnchecked { g in
            for id in WindowSymbolID.allCases { g.health[id]?.poisonForProcess() }
        }
        return launchReports()
    }
    #endif

    /// A stopped feature row's Try Again (G3-2): clears that feature's disabled builds and re-reads them.
    static func tryAgain(_ feature: WindowFeature) {
        for key in CrashGuard.tryAgainKeys(feature) { UserDefaults.standard.removeObject(forKey: key) }
        reloadGuards()
        postStopsChanged()
    }
}

// MARK: Probe windows (PLAN 0.5 §4.12 "The probe window"; PC-1)

/// Black, then white stripes where `CapturePattern.isWhite`.
private final class ProbePatternView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        NSColor.white.setFill()
        let stripe = CapturePattern.stripeWidth
        for x in stride(from: 0, to: CapturePattern.side, by: stripe) where CapturePattern.isWhite(column: x) {
            NSRect(x: CGFloat(x), y: 0, width: CGFloat(stripe), height: bounds.height).fill()
        }
    }
}

@MainActor
private enum ProbeWindows {
    private static var spacesWindow: NSWindow?
    private static var holders = 0
    private static var captureWindow: NSWindow?

    private static func borderless(_ frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        return window
    }

    /// The AX and Spaces probes' window: ordered in off screen while a probe holds it. Returns its number.
    static func acquire() -> Int {
        let side = CGFloat(CapturePattern.side)
        let union = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let frame = NSRect(x: union.maxX + 200, y: union.maxY + 200, width: side, height: side)
        let window = spacesWindow ?? borderless(frame)
        if spacesWindow == nil {
            window.collectionBehavior = [.managed, .ignoresCycle]
            window.sharingType = .none
            spacesWindow = window
        }
        holders += 1
        if holders == 1 {
            window.setFrameOrigin(frame.origin)
            window.orderFrontRegardless()
        }
        return window.windowNumber
    }

    static func release() {
        holders = max(0, holders - 1)
        if holders == 0 { spacesWindow?.orderOut(nil) }
    }

    /// The capture probe's window: inside the main screen's visible frame, never ordered in, `.readOnly`.
    static func makeCaptureWindow() -> (number: Int, scale: Double)? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let side = CGFloat(CapturePattern.side)
        let visible = screen.visibleFrame
        let window = captureWindow ?? borderless(NSRect(x: visible.midX - side / 2, y: visible.midY - side / 2,
                                                        width: side, height: side))
        window.sharingType = .readOnly
        window.contentView = ProbePatternView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        window.display()
        captureWindow = window
        let scale = NSScreen.screens.map { Double($0.backingScaleFactor) }.max() ?? 2
        return (window.windowNumber, scale)
    }

    static func closeCaptureWindow() {
        captureWindow?.close()
        captureWindow = nil
    }
}
