import Foundation

// The thumbnail store's bookkeeping, without images (lead; PLAN 0.5 §2.3, §2.5, P2-3): keys (windowID, pixel bucket),
// client tags, a generation per client, the epoch, the stamp check, invalidate, prune, purge, purgeAll, LRU eviction,
// expiry and the bucket lookup. The app's `ThumbnailStore` keeps the images under these keys and drops the ones each
// call returns. The index never reads a clock: callers pass `now` (seconds, any monotonic origin).
// A2a adds the byte budget, the oversize skip, 30-minute retention and `nextExpiry`.

/// One cached thumbnail: a window at one pixel bucket (§2.3). Buckets: 720 for the Dock; 640 and 2400 for the
/// switcher (§4.9).
package struct ThumbnailKey: Hashable, Sendable {
    package var windowID: UInt32
    package var bucket: Int

    package init(windowID: UInt32, bucket: Int) {
        self.windowID = windowID
        self.bucket = bucket
    }
}

/// Taken when a capture starts and checked when it lands (§2.5): a capture whose client was invalidated or purged,
/// or that started before a `purgeAll()`, is dropped.
package struct ThumbnailStamp: Equatable, Sendable {
    package let client: ModuleID
    package let generation: Int
    package let epoch: Int
}

/// How much the index keeps.
package struct ThumbnailLimits: Equatable, Sendable {
    package var maxEntries: Int
    /// An entry is gone this many seconds after its capture.
    package var maxAge: Double

    package init(maxEntries: Int, maxAge: Double) {
        self.maxEntries = maxEntries
        self.maxAge = maxAge
    }

    /// 0.4's limits: 40 entries for 5 minutes. A1a and A1b keep them; A2a switches (D2-22).
    package static let v04 = ThumbnailLimits(maxEntries: 40, maxAge: 5 * 60)
}

