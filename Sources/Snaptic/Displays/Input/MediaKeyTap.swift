import AppKit
import ApplicationServices
import SnapticKit

/// The NX_SYSDEFINED event tap for brightness, volume and mute keys (PLAN §8.1, R3C §5.4).
///
/// Nonisolated: it runs on its own thread with the generation pattern. `start()` bumps the
/// generation and spawns a new thread; the thread runs its run loop in 0.25 s slices and
/// tears the tap down once its generation is stale, so `stop()` never waits. The
/// callback decides once per press (on the initial key-down) and gives repeats the same
/// verdict; key-ups always pass and orphan repeats are ignored (macOS 27 Control Center
/// fights otherwise). The decision reads only the lock-protected policy closure.
final class MediaKeyTap: @unchecked Sendable {
    typealias Policy = @Sendable (MediaKeyService.Key, UInt64) -> Bool
    typealias Delivery = @Sendable (MediaKeyService.Key, UInt64, Bool) -> Void

    /// One tap thread's state; retained by the thread for its whole life.
    fileprivate final class Session: @unchecked Sendable {
        let generation: UInt64
        weak var owner: MediaKeyTap?
        /// Tap thread only.
        var port: CFMachPort?
        /// Tap thread only: verdict for the press in progress, per key.
        var verdicts: [MediaKeyService.Key: Bool] = [:]
        /// Tap thread only: re-enable times for the circuit breaker.
        var reenables: [TimeInterval] = []

        init(generation: UInt64, owner: MediaKeyTap) {
            self.generation = generation
            self.owner = owner
        }

        var isCurrent: Bool { owner?.currentGeneration() == generation }
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var policy: Policy?
    private var delivery: Delivery?
    private var trustLost: (@Sendable () -> Void)?
    private var running = false

    init() {}

    fileprivate func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func snapshot() -> (Policy?, Delivery?) {
        lock.lock()
        defer { lock.unlock() }
        return (policy, delivery)
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// Starts (or restarts) the tap. `policy` runs on the tap thread; `delivery` is called on
    /// the tap thread for swallowed presses and must hop to main itself.
    func start(policy: @escaping Policy, delivery: @escaping Delivery, trustLost: @escaping @Sendable () -> Void) {
        lock.lock()
        generation &+= 1
        let gen = generation
        self.policy = policy
        self.delivery = delivery
        self.trustLost = trustLost
        running = true
        lock.unlock()
        let session = Session(generation: gen, owner: self)
        let thread = Thread {
            let ref = Unmanaged.passRetained(session).toOpaque()
            defer { Unmanaged<Session>.fromOpaque(ref).release() }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: CGEventMask(1) << 14, callback: mediaKeyTapCallback,
                                              userInfo: ref) else {
                EventLog.shared.record(.keys, "Media key tap could not be created")
                session.owner?.markStopped(generation: gen)
                return
            }
            session.port = tap
            guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                CFMachPortInvalidate(tap)
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            while session.isCurrent {
                _ = CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
            session.port = nil
        }
        thread.name = "Snaptic media keys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// The old thread exits within 0.25 s; its callback passes events through meanwhile.
    func stop() {
        lock.lock()
        generation &+= 1
        running = false
        policy = nil
        delivery = nil
        trustLost = nil
        lock.unlock()
    }

    fileprivate func markStopped(generation gen: UInt64) {
        lock.lock()
        if generation == gen { running = false }
        lock.unlock()
    }

    /// Self-stop from the callout (trust lost / breaker): bump the generation, defer the rest.
    fileprivate func selfStop(generation gen: UInt64) {
        lock.lock()
        guard generation == gen else {
            lock.unlock()
            return
        }
        generation &+= 1
        running = false
        let lost = trustLost
        lock.unlock()
        DispatchQueue.main.async { lost?() }
    }

    fileprivate static func key(for code: Int) -> MediaKeyService.Key? {
        switch code {
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 2: return .brightnessUp
        case 3: return .brightnessDown
        case 7: return .mute
        default: return nil
        }
    }

    /// Tap thread. Returns true to swallow.
    fileprivate func handle(_ event: CGEvent, session: Session) -> Bool {
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return false }
        let data1 = ns.data1
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        let isRepeat = data1 & 0x1 != 0
        guard let key = Self.key(for: code) else { return false }
        if state != 0xA {
            // Key-up (0xB) always passes, and ends the press.
            session.verdicts[key] = nil
            return false
        }
        let (policy, delivery) = snapshot()
        guard let policy, let delivery else { return false }
        let flags = event.flags.rawValue
        if isRepeat {
            guard let verdict = session.verdicts[key] else { return false }   // orphan repeat: ignore
            if verdict { delivery(key, flags, true) }
            return verdict
        }
        let verdict = policy(key, flags)
        session.verdicts[key] = verdict
        if verdict { delivery(key, flags, false) }
        return verdict
    }

    fileprivate func handleDisabled(session: Session) {
        guard session.isCurrent, let port = session.port else { return }
        let now = ProcessInfo.processInfo.systemUptime
        session.reenables = session.reenables.filter { now - $0 < 10 }
        session.reenables.append(now)
        if AXIsProcessTrusted() && session.reenables.count <= 5 {
            CGEvent.tapEnable(tap: port, enable: true)
        } else {
            // Never invalidate the port inside its own callout: the thread does that when stale.
            EventLog.shared.record(.keys, "Media key tap stopped (permission or repeated timeouts)")
            selfStop(generation: session.generation)
        }
    }
}

private let mediaKeyTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<MediaKeyTap.Session>.fromOpaque(refcon).takeUnretainedValue()
    guard let owner = session.owner else { return Unmanaged.passUnretained(event) }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        owner.handleDisabled(session: session)
        return Unmanaged.passUnretained(event)
    }
    // A stale generation passes everything through until its thread exits.
    guard type.rawValue == 14, session.isCurrent else { return Unmanaged.passUnretained(event) }
    return owner.handle(event, session: session) ? nil : Unmanaged.passUnretained(event)
}
