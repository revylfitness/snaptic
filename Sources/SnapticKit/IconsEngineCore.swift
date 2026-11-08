import Foundation

// Hidden Icons' engine (lead; PLAN 0.4 §4.2, §4.4, §4.11). One state machine for both engines, over ports, so the
// tests drive it with fakes and assert on recorded lengths and requests (P-3). The core runs on one queue (main in
// the app); every port calls back on it. It never sees an `NSStatusItem`, an AX element or the private class.

// MARK: - Ports

/// Hidden Icons' own three items (`IconsItems`, A1).
package protocol IconsItemsPort: AnyObject {
    /// The item's window frame, in the same space as the inventory's frames. Nil when the item doesn't exist.
    func frame(of role: IconsItemRole) -> IconsRect?
    func setLength(_ length: Double, for role: IconsItemRole)
    /// Nil when the item doesn't exist (`⋮` with Always Hidden off).
    func length(of role: IconsItemRole) -> Double?
    func isVisible(_ role: IconsItemRole) -> Bool
}

package enum IconsActivationError: String, Error, Sendable {
    case failed
    /// The shim caught an exception and is off for the life of the process.
    case poisoned
}

/// The private restriction (`NativeBackend` → `SNMenuBarVisibility`, A2/B1). Tokens are the core's; the shim keeps
/// one assertion per token, delivers each completion at most once on the core's queue, and `invalidate(token:)`
/// releases the token.
package protocol IconsVisibilityPort: AnyObject {
    var isAvailable: Bool { get }
    func activate(systemItems: Range<Int>, bundles: [String], token: UInt64,
                  completion: @escaping (Result<Void, IconsActivationError>) -> Void)
    func invalidate(token: UInt64)
    func invalidateAll()
}

/// Accessibility reads (`AXInventory`, A2). Reads run off the core's queue and complete on it.
package protocol IconsInventoryPort: AnyObject {
    func read(scope: IconsReadScope, completion: @escaping (IconsInventory) -> Void)
    /// MenuBarAgent's `AXIdentifier`s only, for the check after a collapse. Nil when the read failed.
    func readSystemIdentifiers(completion: @escaping (Set<String>?) -> Void)
}

package protocol IconsCancellable: AnyObject {
    func cancel()
}

/// Timers in `.common` modes (A3). `after(0)` is the next run-loop tick.
package protocol IconsSchedulerPort: AnyObject {
    @discardableResult
    func after(_ seconds: Double, _ work: @escaping () -> Void) -> IconsCancellable
}

/// What the core needs from the module and the policy (`IconsModule`, A5; `IconsPolicy`, K4).
package protocol IconsEngineHost: AnyObject {
    /// The policy's gates before a collapse: Accessibility, exam, other-hider pause, stable inventory, own items,
    /// identity. Asked again before each Native activation.
    func collapseRefusal(engine: IconsEngineKind) -> IconsRefusal?
    /// `Icons.disable.native` / `Icons.disable.length`, re-read before each collapse.
    func killSwitchOn(engine: IconsEngineKind) -> Bool
    func screens() -> [IconsScreen]
    func skipRules() -> IconsSkipRules
    /// The crash guard (§4.11): `Icons.native.inFlight = <OS build>` while an activation is outstanding.
    func setActivationInFlight(_ inFlight: Bool)
    /// `Icons.native.disabledBuild = <OS build>`.
    func disableNativeOnThisBuild()
    func count(_ counter: IconsCounter)
    func engineStateChanged(_ state: IconsEngineState)
    /// A usable read. `layout.scope` says whether it may update `knownBundles` (unrestricted only, §4.5).
    func layoutRead(_ layout: IconsLayout)
}

// MARK: - Inputs

/// The settings and app data the core acts on. `update(_:)` re-applies them to the current state.
package struct IconsEngineInputs: Equatable, Sendable {
    package var ownBundleID: String
    package var alwaysHidden: Bool
    /// The Section dividers setting: off makes `|` and `⋮` zero-length while shown.
    package var dividers: Bool
    package var newShown: Set<String>
    /// Per-app choices. Native only; Length keeps them unused (§4.8).
    package var choices: [String: IconsAppChoice]
    package var rightToLeft: Bool
    /// The system item range S0 recorded (S0-2, S0-3).
    package var systemItems: Range<Int>

    package static let defaultSystemItems = 0..<64

    package init(ownBundleID: String, alwaysHidden: Bool = false, dividers: Bool = true, newShown: Set<String> = [],
                 choices: [String: IconsAppChoice] = [:], rightToLeft: Bool = false,
                 systemItems: Range<Int> = IconsEngineInputs.defaultSystemItems) {
        self.ownBundleID = ownBundleID
        self.alwaysHidden = alwaysHidden
        self.dividers = dividers
        self.newShown = newShown
        self.choices = choices
        self.rightToLeft = rightToLeft
        self.systemItems = systemItems
    }
}

