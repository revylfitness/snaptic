import AppKit
import Combine
import SnapticKit
import SnapticShims

/// DDC/CI service (PLAN §7). Nonisolated: one serial queue does all I/O; state the main
/// thread reads is lock-protected. Writes are coalesced per (display, code), rate-limited
/// to 5 per second per display, skipped when equal to the last written value, held while
/// the session, sleep or reconfiguration gates are closed, counted per day, and refused
/// unless the VCP policy (and, for preConfirm codes, a PreConfirmToken) allows them.
final class DDCService: @unchecked Sendable {
    /// Touched only on the main thread.
    weak var context: DisplaysContext?

    enum LinkStatus: Equatable, Sendable {
        case unknown
        case ok
        case failed
    }

    private struct Target: Equatable {
        var hardwareID: UInt32
        var tuning: DDCTransport.Tuning
    }

    private struct Gate {
        var active = false
        var sessionOpen = true
        var asleep = false
        /// Uptime (ns) before which writes wait (wake + 3 s, reconfiguration + 2 s).
        var holdUntil: UInt64 = 0
        /// Uptime of the last wake, for the 15 s backoff window.
        var lastWake: UInt64 = 0
    }

    private struct Slot: Hashable {
        let key: DisplayKey
        let code: UInt8
        let dataAddress: UInt8
    }

    private struct PendingWrite {
        var value: UInt16
        var continuations: [CheckedContinuation<Bool, Never>]
        var enqueuedAt: UInt64
        var retries: Int
    }

    private let queue = DispatchQueue(label: "app.snaptic.ddc", qos: .userInitiated)
    private let lock = NSLock()

    // Lock-protected.
    private var targets: [DisplayKey: Target] = [:]
    private var status: [DisplayKey: LinkStatus] = [:]
    private var caps: [DisplayKey: DDCCapabilities] = [:]
    private var lastValues: [DisplayKey: [UInt8: DDCReading]] = [:]
    private var dailyCounts: [DisplayKey: (day: Int, count: Int)] = [:]
    private var learnedFraming: [DisplayKey: DDCFraming] = [:]
    private var transportNames: [DisplayKey: String] = [:]
    private var gate = Gate()

    // DDC queue only.
    private var transports: [DisplayKey: (hardwareID: UInt32, transport: DDCTransport)] = [:]
    private var pending: [Slot: PendingWrite] = [:]
    private var pendingOrder: [Slot] = []
    private var lastWriteAt: [DisplayKey: UInt64] = [:]
    private var lastWritten: [Slot: UInt16] = [:]
    private var drainScheduled: Set<DisplayKey> = []

    // Main thread only.
    private var sinks: [AnyCancellable] = []
    private var lifetime: Lifetime?
    private var probing: Set<DisplayKey> = []

    /// Called on main when a display's working framing was learned (to persist it).
    var onFramingLearned: (@MainActor (DisplayKey, DDCFraming) -> Void)?
    /// The running DDC controller, for C's settings pages (set in start, cleared in stop).
    @MainActor weak var controller: DDCController?
    /// Observers of link status and value changes (main thread).
    @MainActor private var changeObservers: [(UInt64, @MainActor (DisplayKey) -> Void)] = []
    @MainActor private var observerSerial: UInt64 = 0

    /// Calls `handler` on main whenever a display's link status or values changed, until `lifetime` ends.
    @MainActor func observeChanges(lifetime: Lifetime, _ handler: @escaping @MainActor (DisplayKey) -> Void) {
        guard !lifetime.isEnded else { return }
        observerSerial &+= 1
        let mine = observerSerial
        changeObservers.append((mine, handler))
        lifetime.onEnd { [weak self] in self?.changeObservers.removeAll { $0.0 == mine } }
    }

    @MainActor private func notifyChange(_ key: DisplayKey) {
        for (_, handler) in changeObservers { handler(key) }
    }

    static let interactiveInterval: UInt64 = 200_000_000          // ≤ 5 writes/s per display
    static let wakeHold: UInt64 = 3_000_000_000
    static let wakeBackoffWindow: UInt64 = 15_000_000_000
    static let reconfigureHold: UInt64 = 2_000_000_000
    static let pendingTimeout: UInt64 = 20_000_000_000
    static let capabilitiesTimeout = 2.0

    init() {}

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: Queries (any thread)

    /// True when DDC answered on this display.
    func isAvailable(_ key: DisplayKey) -> Bool {
        locked { gate.active && targets[key] != nil && status[key] == .ok }
    }

