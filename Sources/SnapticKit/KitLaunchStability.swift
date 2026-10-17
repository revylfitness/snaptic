import Foundation

/// One launch, as remembered by the next one (PLAN §4.8).
package struct LaunchRecord: Codable, Equatable, Sendable {
    /// Wall-clock seconds since 1970; informational only (never compared across sleeps).
    package var startedAt: Double
    /// The launch stayed up for `KitLaunchStability.survivalSeconds`.
    package var survived: Bool
    /// The launch ended through the normal quit path.
    package var cleanQuit: Bool

    package init(startedAt: Double, survived: Bool = false, cleanQuit: Bool = false) {
        self.startedAt = startedAt
        self.survived = survived
        self.cleanQuit = cleanQuit
    }

    private enum CodingKeys: String, CodingKey { case startedAt, survived, cleanQuit }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let started = c.lossy(.startedAt, 0.0)
        startedAt = started.isFinite ? started : 0
        // A field we can't read counts as "the launch was fine", so a damaged history
        // never forces Safe Mode by itself.
        survived = c.lossy(.survived, true)
        cleanQuit = c.lossy(.cleanQuit, true)
    }

    /// Ended early without a clean quit: a crash, a force quit or a kill.
    package var isUnstable: Bool { !survived && !cleanQuit }
}

package struct LaunchHistory: Codable, Equatable, Sendable {
    /// Oldest first.
    package var records: [LaunchRecord]

    package static let maxRecords = 8

    package init(records: [LaunchRecord] = []) { self.records = records }

    private enum CodingKeys: String, CodingKey { case records }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = Array(c.lossy(.records, [LaunchRecord]()).suffix(Self.maxRecords))
    }
}

/// Launch-stability bookkeeping: two consecutive launches that ended in under 60 s
/// without a clean quit start the next launch in Safe Mode (PLAN §4.8).
package enum KitLaunchStability {
    package static let survivalSeconds: Double = 60
    /// How many unstable launches in a row trigger Safe Mode.
    package static let unstableRunLength = 2

    /// Evaluates the previous launches, then records this one as running.
    package static func beginLaunch(_ history: LaunchHistory, now: Double) -> (unstable: Bool, history: LaunchHistory) {
        let previous = history.records.suffix(unstableRunLength)
        let unstable = previous.count == unstableRunLength && previous.allSatisfy(\.isUnstable)
        var next = history
        next.records.append(LaunchRecord(startedAt: now.isFinite ? now : 0))
        if next.records.count > LaunchHistory.maxRecords {
            next.records.removeFirst(next.records.count - LaunchHistory.maxRecords)
        }
        return (unstable, next)
    }

    /// The current launch has run long enough to count as stable.
    package static func markSurvived(_ history: LaunchHistory) -> LaunchHistory {
        var next = history
        if !next.records.isEmpty { next.records[next.records.count - 1].survived = true }
        return next
    }

    /// The current launch is quitting normally.
    package static func markCleanQuit(_ history: LaunchHistory) -> LaunchHistory {
        var next = history
        if !next.records.isEmpty { next.records[next.records.count - 1].cleanQuit = true }
        return next
    }

    /// Decodes a stored history; anything unreadable becomes an empty history.
    package static func decode(_ data: Data?) -> LaunchHistory {
        guard let data, data.count <= 16 * 1024,
              let history = try? JSONDecoder().decode(LaunchHistory.self, from: data) else { return LaunchHistory() }
        return history
    }

    package static func encode(_ history: LaunchHistory) -> Data? {
        try? JSONEncoder().encode(history)
    }
}
