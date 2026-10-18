import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.14 + R5-3 (kind S): the declared lossy
// decoder is real; the load-time clamp is a safe stub. Key SnapticAwakeStateV1.

package struct AwakeRuntimeSnapshot: ConfigModel {
    package static let key = "SnapticAwakeStateV1"

    /// kern.bootsessionuuid when written.
    package var bootSession: String
    package var manual: AwakeSession?
    /// `.process` holds only, ≤ 8, lossyUniqueArray (N17, N18, R5-3).
    package var holds: [AwakeHold]
    package var suppressions: LossyMap<StableID, TriggerSuppression>
    /// Wall time; "Pause Rules".
    package var pausedUntil: Double?
    package var guardMemory: GuardMemory

    package init() {
        bootSession = ""
        manual = nil
        holds = []
        suppressions = LossyMap()
        pausedUntil = nil
        guardMemory = GuardMemory()
    }

    private enum CodingKeys: String, CodingKey { case bootSession, manual, holds, suppressions, pausedUntil, guardMemory }

    /// R5-3: a bad `manual` decodes as nil and the rest is kept; holds element-wise, duplicate ids keep the first.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bootSession = c.lossy(.bootSession, "")
        manual = (try? c.decodeIfPresent(AwakeSession.self, forKey: .manual)) ?? nil
        holds = c.lossyUniqueArray(.holds, [])
        suppressions = c.lossy(.suppressions, LossyMap())
        pausedUntil = c.lossy(.pausedUntil, nil)
        guardMemory = c.lossy(.guardMemory, GuardMemory())
    }

    package func sanitized() -> AwakeRuntimeSnapshot {
        var c = self
        c.holds = Array(holds.uniquedByID().prefix(AwakeHold.maxHolds))
        c.suppressions.dropUnknown(keepingAtMost: 0)
        return c
    }

    /// Load-time clamp (Kit half of code R2-M8). Stub: an empty snapshot for this boot (nothing restores).
    package func sanitized(now: ClockNow) -> AwakeRuntimeSnapshot {
        var c = AwakeRuntimeSnapshot()
        c.bootSession = now.bootSession
        return c
    }

    /// Services the restored state needs before restore runs. Stub: none.
    package var dynamicNeeds: AwakeDynamicNeeds { [] }
}
