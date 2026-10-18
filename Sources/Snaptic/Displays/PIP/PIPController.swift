import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
@preconcurrency import ScreenCaptureKit
import SnapticKit

fileprivate extension DisplayActionID {
    static let pipStopAll = DisplayActionID(rawValue: "e.pipStopAll")
    static let pipHideAll = DisplayActionID(rawValue: "e.pipHideAll")
    static let pipPauseAll = DisplayActionID(rawValue: "e.pipPauseAll")
    static let pipToggleDisplay = DisplayActionID(rawValue: "e.pipToggleDisplay")
    static let pipPickWindow = DisplayActionID(rawValue: "e.pipPickWindow")
    static func pipToggle(_ id: StableID) -> DisplayActionID { DisplayActionID(rawValue: "e.pipToggle.\(id.rawValue)") }
}

/// One running PIP window or full-screen stream.
@MainActor private final class PIPSession {
    let id: StableID
    var configuration: PIPConfiguration
    let source: PIPSourceRef
    let lifetime: Lifetime
    let mailbox = FrameMailbox()
    let receiver: StreamReceiver
    let pipeline = FilterPipeline()
    var window: PIPWindow?
    var stream: SCStream?
    var windowFilter: SCContentFilter?
    var sourceDisplayID: CGDirectDisplayID?
    var targetDisplayID: CGDirectDisplayID?
    var sourcePointSize = PIPSize(width: 1920, height: 1080)
    var sourcePixelSize = PIPSize(width: 1920, height: 1080)
    var refreshRate: Double = 60
    var appliedCaptureKey = ""
    var starting = false
    var choosingWindow = false
    var userPaused = false
    var hidden = false
    var occluded = false
    var suspended = false
    var receivedFirstFrame = false
    /// Bumped by every capture start and every suspend: a start task whose
    /// generation is stale after an await stops what it made and gives up.
    var captureGeneration: UInt64 = 0
    var restoreMode: (displayID: CGDirectDisplayID, mode: ModeRef)?
    var onFirstFrame: (() -> Void)?

    init(id: StableID, configuration: PIPConfiguration, source: PIPSourceRef, lifetime: Lifetime) {
        self.id = id
        self.configuration = configuration
        self.source = source
        self.lifetime = lifetime
        receiver = StreamReceiver(mailbox: mailbox)
    }

    func drain() {
        // A frame already in flight when the session was suspended is never shown.
        if suspended {
            mailbox.clear()
            return
        }
        guard let frame = mailbox.take() else { return }
        window?.display(frame)
        if !receivedFirstFrame {
            receivedFirstFrame = true
            onFirstFrame?()
        }
    }

    var publicState: PIPSessionInfo.State {
        if suspended { return .suspended }
        if choosingWindow { return .choosingWindow }
        if hidden { return .hidden }
        if userPaused { return .paused }
        if starting || !receivedFirstFrame { return .starting }
        return .running
    }
}

/// Picture in Picture and full-screen streams (PLAN §10; features `pip`, `pipFilters`).
@MainActor final class PIPController: DisplayFeatureController, PanicParticipant, SessionParticipant, DiagnosticsContributor {
    static var id: DisplayControllerID { .pip }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?

    enum Origin: String { case user, cli, auto }

    /// Why a start was refused, with the CLI exit code (`ControlExit`) it maps to.
    struct StartRefusal {
        let code: Int32
        let message: String
    }

