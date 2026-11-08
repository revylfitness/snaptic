import Foundation

// The hidden list (lead; PLAN 0.4 §4.8, A6). Pure: which rows the Snaptic-menu section and the arrow's menu show,
// what each row is called, what a press needs first and whether the icon read at press time is still the row's.
// The app reads the layout, the app names and the screens, and builds MenuKit rows from this.

/// One row: one extra another app owns.
package struct IconsListRow: Equatable, Sendable {
    package var extra: IconsExtra
    package var section: IconsSection
    package var title: String
    /// The frame came from a read in which the extra was in the menu bar, so a press may match it by position.
    /// An extra Length had pushed off the screen only matches by size.
    package var frameKnown: Bool

    package init(extra: IconsExtra, section: IconsSection, title: String, frameKnown: Bool) {
        self.extra = extra
        self.section = section
        self.title = title
        self.frameKnown = frameKnown
    }
}

/// The rows, by header.
package struct IconsHiddenList: Equatable, Sendable {
    /// **HIDDEN (n)**: Hidden and Always Hidden, nearest the arrow first.
    package var hidden: [IconsListRow]
    /// **BEHIND THE NOTCH (n)**: shown icons a notch covers, per screen.
    package var behindNotch: [IconsListRow]
    /// **Shown Icons ›**.
    package var shown: [IconsListRow]

    package init(hidden: [IconsListRow] = [], behindNotch: [IconsListRow] = [], shown: [IconsListRow] = []) {
        self.hidden = hidden
        self.behindNotch = behindNotch
        self.shown = shown
    }

    /// **No Hidden Icons** shows instead of both headers.
    package var isEmpty: Bool { hidden.isEmpty && behindNotch.isEmpty }
}

/// What the list's slot in the menu shows.
package enum IconsListContent: Equatable, Sendable {
    case rows(IconsHiddenList)
    /// 14–26 without Accessibility: **Allow Accessibility to List Icons…** (opens Permissions; never prompts).
    case allowAccessibility
    /// 27 without Accessibility: **Needs Permission**, disabled.
    case needsPermission
    /// Paused or unavailable: the reason, disabled.
    case reason(String)
    /// Length with `Icons.disable.inventory`: hiding works, but nothing can be listed.
    case none
}

/// What decides the slot.
package struct IconsListFacts: Equatable, Sendable {
    /// Nil while the engine is unavailable.
    package var engine: IconsEngineKind?
    package var state: IconsEngineState
    package var access: IconsAccessState
    package var pausedFor: KnownMenuBarHider?
    package var examPaused: Bool
    /// `Icons.disable.inventory`.
    package var inventoryOff: Bool

    package init(engine: IconsEngineKind?, state: IconsEngineState, access: IconsAccessState,
                 pausedFor: KnownMenuBarHider? = nil, examPaused: Bool = false, inventoryOff: Bool = false) {
        self.engine = engine
        self.state = state
        self.access = access
        self.pausedFor = pausedFor
        self.examPaused = examPaused
        self.inventoryOff = inventoryOff
    }
}

