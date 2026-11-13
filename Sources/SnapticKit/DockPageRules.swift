import Foundation

// Dock Previews' states (lead; PLAN 0.5 §4.17, §4.19, §4.21; G2-2, G2-5, G2-6, G2-9, G3-1, X2-16). Pure: the first
// row that applies wins; the module's pause and its precedence; the page's status row and added rows; the Snaptic
// menu section; the `dock status` state, reason and until; the attention mark. The verb × state replies are
// `DockCommandGrammar`'s (K5). The app reads the module and builds rows from this.

/// Why the module is paused (§4.17 rows 3, 6, 7 and 8), in precedence order: the first that holds wins.
package enum DockPauseReason: String, CaseIterable, Sendable {
    case safeMode
    case otherTool
    case voiceOver
    case command

    /// The pause that wins among those that hold.
    package static func winning(safeMode: Bool, otherTool: Bool, voiceOver: Bool, command: Bool) -> DockPauseReason? {
        allCases.first {
            switch $0 {
            case .safeMode: safeMode
            case .otherTool: otherTool
            case .voiceOver: voiceOver
            case .command: command
            }
        }
    }
}

/// How far the Dock observer got (§4.8).
package enum DockReadState: String, CaseIterable, Sendable {
    /// Between `start()` and the first attach.
    case starting
    case attached
    case unreadable
}

/// A `dock pause` that's held (§4.21). It isn't saved, so a relaunch resumes.
package struct DockCommandPause: Equatable, Sendable {
    /// Wall-clock end, for `until=<ISO>`.
    package var untilUnix: Double
    /// The end as the app formats it for the page and menu ("3:45 PM").
    package var clock: String

    package init(untilUnix: Double, clock: String) {
        self.untilUnix = untilUnix
        self.clock = clock
    }
}

/// What decides the state. `now` and `unreadableSince` are monotonic seconds.
package struct DockPageFacts: Equatable, Sendable {
    package var killSwitch: Bool
    package var enabled: Bool
    package var safeMode: Bool
    package var accessibility: Bool
    package var read: DockReadState
    package var loginLadderEnded: Bool
    /// When the Dock was first found unreadable, for row 5's 2-minute attention wait.
    package var unreadableSince: Double?
    package var now: Double
    /// Bundle ids of running apps; only `KnownDockTools` ids count.
    package var runningBundleIDs: [String]
    package var runAlongsideOtherTools: Bool
    package var voiceOverOn: Bool
    package var showWithVoiceOver: Bool
    /// The click pop-up isn't Do Nothing.
    package var clickActionOn: Bool
    package var restoreAllOn: Bool
    package var commandPause: DockCommandPause?
    /// `paneName(.accessibility)`.
    package var paneName: String
    package var thumbnailsOn: Bool
    package var screenRecording: Bool
    package var clickBreakerTripped: Bool
    package var keysBreakerTripped: Bool
    /// Display names of the features the crash guard stopped, in §4.12's table order.
    package var crashGuardStops: [String]
    /// Display names of the features stopped by a second poisoning, in §4.12's table order.
    package var poisoned: [String]

    package init(killSwitch: Bool = false, enabled: Bool = true, safeMode: Bool = false, accessibility: Bool = true,
                 read: DockReadState = .attached, loginLadderEnded: Bool = true, unreadableSince: Double? = nil,
                 now: Double = 0, runningBundleIDs: [String] = [], runAlongsideOtherTools: Bool = false,
                 voiceOverOn: Bool = false, showWithVoiceOver: Bool = false, clickActionOn: Bool = false,
                 restoreAllOn: Bool = false, commandPause: DockCommandPause? = nil,
                 paneName: String = "Accessibility", thumbnailsOn: Bool = false, screenRecording: Bool = true,
                 clickBreakerTripped: Bool = false, keysBreakerTripped: Bool = false, crashGuardStops: [String] = [],
                 poisoned: [String] = []) {
        self.killSwitch = killSwitch
        self.enabled = enabled
        self.safeMode = safeMode
        self.accessibility = accessibility
        self.read = read
        self.loginLadderEnded = loginLadderEnded
        self.unreadableSince = unreadableSince
        self.now = now
        self.runningBundleIDs = runningBundleIDs
        self.runAlongsideOtherTools = runAlongsideOtherTools
        self.voiceOverOn = voiceOverOn
        self.showWithVoiceOver = showWithVoiceOver
        self.clickActionOn = clickActionOn
        self.restoreAllOn = restoreAllOn
        self.commandPause = commandPause
        self.paneName = paneName
        self.thumbnailsOn = thumbnailsOn
        self.screenRecording = screenRecording
        self.clickBreakerTripped = clickBreakerTripped
        self.keysBreakerTripped = keysBreakerTripped
        self.crashGuardStops = crashGuardStops
        self.poisoned = poisoned
    }
}

