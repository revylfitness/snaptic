import Foundation

// Pure planning for display connect/wake events (owner: D). PLAN §4.11, R5.3.
// The app's ConnectPlanner (runner) gathers ConnectInputs, calls `plan(inputs:)`, and
// executes the steps; nothing here touches the system.

package enum ConnectTrigger: String, Codable, CaseIterable, Sendable { case launch, wake, reconfigure, sessionResume }

/// Plans run in two phases (R5.3): create/rebind virtuals, re-snapshot, then the rest.
package enum ConnectPhase: String, Codable, Sendable { case virtuals, rest }

/// A presented display as the planner sees it.
package struct PlanDisplay: Equatable, Sendable {
    package var key: DisplayKey
    package var transport: Transport
    package var isBuiltin: Bool
    package var isActive: Bool
    package var isMain: Bool
    package var strong: Bool
    package var weak: Bool
    package var mode: ModeRef?
    /// Public, desktop-usable modes.
    package var availableModes: [ModeRef]
    /// Online but disabled by Snaptic's disconnect.
    package var disabledBySnaptic: Bool
    /// Software-dimmed below the visibility floor (dim to black).
    package var dimmedBelowFloor: Bool
    package var x: Int32
    package var y: Int32
    package var rotation: Int
    /// The presented display this one mirrors.
    package var mirrorOf: DisplayKey?

    package init(key: DisplayKey, transport: Transport, isBuiltin: Bool, isActive: Bool = true, isMain: Bool = false,
                 strong: Bool, weak: Bool = false, mode: ModeRef? = nil, availableModes: [ModeRef] = [],
                 disabledBySnaptic: Bool = false, dimmedBelowFloor: Bool = false, x: Int32 = 0, y: Int32 = 0,
                 rotation: Int = 0, mirrorOf: DisplayKey? = nil) {
        self.key = key
        self.transport = transport
        self.isBuiltin = isBuiltin
        self.isActive = isActive
        self.isMain = isMain
        self.strong = strong
        self.weak = weak
        self.mode = mode
        self.availableModes = availableModes
        self.disabledBySnaptic = disabledBySnaptic
        self.dimmedBelowFloor = dimmedBelowFloor
        self.x = x
        self.y = y
        self.rotation = rotation
        self.mirrorOf = mirrorOf
    }
}

/// What a host process is for.
package enum HostPurpose: Codable, Equatable, Sendable {
    case virtualScreen
    case smartHiDPI(physical: DisplayKey)
}

/// A live (or expected) virtual host.
package struct PlanHost: Equatable, Sendable {
    package var specID: StableID
    package var purpose: HostPurpose
    /// Its virtual display is online.
    package var isLive: Bool
    /// The virtual display is the main display.
    package var isMain: Bool
    /// The physical display currently mirroring it.
    package var boundTo: DisplayKey?
    /// The live display still matches the spec (identity and size).
    package var identityMatches: Bool
    /// Seconds the associated physical display has been missing (nil = present or none).
    package var physicalMissingSeconds: Double?

    package init(specID: StableID, purpose: HostPurpose, isLive: Bool = true, isMain: Bool = false, boundTo: DisplayKey? = nil,
                 identityMatches: Bool = true, physicalMissingSeconds: Double? = nil) {
        self.specID = specID
        self.purpose = purpose
        self.isLive = isLive
        self.isMain = isMain
        self.boundTo = boundTo
        self.identityMatches = identityMatches
        self.physicalMissingSeconds = physicalMissingSeconds
    }
}

/// A kept Smart HiDPI pair (restored unattended only with a tier-1 fingerprint, R5.2).
package struct PlanPair: Equatable, Sendable {
    package var physical: DisplayKey
    package var specID: StableID
    package var physicalPresent: Bool
    package var tier1Verified: Bool

    package init(physical: DisplayKey, specID: StableID, physicalPresent: Bool, tier1Verified: Bool) {
        self.physical = physical
        self.specID = specID
        self.physicalPresent = physicalPresent
        self.tier1Verified = tier1Verified
    }
}

