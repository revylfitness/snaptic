import AppKit
import ApplicationServices

// A few undocumented macOS functions every serious window switcher relies on.
// They're looked up at runtime with dlsym, so if Apple removes one, Snaptic falls
// back to public APIs instead of failing to launch.
//
// The focus technique (_SLPSSetFrontProcessWithOptions + a synthetic
// "make key window" event record) follows the public reverse-engineering
// documented by the yabai project (MIT licensed).

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
// Absolute path on the sealed system volume; a platform binary, so it also
// passes library validation under the hardened runtime.
private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private func lookup<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
    guard let symbol = dlsym(handle ?? rtldDefault, name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

private struct ProcessSerialNumberRaw {
    var high: UInt32 = 0
    var low: UInt32 = 0
}

enum PrivateAPIs {
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias SetFrontFn = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32
    private typealias PostEventFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Int32
    private typealias SetHotKeyFn = @convention(c) (Int32, Bool) -> Int32
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SecureInputFn = @convention(c) () -> UInt8
    private typealias IsHotKeyEnabledFn = @convention(c) (Int32) -> Bool
    private typealias KbdTypeFn = @convention(c) () -> UInt8
    private typealias LayoutTypeFn = @convention(c) (Int16) -> UInt32

    private static let axGetWindow = lookup("_AXUIElementGetWindow", in: nil, as: AXGetWindowFn.self)
    private static let getPSN = lookup("GetProcessForPID", in: nil, as: GetPSNFn.self)
    private static let setFront = lookup("_SLPSSetFrontProcessWithOptions", in: skyLight, as: SetFrontFn.self)
    private static let postEvent = lookup("SLPSPostEventRecordTo", in: skyLight, as: PostEventFn.self)
    private static let setHotKey =
        lookup("SLSSetSymbolicHotKeyEnabled", in: skyLight, as: SetHotKeyFn.self)
        ?? lookup("CGSSetSymbolicHotKeyEnabled", in: nil, as: SetHotKeyFn.self)
    private static let mainConnection =
        lookup("SLSMainConnectionID", in: skyLight, as: MainConnectionFn.self)
        ?? lookup("CGSMainConnectionID", in: nil, as: MainConnectionFn.self)
    private static let copySpaces =
        lookup("SLSCopySpacesForWindows", in: skyLight, as: CopySpacesFn.self)
        ?? lookup("CGSCopySpacesForWindows", in: nil, as: CopySpacesFn.self)
    private static let isHotKeyEnabled =
        lookup("SLSIsSymbolicHotKeyEnabled", in: skyLight, as: IsHotKeyEnabledFn.self)
        ?? lookup("CGSIsSymbolicHotKeyEnabled", in: nil, as: IsHotKeyEnabledFn.self)
    // Public Carbon APIs, loaded dynamically to avoid importing all of Carbon.
    private static let secureInput = lookup("IsSecureEventInputEnabled", in: nil, as: SecureInputFn.self)
    private static let kbdType = lookup("LMGetKbdType", in: nil, as: KbdTypeFn.self)
    private static let layoutType = lookup("KBGetLayoutType", in: nil, as: LayoutTypeFn.self)

    /// True for ISO (European) physical keyboards, where the key above Tab has
    /// a different key code. 'ISO ' is Carbon's kKeyboardISO.
    static var isISOKeyboard: Bool {
        guard let kbdType = Self.kbdType, let layoutType = Self.layoutType else { return false }
        return layoutType(Int16(kbdType())) == 0x4953_4F20
    }

    /// Whether a built-in system shortcut is currently on (nil if unknown).
    static func isSymbolicHotKeyEnabled(_ id: Int32) -> Bool? {
        isHotKeyEnabled?(id)
    }

    /// The CGWindowID behind an AX window element.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = axGetWindow else { return nil }
        var id: CGWindowID = 0
        guard fn(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// Whether a window belongs to any Space. Off-screen windows that belong to
    /// none are things like inactive native tabs and hidden helper windows.
    /// Returns nil when the private call isn't available.
    static func isOnAnySpace(_ windowID: CGWindowID) -> Bool? {
        guard let connection = Self.mainConnection, let copySpaces = Self.copySpaces else { return nil }
        let ids = [NSNumber(value: windowID)] as CFArray
        guard let spaces = copySpaces(connection(), 0x7, ids)?.takeRetainedValue() else { return false }
        return CFArrayGetCount(spaces) > 0
    }

    /// True while some app (a password field, Terminal's Secure Keyboard Entry)
    /// has blocked event taps from seeing key presses.
    static var isSecureInputEnabled: Bool {
        (secureInput?() ?? 0) != 0
    }

    /// Brings one specific window of a process to the front and makes it key,
    /// even though Snaptic itself is a background app. Returns false if the
    /// private functions are unavailable, so callers can fall back.
    @discardableResult
    static func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let getPSN = Self.getPSN, let setFront = Self.setFront, let postEvent = Self.postEvent else {
            return false
        }
        var psn = ProcessSerialNumberRaw()
        return withUnsafeMutablePointer(to: &psn) { psnPointer -> Bool in
            let raw = UnsafeMutableRawPointer(psnPointer)
            guard getPSN(pid, raw) == 0 else { return false }
            // 0x200 = kCPSUserGenerated
            guard setFront(raw, windowID, 0x200) == 0 else { return false }
            guard windowID != 0 else { return true }

            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x3a] = 0x10
            bytes[0x3c] = UInt8(windowID & 0xff)
            bytes[0x3d] = UInt8((windowID >> 8) & 0xff)
            bytes[0x3e] = UInt8((windowID >> 16) & 0xff)
            bytes[0x3f] = UInt8((windowID >> 24) & 0xff)
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            for kind: UInt8 in [0x01, 0x02] {
                bytes[0x08] = kind
                _ = bytes.withUnsafeMutableBytes { buffer in
                    postEvent(raw, buffer.baseAddress!)
                }
            }
            return true
        }
    }

    /// Turns a built-in system shortcut (like ⌘⇥) on or off.
    static func setSymbolicHotKey(_ id: Int32, enabled: Bool) {
        _ = setHotKey?(id, enabled)
    }
}

