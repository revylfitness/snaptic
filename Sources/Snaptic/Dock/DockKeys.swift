import AppKit
import ApplicationServices
import CoreGraphics
import SnapticKit

/// Keyboard shortcuts in previews (lead; PLAN 0.5 §4.5; A5). One active key tap, created the first time a panel
/// shows and kept for the life of the module; enabled only while `DockKeyRules.tapEnabled` says so (engaged with keys
/// working, or a swallowed key still down), never while the switcher's session is active.
/// - The callback runs on the main run loop. It builds the event, reads the controller's snapshot, calls
///   `DockKeyRules.decide` and returns; the action, the policy event and the re-sync go on the next main turn. No AX,
///   no I/O in the callback (§2.1).
/// - The mask is key-down and key-up only, never `flagsChanged`.
/// - macOS disabling the tap is counted by the breaker (three in 60 s turn keys off until relaunch); otherwise
///   Accessibility trust is re-checked on the next main turn and the tap re-enabled, or removed when trust is gone.
/// - Nothing about the keys, the app or its windows is logged.
@MainActor
final class DockKeys {
    /// §4.5, §4.17: until relaunch.
    private(set) static var breaker = DockTapBreaker()

    private var tap: DockEventTap?
    private var rules = DockKeyRules(repeatDelay: NSEvent.keyRepeatDelay)
    private let holdTimer = DockOneShot()
    /// The snapshot and target at the pointer (the event's location, CG global coordinates); nil when no event is
    /// being decided, so only the enable rule's fields count.
    private let context: @MainActor (_ pointer: CGPoint?) -> DockKeyContext
    private let onAction: @MainActor (DockKeyAction, DockKeyContext) -> Void
    private let onNotInTable: @MainActor () -> Void
    private let onStopped: @MainActor (_ tripped: Bool) -> Void

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Nil when the tap can't be created (no Accessibility trust, or macOS refused it).
    init?(context: @escaping @MainActor (_ pointer: CGPoint?) -> DockKeyContext,
          onAction: @escaping @MainActor (DockKeyAction, DockKeyContext) -> Void,
          onNotInTable: @escaping @MainActor () -> Void,
          onStopped: @escaping @MainActor (_ tripped: Bool) -> Void) {
        self.context = context
        self.onAction = onAction
        self.onNotInTable = onNotInTable
        self.onStopped = onStopped
        let box = DockTapHandlers()
        guard let tap = DockEventTap(types: [.keyDown, .keyUp], listenOnly: false, handlers: box) else { return nil }
        self.tap = tap
        box.handler = { [weak self] type, event in self?.handle(type, event) ?? false }
        box.onDisabled = { [weak self] in self?.tapDisabled() }
        DockPreviewsModule.liveCount(.keys, up: true)
    }

    var isRunning: Bool { tap != nil }

    /// The snapshot changed (engagement, secure input, the switcher, settings): enable or disable the tap.
    func sync() {
        guard let tap else { return }
        let now = Self.now
        tap.setEnabled(rules.tapEnabled(context(nil).snapshot, at: now))
        if let ends = rules.holdEndsAt, rules.holding(at: now) {
            holdTimer.arm(after: ends - now) { [weak self] in self?.sync() }
        } else {
            holdTimer.cancel()
        }
    }

    /// The module stopped, keys were turned off, or trust or the breaker took the tap.
    func stop() {
        holdTimer.cancel()
        guard let tap else { return }
        tap.invalidate()
        self.tap = nil
        rules = DockKeyRules(repeatDelay: NSEvent.keyRepeatDelay)
        DockPreviewsModule.liveCount(.keys, up: false)
    }

