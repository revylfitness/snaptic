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

/// Takes window thumbnails for both clients (PLAN 0.5 §4.9, X-4, X-20, Y-7): the per-capture rule, the pacing, the
/// ScreenCaptureKit path and the private path. `ThumbnailStore` keeps what it takes.
///
/// - Consent: `CGPreflightScreenCaptureAccess()` once per batch for ScreenCaptureKit and before each private capture.
///   It is never requested from here, and finding it revoked purges the store (§2.5).
/// - The rule: Kit `WindowCatalogRules.captureRefusal` with the window server's owner pid and bundle id, checked on
///   each capture: private windows, protected apps, a wrong owner (S0-18), and for the Dock its hidden apps.
/// - Pacing: captures start only after the panel has been visible for 150 ms; each window at most once per 30 s
///   unless it's dirty; at most 8 captures a second in total and 4 at once; `SCShareableContent` is shared for 2 s.
/// - The private path (A2b; §4.9, §4.12, §4.23): minimized and other-Space windows through
///   `PrivateWindowAPI.capture` (`CGSHWCaptureWindowList`, behind the window-symbol contract), one capture at a time
///   for both clients, at 1x, scaled down at once to the client's size. Each capture passes Kit `CaptureContentCheck`
///   before it's shown or kept; a suspect leaves the card on its last-seen thumbnail or the icon. None in Safe Mode.
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
    /// The private path's one lane, shared by both clients (§4.9).
    private var privateBusy = false
    private var privateWaiters: [CheckedContinuation<Void, Never>] = []
    /// The content check (§4.9; X2-8): one counter for the path, both clients together.
    private var contentCheck = CaptureContentCheck()

    /// The private captures' calls and their scale-down run here, off main.
    private nonisolated static let privateQueue = DispatchQueue(label: "snaptic.windows.privateCapture",
                                                                qos: .userInitiated)

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
            guard let self, !Task.isCancelled, store.isCurrent(stamp), self.screenRecordingAllowed() else { return }
            // Minimized and other-Space windows take the private path while it's open; the rest take ScreenCaptureKit
            // (on-screen windows only). Both run at once, the private one a capture at a time.
            let privateOpen = Self.privatePathOpen
            let privateTargets = privateOpen ? batch.filter { Self.takesPrivatePath($0, client: client) } : []
            let privateIDs = Set(privateTargets.map(\.id))
            let sckTargets = batch.filter { !privateIDs.contains($0.id) }
            async let privateDone: Void = self.capturePrivately(privateTargets, client: client, maxPixels: maxPixels,
                                                                stamp: stamp, rules: rules, onImage: onImage)
            await self.captureWithSCK(sckTargets, client: client, maxPixels: maxPixels, stamp: stamp, rules: rules,
                                      onImage: onImage)
            await privateDone
        }
    }

    /// The ScreenCaptureKit half of a batch: on-screen windows, up to 4 at once.
    private func captureWithSCK(_ batch: [CaptureTarget], client: ModuleID, maxPixels: CGFloat, stamp: ThumbnailStamp,
                                rules: Rules, onImage: @escaping @MainActor (CGWindowID, NSImage) -> Void) async {
        let store = ThumbnailStore.shared
        guard !batch.isEmpty, let windows = await shareableWindows(), !Task.isCancelled, store.isCurrent(stamp) else {
            return
        }
        for target in batch {
            guard store.needsCapture(target.id, maxPixels: maxPixels, client: client),
                  let window = windows[target.id],
                  permits(target, window, rules: rules, thumbnailsLease: store.holdsThumbnails(client))
            else { continue }
            guard await takeSlot() else { return }
            guard !Task.isCancelled, store.isCurrent(stamp) else {
                releaseSlot()
                return
            }
            // Each capture runs on its own; a stale one finishes and is dropped by the stamp check (X2-12).
            Task { @MainActor [weak self] in
                defer { self?.releaseSlot() }
                guard let shot = await Self.capture(window, maxPixels: maxPixels, scale: Self.scale(of: window.frame))
                else { return }
                switch store.store(shot.image, for: target.id, maxPixels: maxPixels, bytes: shot.bytes,
                                   source: .sck, stamp: stamp) {
                case .stored, .skipped: onImage(target.id, shot.image)
                case .refused: break
                }
            }
        }
    }

    /// The private half of a batch: minimized and other-Space windows, one at a time.
    private func capturePrivately(_ batch: [CaptureTarget], client: ModuleID, maxPixels: CGFloat,
                                  stamp: ThumbnailStamp, rules: Rules,
                                  onImage: @escaping @MainActor (CGWindowID, NSImage) -> Void) async {
        guard !batch.isEmpty else { return }
        let store = ThumbnailStore.shared
        forgetGonePlainWindows()
        for target in batch {
            guard !Task.isCancelled, store.isCurrent(stamp), Self.privatePathOpen else { return }
            guard store.needsCapture(target.id, maxPixels: maxPixels, client: client),
                  let shot = await privateShot(target, rules: rules, maxPixels: maxPixels, stamp: stamp,
                                               thumbnailsLease: { store.holdsThumbnails(client) })
            else { continue }
            switch store.store(shot.image, for: target.id, maxPixels: maxPixels, bytes: shot.bytes,
                               source: .privateCapture, stamp: stamp) {
            case .stored, .skipped: onImage(target.id, shot.image)
            case .refused: break
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
    /// purged. A minimized or other-Space window takes the private path while it's open (A2b); that capture, like
    /// every private one, needs `.thumbnails` (§4.9).
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
        let rules = Rules(client: client, protectedBundleIDs: protectedBundleIDs, hiddenBundleIDs: [])
        if Self.privatePathOpen, Self.takesPrivatePath(target, client: client) {
            guard !Task.isCancelled, store.isCurrent(stamp),
                  let shot = await privateShot(target, rules: rules, maxPixels: maxPixels, stamp: stamp,
                                               thumbnailsLease: { store.holdsThumbnails(client) }),
                  store.isCurrent(stamp) else { return nil }
            _ = store.store(shot.image, for: target.id, maxPixels: maxPixels, bytes: shot.bytes,
                            source: .privateCapture, stamp: stamp)
            return shot.image
        }
        guard !Task.isCancelled, store.isCurrent(stamp),
              let windows = await shareableWindows(), store.isCurrent(stamp), let window = windows[target.id] else {
            return nil
        }
        guard permits(target, window, rules: rules, thumbnailsLease: true), await takeSlot() else { return nil }
        defer { releaseSlot() }
        guard store.isCurrent(stamp),
              let shot = await Self.capture(window, maxPixels: maxPixels, scale: Self.scale(of: window.frame)),
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

    // MARK: The private path (A2b; §4.9, §4.12, §4.13)

    /// Whether minimized and other-Space windows may take the private path now: not Safe Mode, and `hwCapture` not
    /// refused, stopped or poisoned. It starts no probe; the first capture that passes every gate does (§4.12 step 4).
    static var privatePathOpen: Bool { PrivateWindowAPI.capturePathOpen }

    /// Whether the catalog sends `target` to the private path, before the window server's own check.
    private static func takesPrivatePath(_ target: CaptureTarget, client: ModuleID) -> Bool {
        let gate = CaptureGate(client: client, screenRecording: true, thumbnailsLease: true, ownerMatches: true,
                               protectedApp: false, hiddenFromDock: false, privatePath: true, hasLastSeen: false)
        return WindowCatalogRules.capturePath(target.window, gate: gate) == .privateCapture
    }

    /// The shared capture rule for the private path, with the window server's own owner (S0-18) and that owner's
    /// bundle id; nil refuses. Otherwise the window server's size in points, for the result's pixel limit.
    private func privatePermits(_ target: CaptureTarget, rules: Rules, thumbnailsLease: Bool) -> CGSize? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], target.id) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target.id })
        else { return nil }
        let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        let bundleID = owner.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        let gate = CaptureGate(client: rules.client, screenRecording: true, thumbnailsLease: thumbnailsLease,
                               ownerMatches: owner == target.pid,
                               protectedApp: Config.bundleID(bundleID, matchesAny: rules.protectedBundleIDs),
                               hiddenFromDock: Config.bundleID(bundleID, matchesAny: rules.hiddenBundleIDs),
                               privatePath: true, hasLastSeen: false)
        guard WindowCatalogRules.capturePath(target.window, gate: gate) == .privateCapture else { return nil }
        if let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
            .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }), bounds.width > 0, bounds.height > 0 {
            return bounds.size
        }
        return CGSize(width: target.window.bounds.width, height: target.window.bounds.height)
    }

    /// One private capture, or nil for the card's fallback (last-seen or the icon). The gates are checked before the
    /// probe and again just before the call. The probe, the call and the scale-down run in the one private lane (so
    /// no two `CGSHWCaptureWindowList` calls overlap), the call and the scale-down off main, holding one of the 4
    /// places and counting toward the 8 a second. A suspect capture is dropped (§4.9).
    private func privateShot(_ target: CaptureTarget, rules: Rules, maxPixels: CGFloat, stamp: ThumbnailStamp,
                             thumbnailsLease: () -> Bool) async -> (image: NSImage, bytes: Int)? {
        let store = ThumbnailStore.shared
        guard Self.privatePathOpen, privatePermits(target, rules: rules, thumbnailsLease: thumbnailsLease()) != nil,
              await takePrivateLane() else { return nil }
        defer { releasePrivateLane() }
        // §4.12 step 4: the probe runs just before the first private capture that passes every gate.
        guard await Self.captureProbed(), !Task.isCancelled, store.isCurrent(stamp), await takeSlot() else {
            return nil
        }
        defer { releaseSlot() }
        // Every gate again, just before the call: consent, the lease, the owner, the lists (§4.9).
        guard !Task.isCancelled, store.isCurrent(stamp), screenRecordingAllowed(),
              let size = privatePermits(target, rules: rules, thumbnailsLease: thumbnailsLease()) else { return nil }
        let maxScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let limit = WindowResults.pixelLimit(windowWidth: Double(size.width), windowHeight: Double(size.height),
                                             maxScale: Double(maxScale))
        let windowID = target.id
        let longest = Double(maxPixels)
        let taken: PrivateTaken? = await withCheckedContinuation { continuation in
            Self.privateQueue.async {
                continuation.resume(returning: Self.takePrivate(windowID, pixelLimit: limit, maxPixels: longest))
            }
        }
        guard let taken, store.isCurrent(stamp) else { return nil }
        switch contentCheck.record(window: windowID, suspect: CaptureContentCheck.isSuspect(taken.sample)) {
        case .accept:
            break
        case .suspect:
            EventLog.shared.count(Self.suspectKey)
            return nil
        case .suspectRecheck:
            EventLog.shared.count(Self.suspectKey)
            startRecheck()
            return nil
        }
        // 1x pixels are points, so the card sizes from what was captured (a part off screen comes back cut; PC-2).
        let image = NSImage(cgImage: taken.image, size: NSSize(width: taken.pointWidth, height: taken.pointHeight))
        return (image, taken.image.bytesPerRow * taken.image.height)
    }

    private static let suspectKey = "windows.captureSuspect"

    /// Waits for `PrivateWindowAPI.ensureCaptureProbed`: true once `hwCapture`'s probe has passed on this build.
    private static func captureProbed() async -> Bool {
        await withCheckedContinuation { continuation in
            PrivateWindowAPI.ensureCaptureProbed { continuation.resume(returning: $0) }
        }
    }

    /// What the private queue hands back: the scaled image, the captured size and the content check's sample.
    private struct PrivateTaken: @unchecked Sendable {
        let image: CGImage
        let pointWidth: Int
        let pointHeight: Int
        let sample: [UInt8]?
    }

    /// On the private queue: the call under the contract, the scale-down to `maxPixels` on the longer side, and the
    /// 16 × 16 luma sample.
    private nonisolated static func takePrivate(_ windowID: CGWindowID, pixelLimit: Double?,
                                                maxPixels: Double) -> PrivateTaken? {
        guard let full = PrivateWindowAPI.capture(windowID, pixelLimit: pixelLimit),
              let scaled = scaledDown(full, maxPixels: maxPixels) else { return nil }
        return PrivateTaken(image: scaled, pointWidth: full.width, pointHeight: full.height,
                            sample: PrivateWindowAPI.lumaSample(scaled))
    }

    /// `image` drawn at `PrivateCaptureScaling.scaledSize`, or itself when it's small enough already.
    private nonisolated static func scaledDown(_ image: CGImage, maxPixels: Double) -> CGImage? {
        guard let size = PrivateCaptureScaling.scaledSize(width: image.width, height: image.height,
                                                          maxPixels: maxPixels) else { return nil }
        if size.width == image.width && size.height == image.height { return image }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    /// Three suspects in a row from two windows: the probe-window capture runs again, in the private lane (§4.9).
    private func startRecheck() {
        Task { @MainActor [weak self] in
            guard let self, await self.takePrivateLane() else { return }
            let result = await withCheckedContinuation { continuation in
                PrivateWindowAPI.recheckCapture { continuation.resume(returning: $0) }
            }
            self.releasePrivateLane()
            self.contentCheck.recheckFinished(result)
            EventLog.shared.record(.privateAPI, "windows.captureRecheck " + String(describing: result))
        }
    }

    /// Plain windows that no longer exist lose the mark, so a reused id proves itself again.
    private func forgetGonePlainWindows() {
        guard !contentCheck.plain.isEmpty else { return }
        let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ids = Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        contentCheck.keepPlain(ids)
    }

    /// Waits for the private lane. False if the task was cancelled.
    private func takePrivateLane() async -> Bool {
        while privateBusy {
            guard !Task.isCancelled else { return false }
            await withCheckedContinuation { privateWaiters.append($0) }
        }
        guard !Task.isCancelled else { return false }
        privateBusy = true
        return true
    }

    private func releasePrivateLane() {
        privateBusy = false
        let woken = privateWaiters
        privateWaiters = []
        for waiter in woken { waiter.resume() }
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

    /// The backing scale of the display a window's centre is on (M13: mixed Retina and non-Retina displays), else
    /// the main display's. `frame` is the window server's, top-left origin.
    private static func scale(of frame: CGRect) -> CGFloat {
        let cocoa = Screens.cocoaRect(fromGlobal: frame)
        let centre = NSPoint(x: cocoa.midX, y: cocoa.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(centre, $0.frame, false) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
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
