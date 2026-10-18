import AppKit
import Combine
import SnapticKit
import SnapticShims

/// One `--virtual-host` helper per Snaptic virtual display (PLAN §9.3, R5.6, R3C §5.1).
/// Each host creates exactly one CGVirtualDisplay; the display lives while the host lives.
@MainActor final class VirtualHostsService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .virtualHosts }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    enum HostError: Error, Equatable {
        case unavailable(String)
        case overBudget
        case tooMany
        case failed(VirtualHostFailure)
        case timeout
        case exited
        case notRunning

        var message: String {
            switch self {
            case .unavailable(let why): return why
            case .overBudget: return L("Not enough graphics memory for another virtual screen")
            case .tooMany: return L("Too many virtual screens")
            case .failed(let f): return f.message
            case .timeout: return L("The virtual screen helper didn't answer")
            case .exited: return L("Virtual display failed to start")
            case .notRunning: return L("The virtual screen isn't running")
            }
        }
    }

    /// Host bookkeeping, touched only on main.
    private final class Host {
        let specID: StableID
        let backing: VirtualBacking
        let bytes: UInt64
        var handle: HelperHandle?
        var displayID: UInt32?
        var exited = false
        var shuttingDown = false
        var pending: [UInt64: CheckedContinuation<VirtualHostReply, Error>] = [:]

        init(specID: StableID, backing: VirtualBacking) {
            self.specID = specID
            self.backing = backing
            bytes = SoCCaps.backingBytes(pixelsWide: backing.pixelsWide, pixelsHigh: backing.pixelsHigh)
        }

        func failAll(_ error: Error) {
            let waiting = pending
            pending = [:]
            waiting.values.forEach { $0.resume(throwing: error) }
        }
    }

    private struct ExitListener { let serial: UInt64; let run: @MainActor (StableID, Bool) -> Void }

    /// 8 user screens plus one per Smart HiDPI display.
    static let maxHosts = VirtualConfig.maxScreens + VirtualConfig.maxPairs
    private var hosts: [StableID: Host] = [:]
    /// Hosts being shut down, until their process exits.
    private var retiring: [StableID: Host] = [:]
    private var nextRequest: UInt64 = 0
    private var listeners: [ExitListener] = []
    private var listenerSerial: UInt64 = 0
    private var lifetime: Lifetime?
    private var failures: [Double] = []
    /// Smart HiDPI: spec → the physical display mirroring it (registry presents one display).
    private var pairPhysical: [StableID: UInt32] = [:]
    /// Headless-recipe screens (weakly visible, §4.1).
    private var headlessSpecs: Set<StableID> = []

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        self.lifetime = lifetime
        context.registry.virtualFacts = { [weak self] in self?.facts() ?? VirtualFacts() }
        context.diagnostics.register(self, section: L("Virtual display hosts"), lifetime: lifetime)
    }

    /// What the registry needs to present pairs and classify headless screens.
    func facts() -> VirtualFacts {
        let live = liveDisplays
        var pairs: [UInt32: UInt32] = [:]
        for (spec, physical) in pairPhysical { if let vid = live[spec] { pairs[vid] = physical } }
        let headless = Set(headlessSpecs.compactMap { live[$0] })
        return VirtualFacts(pairs: pairs, headless: headless)
    }

    /// Smart HiDPI binds (or unbinds, nil) a virtual to its physical display.
    func setPairPhysical(_ specID: StableID, _ physicalID: UInt32?) {
        guard pairPhysical[specID] != physicalID else { return }
        pairPhysical[specID] = physicalID
        context?.registry.refresh()
    }

    func setHeadless(_ specID: StableID, _ on: Bool) {
        if on { headlessSpecs.insert(specID) } else { headlessSpecs.remove(specID) }
    }

    /// Synchronous: every host gets `shutdown` and its stdin closed; stragglers are killed after 1 s.
    func deactivate() {
        context?.registry.virtualFacts = nil
        pairPhysical = [:]
        headlessSpecs = []
        for host in hosts.values { shutdownNow(host) }
        hosts = [:]
        listeners = []
        lifetime = nil
        context = nil
    }

    // MARK: Queries

    /// Live Snaptic virtual displays by spec id.
    var liveDisplays: [StableID: UInt32] {
        var result: [StableID: UInt32] = [:]
        for (id, h) in hosts where !h.exited { if let d = h.displayID { result[id] = d } }
        return result
    }

    var hostCount: Int { hosts.values.filter { !$0.exited }.count }

    /// Physical footprint of each live host process (bytes), for the memory rows (§9.3).
    var hostFootprints: [(specID: StableID, bytes: UInt64)] {
        hosts.values.filter { !$0.exited }.compactMap { h -> (StableID, UInt64)? in
            guard let pid = h.handle?.pid, pid > 0 else { return nil }
            var info = rusage_info_v2()
            let r = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            return r == 0 ? (h.specID, info.ri_phys_footprint) : nil
        }.sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var totalHostFootprint: UInt64 { hostFootprints.reduce(0) { $0 &+ $1.bytes } }

    /// Estimated WindowServer memory of all live hosts' displays.
    var totalBackingBytes: UInt64 { hosts.values.filter { !$0.exited }.reduce(0) { $0 &+ $1.bytes } }

    func isLive(_ specID: StableID) -> Bool { hosts[specID].map { !$0.exited && $0.displayID != nil } ?? false }

    /// Host process of a live virtual display (for GuardDisplayClass).
    func host(for displayID: UInt32) -> (pid: pid_t, startTime: UInt64)? {
        guard let h = hosts.values.first(where: { $0.displayID == displayID && !$0.exited }), let handle = h.handle else { return nil }
        return (handle.pid, handle.startTime)
    }

    func specID(for displayID: UInt32) -> StableID? {
        hosts.values.first { $0.displayID == displayID && !$0.exited }?.specID
    }

    /// Called with (spec id, unexpected) whenever a host process ends.
    func addExitListener(lifetime: Lifetime, _ run: @escaping @MainActor (StableID, Bool) -> Void) {
        guard !lifetime.isEnded else { return }
        listenerSerial &+= 1
        let mine = listenerSerial
        listeners.append(ExitListener(serial: mine, run: run))
        lifetime.onEnd { [weak self] in self?.listeners.removeAll { $0.serial == mine } }
    }

    /// Recent unexpected host failures (3 in 60 s stops recreation, §9.3).
    var recentFailures: Int {
        let now = managementUptime()
        return failures.filter { now - $0 < 60 }.count
    }

    static var isAvailable: Bool { SNVirtualDisplay.isAvailable() }

    // MARK: Create / modes / destroy

    /// Accurate text for a spawn failure (N11): "still starting" is not "restart to update".
    static func spawnFailure(_ error: Error) -> VirtualHostSpawnFailure {
        guard let spawn = error as? HelperSpawnError else { return .launchFailed }
        switch spawn {
        case .unavailable(let reason):
            return reason == HelperSpawner.notReadyMessage ? .helpersStarting : .helpersUnavailable(reason)
        case .verificationFailed(let problem):
            return problem == "identity" ? .appChanged : .checkFailed
        default:
            return .launchFailed
        }
    }

    /// Spawns a host and creates the display with the single `initialMode` (R5.6). Backing is
    /// 2 × the largest mode, or the initial mode only when `limitToInitial`. `serialSeed`:
    /// Smart HiDPI passes the physical display's fingerprint so the identity is stable per panel.
    func create(spec: VirtualScreenSpec, initialMode: VirtualMode, limitToInitial: Bool = false,
                serialSeed: String? = nil) async throws -> UInt32 {
        guard let ctx = context else { throw HostError.notRunning }
        // Right after launch the spawner may still be preparing: wait for it rather than
        // failing with "still starting" (N11).
        if !ctx.helpers.isReady, ctx.helpers.unavailable == nil {
            let ready = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                ctx.helpers.whenPrepared { c.resume(returning: $0) }
            }
            guard context === ctx else { throw HostError.notRunning }
            if !ready { throw HostError.unavailable(VirtualHostSpawnFailure.helpersUnavailable(ctx.helpers.unavailable ?? "").message) }
        }
        if let h = hosts[spec.id], !h.exited, let id = h.displayID { return id }
        if let h = hosts[spec.id], !h.exited { throw HostError.failed(.alreadyCreated) }
        guard Self.isAvailable else { throw HostError.unavailable(L("Virtual displays aren't available on this Mac")) }
        guard hostCount < Self.maxHosts else { throw HostError.tooMany }
        let soc = ManagedHardware.soc
        let clean = spec.sanitized(soc: soc)
        let px = limitToInitial ? clean.fallbackMaxPixels : clean.maxPixels
        let wantsHiDPI = clean.hiDPI && initialMode.hiDPI
        let minWide = wantsHiDPI ? initialMode.width * 2 : initialMode.width
        let minHigh = wantsHiDPI ? initialMode.height * 2 : initialMode.height
        let backing = VirtualBacking(pixelsWide: max(px.wide, minWide), pixelsHigh: max(px.high, minHigh))
        guard SoCCaps.fitsChip(pixelsWide: backing.pixelsWide, pixelsHigh: backing.pixelsHigh, soc: soc) else {
            throw HostError.failed(.invalidRequest)
        }
        let bytes = SoCCaps.backingBytes(pixelsWide: backing.pixelsWide, pixelsHigh: backing.pixelsHigh)
        guard SoCCaps.fitsBudget(existing: totalBackingBytes, additional: bytes, ram: ManagedHardware.ram) else {
            throw HostError.overBudget
        }
        if let reason = VirtualHostProtocol.validate(spec: clean, initialMode: initialMode, backing: backing,
                                                     maxDimension: SoCCaps.maxBackingDimension(soc)) {
            throw HostError.failed(reason)
        }

        let host = Host(specID: spec.id, backing: backing)
        hosts[spec.id] = host
        let specID = spec.id
        let spawned: HelperHandle
        do {
            spawned = try await ctx.helpers.spawn(
                .virtualHost, arguments: ["--protocol", String(VirtualHostProtocol.version)],
                onLine: { [weak self] line in self?.handleLine(specID, line) },
                onExit: { [weak self] status in self?.hostExited(specID, status: status) })
        } catch {
            if hosts[specID] === host { hosts[specID] = nil }
            throw HostError.unavailable(Self.spawnFailure(error).message)
        }
        host.handle = spawned
        // Stopped or destroyed while the suspended child was being verified (off main):
        // retire it so its exit finds this record, not a newer host for the same spec.
        guard context === ctx, hosts[specID] === host, !host.shuttingDown, !spawned.isReaped else {
            host.shuttingDown = true
            if hosts[specID] === host { hosts[specID] = nil }
            if !spawned.isReaped {
                retiring[specID] = host
                spawned.terminate()
            }
            host.failAll(HostError.exited)
            throw HostError.notRunning
        }
        do {
            let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
            let hello = try await request(host, id: 0, .hello(protocolVersion: VirtualHostProtocol.version, build: build))
            guard case .ready(let version) = hello, version == VirtualHostProtocol.version else {
                throw HostError.failed(.protocolMismatch)
            }
            let rid = nextID()
            let reply = try await request(host, id: rid, .create(requestID: rid, spec: clean, initialMode: initialMode,
                                                                 serial: serialSeed.map(VirtualScreenSpec.serial(for:)) ?? clean.serial,
                                                                 backing: backing))
            switch reply {
            case .created(_, let displayID) where displayID != 0:
                host.displayID = displayID
                EventLog.shared.record(.virtualDisplay, "Virtual display created (\(hostCount) hosts)")
                return displayID
            case .failed(_, let reason): throw HostError.failed(reason)
            default: throw HostError.failed(.refused)
            }
        } catch {
            shutdownNow(host)
            hosts[spec.id] = nil
            throw error
        }
    }

    /// Applies additional modes to a live display (Beta). The caller then selects one.
    func setModes(_ modes: [VirtualMode], for specID: StableID) async throws {
        guard let host = hosts[specID], !host.exited, host.displayID != nil else { throw HostError.notRunning }
        if let reason = VirtualHostProtocol.validate(modes: modes, backing: host.backing) { throw HostError.failed(reason) }
        let rid = nextID()
        let reply = try await request(host, id: rid, .setModes(requestID: rid, modes: modes))
        switch reply {
        case .modesSet: return
        case .failed(_, let reason): throw HostError.failed(reason)
        default: throw HostError.failed(.refused)
        }
    }

    /// shutdown → up to 1 s → SIGKILL; no "verify gone" wait (R5.6).
    func destroy(specID: StableID) async {
        guard let host = hosts[specID] else { return }
        hosts[specID] = nil
        host.shuttingDown = true
        retiring[specID] = host
        if !host.exited {
            send(host, .shutdown)
            host.handle?.writer?.close()
            var waited = 0.0
            while !host.exited && waited < VirtualHostProtocol.shutdownGrace {
                try? await Task.sleep(nanoseconds: 50_000_000)
                waited += 0.05
            }
            if !host.exited { host.handle?.terminate() }
        }
        host.failAll(HostError.exited)
        EventLog.shared.record(.virtualDisplay, "Virtual display removed")
    }

    /// Synchronous variant for stop paths: shutdown now, SIGKILL after 1 s if still running.
    func destroyNow(specID: StableID) {
        guard let host = hosts[specID] else { return }
        hosts[specID] = nil
        shutdownNow(host)
    }

    /// Waits until a newly created display is online and the registry lists it.
    func waitUntilOnline(_ displayID: UInt32, timeout: Double = 3) async -> Bool {
        var waited = 0.0
        while waited < timeout {
            if CGDirectDisplayID.online().contains(displayID) {
                context?.registry.refresh()
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
        return false
    }

    // MARK: Private

    private func nextID() -> UInt64 {
        nextRequest &+= 1
        if nextRequest == 0 { nextRequest = 1 }
        return nextRequest
    }

    private func send(_ host: Host, _ message: VirtualHostMessage) {
        guard let data = VirtualHostProtocol.encode(message) else { return }
        host.handle?.writer?.send(data)
    }

    private func request(_ host: Host, id: UInt64, _ message: VirtualHostMessage) async throws -> VirtualHostReply {
        guard !host.exited, host.handle?.writer != nil else { throw HostError.exited }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<VirtualHostReply, Error>) in
            host.pending[id] = cont
            send(host, message)
            DispatchQueue.main.asyncAfter(deadline: .now() + VirtualHostProtocol.replyTimeout) { [weak host] in
                MainActor.assumeIsolated {
                    host?.pending.removeValue(forKey: id)?.resume(throwing: HostError.timeout)
                }
            }
        }
    }

    private func handleLine(_ specID: StableID, _ line: Data) {
        guard let host = hosts[specID], let reply = VirtualHostProtocol.decodeReply(line) else { return }
        switch reply {
        case .ready: host.pending.removeValue(forKey: 0)?.resume(returning: reply)
        case .created(let rid, _), .modesSet(let rid): host.pending.removeValue(forKey: rid)?.resume(returning: reply)
        case .failed(let rid, _):
            if let rid, let cont = host.pending.removeValue(forKey: rid) {
                cont.resume(returning: reply)
            } else {
                host.failAll(HostError.failed(.refused))
            }
        }
    }

    private func hostExited(_ specID: StableID, status: Int32) {
        // Shut-down hosts are in `retiring`; an old record must not hide a newer host.
        let host: Host
        if let r = retiring[specID], r.handle != nil, hosts[specID] == nil || r.shuttingDown {
            retiring[specID] = nil
            host = r
        } else if let h = hosts[specID] {
            hosts[specID] = nil
            host = h
        } else {
            return
        }
        host.exited = true
        host.failAll(HostError.exited)
        let unexpected = !host.shuttingDown
        if unexpected {
            failures.append(managementUptime())
            failures = failures.filter { managementUptime() - $0 < 60 }
            EventLog.shared.record(.virtualDisplay, "Virtual host exited unexpectedly (status \(status))")
        }
        context?.registry.refresh()
        for l in listeners { l.run(specID, unexpected) }
    }

    private func shutdownNow(_ host: Host) {
        host.shuttingDown = true
        guard !host.exited, let handle = host.handle else { return }
        retiring[host.specID] = host
        send(host, .shutdown)
        handle.writer?.close()
        host.failAll(HostError.exited)
        DispatchQueue.main.asyncAfter(deadline: .now() + VirtualHostProtocol.shutdownGrace) { [host] in
            MainActor.assumeIsolated {
                if !host.exited { handle.terminate() }
                if self.retiring[host.specID] === host { self.retiring[host.specID] = nil }
            }
        }
    }
}

extension VirtualHostsService: DiagnosticsContributor {
    func diagnostics() -> [(String, String)] {
        var rows: [(String, String)] = [
            (L("Virtual hosts"), String(hostCount)),
            (L("Estimated virtual display memory"), ByteCountFormatter.string(fromByteCount: Int64(clamping: totalBackingBytes), countStyle: .memory)),
            (L("Virtual displays available"), Self.isAvailable ? L("Yes") : L("No")),
            (L("Recent host failures"), String(recentFailures)),
        ]
        for (i, f) in hostFootprints.enumerated() {
            let pid = hosts[f.specID]?.handle?.pid ?? 0
            rows.append((L("Host \(i + 1) (pid \(pid))"), ByteCountFormatter.string(fromByteCount: Int64(clamping: f.bytes), countStyle: .memory)))
        }
        return rows
    }
}
