import Foundation

/// How a sync target follows its source (PLAN §6.1 "Sync").
package enum SyncMode: String, Codable, CaseIterable, Sendable {
    /// Target = source + offset.
    case absolute
    /// Target moves by the same amount the source moved.
    case delta
}

/// What the sync controller remembers about one target.
package struct SyncTargetState: Equatable, Sendable {
    package var lastWritten: Double?
    package var lastWriteAt: Double?
    /// The user changed this target directly (pauses syncing it).
    package var lastManualAt: Double?

    package init(lastWritten: Double? = nil, lastWriteAt: Double? = nil, lastManualAt: Double? = nil) {
        self.lastWritten = lastWritten
        self.lastWriteAt = lastWriteAt
        self.lastManualAt = lastManualAt
    }
}

/// Brightness sync math: source → targets; absolute or delta; offsets; 2% deadband;
/// DDC writes ≥ 3 s apart; pause 10 s after a manual change. Times are monotonic seconds.
package enum SyncMath {
    package static let deadband = 0.02
    package static let ddcMinInterval = 3.0
    package static let manualPause = 10.0

    /// The value a target should take.
    package static func target(source: Double, previousSource: Double?, targetCurrent: Double, offset: Double,
                               mode: SyncMode, range: ClosedRange<Double> = 0...1) -> Double {
        let raw: Double
        switch mode {
        case .absolute:
            raw = source + offset
        case .delta:
            raw = targetCurrent + (source - (previousSource ?? source))
        }
        guard raw.isFinite else { return targetCurrent }
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    /// Whether to write `value` now. A false return may still need a trailing write: see `nextWriteTime`.
    package static func shouldWrite(_ value: Double, state: SyncTargetState, now: Double, isDDC: Bool) -> Bool {
        if isPaused(state, now: now) { return false }
        if let last = state.lastWritten, abs(value - last) < deadband { return false }
        if isDDC, let at = state.lastWriteAt, now - at < ddcMinInterval, now >= at { return false }
        return true
    }

    package static func isPaused(_ state: SyncTargetState, now: Double) -> Bool {
        guard let manual = state.lastManualAt else { return false }
        return now >= manual && now - manual < manualPause
    }

    /// When a rate-limited value may be written (nil when it can be written now or never).
    package static func nextWriteTime(_ value: Double, state: SyncTargetState, now: Double, isDDC: Bool) -> Double? {
        if let last = state.lastWritten, abs(value - last) < deadband { return nil }
        var t = now
        if let manual = state.lastManualAt, now >= manual, now - manual < manualPause { t = max(t, manual + manualPause) }
        if isDDC, let at = state.lastWriteAt, now >= at, now - at < ddcMinInterval { t = max(t, at + ddcMinInterval) }
        return t > now ? t : nil
    }

    /// Records a sync write.
    package static func didWrite(_ value: Double, state: inout SyncTargetState, now: Double) {
        state.lastWritten = value
        state.lastWriteAt = now
    }
}