    /// True when the display is a DDC candidate (wired external with DDC enabled).
    func isCandidate(_ key: DisplayKey) -> Bool { locked { gate.active && targets[key] != nil } }

    func linkStatus(_ key: DisplayKey) -> LinkStatus { locked { targets[key] == nil ? .failed : (status[key] ?? .unknown) } }

    func cachedCapabilities(_ key: DisplayKey) -> DDCCapabilities? { locked { caps[key] } }

    /// Last value read or written for a code.
    func lastReading(_ vcp: UInt8, of key: DisplayKey) -> DDCReading? { locked { lastValues[key]?[vcp] } }

    /// True when the display reported a brightness (VCP 0x10) reading.
    func supportsBrightness(_ key: DisplayKey) -> Bool { lastReading(VCPPolicy.brightness, of: key) != nil }

    func writesToday(_ key: DisplayKey) -> Int {
        let today = Self.dayIndex()
        return locked { dailyCounts[key].map { $0.day == today ? $0.count : 0 } ?? 0 }
    }

    func transportDescription(_ key: DisplayKey) -> String? { locked { transportNames[key] } }

    func framing(_ key: DisplayKey) -> DDCFraming? { locked { learnedFraming[key] } }

    private static func dayIndex() -> Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }

    // MARK: Reads

    func read(_ vcp: UInt8, from key: DisplayKey) async -> DDCReading? {
        await read(vcp, from: key, dataAddress: DDCPacket.sourceAddress)
    }

    func read(_ vcp: UInt8, from key: DisplayKey, dataAddress: UInt8) async -> DDCReading? {
        // Any code can be read: reads never change the monitor.
        let result: DDCReading? = await withCheckedContinuation { (continuation: CheckedContinuation<DDCReading?, Never>) in
            queue.async { [self] in
                continuation.resume(returning: self.performRead(vcp, key: key, dataAddress: dataAddress))
            }
        }
        if result != nil || linkStatus(key) != .unknown {
            await MainActor.run { [weak self] in self?.notifyChange(key) }
        }
        return result
    }

    /// On the queue.
    private func performRead(_ vcp: UInt8, key: DisplayKey, dataAddress: UInt8) -> DDCReading? {
        let (open, wait) = readGate()
        guard open, wait == 0 else { return nil }
        guard let transport = ensureTransport(key) else { return nil }
        switch transport.read(vcp, dataAddress: dataAddress) {
        case .success(let value):
            let reading = DDCReading(current: value.current, max: value.maximum)
            noteFraming(transport, key: key)
            locked {
                status[key] = .ok
                lastValues[key, default: [:]][vcp] = reading
            }
            return reading
        case .failure(.unsupported):
            noteFraming(transport, key: key)
            locked { status[key] = .ok }
            return nil
        case .failure:
            locked {
                if status[key] != .ok || transport.consecutiveFailures >= 3 { status[key] = .failed }
            }
            return nil
        }
    }

    private func noteFraming(_ transport: DDCTransport, key: DisplayKey) {
        guard let framing = transport.learnedFraming else { return }
        let changed: Bool = locked {
            let old = learnedFraming[key]
            learnedFraming[key] = framing
            return old != framing && targets[key]?.tuning.framing != framing
        }
        if changed {
            DispatchQueue.main.async { [weak self] in self?.onFramingLearned?(key, framing) }
        }
    }

    /// Reads the brightness code to learn whether DDC works on a display.
    @discardableResult
    func probe(_ key: DisplayKey) async -> Bool {
        _ = await read(VCPPolicy.brightness, from: key)
        return isAvailable(key)
    }

    func capabilities(of key: DisplayKey, refresh: Bool) async -> DDCCapabilities? {
        if !refresh, let cached = cachedCapabilities(key) { return cached }
        let result: DDCCapabilities? = await withCheckedContinuation { (continuation: CheckedContinuation<DDCCapabilities?, Never>) in
            queue.async { [self] in
                let (open, wait) = self.readGate()
                guard open, wait == 0, let transport = self.ensureTransport(key) else {
                    continuation.resume(returning: nil)
                    return
                }
                let deadline = DispatchTime.now() + Self.capabilitiesTimeout
                let parsed = transport.readCapabilities(deadline: deadline).flatMap { DDCCapabilities.parse($0) }
                if let parsed { self.locked { self.caps[key] = parsed; self.status[key] = .ok } }
                continuation.resume(returning: parsed)
            }
        }
        await MainActor.run { [weak self] in self?.notifyChange(key) }
        return result
    }

    // MARK: Writes

    /// PreConfirm codes need a token from PreConfirmPresenter.
    func write(_ vcp: UInt8, _ value: UInt16, to key: DisplayKey, interactive: Bool, token: PreConfirmToken?) async -> Bool {
        await write(vcp, value, to: key, interactive: interactive, token: token, dataAddress: DDCPacket.sourceAddress)
    }

    /// `dataAddress` 0x50 is LG's alternate input addressing (VCP 0xF4).
    func write(_ vcp: UInt8, _ value: UInt16, to key: DisplayKey, interactive: Bool, token: PreConfirmToken?,
               dataAddress: UInt8) async -> Bool {
        let refusal = await MainActor.run { [weak self] () -> String? in
            guard let self else { return "stopped" }
            return self.refusalReason(vcp, value, key: key, interactive: interactive, token: token)
        }
        if let refusal {
            EventLog.shared.record(.ddc, "Refused VCP \(VCPPolicy.hex(vcp)) write: \(refusal)")
            return false
        }
        let ok: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                self.enqueue(Slot(key: key, code: vcp, dataAddress: dataAddress), value: value, continuation: continuation)
            }
        }
        await MainActor.run { [weak self] in self?.notifyChange(key) }
        return ok
    }

    /// Writes only when a read-back differs (wake, restore). Never for preConfirm codes.
    func writeIfDifferent(_ vcp: UInt8, _ value: UInt16, to key: DisplayKey) async -> Bool {
        if let current = await read(vcp, from: key), current.current == value { return true }
        return await write(vcp, value, to: key, interactive: false, token: nil)
    }

    /// Main thread: the policy gate (PLAN §7.4, R5.4). Nil means allowed.
    @MainActor private func refusalReason(_ vcp: UInt8, _ value: UInt16, key: DisplayKey, interactive: Bool,
                                          token: PreConfirmToken?) -> String? {
        guard let context else { return "inactive" }
        guard isCandidate(key) else { return "not a DDC display" }
        let perDisplay = context.config.value.perDisplay[key]?.ddc ?? PerDisplayDDC()
        guard perDisplay.enabled else { return "DDC off for this display" }
        let tier = VCPPolicy.tier(code: vcp, value: value, capabilities: cachedCapabilities(key))
        switch tier {
        case .denied:
            return "denied code"
        case .safe:
            break
        case .preConfirm, .unlockable:
            guard interactive else { return "needs the user" }
            if tier == .unlockable, !perDisplay.isUnlocked(vcp) { return "locked code" }
            guard let token, token.authorizes(key, vcp, value) else { return "not confirmed" }
        }
        if !interactive {
            // Safe Mode and the panic latch stop automatic DDC writes (restore, sync); user-initiated ones run.
            if context.safeMode.isActive { return "Safe Mode" }
            if context.panic.isLatched { return "paused after Restore All Displays" }
        }
        return nil
    }

    /// On the queue.
    private func enqueue(_ slot: Slot, value: UInt16, continuation: CheckedContinuation<Bool, Never>) {
        if var existing = pending[slot] {
            existing.value = value
            existing.continuations.append(continuation)
            pending[slot] = existing
        } else {
            pending[slot] = PendingWrite(value: value, continuations: [continuation], enqueuedAt: Self.now(), retries: 0)
            pendingOrder.append(slot)
        }
        scheduleDrain(slot.key, after: 0)
    }

    private func scheduleDrain(_ key: DisplayKey, after nanoseconds: UInt64) {
        guard !drainScheduled.contains(key) else { return }
        drainScheduled.insert(key)
        let work = { [self] in
            self.drainScheduled.remove(key)
            self.drain(key)
        }
        if nanoseconds == 0 {
            queue.async(execute: work)
        } else {
            queue.asyncAfter(deadline: .now() + .nanoseconds(Int(min(nanoseconds, 60_000_000_000))), execute: work)
        }
    }

    private func finish(_ slot: Slot, _ ok: Bool) {
        guard let write = pending.removeValue(forKey: slot) else { return }
        pendingOrder.removeAll { $0 == slot }
        write.continuations.forEach { $0.resume(returning: ok) }
    }

    /// On the queue: performs at most one write for `key`, then reschedules.
    private func drain(_ key: DisplayKey) {
        let now = Self.now()
        let slots = pendingOrder.filter { $0.key == key }
        guard let slot = slots.first, let write = pending[slot] else { return }
        let gateState = writeGate()
        if !gateState.open {
            slots.forEach { finish($0, false) }
            return
        }
        if gateState.wait > 0 {
            if now - write.enqueuedAt > Self.pendingTimeout {
                slots.forEach { finish($0, false) }
                return
            }
            scheduleDrain(key, after: gateState.wait)
            return
        }
        if let last = lastWriteAt[key], now >= last, now - last < Self.interactiveInterval {
            scheduleDrain(key, after: Self.interactiveInterval - (now - last))
            return
        }
        if lastWritten[slot] == write.value {
            finish(slot, true)
        } else if let transport = ensureTransport(key) {
            let ok = transport.write(slot.code, write.value, dataAddress: slot.dataAddress)
            lastWriteAt[key] = Self.now()
            if ok {
                lastWritten[slot] = write.value
                let today = Self.dayIndex()
                locked {
                    status[key] = .ok
                    let current = dailyCounts[key]
                    dailyCounts[key] = (today, (current?.day == today ? current?.count ?? 0 : 0) + 1)
                    let maximum = lastValues[key]?[slot.code]?.max ?? 0
                    lastValues[key, default: [:]][slot.code] = DDCReading(current: write.value, max: maximum)
                }
                finish(slot, true)
            } else if write.retries < 3, locked({ gate.lastWake > 0 && now - gate.lastWake < Self.wakeBackoffWindow }) {
                // Just after wake the link may still be coming up: back off 3 → 6 → 12 s (bounded by 15 s).
                var retry = write
                retry.retries += 1
                pending[slot] = retry
                scheduleDrain(key, after: Self.wakeHold << UInt64(retry.retries - 1))
                return
            } else {
                locked { if transport.consecutiveFailures >= 3 { status[key] = .failed } }
                finish(slot, false)
            }
        } else {
            finish(slot, false)
        }
        if pendingOrder.contains(where: { $0.key == key }) { scheduleDrain(key, after: Self.interactiveInterval) }
    }

    /// (open, wait ns): closed while inactive or the session is resigned.
    private func readGate() -> (Bool, UInt64) {
        locked {
            guard gate.active, gate.sessionOpen, !gate.asleep else { return (false, 0) }
            let now = Self.now()
            return (true, gate.holdUntil > now ? gate.holdUntil - now : 0)
        }
    }

    private func writeGate() -> (open: Bool, wait: UInt64) {
        locked {
            guard gate.active, gate.sessionOpen else { return (false, 0) }
            if gate.asleep { return (true, 500_000_000) }
            let now = Self.now()
            return (true, gate.holdUntil > now ? gate.holdUntil - now : 0)
        }
    }

    /// On the queue: the cached transport, created (or recreated after a replug) on demand.
    private func ensureTransport(_ key: DisplayKey) -> DDCTransport? {
        guard let target = locked({ targets[key] }) else {
            transports[key] = nil
            return nil
        }
        if let existing = transports[key], existing.hardwareID == target.hardwareID {
            existing.transport.update(target.tuning)
            return existing.transport
        }
        transports[key] = nil
        guard let endpoint = try? SNDDC.endpoint(forDisplay: target.hardwareID) else {
            locked { status[key] = .failed }
            return nil
        }
        let transport = DDCTransport(endpoint: endpoint, tuning: target.tuning)
        transports[key] = (target.hardwareID, transport)
        let name = transport.kindDescription
        locked { transportNames[key] = name }
        return transport
    }

    // MARK: Targets and gates (main thread)

    @MainActor private func updateTargets() {
        guard let context else { return }
        let config = context.config.value
        var next: [DisplayKey: Target] = [:]
        for display in context.registry.displays where Self.isDDCCandidate(display) {
            let perDisplay = config.perDisplay[display.key]?.ddc ?? PerDisplayDDC()
            guard perDisplay.enabled else { continue }
            next[display.key] = Target(hardwareID: display.hardwareID, tuning: DDCTransport.Tuning(perDisplay))
        }
        let (added, changedHardware): ([DisplayKey], Bool) = locked {
            let added = next.keys.filter { targets[$0] == nil }
            let changed = next.contains { key, target in targets[key].map { $0.hardwareID != target.hardwareID } ?? false }
                || targets.keys.contains { next[$0] == nil }
            for key in targets.keys where next[key] == nil || next[key]?.hardwareID != targets[key]?.hardwareID {
                status[key] = nil
                caps[key] = nil
                lastValues[key] = nil
                transportNames[key] = nil
            }
            targets = next
            return (added, changed)
        }
        if changedHardware || !added.isEmpty {
            queue.async { [self] in
                // Drop handles for displays that left or were replugged; values may have changed too.
                for (key, entry) in self.transports where self.locked({ self.targets[key]?.hardwareID }) != entry.hardwareID {
                    self.transports[key] = nil
                    self.lastWritten = self.lastWritten.filter { $0.key.key != key }
                }
            }
        }
        for key in added { startProbe(key) }
    }

    @MainActor private func startProbe(_ key: DisplayKey) {
        guard let lifetime, !probing.contains(key) else { return }
        probing.insert(key)
        lifetime.spawn { [weak self] in
            guard let self else { return }
            _ = await self.probe(key)
            self.probing.remove(key)
        }
    }

    /// Wired external displays (DDC runs on the physical display of a Smart HiDPI pair).
    static func isDDCCandidate(_ display: DisplayInfo) -> Bool {
        !display.isBuiltin && display.isOnline && display.transport == .wired
    }

    @MainActor private func holdWrites(for nanoseconds: UInt64, wake: Bool) {
        locked {
            let until = Self.now() + nanoseconds
            gate.holdUntil = max(gate.holdUntil, until)
            if wake { gate.lastWake = Self.now() }
        }
        if wake {
            // A monitor may have reset its values while asleep: re-check before skipping equal writes.
            queue.async { [self] in self.lastWritten = [:] }
        }
    }

    @MainActor private func setAsleep(_ asleep: Bool) {
        locked { gate.asleep = asleep }
    }
}

