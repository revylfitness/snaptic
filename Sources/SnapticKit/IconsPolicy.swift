import Foundation

// Hidden Icons' policy (lead; PLAN 0.4 §4.3, §4.5, §4.6, §4.10, §4.11, §4.12, §4.2.5). Pure decisions over plain
// facts the app gathers: what a click means, when the timer may collapse, when hover expands, whether launch collapse
// runs, what's "new", what the own-items guard does, when another hider pauses us, when an exam holds the screen, and
// what each Accessibility state shows. The app owns the monitors and the clock; nothing here reads either.

// MARK: - Clicks (§4.3)

package enum IconsMouseButton: String, Sendable {
    case left
    case right
    /// Any button other than the first two.
    case other
}

/// One mouse-up on the arrow, as the app reads it from `NSApp.currentEvent`. A VoiceOver press has no event.
package struct IconsClickEvent: Equatable, Sendable {
    package var button: IconsMouseButton
    package var option: Bool
    package var control: Bool

    package init(button: IconsMouseButton, option: Bool = false, control: Bool = false) {
        self.button = button
        self.option = option
        self.control = control
    }
}

/// What the arrow does with a click, before the state is known.
package enum IconsClickAction: String, Sendable {
    /// Expand plain while collapsed, collapse while expanded.
    case toggle
    /// ⌥: expand with Always Hidden, or collapse when that is already shown.
    case toggleAll
    case menu
}

/// A visibility command from any source, resolved against the target state (§4.3, §4.4).
package enum IconsCommand: Equatable, Sendable {
    /// A click, a VoiceOver press, the shortcut, CLI `toggle`.
    case toggle
    /// ⌥ + any button.
    case toggleAll
    /// CLI `show`, hover, a hidden-list press.
    case show
    /// CLI `show --all`, the menu's Show All Hidden Icons. Already all: nothing.
    case showAll
    /// CLI `hide`, the menu's Hide Icons Again, the timer, launch collapse, a re-collapse.
    case hide
}

/// Where the bar is heading once every queued intent has run. Calibrating heads to collapsed; an unavailable
/// engine shows everything.
package enum IconsTarget: Equatable, Sendable {
    case collapsed
    case expanded(IconsExpandMode)

    package init(_ state: IconsEngineState) {
        switch state {
        case .collapsed, .calibrating: self = .collapsed
        case .expanded(let mode): self = .expanded(mode)
        case .unavailable: self = .expanded(.plain)
        }
    }

    package var isCollapsed: Bool { self == .collapsed }
}

/// What a command asks the engine to do.
package enum IconsOperation: Equatable, Sendable {
    case collapse
    case expand(IconsExpandMode)
}

package enum IconsClicks {
    /// Hidden Bar's six click cases, remapped (§4.3): no event and a left click toggle, ⌥ with any button shows all,
    /// a right click, ⌃-click or another button opens the menu.
    package static func action(for event: IconsClickEvent?) -> IconsClickAction {
        guard let event else { return .toggle }
        if event.option { return .toggleAll }
        if event.button != .left || event.control { return .menu }
        return .toggle
    }

    /// The table in §4.3. Nil means nothing changes.
    package static func resolve(_ command: IconsCommand, target: IconsTarget) -> IconsOperation? {
        switch (command, target) {
        case (.toggle, .collapsed): .expand(.plain)
        case (.toggle, .expanded): .collapse
        case (.toggleAll, .expanded(.all)): .collapse
        case (.toggleAll, _): .expand(.all)
        case (.show, .collapsed): .expand(.plain)
        case (.show, .expanded): nil
        case (.showAll, .expanded(.all)): nil
        case (.showAll, _): .expand(.all)
        case (.hide, .collapsed): nil
        case (.hide, .expanded): .collapse
        }
    }

    package static func target(after operation: IconsOperation) -> IconsTarget {
        switch operation {
        case .collapse: .collapsed
        case .expand(let mode): .expanded(mode)
        }
    }
}

// MARK: - Auto-collapse (§4.6)

