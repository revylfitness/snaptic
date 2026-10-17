import Foundation

// Compare-and-swap undo operations (owner: B). See R2C §5.1 and PLAN R5.2.

package enum DisplayProperty: String, Codable, Sendable { case enabled, mirrorOf, mode, origin, main, rotation, underscan, hdr }

package enum PropertyValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case display(UInt32?)
    case mode(ModeRef)
    case point(x: Int32, y: Int32)
    case degrees(Int)
    case fraction(Double)
}

package struct UndoOp: Codable, Equatable, Sendable {
    package var displayID: UInt32
    /// Re-resolves the id if the display was replugged.
    package var fingerprint: String
    package var property: DisplayProperty
    /// The value to put back.
    package var restore: PropertyValue
    /// The value the transaction applied; revert only if the live value still equals it.
    package var expected: PropertyValue

    package init(displayID: UInt32, fingerprint: String, property: DisplayProperty, restore: PropertyValue, expected: PropertyValue) {
        self.displayID = displayID
        self.fingerprint = fingerprint
        self.property = property
        self.restore = restore
        self.expected = expected
    }

    /// Directions allowed when replaying a journal at launch (§4.6).
    package var isSafeDirection: Bool {
        switch (property, restore) {
        case (.enabled, .bool(true)), (.mirrorOf, .display(nil)): return true
        default: return false
        }
    }
}

extension PropertyValue {
    /// Equality for CAS checks: fractions within 0.001, modes by shape (ioModeID is a hint).
    package func matches(_ other: PropertyValue) -> Bool {
        switch (self, other) {
        case (.fraction(let a), .fraction(let b)): return abs(a - b) < 0.001
        case (.mode(let a), .mode(let b)): return a == b || a.sameShape(as: b)
        default: return self == other
        }
    }
}

extension UndoOp {
    /// Where this op runs in the single undo order (R5.2).
    package var stage: UndoStage {
        switch (property, restore) {
        case (.enabled, .bool(true)): return .enable
        case (.mirrorOf, .display(nil)): return .unmirror
        case (.rotation, _), (.underscan, _), (.hdr, _): return .monitorPanel
        default: return .configure
        }
    }
}

/// The R5.2 stages, in order. Mode ops run after a fresh mode read (step 4).
package enum UndoStage: Int, Codable, Sendable, CaseIterable, Comparable {
    case enable, unmirror, monitorPanel, configure
    package static func < (a: UndoStage, b: UndoStage) -> Bool { a.rawValue < b.rawValue }
}

