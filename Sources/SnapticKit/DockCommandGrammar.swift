import Foundation

// `snaptic dock …` (lead; PLAN 0.5 §4.21, P-17, P2-25, G2-12, G3-1). A closed grammar: three verbs, one flag and one
// duration, no free-form string. The status line and JSON carry states, enums and counts, never an app's name or a
// window's title (§4.17). The verb × state table is data here, so `DockControlsTests` checks each cell and A9's
// `DockCLI` only looks them up. Never traps (seeded fuzz). Exit codes are the house `ControlExit` ones.

package enum DockCLICommand: Equatable, Sendable {
    case status(json: Bool)
    /// Seconds, `minPauseSeconds...maxPauseSeconds`; `pause` alone is `defaultPauseSeconds`.
    case pause(seconds: Int)
    case resume
}

/// `state=` of `dock status`.
package enum DockCLIState: String, CaseIterable, Sendable {
    case on, starting, paused, needsPermission, unavailable
}

/// `reason=` of `dock status`; `-` (null) when the row has none.
package enum DockCLIReason: String, CaseIterable, Sendable {
    case safeMode, otherTool, voiceOver, command, dockUnreadable
}

/// `thumbnails=` of `dock status`: the effective value.
package enum DockCLIThumbnails: String, CaseIterable, Sendable {
    case on, off, noPermission
}

/// `clickActions=` and `keys=` of `dock status`: the effective value. `stopped` is the breaker, `disabled` the kill
/// switch.
package enum DockCLIFeature: String, CaseIterable, Sendable {
    case on, off, paused, stopped, disabled
}

/// §4.17's rows (K3's `DockPageRow`, in precedence order) as the command line sees them. `DockPageRules.row` picks
/// the first that applies, and a held command pause doesn't change it (G3-1).
extension DockPageRow {

    /// §4.17's row number; nil for Starting, which has none.
    package var number: Int? {
        switch self {
        case .killSwitch: return 1
        case .off: return 2
        case .starting: return nil
        case .safeMode: return 3
        case .needsPermission: return 4
        case .dockUnreadable: return 5
        case .otherTool: return 6
        case .voiceOver: return 7
        case .pausedByCommand: return 8
        case .working: return 9
        }
    }

    /// The verbs are registered whenever the module is on (Starting and rows 3 to 9). Rows 1 and 2 register none, so
    /// every verb is the house "Unknown command" (exit 2).
    package var registersVerbs: Bool { self != .killSwitch && self != .off }

    /// `state=`; nil in rows 1 and 2.
    package var state: DockCLIState? {
        switch self {
        case .killSwitch, .off: return nil
        case .starting: return .starting
        case .safeMode, .otherTool, .voiceOver, .pausedByCommand: return .paused
        case .needsPermission: return .needsPermission
        case .dockUnreadable: return .unavailable
        case .working: return .on
        }
    }

    /// `reason=`: the row's own, whatever pause is held.
    package var reason: DockCLIReason? {
        switch self {
        case .safeMode: return .safeMode
        case .dockUnreadable: return .dockUnreadable
        case .otherTool: return .otherTool
        case .voiceOver: return .voiceOver
        case .pausedByCommand: return .command
        case .killSwitch, .off, .starting, .needsPermission, .working: return nil
        }
    }
}

/// Why `pause` or `resume` did nothing: one line, exit `ControlExit.unavailable`. `status` never refuses.
package enum DockCLIRefusal: String, CaseIterable, Sendable {
    case safeMode, needsPermission, otherTool, voiceOver

    /// `paneName` names a permission's pane as Settings shows it (the app's `PermissionFlow.paneName`).
    package func message(paneName: (Permission) -> String) -> String {
        switch self {
        case .safeMode: return L("Dock Previews is paused in Safe Mode.")
        case .needsPermission:
            return L("Dock Previews needs \(paneName(.accessibility)). Open Snaptic Settings › Permissions.")
        case .otherTool:
            return L("Dock Previews is paused while another Dock preview app runs. Choose Run Both Anyway in Dock Previews’ Advanced settings to use both.")
        case .voiceOver: return L("Dock Previews is paused while VoiceOver is on.")
        }
    }

    package var exitCode: Int32 { ControlExit.unavailable }
}

/// `dock status` in a row.
package enum DockStatusCell: Equatable, Sendable {
    /// Rows 1 and 2: not registered (exit 2).
    case unknownCommand
    /// Exit 0. `until=` is added whenever a pause is held.
    case answers(state: DockCLIState, reason: DockCLIReason?)
}

/// `dock pause [duration]` in a row.
package enum DockPauseCell: Equatable, Sendable {
    case unknownCommand
    case refused(DockCLIRefusal)
    /// Exit 0: the end becomes the later of the current one and now + duration (G2-12).
    case pauses
}

