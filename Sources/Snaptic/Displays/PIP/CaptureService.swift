import AppKit
import Combine
import CoreGraphics
import CoreMedia
@preconcurrency import ScreenCaptureKit
import SnapticKit

/// Live state of one running PIP or stream, for the settings page and menus.
struct PIPSessionInfo: Identifiable, Equatable {
    enum State: String {
        case starting, choosingWindow, running, paused, hidden, suspended

        var title: String {
            switch self {
            case .starting: return L("Starting…")
            case .choosingWindow: return L("Choose a window…")
            case .running: return L("Running")
            case .paused: return L("Paused")
            case .hidden: return L("Hidden")
            case .suspended: return L("Paused while locked")
            }
        }
    }

    let id: StableID
    var name: String
    var kind: PIPKind
    var source: PIPSourceRef
    var state: State
}

enum CaptureError: Error, Equatable {
    case permission
    case sourceMissing
    case cancelled
    case failed(String)

    var message: String {
        switch self {
        case .permission: return L("Screen Recording isn’t allowed for Snaptic. Allow it in System Settings › Privacy & Security, then relaunch Snaptic.")
        case .sourceMissing: return L("The source is no longer available.")
        case .cancelled: return L("Stopped.")
        case .failed(let text): return text
        }
    }
}

/// ScreenCaptureKit access for PIP and streams (PLAN §10, §4.10(5)). Builds the
/// privacy-filtered display filters, keeps them current (app activation and launch,
/// new windows, every 5 s), starts and stops streams with lifetime checks after
/// every await [R2C c11], and runs the system content-sharing picker for windows.
@MainActor final class CaptureService: ObservableObject, DisplayServiceLifecycle, SessionParticipant {
    static var serviceID: DisplayServiceID { .capture }
    static var privateSymbols: [PrivateSymbol] { [] }
    weak var context: DisplaysContext?
    /// Set by PIPController while it runs.
    weak var controller: PIPController?

    @Published private(set) var sessions: [PIPSessionInfo] = []

    private struct Tracked {
        let stream: SCStream
        let displayID: CGDirectDisplayID
        var signature: String
    }

    private var lifetime: Lifetime?
    /// Streams between start and stop, held strongly until `stopCapture` returns.
    private var active: [ObjectIdentifier: SCStream] = [:]
    /// Display streams whose filters follow the privacy rules.
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var observers: [NSObjectProtocol] = []
    private var privacyTimer: Timer?
    private var windowTimer: Timer?
    private var knownWindowIDs: Set<Int> = []
    private var refreshing = false
    private var refreshAgain = false
    private var pickerObserver: PIPPickerObserver?
    private var pendingPick: (@MainActor (SCContentFilter?) -> Void)?

    private(set) var privateWindowCount = 0
    private(set) var excludedAppCount = 0
    private(set) var privacyRefreshes: UInt64 = 0
    private(set) var lastFailure: String?

    init() {}