package enum UndoPlanner {
    /// Undo ops for a request, computed from the request and the before-snapshot, never
    /// from a diff (WindowServer re-snaps other displays' origins). One op per
    /// (display, property): `restore` is the before value, `expected` the last value requested.
    package static func undo(for changes: [DisplayChange], before: LayoutSnapshot) -> [UndoOp] {
        var ops: [UndoOp] = []
        func upsert(_ op: UndoOp) {
            if let i = ops.firstIndex(where: { $0.displayID == op.displayID && $0.property == op.property }) {
                ops[i].expected = op.expected
            } else {
                ops.append(op)
            }
        }
        for change in changes {
            let id = change.displayID
            guard let e = before.entry(id) else { continue }
            let fp = e.fingerprint
            switch change {
            case .mode(_, let m):
                guard let old = e.mode else { continue }
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .mode, restore: .mode(old), expected: .mode(m)))
            case .origin(_, let x, let y):
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .origin,
                              restore: .point(x: e.x, y: e.y), expected: .point(x: x, y: y)))
            case .mirror(_, let source):
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .mirrorOf,
                              restore: .display(e.mirrorOf), expected: .display(source)))
            case .enabled(_, let on):
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .enabled,
                              restore: .bool(e.isEnabled), expected: .bool(on)))
            case .main(let target):
                // The op lives on the previous main display: CAS checks that `target` is still main.
                guard let old = before.entry(before.mainID) else { continue }
                if let i = ops.firstIndex(where: { $0.property == .main }) {
                    ops[i].expected = .display(target)
                } else {
                    ops.append(UndoOp(displayID: old.id, fingerprint: old.fingerprint, property: .main,
                                      restore: .display(old.id), expected: .display(target)))
                }
            case .rotation(_, let degrees):
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .rotation,
                              restore: .degrees(e.rotation), expected: .degrees(Invariants.normalizedRotation(degrees))))
            case .underscan(_, let value):
                guard let old = e.underscan else { continue }
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .underscan,
                              restore: .fraction(old), expected: .fraction(value)))
            case .hdr(_, let on):
                guard let old = e.hdrEnabled else { continue }
                upsert(UndoOp(displayID: id, fingerprint: fp, property: .hdr, restore: .bool(old), expected: .bool(on)))
            }
        }
        return ops.filter { !$0.restore.matches($0.expected) }
    }

    /// Re-resolves an op's display after a replug: same id and fingerprint, else the unique
    /// display with that fingerprint. Nil if the display is gone or ambiguous.
    package static func resolve(_ op: UndoOp, in live: LayoutSnapshot) -> UndoOp? {
        if let e = live.entry(op.displayID), op.fingerprint.isEmpty || e.fingerprint == op.fingerprint { return op }
        guard let e = live.entry(fingerprint: op.fingerprint) else { return nil }
        var moved = op
        if case .display(let old?) = op.restore, old == op.displayID, op.property == .main {
            moved.restore = .display(e.id)
        }
        moved.displayID = e.id
        return moved
    }

    /// The live value of an op's property, or nil when unknown.
    package static func liveValue(_ op: UndoOp, in live: LayoutSnapshot) -> PropertyValue? {
        guard let e = live.entry(op.displayID) else { return nil }
        switch op.property {
        case .enabled: return .bool(e.isEnabled)
        case .mirrorOf: return .display(e.mirrorOf)
        case .mode: return e.mode.map { .mode($0) }
        case .origin: return .point(x: e.x, y: e.y)
        case .main: return .display(live.mainID)
        case .rotation: return .degrees(e.rotation)
        case .underscan: return e.underscan.map { .fraction($0) }
        case .hdr: return e.hdrEnabled.map { .bool($0) }
        }
    }

    /// Ops whose live value still equals what the transaction applied (compare-and-swap).
    /// A value someone else set since (System Settings, WindowServer's own revert) is left alone.
    package static func pending(_ ops: [UndoOp], live: LayoutSnapshot) -> [UndoOp] {
        ops.compactMap { op in
            guard let resolved = resolve(op, in: live), let value = liveValue(resolved, in: live) else { return nil }
            return value.matches(resolved.expected) ? resolved : nil
        }
    }

    /// The single undo order (R5.2): enable → un-mirror → MonitorPanel in reverse
    /// (rotation before underscan before HDR) → modes, re-mirrors, origins, main → disables.
    package static func order(_ ops: [UndoOp]) -> [UndoOp] {
        func rank(_ op: UndoOp) -> Int {
            switch (op.property, op.restore) {
            case (.enabled, .bool(true)): return 0
            case (.mirrorOf, .display(nil)): return 1
            case (.rotation, _): return 2
            case (.underscan, _): return 3
            case (.hdr, _): return 4
            case (.mode, _): return 5
            case (.mirrorOf, _): return 6
            case (.origin, _): return 7
            case (.main, _): return 8
            case (.enabled, _): return 9
            }
        }
        return ops.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// The ordered ops grouped by stage; each group is applied, then the layout settles.
    package static func stages(_ ops: [UndoOp]) -> [(stage: UndoStage, ops: [UndoOp])] {
        var groups: [(stage: UndoStage, ops: [UndoOp])] = []
        for op in order(ops) {
            if let last = groups.last, last.stage == op.stage {
                groups[groups.count - 1].ops.append(op)
            } else {
                groups.append((op.stage, [op]))
            }
        }
        return groups
    }

    /// The change that performs an op's restore.
    package static func change(for op: UndoOp) -> DisplayChange? {
        switch (op.property, op.restore) {
        case (.enabled, .bool(let on)): return .enabled(op.displayID, on)
        case (.mirrorOf, .display(let source)): return .mirror(op.displayID, of: source)
        case (.mode, .mode(let m)): return .mode(op.displayID, m)
        case (.origin, .point(let x, let y)): return .origin(op.displayID, x: x, y: y)
        case (.main, .display(let id?)): return .main(id)
        case (.rotation, .degrees(let d)): return .rotation(op.displayID, d)
        case (.underscan, .fraction(let f)): return .underscan(op.displayID, f)
        case (.hdr, .bool(let on)): return .hdr(op.displayID, on)
        default: return nil
        }
    }

    /// Merges a new undo set into an existing one: for a (display, property) already
    /// covered, the older restore wins and the newer expected value is kept.
    package static func merge(_ existing: [UndoOp], _ newer: [UndoOp]) -> [UndoOp] {
        var result = existing
        for op in newer {
            if let i = result.firstIndex(where: { $0.displayID == op.displayID && $0.property == op.property }) {
                result[i].expected = op.expected
            } else {
                result.append(op)
            }
        }
        return result.filter { !$0.restore.matches($0.expected) }
    }
}