/// `dock resume` in a row.
package enum DockResumeCell: Equatable, Sendable {
    case unknownCommand
    case refused(DockCLIRefusal)
    /// Row 8: “Dock Previews is on again.” (exit 0); then the next row that applies.
    case onAgain
    /// A pause held under Starting, row 4 or row 5: “Dock Previews’ pause is cleared.” (exit 0; G3-1).
    case cleared
    /// “Dock Previews isn’t paused.” (exit 0).
    case notPaused
}

/// One row of §4.21's verb × state table. `resumeHeld` is `resume` while a command pause is held, `resume` while
/// none is. Row 8 always holds one and row 9 never does (a held pause makes row 8 apply), so their two cells agree.
package struct DockVerbCells: Equatable, Sendable {
    package let row: DockPageRow
    package let status: DockStatusCell
    package let pause: DockPauseCell
    package let resume: DockResumeCell
    package let resumeHeld: DockResumeCell
}

/// What A9's `DockCLI` does with one parsed command: the table's cell for the row, as an action. The app only applies
/// it (holds or clears the command pause, formats the reply).
package enum DockCLIStep: Equatable, Sendable {
    /// Rows 1 and 2, where nothing is registered: the house "Unknown command" (exit 2).
    case unknownCommand
    /// The refusal's line, exit `ControlExit.unavailable`.
    case refuse(DockCLIRefusal)
    /// The status line, or its JSON.
    case status(json: Bool)
    /// Hold a command pause for `seconds` (never shortening one held), then answer `pausedReply(until:)`.
    case pause(seconds: Int)
    /// Clear the held pause when `cell.clearsPause`, then answer `resumeReply(cell)`, exit 0.
    case resume(DockResumeCell)
}

extension DockResumeCell {
    /// `resume` clears the held command pause: row 8, and a pause held under Starting, row 4 or row 5 (G3-1).
    package var clearsPause: Bool { self == .onAgain || self == .cleared }
}

/// The §4.22 live counters `status --json` adds (A6a's `DockLive` and `WindowServices.liveLeases`).
package struct DockStatusLiveCounts: Equatable, Sendable {
    package var observer: Int
    package var clickTap: Int
    package var keys: Int
    package var panel: Int
    package var timers: Int
    package var leases: Int

    package init(observer: Int = 0, clickTap: Int = 0, keys: Int = 0, panel: Int = 0, timers: Int = 0,
                 leases: Int = 0) {
        self.observer = observer
        self.clickTap = clickTap
        self.keys = keys
        self.panel = panel
        self.timers = timers
        self.leases = leases
    }
}

package struct DockStatusFacts: Equatable, Sendable {
    package var state: DockCLIState
    package var reason: DockCLIReason?
    /// The held command pause's end (Unix seconds); nil while none is held.
    package var pausedUntil: Double?
    package var thumbnails: DockCLIThumbnails
    package var clickActions: DockCLIFeature
    package var keys: DockCLIFeature
    package var cacheEntries: Int
    package var cacheBytes: Int
    /// `--json` only; nil is `null`.
    package var observerAttached: Bool?
    /// `--json` only; nil is `null`.
    package var live: DockStatusLiveCounts?

    package init(state: DockCLIState, reason: DockCLIReason? = nil, pausedUntil: Double? = nil,
                 thumbnails: DockCLIThumbnails = .on, clickActions: DockCLIFeature = .off, keys: DockCLIFeature = .on,
                 cacheEntries: Int = 0, cacheBytes: Int = 0, observerAttached: Bool? = nil,
                 live: DockStatusLiveCounts? = nil) {
        self.state = state
        self.reason = reason
        self.pausedUntil = pausedUntil
        self.thumbnails = thumbnails
        self.clickActions = clickActions
        self.keys = keys
        self.cacheEntries = cacheEntries
        self.cacheBytes = cacheBytes
        self.observerAttached = observerAttached
        self.live = live
    }
}

