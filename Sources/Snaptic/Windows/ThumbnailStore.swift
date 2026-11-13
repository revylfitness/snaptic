import AppKit
import ScreenCaptureKit

/// A window Snaptic wants to capture, and the process that should own it.
struct CaptureTarget: Equatable {
    let id: CGWindowID
    let pid: pid_t
}

/// Captures window thumbnails with ScreenCaptureKit.
///
/// Privacy: images live only in memory, the cache is small, least-recently used
/// and expires after a few minutes, entries for closed windows are dropped,
/// nothing is captured once the switcher is dismissed, and everything is purged
/// when the screen sleeps or locks. The caller decides which windows may be
/// captured; this store double-checks ownership with ScreenCaptureKit itself.
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private static let capacity = 40
    private static let maxAge: TimeInterval = 5 * 60

    private var cache: [CGWindowID: (image: NSImage, at: Date)] = [:]
    private var recency: [CGWindowID] = []          // least recent first
    private var shareable: [CGWindowID: SCWindow] = [:]
    private var generation = 0

    func cached(_ ids: [CGWindowID]) -> [CGWindowID: NSImage] {
        let now = Date()
        var result: [CGWindowID: NSImage] = [:]
        for id in ids {
            if let entry = cache[id], now.timeIntervalSince(entry.at) < Self.maxAge { result[id] = entry.image }
        }
        return result
    }

    /// Stops any capture in flight. Called whenever the switcher closes.
    func invalidate() {
        generation += 1
        shareable = [:]
    }

    /// Forgets every image (screen locked, display asleep, user switched away).
    func purge() {
        invalidate()
        cache = [:]
        recency = []
    }

    /// Drops images of windows that no longer exist (or that may no longer be
    /// captured) and anything too old.
    func prune(keeping allowed: Set<CGWindowID>) {
        let now = Date()
        cache = cache.filter { allowed.contains($0.key) && now.timeIntervalSince($0.value.at) < Self.maxAge }
        recency.removeAll { cache[$0] == nil }
    }

    /// Captures `targets` one at a time, `priority` first.
    func refresh(
        _ targets: [CaptureTarget],
        blockedBundleIDs: [String],
        maxPixels: CGFloat,
        priority: CGWindowID?,
        onImage: @escaping @MainActor (CGWindowID, NSImage) -> Void
    ) {
        guard !targets.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        generation += 1
        let token = generation
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        var reordered = targets
        if let priority, let index = reordered.firstIndex(where: { $0.id == priority }) {
            let first = reordered.remove(at: index)
            reordered.insert(first, at: 0)
        }
        let ordered = reordered

        Task { @MainActor in
            guard let windows = await Self.shareableWindows(), token == self.generation else { return }
            self.shareable = windows
            for target in ordered {
                guard token == self.generation else { return }
                guard let window = windows[target.id],
                      Self.isOwned(window, by: target.pid, blockedBundleIDs: blockedBundleIDs),
                      let image = await Self.capture(window, maxPixels: maxPixels, scale: scale) else { continue }
                // The switcher may have closed while we waited: don't keep the image.
                guard token == self.generation else { return }
                self.store(target.id, image)
                onImage(target.id, image)
            }
        }
    }

    /// A one-off high-resolution capture for the full-size preview. Not cached.
    func captureForPreview(_ target: CaptureTarget, blockedBundleIDs: [String], maxPixels: CGFloat) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let token = generation
        var found = shareable[target.id]
        if found == nil {
            guard let windows = await Self.shareableWindows(), token == generation else { return nil }
            shareable = windows
            found = windows[target.id]
        }
        guard let window = found, Self.isOwned(window, by: target.pid, blockedBundleIDs: blockedBundleIDs) else {
            return nil
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = await Self.capture(window, maxPixels: maxPixels, scale: scale)
        return token == generation ? image : nil
    }

    /// ScreenCaptureKit's own view of who owns the window must match what we
    /// expect, and the owner must not be a protected app.
    private static func isOwned(_ window: SCWindow, by pid: pid_t, blockedBundleIDs: [String]) -> Bool {
        guard let owner = window.owningApplication, owner.processID == pid else { return false }
        return !Config.bundleID(owner.bundleIdentifier, matchesAny: blockedBundleIDs)
    }

    private func store(_ id: CGWindowID, _ image: NSImage) {
        cache[id] = (image, Date())
        recency.removeAll { $0 == id }
        recency.append(id)
        while recency.count > Self.capacity {
            cache[recency.removeFirst()] = nil
        }
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