/// A user virtual screen with its association rules.
package struct PlanVirtualScreen: Equatable, Sendable {
    package var specID: StableID
    package var associations: [VirtualAssociation]
    /// The manual connection state, already filtered by `recreateOnLaunch` at launch.
    package var wantsConnected: Bool

    package init(specID: StableID, associations: [VirtualAssociation] = [], wantsConnected: Bool) {
        self.specID = specID
        self.associations = associations
        self.wantsConnected = wantsConnected
    }

    /// Associations decide when any of them auto-connects; they override manual state.
    package var isAssociationManaged: Bool { associations.contains { $0.autoConnect != .never } }

    package func desiredConnected(present: Set<DisplayKey>) -> Bool {
        let auto = associations.filter { $0.autoConnect != .never }
        guard !auto.isEmpty else { return wantsConnected }
        let whilePresent = auto.filter { $0.autoConnect == .whilePresent }
        let whileAbsent = auto.filter { $0.autoConnect == .whileAbsent }
        if whilePresent.contains(where: { present.contains($0.target) }) { return true }
        if !whileAbsent.isEmpty && whileAbsent.allSatisfy({ !present.contains($0.target) }) { return true }
        return false
    }
}

package struct PlanPersistedChoice: Equatable, Sendable {
    package var key: DisplayKey
    package var mode: ModeRef
    package var preKeepMode: ModeRef

    package init(key: DisplayKey, mode: ModeRef, preKeepMode: ModeRef) {
        self.key = key
        self.mode = mode
        self.preKeepMode = preKeepMode
    }
}

package struct PlanAutoDisconnect: Equatable, Sendable {
    package var builtin: DisplayKey
    package var modelIdentifier: String
    package var modelName: String?
    package var isAppleSilicon: Bool
    package var lidOpen: Bool?
    /// Power reading of the external display that would remain.
    package var externalPower: ExternalPowerReading
    package var externalIsAppleNative: Bool
    package var userSaysNoDDC: Bool
    package var builtinIgnored: Bool

    package init(builtin: DisplayKey, modelIdentifier: String, modelName: String? = nil, isAppleSilicon: Bool, lidOpen: Bool?,
                 externalPower: ExternalPowerReading, externalIsAppleNative: Bool, userSaysNoDDC: Bool = false,
                 builtinIgnored: Bool = false) {
        self.builtin = builtin
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.isAppleSilicon = isAppleSilicon
        self.lidOpen = lidOpen
        self.externalPower = externalPower
        self.externalIsAppleNative = externalIsAppleNative
        self.userSaysNoDDC = userSaysNoDDC
        self.builtinIgnored = builtinIgnored
    }
}

package struct ConnectInputs: Equatable, Sendable {
    package var trigger: ConnectTrigger
    package var phase: ConnectPhase
    package var effective: Set<DisplayFeature>
    package var safeMode: Bool
    package var panicLatch: Bool
    /// Seconds since the last wake or unlock (nil = long ago / never).
    package var secondsSinceWakeOrUnlock: Double?
    /// The presented-display set changed since the last plan (layouts apply only then,
    /// or on launch/wake/resume).
    package var displaySetChanged: Bool
    package var displays: [PlanDisplay]
    package var hosts: [PlanHost]
    package var pairs: [PlanPair]
    package var virtualScreens: [PlanVirtualScreen]
    package var layouts: [SavedLayout]
    package var trustedLayouts: Set<StableID>
    package var liveIdentities: [LiveLayoutDisplay]
    package var protection: ProtectionProfile?
    package var protectionFields: ProtectedFields
    /// Fight detection stopped protection for this set.
    package var protectionStopped: Bool
    package var persisted: [PlanPersistedChoice]
    package var autoDisconnect: PlanAutoDisconnect?

    package init(trigger: ConnectTrigger, phase: ConnectPhase = .virtuals, effective: Set<DisplayFeature> = [],
                 safeMode: Bool = false, panicLatch: Bool = false, secondsSinceWakeOrUnlock: Double? = nil,
                 displaySetChanged: Bool = true, displays: [PlanDisplay] = [], hosts: [PlanHost] = [], pairs: [PlanPair] = [],
                 virtualScreens: [PlanVirtualScreen] = [], layouts: [SavedLayout] = [], trustedLayouts: Set<StableID> = [],
                 liveIdentities: [LiveLayoutDisplay] = [], protection: ProtectionProfile? = nil,
                 protectionFields: ProtectedFields = ProtectedFields(), protectionStopped: Bool = false,
                 persisted: [PlanPersistedChoice] = [], autoDisconnect: PlanAutoDisconnect? = nil) {
        self.trigger = trigger
        self.phase = phase
        self.effective = effective
        self.safeMode = safeMode
        self.panicLatch = panicLatch
        self.secondsSinceWakeOrUnlock = secondsSinceWakeOrUnlock
        self.displaySetChanged = displaySetChanged
        self.displays = displays
        self.hosts = hosts
        self.pairs = pairs
        self.virtualScreens = virtualScreens
        self.layouts = layouts
        self.trustedLayouts = trustedLayouts
        self.liveIdentities = liveIdentities
        self.protection = protection
        self.protectionFields = protectionFields
        self.protectionStopped = protectionStopped
        self.persisted = persisted
        self.autoDisconnect = autoDisconnect
    }
}

