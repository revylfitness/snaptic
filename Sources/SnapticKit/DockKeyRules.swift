import Foundation

// Keyboard shortcuts in previews (lead; PLAN 0.5 §4.5; D2-3, X2-5, X3-4, X3-5, G2-1). Pure: the engagement rule, and
// the key decision the `DockKeys` tap callback asks for on the main run loop. The callback builds a snapshot, calls
// `decide`, and returns; it does no AX and no I/O. Times are monotonic seconds passed in as `now`.

/// What a table key did; `DockPreviewPolicy` takes it as `keyHandled`.
package enum DockKeyAction: String, CaseIterable, Sendable {
    case close
    case minimize
    case restore
    case hideApp
    case showApp
    case quitApp
    case escape
}

/// Engagement (§4.5): the pointer has moved at least 4 pt in total inside the panel within the last 1.5 s, and has
/// been inside for at least 250 ms since `panelEntered`; or a click in the panel. Movement is checked when it
/// happens, so a pointer that moved 4 pt early and then rests doesn't engage later on its own (X3-5).
package struct DockEngagement: Equatable, Sendable {
    package static let minDistance = 4.0
    package static let window = 1.5
    package static let minDwell = 0.25
    package static let idle = 1.5

    private struct Step: Equatable, Sendable {
        var at: Double
        var distance: Double
    }

    package private(set) var engaged = false
    private var enteredAt: Double?
    private var lastPoint: DockPoint?
    private var steps: [Step] = []
    private var lastActivityAt: Double?

    package init() {}

    /// The pointer entered the panel.
    package mutating func entered(at now: Double) {
        enteredAt = now
        lastPoint = nil
        steps = []
    }

    /// The pointer moved inside the panel. Returns whether `engaged` changed.
    @discardableResult
    package mutating func moved(to point: DockPoint, at now: Double) -> Bool {
        let before = engaged
        expire(at: now)
        if enteredAt == nil { enteredAt = now }
        let distance = lastPoint.map { $0.distance(to: point) } ?? 0
        lastPoint = point
        guard distance > 0 else { return engaged != before }
        steps.append(Step(at: now, distance: distance))
        lastActivityAt = now
        steps.removeAll { $0.at <= now - Self.window }
        if !engaged, let enteredAt, now - enteredAt >= Self.minDwell,
           steps.reduce(0, { $0 + $1.distance }) >= Self.minDistance {
            engaged = true
        }
        return engaged != before
    }

    /// A click in the panel engages at once. Returns whether `engaged` changed.
    @discardableResult
    package mutating func clicked(at now: Double) -> Bool {
        let before = engaged
        if enteredAt == nil { enteredAt = now }
        engaged = true
        lastActivityAt = now
        return engaged != before
    }

    /// 1.5 s without movement or a click disengages. Returns whether `engaged` changed.
    @discardableResult
    package mutating func expire(at now: Double) -> Bool {
        guard engaged, let lastActivityAt, now - lastActivityAt >= Self.idle else { return false }
        disengage()
        return true
    }

    /// The pointer left the panel. Returns whether `engaged` changed.
    @discardableResult
    package mutating func exited() -> Bool {
        let before = engaged
        disengage()
        enteredAt = nil
        lastPoint = nil
        return engaged != before
    }

    /// The panel hid. Returns whether `engaged` changed.
    @discardableResult
    package mutating func hidden() -> Bool { exited() }

    /// A key-down that isn't in the table: disengage; it engages again only by the same rule. Returns whether
    /// `engaged` changed.
    @discardableResult
    package mutating func notInTable() -> Bool {
        let before = engaged
        disengage()
        return engaged != before
    }

    private mutating func disengage() {
        engaged = false
        steps = []
        lastActivityAt = nil
    }
}

/// Secure Event Input as read when the panel shows and when it engages (§4.5, §4.12).
package enum DockSecureInput: String, CaseIterable, Sendable {
    case off
    case on
    case unknown
}

/// What's under the pointer in the panel.
package enum DockKeyTarget: Equatable, Sendable {
    case card(hasAXElement: Bool, minimized: Bool)
    case header
    case gap
    case none
}

/// What the tap reads at each event (§2.1). The app keeps it current; the tap never asks AX.
package struct DockKeySnapshot: Equatable, Sendable {
    package var engaged: Bool
    /// The setting is on, there's no `Dock.disable.keys` and no tripped breaker.
    package var keysWork: Bool
    package var secureInput: DockSecureInput
    /// `WindowServices.switcherSessionActive`.
    package var switcherActive: Bool
    package var target: DockKeyTarget
    package var appIsFinder: Bool
    package var appHidden: Bool
    /// When the last card close or minimize started the cards moving.
    package var reflowStartedAt: Double?

    package init(engaged: Bool = true, keysWork: Bool = true, secureInput: DockSecureInput = .off,
                 switcherActive: Bool = false, target: DockKeyTarget = .card(hasAXElement: true, minimized: false),
                 appIsFinder: Bool = false, appHidden: Bool = false, reflowStartedAt: Double? = nil) {
        self.engaged = engaged
        self.keysWork = keysWork
        self.secureInput = secureInput
        self.switcherActive = switcherActive
        self.target = target
        self.appIsFinder = appIsFinder
        self.appHidden = appHidden
        self.reflowStartedAt = reflowStartedAt
    }
}

/// The character a key event types, read from the layout by the app.
package enum DockKeyChar: String, CaseIterable, Sendable {
    case w
    case m
    case h
    case q
    case escape
    case other
}

/// Modifier flags the table cares about.
package struct DockKeyModifiers: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) { self.rawValue = rawValue }

    package static let command = DockKeyModifiers(rawValue: 1 << 0)
    package static let shift = DockKeyModifiers(rawValue: 1 << 1)
    package static let option = DockKeyModifiers(rawValue: 1 << 2)
    package static let control = DockKeyModifiers(rawValue: 1 << 3)
}

