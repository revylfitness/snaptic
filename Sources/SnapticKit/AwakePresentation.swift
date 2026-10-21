import Foundation

// What Awake shows (owner: G; PLAN 0.3 §2.5 toasts, §5.3, §5.4, design M8, R5-10, R5-11): holder summaries, end and
// last-end texts, the switch header's detail lines, the status item's title and accessibility label, the Awake menu's
// row plan and the Rules submenu selection, and the diagnostics section; since 0.3.1 (owner: T-lid-kit) also the
// lid-closed mode rows and words (B0–B3.4) and the `tab` style (A4). App names, holder names and rule names come from
// the app (local UI only); nothing here reaches logs or the CLI.

/// "Held by Terminal (2)" (N17): holders grouped by name in first-seen order; nil names are "the command line".
package enum AwakeHolderText {
    package static let commandLine = L("the command line")

    /// Groups as (name, count), first-seen order.
    package static func groups(_ names: [String?]) -> [(name: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for raw in names {
            let n = raw.flatMap { $0.isEmpty ? nil : $0 } ?? commandLine
            if counts[n] == nil { order.append(n) }
            counts[n, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    /// "Held by Terminal", "Held by Terminal (2)", "Held by Terminal and Xcode", "Held by Terminal, Xcode, and iTerm";
    /// nil without holders.
    package static func summary(_ names: [String?]) -> String? {
        let g = groups(names)
        guard !g.isEmpty else { return nil }
        let parts = g.map { $0.count > 1 ? "\($0.name) (\($0.count))" : $0.name }
        return L("Held by ") + list(parts)
    }

    /// "Terminal is still keeping your Mac awake." / "Terminal and Xcode are still keeping your Mac awake." (R5-10).
    package static func stillKeeping(_ names: [String?]) -> String {
        let g = groups(names)
        let parts = g.map(\.name)
        let subject = parts.isEmpty ? capitalizedFirst(commandLine) : capitalizedFirst(list(parts))
        let plural = parts.count > 1
        return subject + (plural ? L(" are still keeping your Mac awake.") : L(" is still keeping your Mac awake."))
    }

    /// "A", "A and B", "A, B, and C" (serial comma).
    package static func list(_ parts: [String]) -> String { SentenceText.list(parts) }

    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + String(s.dropFirst())
    }
}

/// End toasts and the 12-hour "last end" line (§2.5).
package enum AwakeEndText {
    /// Ends worth a "last end" line: the session stopped for a reason other than its own natural end.
    package static func isInterruption(_ reason: AwakeEndReason) -> Bool {
        switch reason {
        case .batteryLow, .adapterDisconnected, .lowPowerMode, .thermal, .systemSleep, .userSwitch, .lockedTooLong,
             .assertionFailed, .commandLineOff, .lidEnded:
            return true
        case .user, .timeUp, .appQuit, .processExited, .tasksFinished, .replaced, .triggerEnded, .moduleStopped,
             .safeMode, .reboot:
            return false
        }
    }

    /// The short reason ("battery below 20%", "Xcode quit").
    package static func phrase(_ reason: AwakeEndReason, floor: Int, appName: String?, lockedHours: Int?) -> String {
        switch reason {
        case .user: return L("turned off")
        case .timeUp: return L("time is up")
        case .appQuit: return (appName.map { $0.isEmpty ? nil : $0 } ?? nil).map { $0 + L(" quit") } ?? L("the app quit")
        case .processExited: return L("the process ended")
        case .tasksFinished: return L("downloads and tasks finished")
        case .replaced: return L("another session started")
        case .triggerEnded: return L("the rule no longer applies")
        case .batteryLow: return L("battery below \(floor)%")
        case .adapterDisconnected: return L("power adapter disconnected")
        case .lowPowerMode: return L("Low Power Mode turned on")
        case .thermal: return L("your Mac got too hot")
        case .systemSleep: return L("your Mac went to sleep")
        case .userSwitch: return L("you switched users")
        case .lockedTooLong:
            if let h = lockedHours { return L("the screen was locked for ") + AwakeCountdown.unit(h, L("hour"), L("hours")) }
            return L("the screen was locked too long")
        case .moduleStopped: return L("Awake was turned off")
        case .safeMode: return L("Snaptic restarted in Safe Mode")
        case .reboot: return L("your Mac restarted")
        case .assertionFailed: return L("Snaptic couldn’t keep your Mac awake")
        case .commandLineOff: return L("command-line control was turned off")
        case .lidEnded: return L("lid-closed mode turned off while the lid was closed")
        }
    }

    /// The toast for a manual session's non-user end; nil for ends that show none (the user's own, a replacement,
    /// rule ends, module stop, Safe Mode, reboot).
    package static func toast(_ reason: AwakeEndReason, floor: Int, appName: String?, lockedHours: Int?) -> String? {
        switch reason {
        case .user, .replaced, .triggerEnded, .moduleStopped, .safeMode, .reboot:
            return nil
        case .assertionFailed:
            return L("Snaptic couldn’t keep your Mac awake. Try again, or restart Snaptic.")
        case .batteryLow:
            return L("Awake ended: battery is below \(floor)%.")
        default:
            return L("Awake ended: ") + phrase(reason, floor: floor, appName: appName, lockedHours: lockedHours) + "."
        }
    }

    /// "Ended at 3:12 AM: battery below 20%." (`clock` is the end time the app formatted).
    package static func lastEnd(_ reason: AwakeEndReason, clock: String, floor: Int, lockedHours: Int?) -> String {
        L("Ended at ") + clock + ": " + phrase(reason, floor: floor, appName: nil, lockedHours: lockedHours) + "."
    }

    /// The idle detail while a guard holds: "Ended because the battery is below 20%."
    package static func holding(_ reason: AwakeEndReason, floor: Int) -> String? {
        switch reason {
        case .batteryLow: return L("Ended because the battery is below \(floor)%.")
        case .thermal: return L("Ended because your Mac got too hot.")
        case .lowPowerMode: return L("Ended because Low Power Mode is on.")
        case .adapterDisconnected: return L("Ended because the power adapter was disconnected.")
        default: return nil
        }
    }

    /// The guard refusal toast that carries Start Anyway (§2.5): "Battery is below 20%."
    package static func refusal(_ reason: AwakeEndReason, floor: Int) -> String {
        switch reason {
        case .batteryLow: return L("Battery is below \(floor)%.")
        case .lowPowerMode: return L("Low Power Mode is on.")
        case .thermal: return L("Your Mac is too hot to keep awake right now.")
        case .adapterDisconnected: return L("The power adapter is disconnected.")
        default: return L("Awake can’t start right now.")
        }
    }
}

/// Why a saved-on Awake feature doesn't run (ux N2): a kill switch (`Awake.disable.<feature>`; it outlasts Safe
/// Mode, so it is named first) or Safe Mode's removals. nil = nothing locks it.
package enum AwakeFeatureLock: Equatable, Sendable {
    case killSwitch, safeMode

    package static func of(_ f: AwakeFeature, killSwitches: Set<AwakeFeature>, safeMode: Bool) -> AwakeFeatureLock? {
        if killSwitches.contains(f) && !AwakeFeatureGraph.unkillable.contains(f) { return .killSwitch }
        if safeMode && AwakeFeatureGraph.safeModeRemoves.contains(f) { return .safeMode }
        return nil
    }

    /// The first lock of `features` in order (a feature and what it requires, e.g. pointer movement and activity).
    package static func first(_ features: [AwakeFeature], killSwitches: Set<AwakeFeature>,
                              safeMode: Bool) -> (feature: AwakeFeature, lock: AwakeFeatureLock)? {
        for f in features {
            if let lock = of(f, killSwitches: killSwitches, safeMode: safeMode) { return (f, lock) }
        }
        return nil
    }

    /// The row note: "Paused in Safe Mode." or the one kill-switch wording.
    package var text: String {
        switch self {
        case .safeMode: return L("Paused in Safe Mode.")
        case .killSwitch: return DefaultsLock.text
        }
    }

    /// The Awake page's Safe Mode row: what is paused and what still works (sessions do, §2.6 N14).
    package static let safeModeStatus = L("Safe Mode is on. Rules, Appear active, and Drive Alive are paused; sessions you start still work.")
    /// Above the rules list while rules can't run.
    package static func rulesNote(_ lock: AwakeFeatureLock) -> String {
        switch lock {
        case .safeMode: return L("Rules don’t run in Safe Mode.")
        case .killSwitch: return DefaultsLock.text
        }
    }
}

/// Why activity and Drive Alive stopped (§2.6, awake-correctness F2): the unreadable-battery toast and the status
/// line, naming only what is in use.
package enum AwakeBackgroundText {
    /// The one toast when the battery becomes unreadable; nil when neither activity nor Drive Alive is in use.
    package static func unreadableToast(activity: Bool, drives: Bool) -> String? {
        switch (activity, drives) {
        case (true, true): return L("Snaptic can’t read the battery level, so it stopped appearing active and keeping drives awake.")
        case (true, false): return L("Snaptic can’t read the battery level, so it stopped appearing active.")
        case (false, true): return L("Snaptic can’t read the battery level, so it stopped keeping drives awake.")
        case (false, false): return nil
        }
    }

    /// "Appear active and Drive Alive are paused: your Mac is too hot."; nil when nothing in use is stopped.
    package static func paused(_ block: AwakeBackgroundBlock?, activity: Bool, drives: Bool) -> String? {
        guard let block else { return nil }
        let subject: String
        switch (activity, drives) {
        case (true, true): subject = L("Appear active and Drive Alive are paused")
        case (true, false): subject = L("Appear active is paused")
        case (false, true): subject = L("Drive Alive is paused")
        case (false, false): return nil
        }
        let reason: String
        switch block {
        case .heat: reason = L("your Mac is too hot")
        case .batteryUnreadable: reason = L("Snaptic can’t read the battery level")
        case .batteryLow: reason = L("the battery is low")
        }
        return subject + ": " + reason + "."
    }
}

/// The switch header's detail lines (§5.3): a primary line for what governs, then the single most relevant extra.
package struct AwakeDetailInput: Equatable, Sendable {
    package var governing: AwakeGoverning
    package var now: ClockNow
    /// The end time formatted by the app ("3:45 PM"); nil without an end.
    package var endClock: String?
    /// whileApp: the app's name.
    package var appName: String?
    /// The governing rule's name.
    package var ruleName: String?
    /// The active rule waiting behind a manual session ("Then “Desk dock” keeps it awake.").
    package var nextRuleName: String?
    /// "Held by Terminal (2)" (holds under any source).
    package var holderSummary: String?
    /// untilIdle: seconds of the current quiet run; nil while busy.
    package var quietFor: Double?
    package var activity: AwakeActivityMode
    package var activityCapped: Bool
    package var stopAfterHours: Int
    /// On battery or without an external display while active (§2.12).
    package var lidWarning: Bool
    /// Idle: "Ended at 3:12 AM: battery below 20%." or the guard-holding line.
    package var idleNote: String?
    /// "Appear active is paused: Snaptic can't read the battery level." (`AwakeBackgroundText.paused`).
    package var backgroundPaused: String?
    /// 0.3.1 B1: lid-closed mode is on (the lid line comes first; no lid warning).
    package var lidModeOn: Bool = false
    /// 0.3.1 B1: the cap's end time ("6:40 PM") when the cap ends before the session (`AwakeLidPolicy.capEndsFirst`).
    package var lidUntilClock: String?
    /// 0.3.1 B1: which `lidRoute` line the Settings status row shows after the lid warning.
    package var lidRoute: AwakeLidRoute = .unavailable
    /// 0.3.1 B1: "Lid-closed mode ended at 3:12 AM: battery at 20%." (`AwakeLidText.lastEnd`), kept 12 h and cleared
    /// at the next turn-on; nil while the mode is on, or when the leftover rows already explain the state (B2).
    package var lidLastEnd: String?

    package init(governing: AwakeGoverning, now: ClockNow, endClock: String? = nil, appName: String? = nil,
                 ruleName: String? = nil, nextRuleName: String? = nil, holderSummary: String? = nil,
                 quietFor: Double? = nil, activity: AwakeActivityMode = .off, activityCapped: Bool = false,
                 stopAfterHours: Int = 1, lidWarning: Bool = false, idleNote: String? = nil,
                 backgroundPaused: String? = nil, lidModeOn: Bool = false, lidUntilClock: String? = nil,
                 lidRoute: AwakeLidRoute = .unavailable, lidLastEnd: String? = nil) {
        self.governing = governing
        self.now = now
        self.endClock = endClock
        self.appName = appName
        self.ruleName = ruleName
        self.nextRuleName = nextRuleName
        self.holderSummary = holderSummary
        self.quietFor = quietFor
        self.activity = activity
        self.activityCapped = activityCapped
        self.stopAfterHours = stopAfterHours
        self.lidWarning = lidWarning
        self.idleNote = idleNote
        self.backgroundPaused = backgroundPaused
        self.lidModeOn = lidModeOn
        self.lidUntilClock = lidUntilClock
        self.lidRoute = lidRoute
        self.lidLastEnd = lidLastEnd
    }
}

package enum AwakeDetail {
    /// The switch header holds two secondary lines.
    package static let maxLines = 2

    package static func quoted(_ s: String?) -> String { "“" + (s ?? "") + "”" }

    /// "Until 3:45 PM · 1h 12m left", "Until turned off", "While Xcode is running", "Until downloads and tasks
    /// finish", "While “Desk dock” applies", "Held by Terminal (2)"; nil while idle.
    package static func primary(_ i: AwakeDetailInput) -> String? {
        switch i.governing {
        case .inactive:
            return nil
        case .manual(let s):
            let left = AwakeClock.remaining(s, now: i.now).map { AwakeCountdown.short(max(0, $0)) + L(" left") }
            switch s.kind {
            case .indefinite:
                return L("Until turned off")
            case .duration, .until:
                return [i.endClock.map { L("Until ") + $0 }, left].compactMap { $0 }.joined(separator: " · ")
            case .whileApp:
                let base = L("While ") + (i.appName ?? L("the app")) + L(" is running")
                return [base, left.map { L("at most ") + $0 }].compactMap { $0 }.joined(separator: " · ")
            case .untilIdle:
                let base = L("Until downloads and tasks finish")
                return [base, left.map { L("at most ") + $0 }].compactMap { $0 }.joined(separator: " · ")
            }
        case .trigger:
            return L("While ") + quoted(i.ruleName) + L(" applies")
        case .holds:
            return i.holderSummary ?? L("Held by the command line")
        }
    }

    /// Extra lines in priority order, each only while true. Lid-closed mode's line comes first (0.3.1 B1).
    package static func extras(_ i: AwakeDetailInput) -> [String] {
        var out: [String] = []
        if i.lidModeOn && i.governing.isActive { out.append(AwakeLidText.headerLine(untilClock: i.lidUntilClock)) }
        // The mode ended under a session that goes on: say so first (idle, `lines` shows it after the idle note).
        if !i.lidModeOn && i.governing.isActive, let ended = i.lidLastEnd { out.append(ended) }
        if case .manual(let s) = i.governing, case .untilIdle(let spec, _) = s.kind {
            let quiet = AwakeCountdown.unit(max(1, spec.sanitized().quietSeconds / 60), L("min"), L("min"))
            var line = L("Ends after ") + quiet + L(" with no activity")
            if let q = i.quietFor, q >= 60 {
                line += L(" · quiet for ") + AwakeCountdown.unit(Int(min(q, 1e9) / 60), L("min"), L("min"))
            }
            out.append(line)
        }
        if case .manual = i.governing, let next = i.nextRuleName {
            out.append(L("Then ") + quoted(next) + L(" keeps it awake."))
        }
        switch i.governing {
        case .manual, .trigger:
            if let h = i.holderSummary { out.append(h) }
        case .holds, .inactive:
            break
        }
        if i.governing.isActive {
            if let paused = i.backgroundPaused {
                out.append(paused)
            } else if i.activityCapped {
                let span = AwakeCountdown.unit(max(1, i.stopAfterHours), L("hour"), L("hours"))
                out.append(L("Stopped appearing active after ") + span + ".")
            } else if i.activity == .nudge {
                out.append(L("Moving the pointer"))
            } else if i.activity == .declare {
                out.append(L("Appearing active"))
            }
            if i.lidWarning && !i.lidModeOn { out.append(L("Closing the lid will put your Mac to sleep.")) }
        }
        return out
    }

    /// The lid warning's rule (0.3.1 B1): closing the lid would sleep the Mac, lid-closed mode is off, and the Mac is on
    /// battery or has no external display. Re-evaluated on `lidWillSleep`, screen and lid-mode changes.
    package static func showsLidWarning(lidWillSleep: Bool?, lidModeOn: Bool, onBattery: Bool,
                                        externalDisplay: Bool) -> Bool {
        lidWillSleep == true && !lidModeOn && (onBattery || !externalDisplay)
    }

    /// At most `maxLines` lines: the primary line and the first extra; idle shows `idleNote`, then the lid-closed
    /// mode's last end (0.3.1).
    package static func lines(_ i: AwakeDetailInput) -> [String] {
        guard let p = primary(i) else {
            return Array([i.idleNote, i.lidModeOn ? nil : i.lidLastEnd].compactMap { $0 }.prefix(maxLines))
        }
        return Array(([p] + extras(i)).prefix(maxLines))
    }
}

/// The Awake status item's title and spoken label (§5.3, design M8).
package enum AwakeIndicatorText {
    /// nil = glyph only. Time Remaining / End Time show for manual sessions with an end (timed and capped).
    package static func title(style: AwakeIndicatorStyle, governing: AwakeGoverning, remaining: Double?,
                              endClock: String?) -> String? {
        guard case .manual = governing, let r = remaining else { return nil }
        switch style {
        case .icon: return nil
        case .iconAndTime: return AwakeCountdown.short(max(0, r))
        case .iconAndEndTime: return endClock
        }
    }

    /// "Awake, 1 hour 42 minutes remaining" / "Awake, until turned off" / "Awake, held by Terminal" / "Awake, off";
    /// while lid-closed mode is on, ", even with the lid closed" follows (0.3.1 B1; the tooltip uses the same label).
    package static func accessibilityLabel(governing: AwakeGoverning, remaining: Double?, appName: String?,
                                           ruleName: String?, holderSummary: String?, lidModeOn: Bool = false) -> String {
        let label = baseLabel(governing: governing, remaining: remaining, appName: appName, ruleName: ruleName,
                              holderSummary: holderSummary)
        return lidModeOn && governing.isActive ? label + AwakeLidText.statusSuffix : label
    }

    private static func baseLabel(governing: AwakeGoverning, remaining: Double?, appName: String?, ruleName: String?,
                                  holderSummary: String?) -> String {
        let prefix = L("Awake, ")
        switch governing {
        case .inactive:
            return prefix + L("off")
        case .manual(let s):
            if let r = remaining { return prefix + AwakeCountdown.spoken(max(0, r)) }
            switch s.kind {
            case .whileApp: return prefix + L("while ") + (appName ?? L("the app")) + L(" is running")
            case .untilIdle: return prefix + L("until downloads and tasks finish")
            case .indefinite, .duration, .until: return prefix + L("until turned off")
            }
        case .trigger:
            return prefix + L("while ") + AwakeDetail.quoted(ruleName) + L(" applies")
        case .holds:
            let h = holderSummary ?? L("Held by the command line")
            return prefix + h.prefix(1).lowercased() + String(h.dropFirst())
        }
    }
}

/// One row of the Awake menu or the compact section (§5.3, §5.4); the app turns each into a MenuKit item.
package enum AwakeMenuRow: Equatable, Sendable {
    case header
    /// The default preset as a verb phrase (idle, and in the holds-only state).
    case startDefault
    case turnOff
    case addTime(seconds: Int)
    case keepDisplayOn
    case endHolds
    case startSession
    case whileApp
    case rules
    case settings
    case separator
    /// 0.3.1 B1: "Keep Awake with the Lid Closed…" in a menu or Settings session, ✓ while on, or a pending row.
    case lidClosed(LidRowState)
    /// 0.3.1 B1: the idle "Keep Awake with the Lid Closed ›" submenu: these presets (each "…"), then Custom….
    case lidSubmenu([StableID])
}

/// The lid row's state (0.3.1 B0, B1, B3.0).
package enum LidRowState: String, Equatable, Sendable {
    /// "Keep Awake with the Lid Closed…" (asks for the password).
    case off
    /// "✓ Keep Awake with the Lid Closed" (turning it off asks nothing).
    case on
    /// Disabled: "Waiting for Password…", "Turning On…", "Turning Off…".
    case authorizing, verifying, stopping
    /// Disabled: "Finishing Earlier Session…" (an earlier session's journal is still pending, B3.4).
    case finishingEarlier
}

/// Which menu the Awake rows are for (0.3.1 A4): Awake's own menu, the compact section (Awake is the Snaptic menu's
/// only module), or Awake's tab (the own rows minus Awake Settings…).
package enum AwakeMenuStyle: String, CaseIterable, Sendable {
    case own, compact, tab
}

package struct AwakeMenuFacts: Equatable, Sendable {
    package var governing: AwakeGoverning
    /// Holds exist (also under another source).
    package var holdsExist: Bool
    /// Rules › shows: ≥ 1 rule exists and `triggers` is effective.
    package var rulesShown: Bool
    /// 0.3.1 A4: replaces 0.3's `compact: Bool`.
    package var style: AwakeMenuStyle
    /// 0.3.1 B1: the lid rows' facts; nil while lid-closed mode isn't available (no lid row then).
    package var lid: AwakeLidMenuFacts?

    /// The compact section in the Snaptic menu (no separators, no Settings item). Kept for 0.3 callers and tests.
    package var compact: Bool {
        get { style == .compact }
        set { style = newValue ? .compact : .own }
    }

    package init(governing: AwakeGoverning, holdsExist: Bool, rulesShown: Bool, style: AwakeMenuStyle) {
        self.governing = governing
        self.holdsExist = holdsExist
        self.rulesShown = rulesShown
        self.style = style
    }

    package init(governing: AwakeGoverning, holdsExist: Bool, rulesShown: Bool, compact: Bool) {
        self.init(governing: governing, holdsExist: holdsExist, rulesShown: rulesShown, style: compact ? .compact : .own)
    }

    /// 0.3.1 B1: with the lid facts, so `AwakeMenuModel.rows` places the lid row itself (nil: no lid row).
    package init(governing: AwakeGoverning, holdsExist: Bool, rulesShown: Bool, style: AwakeMenuStyle,
                 lid: AwakeLidMenuFacts?) {
        self.init(governing: governing, holdsExist: holdsExist, rulesShown: rulesShown, style: style)
        self.lid = lid
    }
}

package enum AwakeMenuModel {
    /// The two Add Time steps (consistency m4: one label everywhere).
    package static let addSteps = [900, 3_600]

    /// The rows in order. Idle: header, the default preset, Start Session ›, While an App Is Running ›, Rules ›,
    /// Awake Settings…. Active: Turn Off Keep Awake in the default item's slot, then Add 15 Minutes / Add 1 Hour (timed
    /// and capped manual sessions), ✓ Keep Display On (manual and rule sessions), End Command-Line Holds (holds under
    /// another source). Holds only: Turn Off (it ends the stack) and the default preset (adds a session beside them).
    /// 0.3.1 B1: the lid row (`lidRow`) follows the default preset, or ✓ Keep Display On while a session or rule
    /// governs. Styles (A4): `compact` has no separators and no Awake Settings…; `tab` is `own` without Awake
    /// Settings… and the separator before it.
    package static func rows(_ f: AwakeMenuFacts) -> [AwakeMenuRow] {
        var rows: [AwakeMenuRow] = [.header]
        let lid = lidRow(f.lid, governing: f.governing)
        if !f.compact { rows.append(.separator) }
        switch f.governing {
        case .inactive:
            rows.append(.startDefault)
            if let lid { rows.append(lid) }
        case .holds:
            rows.append(.turnOff)
            rows.append(.startDefault)
            if let lid { rows.append(lid) }
        case .manual(let s):
            rows.append(.turnOff)
            if AwakeClock.canExtend(s) { rows += addSteps.map { .addTime(seconds: $0) } }
            rows.append(.keepDisplayOn)
            if let lid { rows.append(lid) }
            if f.holdsExist { rows.append(.endHolds) }
        case .trigger:
            rows.append(.turnOff)
            rows.append(.keepDisplayOn)
            if let lid { rows.append(lid) }
            if f.holdsExist { rows.append(.endHolds) }
        }
        rows.append(.startSession)
        rows.append(.whileApp)
        if f.rulesShown {
            if !f.compact { rows.append(.separator) }
            rows.append(.rules)
        }
        if f.style == .own {
            rows.append(.separator)
            rows.append(.settings)
        }
        return rows
    }

    /// The lid row (0.3.1 B1), also for the Settings pull-downs: ✓ while on; the pending text while a request or an
    /// earlier session's journal is pending (disabled); "Keep Awake with the Lid Closed…" in a manual session started
    /// from the menu or Settings in this process; otherwise (idle, or any other governing state) the idle submenu.
    /// nil while the mode isn't available.
    package static func lidRow(_ lid: AwakeLidMenuFacts?, governing: AwakeGoverning) -> AwakeMenuRow? {
        guard let lid else { return nil }
        switch lid.state {
        case .on, .authorizing, .verifying, .stopping, .finishingEarlier:
            return .lidClosed(lid.state)
        case .off:
            if lid.sessionTakesMode, case .manual = governing { return .lidClosed(.off) }
            return .lidSubmenu(lid.presets)
        }
    }
}

/// What the lid rows need (0.3.1 B1).
package struct AwakeLidMenuFacts: Equatable, Sendable {
    /// `AwakeLidMode.rowState`, or `.finishingEarlier` while an earlier session's journal is pending (B3.4) and the
    /// mode is off.
    package var state: LidRowState
    /// The governing manual session was started from the menu or Settings in this process
    /// (`AwakeLidGate.addsToSession`), so the mode is added to it.
    package var sessionTakesMode: Bool
    /// The idle submenu's presets, in preset order.
    package var presets: [StableID]

    package init(state: LidRowState, sessionTakesMode: Bool, presets: [StableID]) {
        self.state = state
        self.sessionTakesMode = sessionTakesMode
        self.presets = presets
    }

    /// The facts from what the app knows; nil (no lid row) unless the feature is effective (`available`: turned on,
    /// available, not killed, not in Safe Mode). `sessionTakesMode` is `AwakeLidGate.addsToSession` for the governing
    /// manual session (false while none governs).
    package static func make(available: Bool, mode: AwakeLidMode, recovery: AwakeLidRecovery, sessionTakesMode: Bool,
                             presets: [StableID]) -> AwakeLidMenuFacts? {
        guard available else { return nil }
        return AwakeLidMenuFacts(state: rowState(mode: mode, recovery: recovery), sessionTakesMode: sessionTakesMode,
                                 presets: presets)
    }

    /// The row state from the mode and the recovery: the mode's own state first; while it is off, a pending journal
    /// shows "Finishing Earlier Session…".
    package static func rowState(mode: AwakeLidMode, recovery: AwakeLidRecovery) -> LidRowState {
        let s = mode.rowState
        return s == .off && recovery == .pending ? .finishingEarlier : s
    }
}

/// The Rules submenu (§5.3): active rules plus up to four others, in list order; and its subtitle.
package enum AwakeRulesMenu {
    package static let maxOthers = 4

    package enum State: Equatable, Sendable { case active, waiting, idle, off }

    package static func visible(_ triggers: [AwakeTrigger], active: [StableID], waiting: [StableID])
        -> [(id: StableID, state: State)] {
        var others = 0
        var out: [(id: StableID, state: State)] = []
        for t in triggers {
            let state: State = !t.enabled ? .off : active.contains(t.id) ? .active : waiting.contains(t.id) ? .waiting : .idle
            if state == .active {
                out.append((t.id, state))
            } else if others < maxOthers {
                others += 1
                out.append((t.id, state))
            }
        }
        return out
    }

    /// "Paused until 4:00 PM" (whatever runs, R5-11), "Desk dock is active", "Waiting for Desk dock", or nil.
    package static func subtitle(pausedUntilClock: String?, activeName: String?, waitingName: String?) -> String? {
        if let p = pausedUntilClock { return L("Paused until ") + p }
        if let a = activeName { return a + L(" is active") }
        if let w = waitingName { return L("Waiting for ") + w }
        return nil
    }
}

/// The Awake section of the diagnostics report (§3.6): counts and states only, never names, ids, pids or times.
package struct AwakeDiagnosticsFacts: Equatable, Sendable {
    package var effective: Set<AwakeFeature>
    package var governing: AwakeStatusSource?
    package var kind: AwakeHistoryKind?
    package var assertion: AwakeAssertionType
    package var assertionErrors: Int
    package var guardHolding: AwakeEndReason?
    package var activeServices: [AwakeServiceID]
    package var holds: Int
    package var rules: Int
    package var conditionsByKind: [AwakeCriterionKind: Int]
    package var eventCounts: [String: Int]
    package var drives: Int
    /// `Awake.disable.<feature>` keys that are set (fixed ids only), so an administrator can tell a kill switch from
    /// the user's own switch; unkillable ones are dropped, since they change nothing (review7 security N1).
    package var killSwitches: Set<AwakeFeature>
    /// 0.3.1: lid-closed mode's state (nil while the feature isn't effective) and whether sleep was found left off
    /// by an earlier session (B3.4). States only: no token, pid or time.
    package var lid: LidRowState?
    package var lidLeftover: Bool

    package init(effective: Set<AwakeFeature>, governing: AwakeStatusSource?, kind: AwakeHistoryKind?,
                 assertion: AwakeAssertionType, assertionErrors: Int, guardHolding: AwakeEndReason?,
                 activeServices: [AwakeServiceID], holds: Int, rules: Int,
                 conditionsByKind: [AwakeCriterionKind: Int], eventCounts: [String: Int], drives: Int,
                 killSwitches: Set<AwakeFeature> = [], lid: LidRowState? = nil, lidLeftover: Bool = false) {
        self.lid = lid
        self.lidLeftover = lidLeftover
        self.killSwitches = killSwitches.subtracting(AwakeFeatureGraph.unkillable)
        self.effective = effective
        self.governing = governing
        self.kind = kind
        self.assertion = assertion
        self.assertionErrors = assertionErrors
        self.guardHolding = guardHolding
        self.activeServices = activeServices
        self.holds = holds
        self.rules = rules
        self.conditionsByKind = conditionsByKind
        self.eventCounts = eventCounts
        self.drives = drives
    }
}

package enum AwakeDiagnosticsReport {
    /// Stable, sorted lines (no locale): "Awake features: history, indicator, sessions".
    package static func lines(_ f: AwakeDiagnosticsFacts) -> [String] {
        var out: [String] = []
        out.append("Awake features: " + f.effective.map(\.rawValue).sorted().joined(separator: ", "))
        let killed = f.killSwitches.map(\.rawValue).sorted()
        out.append("Awake kill switches: " + (killed.isEmpty ? "none" : killed.joined(separator: ", ")))
        out.append("Awake governing: " + (f.governing?.rawValue ?? "inactive") + (f.kind.map { " (" + $0.rawValue + ")" } ?? ""))
        out.append("Awake assertion: " + f.assertion.rawValue + (f.assertionErrors > 0 ? " (\(f.assertionErrors) errors)" : ""))
        out.append("Awake guard: " + (f.guardHolding?.rawValue ?? "none"))
        out.append("Awake services: " + f.activeServices.map(\.rawValue).joined(separator: ", "))
        out.append("Awake holds: \(f.holds)")
        let kinds = f.conditionsByKind.filter { $0.value > 0 }.map { "\($0.key.rawValue) \($0.value)" }.sorted()
        out.append("Awake rules: \(f.rules)" + (kinds.isEmpty ? "" : " (" + kinds.joined(separator: ", ") + ")"))
        out.append("Awake drives: \(f.drives)")
        if f.lid != nil || f.lidLeftover {
            out.append("Awake lid-closed mode: " + (f.lid?.rawValue ?? "unavailable") + (f.lidLeftover ? " (leftover)" : ""))
        }
        for (key, n) in f.eventCounts.sorted(by: { $0.key < $1.key }) where n > 0 {
            out.append("Awake event \(key): \(n)")
        }
        return out
    }
}

// MARK: - Settings status row (§4.3 Awake "Status", R5-9, R5-10, R5-11)

/// A button of the status row on the Awake page, in order. None is a default button (r3 security L8).
package enum AwakeStatusButton: Equatable, Sendable {
    /// Pause Rules ▾ (For 1 Hour / Until Tomorrow): whenever a rule exists and rules aren't paused.
    case pauseRules
    /// Resume: in Pause Rules ▾'s slot while rules are paused (R5-11).
    case resumeRules
    /// Keep Awake ▾: click = the default session, ▾ = presets, While an App Is Running ▸, Custom… (R5-9).
    case keepAwake
    /// Options ▾ while a session or rule governs.
    case options
    /// Turn Off, also in the holds-only state, where it ends the hold stack (R5-10).
    case turnOff
}

/// One entry of the status row's Options ▾.
package enum AwakeOptionsItem: Equatable, Sendable {
    case addTime(seconds: Int)
    /// Add Time… (the custom panel in extend mode).
    case addTimeCustom
    case separator
    /// ✓ Keep Display On, always while a session or rule governs.
    case keepDisplayOn
    /// End Command-Line Holds: only while holds exist under another governing source (R5-10).
    case endHolds
    /// Replace With ▸: the Keep Awake list (R5-9).
    case replaceWith
}

package struct AwakeStatusRowFacts: Equatable, Sendable {
    package var governing: AwakeGoverning
    /// Holds exist (under any source).
    package var holdsExist: Bool
    /// ≥ 1 rule exists and `triggers` is effective.
    package var rulesExist: Bool
    package var rulesPaused: Bool

    package init(governing: AwakeGoverning, holdsExist: Bool, rulesExist: Bool, rulesPaused: Bool) {
        self.governing = governing
        self.holdsExist = holdsExist
        self.rulesExist = rulesExist
        self.rulesPaused = rulesPaused
    }
}

package enum AwakeStatusPlan {
    /// Idle: [Pause Rules ▾] [Keep Awake ▾]. Session or rule: [Pause Rules ▾] [Options ▾] [Turn Off]. Holds only:
    /// [Pause Rules ▾] [Keep Awake ▾] [Turn Off] — a start adds a manual session beside the holds, like the menus'
    /// default-preset item (§5.3, R5-9: every session kind starts from Settings alone). Paused: Resume in Pause
    /// Rules ▾'s slot.
    package static func buttons(_ f: AwakeStatusRowFacts) -> [AwakeStatusButton] {
        var out: [AwakeStatusButton] = []
        if f.rulesExist { out.append(f.rulesPaused ? .resumeRules : .pauseRules) }
        switch f.governing {
        case .inactive: out.append(.keepAwake)
        case .holds: out += [.keepAwake, .turnOff]
        case .manual, .trigger: out += [.options, .turnOff]
        }
        return out
    }

    /// Options ▾: Add 15 Minutes, Add 1 Hour, Add Time… (timed and capped manual sessions); ─; ✓ Keep Display On;
    /// End Command-Line Holds (holds under this source); ─; Replace With ▸. Empty while idle or holds-only.
    package static func options(_ f: AwakeStatusRowFacts) -> [AwakeOptionsItem] {
        var out: [AwakeOptionsItem] = []
        switch f.governing {
        case .inactive, .holds:
            return []
        case .manual(let s):
            if AwakeClock.canExtend(s) {
                out += AwakeMenuModel.addSteps.map { AwakeOptionsItem.addTime(seconds: $0) }
                out += [.addTimeCustom, .separator]
            }
        case .trigger:
            break
        }
        out.append(.keepDisplayOn)
        if f.holdsExist { out.append(.endHolds) }
        out += [.separator, .replaceWith]
        return out
    }
}

/// The status row's text: one primary line and secondary details, each only while true.
package enum AwakeStatusText {
    package static let idle = L("Your Mac can sleep as usual.")
    /// After the lid line: how macOS keeps a Mac awake with its lid closed (closed-display mode). The 0.3 text, still
    /// the `unavailable` variant.
    package static let lidRoute = L("To keep it awake with the lid closed, connect power and an external display.")

    /// 0.3.1 B1: the `lidRoute` line by lid-closed mode's state (0.3.3: the switch moved to the Awake page).
    package static func lidRoute(_ route: AwakeLidRoute) -> String {
        switch route {
        case .featureOff:
            return L("To keep it awake with the lid closed, connect power and an external display, or turn on lid-closed mode in Awake settings.")
        case .available:
            return L("To keep it awake with the lid closed, connect power and an external display, or choose Keep Awake with the Lid Closed in the Awake menu.")
        case .unavailable:
            return lidRoute
        }
    }

    /// "Keeping your Mac awake until 3:45 PM", "…until turned off", "…while Xcode is running", "…until downloads
    /// and tasks finish", "…while “Desk dock” applies", "Held by Terminal (2)"; idle: "Your Mac can sleep as usual."
    package static func primary(_ i: AwakeDetailInput) -> String {
        let keeping = L("Keeping your Mac awake")
        switch i.governing {
        case .inactive:
            return idle
        case .manual(let s):
            switch s.kind {
            case .indefinite: return keeping + L(" until turned off")
            case .duration, .until: return i.endClock.map { keeping + L(" until ") + $0 } ?? keeping
            case .whileApp: return keeping + L(" while ") + (i.appName ?? L("the app")) + L(" is running")
            case .untilIdle: return keeping + L(" until downloads and tasks finish")
            }
        case .trigger:
            return keeping + L(" while ") + AwakeDetail.quoted(i.ruleName) + L(" applies")
        case .holds:
            return i.holderSummary ?? L("Held by the command line")
        }
    }

    /// "1h 12m left" (timed) or "At most 1h 12m left" (capped app and task sessions), then the extras of the switch
    /// header (quiet time, the rule that takes over, holders, activity, lid), the paused line, and while idle the
    /// last end or guard line.
    package static func details(_ i: AwakeDetailInput, pausedUntilClock: String?) -> [String] {
        var out: [String] = []
        if case .manual(let s) = i.governing, let r = AwakeClock.remaining(s, now: i.now) {
            let left = AwakeCountdown.short(max(0, r)) + L(" left")
            switch s.kind {
            case .whileApp, .untilIdle: out.append(L("At most ") + left)
            case .indefinite, .duration, .until: out.append(left)
            }
        }
        out += AwakeDetail.extras(i)
        // §1.4 closed-display mode: the native route, where there is room for it (the menu header keeps 2 lines).
        if i.lidWarning && !i.lidModeOn { out.append(lidRoute(i.lidRoute)) }
        if !i.governing.isActive, let note = i.idleNote { out.append(note) }
        if !i.governing.isActive && !i.lidModeOn, let ended = i.lidLastEnd { out.append(ended) }
        // Drive Alive runs without a session too: say why it stopped while idle as well.
        if !i.governing.isActive, let paused = i.backgroundPaused { out.append(paused) }
        if let p = pausedUntilClock { out.append(L("Rules are paused until ") + p + ".") }
        return out
    }
}

/// A rule row's trailing state on the Awake page: "Active", "Waiting" or "Off" (nothing while it simply waits for
/// its conditions).
package enum AwakeRuleRowText {
    package static func state(enabled: Bool, active: Bool, waiting: Bool) -> String? {
        if !enabled { return L("Off") }
        if active { return L("Active") }
        if waiting { return L("Waiting") }
        return nil
    }
}

/// Where the Settings status row's `lidRoute` line points (0.3.1 B1).
package enum AwakeLidRoute: String, CaseIterable, Sendable {
    /// The feature is off: turn it on in Awake settings (the Awake page's Lid closed section, 0.3.3).
    case featureOff
    /// On and available: choose it in the Awake menu.
    case available
    /// Translocated, no lid, no battery, the kill switch, or Safe Mode (the Awake page's switch is missing or locked):
    /// the 0.3 text.
    case unavailable
}

/// Lid-closed mode's words (0.3.1 B0–B3.4): the menus, Settings, toasts, VoiceOver and the History suffix. The
/// password dialogs' texts are `LidWatchdog.promptText(floor:)` and `restorePromptText`; the refusals are
/// `AwakeLidRefusal.text`.
package enum AwakeLidText {
    // MARK: Names (B0)

    /// The submenu, and the row while on (shown with a checkmark: turning it off asks nothing).
    package static let title = L("Keep Awake with the Lid Closed")
    /// The row in a menu or Settings session: asks for the password.
    package static let action = L("Keep Awake with the Lid Closed…")
    /// The idle submenu's last item: the Custom… panel with lid-closed mode turned on.
    package static let custom = L("Custom…")
    /// The Awake page's setting (0.3.3; Advanced's until then) and the Custom… panel's toggle.
    package static let setting = L("Keep awake with the lid closed")
    package static let settingHelp = L("Choose Keep Awake with the Lid Closed in the Awake menu. Asks for an administrator password each time.")
    /// 0.3.3: the same setting on the Menu Bar page, under Awake's rows; it names what it adds to the Awake menu.
    package static let menuBarSetting = L("Show Keep Awake with the Lid Closed in the Awake menu")
    package static let menuBarHelp = L("Turns on lid-closed mode, the same switch as on the Awake page. Choosing it in the menu asks for an administrator password each time.")
    package static let customHelp = L("Start… asks for an administrator password.")
    /// The Custom… panel's button while the toggle is on.
    package static let customStart = L("Start…")
    /// The Awake page's section title (0.3.3).
    package static let section = L("Lid closed")
    package static let learnMore = L("Learn More…")
    /// The translocated row (B1), also the refusal's toast.
    package static let translocated = L("Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode.")

    /// A preset in the idle submenu: its title and "…" (each asks for a password).
    package static func presetTitle(_ title: String) -> String { title + "…" }

    /// The row's title by state (B0).
    package static func rowTitle(_ state: LidRowState) -> String {
        switch state {
        case .off: return action
        case .on: return title
        case .authorizing: return L("Waiting for Password…")
        case .verifying: return L("Turning On…")
        case .stopping: return L("Turning Off…")
        case .finishingEarlier: return L("Finishing Earlier Session…")
        }
    }

    /// Pending rows are disabled.
    package static func rowEnabled(_ state: LidRowState) -> Bool { state == .off || state == .on }
    /// The row carries a checkmark while on.
    package static func rowChecked(_ state: LidRowState) -> Bool { state == .on }

    /// The Lid closed section's footer (B1; on the Awake page from 0.3.3), before its Learn More… link.
    package static var footer: String {
        L("While lid-closed mode is on, your Mac can’t sleep for low battery or heat. Awake turns it off at the Awake page’s battery level (at least 10%), when your Mac gets hot, or after ")
            + capSpan + L(". Use it on a hard surface, not in a bag.")
    }

    /// "24 hours" (`AwakeCountdown.unit`).
    package static var capSpan: String { AwakeCountdown.unit(LidWatchdog.capSeconds / 3_600, L("hour"), L("hours")) }

    // MARK: Status (B1)

    /// The accessibility label's and N11's suffix while the mode is on.
    package static let statusSuffix = L(", even with the lid closed")

    /// The header's and status row's first extra while on: the cap's clock when the cap ends first.
    package static func headerLine(untilClock: String?) -> String {
        untilClock.map { L("Stays awake with the lid closed until ") + $0 } ?? L("Stays awake with the lid closed")
    }

    /// "Lid-closed mode ended at 3:12 AM: battery at 20%." (kept 12 h, cleared at the next turn-on); nil for ends the
    /// user chose or that another line explains.
    package static func lastEnd(_ end: AwakeLidEnd, clock: String, floor: Int) -> String? {
        guard let phrase = endPhrase(end, floor: floor) else { return nil }
        return L("Lid-closed mode ended at ") + clock + ": " + phrase + "."
    }

    /// The "ended at" phrase: battery, heat, the time limit, another app, quitting, or a watchdog that stopped for a
    /// reason the app couldn't see (r2 A2-1).
    package static func endPhrase(_ end: AwakeLidEnd, floor: Int) -> String? {
        switch end {
        case .battery: return L("battery at \(floor)%")
        case .heat: return L("your Mac got hot")
        case .cap: return L("time limit reached")
        case .otherApp: return L("another app turned sleep back on")
        case .quit: return L("Snaptic quit")
        case .watchdogLost: return L("it stopped unexpectedly")
        case .user, .sessionEnded, .replaced, .safeMode, .featureOff, .moduleStopped: return nil
        }
    }

    // MARK: Toasts and VoiceOver (B1, B3)

    /// After 2 s of verifying.
    package static let verifying = L("Turning on lid-closed mode…")
    /// The Custom… panel's Start… while the mode can't be requested (r2 A2-2); the panel stays open.
    package static let customUnavailable = L("Lid-closed mode isn’t available right now. To start without it, turn off “Keep awake with the lid closed”.")

    /// The Custom… panel's Start… while another lid request is under way (r2 A2-2): a sentence, not the bare row
    /// title; nil for the states that aren't pending.
    package static func pendingToast(_ state: LidRowState) -> String? {
        switch state {
        case .authorizing: return L("Lid-closed mode is waiting for a password. Try again in a moment.")
        case .verifying: return L("Lid-closed mode is turning on. Try again in a moment.")
        case .stopping: return L("Lid-closed mode is turning off. Try again in a moment.")
        case .finishingEarlier: return AwakeLidRefusal.journalPending.text
        case .off, .on: return nil
        }
    }
    package static let couldNotTurnOn = L("Snaptic couldn’t turn on lid-closed mode. Try again.")
    /// `check` found sleep already turned off (exit 3, or the preflight read 1).
    package static let alreadyOff = L("Sleep is already turned off for this Mac by another app or command, so it stays awake with the lid closed.")
    /// An idle-submenu start that replaced another governing session.
    package static let replaced = L("Replaced the running session.")
    package static let capWarning = L("Lid-closed mode turns off in 5 minutes. If the lid is closed then, your Mac goes to sleep.")
    package static let voiceOverOn = L("Keeping your Mac awake with the lid closed.")
    package static let voiceOverOff = L("Lid-closed mode turned off.")

    /// The toast when the mode ends but the session goes on (B3.1 step 7, B3.3); nil for the other ends. While the
    /// lid is shut the session ends too (`AwakeLidPolicy.endsSession`) and its `.lidEnded` toast shows instead.
    package static func endToast(_ end: AwakeLidEnd, floor: Int) -> String? {
        switch end {
        case .cap:
            return L("Lid-closed mode turned off after ") + capSpan
                + L(". Awake is still on; your Mac sleeps if you close the lid.")
        case .battery: return L("Lid-closed mode turned off at \(floor)% battery.")
        case .heat: return L("Lid-closed mode turned off because your Mac got hot.")
        case .otherApp: return L("Another app turned sleep back on, so lid-closed mode stopped.")
        case .watchdogLost:
            // Nothing has checked yet that sleep is back on: the leftover rows follow if it isn't (r3 U3-1).
            return L("Lid-closed mode stopped unexpectedly. Awake is still on.")
        case .user, .sessionEnded, .replaced, .quit, .safeMode, .featureOff, .moduleStopped: return nil
        }
    }

    // MARK: Leftovers (B3.4)

    /// The menus' status row and its action (never Keep Sleep Off in a menu).
    package static let menuLeftover = L("Sleep Is Turned Off")
    package static let turnSleepBackOn = L("Turn Sleep Back On…")
    /// The Awake page's and Other Apps' row, and the toast when Awake isn't running.
    package static let leftover = L("Your Mac can’t sleep. This may be from an earlier lid-closed session that didn’t finish.")
    package static let keepSleepOff = L("Keep Sleep Off")
    package static let notNow = L("Not Now")
    package static let openAwakeSettings = L("Open Awake Settings…")
    /// Turn Sleep Back On… couldn't run or its script failed (r1 C4); Cancel is silent.
    package static let couldNotTurnSleepBackOn = L("Snaptic couldn’t turn sleep back on. Try again.")

    /// The menus' Turn Sleep Back On… row (r1 U7): while a restore waits for its password it shows the B0 pending
    /// text and is disabled, like the Awake page's buttons.
    package static func restoreRow(restoring: Bool) -> (title: String, enabled: Bool) {
        restoring ? (rowTitle(.authorizing), false) : (turnSleepBackOn, true)
    }

    // MARK: History (B1)

    /// The subtitle's suffix for an entry with lid-closed mode.
    package static let historySuffix = L(" · Lid closed")
}
