import Foundation

// The `WindowServices` lease ledger (lead; PLAN 0.5 §2.3, §2.5, D2-5): which client holds which needs, the union of
// them, and the commands each edge sends. The app runs the commands; the ledger never reads a clock, so callers pass
// `now` (seconds, any monotonic origin) and call `tick` at `nextDeadline`.

/// One thing a client needs from `WindowServices` (§2.3).
package enum WindowNeed: Hashable, Sendable {
    /// `FocusTracker` on every regular app, focus changes only.
    case recency
    /// The five extra notifications for one app (X-9).
    case freshness(Int32)
    /// The client's Window thumbnails setting is on: it may capture, and its entries are kept.
    case thumbnails
    /// The client lists other-Space windows.
    case otherSpaces
}

package typealias WindowNeeds = Set<WindowNeed>

/// Where an app's freshness notifications are registered (D2-5).
package enum FreshnessHost: Equatable, Sendable {
    /// Added to `FocusTracker`'s observer for that app, while `.recency` is live.
    case focusTracker
    /// Its own `AXObserver` on its own `ObserverThread`.
    case own
}

/// What an edge asks `WindowServices` to do, in order.
package enum WindowLeaseCommand: Equatable, Sendable {
    /// The first lease: the 0.15 s AX messaging timeout and the §2.5 purge observers.
    case startServices
    /// The last release: cancel in-flight captures and remove every observer.
    case stopServices
    case startRecency
    case stopRecency
    case startFreshness(pid: Int32, host: FreshnessHost)
    case stopFreshness(pid: Int32, host: FreshnessHost)
    /// Bump the client's generation, then drop its entries.
    case purge(ModuleID)
    /// The §2.5 purge: the last release, or no live lease with `.thumbnails`.
    case purgeAll
}

package struct WindowLeaseLedger: Equatable, Sendable {
    /// Freshness notifications stay this long after the last need for them drops (§2.3), so a panel that hides and
    /// shows again doesn't re-register them.
    package static let freshnessLinger: Double = 2

    package private(set) var leases: [ModuleID: WindowNeeds] = [:]
    /// The apps whose freshness notifications are registered, and where.
    package private(set) var freshness: [Int32: FreshnessHost] = [:]
    /// Registered freshness notifications no lease needs any more, and when they stop.
    package private(set) var stopsAt: [Int32: Double] = [:]

    package init() {}

    /// The needs of every live lease.
    package var union: WindowNeeds { leases.values.reduce(into: WindowNeeds()) { $0.formUnion($1) } }
    package var isLive: Bool { !leases.isEmpty }
    package var recencyLive: Bool { union.contains(.recency) }
    package func holds(_ client: ModuleID) -> Bool { leases[client] != nil }
    package func needs(of client: ModuleID) -> WindowNeeds { leases[client] ?? [] }

    /// Freshness observers on their own threads (`WindowServices.freshnessObservers`).
    package var ownFreshnessObservers: Int { freshness.values.filter { $0 == .own }.count }
    package var freshnessPIDs: [Int32] { freshness.keys.sorted() }
    /// When `tick` next has work, or nil.
    package var nextDeadline: Double? { stopsAt.values.min() }

    /// M32's AX observer count: `FocusTracker`'s one per regular app while `.recency` is live, one per freshness app
    /// not hosted by it, and the Dock's own observer while Dock Previews holds a lease. Dock Previews alone holds no
    /// `.recency`, so it's the Dock plus the previewed app (D2-5).
    package func axObservers(regularApps: Int) -> Int {
        (recencyLive ? regularApps : 0) + ownFreshnessObservers + (holds(.dockPreviews) ? 1 : 0)
    }

    /// Takes a lease; a client that holds one already has it updated.
    package mutating func acquire(_ client: ModuleID, needs: WindowNeeds, now: Double) -> [WindowLeaseCommand] {
        update(client, needs: needs, now: now)
    }

    package mutating func update(_ client: ModuleID, needs: WindowNeeds, now: Double) -> [WindowLeaseCommand] {
        let before = union, wasLive = isLive
        let dropsThumbnails = leases[client]?.contains(.thumbnails) == true && !needs.contains(.thumbnails)
        leases[client] = needs
        var commands: [WindowLeaseCommand] = wasLive ? [] : [.startServices]
        if dropsThumbnails { commands.append(.purge(client)) }
        commands += reconcile(from: before, now: now)
        return commands
    }

    /// Drops the lease. The last release stops everything at once, with no linger.
    package mutating func release(_ client: ModuleID, now: Double) -> [WindowLeaseCommand] {
        guard leases[client] != nil else { return [] }
        let before = union
        leases[client] = nil
        return [.purge(client)] + reconcile(from: before, now: now)
    }

    /// Stops the freshness notifications whose linger is over, by pid.
    package mutating func tick(now: Double) -> [WindowLeaseCommand] {
        var commands: [WindowLeaseCommand] = []
        for pid in stopsAt.keys.sorted() where stopsAt[pid].map({ $0 <= now }) == true {
            stopsAt[pid] = nil
            if let host = freshness.removeValue(forKey: pid) { commands.append(.stopFreshness(pid: pid, host: host)) }
        }
        return commands
    }

    private mutating func reconcile(from before: WindowNeeds, now: Double) -> [WindowLeaseCommand] {
        let after = union
        var commands: [WindowLeaseCommand] = []
        if !isLive {
            // The last release: every observer goes now.
            for pid in freshnessPIDs {
                if let host = freshness[pid] { commands.append(.stopFreshness(pid: pid, host: host)) }
            }
            freshness = [:]
            stopsAt = [:]
            if before.contains(.recency) { commands.append(.stopRecency) }
            commands += [.purgeAll, .stopServices]
            return commands
        }

        if before.contains(.thumbnails), !after.contains(.thumbnails) { commands.append(.purgeAll) }

        let recencyNow = after.contains(.recency)
        if !before.contains(.recency), recencyNow {
            commands.append(.startRecency)
            for pid in freshnessPIDs where freshness[pid] == .own {
                commands += [.stopFreshness(pid: pid, host: .own), .startFreshness(pid: pid, host: .focusTracker)]
                freshness[pid] = .focusTracker
            }
        } else if before.contains(.recency), !recencyNow {
            let moved = freshnessPIDs.filter { freshness[$0] == .focusTracker }
            commands += moved.map { .stopFreshness(pid: $0, host: .focusTracker) }
            commands.append(.stopRecency)
            for pid in moved {
                commands.append(.startFreshness(pid: pid, host: .own))
                freshness[pid] = .own
            }
        }

        var wanted = Set<Int32>()
        for need in after { if case .freshness(let pid) = need { wanted.insert(pid) } }
        for pid in wanted.sorted() {
            if freshness[pid] != nil {
                stopsAt[pid] = nil
            } else {
                let host: FreshnessHost = recencyNow ? .focusTracker : .own
                freshness[pid] = host
                commands.append(.startFreshness(pid: pid, host: host))
            }
        }
        for pid in freshnessPIDs where !wanted.contains(pid) && stopsAt[pid] == nil {
            stopsAt[pid] = now + Self.freshnessLinger
        }
        return commands
    }
}