/// Why the timer waits another round instead of collapsing.
package enum IconsRearmReason: String, CaseIterable, Sendable {
    /// The pointer is in a screen's menu bar band, not in full screen.
    case pointerInBand
    /// A Snaptic window is visible: Settings, onboarding, a confirm panel, a save panel, Sparkle and the like.
    case snapticWindow
    /// A menu is open: layer 101, or a SystemUIServer/ControlCenter window at layer 25 touching the band.
    case menuOpen
    /// A popover or panel at layer ≥ 25, or a floating window of an app with an extra, within 40 pt of the band.
    case popoverNearBand
    /// Within 60 s of a hidden-list press.
    case hiddenListPress
    /// The VoiceOver cursor is on a menu bar extra.
    case voiceOverOnExtra
    /// The Snaptic menu or the arrow's menu is open.
    case ownMenuOpen

    /// The reasons that come from other apps' windows. They stop counting after `IconsAutoCollapse.windowCap`.
    package var isWindowBased: Bool { self == .menuOpen || self == .popoverNearBand }
}

/// What the app saw when the timer fired.
package struct IconsRearmFacts: Equatable, Sendable {
    package var pointerInBand = false
    package var fullScreen = false
    package var snapticWindowVisible = false
    package var menuOpen = false
    package var popoverNearBand = false
    /// Monotonic seconds of the last hidden-list press.
    package var lastHiddenListPress: Double?
    package var voiceOverOnExtra = false
    package var ownMenuOpen = false

    package init() {}

    package func reasons(now: Double) -> [IconsRearmReason] {
        var out: [IconsRearmReason] = []
        if pointerInBand, !fullScreen { out.append(.pointerInBand) }
        if snapticWindowVisible { out.append(.snapticWindow) }
        if menuOpen { out.append(.menuOpen) }
        if popoverNearBand { out.append(.popoverNearBand) }
        if let press = lastHiddenListPress, now - press >= 0, now - press < IconsAutoCollapse.hiddenListGrace {
            out.append(.hiddenListPress)
        }
        if voiceOverOnExtra { out.append(.voiceOverOnExtra) }
        if ownMenuOpen { out.append(.ownMenuOpen) }
        return out
    }
}

package enum IconsAutoCollapseDecision: Equatable, Sendable {
    /// Not armed.
    case idle
    /// Armed; fire again at this monotonic time.
    case wait(until: Double)
    /// Something holds the bar open; the timer re-armed.
    case rearm([IconsRearmReason], until: Double)
    /// Collapse now. The timer is disarmed until the result says otherwise.
    case collapse
}

/// The auto-collapse timer's state. The app schedules a wake-up at each `until` and calls `fire`.
package struct IconsAutoCollapse: Equatable, Sendable {
    /// The window-based reasons stop holding after this many seconds in a row.
    package static let windowCap: Double = 120
    package static let hiddenListGrace: Double = 60

    package private(set) var deadline: Double?
    package private(set) var seconds: Double
    /// When the window-based reasons started holding, while they still do.
    package private(set) var windowSince: Double?

    package init(seconds: Int) {
        self.seconds = Double(Self.clamped(seconds))
    }

    /// The timer runs only when the setting is on and the user has collapsed once (§4.0: nothing hides on its own
    /// before then).
    package static func enabled(_ config: IconsConfig) -> Bool { config.autoCollapse && config.arranged }

    package static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, IconsConfig.autoCollapseRange.lowerBound), IconsConfig.autoCollapseRange.upperBound)
    }

    /// An expand, a settings change, or a refused or failed collapse: count down from now.
    @discardableResult
    package mutating func arm(now: Double) -> Double {
        let until = now + seconds
        deadline = until
        return until
    }

    /// A settings change restarts a running timer with the new delay; a stopped one stays stopped.
    package mutating func setSeconds(_ value: Int, now: Double) {
        seconds = Double(Self.clamped(value))
        if deadline != nil { arm(now: now) }
    }

    /// A collapse, a stop, or the setting turned off.
    package mutating func disarm() {
        deadline = nil
        windowSince = nil
    }

    package mutating func fire(now: Double, facts: IconsRearmFacts) -> IconsAutoCollapseDecision {
        guard let deadline else { return .idle }
        if now < deadline { return .wait(until: deadline) }
        var reasons = facts.reasons(now: now)
        if reasons.contains(where: \.isWindowBased) {
            let since = windowSince ?? now
            windowSince = since
            if now - since >= Self.windowCap { reasons.removeAll(where: \.isWindowBased) }
        } else {
            windowSince = nil
        }
        if reasons.isEmpty {
            disarm()
            return .collapse
        }
        return .rearm(reasons, until: arm(now: now))
    }
}