/// §4.17's rows, in the order they're tried. Starting sits after row 4: it holds when rows 1–4 don't apply and
/// row 5 doesn't yet.
package enum DockPageRow: String, CaseIterable, Sendable {
    case killSwitch
    case off
    case safeMode
    case needsPermission
    case starting
    case dockUnreadable
    case otherTool
    case voiceOver
    case pausedByCommand
    case working
}

/// A button on the status row or an added row.
package enum DockPageAction: String, CaseIterable, Sendable {
    case openPrivacy
    case tryAgain
    /// Opens the Advanced sheet at “When another app shows Dock previews” (row 6).
    case advancedOtherTools
    /// Opens the Advanced sheet at “Show previews while VoiceOver is on” (row 7).
    case advancedVoiceOver
    case resume
    case relaunch

    package var title: String {
        switch self {
        case .openPrivacy: L("Open Privacy Settings…")
        case .tryAgain: L("Try Again")
        case .advancedOtherTools, .advancedVoiceOver: L("Advanced…")
        case .resume: L("Resume")
        case .relaunch: L("Relaunch Snaptic")
        }
    }
}

/// An added row under the status row; it never replaces it.
package struct DockPageNote: Equatable, Sendable {
    package var text: String
    package var warning: Bool
    package var action: DockPageAction?

    package init(_ text: String, warning: Bool = true, action: DockPageAction? = nil) {
        self.text = text
        self.warning = warning
        self.action = action
    }
}

/// The status row. `text` is nil in rows 1 and 2 (the app shows `DefaultsLockRow` or `FeatureHighlights`) and in
/// row 9 (no row).
package struct DockPageStatus: Equatable, Sendable {
    package var row: DockPageRow
    package var text: String?
    package var warning: Bool
    package var action: DockPageAction?
    package var notes: [DockPageNote]

    package init(row: DockPageRow, text: String?, warning: Bool = false, action: DockPageAction? = nil,
                 notes: [DockPageNote] = []) {
        self.row = row
        self.text = text
        self.warning = warning
        self.action = action
        self.notes = notes
    }
}

/// One row of the Snaptic menu's Dock Previews section (§4.19), in order.
package enum DockMenuItem: Equatable, Sendable {
    /// A status line (disabled).
    case status(String)
    /// “Open \(paneName) Settings…”.
    case openPane(String)
    case pauseForOneHour
    case resume
    case settings

    package var title: String {
        switch self {
        case let .status(text): text
        case let .openPane(pane): L("Open \(pane) Settings…")
        case .pauseForOneHour: L("Pause Dock Previews for 1 Hour")
        case .resume: L("Resume Dock Previews")
        case .settings: L("Dock Previews Settings…")
        }
    }
}

/// `dock status`'s `state` (§4.21).
package enum DockCLIState: String, CaseIterable, Sendable {
    case on
    case starting
    case paused
    case needsPermission
    case unavailable
}

/// `dock status`'s `reason` (§4.21).
package enum DockCLIReason: String, CaseIterable, Sendable {
    case safeMode
    case otherTool
    case voiceOver
    case command
    case dockUnreadable
}

/// `dock status`'s first three fields.
package struct DockCLIStatus: Equatable, Sendable {
    package var state: DockCLIState
    package var reason: DockCLIReason?
    /// ISO UTC, whenever a command pause is held; the reason stays the row's.
    package var until: String?

    package init(state: DockCLIState, reason: DockCLIReason? = nil, until: String? = nil) {
        self.state = state
        self.reason = reason
        self.until = until
    }
}