/// Disables macOS's own ⌘⇥ / ⌘` while a Snaptic shortcut uses them and gives
/// them back afterwards. Which ones Snaptic disabled is saved to disk first, so
/// a crash or force-quit is repaired on the next launch, and shortcuts the
/// user turned off themselves are never touched.
@MainActor
enum SystemHotkeys {
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2
    private static let commandKeyAboveTab: Int32 = 6
    private static let defaultsKey = "SnapticDisabledSystemHotkeys"
    private static let managed: Set<Int32> = [1, 2, 6]

    private static var disabledBySnaptic = Set<Int32>()
    private static var suspended = false

    /// Re-enables anything a previous run disabled but never restored.
    static func recoverFromPreviousRun() {
        let leftover = (UserDefaults.standard.array(forKey: defaultsKey) as? [Int]) ?? []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        // Only ever touch the three shortcuts Snaptic manages, whatever the file says.
        for value in leftover {
            guard let id = Int32(exactly: value), managed.contains(id) else { continue }
            PrivateAPIs.setSymbolicHotKey(id, enabled: true)
        }
    }

    static func apply(_ shortcuts: [Shortcut]) {
        var wanted = Set<Int32>()
        if shortcuts.contains(where: { $0.modifier == .command && $0.keyCode == KeyCode.tab }) {
            wanted.formUnion([commandTab, commandShiftTab])
        }
        if shortcuts.contains(where: { $0.modifier == .command && $0.keyCode == KeyCode.backtick }) {
            wanted.insert(commandKeyAboveTab)
        }
        // A shortcut the user already switched off in System Settings is left
        // alone, so Snaptic never turns it back on later.
        wanted = wanted.filter { disabledBySnaptic.contains($0) || PrivateAPIs.isSymbolicHotKeyEnabled($0) != false }

        // Persist before touching the system so a crash mid-way is recoverable.
        let everDisabled = disabledBySnaptic.union(wanted)
        UserDefaults.standard.set(everDisabled.map { Int($0) }, forKey: defaultsKey)

        for id in disabledBySnaptic.subtracting(wanted) {
            PrivateAPIs.setSymbolicHotKey(id, enabled: true)
        }
        if !suspended {
            for id in wanted {
                PrivateAPIs.setSymbolicHotKey(id, enabled: false)
            }
        }
        disabledBySnaptic = wanted
        UserDefaults.standard.set(wanted.map { Int($0) }, forKey: defaultsKey)
        HotkeyGuard.shared.setDisabled(suspended ? [] : wanted)
    }

    /// Takes the shortcuts back after the hang guard released them.
    static func reassert() {
        guard !suspended else { return }
        for id in disabledBySnaptic {
            PrivateAPIs.setSymbolicHotKey(id, enabled: false)
        }
        HotkeyGuard.shared.setDisabled(disabledBySnaptic)
    }

    /// Hands the shortcuts back to macOS while Snaptic can't see key presses.
    static func setSuspended(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value
        for id in disabledBySnaptic {
            PrivateAPIs.setSymbolicHotKey(id, enabled: value)
        }
        HotkeyGuard.shared.setDisabled(value ? [] : disabledBySnaptic)
    }

    static func restore() {
        guard !disabledBySnaptic.isEmpty else { return }
        for id in disabledBySnaptic {
            PrivateAPIs.setSymbolicHotKey(id, enabled: true)
        }
        disabledBySnaptic = []
        HotkeyGuard.shared.setDisabled([])
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// A thread-safe safety net for ⌘⇥. The main thread checks in regularly; if it
/// stops (a hang), a background timer gives the built-in shortcuts back to
/// macOS so the user is never left without ⌘⇥. Also used from signal handlers.
final class HotkeyGuard: @unchecked Sendable {
    static let shared = HotkeyGuard()

    private let lock = NSLock()
    private var disabled = Set<Int32>()
    private var lastBeat = DispatchTime.now().uptimeNanoseconds
    private var tripped = false
    private var timer: DispatchSourceTimer?

    /// The shortcuts Snaptic currently has switched off.
    func setDisabled(_ ids: Set<Int32>) {
        lock.lock()
        disabled = ids
        lock.unlock()
    }

    /// Called from the main thread. Returns true if the guard had to step in
    /// since the last beat, so the caller can take the shortcuts back over.
    func beat() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        lastBeat = DispatchTime.now().uptimeNanoseconds
        let wasTripped = tripped
        tripped = false
        return wasTripped
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 2, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    private func check() {
        lock.lock()
        let stale = Double(DispatchTime.now().uptimeNanoseconds &- lastBeat) / 1_000_000_000 > 1.5
        let ids = disabled
        let trip = stale && !tripped && !ids.isEmpty
        if trip { tripped = true }
        lock.unlock()
        if trip {
            for id in ids { PrivateAPIs.setSymbolicHotKey(id, enabled: true) }
        }
    }

    /// Gives every shortcut back right away, from any thread.
    func releaseAll() {
        lock.lock()
        let ids = disabled
        disabled = []
        lock.unlock()
        for id in ids { PrivateAPIs.setSymbolicHotKey(id, enabled: true) }
    }
}