// MARK: - Hover (§4.6)

/// The 0.5 s dwell in the menu bar band. Fires once per entry.
package struct IconsHoverDwell: Equatable, Sendable {
    package static let dwell: Double = 0.5

    package private(set) var enteredAt: Double?
    package private(set) var fired = false

    package init() {}

    /// Hover needs the setting, a collapsed bar, and no `Icons.disable.hover`.
    package static func active(hover: Bool, collapsed: Bool, killSwitches: Set<IconsFeature>) -> Bool {
        hover && collapsed && !killSwitches.contains(.hover)
    }

    /// One pointer sample. True exactly once, when the pointer has stayed in the band for the dwell.
    package mutating func sample(inBand: Bool, now: Double) -> Bool {
        guard inBand else {
            reset()
            return false
        }
        guard let enteredAt else {
            self.enteredAt = now
            return false
        }
        guard !fired, now - enteredAt >= Self.dwell else { return false }
        fired = true
        return true
    }

    /// When the dwell will be reached, so the app can schedule a check without another mouse move.
    package var due: Double? {
        guard let enteredAt, !fired else { return nil }
        return enteredAt + Self.dwell
    }

    package mutating func reset() {
        enteredAt = nil
        fired = false
    }
}

// MARK: - Launch collapse and the stable-inventory gate (§4.5, §4.6)

/// Two matching reads 2 s apart with system uptime over 60 s, within 30 s of start. Gates the first collapse after
/// start.
package struct IconsStableGate: Equatable, Sendable {
    package static let spacing: Double = 2
    package static let minimumUptime: Double = 60
    package static let cap: Double = 30

    package enum Status: Equatable, Sendable {
        case pending
        case passed
        /// The cap ran out; launch collapse is skipped this time.
        case failed
    }

    package private(set) var status: Status = .pending
    private let startedAt: Double
    private var last: (at: Double, sections: [String: IconsSection])?

    package init(startedAt: Double) {
        self.startedAt = startedAt
    }

    /// One read. `sections` is nil for an unusable read, or when the arrow's frame is outside every screen (R2-6).
    /// `uptime` is the system's, in seconds.
    package mutating func read(_ sections: [String: IconsSection]?, at now: Double, uptime: Double) -> Status {
        guard status == .pending else { return status }
        if now - startedAt > Self.cap {
            status = .failed
            return status
        }
        guard let sections else {
            last = nil
            return status
        }
        if let last, now - last.at >= Self.spacing, last.sections == sections, uptime > Self.minimumUptime {
            status = .passed
            return status
        }
        // A read too soon after the last keeps the earlier one, so a quick double read doesn't reset the spacing.
        if let last, now - last.at < Self.spacing, last.sections == sections { return status }
        last = (now, sections)
        return status
    }

    /// No read came in time.
    package mutating func expire(at now: Double) -> Status {
        if status == .pending, now - startedAt > Self.cap { status = .failed }
        return status
    }

    package static func == (a: IconsStableGate, b: IconsStableGate) -> Bool {
        a.status == b.status && a.startedAt == b.startedAt && a.last?.at == b.last?.at
            && a.last?.sections == b.last?.sections
    }
}

package struct IconsLaunchFacts: Equatable, Sendable {
    package var collapseAtLaunch: Bool
    package var arranged: Bool
    /// Launch collapse already ran (or was skipped) in this process. A reopen never runs it.
    package var alreadyDecided = false
    package var versionChanged = false
    package var osBuildChanged = false
    /// The crash guard tripped, or the Safe Mode marker was left over (§4.11).
    package var unstableLaunch = false
    /// A user intent came before the gate passed.
    package var userActed = false
    package var gate: IconsStableGate.Status

    package init(collapseAtLaunch: Bool, arranged: Bool, gate: IconsStableGate.Status) {
        self.collapseAtLaunch = collapseAtLaunch
        self.arranged = arranged
        self.gate = gate
    }
}

package enum IconsLaunchSkip: String, CaseIterable, Sendable {
    case off
    case notArranged
    case alreadyDecided
    case versionChanged
    case osBuildChanged
    case unstableLaunch
    case userActed
    case unstableInventory
}