    /// ⌃⌥⌘P: stops full-screen streams and turns click-through off.
    static let stopCombo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))

    private var lifetime: Lifetime?
    private var effective: Set<DisplayFeature> = []
    private var sessions: [StableID: PIPSession] = [:]
    private var order: [StableID] = []
    private var menuItems: PIPMenuItems?
    private var configActionsLifetime: Lifetime?
    private var configActionSignature = ""
    private var hotkeyLifetime: Lifetime?
    private var hotkeyToken: GlobalHotkeys.Token?
    private var hotkeyFailed = false
    private var sinks: [AnyCancellable] = []
    /// Session-gate event subscription; ends in stop().
    private var systemLifetime: Lifetime?
    private var knownDisplays: Set<DisplayKey> = []
    private var sessionPaused = false
    /// Between sleep (or display sleep) and wake: nothing resumes.
    private var displaysAsleep = false
    private var resumeOffers: [StableID] = []
    private var resumeTimer: Timer?
    private var lutCache: [StableID: CubeLUT] = [:]
    private var lutLoading: Set<StableID> = []
    private var lastError: String?
    private var startsThisRun = 0

    init() {}

    // MARK: DisplayFeatureController

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        guard feature == .pip || feature == .pipFilters else { return .unavailable(L("Not handled by Picture in Picture")) }
        // W3: static facts only (ScreenCaptureKit is always there on macOS 14+). Screen
        // Recording is a permission, not availability: Features shows "Needs Screen
        // Recording" with Grant, the feature can be turned on first, and starting a picture
        // without it asks for the permission.
        return .available
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        if let current = self.lifetime, !current.isEnded { return }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.capture.controller = self
        context.registerPanic(self, lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Picture in Picture"), lifetime: lifetime)
        let items = PIPMenuItems(context: context)
        items.controller = self
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerConfigActions()
        registerCommand(context, lifetime: lifetime)
        observeSystem(context, lifetime: lifetime)
        knownDisplays = Set(context.registry.displays.map(\.key))
        if context.permissions.state(.screenRecording) != .granted {
            context.permissions.request(.screenRecording, reason: L("Picture in Picture shows the contents of your displays."),
                                        lifetime: lifetime)
        }
        offerAutoStart(only: nil)
        publish()
        EventLog.shared.record(.pip, "PIP started (filters \(effective.contains(.pipFilters) ? "on" : "off"))")
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        for s in sessions.values { applyFilters(s) }
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        guard context != nil else { return }
        for id in order {
            guard let s = sessions[id] else { continue }
            guard let entry = PIPConfig.entry(id, in: new) else {
                endSession(id, reason: L("“\(s.configuration.name)” was deleted, so it stopped."))
                continue
            }
            let before = s.configuration
            let after = entry.configuration
            if before.kind != after.kind || before.target != after.target || entry.source != s.source {
                restart(id)
                continue
            }
            s.configuration = after
            if after.kind == .fullScreen, let refusal = streamRefusal(source: s.source, configuration: after, excluding: id) {
                endSession(id, reason: refusal)
                continue
            }
            applyWindow(s)
            applyCapture(s)
            if before.filters != after.filters || before.lutID != after.lutID { applyFilters(s) }
        }
        if old.pip.protectedBundlePrefixes != new.pip.protectedBundlePrefixes { context?.capture.refreshPrivacy() }
        if old.pip.pauseWhenOccluded != new.pip.pauseWhenOccluded { sessions.values.forEach { updateFlow($0) } }
        registerConfigActions()
        updateHotkey()
        publish()
    }

    func stop() {
        for id in order.reversed() { endSession(id, reason: nil) }
        sessions = [:]
        order = []
        sinks = []
        systemLifetime?.end()
        systemLifetime = nil
        resumeTimer?.invalidate()
        resumeTimer = nil
        if let token = hotkeyToken { context?.hotkeys.unregister(token) }
        hotkeyToken = nil
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        hotkeyFailed = false
        configActionsLifetime?.end()
        configActionsLifetime = nil
        configActionSignature = ""
        context?.capture.cancelPick()
        context?.capture.publish([])
        if context?.capture.controller === self { context?.capture.controller = nil }
        menuItems = nil
        sessionPaused = false
        displaysAsleep = false
        resumeOffers = []
        lifetime = nil
        context = nil
    }

    // MARK: Panic and session

    func panicRestore() {
        guard !sessions.isEmpty else { return }
        EventLog.shared.record(.pip, "Panic: stopping \(sessions.count) PIP/stream sessions")
        stopAll()
    }

    func sessionDidPause() { suspendAll() }

    func sessionDidResume() { resumeIfPossible() }

    /// Console and unlocked, read fresh (PLAN §4.9: every resume re-checks the session
    /// dictionary). Fails closed: no dictionary means no capture.
    static func isSessionOpen() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        let onConsole = (dict[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue ?? false
        let locked = (dict["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
        return onConsole && !locked
    }

    /// The gate is open (not locked, asleep or switched out) and a fresh read agrees.
    private func sessionUsable() -> Bool {
        guard let ctx = context, ctx.sessionGate.isOpen else { return false }
        return Self.isSessionOpen()
    }

    /// Lock, sleep, resign: captures stop and last frames clear. Window PIPs resume by
    /// themselves; full-screen streams are offered again (never restarted unattended).
    private func suspendAll() {
        guard !sessionPaused, context != nil else { return }
        sessionPaused = true
        for id in order {
            guard let s = sessions[id] else { continue }
            if s.configuration.kind == .fullScreen {
                if !resumeOffers.contains(id) { resumeOffers.append(id) }
                endSession(id, reason: nil)
                continue
            }
            // Any start still awaiting is now stale and stops what it made.
            s.captureGeneration &+= 1
            if let stream = s.stream { context?.capture.stop(stream) }
            s.stream = nil
            s.appliedCaptureKey = ""
            s.starting = false
            s.receiver.setDropping(true)
            s.mailbox.clear()
            s.window?.clearFrame()
            s.window?.setStatus(L("Paused while the Mac is locked"))
            s.suspended = true
        }
        startResumePoll()
        EventLog.shared.record(.pip, "PIP suspended for the session")
        publish()
    }

    private func resumeIfPossible() {
        guard sessionPaused, !displaysAsleep, sessionUsable(), let ctx = context, let lifetime else { return }
        sessionPaused = false
        resumeTimer?.invalidate()
        resumeTimer = nil
        for id in order {
            guard let s = sessions[id], s.suspended else { continue }
            s.suspended = false
            s.receivedFirstFrame = false
            s.window?.setStatus(s.choosingWindow ? L("Choose a window…") : L("Starting…"))
            if let filter = s.windowFilter {
                beginWindowCapture(s, filter: filter)
            } else if s.source != .window {
                beginDisplayCapture(s)
            }
        }
        let offers = resumeOffers
        resumeOffers = []
        for id in offers {
            guard let entry = PIPConfig.entry(id, in: ctx.config.value), sessions[id] == nil else { continue }
            let name = entry.configuration.name
            ctx.toasts.show(entry.configuration.kind == .fullScreen ? L("Resume the stream “\(name)”?") : L("Resume “\(name)”?"),
                            action: ToastAction(title: L("Resume")) { [weak self] in self?.userStart(id) },
                            lifetime: lifetime)
        }
        publish()
    }

    /// While suspended, checks every 2 s whether the session is usable again.
    private func startResumePoll() {
        guard resumeTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeIfPossible() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        resumeTimer = t
    }

    // MARK: Starting

    /// Starts a saved configuration and shows any refusal as a toast.
    func userStart(_ id: StableID) {
        guard let error = start(id, origin: .user), let ctx = context else { return }
        ctx.toasts.show(error, lifetime: lifetime)
    }

    /// Starts a saved configuration. Returns a user-facing reason when refused.
    @discardableResult
    func start(_ id: StableID, origin: Origin) -> String? {
        startChecked(id, origin: origin)?.message
    }

    /// Starts a saved configuration, or says why not (with the CLI exit code).
    private func startChecked(_ id: StableID, origin: Origin) -> StartRefusal? {
        func refuse(_ code: Int32, _ message: String) -> StartRefusal {
            StartRefusal(code: code, message: remember(message))
        }
        guard let ctx = context, let lifetime, !lifetime.isEnded, effective.contains(.pip) else {
            return StartRefusal(code: ControlExit.unavailable, message: L("Picture in Picture is off."))
        }
        if let existing = sessions[id] {
            if existing.hidden {
                existing.hidden = false
                updateFlow(existing)
                publish()
            }
            return nil
        }
        // Someone at the Mac clicking a menu or button means the displays are awake.
        if origin == .user { displaysAsleep = false }
        if sessionPaused { resumeIfPossible() }
        guard !sessionPaused, sessionUsable() else { return refuse(ControlExit.refused, L("Unlock the Mac first.")) }
        guard sessions.count < PIPConfig.maxConcurrentSessions else {
            return refuse(ControlExit.refused,
                          L("At most \(PIPConfig.maxConcurrentSessions) pictures in picture and streams can run at once."))
        }
        guard let entry = PIPConfig.entry(id, in: ctx.config.value) else {
            return refuse(ControlExit.notFound, L("That configuration no longer exists."))
        }
        let c = entry.configuration
        if origin == .cli, entry.source == .window {
            return refuse(ControlExit.refused, L("“\(c.name)” uses a window chosen in a picker, so it can't start from the command line."))
        }
        if ctx.permissions.state(.screenRecording) != .granted {
            if origin == .user {
                // Someone just asked for a picture: always show the guide.
                ctx.permissions.presentGuide(.screenRecording, reason: L("Picture in Picture shows the contents of your displays."))
            } else {
                ctx.permissions.request(.screenRecording, reason: L("Picture in Picture shows the contents of your displays."),
                                        lifetime: lifetime)
            }
            return refuse(ControlExit.unavailable, CaptureError.permission.message)
        }
        var sourceInfo: DisplayInfo?
        if case .display(let key) = entry.source {
            guard let info = ctx.registry.info(for: key), info.isOnline else {
                return refuse(ControlExit.unavailable, L("“\(c.name)”: the source display isn't connected."))
            }
            sourceInfo = info
        }
        var targetInfo: DisplayInfo?
        if c.kind == .fullScreen {
            if let refusal = streamRefusal(source: entry.source, configuration: c, excluding: nil) {
                return refuse(ControlExit.refused, refusal)
            }
            targetInfo = c.target.flatMap { ctx.registry.info(for: $0) }
        }
        if !ctx.config.value.pip.firstRunAcknowledged {
            ctx.toasts.show(L("Picture in Picture uses Screen Recording. macOS may ask again each month; after allowing it, relaunch Snaptic."),
                            lifetime: lifetime)
            ctx.config.value.pip.firstRunAcknowledged = true
        }

        let session = PIPSession(id: id, configuration: c, source: entry.source, lifetime: lifetime.child())
        session.sourceDisplayID = sourceInfo?.desktopID
        session.targetDisplayID = targetInfo?.desktopID
        if let displayID = session.sourceDisplayID { readSourceGeometry(session, displayID: displayID) }
        sessions[id] = session
        order.append(id)
        connect(session)
        makeWindow(session)
        applyFilters(session)
        switch entry.source {
        case .display:
            beginDisplayCapture(session)
        case .window:
            session.choosingWindow = true
            session.window?.setStatus(L("Choose a window…"))
            ctx.capture.pickWindow { [weak self, weak session] filter in
                guard let self, let session, self.sessions[session.id] === session else { return }
                session.choosingWindow = false
                guard let filter else {
                    self.endSession(session.id, reason: nil)
                    return
                }
                if session.suspended {
                    // Picked just as the Mac locked or the displays slept: start on resume.
                    session.windowFilter = filter
                    self.publish()
                    return
                }
                self.beginWindowCapture(session, filter: filter)
                self.publish()
            }
        }
        if c.kind == .fullScreen, c.nativeModeWhileStreaming { switchToNativeMode(session) }
        startsThisRun += 1
        updateHotkey()
        publish()
        EventLog.shared.record(.pip, "Started a \(c.kind == .fullScreen ? "full-screen stream" : "PIP window") (\(origin.rawValue))")
        return nil
    }

    private func remember(_ message: String) -> String {
        lastError = message
        return message
    }

    private func restart(_ id: StableID) {
        let paused = sessionPaused
        endSession(id, reason: nil)
        guard !paused else {
            // Never start anything while locked or asleep: offer it on resume instead.
            if !resumeOffers.contains(id) { resumeOffers.append(id) }
            return
        }
        userStart(id)
    }

    /// Why a full-screen stream may not run (PLAN §4.10(5), §10), or nil.
    func streamRefusal(source: PIPSourceRef, configuration c: PIPConfiguration, excluding: StableID?) -> String? {
        guard let ctx = context else { return L("Picture in Picture is off.") }
        guard let target = c.target else { return L("Choose a display for “\(c.name)” to cover.") }
        guard let t = ctx.registry.info(for: target), t.isOnline else { return L("The target display isn't connected.") }
        // A full-screen window on any member of a mirror set covers the whole set.
        func mirrorRoot(_ d: DisplayInfo) -> UInt32 { d.mirrorOf ?? d.desktopID }
        let covered = mirrorRoot(t)
        if case .display(let key) = source {
            if key == target { return L("A display can't stream onto itself.") }
            if let s = ctx.registry.info(for: key), s.desktopID == t.desktopID || mirrorRoot(s) == covered {
                return L("A display can't stream onto itself or its mirror.")
            }
        }
        let others = ctx.registry.displays.filter { $0.key != target && $0.isOnline && mirrorRoot($0) != covered }
        if t.isStronglyVisible {
            if !others.contains(where: \.isStronglyVisible) {
                return L("“\(t.name)” is the only display you can see; a full-screen stream would cover it.")
            }
        } else if !others.contains(where: { $0.isStronglyVisible || $0.isWeaklyVisible }) {
            return L("A full-screen stream would cover the last visible display.")
        }
        for s in sessions.values where s.id != excluding && s.configuration.kind == .fullScreen {
            if s.configuration.target == target { return L("Another stream already covers that display.") }
            if case .display(let theirs) = s.source, theirs == target,
               case .display(let mine) = source, s.configuration.target == mine {
                return L("Two streams can't point at each other.")
            }
        }
        return nil
    }

    // MARK: Session plumbing

    private func connect(_ s: PIPSession) {
        let box = CallbackTarget(s)
        let controllerBox = CallbackTarget(self)
        let id = s.id
        s.receiver.setHandlers(onFrame: {
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.drain() } }
        }, onStop: { declined in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { controllerBox.target?.streamStopped(id, declined: declined) }
            }
        })
        s.onFirstFrame = { [weak self, weak s] in
            s?.starting = false
            self?.publish()
        }
    }

    private func makeWindow(_ s: PIPSession) {
        let id = s.id
        let w = PIPWindow(mode: s.configuration.kind == .fullScreen ? .fullScreen : .floating, configuration: s.configuration)
        w.onClose = { [weak self] in self?.endSession(id, reason: nil) }
        w.onFrameChange = { [weak self] rect in self?.windowFrameChanged(id, rect) }
        w.onOcclusion = { [weak self] occluded in self?.occlusionChanged(id, occluded) }
        w.onCrop = { [weak self] crop in self?.setCrop(id, crop) }
        w.onCommandClick = { [weak self] point in self?.warp(id, point) }
        w.onCommand = { [weak self] command in self?.handle(command, for: id) }
        s.window = w
        applyWindow(s)
        w.setStatus(L("Starting…"))
        w.show()
    }

    private func readSourceGeometry(_ s: PIPSession, displayID: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(displayID)
        if bounds.width > 0, bounds.height > 0 {
            s.sourcePointSize = PIPSize(width: Double(bounds.width), height: Double(bounds.height))
        }
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            s.sourcePixelSize = PIPSize(width: Double(mode.pixelWidth), height: Double(mode.pixelHeight))
            s.refreshRate = mode.refreshRate
        } else {
            s.sourcePixelSize = PIPSize(width: s.sourcePointSize.width * 2, height: s.sourcePointSize.height * 2)
        }
    }

    private func visiblePixels(_ s: PIPSession) -> PIPSize {
        PIPGeometry.visibleSize(source: s.sourcePixelSize, crop: s.configuration.crop, rotation: s.configuration.rotation)
    }

    private func targetScreen(_ s: PIPSession) -> NSScreen? {
        s.targetDisplayID.flatMap { NSScreen.screen(for: $0) }
    }

    private func applyWindow(_ s: PIPSession) {
        s.window?.apply(s.configuration, visiblePixels: visiblePixels(s), targetScreen: targetScreen(s))
        s.window?.isPaused = s.userPaused
    }

    /// The capture configuration this session should have now, and a key to detect changes.
    private func captureConfiguration(_ s: PIPSession) -> (SCStreamConfiguration, String) {
        let c = s.configuration
        let crop = c.crop?.normalizedCrop()
        let cropPixels = PIPSize(width: s.sourcePixelSize.width * (crop?.width ?? 1),
                                 height: s.sourcePixelSize.height * (crop?.height ?? 1))
        var view = s.window?.contentPixelSize ?? cropPixels
        if c.isQuarterTurn { view = PIPSize(width: view.height, height: view.width) }
        let full = c.integerScaling || (c.kind == .fullScreen && (c.scaling == .integer || c.scaling == .oneToOne))
        let size = PIPGeometry.captureSize(sourcePixels: cropPixels, viewPixels: view, fullResolution: full)
        let dropping = isDropping(s)
        let interval = dropping ? 1.0 : PIPGeometry.frameInterval(fps: c.fps, displayRefresh: s.refreshRate)
        var sourceRect: CGRect?
        if let crop {
            sourceRect = CGRect(x: crop.x * s.sourcePointSize.width, y: crop.y * s.sourcePointSize.height,
                                width: crop.width * s.sourcePointSize.width, height: crop.height * s.sourcePointSize.height)
        }
        let config = CaptureService.configuration(width: Int(size.width), height: Int(size.height), interval: interval,
                                                  showsCursor: c.showCursor, sourceRect: sourceRect)
        let key = "\(Int(size.width))x\(Int(size.height))|\(interval)|\(c.showCursor)|\(String(describing: sourceRect))"
        return (config, key)
    }

    private func applyCapture(_ s: PIPSession) {
        guard let ctx = context, let stream = s.stream else { return }
        let (config, key) = captureConfiguration(s)
        guard key != s.appliedCaptureKey else { return }
        s.appliedCaptureKey = key
        ctx.capture.update(stream, configuration: config)
    }

    private func isDropping(_ s: PIPSession) -> Bool {
        let occludedPause = s.occluded && (context?.config.value.pip.pauseWhenOccluded ?? true) && s.configuration.kind == .window
        return s.userPaused || s.hidden || occludedPause || s.suspended
    }

    /// Pause, hide and occlusion: drop frames and slow the capture to 1 fps.
    private func updateFlow(_ s: PIPSession) {
        s.receiver.setDropping(isDropping(s))
        // Only on a change: re-fronting on every occlusion change would defeat the pause.
        if let w = s.window {
            if s.hidden, w.isVisible { w.hide() } else if !s.hidden, !w.isVisible { w.show() }
        }
        s.window?.isPaused = s.userPaused
        if s.userPaused { s.window?.setStatus(L("Paused")) } else if !s.suspended, s.receivedFirstFrame { s.window?.setStatus(nil) }
        applyCapture(s)
    }

    /// Whether a start task begun at `generation` may still go on after an await.
    private func isCurrent(_ s: PIPSession, _ generation: UInt64) -> Bool {
        !s.lifetime.isEnded && !s.suspended && s.captureGeneration == generation && sessions[s.id] === s
    }

    private func beginDisplayCapture(_ s: PIPSession) {
        guard let displayID = s.sourceDisplayID, context != nil, !s.suspended else { return }
        s.starting = true
        s.captureGeneration &+= 1
        let generation = s.captureGeneration
        s.lifetime.spawn { [weak self, weak s] in
            guard let self, let s, let capture = self.context?.capture else { return }
            let content: SCShareableContent
            do {
                content = try await capture.shareableContent()
            } catch {
                if self.isCurrent(s, generation) { self.captureFailed(s.id, CaptureService.classify(error)) }
                return
            }
            guard self.isCurrent(s, generation) else { return }
            guard let built = capture.displayFilter(for: displayID, in: content),
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                self.captureFailed(s.id, .sourceMissing)
                return
            }
            s.sourcePointSize = PIPSize(width: Double(display.width), height: Double(display.height))
            self.applyWindow(s)
            let (config, key) = self.captureConfiguration(s)
            let result = await capture.start(filter: built.filter, configuration: config, receiver: s.receiver,
                                             privacyDisplay: displayID, signature: built.signature, lifetime: s.lifetime)
            guard self.isCurrent(s, generation) else {
                if case .success(let stream) = result { capture.stop(stream) }
                return
            }
            switch result {
            case .success(let stream):
                s.stream = stream
                s.appliedCaptureKey = key
                self.updateFlow(s)
                self.publish()
            case .failure(let error):
                if error != .cancelled { self.captureFailed(s.id, error) }
            }
        }
    }

    private func beginWindowCapture(_ s: PIPSession, filter: SCContentFilter) {
        s.windowFilter = filter
        let rect = filter.contentRect
        let scale = Double(filter.pointPixelScale)
        if rect.width > 0, rect.height > 0 {
            s.sourcePointSize = PIPSize(width: Double(rect.width), height: Double(rect.height))
            s.sourcePixelSize = PIPSize(width: Double(rect.width) * max(scale, 1), height: Double(rect.height) * max(scale, 1))
        }
        guard !s.suspended else { return }
        s.starting = true
        s.captureGeneration &+= 1
        let generation = s.captureGeneration
        applyWindow(s)
        s.window?.setStatus(L("Starting…"))
        s.lifetime.spawn { [weak self, weak s] in
            guard let self, let s, let capture = self.context?.capture else { return }
            let (config, key) = self.captureConfiguration(s)
            let result = await capture.start(filter: filter, configuration: config, receiver: s.receiver,
                                             privacyDisplay: nil, signature: nil, lifetime: s.lifetime)
            guard self.isCurrent(s, generation) else {
                if case .success(let stream) = result { capture.stop(stream) }
                return
            }
            switch result {
            case .success(let stream):
                s.stream = stream
                s.appliedCaptureKey = key
                self.updateFlow(s)
                self.publish()
            case .failure(let error):
                if error != .cancelled { self.captureFailed(s.id, error) }
            }
        }
    }

    private func captureFailed(_ id: StableID, _ error: CaptureError) {
        guard let ctx = context, sessions[id] != nil else { return }
        if error == .permission, let lifetime {
            ctx.permissions.request(.screenRecording, reason: L("Picture in Picture shows the contents of your displays."),
                                    lifetime: lifetime)
        }
        EventLog.shared.record(.pip, "Capture failed: \(error == .permission ? "permission" : "error")")
        endSession(id, reason: remember(error.message))
    }

    private func streamStopped(_ id: StableID, declined: Bool) {
        guard let s = sessions[id], !s.suspended else { return }
        captureFailed(id, declined ? .permission : .failed(L("“\(s.configuration.name)” stopped: the capture ended.")))
    }

    /// Stops one session and reverts what it changed.
    func endSession(_ id: StableID, reason: String?) {
        guard let s = sessions.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        s.lifetime.end()
        s.receiver.detach()
        if let stream = s.stream { context?.capture.stop(stream) }
        s.stream = nil
        let pipeline = s.pipeline
        s.receiver.queue.async { pipeline.reset() }
        s.window?.close()
        s.window = nil
        if s.choosingWindow { context?.capture.cancelPick() }
        restoreNativeMode(s)
        if !sessions.values.contains(where: { $0.source == .window }) { context?.capture.endPicker() }
        if let reason, let ctx = context { ctx.toasts.show(reason, lifetime: lifetime) }
        updateHotkey()
        publish()
    }

    // MARK: Window events

    private func windowFrameChanged(_ id: StableID, _ rect: PIPRect) {
        guard let s = sessions[id], let ctx = context else { return }
        if s.configuration.kind == .window, s.configuration.windowFrame != rect.windowFrame() {
            var value = ctx.config.value
            PIPConfig.update(id, in: &value) { $0.windowFrame = rect }
            ctx.config.value = value
            s.configuration.windowFrame = rect.windowFrame()
        }
        applyCapture(s)
    }

    private func occlusionChanged(_ id: StableID, _ occluded: Bool) {
        guard let s = sessions[id] else { return }
        s.occluded = occluded
        updateFlow(s)
    }

    private func setCrop(_ id: StableID, _ crop: PIPRect?) {
        mutate(id) { $0.crop = crop }
    }

    private func mutate(_ id: StableID, _ body: (inout PIPConfiguration) -> Void) {
        guard let ctx = context else { return }
        var value = ctx.config.value
        guard PIPConfig.update(id, in: &value, body) else { return }
        ctx.config.value = value
        // Apply now; configDidChange arrives after the store's hop and is then a no-op.
        if let s = sessions[id], let entry = PIPConfig.entry(id, in: value) {
            let before = s.configuration
            s.configuration = entry.configuration
            applyWindow(s)
            applyCapture(s)
            if before.filters != entry.configuration.filters || before.lutID != entry.configuration.lutID { applyFilters(s) }
            updateHotkey()
        }
    }

    /// ⌘-click moves the pointer to the matching point of the source display.
    private func warp(_ id: StableID, _ point: PIPPoint) {
        guard let s = sessions[id], s.configuration.warpOnCommandClick, let displayID = s.sourceDisplayID else { return }
        let c = s.configuration
        let p = PIPGeometry.sourcePoint(view: point, crop: c.crop, rotation: c.rotation,
                                        flipHorizontal: c.flipHorizontal, flipVertical: c.flipVertical)
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0 else { return }
        let target = CGPoint(x: bounds.minX + CGFloat(p.x) * bounds.width, y: bounds.minY + CGFloat(p.y) * bounds.height)
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func handle(_ command: PIPWindowCommand, for id: StableID) {
        guard let s = sessions[id] else { return }
        switch command {
        case .stop: endSession(id, reason: nil)
        case .togglePause:
            s.userPaused.toggle()
            updateFlow(s)
            publish()
        case .hide:
            s.hidden = true
            updateFlow(s)
            publish()
        case .toggleClickThrough: mutate(id) { $0.clickThrough.toggle() }
        case .beginCrop: s.window?.beginCrop()
        case .resetCrop: setCrop(id, nil)
        case .toggleTitleBar: mutate(id) { $0.showTitleBar.toggle() }
        case .setLevel(let level): mutate(id) { $0.level = level }
        case .setOpacity(let value): mutate(id) { $0.opacity = value }
        }
    }

    // MARK: Filters

    private func applyFilters(_ s: PIPSession) {
        guard effective.contains(.pipFilters) else {
            s.pipeline.configure(chain: [], lut: nil)
            s.receiver.setPipeline(nil)
            return
        }
        let chain = FilterSpec.resolveChain(s.configuration.filters)
        var lut: CubeLUT?
        if let lutID = s.configuration.lutID {
            if let cached = lutCache[lutID] { lut = cached } else { loadLUT(lutID) }
        }
        s.pipeline.configure(chain: chain, lut: lut)
        s.receiver.setPipeline(chain.isEmpty && lut == nil ? nil : s.pipeline)
    }

    /// Reads a stored LUT off the main thread, then applies it where it is used.
    private func loadLUT(_ id: StableID) {
        guard !lutLoading.contains(id), let lifetime else { return }
        lutLoading.insert(id)
        lifetime.spawn { [weak self] in
            let loaded = await Task.detached(priority: .utility) { () -> CubeLUT? in
                (try? PIPLUTStore.load(id))?.renderable
            }.value
            guard let self else { return }
            self.lutLoading.remove(id)
            guard let loaded else {
                _ = self.remember(L("A LUT couldn't be read; it was skipped."))
                return
            }
            self.lutCache[id] = loaded
            for s in self.sessions.values where s.configuration.lutID == id { self.applyFilters(s) }
        }
    }

    /// The page deleted a LUT.
    func forgetLUT(_ id: StableID) {
        lutCache[id] = nil
    }

    // MARK: Native mode while streaming (a trial; PLAN §10)

    private func switchToNativeMode(_ s: PIPSession) {
        guard let ctx = context, let targetID = s.targetDisplayID else { return }
        guard ctx.runtime.isEffective(.resolution) else {
            ctx.toasts.show(L("“Native mode while streaming” needs the Resolution feature."), lifetime: lifetime)
            return
        }
        guard let currentRef = ManagedModes.current(for: targetID)?.ref, let nativeRef = Self.nativeMode(targetID) else { return }
        guard currentRef != nativeRef else { return }
        s.lifetime.spawn { [weak self, weak s] in
            guard let transactions = self?.context?.transactions else { return }
            let outcome = await transactions.submit(TransactionRequest(
                label: L("Native mode while streaming"), risk: .trial, changes: [.mode(targetID, nativeRef)], finalScope: .forSession))
            guard outcome == .applied || outcome == .kept else { return }
            if let s, !s.lifetime.isEnded {
                s.restoreMode = (targetID, currentRef)
            } else {
                Self.submitRestore(transactions, displayID: targetID, mode: currentRef)
            }
        }
    }

    private func restoreNativeMode(_ s: PIPSession) {
        guard let restore = s.restoreMode, let transactions = context?.transactions else { return }
        s.restoreMode = nil
        Self.submitRestore(transactions, displayID: restore.displayID, mode: restore.mode)
    }

    private static func submitRestore(_ transactions: DisplayTransactionQueue, displayID: CGDirectDisplayID, mode: ModeRef) {
        Task { @MainActor in
            _ = await transactions.submit(TransactionRequest(
                label: L("Restore the mode after streaming"), risk: .low, changes: [.mode(displayID, mode)], finalScope: .forSession))
        }
    }

    /// The largest desktop-usable mode flagged native (IOKit kDisplayModeNativeFlag), from
    /// D's mode list (the same one the Resolution feature uses).
    private static func nativeMode(_ id: CGDirectDisplayID) -> ModeRef? {
        ManagedModes.modes(for: id).filter(\.isNative).max { a, b in
            (a.ref.pixelWidth * a.ref.pixelHeight, a.ref.refreshMilliHz) < (b.ref.pixelWidth * b.ref.pixelHeight, b.ref.refreshMilliHz)
        }?.ref
    }

    // MARK: Bulk actions

    func stopAll() {
        for id in order.reversed() { endSession(id, reason: nil) }
    }

    var hasSessions: Bool { !sessions.isEmpty }
    var allHidden: Bool { !sessions.isEmpty && sessions.values.allSatisfy(\.hidden) }
    var allPaused: Bool { !sessions.isEmpty && sessions.values.allSatisfy(\.userPaused) }

    func setAllHidden(_ hidden: Bool) {
        for s in sessions.values {
            s.hidden = hidden
            updateFlow(s)
        }
        publish()
    }

    func setAllPaused(_ paused: Bool) {
        for s in sessions.values {
            s.userPaused = paused
            updateFlow(s)
        }
        publish()
    }

    func isRunning(_ id: StableID) -> Bool { sessions[id] != nil }

    func toggle(_ id: StableID) {
        if sessions[id] != nil { endSession(id, reason: nil) } else { userStart(id) }
    }

    func setPaused(_ id: StableID, _ paused: Bool) {
        guard let s = sessions[id] else { return }
        s.userPaused = paused
        updateFlow(s)
        publish()
    }

    func setHidden(_ id: StableID, _ hidden: Bool) {
        guard let s = sessions[id] else { return }
        s.hidden = hidden
        updateFlow(s)
        publish()
    }

    func beginCrop(_ id: StableID) {
        sessions[id]?.window?.beginCrop()
    }

    /// Saves a new configuration for a source and starts it.
    func createAndStart(source: PIPSourceRef, kind: PIPKind, target: DisplayKey? = nil) {
        guard let ctx = context else { return }
        var c = PIPConfiguration(name: defaultName(source: source, kind: kind, target: target), kind: kind)
        c.target = target
        if kind == .fullScreen, let refusal = streamRefusal(source: source, configuration: c, excluding: nil) {
            ctx.toasts.show(refusal, lifetime: lifetime)
            return
        }
        var value = ctx.config.value
        guard PIPConfig.add(c, source: source, to: &value) else {
            ctx.toasts.show(L("That source already has the most saved configurations; delete one in Settings."), lifetime: lifetime)
            return
        }
        ctx.config.value = value
        userStart(c.id)
    }

    /// Starts a window PIP: an idle saved window configuration, or a new one.
    func pickWindow() {
        guard let ctx = context else { return }
        if let idle = ctx.config.value.pip.windowConfigurations.first(where: { sessions[$0.id] == nil && $0.kind == .window }) {
            userStart(idle.id)
        } else {
            createAndStart(source: .window, kind: .window)
        }
    }

    /// PIP of a display: stops its running PIPs, or starts its first one (creating it).
    func toggleDisplay(_ key: DisplayKey) {
        guard let ctx = context else { return }
        let running = order.filter { sessions[$0]?.source == .display(key) && sessions[$0]?.configuration.kind == .window }
        if !running.isEmpty {
            running.forEach { endSession($0, reason: nil) }
            return
        }
        if let first = ctx.config.value.perDisplay[key]?.pip.configurations.first(where: { $0.kind == .window }) {
            userStart(first.id)
        } else {
            createAndStart(source: .display(key), kind: .window)
        }
    }

    private func defaultName(source: PIPSourceRef, kind: PIPKind, target: DisplayKey?) -> String {
        guard let ctx = context else { return L("Picture in Picture") }
        let sourceName: String
        switch source {
        case .display(let key): sourceName = ctx.registry.info(for: key)?.name ?? L("Display")
        case .window: sourceName = L("Window")
        }
        if kind == .fullScreen, let target, let t = ctx.registry.info(for: target) {
            return PIPConfiguration.cleanName("\(sourceName) → \(t.name)")
        }
        return PIPConfiguration.cleanName(L("\(sourceName) PIP"))
    }

    // MARK: Hotkey

    private func updateHotkey() {
        guard let ctx = context, let lifetime else { return }
        let need = ctx.config.value.pip.stopHotkeyEnabled
            && sessions.values.contains { $0.configuration.kind == .fullScreen || $0.configuration.clickThrough }
        if need, hotkeyLifetime == nil, !hotkeyFailed {
            let life = lifetime.child()
            do {
                hotkeyToken = try ctx.hotkeys.register(Self.stopCombo, owner: L("Picture in Picture"), lifetime: life) { [weak self] in
                    self?.stopHotkeyPressed()
                }
                hotkeyLifetime = life
            } catch {
                life.end()
                hotkeyFailed = true
                EventLog.shared.record(.pip, "The PIP stop shortcut couldn't be registered")
            }
        } else if !need {
            if let token = hotkeyToken { ctx.hotkeys.unregister(token) }
            hotkeyToken = nil
            hotkeyLifetime?.end()
            hotkeyLifetime = nil
            if sessions.isEmpty { hotkeyFailed = false }
        }
    }

    private func stopHotkeyPressed() {
        for id in order {
            guard let s = sessions[id] else { continue }
            if s.configuration.kind == .fullScreen {
                endSession(id, reason: nil)
            } else if s.configuration.clickThrough {
                mutate(id) { $0.clickThrough = false }
            }
        }
        EventLog.shared.record(.pip, "Stop shortcut pressed")
    }

    // MARK: Registrations

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: .pipStopAll, title: L("Stop All Pictures in Picture"), feature: .pip, cliAllowed: true) {
            [weak self] _ in self?.stopAll()
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .pipHideAll, title: L("Hide or Show All Pictures in Picture"), feature: .pip, cliAllowed: true) {
            [weak self] _ in
            guard let self else { return }
            self.setAllHidden(!self.allHidden)
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .pipPauseAll, title: L("Pause or Resume All Pictures in Picture"), feature: .pip, cliAllowed: true) {
            [weak self] _ in
            guard let self else { return }
            self.setAllPaused(!self.allPaused)
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .pipToggleDisplay, title: L("Picture in Picture of This Display"), feature: .pip, cliAllowed: false) {
            [weak self] target in
            guard let self else { return }
            for display in self.displays(for: target) { self.toggleDisplay(display.key) }
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: .pipPickWindow, title: L("Picture in Picture of a Window…"), feature: .pip, cliAllowed: false) {
            [weak self] _ in self?.pickWindow()
        }, lifetime: lifetime)
    }

    /// One "start/stop" action per saved configuration (for shortcuts and menus).
    private func registerConfigActions() {
        guard let ctx = context, let lifetime else { return }
        let entries = PIPConfig.entries(in: ctx.config.value)
        let signature = entries.map { "\($0.configuration.id.rawValue)=\($0.configuration.name)" }.joined(separator: ";")
        guard signature != configActionSignature else { return }
        configActionSignature = signature
        configActionsLifetime?.end()
        let life = lifetime.child()
        configActionsLifetime = life
        for entry in entries {
            let id = entry.configuration.id
            ctx.actions.register(Action(id: .pipToggle(id), title: L("Start or Stop “\(entry.configuration.name)”"), feature: .pip,
                                        cliAllowed: false) { [weak self] _ in self?.toggle(id) }, lifetime: life)
        }
    }

    private func displays(for target: DisplayTarget) -> [DisplayInfo] {
        guard let ctx = context else { return [] }
        let all = ctx.registry.displays
        switch target {
        case .display(let key): return all.filter { $0.key == key }
        case .main: return all.filter(\.isMain)
        case .all: return all
        case .pointer:
            let p = NSEvent.mouseLocation
            guard let id = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) })?.displayID else { return [] }
            return all.filter { $0.desktopID == id }
        }
    }

    private func registerCommand(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("pip", policy: .low, offOnly: false, cliAllowed: true, summary: PIPCommand.usage,
                              lifetime: lifetime) { [weak self] request in
            guard let self else { return .failure(ControlExit.unavailable, L("Picture in Picture is off.")) }
            return self.handleCommand(request.arguments, json: request.json)
        }
    }

    /// `pip …` (PLAN §4.10(3)): saved configurations only; starting only while on
    /// console and unlocked. Stopping is always allowed. Displays are picked with
    /// `DisplaySelectorResolver`, so `--display 2` is the "2" Identify shows.
    private func handleCommand(_ arguments: [String], json: Bool = false) -> ControlResponse {
        guard let ctx = context else { return .failure(ControlExit.unavailable, L("Picture in Picture is off.")) }
        guard let command = PIPCommand.parse(arguments) else { return .failure(ControlExit.usage, "usage: " + PIPCommand.usage) }
        let entries = PIPConfig.entries(in: ctx.config.value)
        func lookup(_ query: String) -> (id: StableID?, error: ControlResponse) {
            switch PIPLookup.find(query, in: entries.map(\.configuration)) {
            case .found(let id): return (id, .ok())
            case .notFound: return (nil, .failure(ControlExit.notFound, L("No saved configuration matches “\(query)”.")))
            case .ambiguous(let n): return (nil, .failure(ControlExit.usage, L("\(n) configurations match “\(query)”; use the id.")))
            }
        }
        let locked = L("PIP starts from the command line only while the Mac is unlocked and on the console.")
        switch command {
        case .list:
            let numbers = Dictionary(DisplaySelectorResolver.ordered(ctx).enumerated().map { pair in (pair.element.key, pair.offset + 1) },
                                     uniquingKeysWith: { first, _ in first })
            if json {
                let rows: [[String: Any]] = entries.map { e in
                    let c = e.configuration
                    var row: [String: Any] = ["id": c.id.rawValue, "name": c.name, "kind": c.kind.rawValue,
                                              "state": sessions[c.id]?.publicState.rawValue ?? "stopped"]
                    switch e.source {
                    case .display(let key):
                        row["source"] = "display"
                        if let n = numbers[key] { row["display"] = n }
                    case .window: row["source"] = "window"
                    }
                    return row
                }
                return .ok(KitControl.jsonText(rows) ?? "[]")
            }
            let lines = entries.map { e -> String in
                let c = e.configuration
                let source: String
                switch e.source {
                case .display(let key): source = numbers[key].map { "display \($0)" } ?? "display (not connected)"
                case .window: source = "window"
                }
                let state = sessions[c.id]?.publicState.rawValue ?? "stopped"
                return "\(c.id.rawValue)\t\(c.name)\t\(c.kind.rawValue)\t\(source)\t\(state)"
            }
            return .ok(lines.joined(separator: "\n"))
        case .start(let query):
            guard sessionUsable() else { return .failure(ControlExit.refused, locked) }
            let found = lookup(query)
            guard let id = found.id else { return found.error }
            if let refusal = startChecked(id, origin: .cli) { return .failure(refusal.code, refusal.message) }
            return .ok()
        case .startDisplay(let selector):
            guard sessionUsable() else { return .failure(ControlExit.refused, locked) }
            let resolved = DisplaySelectorResolver.resolveForCLI(selector, ctx)
            guard let target = resolved.target else {
                return resolved.error ?? .failure(ControlExit.notFound, L("No display matches “\(selector)”."))
            }
            return startDisplays(displays(for: target), ctx)
        case .stop(let query):
            let found = lookup(query)
            guard let id = found.id else { return found.error }
            endSession(id, reason: nil)
            return .ok()
        case .stopDisplay(let selector):
            let resolved = DisplaySelectorResolver.resolveForCLI(selector, ctx)
            guard let target = resolved.target else {
                return resolved.error ?? .failure(ControlExit.notFound, L("No display matches “\(selector)”."))
            }
            if target == .all {
                stopAll()
                return .ok()
            }
            let keys = Set(displays(for: target).map(\.key))
            let matching = order.filter { id in
                guard let s = sessions[id] else { return false }
                if case .display(let key) = s.source, keys.contains(key) { return true }
                return s.configuration.kind == .fullScreen && s.configuration.target.map(keys.contains) == true
            }
            matching.forEach { endSession($0, reason: nil) }
            return .ok(matching.isEmpty ? L("Nothing was running on that display.") : "")
        case .stopAll:
            stopAll()
            return .ok()
        case .hideAll:
            setAllHidden(true)
            return .ok()
        case .showAll:
            setAllHidden(false)
            return .ok()
        case .pauseAll:
            setAllPaused(true)
            return .ok()
        case .resumeAll:
            setAllPaused(false)
            return .ok()
        }
    }

    /// `pip start --display`: each display's preferred saved configuration (never a new one).
    private func startDisplays(_ targets: [DisplayInfo], _ ctx: DisplaysContext) -> ControlResponse {
        var started = 0
        var refusals: [StartRefusal] = []
        var anySaved = false
        for display in targets where display.isOnline {
            let saved = ctx.config.value.perDisplay[display.key]?.pip.configurations ?? []
            guard let pick = PIPLookup.preferredForDisplay(saved) else { continue }
            anySaved = true
            if let refusal = startChecked(pick.id, origin: .cli) { refusals.append(refusal) } else { started += 1 }
        }
        guard anySaved else {
            return .failure(ControlExit.notFound, L("No saved Picture in Picture uses that display as its source. Create one in Settings first."))
        }
        if started == 0, let first = refusals.first { return .failure(first.code, first.message) }
        return .ok(refusals.map(\.message).joined(separator: "\n"))
    }

    // MARK: System events

    /// Lock, sleep and resign arrive as SessionParticipant calls (SessionGate). The gate
    /// stays open while only the displays sleep, so display sleep comes from its raw events.
    private func observeSystem(_ ctx: DisplaysContext, lifetime: Lifetime) {
        systemLifetime?.end()
        let life = lifetime.child()
        systemLifetime = life
        ctx.sessionGate.observeEvents(lifetime: life) { [weak self] event in
            guard let self, self.context != nil else { return }
            switch event {
            case .willSleep, .screensDidSleep:
                self.displaysAsleep = true
                self.suspendAll()
            case .didWake, .screensDidWake:
                self.displaysAsleep = false
                // Before the gate recomputes this is a no-op; sessionDidResume follows.
                self.resumeIfPossible()
            case .locked, .unlocked, .resignedActive, .becameActive:
                break
            }
        }
        ctx.registry.changes
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in MainActor.assumeIsolated { self?.displaysChanged(displays) } }
            .store(in: &sinks)
    }

    /// Auto-stop when a source or target goes away or a stream becomes unsafe; offer
    /// auto-start for sources that appeared.
    private func displaysChanged(_ displays: [DisplayInfo]) {
        guard let ctx = context else { return }
        let keys = Set(displays.map(\.key))
        let appeared = keys.subtracting(knownDisplays)
        knownDisplays = keys
        for id in order {
            guard let s = sessions[id] else { continue }
            if case .display(let key) = s.source {
                guard let info = ctx.registry.info(for: key) else {
                    endSession(id, reason: L("“\(s.configuration.name)” stopped: its source display disconnected."))
                    continue
                }
                if info.desktopID != s.sourceDisplayID {
                    if s.suspended {
                        // Locked or asleep: nothing starts now; the resume captures the new id.
                        s.sourceDisplayID = info.desktopID
                        readSourceGeometry(s, displayID: info.desktopID)
                        continue
                    }
                    // The display id changed (reconnect, Smart HiDPI): capture it afresh.
                    restart(id)
                    continue
                }
            }
            if s.configuration.kind == .fullScreen {
                if let refusal = streamRefusal(source: s.source, configuration: s.configuration, excluding: id) {
                    endSession(id, reason: refusal)
                    continue
                }
                s.targetDisplayID = s.configuration.target.flatMap { ctx.registry.info(for: $0)?.desktopID }
            }
            applyWindow(s)
        }
        if !appeared.isEmpty { offerAutoStart(only: appeared) }
        publish()
    }

    /// "Start when the source connects": always a prompt, never unattended (R5.2);
    /// never in Safe Mode or while panic-latched.
    private func offerAutoStart(only keys: Set<DisplayKey>?) {
        guard let ctx = context, let lifetime, !ctx.safeMode.isActive, !ctx.panic.isLatched, Self.isSessionOpen() else { return }
        for entry in PIPConfig.entries(in: ctx.config.value) where entry.configuration.autoStart && sessions[entry.configuration.id] == nil {
            guard case .display(let key) = entry.source, ctx.registry.info(for: key) != nil else { continue }
            if let keys, !keys.contains(key) { continue }
            let id = entry.configuration.id
            ctx.toasts.show(L("Start “\(entry.configuration.name)”?"),
                            action: ToastAction(title: L("Start")) { [weak self] in self?.userStart(id) }, lifetime: lifetime)
        }
    }

    private func publish() {
        let infos = order.compactMap { id -> PIPSessionInfo? in
            guard let s = sessions[id] else { return nil }
            return PIPSessionInfo(id: id, name: s.configuration.name, kind: s.configuration.kind, source: s.source, state: s.publicState)
        }
        context?.capture.publish(infos)
        context?.requestMenuRebuild()
    }

    // MARK: Diagnostics (counts and states only: no titles, app names or pixels)

    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [("State", "Stopped")] }
        let permission: String
        switch ctx.permissions.state(.screenRecording) {
        case .granted: permission = "granted"
        case .denied: permission = "denied"
        case .unknown: permission = "unknown"
        }
        let windows = sessions.values.filter { $0.configuration.kind == .window }.count
        var delivered: UInt64 = 0, dropped: UInt64 = 0, incomplete: UInt64 = 0, filtered: UInt64 = 0, failures: UInt64 = 0
        for s in sessions.values {
            let c = s.mailbox.counters
            delivered &+= c.delivered
            dropped &+= c.dropped
            incomplete &+= s.receiver.incompleteFrames
            let p = s.pipeline.stats
            filtered &+= p.rendered
            failures &+= p.failures
        }
        let entries = PIPConfig.entries(in: ctx.config.value)
        return [
            ("Screen Recording", permission),
            ("Filters feature", effective.contains(.pipFilters) ? "on" : "off"),
            ("Sessions", "\(sessions.count) (\(windows) windows, \(sessions.count - windows) full-screen)"),
            ("Active capture streams", "\(ctx.capture.activeStreamCount)"),
            ("Saved configurations", "\(entries.count) (\(entries.filter { $0.source == .window }.count) window sources)"),
            ("Auto-start configurations", "\(entries.filter { $0.configuration.autoStart }.count)"),
            ("Suspended for session", sessionPaused ? "yes" : "no"),
            ("Safe Mode", ctx.safeMode.isActive ? "on (no auto-start)" : "off"),
            ("Protected app prefixes", "\(ctx.config.value.pip.protectedBundlePrefixes.count)"),
            ("Excluded apps / private windows (last filter)", "\(ctx.capture.excludedAppCount) / \(ctx.capture.privateWindowCount)"),
            ("Privacy refreshes", "\(ctx.capture.privacyRefreshes)"),
            ("Frames shown / dropped / incomplete", "\(delivered) / \(dropped) / \(incomplete)"),
            ("Filtered frames / filter failures", "\(filtered) / \(failures)"),
            ("Imported LUTs", "\(ctx.config.value.pip.luts.count) (\(lutCache.count) loaded)"),
            ("Stop shortcut", hotkeyLifetime != nil ? "registered" : (hotkeyFailed ? "unavailable" : "not needed")),
            ("Starts this run", "\(startsThisRun)"),
            ("Last error", lastError == nil ? "none" : "yes"),
        ]
    }
}
