import AppKit
import ScreenCaptureKit
import SnapticKit

/// A window a client wants captured: the catalog's view of it, so the shared capture rule can be checked again with
/// the window server's own owner (§4.9).
struct CaptureTarget: Equatable {
    let window: CatalogWindow

    var id: CGWindowID { window.id }
    var pid: pid_t { window.pid }
}

/// Takes window thumbnails for both clients (PLAN 0.5 §4.9, X-4, X-20, Y-7): the per-capture rule, the pacing and the
/// ScreenCaptureKit path. `ThumbnailStore` keeps what it takes.
///
/// - Consent: `CGPreflightScreenCaptureAccess()` once per batch. It is never requested from here, and finding it
///   revoked purges the store (§2.5).
/// - The rule: Kit `WindowCatalogRules.captureRefusal` with the window server's owner pid and bundle id, checked on
///   each capture: private windows, protected apps, a wrong owner (S0-18), and for the Dock its hidden apps.
/// - Pacing: captures start only after the panel has been visible for 150 ms; each window at most once per 30 s
///   unless it's dirty; at most 8 captures a second in total and 4 at once; `SCShareableContent` is shared for 2 s.
/// - The private path for minimized and other-Space windows is A2b's.
@MainActor
final class WindowCapture {
    static let shared = WindowCapture()

    /// A panel shows this long before its captures start (§4.9).
    static let visibleDelay: Double = 0.15
    /// ScreenCaptureKit captures at once.
    static let maxRunning = 4
    /// Captures started in any one second, both clients together.
    static let maxPerSecond = 8
    /// `SCShareableContent` is reused this long by both clients.
    static let shareableLifetime: Double = 2

    private var shareable: [CGWindowID: SCWindow] = [:]
    private var shareableAt: Double?
    private var running = 0
    private var recentStarts: [Double] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var batches: [ModuleID: Task<Void, Never>] = [:]

    private init() {}

    private static var now: Double { ThumbnailStore.now }

    // MARK: Consent (§2.5, §4.9)

