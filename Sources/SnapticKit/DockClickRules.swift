import Foundation

// Dock click actions (lead; PLAN 0.5 §4.11; X-13, Y-15, D2-15, D2-20, X2-17). Pure: the resolver over an activation
// history, and the tap breaker the click and key taps share. Times are monotonic seconds passed in as `now`; the app
// stamps them from one clock (§R4: the plan names `mach_absolute_time`; Kit takes the seconds it converts to).

/// One app activation, as `NSWorkspace` reports it.
package struct DockActivation: Equatable, Sendable {
    package var pid: Int32
    package var at: Double

    package init(pid: Int32, at: Double) {
        self.pid = pid
        self.at = at
    }
}

/// The last activations, oldest first, at most `capacity`.
package struct DockActivationHistory: Equatable, Sendable {
    package static let capacity = 32

    package private(set) var records: [DockActivation] = []

    package init(_ records: [DockActivation] = []) {
        for r in records { record(pid: r.pid, at: r.at) }
    }

    package mutating func record(pid: Int32, at: Double) {
        let i = records.lastIndex { $0.at <= at }.map { $0 + 1 } ?? 0
        records.insert(DockActivation(pid: pid, at: at), at: i)
        if records.count > Self.capacity { records.removeFirst(records.count - Self.capacity) }
    }

    /// The app active at `t`: the last activation at or before it.
    package func active(at t: Double) -> Int32? {
        records.last { $0.at <= t }?.pid
    }

    /// Whether an app other than `pid` was activated in `from...through`.
    package func otherActivation(than pid: Int32?, from: Double, through: Double) -> Bool {
        records.contains { $0.at >= from && $0.at <= through && $0.pid != pid }
    }
}

/// What the click resolver sampled at mouse-down, before the Dock acts (D2-20).
package struct DockClickPress: Equatable, Sendable {
    package var at: Double
    /// The clicked item's app; nil for an item that isn't a running app.
    package var pid: Int32?
    /// The active app: the last activation at least 150 ms before the mouse-down.
    package var activePID: Int32?
    /// The app's windows visible on the current Space.
    package var visibleOnSpace: Int
    package var windowCount: Int
    package var minimizedCount: Int
    package var action: DockClickAction
    package var restoreAll: Bool

    package init(at: Double, pid: Int32?, activePID: Int32?, visibleOnSpace: Int, windowCount: Int,
                 minimizedCount: Int, action: DockClickAction, restoreAll: Bool) {
        self.at = at
        self.pid = pid
        self.activePID = activePID
        self.visibleOnSpace = visibleOnSpace
        self.windowCount = windowCount
        self.minimizedCount = minimizedCount
        self.action = action
        self.restoreAll = restoreAll
    }

    /// Every window is minimized, and there's at least one.
    package var allMinimized: Bool { windowCount > 0 && minimizedCount == windowCount }
}

/// Why a click does nothing. Counted (enum only), never logged with a name.
package enum DockClickSkip: String, CaseIterable, Sendable {
    case notAnApp
    case off
    case paused
    case breaker
    case killSwitch
    case otherItem
    case tooLate
    case notActive
    case ambiguous
    case noVisibleWindow
    case windowCreated
}

/// The resolver's answer.
package enum DockClickDecision: Equatable, Sendable {
    case skip(DockClickSkip)
    /// Restore every minimized window now.
    case restoreAll
    /// Confirm at `at` (mouse-up + 100 ms) with `confirm`, then act.
    case wait(DockClickAction, at: Double)
    /// Act now.
    case act(DockClickAction)
}

package enum DockClickRules {
    /// The active app is the last activation at least this long before the mouse-down.
    package static let activeLead = 0.15
    /// The mouse-up must land within this long of the mouse-down.
    package static let mouseUpWithin = 0.5
    /// Hide or Minimize runs this long after the mouse-up.
    package static let actDelay = 0.1

    /// Samples everything at mouse-down.
    package static func press(at: Double, pid: Int32?, history: DockActivationHistory, visibleOnSpace: Int,
                              windowCount: Int, minimizedCount: Int, action: DockClickAction,
                              restoreAll: Bool) -> DockClickPress {
        DockClickPress(at: at, pid: pid, activePID: history.active(at: at - activeLead),
                       visibleOnSpace: visibleOnSpace, windowCount: windowCount, minimizedCount: minimizedCount,
                       action: action, restoreAll: restoreAll)
    }

    /// The mouse-up. `onSameItem` is `DockObserver`'s latest selection checked against the hit band (§4.1); no AX
    /// call is made in the tap. `killSwitch` reads `Dock.disable.clickActions`, and only when the click would act
    /// (D2-15).
    package static func mouseUp(_ p: DockClickPress, at now: Double, onSameItem: Bool,
                                history: DockActivationHistory, pause: DockPauseReason?, breakerTripped: Bool,
                                killSwitch: () -> Bool) -> DockClickDecision {
        guard let pid = p.pid else { return .skip(.notAnApp) }
        let restore = p.restoreAll && p.allMinimized
        guard restore || p.action != .doNothing else { return .skip(.off) }
        if let pause, pause != .voiceOver { return .skip(.paused) }
        if breakerTripped { return .skip(.breaker) }
        guard onSameItem else { return .skip(.otherItem) }
        guard now - p.at <= mouseUpWithin else { return .skip(.tooLate) }
        if restore { return killSwitch() ? .skip(.killSwitch) : .restoreAll }
        guard p.activePID == pid else { return .skip(.notActive) }
        if history.otherActivation(than: pid, from: p.at - activeLead, through: now) { return .skip(.ambiguous) }
        guard p.visibleOnSpace > 0 else { return .skip(.noVisibleWindow) }
        return killSwitch() ? .skip(.killSwitch) : .wait(p.action, at: now + actDelay)
    }

    /// At mouse-up + 100 ms: still unambiguous, and for Hide, no window created meanwhile (the pid's on-screen
    /// layer-0 count didn't grow; X2-17).
    package static func confirm(_ p: DockClickPress, _ action: DockClickAction, at now: Double,
                                history: DockActivationHistory, layer0Grew: Bool) -> DockClickDecision {
        if history.otherActivation(than: p.pid, from: p.at - activeLead, through: now) { return .skip(.ambiguous) }
        if action == .hideApp && layer0Grew { return .skip(.windowCreated) }
        return .act(action)
    }
}

/// Three disables by macOS within 60 s turn a tap off until relaunch (§4.5, §4.11).
package struct DockTapBreaker: Equatable, Sendable {
    package static let limit = 3
    package static let window = 60.0

    package private(set) var tripped = false
    private var disables: [Double] = []

    package init() {}

    /// macOS disabled the tap. Returns whether the breaker is tripped.
    @discardableResult
    package mutating func disabled(at now: Double) -> Bool {
        disables.append(now)
        disables.removeAll { $0 <= now - Self.window }
        if disables.count >= Self.limit { tripped = true }
        return tripped
    }
}
