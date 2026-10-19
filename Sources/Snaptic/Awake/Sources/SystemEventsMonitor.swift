import AppKit
import CoreGraphics
import IOKit
import SnapticKit

// Session, sleep, screensaver, clock and lid events (owner: J; PLAN 0.3 §2.8, §2.12, security M2/L4). Not a criterion
// source of its own (no kinds) but multicast like one (code M7). Notifications are hints, never truth: the lock and
// screensaver names are distributed notifications any process can post, so they only cause a re-read;
// `sessionFacts()` reads the session dictionary at the moment of use. Every observer runs on the main queue.

/// Read synchronously from CGSessionCopyCurrentDictionary() (security M2).
struct SessionFacts: Equatable, Sendable {
    var locked: Bool
    var onConsole: Bool
}

/// What happened, for consumers that react to a kind of event (a wake settles before triggers re-run; a clock or
/// time-zone change re-evaluates schedules and `pausedUntil`).
enum SystemEvent: Equatable, Sendable {
    case willSleep, didWake, screensDidSleep, screensDidWake
    case sessionResigned, sessionBecameActive
    /// Distributed hints; re-read `sessionFacts()` / `screensaverRunning`.
    case lockHint, unlockHint, screensaverStarted, screensaverStopped
    case clockChanged, timeZoneChanged, dayChanged
    case lowPowerModeChanged, thermalChanged
    /// AppleClamshellState / AppleClamshellCausesSleep changed.
    case lidChanged
}

