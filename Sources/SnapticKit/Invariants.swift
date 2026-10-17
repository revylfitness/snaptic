import Foundation

// Visibility classification and the hard safety invariants (owner: B). PLAN §4.1, §4.2,
// R5.2. Pure functions over LayoutSnapshot so the app, the guard and the tests share them.

/// How well a display lets the user see and operate the Mac (PLAN §4.1).
package enum Visibility: String, Codable, Sendable, Comparable {
    case none, weak, strong

    private var rank: Int {
        switch self {
        case .none: return 0
        case .weak: return 1
        case .strong: return 2
        }
    }

    package static func < (a: Visibility, b: Visibility) -> Bool { a.rank < b.rank }
}

/// Facts the invariant check needs beyond the layout itself.
package struct InvariantContext: Equatable, Sendable {
    /// The guard is running and acknowledged (needed for long-arm states, invariant 4).
    package var guardAvailable: Bool
    /// Displays the request wants to dim to black (invariant 3).
    package var dimToBlack: Set<UInt32>
    /// An unattended (restore-class) request: may not modeset the only strongly visible display.
    package var unattended: Bool

    package init(guardAvailable: Bool = true, dimToBlack: Set<UInt32> = [], unattended: Bool = false) {
        self.guardAvailable = guardAvailable
        self.dimToBlack = dimToBlack
        self.unattended = unattended
    }
}

/// Why Snaptic must keep the guard long-armed (invariant 4), and what the guard undoes.
package struct LongArmRequirement: Equatable, Sendable {
    package enum Reason: String, Codable, Sendable, CaseIterable {
        case disabledDisplay, mirrorsSnapticVirtual, dimToBlack, overlayBelowFloor
    }

    package var reasons: Set<Reason>
    /// Re-enable / un-mirror operations (CAS), in undo order.
    package var undo: [UndoOp]
    /// Gamma dims below the floor: the guard restores ColorSync.
    package var restoreColorSync: Bool

    package init(reasons: Set<Reason> = [], undo: [UndoOp] = [], restoreColorSync: Bool = false) {
        self.reasons = reasons
        self.undo = undo
        self.restoreColorSync = restoreColorSync
    }

    package var isEmpty: Bool { reasons.isEmpty }

    /// R5.2: hang actions apply only to states that impair visibility.
    package var impairsVisibility: Bool {
        reasons.contains(.disabledDisplay) || reasons.contains(.dimToBlack) || reasons.contains(.overlayBelowFloor)
    }

    /// Dim conditions that justify killing a hung parent after 30 s (PLAN §4.5).
    package var dimImpairing: Bool { reasons.contains(.dimToBlack) || reasons.contains(.overlayBelowFloor) }
}

