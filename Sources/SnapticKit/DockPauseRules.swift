import Foundation

// Dock Previews' pauses, their EventLog lines and diagnostics, and `dock status`'s feature values (lead; PLAN 0.5
// §4.13, §4.15, §4.16, §4.21, §4.22; A6b). The app's `DockPauseSources` gathers the facts; this decides. Lines carry
// enums and counts only: never a tool's name, an app's name or a window's title (§4.15, ground rule 6).

package enum DockPauseRules {
    /// The pause the module holds: the first of Safe Mode, other tool, VoiceOver and command that applies, whatever
    /// the Dock read shows (§4.15). `DockPageRules.pause` is the row's; this one doesn't wait for a read, so a Dock
    /// that becomes readable while another tool runs never shows a preview first.
    package static func effective(_ f: DockPageFacts) -> DockPauseReason? {
        DockPauseReason.winning(safeMode: f.safeMode, otherTool: DockPageRules.otherTool(f) != nil,
                                voiceOver: DockPageRules.voiceOverPauses(f), command: f.commandPause != nil)
    }

    /// The observer, the lease and the controller run (ground rule 1). A pause takes them down, except the VoiceOver
    /// pause while Dock click actions work: clicks still come from the pointer and need the observer's selection
    /// (§4.11, §4.16). `clicksWork`: a click action or Restore All is on and nothing stopped them.
    package static func engineRuns(pause: DockPauseReason?, clicksWork: Bool) -> Bool {
        switch pause {
        case nil: return true
        case .voiceOver?: return clicksWork
        case .safeMode?, .otherTool?, .command?: return false
        }
    }

    /// The Dock read the page and `dock status` see. `stats` is nil while a pause keeps the observer down: nothing
    /// is read then, so Starting and row 5 can't apply and the pause's own row shows.
    package static func read(_ stats: DockObserverStats?) -> (read: DockReadState, ladderEnded: Bool,
                                                             unreadableSince: Double?) {
        guard let stats else { return (.attached, true, nil) }
        return (stats.read, stats.ladderEnded, stats.unreadableSince)
    }

    // MARK: EventLog (§4.22)

    /// `dock.paused reason=<enum>` or `dock.resumed`; nil when nothing changed.
    package static func eventLine(from old: DockPauseReason?, to new: DockPauseReason?) -> String? {
        guard old != new else { return nil }
        guard let new else { return "dock.resumed" }
        return "dock.paused reason=" + new.rawValue
    }

    // MARK: Diagnostics (§4.22)

    /// `Pause reason: <enum|none>`.
    package static func pauseLine(_ reason: DockPauseReason?) -> String {
        "Pause reason: " + (reason?.rawValue ?? "none")
    }

    /// One line per window symbol, `<id>: <state>[, imageMoved]`, for reports in `WindowSymbolID.allCases` order.
    /// - In Safe Mode the capture symbol reads `safeMode`: nothing captures (M33).
    /// - An available symbol whose probe hasn't passed on this build (`Windows.probedBuild.<symbol>` isn't
    ///   `currentBuild`) reads `notProbed` (M1, X3-3). Presence-only symbols have no probe.
    package static func symbolLines(_ reports: [WindowSymbolReport], probedBuilds: [WindowSymbolID: String],
                                    currentBuild: String, safeMode: Bool) -> [String] {
        zip(WindowSymbolID.allCases, reports).map { id, report in
            let value: String
            if safeMode && id == .hwCapture {
                value = "safeMode"
            } else if report.state == .available,
                      WindowSymbolHealth(id, probedBuild: probedBuilds[id], currentBuild: currentBuild).phase != .passed {
                value = "notProbed"
            } else {
                value = report.state.rawValue
            }
            return id.rawValue + ": " + value + (report.imageMoved ? ", imageMoved" : "")
        }
    }

    // MARK: `dock status` (§4.21)

    /// `clickActions=` or `keys=`: the kill switch, then the setting, then the breaker, then the pause.
    package static func feature(on: Bool, killed: Bool, stopped: Bool, paused: Bool) -> DockCLIFeature {
        if killed { return .disabled }
        if !on { return .off }
        if stopped { return .stopped }
        return paused ? .paused : .on
    }

    /// `thumbnails=`: off, or on without Screen Recording (`noPermission`), or on.
    package static func thumbnails(on: Bool, screenRecording: Bool) -> DockCLIThumbnails {
        guard on else { return .off }
        return screenRecording ? .on : .noPermission
    }

    /// `dock status`'s facts; nil in rows 1 and 2 (the verb isn't registered there). The pause covers click actions
    /// except VoiceOver's (§4.11, so `clickActions` stays `on` in row 7), and keys under any pause (§4.15).
    package static func status(_ f: DockPageFacts, keysOn: Bool, killed: Set<DockFeature>,
                               clickBreakerTripped: Bool = false, keysBreakerTripped: Bool = false,
                               cacheEntries: Int, cacheBytes: Int, observerAttached: Bool,
                               live: DockStatusLiveCounts) -> DockStatusFacts? {
        guard let cli = DockPageRules.cli(f) else { return nil }
        let pause = effective(f)
        let clicks = feature(on: f.clickActionOn || f.restoreAllOn, killed: killed.contains(.clickActions),
                             stopped: clickBreakerTripped, paused: pause != nil && pause != .voiceOver)
        let keys = feature(on: keysOn, killed: killed.contains(.keys), stopped: keysBreakerTripped,
                           paused: pause != nil)
        return DockStatusFacts(state: cli.state, reason: cli.reason, pausedUntil: f.commandPause?.untilUnix,
                               thumbnails: thumbnails(on: f.thumbnailsOn, screenRecording: f.screenRecording),
                               clickActions: clicks, keys: keys, cacheEntries: cacheEntries, cacheBytes: cacheBytes,
                               observerAttached: observerAttached, live: live)
    }
}