    func activate(_ context: DisplaysContext, lifetime: Lifetime) {
        guard self.lifetime == nil else { return }
        self.context = context
        self.lifetime = lifetime
        context.registerSession(self, lifetime: lifetime)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPrivacy() }
            })
        }
    }

    func deactivate() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        stopTimers()
        let streams = Array(active.values)
        active = [:]
        tracked = [:]
        streams.forEach { finishStopping($0) }
        cancelPick()
        endPicker()
        sessions = []
        refreshing = false
        refreshAgain = false
        lifetime = nil
        context = nil
    }

    // MARK: SessionParticipant

    /// Lock, switch-out or sleep: every stream stops, whoever owns it (the controller
    /// also suspends its sessions and clears their frames, and restarts them later).
    func sessionDidPause() {
        guard !active.isEmpty else { return }
        let streams = Array(active.values)
        active = [:]
        tracked = [:]
        stopTimers()
        streams.forEach { finishStopping($0) }
        cancelPick()
        EventLog.shared.record(.pip, "Capture stopped for the session (\(streams.count) streams)")
    }

    /// Nothing restarts here; resuming is the controller's decision.
    func sessionDidResume() {}

    var isActive: Bool { lifetime != nil }
    var activeStreamCount: Int { active.count }

    func publish(_ infos: [PIPSessionInfo]) {
        if infos != sessions { sessions = infos }
    }

    // MARK: Content and filters

    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    /// A display filter that shows only allowed apps' windows, minus private windows,
    /// plus a signature that changes whenever the filter would.
    func displayFilter(for displayID: CGDirectDisplayID, in content: SCShareableContent) -> (filter: SCContentFilter, signature: String)? {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let protected = context?.config.value.pip.protectedBundlePrefixes ?? PIPPrivacy.defaultProtectedPrefixes
        let own = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = content.applications.filter { app in
            let bundle = app.bundleIdentifier.isEmpty ? nil : app.bundleIdentifier
            return app.processID != ownPID && PIPPrivacy.isCaptureAllowed(bundleID: bundle, ownBundleID: own, protected: protected)
        }
        let allowed = Set(apps.map(\.processID))
        let hidden = content.windows.filter { window in
            guard let app = window.owningApplication, allowed.contains(app.processID) else { return false }
            return PIPPrivacy.isPrivateWindow(title: window.title, bundleID: app.bundleIdentifier)
        }
        privateWindowCount = hidden.count
        excludedAppCount = content.applications.count - apps.count
        let filter = SCContentFilter(display: display, including: apps, exceptingWindows: hidden)
        let signature = "\(displayID)|" + allowed.sorted().map { String($0) }.joined(separator: ",") + "|"
            + hidden.map { String($0.windowID) }.sorted().joined(separator: ",")
        return (filter, signature)
    }

    static func configuration(width: Int, height: Int, interval: Double, showsCursor: Bool,
                              sourceRect: CGRect?) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = max(16, width)
        c.height = max(16, height)
        c.minimumFrameInterval = CMTime(seconds: max(interval, 1.0 / 120), preferredTimescale: 6000)
        c.queueDepth = 3
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.showsCursor = showsCursor
        c.scalesToFit = true
        c.colorSpaceName = CGColorSpace.sRGB
        if let r = sourceRect, r.width >= 1, r.height >= 1 { c.sourceRect = r }
        return c
    }

    static func classify(_ error: Error) -> CaptureError {
        let ns = error as NSError
        if ns.domain == SCStreamErrorDomain, ns.code == SCStreamError.Code.userDeclined.rawValue { return .permission }
        return .failed(L("The capture couldn’t start (error \(ns.code))."))
    }

    // MARK: Streams

    /// Starts a stream. If `lifetime` ends (or the service deactivates) during the
    /// start, the stream is stopped and `.cancelled` returned.
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, receiver: StreamReceiver,
               privacyDisplay: CGDirectDisplayID?, signature: String?, lifetime: Lifetime) async -> Result<SCStream, CaptureError> {
        // Never while locked, asleep or switched out (PLAN §4.10(5)); the controller resumes.
        guard self.lifetime != nil, !lifetime.isEnded, context?.sessionGate.isOpen == true else { return .failure(.cancelled) }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        do {
            try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
        } catch {
            lastFailure = L("Couldn’t attach to the capture.")
            return .failure(.failed(L("Couldn’t attach to the capture.")))
        }
        let key = ObjectIdentifier(stream)
        active[key] = stream
        do {
            try await stream.startCapture()
        } catch {
            active[key] = nil
            let classified = Self.classify(error)
            lastFailure = classified.message
            return .failure(classified)
        }
        guard !lifetime.isEnded, self.lifetime != nil, active[key] != nil, context?.sessionGate.isOpen == true else {
            stop(stream)
            return .failure(.cancelled)
        }
        if let displayID = privacyDisplay {
            tracked[key] = Tracked(stream: stream, displayID: displayID, signature: signature ?? "")
            startTimers()
        }
        return .success(stream)
    }

    func stop(_ stream: SCStream) {
        let key = ObjectIdentifier(stream)
        active[key] = nil
        tracked[key] = nil
        if tracked.isEmpty { stopTimers() }
        finishStopping(stream)
    }

    /// The task keeps the stream alive until `stopCapture` completes [R2C c11].
    private func finishStopping(_ stream: SCStream) {
        Task { @MainActor in
            try? await stream.stopCapture()
        }
    }

    func update(_ stream: SCStream, configuration: SCStreamConfiguration) {
        guard let lifetime, active[ObjectIdentifier(stream)] != nil else { return }
        lifetime.spawn {
            try? await stream.updateConfiguration(configuration)
        }
    }

    // MARK: Privacy refresh (PLAN §4.10(5))

    /// Rebuilds every display stream's filter and applies the ones that changed.
    func refreshPrivacy() {
        guard !tracked.isEmpty, let lifetime, !lifetime.isEnded else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        privacyRefreshes &+= 1
        lifetime.spawn { [weak self] in
            guard let self else { return }
            defer {
                self.refreshing = false
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refreshPrivacy()
                }
            }
            guard let content = try? await self.shareableContent(), self.lifetime != nil else { return }
            for (key, entry) in self.tracked {
                guard let built = self.displayFilter(for: entry.displayID, in: content), built.signature != entry.signature else {
                    continue
                }
                self.tracked[key]?.signature = built.signature
                try? await entry.stream.updateContentFilter(built.filter)
                if self.lifetime == nil { return }
            }
        }
    }

    /// New on-screen windows trigger a refresh (window ids only; nothing else is read).
    private func pollWindows() {
        guard !tracked.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return }
        let ids = Set(list.compactMap { $0[kCGWindowNumber as String] as? Int })
        let appeared = !ids.subtracting(knownWindowIDs).isEmpty
        knownWindowIDs = ids
        if appeared { refreshPrivacy() }
    }

    private func startTimers() {
        if privacyTimer == nil {
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPrivacy() }
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            privacyTimer = t
        }
        if windowTimer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollWindows() }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            windowTimer = t
        }
    }

    private func stopTimers() {
        privacyTimer?.invalidate()
        privacyTimer = nil
        windowTimer?.invalidate()
        windowTimer = nil
        knownWindowIDs = []
    }

    // MARK: Window picker (SCContentSharingPicker, per session)

    /// Shows the system picker for one window; `completion` gets nil on cancel.
    func pickWindow(_ completion: @escaping @MainActor (SCContentFilter?) -> Void) {
        guard lifetime != nil else {
            completion(nil)
            return
        }
        cancelPick()
        pendingPick = completion
        let picker = SCContentSharingPicker.shared
        if pickerObserver == nil {
            let observer = PIPPickerObserver()
            let target = CallbackTarget(self)
            observer.onEvent = { box in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { target.target?.pickerFinished(box.value) }
                }
            }
            picker.add(observer)
            pickerObserver = observer
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedBundleIDs = pickerExcludedBundleIDs()
        configuration.excludedWindowIDs = NSApp.windows.map { $0.windowNumber }
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present()
    }

    func cancelPick() {
        let pending = pendingPick
        pendingPick = nil
        pending?(nil)
    }

    /// Hides the system picker UI once no window session needs it.
    func endPicker() {
        guard pendingPick == nil else { return }
        let picker = SCContentSharingPicker.shared
        if let observer = pickerObserver {
            picker.remove(observer)
            pickerObserver = nil
        }
        picker.isActive = false
    }

    private func pickerFinished(_ filter: SCContentFilter?) {
        let pending = pendingPick
        pendingPick = nil
        pending?(filter)
    }

    /// Snaptic itself, Notification Center and running protected apps.
    private func pickerExcludedBundleIDs() -> [String] {
        var ids = PIPPrivacy.alwaysExcludedBundleIDs
        if let own = Bundle.main.bundleIdentifier { ids.append(own) }
        let protected = context?.config.value.pip.protectedBundlePrefixes ?? PIPPrivacy.defaultProtectedPrefixes
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, PIPPrivacy.matches(id, prefixes: protected), !ids.contains(id) { ids.append(id) }
        }
        return ids
    }
}

/// Carries a non-Sendable filter across the queue hop.
struct PIPFilterBox: @unchecked Sendable {
    let value: SCContentFilter?
}

/// The picker observer, a separate nonisolated class (PLAN §14.3 rule 5).
final class PIPPickerObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    /// Set once, before the observer is added.
    var onEvent: (@Sendable (PIPFilterBox) -> Void)?

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        onEvent?(PIPFilterBox(value: nil))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        // Changes to an existing stream's content aren't accepted (the picker is
        // configured not to offer them); only a new pick starts a session.
        guard stream == nil else { return }
        onEvent?(PIPFilterBox(value: filter))
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        onEvent?(PIPFilterBox(value: nil))
    }
}