    // MARK: The callback (main run loop)

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard let e = Self.keyEvent(type, event) else { return false }
        let now = Self.now
        let ctx = context(event.location)
        let before = rules
        let decision = rules.decide(e, ctx.snapshot, at: now)
        let changed = rules != before
        switch decision {
        case .pass:
            if changed { followUp(nil, ctx) }
            return false
        case .passNotInTable:
            followUp(.notInTable, ctx)
            return false
        case let .swallow(action):
            followUp(action.map(FollowUp.act) ?? .resync, ctx)
            return true
        }
    }

    private enum FollowUp {
        case resync
        case act(DockKeyAction)
        case notInTable
    }

    /// The action and the re-sync run on the next main turn, never inside the callout.
    private func followUp(_ next: FollowUp?, _ ctx: DockKeyContext) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tap != nil else { return }
                switch next {
                case let .act(action)?: self.onAction(action, ctx)
                case .notInTable?: self.onNotInTable()
                case .resync?, nil: break
                }
                self.sync()
            }
        }
    }

    /// Counted in the callout (pure); trust is read and the tap re-enabled or removed on the next main turn.
    private func tapDisabled() {
        let tripped = Self.breaker.disabled(at: Self.now)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tap != nil else { return }
                if tripped {
                    self.stop()
                    EventLog.shared.record(.dock, "dock.breaker.\(DockFeature.keys.rawValue)")
                    self.onStopped(true)
                } else if AXIsProcessTrusted() {
                    self.sync()
                } else {
                    self.stop()
                    self.onStopped(false)
                }
            }
        }
    }

    // MARK: Events

    /// A key-down, key-up or autorepeat for the rules; nil for anything else.
    private static func keyEvent(_ type: CGEventType, _ event: CGEvent) -> DockKeyEvent? {
        let kind: DockKeyEvent.Kind
        switch type {
        case .keyDown:
            kind = event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? .autorepeat : .down
        case .keyUp:
            kind = .up
        default:
            return nil
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = modifiers(event.flags)
        return DockKeyEvent(kind, keyCode: keyCode, char: char(event, keyCode: keyCode, modifiers: modifiers),
                            modifiers: modifiers)
    }

    private static func modifiers(_ flags: CGEventFlags) -> DockKeyModifiers {
        var m: DockKeyModifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        return m
    }

    /// The letter the layout types, as the switcher reads it; only ⌘ alone can make a table letter, so other keys
    /// aren't looked up. ANSI positions stand in when the layout gives no characters.
    private static func char(_ event: CGEvent, keyCode: Int, modifiers: DockKeyModifiers) -> DockKeyChar {
        if keyCode == DockKeyEvent.keyCodeEscape { return .escape }
        guard modifiers == .command else { return .other }
        if let typed = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(), !typed.isEmpty {
            switch typed {
            case "w": return .w
            case "m": return .m
            case "h": return .h
            case "q": return .q
            default: return .other
            }
        }
        switch keyCode {
        case DockKeyEvent.keyCodeW: return .w
        case DockKeyEvent.keyCodeM: return .m
        case DockKeyEvent.keyCodeH: return .h
        case DockKeyEvent.keyCodeQ: return .q
        default: return .other
        }
    }
}

/// What a key acts on, read with the snapshot at the key-down so the action hits the card the rules saw.
struct DockKeyContext {
    var snapshot: DockKeySnapshot
    /// The previewed app; nil while no panel is shown.
    var pid: Int32?
    /// The window whose card is under the pointer.
    var item: WindowItem?
}

// MARK: - The tap

/// The tap's handlers, set once the owner exists (the owner can't pass itself before its own init ends).
@MainActor
final class DockTapHandlers {
    var handler: (@MainActor (CGEventType, CGEvent) -> Bool)?
    var onDisabled: (@MainActor () -> Void)?
}

/// One CGEvent tap on the main run loop, created disabled (HotkeyTap's pattern; the box is a `CallbackTarget`).
/// The keys tap is active (it may swallow); the Dock click tap is listen-only (§4.11).
@MainActor
final class DockEventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var box: Unmanaged<CallbackTarget<DockTapHandlers>>?
    private let handlers: DockTapHandlers

    /// Nil without Accessibility trust, or when macOS refuses the tap.
    init?(types: [CGEventType], listenOnly: Bool, handlers: DockTapHandlers) {
        self.handlers = handlers
        guard AXIsProcessTrusted() else { return nil }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            // The tap's run loop source lives on the main run loop.
            let box = Unmanaged<CallbackTarget<DockTapHandlers>>.fromOpaque(refcon).takeUnretainedValue()
            let swallow: Bool = MainActor.assumeIsolated {
                guard let handlers = box.target else { return false }
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    handlers.onDisabled?()
                    return false
                }
                return handlers.handler?(type, event) ?? false
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        let retained = Unmanaged.passRetained(CallbackTarget(handlers))
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: listenOnly ? .tailAppendEventTap : .headInsertEventTap,
                                          options: listenOnly ? .listenOnly : .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: retained.toOpaque()) else {
            retained.release()
            return nil
        }
        // Disabled until the owner says otherwise; nothing runs on main before this line, so no event slips in.
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        box = retained
    }

    /// Whether macOS has the tap enabled (it turns it off on a timeout).
    var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func setEnabled(_ on: Bool) {
        guard let tap, CGEvent.tapIsEnabled(tap: tap) != on else { return }
        CGEvent.tapEnable(tap: tap, enable: on)
    }

    func invalidate() {
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
        handlers.handler = nil
        handlers.onDisabled = nil
    }
}

/// One counted one-shot timer on the main run loop's common modes (§4.22 `timers`; L14).
@MainActor
final class DockOneShot {
    private var timer: Timer?

    var isArmed: Bool { timer != nil }

    /// Replaces any pending fire.
    func arm(after seconds: Double, _ body: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: max(seconds.isFinite ? seconds : 0, 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(body) }
        }
        self.timer = timer
        DockPreviewsModule.liveCount(.timers, up: true)
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        DockPreviewsModule.liveCount(.timers, up: false)
    }

    private func fire(_ body: @MainActor () -> Void) {
        guard timer != nil else { return }
        cancel()
        body()
    }
}