package enum HostTeardownReason: String, Codable, Sendable {
    /// Its physical display is still missing after the grace (step 1).
    case orphaned
    /// Its association no longer wants it connected (step 2).
    case associationEnded
    /// The live display no longer matches the spec; it is recreated (step 2).
    case mismatch
}

package enum PlanStep: Codable, Equatable, Sendable {
    // Step 1: visibility restore (immediate, not coalesced, not rate-limited; also in Safe Mode and panic).
    case reenable(DisplayKey)
    case raiseFloor(DisplayKey)
    case destroyHost(StableID, reason: HostTeardownReason)
    case moveMain(to: DisplayKey)
    // Step 2: Smart HiDPI and associations.
    case createVirtual(StableID, purpose: HostPurpose)
    case rebind(specID: StableID, physical: DisplayKey)
    /// Needs the user (toast): mirroring to another display, streams, untrusted pairs.
    case promptMirror(specID: StableID, target: DisplayKey)
    case promptStream(specID: StableID, target: DisplayKey, flipped: Bool)
    // Step 3: layout or protection.
    case applyLayout(StableID)
    case promptLayout(StableID)
    case protect([ProtectionDelta])
    /// Restores that would modeset the only strongly visible display: a trial at the next
    /// user presence ("Restore 'Office'? Keep / Not now").
    case promptRestore([ProtectionDelta])
    // Step 4: persisted choice.
    case restoreMode(DisplayKey, ModeRef)
    case promptRestoreMode(DisplayKey, ModeRef)
    // Step 5: auto-disconnect built-in.
    case disconnectBuiltin(DisplayKey)

    package var stage: Int {
        switch self {
        case .reenable, .raiseFloor, .moveMain: return 1
        case .destroyHost(_, let reason): return reason == .orphaned ? 1 : 2
        case .createVirtual, .rebind, .promptMirror, .promptStream: return 2
        case .applyLayout, .promptLayout, .protect, .promptRestore: return 3
        case .restoreMode, .promptRestoreMode: return 4
        case .disconnectBuiltin: return 5
        }
    }

    package var isVisibilityRestore: Bool { stage == 1 }

    /// Steps that only show a prompt (never change anything unattended).
    package var isPrompt: Bool {
        switch self {
        case .promptMirror, .promptStream, .promptLayout, .promptRestore, .promptRestoreMode: return true
        default: return false
        }
    }

    /// Displays the step changes (for rate limiting and "touched" bookkeeping).
    package var keys: [DisplayKey] {
        switch self {
        case .reenable(let k), .raiseFloor(let k), .moveMain(let k), .restoreMode(let k, _), .promptRestoreMode(let k, _),
             .disconnectBuiltin(let k):
            return [k]
        case .rebind(_, let k), .promptMirror(_, let k), .promptStream(_, let k, _): return [k]
        case .createVirtual(_, let purpose):
            if case .smartHiDPI(let k) = purpose { return [k] }
            return []
        case .protect(let d), .promptRestore(let d): return d.map(\.key)
        case .destroyHost, .applyLayout, .promptLayout: return []
        }
    }
}

