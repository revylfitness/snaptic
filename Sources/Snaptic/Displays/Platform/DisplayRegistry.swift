import AppKit
import Combine
import CoreGraphics
import SnapticKit
import SnapticShims

// The live display list (owner: B). PLAN §5: online enumeration with mirror membership,
// CallbackTarget refcon (the same static callback for register and remove), debounce until
// quiet, salted DisplayKeys, presented displays (a Smart HiDPI pair is one DisplayInfo).

/// What D's virtual hosts know (set `DisplayRegistry.virtualFacts`).
struct VirtualFacts: Equatable {
    /// Smart HiDPI pairs: virtual display id → the physical display that mirrors it.
    var pairs: [UInt32: UInt32] = [:]
    /// Snaptic virtuals created by the Headless recipe (weakly visible).
    var headless: Set<UInt32> = []
    init(pairs: [UInt32: UInt32] = [:], headless: Set<UInt32> = []) {
        self.pairs = pairs
        self.headless = headless
    }
}

@MainActor final class DisplayRegistry: DisplayServiceLifecycle, DiagnosticsContributor {
    static var serviceID: DisplayServiceID { .registry }
    static var privateSymbols: [PrivateSymbol] { [.coreDisplayInfo, .cgsIsHDRSupported, .cgsIsHDREnabled] }
    weak var context: DisplaysContext?

    init() {}

    private let subject = CurrentValueSubject<[DisplayInfo], Never>([])
    var displays: [DisplayInfo] { subject.value }
    var changes: AnyPublisher<[DisplayInfo], Never> { subject.eraseToAnyPublisher() }

    /// Fires on every raw reconfiguration callback, before the debounce.
    let reconfigurations = PassthroughSubject<Void, Never>()
    /// True from the first callback until the layout has been quiet for the debounce.
    private(set) var isReconfiguring = false
    private(set) var lastReconfigureUptime: Double = 0

    /// Set by D (VirtualHostsService / SmartHiDPIController).
    var virtualFacts: (@MainActor () -> VirtualFacts)?

    private struct Raw {
        var key: DisplayKey
        var transport: Transport
        var name: String
        var record: FingerprintRecord
    }

    private var raw: [String: Raw] = [:]                     // by session fingerprint
    private var idToFingerprint: [UInt32: String] = [:]
    private var softwareDim: [UInt32: Double] = [:]
    private var overlayDim: [UInt32: Double] = [:]
    private(set) var snapticDisabled: Set<String> = []
    private var refcon: UnsafeMutableRawPointer?
    private var debounce: DispatchWorkItem?
    private var firstEventUptime: Double?
    private var screenObserver: NSObjectProtocol?
    private let reader = LayoutReader()
    private var active = false
    private var lastSnapshot: LayoutSnapshot?
    private var configSink: AnyCancellable?