package enum DockPageRules {
    /// Row 5's attention mark waits this long (X2-16).
    package static let unreadableAttentionDelay = 120.0

    /// The first row that applies.
    package static func row(_ f: DockPageFacts) -> DockPageRow {
        if f.killSwitch { return .killSwitch }
        if !f.enabled { return .off }
        if f.safeMode { return .safeMode }
        if !f.accessibility { return .needsPermission }
        switch f.read {
        case .starting: return .starting
        case .unreadable: return f.loginLadderEnded ? .dockUnreadable : .starting
        case .attached: break
        }
        if otherTool(f) != nil { return .otherTool }
        if voiceOverPauses(f) { return .voiceOver }
        if f.commandPause != nil { return .pausedByCommand }
        return .working
    }

    /// The running known tool row 6 names: the first in `KnownDockTools.all` order. Nil when Run Both is chosen.
    package static func otherTool(_ f: DockPageFacts) -> KnownDockTool? {
        guard !f.runAlongsideOtherTools else { return nil }
        let running = Set(f.runningBundleIDs)
        return KnownDockTools.all.first { running.contains($0.bundleID) }
    }

    /// VoiceOver is on and “Show previews with VoiceOver” is off (G2-5).
    package static func voiceOverPauses(_ f: DockPageFacts) -> Bool { f.voiceOverOn && !f.showWithVoiceOver }

    /// The pause the module sends as `pauseChanged`: rows 3, 6, 7 and 8 only. Rows 4, 5 and Starting have no hover
    /// to pause.
    package static func pause(_ f: DockPageFacts) -> DockPauseReason? {
        switch row(f) {
        case .safeMode: .safeMode
        case .otherTool: .otherTool
        case .voiceOver: .voiceOver
        case .pausedByCommand: .command
        default: nil
        }
    }

    /// A command pause is held under Starting, row 4 or row 5, where row 8 doesn't show (G3-1).
    package static func heldPauseUnder(_ f: DockPageFacts) -> Bool {
        guard f.commandPause != nil else { return false }
        return [.starting, .needsPermission, .dockUnreadable].contains(row(f))
    }

    package static func status(_ f: DockPageFacts) -> DockPageStatus {
        let r = row(f)
        var status = main(r, f)
        if r != .killSwitch && r != .off { status.notes = notes(f) }
        return status
    }

    private static func main(_ r: DockPageRow, _ f: DockPageFacts) -> DockPageStatus {
        switch r {
        case .killSwitch, .off, .working:
            return DockPageStatus(row: r, text: nil)
        case .starting:
            return DockPageStatus(row: r, text: L("Starting…"))
        case .safeMode:
            return DockPageStatus(row: r, text: L("Paused in Safe Mode"))
        case .needsPermission:
            return DockPageStatus(row: r, text: L("Dock Previews needs \(f.paneName) to read the Dock."),
                                  warning: true, action: .openPrivacy)
        case .dockUnreadable:
            return DockPageStatus(row: r, text: L("Dock Previews can’t read the Dock. It tries again when the Dock restarts."),
                                  warning: true, action: .tryAgain)
        case .otherTool:
            let name = otherTool(f)?.name ?? ""
            return DockPageStatus(row: r, text: L("Paused while \(name) runs"), action: .advancedOtherTools)
        case .voiceOver:
            let text = f.clickActionOn || f.restoreAllOn
                ? L("Previews are paused while VoiceOver is on. Dock click actions still work.")
                : L("Paused while VoiceOver is on")
            return DockPageStatus(row: r, text: text, action: .advancedVoiceOver)
        case .pausedByCommand:
            return DockPageStatus(row: r, text: pausedUntil(f), action: .resume)
        }
    }

    /// The added rows, in §4.17's order.
    private static func notes(_ f: DockPageFacts) -> [DockPageNote] {
        var notes: [DockPageNote] = []
        if f.thumbnailsOn && !f.screenRecording {
            notes.append(DockPageNote(L("Window thumbnails need Screen Recording. Until then, previews show window titles."),
                                      action: .openPrivacy))
        }
        if f.clickBreakerTripped {
            notes.append(DockPageNote(L("Dock click actions stopped because macOS turned them off 3 times. Relaunch Snaptic to use them again."),
                                      action: .relaunch))
        }
        if f.keysBreakerTripped {
            notes.append(DockPageNote(L("Keyboard shortcuts in previews stopped because macOS turned them off 3 times. Relaunch Snaptic to use them again."),
                                      action: .relaunch))
        }
        for feature in f.crashGuardStops {
            notes.append(DockPageNote(L("\(feature) stopped after a problem in macOS. Snaptic tries again after a macOS update."),
                                      action: .tryAgain))
        }
        for feature in f.poisoned {
            notes.append(DockPageNote(L("\(feature) stopped because macOS answered in a way Snaptic didn’t expect. Quit and reopen Snaptic to try again.")))
        }
        if heldPauseUnder(f) {
            notes.append(DockPageNote(pausedUntil(f), warning: false, action: .resume))
        }
        return notes
    }

    private static func pausedUntil(_ f: DockPageFacts) -> String {
        let clock = f.commandPause?.clock ?? ""
        return L("Paused until \(clock)")
    }

    /// The Snaptic menu's section (§4.19). Empty in rows 1 and 2.
    package static func menu(_ f: DockPageFacts) -> [DockMenuItem] {
        let r = row(f)
        if r == .killSwitch || r == .off { return [] }
        let held = heldPauseUnder(f)
        var items: [DockMenuItem] = []
        switch r {
        case .safeMode: items.append(.status(L("Paused in Safe Mode")))
        case .needsPermission: items.append(.status(L("Needs Permission")))
        case .dockUnreadable: items.append(.status(L("Can’t read the Dock")))
        case .otherTool:
            let name = otherTool(f)?.name ?? ""
            items.append(.status(L("Paused while \(name) runs")))
        case .voiceOver: items.append(.status(L("Paused while VoiceOver is on")))
        case .pausedByCommand: items.append(.status(pausedUntil(f)))
        default: break
        }
        if held { items.append(.status(pausedUntil(f))) }
        if r == .needsPermission { items.append(.openPane(f.paneName)) }
        if r == .working {
            items.append(.pauseForOneHour)
        } else if r == .pausedByCommand || held {
            items.append(.resume)
        }
        items.append(.settings)
        return items
    }

    /// `dock status`'s state, reason and until. Nil in rows 1 and 2 (the verb isn't registered: exit 2).
    package static func cli(_ f: DockPageFacts) -> DockCLIStatus? {
        let until = f.commandPause.flatMap { AwakeCommandGrammar.isoUTC($0.untilUnix) }
        switch row(f) {
        case .killSwitch, .off: return nil
        case .starting: return DockCLIStatus(state: .starting, until: until)
        case .safeMode: return DockCLIStatus(state: .paused, reason: .safeMode, until: until)
        case .needsPermission: return DockCLIStatus(state: .needsPermission, until: until)
        case .dockUnreadable: return DockCLIStatus(state: .unavailable, reason: .dockUnreadable, until: until)
        case .otherTool: return DockCLIStatus(state: .paused, reason: .otherTool, until: until)
        case .voiceOver: return DockCLIStatus(state: .paused, reason: .voiceOver, until: until)
        case .pausedByCommand: return DockCLIStatus(state: .paused, reason: .command, until: until)
        case .working: return DockCLIStatus(state: .on, until: until)
        }
    }

    /// The menu-bar attention mark: row 4, row 5 after 2 minutes, or a tripped breaker (§4.17).
    package static func attention(_ f: DockPageFacts) -> Bool {
        switch row(f) {
        case .killSwitch, .off: return false
        case .needsPermission: return true
        case .dockUnreadable:
            if let since = f.unreadableSince, f.now - since >= unreadableAttentionDelay { return true }
        default: break
        }
        return f.clickBreakerTripped || f.keysBreakerTripped
    }
}