@MainActor final class SystemEventsMonitor: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [] }
    /// A `didstart` hint only suppresses (fail-safe) and expires after this long (security L4).
    static let screensaverHintSeconds: Double = 10
    static let screensaverBundleID = "com.apple.ScreenSaver.Engine"

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private let events = EventFanout<SystemEvent>()
    private var active = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var screensaverHintAt: Double?

    /// Between willSleep and didWake.
    private(set) var isSleeping = false
    /// Continuous instant of the last didWake (nil before the first one in this activation).
    private(set) var lastWake: Double?
    private(set) var lastEvent: SystemEvent?
    /// nil = no lid (desktop Mac) or unreadable.
    private(set) var lidClosed: Bool?
    /// "Closing the lid will sleep": nil = no lid.
    private(set) var lidWillSleep: Bool?

    private var rootDomain: io_service_t = 0
    private var lidPort: IONotificationPortRef?
    private var lidNotification: io_object_t = 0
    private var lidRefcon: UnsafeMutableRawPointer?

    init() {}

    // MARK: On-demand reads

    /// The session dictionary at the moment of use. Unreadable → locked and off console (nothing acts). The
    /// "CGSSessionScreenIsLocked" key (undocumented, HW-1) is present only while locked.
    func sessionFacts() -> SessionFacts {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return SessionFacts(locked: true, onConsole: false)
        }
        let onConsole = (dict[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue ?? false
        let locked = (dict["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
        return SessionFacts(locked: locked, onConsole: onConsole)
    }

    /// ScreenSaverEngine frontmost (a notification can't fake that), or a `didstart` hint younger than 10 s.
    var screensaverRunning: Bool {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.screensaverBundleID { return true }
        guard let at = screensaverHintAt else { return false }
        return AwakeSourceClock.now() - at < Self.screensaverHintSeconds
    }

    /// CGDisplayIsAsleep(main display): `declare` turns the display on, so it never runs while this is true.
    var displaysAsleep: Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }

    /// Typed events, in registration order, until `lifetime` ends.
    func observeEvents(_ lifetime: Lifetime, _ handler: @escaping @MainActor (SystemEvent) -> Void) {
        events.add(lifetime, handler)
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        let workspace = NSWorkspace.shared.notificationCenter
        add(workspace, NSWorkspace.willSleepNotification, .willSleep)
        add(workspace, NSWorkspace.didWakeNotification, .didWake)
        add(workspace, NSWorkspace.screensDidSleepNotification, .screensDidSleep)
        add(workspace, NSWorkspace.screensDidWakeNotification, .screensDidWake)
        add(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned)
        add(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive)
        let distributed = DistributedNotificationCenter.default()
        add(distributed, Notification.Name("com.apple.screenIsLocked"), .lockHint)
        add(distributed, Notification.Name("com.apple.screenIsUnlocked"), .unlockHint)
        add(distributed, Notification.Name("com.apple.screensaver.didstart"), .screensaverStarted)
        add(distributed, Notification.Name("com.apple.screensaver.didstop"), .screensaverStopped)
        let center = NotificationCenter.default
        add(center, .NSSystemClockDidChange, .clockChanged)
        add(center, .NSSystemTimeZoneDidChange, .timeZoneChanged)
        add(center, .NSCalendarDayChanged, .dayChanged)
        add(center, .NSProcessInfoPowerStateDidChange, .lowPowerModeChanged)
        add(center, ProcessInfo.thermalStateDidChangeNotification, .thermalChanged)
        startLidNotifications()
        readLid()
    }

    func deactivate() {
        guard active else { return }
        active = false
        for o in observers { o.center.removeObserver(o.token) }
        observers = []
        stopLidNotifications()
        screensaverHintAt = nil
        isSleeping = false
        lastWake = nil
        lastEvent = nil
        lidClosed = nil
        lidWillSleep = nil
        publishLid()
        context = nil
    }

    // MARK: CriterionSource (no kinds: nothing to contribute)

    func contribute(to facts: inout CriterionFacts) {}

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Events

    private func add(_ center: NotificationCenter, _ name: Notification.Name, _ event: SystemEvent) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        observers.append((center, token))
    }

    private func handle(_ event: SystemEvent) {
        guard active else { return }
        switch event {
        case .willSleep: isSleeping = true
        case .didWake:
            isSleeping = false
            lastWake = AwakeSourceClock.now()
            readLid()
        case .screensaverStarted: screensaverHintAt = AwakeSourceClock.now()
        case .screensaverStopped: screensaverHintAt = nil
        case .timeZoneChanged: NSTimeZone.resetSystemTimeZone()
        case .lidChanged: readLid()
        default: break
        }
        lastEvent = event
        events.fire(event)
        changes.fire()
    }

    // MARK: Lid (IOPMrootDomain interest, [PA] §2)

    private func readLid() {
        guard rootDomain != 0 else {
            lidClosed = nil
            lidWillSleep = nil
            publishLid()
            return
        }
        lidClosed = Self.boolProperty(rootDomain, "AppleClamshellState")
        lidWillSleep = lidClosed == nil ? nil : Self.boolProperty(rootDomain, "AppleClamshellCausesSleep")
        publishLid()
    }

    /// The runtime's "closing the lid will sleep" fact (nil = no lid), for the Awake menu's lid notice (§2.12).
    private func publishLid() {
        guard let runtime = context?.runtime, runtime.lidWillSleep != lidWillSleep else { return }
        runtime.lidWillSleep = lidWillSleep
    }

    private static func boolProperty(_ entry: io_registry_entry_t, _ key: String) -> Bool? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    private func startLidNotifications() {
        guard rootDomain == 0 else { return }
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        let callback: IOServiceInterestCallback = { refcon, _, messageType, _ in
            // kIOPMMessageClamshellStateChange = iokit_family_msg(sub_iokit_powermanagement, 0x100).
            guard messageType == 0xE003_4100, let refcon else { return }
            let box = Unmanaged<CallbackTarget<SystemEventsMonitor>>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.handle(.lidChanged) } }
        }
        var note: io_object_t = 0
        if IOServiceAddInterestNotification(port, rootDomain, "IOGeneralInterest", callback, box, &note) == KERN_SUCCESS {
            lidPort = port
            lidNotification = note
            lidRefcon = box
        } else {
            IONotificationPortDestroy(port)
            Unmanaged<CallbackTarget<SystemEventsMonitor>>.fromOpaque(box).release()
        }
    }

    private func stopLidNotifications() {
        if lidNotification != 0 { IOObjectRelease(lidNotification) }
        lidNotification = 0
        if let port = lidPort { IONotificationPortDestroy(port) }
        lidPort = nil
        if let box = lidRefcon { Unmanaged<CallbackTarget<SystemEventsMonitor>>.fromOpaque(box).release() }
        lidRefcon = nil
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
        rootDomain = 0
    }
}
