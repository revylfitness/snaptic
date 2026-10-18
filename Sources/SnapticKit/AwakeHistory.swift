import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.14 + R5-3 (kind S). Key SnapticAwakeHistoryV1.

package enum AwakeHistoryKind: String, Codable, Sendable { case indefinite, duration, until, app, idle, process, automatic }

package struct AwakeHistoryEntry: Codable, Equatable, Sendable {
    package var start: Double
    package var end: Double
    package var kind: AwakeHistoryKind
    /// Start Again is hidden for .commandLine and .rule (R5-14).
    package var source: AwakeSessionSource
    package var presetID: StableID?
    package var triggerID: StableID?
    /// App sessions, for Start Again; local only.
    package var bundleID: String?
    package var endReason: AwakeEndReason

    package init(start: Double, end: Double, kind: AwakeHistoryKind, source: AwakeSessionSource, presetID: StableID?,
                 triggerID: StableID?, bundleID: String?, endReason: AwakeEndReason) {
        self.start = start
        self.end = end
        self.kind = kind
        self.source = source
        self.presetID = presetID
        self.triggerID = triggerID
        self.bundleID = bundleID
        self.endReason = endReason
    }

    private enum CodingKeys: String, CodingKey { case start, end, kind, source, presetID, triggerID, bundleID, endReason }

    /// Hand-written (N18): an unknown kind, source or endReason throws (the entry is dropped); the rest lossy.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(AwakeHistoryKind.self, forKey: .kind)
        source = try c.decode(AwakeSessionSource.self, forKey: .source)
        endReason = try c.decode(AwakeEndReason.self, forKey: .endReason)
        start = c.lossy(.start, 0)
        end = c.lossy(.end, 0)
        presetID = c.lossy(.presetID, nil)
        triggerID = c.lossy(.triggerID, nil)
        bundleID = c.lossy(.bundleID, nil)
    }

    /// False for .commandLine/.rule sources and process/automatic kinds. Stub: false.
    package var offersStartAgain: Bool { false }
}

package struct AwakeHistory: ConfigModel {
    /// ≤ 500, lossyArray (N18).
    package var entries: [AwakeHistoryEntry]

    package init() { entries = [] }

    private enum CodingKeys: String, CodingKey { case entries }

    /// R5-3: element-wise.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = c.lossyArray(.entries, [])
    }

    package func sanitized() -> AwakeHistory {
        var c = self
        c.entries = Array(entries.suffix(500))
        return c
    }

    /// cap 500; merges < 60 s `.replaced` runs. Stub: unchanged.
    package func appending(_ e: AwakeHistoryEntry, cap: Int) -> AwakeHistory { self }
    /// 90 days. Stub: unchanged.
    package func pruned(now: Double, keepDays: Int) -> AwakeHistory { self }
    /// Day boundaries come from the app as unix times. Stub: zero.
    package func totals(todayStart: Double, weekStart: Double, now: Double) -> (today: Double, week: Double) { (0, 0) }
}