package enum ConnectPlan {
    /// Grace before an orphaned host is torn down (R5.3).
    package static let normalGrace: Double = 4
    package static let wakeGrace: Double = 30
    package static let wakeWindow: Double = 120
    /// Steps 2–5 wait for this much reconfiguration quiet, capped (R5.3).
    package static let quietSeconds: Double = 3
    package static let quietCapSeconds: Double = 10

    /// The grace for orphaned hosts given the current state.
    package static func grace(secondsSinceWakeOrUnlock: Double?, anyVisible: Bool) -> Double {
        guard anyVisible else { return normalGrace }
        if let s = secondsSinceWakeOrUnlock, s >= 0, s <= wakeWindow { return wakeGrace }
        return normalGrace
    }

    /// Builds the ordered steps for one phase of one run. Safe Mode and panic latch run step 1 only.
    package static func plan(inputs: ConnectInputs) -> [PlanStep] {
        var steps = visibilitySteps(inputs)
        guard !inputs.safeMode, !inputs.panicLatch else { return steps }
        let present = Set(inputs.displays.filter { $0.isActive || $0.disabledBySnaptic }.map(\.key))
        let orphaned = Set(steps.compactMap { step -> StableID? in
            if case .destroyHost(let id, .orphaned) = step { return id }
            return nil
        })
        var touched = Set<DisplayKey>()

        // Step 2.
        let step2 = virtualSteps(inputs, present: present, skipping: orphaned)
        for s in step2 { touched.formUnion(s.keys) }
        if inputs.phase == .virtuals {
            steps += step2
            return steps
        }
        steps += step2.filter { if case .rebind = $0 { return true }; return false }

        // Step 3.
        let strongKeys = inputs.displays.filter(\.strong).map(\.key)
        let onlyStrong: DisplayKey? = strongKeys.count == 1 ? strongKeys[0] : nil
        var layoutApplied = false
        let layoutTrigger = inputs.displaySetChanged || inputs.trigger != .reconfigure
        if inputs.effective.contains(.layouts), layoutTrigger,
           let pick = LayoutPresetModel.select(inputs.layouts, live: inputs.liveIdentities) {
            let trusted = inputs.trustedLayouts.contains(pick.layout.id)
            if trusted && !modesetsOnly(pick.layout, onlyStrong: onlyStrong, displays: inputs.displays) {
                steps.append(.applyLayout(pick.layout.id))
                layoutApplied = true
                touched.formUnion(pick.layout.referencedKeys)
            } else {
                steps.append(.promptLayout(pick.layout.id))
            }
        }
        if !layoutApplied, inputs.effective.contains(.protection), !inputs.protectionStopped, let desired = inputs.protection {
            let deltas = ProtectionDiff.diff(desired: desired, live: inputs.liveStates, fields: inputs.protectionFields.gated(by: inputs.effective))
            let needsPresence = deltas.filter { $0.isModeChange && $0.key == onlyStrong }
            let unattended = deltas.filter { !($0.isModeChange && $0.key == onlyStrong) }
            if !unattended.isEmpty { steps.append(.protect(unattended)) }
            if !needsPresence.isEmpty { steps.append(.promptRestore(needsPresence)) }
            for d in deltas { touched.insert(d.key) }
        }

        // Step 4.
        if inputs.effective.contains(.resolution) {
            for choice in inputs.persisted.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where !touched.contains(choice.key) {
                guard let d = inputs.displays.first(where: { $0.key == choice.key && $0.isActive }), let current = d.mode,
                      ProtectionDiff.resolve(choice.preKeepMode, in: [current]) != nil,
                      let target = ProtectionDiff.resolve(choice.mode, in: d.availableModes), target != current else { continue }
                let otherStrong = inputs.displays.contains { $0.strong && $0.key != d.key }
                if d.strong && !otherStrong {
                    steps.append(.promptRestoreMode(d.key, target))
                } else {
                    steps.append(.restoreMode(d.key, target))
                }
                touched.insert(d.key)
            }
        }

        // Step 5.
        if inputs.effective.contains(.autoDisconnectBuiltin), let ad = inputs.autoDisconnect,
           let builtin = inputs.displays.first(where: { $0.key == ad.builtin && $0.isBuiltin && $0.isActive && !$0.disabledBySnaptic }) {
            let externalStrong = inputs.displays.contains { $0.strong && !$0.isBuiltin && $0.key != builtin.key }
            let verdict = BuiltinDisconnectPolicy.autoDisconnectDecision(
                modelIdentifier: ad.modelIdentifier, modelName: ad.modelName, isAppleSilicon: ad.isAppleSilicon,
                lidOpen: ad.lidOpen, externalStronglyVisible: externalStrong, externalPower: ad.externalPower,
                externalIsAppleNative: ad.externalIsAppleNative, userSaysNoDDC: ad.userSaysNoDDC,
                builtinIgnored: ad.builtinIgnored)
            if verdict.isAllowed { steps.append(.disconnectBuiltin(builtin.key)) }
        }
        return steps
    }

    // MARK: Step 1

    package static func visibilitySteps(_ inputs: ConnectInputs) -> [PlanStep] {
        var steps: [PlanStep] = []
        let displays = inputs.displays.sorted { $0.key.rawValue < $1.key.rawValue }
        let strong = displays.filter(\.strong)
        let anyVisible = displays.contains { $0.strong || $0.weak }
        if strong.isEmpty {
            for d in displays where d.disabledBySnaptic { steps.append(.reenable(d.key)) }
            for d in displays where d.dimmedBelowFloor && d.isActive { steps.append(.raiseFloor(d.key)) }
        }
        let graceSeconds = ConnectPlan.grace(secondsSinceWakeOrUnlock: inputs.secondsSinceWakeOrUnlock, anyVisible: anyVisible)
        var mainMoved = false
        for h in inputs.hosts.sorted(by: { $0.specID.rawValue < $1.specID.rawValue }) {
            guard h.isLive, let missing = h.physicalMissingSeconds else { continue }
            if missing >= graceSeconds {
                steps.append(.destroyHost(h.specID, reason: .orphaned))
            } else if h.isMain, !mainMoved, let target = preferredStrong(strong) {
                steps.append(.moveMain(to: target.key))
                mainMoved = true
            }
        }
        // Invariant 7: main must be strongly visible while any display is.
        if !mainMoved, let main = displays.first(where: \.isMain), !main.strong, let target = preferredStrong(strong) {
            steps.append(.moveMain(to: target.key))
        }
        return steps
    }

    private static func preferredStrong(_ strong: [PlanDisplay]) -> PlanDisplay? {
        strong.first { $0.isBuiltin } ?? strong.first
    }

    // MARK: Step 2

    private static func virtualSteps(_ inputs: ConnectInputs, present: Set<DisplayKey>, skipping orphaned: Set<StableID>) -> [PlanStep] {
        var steps: [PlanStep] = []
        let hosts = Dictionary(inputs.hosts.map { ($0.specID, $0) }, uniquingKeysWith: { a, _ in a })
        if inputs.effective.contains(.smartHiDPI) {
            for pair in inputs.pairs.sorted(by: { $0.physical.rawValue < $1.physical.rawValue }) where pair.physicalPresent {
                guard !orphaned.contains(pair.specID) else { continue }
                let host = hosts[pair.specID]
                if let host, host.isLive {
                    if !host.identityMatches {
                        steps.append(.destroyHost(pair.specID, reason: .mismatch))
                        steps.append(.createVirtual(pair.specID, purpose: .smartHiDPI(physical: pair.physical)))
                    } else if host.boundTo != pair.physical {
                        steps.append(pair.tier1Verified ? .rebind(specID: pair.specID, physical: pair.physical)
                                     : .promptMirror(specID: pair.specID, target: pair.physical))
                    }
                } else {
                    steps.append(.createVirtual(pair.specID, purpose: .smartHiDPI(physical: pair.physical)))
                }
            }
        }
        if inputs.effective.contains(.virtualScreens) {
            for screen in inputs.virtualScreens.sorted(by: { $0.specID.rawValue < $1.specID.rawValue }) {
                guard !orphaned.contains(screen.specID) else { continue }
                let host = hosts[screen.specID]
                let live = host?.isLive == true
                let wants = screen.desiredConnected(present: present)
                if wants && !live {
                    steps.append(.createVirtual(screen.specID, purpose: .virtualScreen))
                } else if !wants && live && screen.isAssociationManaged {
                    steps.append(.destroyHost(screen.specID, reason: .associationEnded))
                    continue
                } else if wants && live && host?.identityMatches == false {
                    steps.append(.destroyHost(screen.specID, reason: .mismatch))
                    steps.append(.createVirtual(screen.specID, purpose: .virtualScreen))
                }
                guard wants else { continue }
                for a in screen.associations where present.contains(a.target) {
                    switch a.presentation {
                    case .none: break
                    case .mirror:
                        if host?.boundTo != a.target { steps.append(.promptMirror(specID: screen.specID, target: a.target)) }
                    case .stream:
                        steps.append(.promptStream(specID: screen.specID, target: a.target, flipped: false))
                    case .flippedStream:
                        steps.append(.promptStream(specID: screen.specID, target: a.target, flipped: true))
                    }
                }
            }
        }
        return steps
    }

    // MARK: Helpers

    /// True when applying the layout would change the mode of the only strongly visible display.
    private static func modesetsOnly(_ layout: SavedLayout, onlyStrong: DisplayKey?, displays: [PlanDisplay]) -> Bool {
        guard let k = onlyStrong, let want = layout.displays[k]?.mode,
              let d = displays.first(where: { $0.key == k }) else { return false }
        guard let current = d.mode else { return true }
        return ProtectionDiff.resolve(want, in: [current]) == nil
    }
}