package enum IconsHiddenListRules {
    /// Polls for the extra's frame to be in the menu bar after an expand (§4.8).
    package static let pollInterval: Double = 0.03
    package static let readyWait: Double = 0.3
    /// A press that opens no window within this counts `icons.pressNoop`.
    package static let noopWindow: Double = 0.5
    /// How far the extra read at press time may be from the row's frame.
    package static let matchTolerance: Double = 4
    /// Opening a menu asks for a background re-read at most this often.
    package static let refreshInterval: Double = 5

    // MARK: Slot

    /// Reasons first (paused, unavailable), then permission, then the rows.
    package static func content(_ facts: IconsListFacts, list: () -> IconsHiddenList) -> IconsListContent {
        if let reason = reason(facts) { return .reason(reason) }
        guard let engine = facts.engine else { return .none }
        if facts.access.needsPermission {
            return engine == .native ? .needsPermission : .allowAccessibility
        }
        if engine == .length, facts.inventoryOff { return .none }
        return .rows(list())
    }

    /// The disabled reason row (§4.17's status strings), or nil when nothing is paused or unavailable.
    package static func reason(_ facts: IconsListFacts) -> String? {
        if let hider = facts.pausedFor { return L("Paused while \(hider.name) runs") }
        if facts.examPaused { return L("Paused during an exam session") }
        guard case .unavailable(let why) = facts.state else { return nil }
        return unavailableText(why)
    }

    /// Settings' status line for an unavailable engine, or nil once the module stopped.
    package static func unavailableText(_ reason: IconsUnavailableReason) -> String? {
        switch reason {
        case .killSwitch, .inventoryOff:
            return L("Hidden Icons is turned off on this Mac, so your icons stay shown.")
        case .shimUnavailable:
            return L("Hidden Icons isn’t available on this version of macOS. Your icons stay shown.")
        case .shimPoisoned, .disabledBuild, .timeouts:
            return L("Hidden Icons stopped using the macOS 27 method after a problem, so your icons stay shown.")
        case .identity:
            return L("Move Snaptic to Applications to hide icons.")
        case .stopped:
            return nil
        }
    }

    // MARK: Rows

    /// The rows of `layout`. Placed extras keep the resolver's order (nearest the boundary first). On Length while
    /// collapsed a fresh read finds the hidden extras off the screen: they're listed after the placed ones, in bar
    /// order from the boundary, under their app's section. Zero-size extras are dropped.
    ///
    /// - Parameters:
    ///   - names: the app name per pid (`NSRunningApplication.localizedName`). A missing name reads "App".
    ///   - screens: every display, for Behind the Notch.
    package static func list(_ layout: IconsLayout?, names: [Int32: String], screens: [IconsScreen],
                             rightToLeft: Bool) -> IconsHiddenList {
        guard let layout else { return IconsHiddenList() }
        var seen: Set<ExtraKey> = []
        var placed: [IconsPlacedExtra] = []
        for row in layout.extras where !row.extra.frame.isDegenerate && seen.insert(ExtraKey(row.extra)).inserted {
            placed.append(row)
        }
        var pushed: [(IconsExtra, IconsSection)] = []
        // Every extra the read found counts toward "several", listed or not.
        var all = placed.map(\.extra)
        for extra in layout.offScreen where !extra.frame.isDegenerate && seen.insert(ExtraKey(extra)).inserted {
            all.append(extra)
            if let bundle = extra.bundleID, let section = layout.sections[bundle], section != .shown {
                pushed.append((extra, section))
            }
        }
        // The hidden side is left of the boundary in LTR, so its nearest icon has the largest x.
        pushed.sort { a, b in
            if a.0.frame.midX != b.0.frame.midX {
                return rightToLeft ? a.0.frame.midX < b.0.frame.midX : a.0.frame.midX > b.0.frame.midX
            }
            return a.0.pid != b.0.pid ? a.0.pid < b.0.pid : a.0.index < b.0.index
        }

        let counts = Dictionary(all.map { ($0.pid, 1) }, uniquingKeysWith: +)
        func row(_ extra: IconsExtra, _ section: IconsSection, known: Bool) -> IconsListRow {
            IconsListRow(extra: extra, section: section,
                         title: title(extra, appName: names[extra.pid], several: (counts[extra.pid] ?? 0) > 1),
                         frameKnown: known)
        }

        let hiddenPlaced = placed.filter { $0.section != .shown }.sorted(by: nearestFirst)
        let hidden = hiddenPlaced.map { row($0.extra, $0.section, known: true) }
            + pushed.map { row($0.0, $0.1, known: false) }
        let shownRows = placed.filter { $0.section == .shown }.sorted(by: nearestFirst)
        let split = IconsNotch.split(shownRows, screens: screens)
        return IconsHiddenList(hidden: hidden,
                               behindNotch: split.behindNotch.map { row($0.extra, .shown, known: true) },
                               shown: split.clear.map { row($0.extra, .shown, known: true) })
    }

    /// "App", or "App — Title" when the app has several extras (the AX title, or "Icon n" by position).
    package static func title(_ extra: IconsExtra, appName: String?, several: Bool) -> String {
        let name = appName.flatMap { $0.isEmpty ? nil : $0 } ?? L("App")
        guard several else { return name }
        let own = extra.title.flatMap { t -> String? in
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == name ? nil : trimmed
        }
        return name + " — " + (own ?? L("Icon \(extra.index + 1)"))
    }

    /// **HIDDEN (n)** and **BEHIND THE NOTCH (n)** (the header style draws them small; the count is the row count).
    package static func hiddenHeader(_ count: Int) -> String { L("Hidden (\(count))") }
    package static func notchHeader(_ count: Int) -> String { L("Behind the Notch (\(count))") }

    // MARK: Press

    /// The expand a row needs before its press, or nil when its icon is already in the bar.
    package static func expand(for section: IconsSection, state: IconsEngineState) -> IconsExpandMode? {
        switch section {
        case .shown: return nil
        case .hidden: return state == .expanded(.plain) || state == .expanded(.all) ? nil : .plain
        case .alwaysHidden: return state == .expanded(.all) ? nil : .all
        }
    }

    /// The extra read at the row's index can be pressed: it's in the menu bar of `screen` (the arrow's).
    package static func ready(_ frame: IconsRect?, screen: IconsRect) -> Bool {
        guard let frame else { return false }
        return IconsGeometry.isOnScreen(frame, screen)
    }

    /// The extra read at the row's index is still the row's icon: same size, and same place when the row's frame was
    /// read in the bar, each within `matchTolerance`.
    package static func matches(_ row: IconsListRow, actual: IconsRect) -> Bool {
        let e = row.extra.frame, t = matchTolerance
        guard abs(e.width - actual.width) <= t, abs(e.height - actual.height) <= t else { return false }
        guard row.frameKnown else { return true }
        return abs(e.minX - actual.minX) <= t && abs(e.minY - actual.minY) <= t
    }

    /// Whether an opening menu should ask for a background re-read.
    package static func wantsRefresh(lastAsk: Double?, now: Double) -> Bool {
        guard let lastAsk else { return true }
        return now - lastAsk >= refreshInterval || now < lastAsk
    }

    private struct ExtraKey: Hashable {
        let pid: Int32
        let index: Int
        init(_ extra: IconsExtra) {
            pid = extra.pid
            index = extra.index
        }
    }

    private static func nearestFirst(_ a: IconsPlacedExtra, _ b: IconsPlacedExtra) -> Bool {
        if a.distance != b.distance { return a.distance < b.distance }
        if a.extra.pid != b.extra.pid { return a.extra.pid < b.extra.pid }
        return a.extra.index < b.extra.index
    }
}
