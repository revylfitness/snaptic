import AppKit
import ScreenCaptureKit
import SnapticKit

/// A window Snaptic wants to capture, and the process that should own it.
struct CaptureTarget: Equatable {
    let id: CGWindowID
    let pid: pid_t
}

/// Captures window thumbnails with ScreenCaptureKit and keeps the images.
///
/// Every rule lives in Kit `ThumbnailIndex` (PLAN 0.5 §2.3, P2-3): client tags, each client's generation, the stamp
/// check, LRU eviction, expiry and the bucket lookup. This store holds only the images under the index's keys, and
/// each call names its client.
///
/// Privacy: images live only in memory, the cache is small, least-recently used and expires after a few minutes,
/// entries for closed windows are dropped, nothing is kept from a capture its client no longer wants, and everything
/// is purged when the screen sleeps or locks. The caller decides which windows may be captured; this store
/// double-checks ownership with ScreenCaptureKit itself.
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private var index = ThumbnailIndex(limits: .v04)
    private var images: [ThumbnailKey: NSImage] = [:]
    /// ScreenCaptureKit's windows from the last capture batch: capture state, not bookkeeping. A2a's `WindowCapture`
    /// takes it over.
    private var shareable: [CGWindowID: SCWindow] = [:]

    /// Cached thumbnails (§2.3 counters).
    var liveEntries: Int { index.count }

    /// Monotonic seconds that keep counting while the Mac sleeps, so an entry ages as it did under 0.4's `Date`.
    private static var now: Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }

    // MARK: Leases

    /// Runs the purges in a batch of lease commands and follows each client's `.thumbnails` need (§2.3).
    func apply(_ commands: [WindowLeaseCommand], ledger: WindowLeaseLedger) {
        let dropped = index.apply(commands, ledger: ledger)
        forget(dropped)
        if commands.contains(.purgeAll) { shareable = [:] }
    }

    /// The §2.5 purge: every image goes, and every capture in flight is dropped when it lands.
    func purgeAll() {
        forget(index.purgeAll())
        shareable = [:]
    }

    // MARK: Client calls

    /// `client`'s cached thumbnails of `ids` at `maxPixels`, or the nearest size cached (§2.3 lookup rule). Nothing
    /// for a client without `.thumbnails`.
    func cached(_ ids: [CGWindowID], maxPixels: CGFloat, client: ModuleID) -> [CGWindowID: NSImage] {
        let now = Self.now
        var result: [CGWindowID: NSImage] = [:]
        for id in ids {
            if let key = index.lookup(windowID: id, bucket: Self.bucket(maxPixels), client: client, now: now),
               let image = images[key] {
                result[id] = image
            }
        }
        return result
    }

    /// Stops `client`'s captures in flight; its images stay. The switcher calls it whenever it closes.
    func invalidate(client: ModuleID) {
        index.invalidate(client: client)
        shareable = [:]
    }

    /// Drops `client`'s images of windows that no longer exist (or that may no longer be captured) and anything too
    /// old. Another client's images are never touched.
    func prune(keeping allowed: Set<CGWindowID>, client: ModuleID) {
        forget(index.prune(keeping: allowed, client: client, now: Self.now))
    }

    /// Captures `targets` one at a time, `priority` first, for `client`. Its previous batch stops.
    func refresh(
        _ targets: [CaptureTarget],
        blockedBundleIDs: [String],
        maxPixels: CGFloat,
        priority: CGWindowID?,
        client: ModuleID,
        onImage: @escaping @MainActor (CGWindowID, NSImage) -> Void
    ) {
        guard !targets.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        index.invalidate(client: client)
        let stamp = index.stamp(for: client)
        let bucket = Self.bucket(maxPixels)
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        var reordered = targets
        if let priority, let position = reordered.firstIndex(where: { $0.id == priority }) {
            let first = reordered.remove(at: position)
            reordered.insert(first, at: 0)
        }
        let ordered = reordered

        Task { @MainActor in
            guard let windows = await Self.shareableWindows(), self.index.isCurrent(stamp) else { return }
            self.shareable = windows
            for target in ordered {
                guard self.index.isCurrent(stamp) else { return }
                guard let window = windows[target.id],
                      Self.isOwned(window, by: target.pid, blockedBundleIDs: blockedBundleIDs),
                      let image = await Self.capture(window, maxPixels: maxPixels, scale: scale) else { continue }
                // The client may have closed, been purged or lost `.thumbnails` while we waited: don't keep the image.
                guard self.store(ThumbnailKey(windowID: target.id, bucket: bucket), image, stamp: stamp) else { return }
                onImage(target.id, image)
            }
        }
    }

    /// A one-off high-resolution capture for `client`'s full-size preview. Not cached, and dropped if `client` is
    /// invalidated or purged first.
    func captureForPreview(_ target: CaptureTarget, blockedBundleIDs: [String], maxPixels: CGFloat,
                           client: ModuleID) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let stamp = index.stamp(for: client)
        var found = shareable[target.id]
        if found == nil {
            guard let windows = await Self.shareableWindows(), index.isCurrent(stamp) else { return nil }
            shareable = windows
            found = windows[target.id]
        }
        guard let window = found, Self.isOwned(window, by: target.pid, blockedBundleIDs: blockedBundleIDs) else {
            return nil
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = await Self.capture(window, maxPixels: maxPixels, scale: scale)
        return index.isCurrent(stamp) ? image : nil
    }

    // MARK: Images

    /// Keeps `image` if the index takes it, and drops the images it evicts.
    private func store(_ key: ThumbnailKey, _ image: NSImage, stamp: ThumbnailStamp) -> Bool {
        guard case .stored(let evicted) = index.insert(key, stamp: stamp, now: Self.now) else { return false }
        images[key] = image
        forget(evicted)
        return true
    }

    private func forget(_ keys: [ThumbnailKey]) {
        for key in keys { images[key] = nil }
    }

    private static func bucket(_ maxPixels: CGFloat) -> Int { Int(maxPixels.rounded()) }

    // MARK: ScreenCaptureKit

    /// ScreenCaptureKit's own view of who owns the window must match what we
    /// expect, and the owner must not be a protected app.
    private static func isOwned(_ window: SCWindow, by pid: pid_t, blockedBundleIDs: [String]) -> Bool {
        guard let owner = window.owningApplication, owner.processID == pid else { return false }
        return !Config.bundleID(owner.bundleIdentifier, matchesAny: blockedBundleIDs)
    }

    private static func shareableWindows() async -> [CGWindowID: SCWindow]? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        var byID: [CGWindowID: SCWindow] = [:]
        for window in content.windows { byID[window.windowID] = window }
        return byID
    }

    private static func capture(_ window: SCWindow, maxPixels: CGFloat, scale: CGFloat) async -> NSImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }
        let pixelRatio = min(scale, maxPixels / max(frame.width, frame.height))

        let config = SCStreamConfiguration()
        config.width = max(1, Int(frame.width * pixelRatio))
        config.height = max(1, Int(frame.height * pixelRatio))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height))
    }
}
