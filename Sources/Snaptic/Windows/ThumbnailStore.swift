import AppKit
import SnapticKit

/// Keeps window thumbnails, in memory only, under Kit `ThumbnailIndex`'s keys (PLAN 0.5 §2.3, §2.5, P2-3).
///
/// Every rule lives in the index: client tags, each client's generation, the stamp check, LRU eviction by 120 entries
/// and 96 MB, the oversize skip, 30-minute expiry, the privacy drop, the 30 s pacing rule and the bucket lookup. This
/// store holds only the images, and the one retention timer. `WindowCapture` takes the pictures; each call names its
/// client.
///
/// Privacy: captured only while the Window Switcher or a Dock preview is showing. Kept in memory for at most
/// 30 minutes, and purged on lock, sleep, fast user switching and when the last module using them stops. Nothing is
/// ever written to disk, nothing is kept from a capture its client no longer wants, a window that turns private loses
/// its thumbnails, and everything goes when Screen Recording is found revoked.
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private var index = ThumbnailIndex(limits: .v05)
    private var images: [ThumbnailKey: NSImage] = [:]
    /// One one-shot at the index's next expiry plus `retentionLeeway`; nil while the store is empty (§2.5).
    private var retentionItem: DispatchWorkItem?

    /// The retention timer fires this long after the earliest expiry, so one sweep takes several entries (X3-10).
    private static let retentionLeeway: Double = 60

    /// Cached thumbnails (§2.3 counters).
    var liveEntries: Int { index.count }
    /// Their bytes, counted as `bytesPerRow × height` (§2.3 counters).
    var liveBytes: Int { index.totalBytes }

    /// Monotonic seconds that keep counting while the Mac sleeps (§R4 A1b): an entry ages through sleep.
    static var now: Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }

    // MARK: Leases and purges

    /// Runs the purges in a batch of lease commands and follows each client's `.thumbnails` need (§2.3).
    func apply(_ commands: [WindowLeaseCommand], ledger: WindowLeaseLedger) {
        forget(index.apply(commands, ledger: ledger))
        for case .purge(let client) in commands { WindowCapture.shared.stop(client: client) }
        if commands.contains(.purgeAll) { WindowCapture.shared.purged() }
    }

    /// The §2.5 purge: every image goes, and every capture in flight is dropped when it lands.
    func purgeAll() {
        forget(index.purgeAll())
        WindowCapture.shared.purged()
    }

    /// Stops `client`'s captures in flight; its images stay. The switcher calls it whenever it closes.
    func invalidate(client: ModuleID) {
        index.invalidate(client: client)
    }

    /// Drops `client`'s images of windows that no longer exist (or that may no longer be captured) and anything too
    /// old. Another client's images are never touched; a window in `allowed` keeps its last-seen image (D2-14).
    func prune(keeping allowed: Set<CGWindowID>, client: ModuleID) {
        forget(index.prune(keeping: allowed, client: client, now: Self.now))
    }

    /// The cache refuses private windows (§4.10): every client's images of `windowIDs` go.
    func forget(windowIDs: Set<CGWindowID>) {
        forget(index.forget(windowIDs: windowIDs))
    }

    /// `windowIDs` changed since their capture: the next batch captures them even while they're fresh (§4.9).
    func markDirty(_ windowIDs: Set<CGWindowID>) {
        index.markDirty(windowIDs)
    }

    // MARK: Lookups

    /// `client`'s cached thumbnails of `ids` at `maxPixels`, or the nearest size cached (§2.3 lookup rule). Nothing
    /// for a client without `.thumbnails`.
    func cached(_ ids: [CGWindowID], maxPixels: CGFloat, client: ModuleID) -> [CGWindowID: NSImage] {
        var result: [CGWindowID: NSImage] = [:]
        for id in ids {
            if let image = cached(id, maxPixels: maxPixels, client: client) { result[id] = image }
        }
        return result
    }

    func cached(_ id: CGWindowID, maxPixels: CGFloat, client: ModuleID) -> NSImage? {
        index.lookup(windowID: id, bucket: Self.bucket(maxPixels), client: client, now: Self.now).flatMap { images[$0] }
    }

    // MARK: For `WindowCapture`

    func holdsThumbnails(_ client: ModuleID) -> Bool { index.thumbnailClients.contains(client) }

    func stamp(for client: ModuleID) -> ThumbnailStamp { index.stamp(for: client) }

    func isCurrent(_ stamp: ThumbnailStamp) -> Bool { index.isCurrent(stamp) }

    /// Whether `client` should capture `id` at `maxPixels` now: at most once per 30 s unless it's dirty (§4.9).
    func needsCapture(_ id: CGWindowID, maxPixels: CGFloat, client: ModuleID) -> Bool {
        index.needsCapture(windowID: id, bucket: Self.bucket(maxPixels), client: client, now: Self.now)
    }

    /// Keeps `image` if the index takes it, and drops the images it evicts. `.skipped` (over 16 MB) may still be
    /// shown; `.refused` may not be kept.
    func store(_ image: NSImage, for id: CGWindowID, maxPixels: CGFloat, bytes: Int, source: ThumbnailSource,
               stamp: ThumbnailStamp) -> ThumbnailIndex.InsertResult {
        let key = ThumbnailKey(windowID: id, bucket: Self.bucket(maxPixels))
        let result = index.insert(key, stamp: stamp, now: Self.now, bytes: bytes, source: source)
        if case .stored(let evicted) = result {
            images[key] = image
            forget(evicted)
        }
        return result
    }

    // MARK: Images and retention

    private func forget(_ keys: [ThumbnailKey]) {
        for key in keys { images[key] = nil }
        syncRetention()
    }

    private static func bucket(_ maxPixels: CGFloat) -> Int { Int(maxPixels.rounded()) }

    /// One one-shot for the earliest expiry while anything is stored; none while the store is empty (§2.5).
    private func syncRetention() {
        guard let expiry = index.nextExpiry else {
            retentionItem?.cancel()
            retentionItem = nil
            return
        }
        guard retentionItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.retentionFired() }
        }
        retentionItem = item
        let delay = max(0, expiry + Self.retentionLeeway - Self.now)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// The sweep, then the timer is armed again for the next expiry.
    private func retentionFired() {
        retentionItem = nil
        forget(index.expire(now: Self.now))
    }
}