package enum IconsLaunchDecision: Equatable, Sendable {
    case collapse
    /// Wait for the stable-inventory gate.
    case wait
    case skip(IconsLaunchSkip)
}

package enum IconsLaunchCollapse {
    package static func decide(_ facts: IconsLaunchFacts) -> IconsLaunchDecision {
        if facts.alreadyDecided { return .skip(.alreadyDecided) }
        if !facts.collapseAtLaunch { return .skip(.off) }
        if !facts.arranged { return .skip(.notArranged) }
        if facts.versionChanged { return .skip(.versionChanged) }
        if facts.osBuildChanged { return .skip(.osBuildChanged) }
        if facts.unstableLaunch { return .skip(.unstableLaunch) }
        if facts.userActed { return .skip(.userActed) }
        switch facts.gate {
        case .pending: return .wait
        case .passed: return .collapse
        case .failed: return .skip(.unstableInventory)
        }
    }
}

// MARK: - New icons (§4.5)

/// What one read saw, by bundle.
package struct IconsSighting: Equatable, Sendable {
    /// Bundles this read placed, with their sections.
    package var placed: [String: IconsSection]
    /// Every bundle the read found running with extras, placed or not (carried, off the arrow's screen).
    package var present: Set<String>

    package init(placed: [String: IconsSection], present: Set<String>) {
        self.placed = placed
        self.present = present.union(placed.keys)
    }

    /// From a usable layout. Off-screen extras (Length's hidden ones while collapsed) count as present.
    package init(layout: IconsLayout) {
        var placed: [String: IconsSection] = [:]
        for (bundle, section) in layout.sections where !layout.carried.contains(bundle) { placed[bundle] = section }
        let offScreen = layout.offScreen.compactMap(\.bundleID).filter { !$0.isEmpty }
        self.init(placed: placed, present: Set(layout.sections.keys).union(offScreen))
    }

    /// From a restricted read's raw inventory: hidden apps' frames are stale, so nothing is placed, but an app with
    /// extras is still there (§4.2.2, R2-5).
    package init(inventory: IconsInventory, skip: IconsSkipRules) {
        var present: Set<String> = []
        for app in inventory.apps where app.result == .ok && !app.extras.isEmpty && skip.skip(app) == nil {
            if let bundle = app.bundleID { present.insert(bundle) }
        }
        self.init(placed: [:], present: present)
    }
}

package struct IconsNewIconsUpdate: Equatable, Sendable {
    package var state: IconsAppsState
    /// Bundles seen for the first time, sorted.
    package var new: [String]
    /// Bundles that left `knownBundles` this read, sorted.
    package var dropped: [String]
    /// `newShown` gained or lost a bundle, so the engine's allow-list needs `update(_:)`. A new last-seen time alone
    /// doesn't count.
    package var newShownChanged: Bool
}