extension ConnectInputs {
    /// Protection's live view of the active displays.
    package var liveStates: [LiveDisplayState] {
        displays.filter(\.isActive).map { d in
            LiveDisplayState(key: d.key, mode: d.mode, x: d.x, y: d.y, rotation: d.rotation, mirrorOf: d.mirrorOf,
                             isMain: d.isMain, availableModes: d.availableModes)
        }
    }
}

/// Invariant 6 for automatic plans: 1 per 2 s globally, 3 per display per 60 s. Plans that
/// change nothing aren't counted, and visibility restores bypass the limits (§4.2, R4C §4.4).
package struct PlanRateLimiter: Equatable, Sendable {
    package static let globalInterval: Double = 2
    package static let perDisplayWindow: Double = 60
    package static let perDisplayLimit = 3

    private var lastGlobal: Double?
    private var perDisplay: [DisplayKey: [Double]] = [:]

    package init() {}

    /// Whether a plan touching `keys` may run now; records it when allowed.
    package mutating func allow(keys: Set<DisplayKey>, now: Double) -> Bool {
        if let last = lastGlobal, now >= last, now - last < Self.globalInterval { return false }
        var pruned: [DisplayKey: [Double]] = [:]
        for (k, times) in perDisplay {
            let kept = times.filter { now >= $0 && now - $0 < Self.perDisplayWindow }
            if !kept.isEmpty { pruned[k] = kept }
        }
        perDisplay = pruned
        for k in keys where (perDisplay[k]?.count ?? 0) >= Self.perDisplayLimit { return false }
        lastGlobal = now
        for k in keys { perDisplay[k, default: []].append(now) }
        return true
    }
}