// MARK: - Factory and crash guard (§4.2.1, §4.11)

package struct IconsFactoryInputs: Equatable, Sendable {
    package var osMajor: Int
    package var currentBuild: String
    package var killSwitches: Set<IconsFeature>
    package var shimAvailable: Bool
    package var shimVerified: Bool
    package var shimPoisoned: Bool
    package var disabledBuild: String?
    package var identityOK: Bool

    package init(osMajor: Int, currentBuild: String, killSwitches: Set<IconsFeature> = [], shimAvailable: Bool = false,
                 shimVerified: Bool = false, shimPoisoned: Bool = false, disabledBuild: String? = nil,
                 identityOK: Bool = true) {
        self.osMajor = osMajor
        self.currentBuild = currentBuild
        self.killSwitches = killSwitches
        self.shimAvailable = shimAvailable
        self.shimVerified = shimVerified
        self.shimPoisoned = shimPoisoned
        self.disabledBuild = disabledBuild
        self.identityOK = identityOK
    }
}

package enum IconsEngineChoice: Equatable, Sendable {
    case engine(IconsEngineKind)
    case unavailable(IconsUnavailableReason)
}

package enum IconsEngineFactory {
    package static let nativeMajor = 27

    package static func choose(_ i: IconsFactoryInputs) -> IconsEngineChoice {
        guard i.osMajor >= nativeMajor else {
            return i.killSwitches.contains(.length) ? .unavailable(.killSwitch) : .engine(.length)
        }
        // macOS 27 never falls back to Length: the restriction is the only engine there (§4.2.1).
        if i.killSwitches.contains(.native) { return .unavailable(.killSwitch) }
        if i.killSwitches.contains(.inventory) { return .unavailable(.inventoryOff) }
        if i.shimPoisoned { return .unavailable(.shimPoisoned) }
        if !i.shimAvailable || !i.shimVerified { return .unavailable(.shimUnavailable) }
        if let disabled = i.disabledBuild, disabled == i.currentBuild { return .unavailable(.disabledBuild) }
        if !i.identityOK { return .unavailable(.identity) }
        return .engine(.native)
    }
}

package struct IconsCrashGuardResult: Equatable, Sendable {
    /// The `Icons.native.disabledBuild` to keep.
    package var disabledBuild: String?
    /// Remove `Icons.native.inFlight`.
    package var clearInFlight: Bool
    /// The last activation on this build never finished: the status row explains, with Try Again.
    package var tripped: Bool
}

package enum IconsCrashGuard {
    /// Run at module start, before the factory. A marker left by another OS build only clears: that build's crash
    /// says nothing about this one.
    package static func atStart(inFlight: String?, disabledBuild: String?,
                                currentBuild: String) -> IconsCrashGuardResult {
        guard let inFlight else {
            return IconsCrashGuardResult(disabledBuild: disabledBuild, clearInFlight: false, tripped: false)
        }
        if inFlight == currentBuild {
            return IconsCrashGuardResult(disabledBuild: currentBuild, clearInFlight: true, tripped: true)
        }
        return IconsCrashGuardResult(disabledBuild: disabledBuild, clearInFlight: true, tripped: false)
    }
}

// MARK: - Lengths (§4.2.3, §4.2.4)

/// What the bar shows, for the lengths table.
package enum IconsVisual: Equatable, Sendable {
    case collapsed
    case expanded(IconsExpandMode)
}

/// Target lengths. `alwaysHidden` is nil when `⋮` doesn't exist (Always Hidden off): nothing is written to it.
package struct IconsLengthPlan: Equatable, Sendable {
    package var separator: Double
    package var alwaysHidden: Double?
}

package struct IconsLengthWrite: Equatable, Sendable {
    package var role: IconsItemRole
    package var length: Double

    package init(_ role: IconsItemRole, _ length: Double) {
        self.role = role
        self.length = length
    }
}