package enum IconsNewIcons {
    /// `newShown` entries unseen this long go (§4.5).
    package static let expiry: Double = 30 * 86_400
    /// Re-reads after an app launches, because macOS adds extras late.
    package static let rereadDelays: [Double] = [2, 10, 30]

    /// App launches are watched while an assertion is active (Native) or while collapsed (Length).
    package static func watchesLaunches(engine: IconsEngineKind, assertionActive: Bool, collapsed: Bool) -> Bool {
        engine == .native ? assertionActive : collapsed
    }

    /// An unrestricted read: the only kind that records sections and counts misses. `now` is wall seconds.
    package static func unrestrictedRead(_ sighting: IconsSighting, now: Double,
                                         state: IconsAppsState) -> IconsNewIconsUpdate {
        var s = state
        var new: [String] = []
        var dropped: [String] = []
        for bundle in sighting.present.sorted() where IconsAppsState.isBundle(bundle) {
            if var known = s.knownBundles[bundle] {
                known.lastSeen = max(known.lastSeen, now)
                known.missedReads = 0
                if let section = sighting.placed[bundle] { known.section = section }
                s.knownBundles[bundle] = known
            } else {
                new.append(bundle)
                s.knownBundles[bundle] = IconsKnownBundle(section: sighting.placed[bundle], firstSeen: now,
                                                          lastSeen: now)
            }
        }
        for (bundle, var known) in s.knownBundles where !sighting.present.contains(bundle) {
            known.missedReads += 1
            if known.missedReads >= IconsAppsState.dropAfterMissedReads {
                s.knownBundles[bundle] = nil
                dropped.append(bundle)
            } else {
                s.knownBundles[bundle] = known
            }
        }
        let before = s.newShown
        // Show lasts until an unrestricted read records the section.
        for bundle in sighting.placed.keys { s.newShown[bundle] = nil }
        for bundle in sighting.present where s.newShown[bundle] != nil { s.newShown[bundle] = now }
        s.newShown = expired(s.newShown, now: now)
        let out = s.sanitized()
        return IconsNewIconsUpdate(state: out, new: new, dropped: dropped.sorted(),
                                   newShownChanged: Set(out.newShown.keys) != Set(before.keys))
    }

    /// A restricted read (Native while collapsed): records nothing in `knownBundles`, but a new app's bundle joins
    /// `newShown` under Show. Under Hide it is hidden, and the hidden list says "New".
    package static func restrictedRead(_ sighting: IconsSighting, now: Double, policy: IconsNewAppPolicy,
                                       state: IconsAppsState) -> IconsNewIconsUpdate {
        var s = state
        let before = s.newShown
        let new = sighting.present.filter {
            IconsAppsState.isBundle($0) && s.knownBundles[$0] == nil && s.choices[$0] == nil
        }.sorted()
        for bundle in sighting.present where s.newShown[bundle] != nil { s.newShown[bundle] = now }
        if policy == .show {
            for bundle in new { s.newShown = inserting(bundle, at: now, into: s.newShown) }
        }
        s.newShown = expired(s.newShown, now: now)
        return IconsNewIconsUpdate(state: s, new: new, dropped: [],
                                   newShownChanged: Set(s.newShown.keys) != Set(before.keys))
    }

    /// The user picked a place for the app in Sections.
    package static func chose(_ bundle: String, state: IconsAppsState) -> IconsAppsState {
        var s = state
        s.newShown[bundle] = nil
        return s
    }

    package static func expired(_ newShown: [String: Double], now: Double) -> [String: Double] {
        newShown.filter { now - $0.value <= expiry }
    }

    /// LRU at the cap: the least recently seen goes first, ties by bundle id.
    package static func inserting(_ bundle: String, at now: Double, into newShown: [String: Double]) -> [String: Double] {
        var out = newShown
        out[bundle] = now
        while out.count > IconsAppsState.newShownCap {
            guard let oldest = out.min(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else {
                break
            }
            out[oldest.key] = nil
        }
        return out
    }

    /// Length's toast (§4.5): once per app per day, and only when an Accessibility inventory exists.
    package static func toastDue(_ bundle: String, now: Double, inventoryExists: Bool,
                                 state: IconsAppsState) -> Bool {
        guard inventoryExists, IconsAppsState.isBundle(bundle) else { return false }
        return state.toasts[bundle] != day(now)
    }

    package static func toasted(_ bundle: String, now: Double, state: IconsAppsState) -> IconsAppsState {
        var s = state
        s.toasts[bundle] = day(now)
        return s.sanitized()
    }

    package static func day(_ wall: Double) -> Int {
        guard wall.isFinite, wall > 0 else { return 0 }
        return Int(wall / 86_400)
    }
}

// MARK: - Own-items guard (§4.2.5, Length)

/// The rows the guard shows. Their strings are `IconsPageRules.ownItemsText` (§4.2.5).
package enum IconsOwnItemsRow: String, Sendable {
    /// “The arrow is in the hidden area. ⌘-drag it to the right of the | divider.”
    case arrowHidden
    /// “Awake’s icon is in the hidden area, so icons stay shown while your Mac is kept awake. …”
    case awakeHidden
    /// “Some Snaptic icons are in the hidden area. ⌘-drag them to the right of the arrow.”
    case someHidden
}

package struct IconsOwnItemsDecision: Equatable, Sendable {
    /// Collapse is refused with `.ownItems`.
    package var refuse: Bool
    /// Expand now: Awake is hidden while it holds, or a Snaptic item appeared while collapsed.
    package var expand: Bool
    package var row: IconsOwnItemsRow?

    package static let ok = IconsOwnItemsDecision(refuse: false, expand: false, row: nil)
}

package enum IconsOwnItemsGuard {
    /// - Parameters:
    ///   - awakeHolding: Awake keeps the Mac awake, or lid-closed mode is on.
    ///   - appeared: a Snaptic status item appeared for the first time.
    package static func decide(_ placement: IconsOwnItemsPlacement, awakeHolding: Bool, collapsed: Bool,
                               appeared: Bool = false) -> IconsOwnItemsDecision {
        let expandForNew = collapsed && appeared
        guard placement.known else {
            return IconsOwnItemsDecision(refuse: true, expand: expandForNew, row: nil)
        }
        if placement.toggleBeyond {
            return IconsOwnItemsDecision(refuse: true, expand: expandForNew, row: .arrowHidden)
        }
        if awakeHolding, !placement.beyond.isEmpty {
            return IconsOwnItemsDecision(refuse: true, expand: collapsed, row: .awakeHidden)
        }
        if !placement.beyond.isEmpty {
            return IconsOwnItemsDecision(refuse: false, expand: expandForNew, row: .someHidden)
        }
        return IconsOwnItemsDecision(refuse: false, expand: expandForNew, row: nil)
    }
}

// MARK: - Other hiders (§4.10)

/// A running app, as the hider watch sees it.
package struct IconsRunningApp: Equatable, Sendable {
    package var bundleID: String?
    /// The code-signing team, or nil when unsigned or unreadable.
    package var teamID: String?

    package init(bundleID: String?, teamID: String?) {
        self.bundleID = bundleID
        self.teamID = teamID
    }
}

package enum IconsHiderPause {
    /// The listed hider Hidden Icons pauses for, or nil. Run Both never pauses.
    package static func pausedFor(policy: IconsOtherHiderPolicy, running: [IconsRunningApp]) -> KnownMenuBarHider? {
        guard policy == .pause else { return nil }
        for app in running {
            if let hider = KnownMenuBarHiders.match(bundleID: app.bundleID, teamID: app.teamID) { return hider }
        }
        return nil
    }
}

// MARK: - Exam guard (§4.11, R2-4)

/// The presentation options that mean an exam holds the screen. The app maps `NSApplication.PresentationOptions`.
package enum IconsPresentationFlag: String, CaseIterable, Sendable {
    case disableProcessSwitching
    case disableForceQuit
    case disableSessionTermination
}

package enum IconsExamGuard {
    /// The 1 s poll while Native holds an assertion.
    package static let pollInterval: Double = 1

    /// An exam holds the screen when another process set one of the flags. `own` is Snaptic's own options, which
    /// never set them; a flag only Snaptic set isn't an exam.
    package static func active(system: Set<IconsPresentationFlag>, own: Set<IconsPresentationFlag> = []) -> Bool {
        !system.subtracting(own).isEmpty
    }

    /// Poll only while Native could show something an exam hid.
    package static func polls(engine: IconsEngineKind, assertionActive: Bool) -> Bool {
        engine == .native && assertionActive
    }
}

// MARK: - Accessibility (§4.12)

package enum IconsAccessState: String, CaseIterable, Sendable {
    case granted
    case notGranted
    /// Trusted stayed false for 5 s after the Privacy pane closed: macOS may need a relaunch.
    case notEffective
    /// A read failed, or two reads found no third-party icons after a good one, while collapsed.
    case revoked

    package var needsPermission: Bool { self != .granted }
    /// A click on the arrow opens Settings › Hidden Icons instead of toggling.
    package var arrowOpensSettings: Bool { needsPermission }
    /// `snaptic icons status` prints `state=needsPermission`.
    package var cliState: String? { needsPermission ? "needsPermission" : nil }
    /// Not effective offers Relaunch Snaptic; the others offer Open Privacy Settings.
    package var offersRelaunch: Bool { self == .notEffective }
}

/// One read's outcome, for the revoke check.
package enum IconsAccessRead: Equatable, Sendable {
    case failed
    /// The read placed this many third-party extras.
    case thirdParty(Int)
}

package struct IconsAccessTracker: Equatable, Sendable {
    package static let effectiveGrace: Double = 5
    package static let emptyReadsToRevoke = 2

    package private(set) var state: IconsAccessState
    private var paneClosedAt: Double?
    private var hadGoodRead = false
    private var emptyReads = 0

    package init(trusted: Bool) {
        state = trusted ? .granted : .notGranted
    }

    /// The Privacy pane Snaptic opened has closed.
    package mutating func paneClosed(at now: Double) {
        paneClosedAt = now
    }

    /// `AXIsProcessTrusted()`, sampled. A revoke found by reads stays until a good read, because the trust flag can
    /// stay true after a revoke.
    @discardableResult
    package mutating func trust(_ trusted: Bool, at now: Double) -> IconsAccessState {
        if trusted {
            paneClosedAt = nil
            if state != .revoked { state = .granted }
            return state
        }
        if let closed = paneClosedAt, now - closed >= Self.effectiveGrace {
            state = .notEffective
        } else if state != .notEffective {
            state = .notGranted
        }
        hadGoodRead = false
        emptyReads = 0
        return state
    }

    /// A read finished. True means expand now: the permission was lost while collapsed.
    package mutating func read(_ outcome: IconsAccessRead, collapsed: Bool) -> Bool {
        switch outcome {
        case .thirdParty(let count) where count > 0:
            hadGoodRead = true
            emptyReads = 0
            if state == .revoked { state = .granted }
            return false
        case .thirdParty:
            guard hadGoodRead else { return false }
            emptyReads += 1
            guard collapsed, emptyReads >= Self.emptyReadsToRevoke, state == .granted else { return false }
        case .failed:
            guard collapsed, state == .granted else { return false }
        }
        state = .revoked
        return true
    }

    /// On macOS 27 the engine can't hide without the read; on 14–26 permission affects only the list and Sections.
    package static func blocksCollapse(engine: IconsEngineKind, state: IconsAccessState) -> Bool {
        engine == .native && state.needsPermission
    }
}

// MARK: - Recovery (§4.11)

package enum IconsRecoveryEvent: String, CaseIterable, Sendable {
    case agentTerminated
    case agentLaunched
    /// Session resign/become active, wake, screen lock/unlock.
    case session
}

package struct IconsRecoveryPlan: Equatable, Sendable {
    /// Show every icon now, for this reason.
    package var failSafe: IconsFailSafeReason?
    /// Re-read, then re-collapse, this many seconds later.
    package var recollapseAfter: Double?
}

package enum IconsRecovery {
    package static let delay: Double = 2

    /// `intentHidden`: the last user, timer or launch intent was to hide (`IconsIntentQueue.intentHidden`).
    package static func plan(_ event: IconsRecoveryEvent, intentHidden: Bool) -> IconsRecoveryPlan {
        switch event {
        case .agentTerminated:
            IconsRecoveryPlan(failSafe: .agentRestart, recollapseAfter: nil)
        case .agentLaunched:
            IconsRecoveryPlan(failSafe: nil, recollapseAfter: intentHidden ? delay : nil)
        case .session:
            IconsRecoveryPlan(failSafe: .session, recollapseAfter: intentHidden ? delay : nil)
        }
    }
}

// MARK: - The collapse gates (`IconsEngineHost.collapseRefusal`)

package struct IconsCollapseFacts: Equatable, Sendable {
    package var engine: IconsEngineKind
    package var exam = false
    package var pausedFor: KnownMenuBarHider?
    package var access: IconsAccessState = .granted
    /// The first collapse after start: the stable-inventory gate's status. Nil once the gate no longer applies.
    package var gate: IconsStableGate.Status?
    /// Length only.
    package var ownItems: IconsOwnItemsDecision = .ok
    package var identityOK = true

    package init(engine: IconsEngineKind) {
        self.engine = engine
    }
}

package enum IconsCollapseGates {
    /// The first gate that refuses, in the order the status row explains them.
    package static func refusal(_ facts: IconsCollapseFacts) -> IconsRefusal? {
        if facts.exam { return .exam }
        if facts.pausedFor != nil { return .paused }
        if IconsAccessTracker.blocksCollapse(engine: facts.engine, state: facts.access) { return .needsPermission }
        if let gate = facts.gate, gate != .passed { return .unstableInventory }
        if facts.engine == .length, facts.ownItems.refuse { return .ownItems }
        if facts.engine == .native, !facts.identityOK { return .identity }
        return nil
    }
}