/// When a mode change Snaptic didn't make becomes the persisted choice (R5.3): only if it
/// lasted 10 s and didn't happen within 15 s of a connect or wake (so macOS 27.2's restore
/// bug doesn't teach us the wrong mode).
package enum PersistedChoiceLearning {
    package static let settleSeconds: Double = 10
    package static let connectQuietSeconds: Double = 15

    package static func shouldLearn(changedAt: Double, now: Double, lastConnectOrWake: Double?, causedBySnaptic: Bool) -> Bool {
        guard !causedBySnaptic, now >= changedAt, now - changedAt >= settleSeconds else { return false }
        if let c = lastConnectOrWake, changedAt >= c, changedAt - c < connectQuietSeconds { return false }
        if let c = lastConnectOrWake, changedAt < c { return false }
        return true
    }
}

/// Coalescing for steps 2–5: run after `quietSeconds` without reconfiguration, but never
/// later than `quietCapSeconds` after the first event (R5.3).
package struct QuietWindow: Equatable, Sendable {
    package private(set) var firstEvent: Double?
    package private(set) var lastEvent: Double?

    package init() {}

    package mutating func note(_ now: Double) {
        if firstEvent == nil { firstEvent = now }
        lastEvent = now
    }

    /// Seconds until the coalesced run is due, or nil when nothing is pending.
    package func dueIn(now: Double) -> Double? {
        guard let first = firstEvent, let last = lastEvent else { return nil }
        let quietDue = last + ConnectPlan.quietSeconds
        let capDue = first + ConnectPlan.quietCapSeconds
        return max(0, min(quietDue, capDue) - now)
    }

    package mutating func reset() {
        firstEvent = nil
        lastEvent = nil
    }
}
