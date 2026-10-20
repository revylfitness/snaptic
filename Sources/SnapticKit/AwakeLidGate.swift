import Foundation

// N19, the lid gate (owner: T-lid-kit; PLAN 0.3.1 B2): who may turn lid-closed mode on, and what each later event does
// to it. Pure, exhaustively tested (the hotkey rows included). Only a direct action in Snaptic's own UI, in this
// process, may ask for the password: a menu click, the Custom… panel or a Settings pull-down item (Settings checks
// `SettingsShell.mayStart()`). The CLI, the control socket, rules, holds, start-at-launch, restore or resume, History's
// Start Again, hotkeys (preset slots included), backups, presets and default options never can: the mode is no
// `AwakeSessionOptions` field and `AwakeSession.lidRequested` is never persisted, so no stored path can carry it.

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
        /// A request to turn the mode on: on an idle Mac, or one that starts its own session (nil: the idle
        /// submenu, Custom…, a Settings preset, which replace whatever governs), or added to the running manual
        /// session started from this source in this process. A restored or resumed session is never `running`
        /// (`addsToSession`): it gets the idle submenu, like any other governing state.
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
    /// `.settings` (ignored for other sources).
    ///
    /// - allowed: `.menu`, or `.settings` with `mayStart`, on an idle Mac or in a menu or Settings session;
    /// - keep: a replacement by such a start (`until` becomes the earlier of the new end and `capStart + 24 h`);
    /// - end: everything else, a hotkey replacement included (any same-user process can change hotkey bindings).
    package static func decide(source: AwakeSessionSource, mayStart: Bool, event: Event) -> Decision {
        switch event {
        case .request(let running):
            guard isDirectUI(source, mayStart: mayStart) else { return .end }
            guard let running else { return .allowed }
            return running == .menu || running == .settings ? .allowed : .end
        case .replaced(let by):
            return by == source && isDirectUI(by, mayStart: mayStart) ? .keep : .end
        case .sessionEnded, .triggerOrHold, .moduleStopped, .safeMode, .featureOff, .restore:
            return .end
        }
    }

    /// Whether a request may be added to the governing manual session (the ✓ row) rather than start its own (the
    /// idle submenu): it was started from the menu or Settings in this process (B1). Restored and resumed sessions,
    /// and every other source, take the idle submenu.
    package static func addsToSession(source: AwakeSessionSource, startedInProcess: Bool) -> Bool {
        startedInProcess && (source == .menu || source == .settings)
    }

    /// A menu click, or a Settings action while Settings may start sessions.
    private static func isDirectUI(_ source: AwakeSessionSource, mayStart: Bool) -> Bool {
        switch source {
        case .menu: return true
        case .settings: return mayStart
        case .hotkey, .commandLine, .launch, .rule: return false
        }
    }
}
