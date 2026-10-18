import AppKit
import Combine
import Darwin
import SnapticKit
import SystemConfiguration

// Local network identity and throughput (owner: J; PLAN 0.3 §2.7, §2.8): read-only, no sockets, no TCC.
// Identity: SCDynamicStore notifications for the IPv4/IPv6 global and per-interface keys (main queue) cause a re-read
// of the interface addresses (getifaddrs), the VPN state, and the router hash (the global IPv4 router's MAC from the
// ARP table via sysctl NET_RT_FLAGS, hashed with Awake's salt at once; HW-11). Throughput: a 5 s `.common` timer only
// while an enabled rule uses network activity or a task-sampling request lives: sysctl NET_RT_IFLIST2 with 64-bit
// if_data64 counters → NetworkMath.throughputKBps (loopback excluded, tunnels not double-counted).

@MainActor final class NetworkMonitor: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.network, .networkActivity] }
    static let throughputSeconds: TimeInterval = 5

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private var store: SCDynamicStore?
    private var refcon: UnsafeMutableRawPointer?
    private let timer = SourceTimer()
    private let taskRequests = NeedCounter()
    private var configSink: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var ruleNeedsThroughput = false
    private var lastCounters: (counters: [InterfaceCounters], at: Double)?

    /// nil until the first read and while inactive.
    private(set) var identity: NetworkFacts?
    /// KB/s over the last 5 s; nil while not sampling or before two samples.
    private(set) var throughputKBps: Double?
    /// The current router's salted hash, for "Connected to this network" in the rule editor.
    var currentRouterHash: String? { identity?.routerHashes.first }

    init() {}

    /// Throughput sampling while `lifetime` lives (SessionController, for an untilIdle session).
    func requestTaskSampling(_ lifetime: Lifetime) { taskRequests.add(lifetime) }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        startStore()
        taskRequests.onChange = { [weak self] in self?.updateThroughputTimer() }
        configSink = context.config.$value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.configChanged(value) }
            }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
        configChanged(context.config.value)
        readIdentity()
    }

    func deactivate() {
        guard active else { return }
        active = false
        stopStore()
        timer.cancel()
        taskRequests.onChange = nil
        configSink = nil
        if let token = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        wakeObserver = nil
        ruleNeedsThroughput = false
        lastCounters = nil
        identity = nil
        throughputKBps = nil
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active else { return }
        facts.network = identity
        facts.throughputKBps = throughputKBps
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Identity

    private func startStore() {
        guard store == nil else { return }
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        var context = SCDynamicStoreContext(version: 0, info: box, retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let box = Unmanaged<CallbackTarget<NetworkMonitor>>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.readIdentity() } }
        }
        guard let created = SCDynamicStoreCreate(nil, "Snaptic Awake" as CFString, callback, &context) else {
            Unmanaged<CallbackTarget<NetworkMonitor>>.fromOpaque(box).release()
            return
        }
        let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] as CFArray
        let patterns = ["State:/Network/Interface/.*/IPv4", "State:/Network/Interface/.*/IPv6",
                        "State:/Network/Interface/.*/Link"] as CFArray
        guard SCDynamicStoreSetNotificationKeys(created, keys, patterns),
              SCDynamicStoreSetDispatchQueue(created, DispatchQueue.main) else {
            Unmanaged<CallbackTarget<NetworkMonitor>>.fromOpaque(box).release()
            return
        }
        store = created
        refcon = box
    }

    private func stopStore() {
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        store = nil
        if let box = refcon { Unmanaged<CallbackTarget<NetworkMonitor>>.fromOpaque(box).release() }
        refcon = nil
    }

    private func readIdentity() {
        guard active else { return }
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let primary = global?["PrimaryInterface"] as? String
        let router = global?["Router"] as? String
        let entries = Self.interfaceAddresses()
        let addresses = entries.compactMap { entry -> String? in
            guard !NetworkMath.isLoopback(entry.interface) else { return nil }
            return entry.address
        }
        var hashes = Set<String>()
        if let router, let ip = NetworkMath.parseAddress(router), ip.count == 4,
           let mac = Self.arpMAC(for: ip), let hash = AwakeIdentity.routerHash(mac: mac) {
            hashes.insert(hash)
        }
        let new = NetworkFacts(addresses: addresses.sorted(), routerHashes: hashes,
                               vpn: NetworkMath.vpnConnected(addresses: entries, primaryInterface: primary))
        guard new != identity else { return }
        identity = new
        changes.fire()
    }

    /// (interface, numeric address) for every up interface with an IPv4 or IPv6 address.
    private nonisolated static func interfaceAddresses() -> [(interface: String, address: String)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var out: [(interface: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, let sa = entry.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            out.append((String(cString: entry.pointee.ifa_name), text(host)))
        }
        return out
    }

    /// The link-layer address the ARP table holds for `ip` (sysctl NET_RT_FLAGS / RTF_LLINFO), as "aa:bb:…".
    /// Parsed by offsets: rt_msghdr is 92 bytes, then the destination sockaddr_inarp and the gateway sockaddr_dl,
    /// each rounded up to 4 bytes.
    private nonisolated static func arpMAC(for ip: [UInt8]) -> String? {
        let rtfLLInfo: Int32 = 0x400
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, rtfLLInfo]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0, length < 16 << 20 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        let headerSize = 92
        let rtaDst: Int32 = 0x1, rtaGateway: Int32 = 0x2
        func roundUp(_ n: Int) -> Int { n > 0 ? 1 + ((n - 1) | 3) : 4 }
        return buffer.withUnsafeBytes { raw -> String? in
            var offset = 0
            let end = min(length, raw.count)
            while offset + headerSize <= end {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength >= headerSize, offset + messageLength <= end else { return nil }
                defer { offset += messageLength }
                let addrs = raw.loadUnaligned(fromByteOffset: offset + 12, as: Int32.self)
                guard addrs & rtaDst != 0, addrs & rtaGateway != 0 else { continue }
                var cursor = offset + headerSize
                let messageEnd = offset + messageLength
                // Destination: sockaddr_in(arp) — sa_len, sa_family, port (2), address (4).
                guard cursor + 8 <= messageEnd else { continue }
                let dstLength = Int(raw[cursor])
                guard Int32(raw[cursor + 1]) == AF_INET,
                      Array(raw[(cursor + 4)..<(cursor + 8)]) == ip else { continue }
                cursor += roundUp(dstLength)
                // Gateway: sockaddr_dl — sdl_len, sdl_family, sdl_index (2), sdl_type, sdl_nlen, sdl_alen, sdl_slen,
                // then sdl_data (name, then the link-layer address).
                guard cursor + 8 <= messageEnd, Int32(raw[cursor + 1]) == AF_LINK else { continue }
                let nameLength = Int(raw[cursor + 5])
                let addressLength = Int(raw[cursor + 6])
                let start = cursor + 8 + nameLength
                guard addressLength == 6, start + 6 <= messageEnd else { continue }
                if let mac = NetworkMath.macString(Array(raw[start..<(start + 6)])) { return mac }
            }
            return nil
        }
    }

    // MARK: Throughput

    private func configChanged(_ config: AwakeConfig) {
        let needs = AwakeFeatureGraph.rawState(.triggers, in: config.rawFeatures)
            && TriggerEngine.requiredKinds(config.triggers.triggers).contains(.networkActivity)
        guard needs != ruleNeedsThroughput else { return }
        ruleNeedsThroughput = needs
        updateThroughputTimer()
    }

    private func updateThroughputTimer() {
        guard active else { return }
        if ruleNeedsThroughput || taskRequests.isNeeded {
            guard !timer.isRunning else { return }
            lastCounters = nil
            timer.start(every: Self.throughputSeconds, tolerance: 0.5) { [weak self] in self?.sampleThroughput() }
            sampleThroughput()
        } else {
            timer.cancel()
            lastCounters = nil
            if throughputKBps != nil {
                throughputKBps = nil
                changes.fire()
            }
        }
    }

    private func didWake() {
        lastCounters = nil
        throughputKBps = nil
        readIdentity()
        if active { changes.fire() }
    }

    private func sampleThroughput() {
        guard active else { return }
        let now = AwakeSourceClock.now()
        let counters = Self.interfaceCounters()
        if let last = lastCounters, let counters {
            throughputKBps = NetworkMath.throughputKBps(prev: last.counters, now: counters, seconds: now - last.at)
        } else {
            throughputKBps = nil
        }
        if let counters { lastCounters = (counters: counters, at: now) } else { lastCounters = nil }
        changes.fire()
    }

    /// 64-bit byte counters per interface (sysctl NET_RT_IFLIST2, RTM_IFINFO2 messages carry if_data64).
    private nonisolated static func interfaceCounters() -> [InterfaceCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0, length < 16 << 20 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        let headerSize = MemoryLayout<if_msghdr2>.size
        let rtmIfInfo2: UInt8 = 0x12   // RTM_IFINFO2 (net/route.h)
        return buffer.withUnsafeBytes { raw -> [InterfaceCounters] in
            var out: [InterfaceCounters] = []
            var offset = 0
            let end = min(length, raw.count)
            while offset + 4 <= end {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength > 0, offset + messageLength <= end else { break }
                defer { offset += messageLength }
                guard raw[offset + 3] == rtmIfInfo2, messageLength >= headerSize else { continue }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                guard if_indextoname(UInt32(message.ifm_index), &name) != nil else { continue }
                out.append(InterfaceCounters(name: text(name), bytesIn: message.ifm_data.ifi_ibytes,
                                             bytesOut: message.ifm_data.ifi_obytes))
            }
            return out
        }
    }
}

/// A NUL-terminated C buffer as UTF-8 text (lossy).
private func text(_ chars: [CChar]) -> String {
    String(decoding: chars.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
