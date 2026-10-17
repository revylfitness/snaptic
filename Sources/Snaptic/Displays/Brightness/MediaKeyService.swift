import AppKit
import ApplicationServices
import Combine
import SnapticKit

/// Owns the media-key tap (PLAN §8.1). KeysController sets the swallow policy and the key
/// handler, then calls `start()`; the tap needs Accessibility ("Device Control and Data
/// Access" on 27), requested through PermissionFlow.
@MainActor final class MediaKeyService: DisplayServiceLifecycle {
    static var serviceID: DisplayServiceID { .mediaKeys }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?

    enum Key: Sendable, Hashable { case brightnessUp, brightnessDown, volumeUp, volumeDown, mute }

    /// What the tap does with a press (decided once, on the initial key-down).
    enum Verdict: Sendable, Equatable {
        /// macOS handles it; Snaptic doesn't act.
        case pass
        /// Snaptic acts and swallows it.
        case handle
        /// Snaptic acts and macOS also handles it ("also let macOS handle it").
        case handleAndPass
    }

    /// Decides on the tap thread (key, modifier flags, pointer location in CG global
    /// coordinates); must read only lock-protected snapshot state (never hop to main).
    /// Set by KeysController.
    var swallowPolicy: (@Sendable (Key, UInt64, CGPoint) -> Verdict)?
    /// Swallowed keys are delivered here, on main (modifier flags raw value).
    var onKey: (@MainActor (Key, UInt64) -> Void)?
    /// Swallowed key repeats (same verdict as their press).
    var onRepeat: (@MainActor (Key, UInt64) -> Void)?
    /// The tap stopped because Accessibility was revoked or it kept timing out.
    var onTrustLost: (@MainActor () -> Void)?

    private let tap = MediaKeyTap()
    private var lifetime: Lifetime?

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        self.context = context
        self.lifetime = lifetime
    }

    func deactivate() {
        stop()
        swallowPolicy = nil
        onKey = nil
        onRepeat = nil
        onTrustLost = nil
        lifetime = nil
        context = nil
    }

    var isRunning: Bool { tap.isRunning }

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Starts the tap if trusted; otherwise asks PermissionFlow and returns false.
    @discardableResult
    func start() -> Bool {
        guard let context, let lifetime, let policy = swallowPolicy else { return false }
        guard AXIsProcessTrusted() else {
            context.permissions.request(.accessibility,
                                        reason: L("Brightness and volume keys for your displays"), lifetime: lifetime)
            return false
        }
        let box = WeakMediaKeyService(self)
        tap.start(policy: policy, delivery: { key, flags, isRepeat in
            DispatchQueue.main.async {
                guard let service = box.service else { return }
                if isRepeat { service.onRepeat?(key, flags) } else { service.onKey?(key, flags) }
            }
        }, trustLost: {
            DispatchQueue.main.async { box.service?.trustLost() }
        })
        EventLog.shared.record(.keys, "Media key tap started")
        return true
    }

    func stop() {
        guard tap.isRunning else { return }
        tap.stop()
        EventLog.shared.record(.keys, "Media key tap stopped")
    }

    private func trustLost() {
        if let context, let lifetime {
            context.permissions.request(.accessibility,
                                        reason: L("Brightness and volume keys for your displays"), lifetime: lifetime)
        }
        onTrustLost?()
    }
}

/// A weak reference the tap thread can carry to main.
private final class WeakMediaKeyService: @unchecked Sendable {
    /// Read only on main.
    weak var service: MediaKeyService?
    init(_ service: MediaKeyService) { self.service = service }
}
