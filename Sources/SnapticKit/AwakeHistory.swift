import Foundation

// Awake history (owner: G; PLAN 0.3 §2.14, §3.6, R5-3, R5-14). Key SnapticAwakeHistoryV1. A local timeline only: it
// never reaches logs, diagnostics, the CLI or exports.

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

    /// False for .commandLine/.rule sources and process/automatic kinds.
    package var offersStartAgain: Bool {
        switch source {
        case .commandLine, .rule: return false
        case .menu, .hotkey, .settings, .launch: break
        }
        switch kind {
        case .process, .automatic: return false
        case .app: return bundleID != nil
        case .indefinite, .duration, .until, .idle: return true
        }
    }

    package var seconds: Double { max(0, end - start) }

    /// nil when the times aren't finite or end before the start; an invalid bundle id is dropped.
    package func sanitized() -> AwakeHistoryEntry? {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        var e = self
        if let b = bundleID, !AwakeBundleID.isValid(b) { e.bundleID = nil }
        return e
    }
}

package struct AwakeHistory: ConfigModel {
    package static let key = "SnapticAwakeHistoryV1"
    package static let maxEntries = 500
    package static let keepDays = 90
    /// A `.replaced` entry shorter than this merges into the session that replaced it.
    package static let mergeSeconds: Double = 60

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
        c.entries = Array(entries.compactMap { $0.sanitized() }.suffix(Self.maxEntries))
        return c
    }

    /// Appends `e` (sanitized) and keeps the newest `cap` (1...500). Short `.replaced` runs merge: while the last
    /// entry was replaced after < 60 s and `e` starts where it ended (≤ 1 s gap), that entry is folded into `e`
    /// (same awake time, one row).
    package func appending(_ e: AwakeHistoryEntry, cap: Int) -> AwakeHistory {
        guard var entry = e.sanitized() else { return self }
        var c = self
        while let last = c.entries.last, last.endReason == .replaced, last.seconds < Self.mergeSeconds,
              abs(entry.start - last.end) <= 1, last.start <= entry.start {
            entry.start = last.start
            c.entries.removeLast()
        }
        c.entries.append(entry)
        let limit = AwakeMath.clamp(cap, 1...Self.maxEntries)
        if c.entries.count > limit { c.entries.removeFirst(c.entries.count - limit) }
        return c
    }

    /// Drops entries that ended more than `keepDays` (≥ 1) days before `now`.
    package func pruned(now: Double, keepDays: Int) -> AwakeHistory {
        guard now.isFinite else { return self }
        let cutoff = now - Double(max(1, keepDays)) * 86_400
        var c = self
        c.entries = entries.filter { $0.end >= cutoff }
        return c
    }

    /// Awake time since `todayStart` and since `weekStart` (unix times from the app's Calendar, N12), counting
    /// overlapping entries once (a hold beside a session is the same awake time).
    package func totals(todayStart: Double, weekStart: Double, now: Double) -> (today: Double, week: Double) {
        (Self.covered(entries, from: todayStart, to: now), Self.covered(entries, from: weekStart, to: now))
    }

    /// Length of the union of entry intervals clipped to [from, to].
    private static func covered(_ entries: [AwakeHistoryEntry], from: Double, to: Double) -> Double {
        guard from.isFinite, to.isFinite, to > from else { return 0 }
        let spans = entries.compactMap { e -> (Double, Double)? in
            guard e.start.isFinite, e.end.isFinite else { return nil }
            let s = max(e.start, from), en = min(e.end, to)
            return en > s ? (s, en) : nil
        }.sorted { $0.0 < $1.0 }
        var total = 0.0
        var current: (Double, Double)?
        for span in spans {
            if let cur = current, span.0 <= cur.1 {
                current = (cur.0, max(cur.1, span.1))
            } else {
                if let cur = current { total += cur.1 - cur.0 }
                current = span
            }
        }
        if let cur = current { total += cur.1 - cur.0 }
        return total
    }
}