package enum Invariants {
    /// Software dim floor while no other display is strongly visible (invariant 3).
    package static let dimFloor = 0.08
    /// Overlay dimming below this keeps the guard long-armed (invariant 4) and is
    /// raised while the confirm panel or an authentication window shows.
    package static let overlayImpairThreshold = 0.30
    /// Mirror chains longer than this are treated as broken (CG sets are flat).
    private static let maxMirrorDepth = 8

    // MARK: Visibility (§4.1)

    /// The source at the top of `id`'s mirror chain, or nil for a cycle or a missing source.
    package static func mirrorRoot(of id: UInt32, in s: LayoutSnapshot) -> UInt32? {
        var current = id
        var seen: Set<UInt32> = [id]
        for _ in 0..<maxMirrorDepth {
            guard let e = s.entry(current) else { return nil }
            guard let next = e.mirrorOf else { return current }
            if seen.contains(next) { return nil }
            seen.insert(next)
            current = next
        }
        return nil
    }

    /// Visibility of every online display.
    package static func visibility(_ s: LayoutSnapshot) -> [UInt32: Visibility] {
        var result: [UInt32: Visibility] = [:]
        // Pass 1: displays that show their own framebuffer.
        for e in s.entries {
            result[e.id] = ownFramebufferVisibility(e)
        }
        // Pass 2: mirror members inherit from their (root) source.
        for e in s.entries where e.mirrorOf != nil {
            result[e.id] = memberVisibility(e, in: s, own: result)
        }
        return result
    }

    private static func ownFramebufferVisibility(_ e: LayoutEntry) -> Visibility {
        guard e.isOnline, e.isActive, !e.isAsleep, e.mirrorOf == nil else { return .none }
        guard e.effectiveDim >= dimFloor else { return .none }
        switch e.transport {
        case .builtin, .wired: return .strong
        case .foreignVirtual, .airplay, .displayLink, .sidecar: return .weak
        case .snapticVirtual: return e.headlessPrimary ? .weak : .none
        }
    }

    private static func memberVisibility(_ e: LayoutEntry, in s: LayoutSnapshot, own: [UInt32: Visibility]) -> Visibility {
        guard e.isOnline, !e.isAsleep, e.isPhysical, e.effectiveDim >= dimFloor else { return .none }
        guard let rootID = mirrorRoot(of: e.id, in: s), rootID != e.id, let root = s.entry(rootID) else { return .none }
        guard root.isOnline, root.isActive else { return .none }
        if root.transport == .snapticVirtual {
            // A live Snaptic virtual (Smart HiDPI or association): its framebuffer is what
            // the member shows, so its own dimming counts too.
            return root.effectiveDim >= dimFloor ? .strong : .none
        }
        return own[rootID] == .strong ? .strong : .none
    }

    package static func stronglyVisible(_ s: LayoutSnapshot) -> Set<UInt32> {
        Set(visibility(s).filter { $0.value == .strong }.map(\.key))
    }

    package static func weaklyVisible(_ s: LayoutSnapshot) -> Set<UInt32> {
        Set(visibility(s).filter { $0.value == .weak }.map(\.key))
    }

    package static func visible(_ s: LayoutSnapshot) -> Set<UInt32> {
        Set(visibility(s).filter { $0.value != .none }.map(\.key))
    }

    /// Where the confirm panel must appear (invariant 2): every visible display that shows
    /// its own framebuffer, plus the source of every visible mirror member.
    package static func panelHosts(_ s: LayoutSnapshot) -> Set<UInt32> {
        let vis = visibility(s)
        var hosts: Set<UInt32> = []
        for e in s.entries where vis[e.id, default: .none] != .none {
            if e.mirrorOf == nil {
                hosts.insert(e.id)
            } else if let root = mirrorRoot(of: e.id, in: s) {
                hosts.insert(root)
            }
        }
        return hosts
    }

    /// The software floor for `id`: 0 when another display stays strongly visible, else 0.08.
    package static func dimFloor(for id: UInt32, in s: LayoutSnapshot) -> Double {
        var others = s
        if let i = others.index(of: id) { others.entries[i].softwareDim = 0; others.entries[i].overlayDim = 0 }
        return stronglyVisible(others).isEmpty ? dimFloor : 0
    }

    // MARK: Prediction

    /// The layout after `changes`, as CG would leave it (best effort; used only for checks).
    package static func predict(_ before: LayoutSnapshot, applying changes: [DisplayChange]) -> LayoutSnapshot {
        var s = before
        for change in changes {
            guard let i = s.index(of: change.displayID) else { continue }
            switch change {
            case .mode(_, let m):
                s.entries[i].mode = m
                let sideways = s.entries[i].isRotatedSideways
                s.entries[i].width = sideways ? m.pointHeight : m.pointWidth
                s.entries[i].height = sideways ? m.pointWidth : m.pointHeight
            case .origin(_, let x, let y):
                s.entries[i].x = x
                s.entries[i].y = y
            case .mirror(_, let source):
                if let source, source != change.displayID {
                    s.entries[i].mirrorOf = source
                } else {
                    s.entries[i].mirrorOf = nil
                    if s.entries[i].isOnline && !s.entries[i].disabledBySnaptic { s.entries[i].isActive = true }
                }
            case .enabled(_, let on):
                s.entries[i].isActive = on && s.entries[i].isOnline
                s.entries[i].disabledBySnaptic = !on
                if !on { s.entries[i].mirrorOf = nil }
            case .main(let id):
                guard s.entries[i].isEnabled else { continue }
                let dx = s.entries[i].x, dy = s.entries[i].y
                for j in s.entries.indices {
                    s.entries[j].x = s.entries[j].x &- dx
                    s.entries[j].y = s.entries[j].y &- dy
                }
                s.mainID = id
            case .rotation(_, let degrees):
                let wasSideways = s.entries[i].isRotatedSideways
                s.entries[i].rotation = normalizedRotation(degrees)
                if wasSideways != s.entries[i].isRotatedSideways {
                    let w = s.entries[i].width
                    s.entries[i].width = s.entries[i].height
                    s.entries[i].height = w
                }
            case .underscan(_, let value):
                s.entries[i].underscan = value
            case .hdr(_, let on):
                s.entries[i].hdrEnabled = on
            }
        }
        // A mirror whose source went away (disabled or missing) breaks, as CG does.
        for i in s.entries.indices {
            guard let src = s.entries[i].mirrorOf else { continue }
            if let root = s.entry(src), root.isEnabled { continue }
            s.entries[i].mirrorOf = nil
            s.entries[i].isActive = s.entries[i].isOnline && !s.entries[i].disabledBySnaptic
        }
        return s
    }

    package static func normalizedRotation(_ degrees: Int) -> Int {
        let r = ((degrees % 360) + 360) % 360
        return (r / 90) * 90
    }

    // MARK: Invariants (§4.2)

    /// Every invariant `changes` would break, given the live layout `before`.
    package static func violations(before: LayoutSnapshot, changes: [DisplayChange],
                                   context: InvariantContext = InvariantContext()) -> [InvariantViolation] {
        let after = predict(before, applying: changes)
        var result: [InvariantViolation] = []

        // 1. Relative visibility.
        let strongBefore = stronglyVisible(before), strongAfter = stronglyVisible(after)
        let visibleBefore = visible(before), visibleAfter = visible(after)
        let lostAll = strongBefore.isEmpty ? (!visibleBefore.isEmpty && visibleAfter.isEmpty) : strongAfter.isEmpty
        if lostAll {
            result.append(.noVisibleDisplay)
        }
        // 2. Panel hosts.
        if !panelHosts(before).isEmpty && panelHosts(after).isEmpty {
            result.append(.noPanelHost)
        }
        // 3. Dim to black needs another strongly visible display.
        for id in context.dimToBlack.sorted() where dimFloor(for: id, in: after) > 0 {
            result.append(.dimToBlackWithoutOtherVisible(id))
        }
        // 4. Long-arm states need the guard.
        if !context.guardAvailable {
            let needBefore = requiredLongArm(before).reasons
            if !requiredLongArm(after).reasons.subtracting(needBefore).isEmpty {
                result.append(.guardNotArmed)
            }
        }
        // 7. Main must be strongly visible while any display is (else weakly visible).
        let vis = visibility(after)
        let mainVis = mainVisibility(after, vis: vis)
        if !strongAfter.isEmpty {
            if mainVis != .strong { result.append(.mainNotVisible(after.mainID)) }
        } else if !visibleAfter.isEmpty, mainVis == .none {
            result.append(.mainNotVisible(after.mainID))
        }
        // R5.2: unattended changes never modeset the only strongly visible display.
        if context.unattended, strongBefore.count == 1, let only = strongBefore.first {
            let touched = changes.contains { change in
                switch change {
                case .mode, .rotation, .hdr, .underscan: return modesetTarget(change, in: before) == only
                default: return false
                }
            }
            if touched { result.append(.onlyDisplayUnsupported(only)) }
        }
        return result
    }

    /// The main display's visibility; a mirror member that is "main" counts via its set.
    private static func mainVisibility(_ s: LayoutSnapshot, vis: [UInt32: Visibility]) -> Visibility {
        let own = vis[s.mainID, default: .none]
        if own != .none { return own }
        // Main may be a mirror source whose members carry the visibility (e.g. Smart HiDPI).
        let members = s.entries.filter { $0.mirrorOf != nil && mirrorRoot(of: $0.id, in: s) == s.mainID }
        return members.map { vis[$0.id, default: .none] }.max() ?? .none
    }

    /// The physical display a mode-like change ends up modesetting (a Snaptic virtual's
    /// mode change re-modesets the panels that mirror it).
    private static func modesetTarget(_ change: DisplayChange, in s: LayoutSnapshot) -> UInt32? {
        let id = change.displayID
        guard let e = s.entry(id) else { return nil }
        if e.transport == .snapticVirtual {
            return s.entries.first { $0.mirrorOf == id && $0.isPhysical }?.id ?? id
        }
        return id
    }

    // MARK: Long-arm (invariant 4)

    /// The long-arm state `s` needs. Empty when nothing Snaptic did impairs visibility.
    package static func requiredLongArm(_ s: LayoutSnapshot) -> LongArmRequirement {
        var req = LongArmRequirement()
        for e in s.entries where e.isOnline {
            if e.disabledBySnaptic && !e.isEnabled {
                req.reasons.insert(.disabledDisplay)
                req.undo.append(UndoOp(displayID: e.id, fingerprint: e.fingerprint, property: .enabled,
                                       restore: .bool(true), expected: .bool(false)))
            }
            if e.isPhysical, let src = e.mirrorOf, s.entry(src)?.transport == .snapticVirtual {
                req.reasons.insert(.mirrorsSnapticVirtual)
                req.undo.append(UndoOp(displayID: e.id, fingerprint: e.fingerprint, property: .mirrorOf,
                                       restore: .display(nil), expected: .display(src)))
            }
            if e.softwareDim < dimFloor {
                req.reasons.insert(.dimToBlack)
                req.restoreColorSync = true
            }
            if e.overlayDim < overlayImpairThreshold {
                req.reasons.insert(.overlayBelowFloor)
            }
        }
        req.undo = UndoPlanner.order(req.undo)
        return req
    }

    // MARK: Panic (invariant 8)

    /// Which Snaptic virtual hosts panic may shut down: all of them, unless that would
    /// leave nothing visible, in which case a lone `headlessPrimary` stays.
    package static func panicRemovableVirtuals(_ s: LayoutSnapshot) -> Set<UInt32> {
        let virtuals = Set(s.entries.filter { $0.transport == .snapticVirtual }.map(\.id))
        guard !virtuals.isEmpty else { return [] }
        // Predict: virtuals gone, physical displays that mirrored them show their own framebuffer.
        var after = s
        after.entries.removeAll { virtuals.contains($0.id) }
        for i in after.entries.indices where after.entries[i].mirrorOf.map({ virtuals.contains($0) }) == true {
            after.entries[i].mirrorOf = nil
            after.entries[i].isActive = after.entries[i].isOnline && !after.entries[i].disabledBySnaptic
        }
        if !visible(after).isEmpty || visible(s).isEmpty { return virtuals }
        let keep = s.entries.filter { virtuals.contains($0.id) && $0.headlessPrimary }.map(\.id).sorted().first
        guard let keep else { return virtuals }
        return virtuals.subtracting([keep])
    }
}
