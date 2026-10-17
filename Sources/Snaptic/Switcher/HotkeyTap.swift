import AppKit
import ApplicationServices
import CoreGraphics

/// A global keyboard event tap. It sees every key press system-wide (which is
/// why macOS asks for Accessibility permission) and can swallow the ones that
/// belong to Snaptic so the frontmost app never receives them.
///
/// Restartable: `start()` after `stop()` creates a fresh tap. When macOS disables the tap
/// it is re-enabled only while Snaptic is still trusted; otherwise (or after too many
/// re-enables in a row) it stops itself, off the callout, and reports `onTrustLost`
/// (PLAN §1.1 item 2; revoking access with a live tap can freeze macOS 27.2).
final class HotkeyTap {
    /// Return true to swallow the event.
    var handler: (@MainActor (CGEventType, CGEvent) -> Bool)?
    /// The tap stopped itself because access was revoked or it kept being disabled.
    var onTrustLost: (@MainActor () -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var box: Unmanaged<CallbackTarget<HotkeyTap>>?
    private var reenables: [UInt64] = []

    /// Re-enables allowed within `breakerWindow` before the tap gives up.
    static let breakerLimit = 5
    static let breakerWindow: UInt64 = 10_000_000_000

    var isRunning: Bool { tap != nil }

    /// False if macOS has switched the tap off (for example after
    /// Accessibility access was revoked).
    var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    @MainActor func start() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            // The tap's run loop source lives on the main run loop.
            let box = Unmanaged<CallbackTarget<HotkeyTap>>.fromOpaque(refcon).takeUnretainedValue()
            let swallow: Bool = MainActor.assumeIsolated {
                guard let me = box.target else { return false }
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    me.tapWasDisabled()
                    return false
                }
                return me.handler?(type, event) ?? false
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        let retained = Unmanaged.passRetained(CallbackTarget(self))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            return false   // Accessibility permission not granted (yet).
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        box = retained
        reenables = []
        return true
    }

    /// Idempotent. Disables and invalidates the tap and removes its source.
    @MainActor func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        // Callbacks run on main, like this method, so none is in flight.
        box?.release()
        box = nil
        reenables = []
    }

    @MainActor private func tapWasDisabled() {
        guard let tap else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        reenables = reenables.filter { now &- $0 < Self.breakerWindow }
        reenables.append(now)
        if AXIsProcessTrusted() && reenables.count <= Self.breakerLimit {
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
        // Not from inside the callout: stop on the next main-queue turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stop()
                self.onTrustLost?()
            }
        }
    }
}