package enum IconsLengthTable {
    /// A shown divider's length.
    package static let divider: Double = 20
    package static let minimumHide: Double = 500
    /// macOS caps a status item's length at 10 000 (X-18's 20 000 is rejected).
    package static let hardCap: Double = 10_000
    package static let noScreen: Double = 1728

    /// L: `max(500, min(2 × widest screen width, 10 000))`, or 1728 with no screen.
    package static func hideLength(widestScreen: Double?) -> Double {
        guard let widest = widestScreen, widest.isFinite, widest > 0 else { return noScreen }
        return max(minimumHide, min(2 * widest, hardCap))
    }

    package static func hideLength(screens: [IconsScreen]) -> Double {
        hideLength(widestScreen: screens.map(\.frame.width).filter { $0.isFinite && $0 > 0 }.max())
    }

    /// The §4.2.4 table. `alwaysHiddenPlaced` matters on Length only: an unplaced `⋮` acts as part of Hidden, so it
    /// is never inflated (inflating it would hide whatever sits on its far side).
    package static func plan(engine: IconsEngineKind, visual: IconsVisual, alwaysHidden: Bool,
                             alwaysHiddenPlaced: Bool, dividers: Bool, hideLength: Double) -> IconsLengthPlan {
        let shown = dividers ? divider : 0
        let separator: Double
        var mark: Double?
        switch engine {
        case .native:
            // `|` is zero-length, never `isVisible = false`, so macOS keeps its position across a downgrade.
            separator = 0
            mark = visual == .collapsed ? 0 : shown
        case .length:
            switch visual {
            case .collapsed:
                separator = hideLength
                mark = 0  // Hidden's L already covers it.
            case .expanded(.plain):
                separator = shown
                mark = alwaysHiddenPlaced ? hideLength : shown
            case .expanded(.all):
                separator = shown
                mark = shown
            }
        }
        return IconsLengthPlan(separator: separator, alwaysHidden: alwaysHidden ? mark : nil)
    }

    /// The writes from the current lengths to `plan`, widening before narrowing so nothing flashes: collapse →
    /// plain writes `⋮`=L then `|`=20; any → collapse writes `|`=L then `⋮`=0. Unchanged lengths aren't written.
    package static func writes(separator current: Double?, alwaysHidden currentMark: Double?,
                               to plan: IconsLengthPlan) -> [IconsLengthWrite] {
        var targets: [(IconsItemRole, Double?, Double)] = [(.separator, current, plan.separator)]
        if let mark = plan.alwaysHidden { targets.append((.alwaysHidden, currentMark, mark)) }
        var widen: [IconsLengthWrite] = []
        var narrow: [IconsLengthWrite] = []
        for (role, now, target) in targets where now != target {
            if let now, target < now {
                narrow.append(IconsLengthWrite(role, target))
            } else {
                widen.append(IconsLengthWrite(role, target))
            }
        }
        return widen + narrow
    }
}

// MARK: - Allow-lists (§4.2.2, §4.2.4, §4.8)

package enum IconsAllowList {
    /// Collapsed: system owners + Shown + own + `newShown` + Always Show, minus Always Hide. Always Hide never
    /// removes Snaptic or a system owner.
    package static func collapse(_ layout: IconsLayout, _ inputs: IconsEngineInputs) -> [String] {
        var set = Set(layout.bundles(in: [.shown])).union(inputs.newShown)
        for (bundle, choice) in inputs.choices {
            switch choice {
            case .alwaysShow: set.insert(bundle)
            case .alwaysHide: set.remove(bundle)
            }
        }
        return finish(set, layout, inputs)
    }

    /// Plain expand with Always Hidden on: + Hidden, still without the Always Hidden section. Always Hide apps in
    /// Shown or Hidden show (the choice hides only while Hidden is hidden); in Always Hidden they stay hidden.
    package static func plainExpand(_ layout: IconsLayout, _ inputs: IconsEngineInputs) -> [String] {
        var set = Set(layout.bundles(in: [.shown, .hidden])).union(inputs.newShown)
        for (bundle, choice) in inputs.choices where choice == .alwaysShow { set.insert(bundle) }
        return finish(set, layout, inputs)
    }

    /// A plain expand keeps a restriction only when Always Hidden is on and something is left for it to hide. With
    /// nothing to hide, an unrestricted bar is strictly safer: a newly launched app can't be hidden by it.
    package static func keepsPlainRestriction(_ layout: IconsLayout?, _ inputs: IconsEngineInputs) -> Bool {
        guard inputs.alwaysHidden, let layout else { return false }
        return layout.bundles(in: [.alwaysHidden]).contains { bundle in
            inputs.choices[bundle] != .alwaysShow && !inputs.newShown.contains(bundle) && bundle != inputs.ownBundleID
        }
    }

    private static func finish(_ set: Set<String>, _ layout: IconsLayout, _ inputs: IconsEngineInputs) -> [String] {
        var set = set.union(layout.systemBundles)
        set.insert(inputs.ownBundleID)
        return set.filter { !$0.isEmpty }.sorted()
    }
}

