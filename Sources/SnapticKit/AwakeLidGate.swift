import Foundation

// N19, the lid gate (owner: T-lid-kit; PLAN 0.3.1 B2): who may turn lid-closed mode on, and what each later event does
// to it. Pure, exhaustively tested (the hotkey rows included).
//
// Step 0 stub: every decision is `.end` (never allowed, never kept) until T-lid-kit lands.

package enum AwakeLidGate {
    package enum Decision: String, Sendable {
        /// The request may proceed (the password prompt follows).
        case allowed
        /// Lid-closed mode ends (or the request is refused).
        case end
        /// The mode carries over to the replacing session; the watchdog is untouched.
        case keep
    }

    package enum Event: Equatable, Sendable {
        /// A request to turn the mode on: on an idle Mac (nil), or in the session started from this source.
        case request(running: AwakeSessionSource?)
        /// The running session is replaced by a start from this source.
        case replaced(by: AwakeSessionSource)
        case sessionEnded
        /// A trigger or hold takes over.
        case triggerOrHold
        case moduleStopped
        case safeMode
        /// The feature turned off, or `Awake.disable.lidClosed` set.
        case featureOff
        /// Restore or resume after a relaunch.
        case restore
    }

    /// `source` is where the request (or the replacing start) came from; `mayStart` is `SettingsShell.mayStart()` for
    /// `.settings`. Stub: `.end`.
    package static func decide(source: AwakeSessionSource, mayStart: Bool, event: Event) -> Decision { .end }
}