extension DDCService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .ddc }
    static var privateSymbols: [PrivateSymbol] { [] }

    @MainActor func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        self.lifetime = lifetime
        locked {
            gate = Gate()
            gate.active = true
            gate.sessionOpen = context.sessionGate.isOpen
        }
        context.registerSession(self, lifetime: lifetime)
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.holdWrites(for: DDCService.reconfigureHold, wake: false)
                    self?.updateTargets()
                }
            }
            .store(in: &sinks)
        context.config.$value
            .map { $0.perDisplay.values.mapValues(\.ddc) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateTargets() } }
            .store(in: &sinks)
        // Sleep and wake from B's session gate (one source of truth for session rules, PLAN §4.9).
        context.sessionGate.observeEvents(lifetime: lifetime) { [weak self] event in
            switch event {
            case .willSleep, .screensDidSleep:
                self?.setAsleep(true)
            case .didWake, .screensDidWake:
                self?.setAsleep(false)
                self?.holdWrites(for: DDCService.wakeHold, wake: true)
            default:
                break
            }
        }
        if context.sessionGate.isAsleep || context.sessionGate.screensAsleep { setAsleep(true) }
        if let wake = context.sessionGate.lastWakeUptime {
            // Started shortly after a wake: keep the wake hold and backoff window.
            let elapsed = UInt64(max(0, SessionGate.uptime() - wake) * 1e9)
            if elapsed < DDCService.wakeHold { holdWrites(for: DDCService.wakeHold - elapsed, wake: false) }
        }
        updateTargets()
    }

    @MainActor func deactivate() {
        sinks.removeAll()
        lifetime = nil
        probing.removeAll()
        locked {
            gate.active = false
            targets = [:]
            status = [:]
            caps = [:]
            lastValues = [:]
            transportNames = [:]
        }
        // Bounded: never wait for in-flight I²C on main. Pending writers hear "false".
        queue.async { [self] in
            for slot in self.pendingOrder { self.finish(slot, false) }
            self.pending = [:]
            self.pendingOrder = []
            self.transports = [:]
            self.lastWritten = [:]
            self.lastWriteAt = [:]
        }
        context = nil
    }
}

extension DDCService: SessionParticipant {
    @MainActor func sessionDidPause() { locked { gate.sessionOpen = false } }

    @MainActor func sessionDidResume() {
        locked { gate.sessionOpen = true }
        holdWrites(for: DDCService.wakeHold, wake: true)
    }
}

struct DDCReading: Equatable, Sendable {
    let current: UInt16
    let max: UInt16

    /// current / max, 0…1.
    var fraction: Double { max == 0 ? 0 : min(1, Double(current) / Double(max)) }
}
