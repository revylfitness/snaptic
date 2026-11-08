import Foundation

// Hidden Icons' intent queue (lead; PLAN 0.4 §4.4). One serialization point for every source: each intent is
// resolved against the target state (where the bar is heading after the intents before it), not the current one, so
// two quick toggles from different sources cancel out instead of both expanding. Debounce and suppression drop intents
// here; the engine (K3) handles preemption, joining and supersession of what it is given. The app runs this on main
// and hands each returned step to `IconsEngineCore`.

package enum IconsIntentSource: String, CaseIterable, Sendable {
    case click
    case shortcut
    case cli
    case menu
    case hiddenList
    case hover
    case timer
    case launch
    case settings
    /// Wake, MenuBarAgent restart, another hider, an exam, a session event.
    case monitor

    /// Sources a person drives. Any of them cancels a pending launch collapse. Settings' Show Icons / Hide Icons
    /// buttons count (A7): a collapse from them marks the icons arranged.
    package var isUser: Bool {
        switch self {
        case .click, .shortcut, .cli, .menu, .hiddenList, .hover, .settings: true
        case .timer, .launch, .monitor: false
        }
    }

    /// Debounced 0.3 s. The CLI and the list aren't: the queue resolves their toggles.
    package var isDebounced: Bool { self == .click || self == .shortcut }
}

package enum IconsIntent: Equatable, Sendable {
    case command(IconsCommand)
    /// The module stops. Preempts everything.
    case stop
    /// Show every icon now. Preempts everything; the last intent stays as it was, so recovery can re-collapse.
    case failSafe(IconsFailSafeReason)
}

/// What the engine is told to do.
package enum IconsStep: Equatable, Sendable {
    case collapse
    case expand(IconsExpandMode)
    case stop
    case failSafe(IconsFailSafeReason)
}

package enum IconsIntentDrop: String, CaseIterable, Sendable {
    /// A click or shortcut within 0.3 s of the last one from the same source.
    case debounce
    /// Hover within 1 s of a click-collapse or a Space change.
    case hoverSuppressed
    /// The timer within 60 s of a hidden-list press.
    case timerSuppressed
    /// Launch collapse after a user intent.
    case launchCancelled
    /// The module isn't running.
    case stopped
}

package enum IconsSubmitResult: Equatable, Sendable {
    /// Run this on the engine. `seq` identifies it for `settled(seq:state:)`.
    case run(IconsStep, seq: UInt64)
    /// The target already is what the intent asks for. A collapse while one is in flight joins it in the engine.
    case noChange
    case dropped(IconsIntentDrop)
}

package struct IconsIntentQueue: Equatable, Sendable {
    package static let debounce: Double = 0.3
    package static let hoverQuiet: Double = 1
    package static let timerQuiet: Double = 60

    /// Where the bar is heading after every step handed out so far.
    package private(set) var target: IconsTarget
    /// The last intent from a person, the timer or launch was to hide. Fail-safes leave it; `stop` clears it.
    package private(set) var intentHidden = false
    /// The source of the last expand, for the activation rule (H9). Cleared once the bar is collapsed.
    package private(set) var expandSource: IconsIntentSource?
    /// A person acted since start; a later launch collapse is dropped.
    package private(set) var userActed = false
    package private(set) var stopped = false
    package private(set) var seq: UInt64 = 0

    private var lastDebounced: [IconsIntentSource: Double] = [:]
    private var hoverQuietUntil: Double?
    private var timerQuietUntil: Double?

    package init(state: IconsEngineState) {
        target = IconsTarget(state)
    }

    /// Resolve one intent. `now` is monotonic seconds.
    package mutating func submit(_ intent: IconsIntent, from source: IconsIntentSource,
                                 now: Double) -> IconsSubmitResult {
        switch intent {
        case .stop:
            stopped = true
            intentHidden = false
            expandSource = nil
            target = .expanded(.plain)
            return handOut(.stop)
        case .failSafe(let reason):
            if stopped { return .dropped(.stopped) }
            // From collapsed the source is already nil, so a fail-safe expand never takes the full menu bar.
            target = .expanded(.plain)
            return handOut(.failSafe(reason))
        case .command(let command):
            return submit(command, from: source, now: now)
        }
    }

    private mutating func submit(_ command: IconsCommand, from source: IconsIntentSource,
                                 now: Double) -> IconsSubmitResult {
        if stopped { return .dropped(.stopped) }
        if let drop = drop(source, now: now) { return .dropped(drop) }
        if source.isUser { userActed = true }
        if source.isDebounced { lastDebounced[source] = now }
        if source == .hiddenList { hiddenListPressed(now: now) }

        guard let operation = IconsClicks.resolve(command, target: target) else {
            intentHidden = command == .hide
            return .noChange
        }
        target = IconsClicks.target(after: operation)
        switch operation {
        case .collapse:
            // `expandSource` stays until the collapse succeeds: a failed collapse keeps the full menu bar (§4.7).
            intentHidden = true
            if source == .click { hoverQuietUntil = max(hoverQuietUntil ?? now, now + Self.hoverQuiet) }
            return handOut(.collapse)
        case .expand(let mode):
            intentHidden = false
            expandSource = source
            return handOut(.expand(mode))
        }
    }

    private func drop(_ source: IconsIntentSource, now: Double) -> IconsIntentDrop? {
        switch source {
        case .click, .shortcut:
            if let last = lastDebounced[source], now - last >= 0, now - last < Self.debounce { return .debounce }
        case .hover:
            if let until = hoverQuietUntil, now < until { return .hoverSuppressed }
        case .timer:
            if let until = timerQuietUntil, now < until { return .timerSuppressed }
        case .launch:
            if userActed { return .launchCancelled }
        case .cli, .menu, .hiddenList, .settings, .monitor:
            break
        }
        return nil
    }

    private mutating func handOut(_ step: IconsStep) -> IconsSubmitResult {
        seq &+= 1
        return .run(step, seq: seq)
    }

    /// The user switched Spaces: hover is ignored for a second.
    package mutating func spaceChanged(now: Double) {
        hoverQuietUntil = max(hoverQuietUntil ?? now, now + Self.hoverQuiet)
    }

    /// A row in the hidden list was pressed: the timer is ignored for a minute.
    package mutating func hiddenListPressed(now: Double) {
        timerQuietUntil = max(timerQuietUntil ?? now, now + Self.timerQuiet)
    }

    /// The engine finished the step `seq` in `state`. Only the latest step may correct the target: a refused or
    /// failed collapse leaves the bar expanded, and a later step already moved the target on its own.
    package mutating func settled(seq finished: UInt64, state: IconsEngineState) {
        guard finished == seq else { return }
        follow(state)
    }

    /// The engine changed state on its own (a fail-safe it raised, an agent restart). The target follows.
    package mutating func engineChanged(_ state: IconsEngineState) {
        guard state != .calibrating else { return }
        follow(state)
    }

    private mutating func follow(_ state: IconsEngineState) {
        target = IconsTarget(state)
        if state.isCollapsed { expandSource = nil }
    }

    /// The module started again after a stop.
    package mutating func restart(state: IconsEngineState) {
        self = IconsIntentQueue(state: state)
    }
}