    // MARK: Lifecycle

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        startObserving()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteReconfigure() }
        }
        context.diagnostics.register(self, section: L("Displays"), lifetime: lifetime)
        rebuild()
        forgetOldDisplays()
        // Custom names come from config: re-present when they change.
        configSink = context.config.$value
            .map { value in value.perDisplay.values.compactMapValues { $0.identity.customName } }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.rebuild() } }
    }

    func deactivate() {
        guard active else { return }
        active = false
        stopObserving()
        configSink = nil
        debounce?.cancel()
        debounce = nil
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
        raw = [:]
        idToFingerprint = [:]
        softwareDim = [:]
        overlayDim = [:]
        isReconfiguring = false
        subject.send([])
        context = nil
    }

    // MARK: Reconfiguration callback (R2C §8 c4)

    private static let reconfigure: CGDisplayReconfigurationCallBack = { _, flags, refcon in
        guard let refcon else { return }
        let box = Unmanaged<CallbackTarget<DisplayRegistry>>.fromOpaque(refcon).takeUnretainedValue()
        let beginOnly = flags.contains(.beginConfigurationFlag)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { box.target?.noteReconfigure(begin: beginOnly) }
        }
    }

    private func startObserving() {
        guard refcon == nil else { return }
        let p = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        if CGDisplayRegisterReconfigurationCallback(Self.reconfigure, p) == .success {
            refcon = p
        } else {
            Unmanaged<CallbackTarget<DisplayRegistry>>.fromOpaque(p).release()
            EventLog.shared.record(.registry, "Could not observe display changes")
        }
    }

    private func stopObserving() {
        guard let p = refcon else { return }
        CGDisplayRemoveReconfigurationCallback(Self.reconfigure, p)
        Unmanaged<CallbackTarget<DisplayRegistry>>.fromOpaque(p).release()
        refcon = nil
    }

    private func noteReconfigure(begin: Bool = false) {
        guard active else { return }
        let now = SessionGate.uptime()
        lastReconfigureUptime = now
        isReconfiguring = true
        if firstEventUptime == nil { firstEventUptime = now }
        reconfigurations.send()
        // Debounce: 0.3 s of quiet, at most 2 s after the first event of a burst.
        let elapsed = now - (firstEventUptime ?? now)
        let delay = begin ? 0.6 : max(0.05, min(0.3, 2 - elapsed))
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.debounce = nil
                self.firstEventUptime = nil
                self.isReconfiguring = false
                self.rebuild()
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Seconds since the last reconfiguration callback.
    func quietSeconds() -> Double { SessionGate.uptime() - lastReconfigureUptime }

    /// Redetect: re-enumerate and re-query identity now.
    func refresh() {
        raw = [:]
        rebuild()
    }

    // MARK: Reports from other services

    /// C's gamma and overlay services report their dimming (1 = none) so visibility and
    /// long-arm checks see it. Nil clears a layer.
    func reportDim(desktopID: UInt32, software: Double?, overlay: Double?) {
        if let software { softwareDim[desktopID] = min(max(software, 0), 1) } else { softwareDim[desktopID] = nil }
        if let overlay { overlayDim[desktopID] = min(max(overlay, 0), 1) } else { overlayDim[desktopID] = nil }
        context?.transactions.layoutFactsChanged()
    }

    /// The transaction queue marks displays Snaptic disabled (by session fingerprint).
    func setDisabledBySnaptic(_ fingerprint: String, _ disabled: Bool) {
        if disabled { snapticDisabled.insert(fingerprint) } else { snapticDisabled.remove(fingerprint) }
    }

    // MARK: Queries

    func info(for key: DisplayKey) -> DisplayInfo? { displays.first { $0.key == key } }
    func info(desktopID: UInt32) -> DisplayInfo? { displays.first { $0.desktopID == desktopID } }
    func info(hardwareID: UInt32) -> DisplayInfo? { displays.first { $0.hardwareID == hardwareID } }

    /// The salted key of a raw display id (also Snaptic virtuals inside a pair).
    func key(forDisplayID id: UInt32) -> DisplayKey? { idToFingerprint[id].flatMap { raw[$0]?.key } }

    /// The raw id currently carrying `key` (the physical one for a pair).
    func displayID(for key: DisplayKey) -> UInt32? {
        idToFingerprint.first { raw[$0.value]?.key == key }?.key
    }

    func sessionFingerprint(of id: UInt32) -> String? { idToFingerprint[id] }

    /// A fresh layout read (not the cached list), with every fact Snaptic knows overlaid.
    func snapshot() -> LayoutSnapshot? {
        guard active else { return nil }
        let s = reader.read(overlay())
        lastSnapshot = s
        return s
    }

    /// The most recent snapshot without re-reading (cheap; may be stale).
    func cachedSnapshot() -> LayoutSnapshot? { lastSnapshot ?? snapshot() }

    private func overlay() -> LayoutReader.Overlay {
        var o = LayoutReader.Overlay()
        let facts = virtualFacts?() ?? VirtualFacts()
        let live = Set(context?.virtualHosts.liveDisplays.values.map { $0 } ?? [])
        for id in CGDirectDisplayID.online() {
            var t = idToFingerprint[id].flatMap { raw[$0]?.transport } ?? LayoutReader.baseTransport(id)
            if id.vendorNumber == LayoutReader.snapticVendor && (live.contains(id) || facts.pairs[id] != nil) {
                t = .snapticVirtual
            } else if t == .snapticVirtual {
                t = .foreignVirtual                      // a 0xD354 display that isn't ours anymore
            }
            o.transports[id] = t
            if let hdr = hdrEnabled(id) { o.hdrEnabled[id] = hdr }
            if context?.privateAPI.monitorPanelSupports("underscan") == true, let u = SNMonitorPanel.underscan(display: id) {
                o.underscan[id] = u.doubleValue
            }
        }
        o.softwareDim = softwareDim
        o.overlayDim = overlayDim
        o.headless = facts.headless
        o.disabledBySnaptic = snapticDisabled
        return o
    }

    private typealias BoolFn = @convention(c) (UInt32) -> UInt8

    private func hdrSupported(_ id: UInt32) -> Bool? {
        guard let fn = context?.privateAPI.function(.cgsIsHDRSupported, as: BoolFn.self) else { return nil }
        return fn(id) != 0
    }

    private func hdrEnabled(_ id: UInt32) -> Bool? {
        guard hdrSupported(id) == true, let fn = context?.privateAPI.function(.cgsIsHDREnabled, as: BoolFn.self) else { return nil }
        return fn(id) != 0
    }

    // MARK: Rebuild

    private func rebuild() {
        guard active, let ctx = context else { return }
        let online = CGDirectDisplayID.online()
        let salt = DisplayIdentity.salt()
        let infoFn = ctx.privateAPI.function(.coreDisplayInfo, as: IORegistryDisplays.InfoDictionaryFn.self)
        var stored: [DisplayKey: FingerprintRecord] = [:]
        for (k, v) in ctx.config.value.perDisplay.values where !v.identity.fingerprint.isEmpty { stored[k] = v.identity.fingerprint }
        var taken: Set<DisplayKey> = []
        var newMap: [UInt32: String] = [:]
        var nextRaw: [String: Raw] = [:]
        for id in online {
            let fp = LayoutReader.fingerprint(id)
            newMap[id] = fp
            if let known = raw[fp], !taken.contains(known.key) {
                nextRaw[fp] = known
                taken.insert(known.key)
                continue
            }
            let io = IORegistryDisplays.facts(for: id, coreDisplayInfo: infoFn)
            let facts = DisplayIdentityFacts(
                edidHash: io.edid.map(DisplayIdentity.edidHash) ?? io.edidUUID.map(DisplayIdentity.unsaltedHash),
                alphanumericSerial: io.alphanumericSerial ?? io.edid.flatMap { EDIDInfo.parse($0)?.serialString },
                uuid: LayoutReader.uuid(id), vendor: id.vendorNumber, model: id.modelNumber, serial: id.serialNumber,
                location: io.location, isBuiltin: id.isBuiltin)
            let record = DisplayIdentity.record(for: facts, salt: salt)
            guard let key = DisplayIdentity.key(for: record, stored: stored, taken: taken) else { continue }
            taken.insert(key)
            let edidName = io.edid.flatMap { EDIDInfo.parse($0)?.name }
            let name = io.productName ?? edidName.flatMap(PerDisplayIdentity.cleanName) ?? ""
            nextRaw[fp] = Raw(key: key, transport: transport(for: id, io: io), name: name, record: record)
        }
        raw = nextRaw
        idToFingerprint = newMap
        let presented = present(snapshot() ?? LayoutSnapshot(entries: [], mainID: 0), config: ctx.config.value)
        rememberIdentities(presented)
        if presented != subject.value {
            EventLog.shared.record(.registry, "\(presented.count) displays")
            subject.send(presented)
        }
        ctx.transactions.layoutFactsChanged()
    }

    private func transport(for id: UInt32, io: IORegistryDisplayFacts) -> Transport {
        if id.isBuiltin { return .builtin }
        if io.isAirPlay { return .airplay }
        if id.vendorNumber == LayoutReader.snapticVendor { return .snapticVirtual }
        if io.isVirtualDevice || id.modelNumber == LayoutReader.virtualModel {
            let n = (io.productName ?? "").lowercased()
            return n.contains("sidecar") || n.contains("ipad") ? .sidecar : .foreignVirtual
        }
        if io.looksLikeDisplayLink { return .displayLink }
        return .wired
    }

    /// Presented displays: a Smart HiDPI pair collapses into its physical display's entry.
    private func present(_ s: LayoutSnapshot, config: DisplaysConfig) -> [DisplayInfo] {
        let facts = virtualFacts?() ?? VirtualFacts()
        let vis = Invariants.visibility(s)
        let physicalOfPair = Dictionary(facts.pairs.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        var out: [DisplayInfo] = []
        for e in s.entries {
            if facts.pairs[e.id] != nil, s.entry(facts.pairs[e.id]!) != nil { continue }   // shown via its physical
            guard let fp = idToFingerprint[e.id], let r = raw[fp] else { continue }
            let desktop: LayoutEntry = physicalOfPair[e.id].flatMap { s.entry($0) } ?? e
            let isPair = desktop.id != e.id
            let screen = NSScreen.screen(for: desktop.id)
            let custom = config.perDisplay[r.key]?.identity.customName
            let name = custom ?? (r.name.isEmpty ? (screen?.localizedName ?? defaultName(e)) : r.name)
            let size = CGDisplayScreenSize(e.id)
            let visibility = isPair ? max(vis[e.id] ?? Visibility.none, vis[desktop.id] ?? Visibility.none) : (vis[e.id] ?? Visibility.none)
            out.append(DisplayInfo(
                key: r.key, desktopID: desktop.id, hardwareID: e.id, transport: r.transport, name: name,
                isBuiltin: e.transport == .builtin, isOnline: e.isOnline, isActive: desktop.isActive || (isPair && e.isEnabled),
                isMain: s.mainID == desktop.id, mirrorOf: isPair ? nil : e.mirrorOf,
                bounds: CGDisplayBounds(desktop.id), rotation: desktop.rotation,
                currentMode: DisplayModes.current(desktop.id), hdrSupported: hdrSupported(e.id), hdrEnabled: e.hdrEnabled,
                notchInset: Double(screen?.safeAreaInsets.top ?? 0),
                physicalSizeMM: CGSize(width: size.width, height: size.height),
                edrPotential: Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1),
                isSmartHiDPIPair: isPair, isStronglyVisible: visibility == .strong, isWeaklyVisible: visibility == .weak))
        }
        return out.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            return a.bounds.minX != b.bounds.minX ? a.bounds.minX < b.bounds.minX : a.bounds.minY < b.bounds.minY
        }
    }

    private func defaultName(_ e: LayoutEntry) -> String {
        switch e.transport {
        case .builtin: return L("Built-in Display")
        case .snapticVirtual: return L("Virtual Screen")
        case .airplay: return L("AirPlay Display")
        case .sidecar: return L("Sidecar")
        default: return L("Display")
        }
    }

    /// Stores salted fingerprints, the last-known name and the day last seen; writes only on change.
    private func rememberIdentities(_ presented: [DisplayInfo]) {
        guard let ctx = context else { return }
        let today = PerDisplayIdentity.day(Date().timeIntervalSince1970)
        var value = ctx.config.value
        var changed = false
        for info in presented {
            guard let fp = idToFingerprint[info.hardwareID], let r = raw[fp] else { continue }
            var per = value.perDisplay[info.key] ?? PerDisplayConfig()
            var identity = per.identity
            var merged = identity.fingerprint
            for tier in FingerprintTier.allCases where r.record[tier] != nil { merged[tier] = r.record[tier] }
            identity.fingerprint = merged
            identity.lastSeen = today
            if !r.name.isEmpty { identity.lastKnownName = PerDisplayIdentity.cleanName(r.name) }
            if identity != per.identity {
                per.identity = identity
                value.perDisplay[info.key] = per
                changed = true
            }
        }
        if changed { ctx.config.value = value }
    }

    /// Forgets offline displays not seen for `forgetAfterDays` (once per activation).
    private func forgetOldDisplays() {
        guard let ctx = context else { return }
        let identities = ctx.config.value.perDisplay.values.mapValues(\.identity)
        let online = Set(displays.map(\.key))
        let forget = ctx.config.value.identity.keysToForget(identities, online: online, now: Date().timeIntervalSince1970)
        guard !forget.isEmpty else { return }
        var value = ctx.config.value
        for k in forget { value.perDisplay[k] = nil }
        ctx.config.value = value
        EventLog.shared.record(.registry, "Forgot \(forget.count) displays not seen recently")
    }

    /// "Forget" from the Display Names page (keeps nothing about the display).
    func forget(_ key: DisplayKey) {
        guard let ctx = context, info(for: key) == nil else { return }
        ctx.config.value.perDisplay[key] = nil
    }

    // MARK: Diagnostics (masked: transport and short key prefix only)

    func diagnostics() -> [(String, String)] {
        var rows: [(String, String)] = [("Displays", "\(displays.count)"), ("Reconfiguring", isReconfiguring ? "yes" : "no")]
        for (i, d) in displays.enumerated() {
            let vis = d.isStronglyVisible ? "strong" : (d.isWeaklyVisible ? "weak" : "none")
            let mode = d.currentMode.map { "\($0.sizeLabel)\($0.isHiDPI ? " HiDPI" : "") \(Int($0.refreshHz.rounded())) Hz" } ?? "?"
            rows.append(("Display \(i + 1)", "\(d.transport.rawValue), key \(d.key.rawValue.prefix(6))…, \(vis), \(mode)"
                + (d.isSmartHiDPIPair ? ", Smart HiDPI" : "") + (d.isMain ? ", main" : "")))
        }
        return rows
    }
}