// MARK: - System-item check (§4.2.2, R2-1)

package enum IconsSystemItemCheck {
    /// Hidden under any restriction and can't be allowed (S0-2): the README's known limitation, not a failure.
    package static let nowPlaying = "com.apple.menuextra.now-playing"

    /// MenuBarAgent items that were there before the collapse and are gone after it. Empty when either read failed:
    /// no evidence isn't a failure.
    package static func missing(before: Set<String>?, after: Set<String>?) -> Set<String> {
        guard let before, let after else { return [] }
        return before.subtracting(after).subtracting([nowPlaying])
    }
}

// MARK: - The core

package final class IconsEngineCore {
    package static let activationTimeout: Double = 3
    package static let screenCoalesce: Double = 0.25
    package static let timeoutsBeforeUnavailable = 2

    private enum Purpose: Equatable {
        /// Hide: completing sets `.collapsed` and answers the waiters.
        case collapse
        /// A changed collapse list while collapsed (newShown, choices). The state doesn't change.
        case recollapse
        /// Plain expand with Always Hidden on.
        case plain
    }

    private struct Pending {
        var token: UInt64
        var purpose: Purpose
        var bundles: [String]
    }

    /// One completion per token: a second call is a duplicate.
    private final class Once {
        private var fired = false
        func fire() -> Bool {
            if fired { return false }
            fired = true
            return true
        }
    }

    package let engine: IconsEngineKind
    private let items: IconsItemsPort
    private let visibility: IconsVisibilityPort?
    private let inventory: IconsInventoryPort?
    private let scheduler: IconsSchedulerPort
    private let host: IconsEngineHost

    package private(set) var inputs: IconsEngineInputs
    /// The last usable layout. Replaced by unrestricted reads; restricted reads re-section allowed bundles only.
    package private(set) var layout: IconsLayout?
    package private(set) var lastFailSafe: IconsFailSafeReason?

    private var stored: IconsEngineState = .expanded(.plain)
    /// Bumped by every intent that changes what's wanted. Reads and timers from an older generation are dropped.
    private var generation: UInt64 = 0
    private var nextToken: UInt64 = 0
    /// The one activation the core waits for. Any other completion is stale.
    private var pending: Pending?
    /// Completed, not yet invalidated. At rest there is at most one.
    private var held: [UInt64: [String]] = [:]
    /// Activations not yet completed or timed out (the crash guard's marker).
    private var outstanding: Set<UInt64> = []
    private var timers: [UInt64: IconsCancellable] = [:]
    private var markedInFlight = false
    private var waiters: [(IconsCollapseResult) -> Void] = []
    private var consecutiveTimeouts = 0
    private var systemBefore: Set<String>?
    /// Length: whether `⋮` was on the hidden side of `|` the last time it could be seen (not while collapsed).
    private var alwaysHiddenPlaced = false
    private var screenWork: IconsCancellable?
    private var displayTrialPending = false
    private var screenDeferred = false
    /// The expanded mode a Native collapse started from, restored when the policy refuses after the read.
    private var collapseFrom: IconsExpandMode = .plain
    private var readsStarted = 0

    package init(engine: IconsEngineKind, items: IconsItemsPort, visibility: IconsVisibilityPort?,
                 inventory: IconsInventoryPort?, scheduler: IconsSchedulerPort, host: IconsEngineHost,
                 inputs: IconsEngineInputs, cache: IconsLayoutCache? = nil) {
        self.engine = engine
        self.items = items
        self.visibility = visibility
        self.inventory = inventory
        self.scheduler = scheduler
        self.host = host
        self.inputs = inputs
        if let cache {
            layout = IconsLayout(sections: cache.sections, systemBundles: [], carried: Set(cache.sections.keys),
                                 extras: [], offScreen: [], scope: .unrestricted, readAt: cache.readAt)
        }
    }

    // MARK: State

    /// On Length the state follows the live length (`|` > 20 is collapsed), so an item macOS reset is never
    /// reported as hiding anything.
    package var state: IconsEngineState {
        guard engine == .length else { return stored }
        switch stored {
        case .unavailable, .calibrating: return stored
        case .collapsed, .expanded:
            if (items.length(of: .separator) ?? 0) > IconsLengthTable.divider { return .collapsed }
            if case .expanded(let mode) = stored { return .expanded(mode) }
            return .expanded(.plain)
        }
    }

    /// A restriction is held or being activated.
    package var isRestricted: Bool { !held.isEmpty || pending != nil }

    /// The allow-list of the restriction in force, when exactly one is held.
    package var heldBundles: [String]? { held.count == 1 ? held.values.first : nil }

    // MARK: Intents

    /// Shows the items at their expanded lengths and reads the layout (Native: unrestricted, before any collapse).
    package func start() {
        if engine == .native, visibility == nil || inventory == nil {
            becomeUnavailable(.shimUnavailable)
            return
        }
        host.count(.started)
        observeAlwaysHiddenPlacement()
        applyLengths(.expanded(.plain))
        setState(.expanded(.plain))
        refreshRead()
    }

    /// Every call gets exactly one result. A collapse during `.calibrating` joins the one in flight.
    package func collapse(_ completion: @escaping (IconsCollapseResult) -> Void = { _ in }) {
        switch state {
        case .unavailable: return completion(.unavailable)
        case .collapsed: return completion(.collapsed)
        case .calibrating:
            waiters.append(completion)
            return
        case .expanded:
            break
        }
        if host.killSwitchOn(engine: engine) {
            becomeUnavailable(.killSwitch)
            return completion(.unavailable)
        }
        if let refusal = refusal() { return completion(.refused(refusal)) }
        switch engine {
        case .length: collapseLength(completion)
        case .native: collapseNative(completion)
        }
    }

    /// Plain keeps Always Hidden hidden; `.all` (⌥) shows everything.
    package func expand(_ mode: IconsExpandMode) {
        if case .unavailable = stored { return }
        let was = state
        generation += 1
        let cancelled = pending != nil
        pending = nil
        answer(.superseded)
        switch engine {
        case .length:
            if was != .collapsed { observeAlwaysHiddenPlacement() }
            applyLengths(.expanded(mode))
            setState(.expanded(mode))
        case .native:
            if mode == .plain, let list = plainRestriction() {
                applyLengths(.expanded(.plain))
                setState(.expanded(.plain))
                // The old restriction stays until the new one is active (no flash, R2-2).
                if heldBundles != list || held.count != 1 { activate(list, purpose: .plain) }
            } else {
                let invalidated = !held.isEmpty
                invalidateHeld()
                applyLengths(.expanded(mode))
                setState(.expanded(mode))
                if invalidated || cancelled || mode == .all { refreshRead() }
            }
        }
        if was == .collapsed || was == .calibrating { host.count(.expand) }
    }

    /// Module off or quit: everything shows now, with nothing to wait for.
    package func stop() {
        if case .unavailable(.stopped) = stored { return }
        generation += 1
        pending = nil
        screenWork?.cancel()
        screenWork = nil
        answer(.superseded)
        held.removeAll()
        visibility?.invalidateAll()
        for (_, timer) in timers { timer.cancel() }
        timers.removeAll()
        outstanding.removeAll()
        updateInFlight()
        applyLengths(.expanded(.all))
        setState(.unavailable(.stopped))
    }

    /// Shows every icon (⌥ lengths, no restriction). Preempts anything in flight.
    package func failSafe(_ reason: IconsFailSafeReason) {
        if case .unavailable = stored { return }
        lastFailSafe = reason
        host.count(reason.counter)
        showEverything()
        setState(.expanded(.all))
        answer(.failed(reason))
        refreshRead()
    }

    /// MenuBarAgent quit (§4.11). The policy re-collapses 2 s after it launches if the intent is hidden.
    package func agentTerminated() {
        failSafe(.agentRestart)
    }

    /// `Icons.disable.native` / `.length` turned on while running.
    package func killSwitchTurnedOn() {
        if case .unavailable = stored { return }
        becomeUnavailable(.killSwitch)
    }

    package func update(_ new: IconsEngineInputs) {
        guard new != inputs else { return }
        let boundariesChanged = new.alwaysHidden != inputs.alwaysHidden || new.rightToLeft != inputs.rightToLeft
        inputs = new
        let readsBefore = readsStarted
        reapply()
        // The sections depend on the boundaries: read again while the read can be trusted.
        if boundariesChanged, readsStarted == readsBefore, engine == .length || !isRestricted { refreshRead() }
    }

    /// Sections › Refresh. While a restriction is held the read can't be trusted, so it shows everything first
    /// (**Show All Icons and Refresh**), which reads on its own.
    package func refreshLayout() {
        switch stored {
        case .unavailable, .calibrating: return
        case .collapsed, .expanded:
            if engine == .native, isRestricted || state == .collapsed {
                expand(.all)
            } else {
                refreshRead()
            }
        }
    }

    /// `didChangeScreenParameters`. Length re-applies inflated lengths 250 ms after the last one, never during a
    /// Displays resolution trial. Native keeps its restriction (Hidden Bar's display-change case).
    package func screenParametersChanged() {
        guard engine == .length else { return }
        screenWork?.cancel()
        screenWork = scheduler.after(Self.screenCoalesce) { [weak self] in self?.screenSettled() }
    }

    package func setDisplayTrialPending(_ trialPending: Bool) {
        displayTrialPending = trialPending
        if !trialPending, screenDeferred {
            screenDeferred = false
            reapplyForScreens()
        }
    }

    // MARK: Length

    private func collapseLength(_ completion: (IconsCollapseResult) -> Void) {
        generation += 1
        observeAlwaysHiddenPlacement()
        let hide = hideLength()
        applyLengths(.collapsed)
        setState(.collapsed)
        host.count(.collapse)
        completion(.collapsed)
        let gen = generation
        scheduler.after(0) { [weak self] in self?.verifyLength(gen, hide) }
    }

    /// `verifyHideMechanismIfNeeded`: the divider's window must have grown.
    private func verifyLength(_ gen: UInt64, _ hide: Double) {
        guard gen == generation, state == .collapsed else { return }
        let width = items.frame(of: .separator)?.width ?? 0
        if width < hide - 1 { failSafe(.lengthRejected) }
    }

    private func screenSettled() {
        screenWork = nil
        if displayTrialPending {
            screenDeferred = true
            return
        }
        reapplyForScreens()
    }

    private func reapplyForScreens() {
        let visual: IconsVisual
        switch state {
        case .collapsed: visual = .collapsed
        case .expanded(.plain) where inputs.alwaysHidden && alwaysHiddenPlaced: visual = .expanded(.plain)
        default: return
        }
        // Re-checked before every inflate (§4.2.5).
        guard arrangementValid() else { return failSafe(.arrangement) }
        applyLengths(visual)
    }

    private func arrangementValid() -> Bool {
        IconsGuards.arrangementValid(engine: engine, toggle: items.frame(of: .toggle),
                                     separator: items.frame(of: .separator), rightToLeft: inputs.rightToLeft)
    }

    private func observeAlwaysHiddenPlacement() {
        guard engine == .length, stored != .collapsed, inputs.alwaysHidden else { return }
        let toggle = items.frame(of: .toggle)
        alwaysHiddenPlaced = arrangementValid() && IconsGuards.alwaysHiddenPlaced(
            engine: .length, toggle: toggle, separator: items.frame(of: .separator),
            alwaysHidden: items.frame(of: .alwaysHidden), screen: screenFrame(holding: toggle),
            rightToLeft: inputs.rightToLeft)
    }

    // MARK: Native

    private func collapseNative(_ completion: @escaping (IconsCollapseResult) -> Void) {
        guard let visibility, let inventory else {
            becomeUnavailable(.shimUnavailable)
            return completion(.unavailable)
        }
        guard visibility.isAvailable else {
            becomeUnavailable(.shimUnavailable)
            return completion(.unavailable)
        }
        if case .expanded(let mode) = stored { collapseFrom = mode }
        generation += 1
        pending = nil  // A plain activation in flight is stale now.
        waiters = [completion]
        setState(.calibrating)
        // While a restriction is held, only its allow-list's frames are fresh (R2-5).
        let held = Set(self.held.values.joined())
        let scope: IconsReadScope = held.isEmpty ? .unrestricted : .restricted(allowed: held)
        let gen = generation
        inventory.read(scope: scope) { [weak self] read in self?.collapseRead(read, scope: scope, gen: gen) }
    }

    private func collapseRead(_ read: IconsInventory, scope: IconsReadScope, gen: UInt64) {
        guard gen == generation, stored == .calibrating else { return }
        guard let fresh = resolve(read, scope: scope).layout else { return failSafe(.unusableRead) }
        adopt(fresh)
        // Checked again before the activation: the read took time.
        if host.killSwitchOn(engine: .native) { return becomeUnavailable(.killSwitch) }
        if let refusal = host.collapseRefusal(engine: .native) {
            generation += 1
            setState(.expanded(collapseFrom))
            answer(.refused(refusal))
            // A plain activation the collapse cancelled.
            return reapply()
        }
        systemBefore = read.systemIdentifiers
        guard let layout else { return failSafe(.unusableRead) }
        activate(IconsAllowList.collapse(layout, inputs), purpose: .collapse)
    }

    private func activate(_ bundles: [String], purpose: Purpose) {
        guard let visibility else { return becomeUnavailable(.shimUnavailable) }
        guard visibility.isAvailable else { return becomeUnavailable(.shimUnavailable) }
        nextToken += 1
        let token = nextToken
        pending = Pending(token: token, purpose: purpose, bundles: bundles)
        outstanding.insert(token)
        updateInFlight()
        timers[token] = scheduler.after(Self.activationTimeout) { [weak self] in self?.timedOut(token) }
        let once = Once()
        visibility.activate(systemItems: inputs.systemItems, bundles: bundles, token: token) { [weak self] result in
            guard let self else { return }
            guard once.fire() else { return self.host.count(.dupCompletion) }
            self.finished(token, bundles, result)
        }
    }

    private func finished(_ token: UInt64, _ bundles: [String], _ result: Result<Void, IconsActivationError>) {
        timers.removeValue(forKey: token)?.cancel()
        outstanding.remove(token)
        updateInFlight()
        guard let p = pending, p.token == token else {
            // Nobody wants it any more: release it at once.
            if case .success = result { visibility?.invalidate(token: token) }
            return
        }
        pending = nil
        switch result {
        case .failure(.poisoned):
            becomeUnavailable(.shimPoisoned, cause: .shimPoisoned)
        case .failure(.failed):
            failSafe(.activationFailed)
        case .success:
            consecutiveTimeouts = 0
            // N+1 is active: now N goes. The server unions them meanwhile, so nothing flashed (R2-2).
            let old = Array(held.keys)
            held[token] = bundles
            for t in old where t != token {
                held[t] = nil
                visibility?.invalidate(token: t)
            }
            switch p.purpose {
            case .collapse:
                applyLengths(.collapsed)
                setState(.collapsed)
                host.count(.collapse)
                answer(.collapsed)
                checkSystemItems()
                // Inputs that changed while calibrating.
                if IconsAllowList.collapse(layoutOrEmpty, inputs) != bundles { reapply() }
            case .recollapse:
                checkSystemItems()
            case .plain:
                break
            }
        }
    }

    private func timedOut(_ token: UInt64) {
        timers[token] = nil
        outstanding.remove(token)
        updateInFlight()
        guard let p = pending, p.token == token else { return }
        pending = nil
        consecutiveTimeouts += 1
        if consecutiveTimeouts >= Self.timeoutsBeforeUnavailable {
            becomeUnavailable(.timeouts, cause: .activateTimeout)
        } else {
            failSafe(.activateTimeout)
        }
    }

    /// After a collapse, a MenuBarAgent item that went missing (other than Now Playing) turns Native off on this
    /// OS build.
    private func checkSystemItems() {
        guard let inventory, let before = systemBefore else { return }
        let gen = generation
        inventory.readSystemIdentifiers { [weak self] after in
            guard let self, gen == self.generation, self.stored == .collapsed else { return }
            guard !IconsSystemItemCheck.missing(before: before, after: after).isEmpty else { return }
            self.host.disableNativeOnThisBuild()
            self.becomeUnavailable(.disabledBuild, cause: .systemItemHidden)
        }
    }

    private func plainRestriction() -> [String]? {
        guard engine == .native, IconsAllowList.keepsPlainRestriction(layout, inputs), let layout else { return nil }
        return IconsAllowList.plainExpand(layout, inputs)
    }

    /// The last cache is replaced only by an unrestricted read, and only while nothing is held or wanted.
    private func refreshRead() {
        guard let inventory else { return }
        if engine == .native, isRestricted || stored != .expanded(.plain) && stored != .expanded(.all) { return }
        let gen = generation
        readsStarted += 1
        inventory.read(scope: .unrestricted) { [weak self] read in
            guard let self, gen == self.generation else { return }
            if self.engine == .native, self.isRestricted { return }
            guard let fresh = self.resolve(read, scope: .unrestricted).layout else { return }
            self.adopt(fresh)
            // Plain with Always Hidden on: now that the layout is known, keep that section hidden.
            if self.engine == .native, self.stored == .expanded(.plain), let list = self.plainRestriction() {
                self.activate(list, purpose: .plain)
            }
        }
    }

    private func adopt(_ fresh: IconsLayout) {
        var next = fresh
        if case .restricted = fresh.scope, let old = layout {
            // Only the allowed bundles were re-sectioned; the cache's age is still the last unrestricted read's.
            next.readAt = old.readAt
        }
        layout = next
        host.layoutRead(next)
    }

    private func resolve(_ read: IconsInventory, scope: IconsReadScope) -> IconsResolution {
        let toggle = items.frame(of: .toggle)
        let screen = screenFrame(holding: toggle)
        let boundaries = IconsGuards.boundaries(
            engine: engine, toggle: toggle, separator: items.frame(of: .separator),
            alwaysHidden: inputs.alwaysHidden ? items.frame(of: .alwaysHidden) : nil, screen: screen,
            rightToLeft: inputs.rightToLeft)
        return IconsLayoutResolver.resolve(read, boundaries: boundaries, screen: screen, skip: host.skipRules(),
                                           previous: layout?.sections, scope: scope)
    }

    private var layoutOrEmpty: IconsLayout {
        layout ?? IconsLayout(sections: [:], systemBundles: [], carried: [], extras: [], offScreen: [],
                              scope: .unrestricted, readAt: 0)
    }

    // MARK: Shared

    private func refusal() -> IconsRefusal? {
        if !items.isVisible(.toggle) { return .arrowHidden }
        if engine == .length {
            if !items.isVisible(.separator) { return .dividerHidden }
            if !arrangementValid() { return .arrangement }
        }
        return host.collapseRefusal(engine: engine)
    }

    /// Settings, `newShown` or choices changed: bring the current state in line.
    private func reapply() {
        switch stored {
        case .unavailable, .calibrating:
            return
        case .collapsed:
            applyLengths(.collapsed)
            guard engine == .native, pending == nil, let layout else { return }
            let list = IconsAllowList.collapse(layout, inputs)
            if heldBundles != list { activate(list, purpose: .recollapse) }
        case .expanded(let mode):
            observeAlwaysHiddenPlacement()
            applyLengths(.expanded(mode))
            guard engine == .native, mode == .plain else { return }
            if let list = plainRestriction() {
                if (pending?.bundles ?? heldBundles) != list { activate(list, purpose: .plain) }
            } else if isRestricted {
                generation += 1
                pending = nil
                invalidateHeld()
                refreshRead()
            }
        }
    }

    private func showEverything() {
        generation += 1
        pending = nil
        invalidateHeld()
        applyLengths(.expanded(.all))
    }

    private func becomeUnavailable(_ reason: IconsUnavailableReason, cause: IconsFailSafeReason? = nil) {
        if let cause {
            lastFailSafe = cause
            host.count(cause.counter)
        }
        showEverything()
        visibility?.invalidateAll()
        setState(.unavailable(reason))
        answer(cause.map { .failed($0) } ?? .unavailable)
    }

    private func invalidateHeld() {
        for token in held.keys.sorted() { visibility?.invalidate(token: token) }
        held.removeAll()
    }

    private func applyLengths(_ visual: IconsVisual) {
        let plan = IconsLengthTable.plan(
            engine: engine, visual: visual, alwaysHidden: inputs.alwaysHidden,
            alwaysHiddenPlaced: alwaysHiddenPlaced && arrangementValid(), dividers: inputs.dividers,
            hideLength: hideLength())
        let writes = IconsLengthTable.writes(separator: items.length(of: .separator),
                                             alwaysHidden: items.length(of: .alwaysHidden), to: plan)
        for write in writes { items.setLength(write.length, for: write.role) }
    }

    private func hideLength() -> Double {
        IconsLengthTable.hideLength(screens: host.screens())
    }

    private func screenFrame(holding frame: IconsRect?) -> IconsRect? {
        guard let frame else { return nil }
        return IconsGeometry.screen(holding: frame, in: host.screens())?.frame
    }

    private func answer(_ result: IconsCollapseResult) {
        let all = waiters
        waiters = []
        for waiter in all { waiter(result) }
    }

    private func setState(_ next: IconsEngineState) {
        guard next != stored else { return }
        stored = next
        host.engineStateChanged(next)
    }

    private func updateInFlight() {
        let now = !outstanding.isEmpty
        guard now != markedInFlight else { return }
        markedInFlight = now
        host.setActivationInFlight(now)
    }
}