    /// `CGPreflightScreenCaptureAccess()`, never the request. False purges the store, so a client shows text
    /// (its cards fall back to the icon) and no prompt appears (M39).
    func screenRecordingAllowed() -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            WindowServices.shared.screenRecordingRevoked()
            return false
        }
        return true
    }

    // MARK: Batches

    /// Captures `targets` for `client` at `maxPixels`, `priority` first, once its panel has been visible for 150 ms
    /// (`visibleSince`, in `ThumbnailStore.now` seconds). Windows captured in the last 30 s are skipped unless dirty.
    /// `client`'s previous batch stops. `onImage` gets each image, including one too big to cache.
    func refresh(_ targets: [CaptureTarget], client: ModuleID, maxPixels: CGFloat, priority: CGWindowID?,
                 visibleSince: Double, protectedBundleIDs: [String], hiddenBundleIDs: [String] = [],
                 onImage: @escaping @MainActor (CGWindowID, NSImage) -> Void) {
        cancelBatch(client)
        ThumbnailStore.shared.invalidate(client: client)
        guard !targets.isEmpty else { return }
        let store = ThumbnailStore.shared
        let stamp = store.stamp(for: client)
        var ordered = targets
        if let priority, let position = ordered.firstIndex(where: { $0.id == priority }) {
            ordered.insert(ordered.remove(at: position), at: 0)
        }
        let batch = ordered
        let rules = Rules(client: client, protectedBundleIDs: protectedBundleIDs, hiddenBundleIDs: hiddenBundleIDs)

        batches[client] = Task { @MainActor [weak self] in
            await Self.waitUntilVisible(since: visibleSince)
            guard let self, !Task.isCancelled, store.isCurrent(stamp), self.screenRecordingAllowed(),
                  let windows = await self.shareableWindows(), !Task.isCancelled, store.isCurrent(stamp) else { return }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            for target in batch {
                guard store.needsCapture(target.id, maxPixels: maxPixels, client: client),
                      let window = windows[target.id],
                      self.permits(target, window, rules: rules, thumbnailsLease: store.holdsThumbnails(client))
                else { continue }
                guard await self.takeSlot() else { return }
                guard !Task.isCancelled, store.isCurrent(stamp) else {
                    self.releaseSlot()
                    return
                }
                // Each capture runs on its own; a stale one finishes and is dropped by the stamp check (X2-12).
                Task { @MainActor [weak self] in
                    defer { self?.releaseSlot() }
                    guard let shot = await Self.capture(window, maxPixels: maxPixels, scale: scale) else { return }
                    switch store.store(shot.image, for: target.id, maxPixels: maxPixels, bytes: shot.bytes,
                                       source: .sck, stamp: stamp) {
                    case .stored, .skipped: onImage(target.id, shot.image)
                    case .refused: break
                    }
                }
            }
        }
    }

    /// Stops `client`'s batch and its captures in flight (their results are dropped when they land).
    func stop(client: ModuleID) {
        cancelBatch(client)
        ThumbnailStore.shared.invalidate(client: client)
        if batches.isEmpty { dropShareable() }
    }

    private func cancelBatch(_ client: ModuleID) {
        batches[client]?.cancel()
        batches[client] = nil
    }

    /// A one-off capture for `client`'s full-size preview, at the switcher's 2400-pixel bucket. Kept like any capture
    /// while `client` holds `.thumbnails` and it's 16 MB or less; shown either way. It doesn't need `.thumbnails`
    /// (§R4 A1b), and a fresh, clean cached one is returned without a capture. Nil once `client` is invalidated or
    /// purged.
    func captureForPreview(_ target: CaptureTarget, client: ModuleID, maxPixels: CGFloat, visibleSince: Double,
                           protectedBundleIDs: [String]) async -> NSImage? {
        let store = ThumbnailStore.shared
        let stamp = store.stamp(for: client)
        guard screenRecordingAllowed() else { return nil }
        if !store.needsCapture(target.id, maxPixels: maxPixels, client: client),
           let cached = store.cached(target.id, maxPixels: maxPixels, client: client) {
            return cached
        }
        await Self.waitUntilVisible(since: visibleSince)
        guard !Task.isCancelled, store.isCurrent(stamp),
              let windows = await shareableWindows(), store.isCurrent(stamp), let window = windows[target.id] else {
            return nil
        }
        let rules = Rules(client: client, protectedBundleIDs: protectedBundleIDs, hiddenBundleIDs: [])
        guard permits(target, window, rules: rules, thumbnailsLease: true), await takeSlot() else { return nil }
        defer { releaseSlot() }
        guard store.isCurrent(stamp),
              let shot = await Self.capture(window, maxPixels: maxPixels, scale: NSScreen.main?.backingScaleFactor ?? 2),
              store.isCurrent(stamp) else { return nil }
        // Refused here means only that `client` keeps no thumbnails: the preview still shows.
        _ = store.store(shot.image, for: target.id, maxPixels: maxPixels, bytes: shot.bytes, source: .sck, stamp: stamp)
        return shot.image
    }

    /// After a §2.5 purge: the batches stop and nothing of the window server's list is kept either. Captures in
    /// flight land on a stale stamp and are dropped.
    func purged() {
        for task in batches.values { task.cancel() }
        batches = [:]
        dropShareable()
    }

    // MARK: The rule (§4.9, §4.10)

    private struct Rules {
        let client: ModuleID
        let protectedBundleIDs: [String]
        let hiddenBundleIDs: [String]
    }

    /// The shared capture rule with the window server's owner. Consent was checked for the batch.
    private func permits(_ target: CaptureTarget, _ window: SCWindow, rules: Rules, thumbnailsLease: Bool) -> Bool {
        let owner = window.owningApplication
        let bundleID = owner?.bundleIdentifier
        let gate = CaptureGate(client: rules.client, screenRecording: true, thumbnailsLease: thumbnailsLease,
                               ownerMatches: owner?.processID == target.pid,
                               protectedApp: Config.bundleID(bundleID, matchesAny: rules.protectedBundleIDs),
                               hiddenFromDock: Config.bundleID(bundleID, matchesAny: rules.hiddenBundleIDs),
                               privatePath: false, hasLastSeen: false)
        return WindowCatalogRules.captureRefusal(target.window, gate: gate) == nil
    }

    // MARK: Pacing (§4.9)

    private static func waitUntilVisible(since visibleSince: Double) async {
        let wait = visibleSince + visibleDelay - now
        guard wait > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }

    /// Waits for one of the 4 running places and the 8-a-second allowance. False if the task was cancelled.
    private func takeSlot() async -> Bool {
        while !Task.isCancelled {
            let now = Self.now
            recentStarts.removeAll { now - $0 >= 1 }
            if running < Self.maxRunning, recentStarts.count < Self.maxPerSecond {
                running += 1
                recentStarts.append(now)
                return true
            }
            if running >= Self.maxRunning {
                await withCheckedContinuation { waiters.append($0) }
            } else if let oldest = recentStarts.first {
                try? await Task.sleep(nanoseconds: UInt64(max(0.005, oldest + 1 - now) * 1_000_000_000))
            }
        }
        return false
    }

    /// Every waiter looks again; the ones that find no place wait again.
    private func releaseSlot() {
        running -= 1
        let woken = waiters
        waiters = []
        for waiter in woken { waiter.resume() }
    }

    // MARK: ScreenCaptureKit

    /// The on-screen windows, from a list both clients share for 2 s.
    private func shareableWindows() async -> [CGWindowID: SCWindow]? {
        if let shareableAt, Self.now - shareableAt < Self.shareableLifetime { return shareable }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        var byID: [CGWindowID: SCWindow] = [:]
        for window in content.windows { byID[window.windowID] = window }
        shareable = byID
        shareableAt = Self.now
        return byID
    }

    private func dropShareable() {
        shareable = [:]
        shareableAt = nil
    }

    /// The image, sized from what was captured (§R4 PC-2), and its bytes as the budget counts them.
    private static func capture(_ window: SCWindow, maxPixels: CGFloat,
                                scale: CGFloat) async -> (image: NSImage, bytes: Int)? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }
        let pixelRatio = min(scale, maxPixels / max(frame.width, frame.height))

        let config = SCStreamConfiguration()
        config.width = max(1, Int(frame.width * pixelRatio))
        config.height = max(1, Int(frame.height * pixelRatio))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }
        let size = NSSize(width: CGFloat(cgImage.width) / pixelRatio, height: CGFloat(cgImage.height) / pixelRatio)
        return (NSImage(cgImage: cgImage, size: size), cgImage.bytesPerRow * cgImage.height)
    }
}