/// A key-down, key-up or autorepeat (`kCGKeyboardEventAutorepeat` = 1). `flagsChanged` is never passed in.
package struct DockKeyEvent: Equatable, Sendable {
    package enum Kind: String, CaseIterable, Sendable {
        case down
        case up
        case autorepeat
    }

    package var kind: Kind
    package var keyCode: Int
    package var char: DockKeyChar
    package var modifiers: DockKeyModifiers

    package init(_ kind: Kind, keyCode: Int, char: DockKeyChar, modifiers: DockKeyModifiers = []) {
        self.kind = kind
        self.keyCode = keyCode
        self.char = char
        self.modifiers = modifiers
    }

    /// ANSI key codes, for tests and the app's snapshot.
    package static let keyCodeW = 13
    package static let keyCodeM = 46
    package static let keyCodeH = 4
    package static let keyCodeQ = 12
    package static let keyCodeEscape = 53
    package static let keyCodeA = 0

    /// One of the five table keys: ⌘W, ⌘M, ⌘H, ⌘Q (⌘ alone) or Esc (no modifiers). Never a bare letter, an arrow
    /// or Return (M40).
    package var isTableKey: Bool {
        switch char {
        case .w, .m, .h, .q: modifiers == .command
        case .escape: modifiers.isEmpty
        case .other: false
        }
    }
}

/// The tap's answer.
package enum DockKeyDecision: Equatable, Sendable {
    /// Let it through.
    case pass
    /// Let it through, and disengage: a key-down that isn't in the table (`keyNotHandled`).
    case passNotInTable
    /// Swallow it; act when there's an action (`keyHandled`). A table key with no target is swallowed with nil.
    case swallow(DockKeyAction?)
}

/// The key decision (§4.5). Holds only the held key (X3-4); everything else comes in the snapshot.
package struct DockKeyRules: Equatable, Sendable {
    /// A swallowed key stays held for at least this long after its key-down or its last repeat.
    package static let holdCap = 1.0
    /// The cap also outlasts the first autorepeat by this much (§R4 A5).
    package static let repeatMargin = 0.2
    /// Table keys do nothing this long after a card closes or minimizes.
    package static let reflow = 0.3

    package private(set) var heldKeyCode: Int?
    package private(set) var holdEndsAt: Double?
    /// `holdCap`, or the user's "Delay until repeat" plus `repeatMargin` when that's longer: with Long (about 1.8 s)
    /// a 1 s cap would end before the first repeat, and a held ⌘Q would reach the app that came forward.
    package let cap: Double

    package init(repeatDelay: Double = 0) {
        cap = max(Self.holdCap, repeatDelay + Self.repeatMargin)
    }

    /// A swallowed key is still down.
    package func holding(at now: Double) -> Bool {
        guard heldKeyCode != nil, let holdEndsAt else { return false }
        return now < holdEndsAt
    }

    /// Whether the tap is enabled: while engaged with keys working and secure input off, or while a key it swallowed
    /// is still down; never while the switcher's session is active.
    package func tapEnabled(_ s: DockKeySnapshot, at now: Double) -> Bool {
        if s.switcherActive { return false }
        return holding(at: now) || Self.active(s)
    }

    /// Engaged, keys work, secure input known to be off, and the switcher closed.
    package static func active(_ s: DockKeySnapshot) -> Bool {
        s.engaged && s.keysWork && s.secureInput == .off && !s.switcherActive
    }

    package mutating func decide(_ e: DockKeyEvent, _ s: DockKeySnapshot, at now: Double) -> DockKeyDecision {
        if let held = heldKeyCode {
            if !holding(at: now) || s.switcherActive {
                release()
            } else if e.keyCode == held {
                switch e.kind {
                case .up:
                    release()
                    return .swallow(nil)
                case .autorepeat:
                    holdEndsAt = now + cap
                    return .swallow(nil)
                case .down:
                    // The key-up was lost: a new press, decided as one.
                    release()
                }
            }
        }
        guard Self.active(s) else { return .pass }
        switch e.kind {
        case .up:
            return .pass
        case .autorepeat:
            guard e.isTableKey else { return .pass }
            hold(e.keyCode, at: now)
            return .swallow(nil)
        case .down:
            guard e.isTableKey else { return .passNotInTable }
            hold(e.keyCode, at: now)
            if let reflow = s.reflowStartedAt, now >= reflow, now < reflow + Self.reflow - 1e-9 { return .swallow(nil) }
            return .swallow(Self.action(e.char, s))
        }
    }

    /// What a table key does on the snapshot's target; nil when it has none (the header, a gap, a card that offers
    /// only Bring Forward, or ⌘Q on Finder). ⌘H acts on the app anywhere in the panel; ⌘Q needs a card under the
    /// pointer, so over the header or a gap it does nothing (M23).
    package static func action(_ char: DockKeyChar, _ s: DockKeySnapshot) -> DockKeyAction? {
        switch char {
        case .w:
            if case .card(true, _) = s.target { return .close }
            return nil
        case .m:
            if case let .card(true, minimized) = s.target { return minimized ? .restore : .minimize }
            return nil
        case .h:
            return s.appHidden ? .showApp : .hideApp
        case .q:
            guard case .card = s.target, !s.appIsFinder else { return nil }
            return .quitApp
        case .escape:
            return .escape
        case .other:
            return nil
        }
    }

    private mutating func hold(_ keyCode: Int, at now: Double) {
        heldKeyCode = keyCode
        holdEndsAt = now + cap
    }

    private mutating func release() {
        heldKeyCode = nil
        holdEndsAt = nil
    }
}