package enum DockCommandGrammar {
    /// The verbs after "dock", in help order, with their help lines (§4.21).
    package static let verbs: [(verb: String, summary: String)] = [
        ("status", L("State, pause reason and cache counts (never names)")),
        ("pause", L("Pause Dock Previews and its Dock click actions for a while (1 h if no time is given)")),
        ("resume", L("Resume Dock Previews and its Dock click actions")),
    ]

    /// The answer to a malformed `dock` line (exit `ControlExit.usage`), as Awake's.
    package static let usage = L("Usage error. Run “snaptic help dock”.")

    /// `pause` with no duration: 1 h.
    package static let defaultPauseSeconds = 3_600
    /// `AwakeDurationGrammar`'s shortest duration (1 minute).
    package static let minPauseSeconds = 60
    /// 24 h; longer is a usage error (P2-25).
    package static let maxPauseSeconds = 86_400

    /// verb is the word after "dock". `status [--json]`; `pause [duration]`, the duration in `AwakeDurationGrammar`'s
    /// words (`30m`, `2h`, `1h30m`, `90` = minutes) from 1 minute to 24 h; `resume`. `forever`, `idle`, `until …`,
    /// `0`, anything over 24 h and any other flag are usage errors. nil = usage error (exit `ControlExit.usage`).
    package static func parse(verb: String, args: [String]) -> DockCLICommand? {
        guard args.count <= 3, args.allSatisfy({ $0.utf8.count <= 16 }) else { return nil }
        switch verb {
        case "status":
            if args.isEmpty { return .status(json: false) }
            return args == ["--json"] ? .status(json: true) : nil
        case "pause":
            if args.isEmpty { return .pause(seconds: defaultPauseSeconds) }
            guard let seconds = AwakeDurationGrammar.durationSeconds(args),
                  (minPauseSeconds...maxPauseSeconds).contains(seconds) else { return nil }
            return .pause(seconds: seconds)
        case "resume":
            return args.isEmpty ? .resume : nil
        default:
            return nil
        }
    }

    // MARK: The verb × state table (§4.21)

    /// One entry per row, in §4.17's order (Starting before row 3).
    package static let table: [DockVerbCells] = [
        DockVerbCells(row: .killSwitch, status: .unknownCommand, pause: .unknownCommand, resume: .unknownCommand,
                      resumeHeld: .unknownCommand),
        DockVerbCells(row: .off, status: .unknownCommand, pause: .unknownCommand, resume: .unknownCommand,
                      resumeHeld: .unknownCommand),
        DockVerbCells(row: .starting, status: .answers(state: .starting, reason: nil), pause: .pauses,
                      resume: .notPaused, resumeHeld: .cleared),
        DockVerbCells(row: .safeMode, status: .answers(state: .paused, reason: .safeMode), pause: .refused(.safeMode),
                      resume: .refused(.safeMode), resumeHeld: .refused(.safeMode)),
        DockVerbCells(row: .needsPermission, status: .answers(state: .needsPermission, reason: nil),
                      pause: .refused(.needsPermission), resume: .notPaused, resumeHeld: .cleared),
        DockVerbCells(row: .dockUnreadable, status: .answers(state: .unavailable, reason: .dockUnreadable),
                      pause: .pauses, resume: .notPaused, resumeHeld: .cleared),
        DockVerbCells(row: .otherTool, status: .answers(state: .paused, reason: .otherTool),
                      pause: .refused(.otherTool), resume: .refused(.otherTool), resumeHeld: .refused(.otherTool)),
        DockVerbCells(row: .voiceOver, status: .answers(state: .paused, reason: .voiceOver),
                      pause: .refused(.voiceOver), resume: .refused(.voiceOver), resumeHeld: .refused(.voiceOver)),
        DockVerbCells(row: .pausedByCommand, status: .answers(state: .paused, reason: .command), pause: .pauses,
                      resume: .onAgain, resumeHeld: .onAgain),
        DockVerbCells(row: .working, status: .answers(state: .on, reason: nil), pause: .pauses, resume: .notPaused,
                      resumeHeld: .notPaused),
    ]

    package static func cells(_ row: DockPageRow) -> DockVerbCells {
        table.first { $0.row == row } ?? table[0]
    }

    /// A9: what `command` does in `row`, with or without a held command pause. `status` never refuses; `resume`
    /// reads the held cell only while a pause is held.
    package static func step(_ command: DockCLICommand, row: DockPageRow, held: Bool) -> DockCLIStep {
        let cells = cells(row)
        switch command {
        case .status(let json):
            guard case .answers = cells.status else { return .unknownCommand }
            return .status(json: json)
        case .pause(let seconds):
            switch cells.pause {
            case .unknownCommand: return .unknownCommand
            case .refused(let refusal): return .refuse(refusal)
            case .pauses: return .pause(seconds: seconds)
            }
        case .resume:
            let cell = held ? cells.resumeHeld : cells.resume
            switch cell {
            case .unknownCommand: return .unknownCommand
            case .refused(let refusal): return .refuse(refusal)
            case .onAgain, .cleared, .notPaused: return .resume(cell)
            }
        }
    }

    /// The same, for the module's facts now: §4.17's row (`DockPageRules.row`) and whether a command pause is held.
    package static func step(_ command: DockCLICommand, facts: DockPageFacts) -> DockCLIStep {
        step(command, row: DockPageRules.row(facts), held: facts.commandPause != nil)
    }

    // MARK: Replies

    /// The pause's new end: the later of the held one and now + seconds, so a pause never shortens one already
    /// running (G2-12). A non-finite held end counts as none.
    package static func pauseEnd(current: Double?, now: Double, seconds: Int) -> Double {
        let proposed = now + Double(max(0, min(seconds, maxPauseSeconds)))
        guard let current, current.isFinite else { return proposed }
        return max(current, proposed)
    }

    /// “Dock Previews is paused until 2026-11-12T20:45:00Z.”; nil for an end no ISO time can name.
    package static func pausedReply(until unix: Double) -> String? {
        guard let end = AwakeCommandGrammar.isoUTC(unix) else { return nil }
        return L("Dock Previews is paused until \(end).")
    }

    /// The line of a `resume` cell that answers exit 0; nil for the others.
    package static func resumeReply(_ cell: DockResumeCell) -> String? {
        switch cell {
        case .onAgain: return L("Dock Previews is on again.")
        case .cleared: return L("Dock Previews’ pause is cleared.")
        case .notPaused: return L("Dock Previews isn’t paused.")
        case .unknownCommand, .refused: return nil
        }
    }

    // MARK: Status

    /// `state=<…> reason=<…|-> until=<ISO|-> thumbnails=<…> clickActions=<…> keys=<…> cacheEntries=<n>
    /// cacheBytes=<n>`.
    package static func statusLine(_ s: DockStatusFacts) -> String {
        "state=\(s.state.rawValue) reason=\(s.reason?.rawValue ?? "-") until=\(until(s.pausedUntil) ?? "-") "
            + "thumbnails=\(s.thumbnails.rawValue) clickActions=\(s.clickActions.rawValue) keys=\(s.keys.rawValue) "
            + "cacheEntries=\(count(s.cacheEntries)) cacheBytes=\(count(s.cacheBytes))"
    }

    /// One JSON object with a fixed key order: the plain line's keys, then `observerAttached` and the live counters.
    /// The counters nest under `live`, because `keys` is already the keyboard state. An absent value is `null`.
    package static func statusJSON(_ s: DockStatusFacts) -> String {
        func string(_ value: String?) -> String { value.map { "\"" + $0 + "\"" } ?? "null" }
        var parts: [String] = []
        parts.append("\"state\":" + string(s.state.rawValue))
        parts.append("\"reason\":" + string(s.reason?.rawValue))
        parts.append("\"until\":" + string(until(s.pausedUntil)))
        parts.append("\"thumbnails\":" + string(s.thumbnails.rawValue))
        parts.append("\"clickActions\":" + string(s.clickActions.rawValue))
        parts.append("\"keys\":" + string(s.keys.rawValue))
        parts.append("\"cacheEntries\":" + String(count(s.cacheEntries)))
        parts.append("\"cacheBytes\":" + String(count(s.cacheBytes)))
        parts.append("\"observerAttached\":" + (s.observerAttached.map { $0 ? "true" : "false" } ?? "null"))
        if let live = s.live {
            let counters = [("observer", live.observer), ("clickTap", live.clickTap), ("keys", live.keys),
                            ("panel", live.panel), ("timers", live.timers), ("leases", live.leases)]
            parts.append("\"live\":{" + counters.map { "\"\($0.0)\":" + String(count($0.1)) }.joined(separator: ",")
                         + "}")
        } else {
            parts.append("\"live\":null")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func until(_ unix: Double?) -> String? {
        unix.flatMap { AwakeCommandGrammar.isoUTC($0) }
    }

    private static func count(_ n: Int) -> Int { max(0, n) }
}

extension DockPageFacts {
    /// Facts in which `DockPageRules.row` is `row`, for walking the verb × state table without starting the module
    /// (`--selftest-controls` starts none, §4.22). `commandPause` is held under every row but Working, where a held
    /// pause would make row 8 apply; row 8 holds one with no end when none is given.
    package static func reaching(_ row: DockPageRow, commandPause: DockCommandPause? = nil) -> DockPageFacts {
        var f = DockPageFacts(commandPause: commandPause)
        switch row {
        case .killSwitch: f.killSwitch = true
        case .off: f.enabled = false
        case .safeMode: f.safeMode = true
        case .needsPermission: f.accessibility = false
        case .starting: f.read = .starting
        case .dockUnreadable: f.read = .unreadable
        case .otherTool: f.runningBundleIDs = KnownDockTools.all.prefix(1).map(\.bundleID)
        case .voiceOver: f.voiceOverOn = true
        case .pausedByCommand: f.commandPause = commandPause ?? DockCommandPause(untilUnix: 0, clock: "")
        case .working: f.commandPause = nil
        }
        return f
    }
}
