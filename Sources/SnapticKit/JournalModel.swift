import Foundation

// Revert journals (owner: B). PLAN §4.6. The app writes them atomically before a trial or
// restore; the guard and the next launch replay them. Pure decisions live here.

/// `journal.json`: what to undo if Snaptic and its guard both die mid-trial.
package struct SessionJournal: Codable, Equatable, Sendable {
    package static let currentVersion = 1

    package var version: Int
    package var bootSessionUUID: String
    package var uid: UInt32
    /// Unix seconds.
    package var createdAt: Double
    /// Physical fingerprints online when written (sorted).
    package var fingerprints: [String]
    package var undo: [UndoOp]
    package var restoreColorSync: Bool
    /// The trial this journal protects, if any (nil for a restore/long-arm state).
    package var trialID: UInt64?

    package init(bootSessionUUID: String, uid: UInt32, createdAt: Double, fingerprints: [String], undo: [UndoOp],
                 restoreColorSync: Bool = false, trialID: UInt64? = nil) {
        version = Self.currentVersion
        self.bootSessionUUID = bootSessionUUID
        self.uid = uid
        self.createdAt = createdAt
        self.fingerprints = fingerprints.sorted()
        self.undo = undo
        self.restoreColorSync = restoreColorSync
        self.trialID = trialID
    }
}

/// One MonitorPanel step (HDR, underscan, rotation) a trial applied; reverted at the next
/// launch unless confirmed, even after a reboot and in Safe Mode.
package struct PermanentOp: Codable, Equatable, Sendable {
    package var trialID: UInt64
    package var op: UndoOp
    package init(trialID: UInt64, op: UndoOp) {
        self.trialID = trialID
        self.op = op
    }
}

/// `permanent.json`.
package struct PermanentJournal: Codable, Equatable, Sendable {
    package var version: Int
    package var uid: UInt32
    package var ops: [PermanentOp]

    package init(uid: UInt32, ops: [PermanentOp] = []) {
        version = SessionJournal.currentVersion
        self.uid = uid
        self.ops = ops
    }

    package var isEmpty: Bool { ops.isEmpty }

    /// Adds a trial's MonitorPanel undo ops (replacing earlier entries for the same trial).
    package mutating func add(trial: UInt64, ops newOps: [UndoOp]) {
        ops.removeAll { $0.trialID == trial }
        ops += newOps.filter { $0.stage == .monitorPanel }.map { PermanentOp(trialID: trial, op: $0) }
        if ops.count > JournalModel.maxOps { ops.removeFirst(ops.count - JournalModel.maxOps) }
    }

    /// Keep or revert finished: the trial's ops no longer need recovery.
    package mutating func resolve(trial: UInt64) { ops.removeAll { $0.trialID == trial } }
}

package enum JournalModel {
    package static let sessionFileName = "journal.json"
    package static let permanentFileName = "permanent.json"
    package static let claimedPrefix = "journal.claimed."
    package static let claimedSuffix = ".json"
    package static let maxAgeSeconds: Double = 24 * 3600
    package static let maxFileBytes = 256 * 1024
    package static let maxOps = 512

    package enum Decision: Equatable, Sendable {
        case discard(String)
        /// Ops to apply, already filtered to safe directions and ordered.
        case recover([UndoOp], restoreColorSync: Bool)
    }

    /// PLAN §4.6: discard on a boot, uid or fingerprint-set mismatch or after 24 h; otherwise
    /// keep only safe directions (re-enable, un-mirror, public-list modes), CAS against `live`.
    package static func evaluate(_ j: SessionJournal, bootSessionUUID: String, uid: UInt32, now: Double,
                                 live: LayoutSnapshot, publicModes: (UInt32) -> Set<ModeRef>) -> Decision {
        guard j.version == SessionJournal.currentVersion else { return .discard("version") }
        guard !j.bootSessionUUID.isEmpty, j.bootSessionUUID == bootSessionUUID else { return .discard("boot") }
        guard j.uid == uid else { return .discard("uid") }
        guard now >= j.createdAt - 60, now - j.createdAt <= maxAgeSeconds else { return .discard("age") }
        guard j.fingerprints == live.physicalFingerprints else { return .discard("displays") }
        let ops = recoverable(j.undo, live: live, publicModes: publicModes)
        if ops.isEmpty && !j.restoreColorSync { return .discard("nothing to undo") }
        return .recover(ops, restoreColorSync: j.restoreColorSync)
    }

    /// Safe-direction ops whose live value still equals what was applied, in undo order.
    package static func recoverable(_ ops: [UndoOp], live: LayoutSnapshot,
                                    publicModes: (UInt32) -> Set<ModeRef>) -> [UndoOp] {
        let safe = UndoPlanner.pending(ops, live: live).filter { op in
            if op.isSafeDirection { return true }
            if op.property == .mode, case .mode(let m) = op.restore {
                return publicModes(op.displayID).contains { $0 == m || $0.sameShape(as: m) }
            }
            return false
        }
        return UndoPlanner.order(safe)
    }

    /// Permanent ops to revert at launch for this user, in undo order. The caller applies
    /// them with CAS against the live MonitorPanel values.
    package static func permanentToRevert(_ j: PermanentJournal, uid: UInt32) -> [UndoOp] {
        guard j.uid == uid, j.version == SessionJournal.currentVersion else { return [] }
        // Reverse application order across trials: latest trial first, then the R5.2 order.
        var seen: Set<String> = []
        var ops: [UndoOp] = []
        for p in j.ops.reversed() {
            let k = "\(p.op.fingerprint)|\(p.op.property.rawValue)"
            if seen.contains(k) { continue }
            seen.insert(k)
            ops.append(p.op)
        }
        // Earlier trials' restore values win for the same property: take the first-applied op's restore.
        let firstRestore = Dictionary(j.ops.map { ("\($0.op.fingerprint)|\($0.op.property.rawValue)", $0.op.restore) },
                                      uniquingKeysWith: { first, _ in first })
        ops = ops.map { op in
            var o = op
            if let r = firstRestore["\(op.fingerprint)|\(op.property.rawValue)"] { o.restore = r }
            return o
        }
        return UndoPlanner.order(ops)
    }

    // MARK: Files

    package static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), data.count <= maxFileBytes else { return nil }
        return data
    }

    package static func decodeSession(_ data: Data) -> SessionJournal? {
        guard data.count <= maxFileBytes, let j = try? JSONDecoder().decode(SessionJournal.self, from: data),
              j.undo.count <= maxOps else { return nil }
        return j
    }

    package static func decodePermanent(_ data: Data) -> PermanentJournal? {
        guard data.count <= maxFileBytes, let j = try? JSONDecoder().decode(PermanentJournal.self, from: data),
              j.ops.count <= maxOps else { return nil }
        return j
    }

    /// "journal.claimed.<pid>.json"
    package static func claimedName(pid: Int32) -> String { "\(claimedPrefix)\(pid)\(claimedSuffix)" }

    /// The pid in a claimed journal's file name, or nil when the name isn't one.
    package static func claimedPID(_ name: String) -> Int32? {
        guard name.hasPrefix(claimedPrefix), name.hasSuffix(claimedSuffix) else { return nil }
        let middle = name.dropFirst(claimedPrefix.count).dropLast(claimedSuffix.count)
        guard !middle.isEmpty, middle.count <= 10, middle.allSatisfy({ $0.isASCII && $0.isNumber }),
              let pid = Int32(middle), pid > 0 else { return nil }
        return pid
    }
}