package struct ThumbnailIndex: Equatable, Sendable {
    package struct Entry: Equatable, Sendable {
        /// The client whose capture this is. A later capture of the same key by another client takes it over.
        package var client: ModuleID
        package var capturedAt: Double
    }

    package enum InsertResult: Equatable, Sendable {
        /// Stored; the store drops the images of `evicted`.
        case stored(evicted: [ThumbnailKey])
        /// The stamp is stale, or its client holds no `.thumbnails`: the image is dropped, not stored.
        case refused
    }

    package let limits: ThumbnailLimits
    package private(set) var entries: [ThumbnailKey: Entry] = [:]
    /// Least recently stored first. Lookups don't reorder it, as in 0.4.
    package private(set) var order: [ThumbnailKey] = []
    package private(set) var epoch = 0
    /// The clients whose lease holds `.thumbnails`. Only they store, and only they get thumbnails (X2-11).
    package private(set) var thumbnailClients: Set<ModuleID> = []
    private var generations: [ModuleID: Int] = [:]

    package init(limits: ThumbnailLimits = .v04) {
        self.limits = limits
    }

    package var count: Int { entries.count }

    package func generation(of client: ModuleID) -> Int { generations[client] ?? 0 }

    /// The stamp for a capture `client` starts now.
    package func stamp(for client: ModuleID) -> ThumbnailStamp {
        ThumbnailStamp(client: client, generation: generation(of: client), epoch: epoch)
    }

    /// Whether a capture with `stamp` may still be used: neither its client's generation nor the epoch has moved.
    package func isCurrent(_ stamp: ThumbnailStamp) -> Bool {
        stamp.generation == generation(of: stamp.client) && stamp.epoch == epoch
    }

    // MARK: Clients

    /// Follows a client's `.thumbnails` need. Turning it off purges that client at once (X2-11).
    @discardableResult
    package mutating func setThumbnails(_ on: Bool, client: ModuleID) -> [ThumbnailKey] {
        if on {
            thumbnailClients.insert(client)
            return []
        }
        guard thumbnailClients.remove(client) != nil else { return [] }
        return purge(client: client)
    }

    /// Runs the purges in a batch of lease commands, then follows every client's `.thumbnails` need in `ledger`
    /// (the ledger after the edge). Returns the keys whose images the store drops.
    package mutating func apply(_ commands: [WindowLeaseCommand], ledger: WindowLeaseLedger) -> [ThumbnailKey] {
        var dropped: [ThumbnailKey] = []
        for command in commands {
            switch command {
            case .purge(let client): dropped += purge(client: client)
            case .purgeAll: dropped += purgeAll()
            default: break
            }
        }
        for client in ModuleID.allCases {
            dropped += setThumbnails(ledger.needs(of: client).contains(.thumbnails), client: client)
        }
        return dropped
    }

    // MARK: Store and look up

    /// Stores a capture taken under `stamp`. Evicts the least recently stored entries over `maxEntries`, whoever
    /// owns them.
    package mutating func insert(_ key: ThumbnailKey, stamp: ThumbnailStamp, now: Double) -> InsertResult {
        guard isCurrent(stamp), thumbnailClients.contains(stamp.client) else { return .refused }
        entries[key] = Entry(client: stamp.client, capturedAt: now)
        order.removeAll { $0 == key }
        order.append(key)
        var evicted: [ThumbnailKey] = []
        while order.count > limits.maxEntries {
            let oldest = order.removeFirst()
            entries[oldest] = nil
            evicted.append(oldest)
        }
        return .stored(evicted: evicted)
    }

    /// The key to show for `windowID` at `bucket`: the smallest cached bucket at least as large, else the largest
    /// smaller one. Nil for a client without `.thumbnails`, whoever owns the entry (X2-11), and for expired entries.
    package func lookup(windowID: UInt32, bucket: Int, client: ModuleID, now: Double) -> ThumbnailKey? {
        guard thumbnailClients.contains(client) else { return nil }
        var larger: Int?
        var smaller: Int?
        for (key, entry) in entries where key.windowID == windowID {
            guard thumbnailClients.contains(entry.client), !isExpired(entry, now: now) else { continue }
            if key.bucket >= bucket {
                if larger.map({ key.bucket < $0 }) ?? true { larger = key.bucket }
            } else if smaller.map({ key.bucket > $0 }) ?? true {
                smaller = key.bucket
            }
        }
        guard let found = larger ?? smaller else { return nil }
        return ThumbnailKey(windowID: windowID, bucket: found)
    }

    // MARK: Invalidate, prune, purge

    /// Drops `client`'s captures in flight; its entries stay.
    package mutating func invalidate(client: ModuleID) {
        generations[client, default: 0] += 1
    }

    /// Drops `client`'s entries for windows not in `keeping` and its expired ones. Another client's entries are never
    /// touched, and an entry of a window in `keeping` stays as its last-seen thumbnail (D2-14).
    package mutating func prune(keeping windowIDs: Set<UInt32>, client: ModuleID, now: Double) -> [ThumbnailKey] {
        let maxAge = limits.maxAge
        return drop { key, entry in
            entry.client == client && (!windowIDs.contains(key.windowID) || now - entry.capturedAt >= maxAge)
        }
    }

    /// Bumps `client`'s generation first, so a capture that lands late is refused, then drops its entries. Waits for
    /// nothing (X2-12).
    package mutating func purge(client: ModuleID) -> [ThumbnailKey] {
        invalidate(client: client)
        return drop { _, entry in entry.client == client }
    }

    /// The §2.5 purge: bumps the epoch, so every capture in flight is refused, then drops every entry.
    package mutating func purgeAll() -> [ThumbnailKey] {
        epoch += 1
        let dropped = order
        entries = [:]
        order = []
        return dropped
    }

    private func isExpired(_ entry: Entry, now: Double) -> Bool {
        now - entry.capturedAt >= limits.maxAge
    }

    private mutating func drop(where shouldDrop: (ThumbnailKey, Entry) -> Bool) -> [ThumbnailKey] {
        var dropped: [ThumbnailKey] = []
        for key in order {
            guard let entry = entries[key], shouldDrop(key, entry) else { continue }
            entries[key] = nil
            dropped.append(key)
        }
        if !dropped.isEmpty { order.removeAll { entries[$0] == nil } }
        return dropped
    }
}
