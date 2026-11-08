import AppKit
import ApplicationServices
import CoreGraphics
import SnapticKit

/// What Hidden Icons watches while it runs (lead; PLAN 0.4 §4.5, §4.6, §4.10, §4.11; A3). Each watcher only samples
/// AppKit and Core Graphics, decides with Kit (`IconsMonitorRules`, `IconsPolicy`) and calls back; the module (A5)
/// wires the callbacks into `IconsEngineCore` and its policy. Every timer is an `IconsScheduler` timer, so it runs in
/// `.common` modes (while a menu tracks too).
///
/// - Hover: a global `.mouseMoved` monitor, only while `setHover(true)`; 0.5 s dwell in a band.
/// - Workspace: app launches start the new-icon re-reads (+2/+10/+30 s) while `setWatchesLaunches(true)`;
///   MenuBarAgent's launch and quit go to `onRecovery`.
/// - Screen: `didChangeScreenParameters` goes to `onScreenParameters` (the core coalesces), refreshes the bands and
///   the exam state; a pending Displays trial is reported and polled until it ends.
/// - Session: resign/become active, wake, lock/unlock go to `onRecovery(.session)`.
/// - Exam: `currentSystemPresentationOptions`, on screen changes, before activation (`examActive()`) and every 1 s
///   while `setExamPolling(true)`.
/// - Auto-collapse: `rearmFacts` samples the pointer, the window list and VoiceOver when the timer fires.
@MainActor final class IconsMonitors {
    // MARK: Callbacks (A5)

    var onHoverDwell: (() -> Void)?
    var onNewAppReread: (() -> Void)?
    var onScreenParameters: (() -> Void)?
    var onDisplayTrialPending: ((Bool) -> Void)?
    var onRecovery: ((IconsRecoveryEvent) -> Void)?
    var onExamChange: ((Bool) -> Void)?
    /// Pulled from Displays (`transactions.hasPendingTrial || isBusy`); false while Displays doesn't run.
    var displayTrialPending: (() -> Bool)?

    private let scheduler: IconsScheduler
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let voiceOverQueue = DispatchQueue(label: "com.snaptic.icons.voiceover", qos: .userInitiated)

    private var workspaceTokens: [NSObjectProtocol] = []
    private var centerTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private(set) var isStarted = false

    /// Cached for the hover handler, refreshed on every screen change.
    private var bands: [IconsRect] = []

    init(scheduler: IconsScheduler) {
        self.scheduler = scheduler
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshBands()
        let ws = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                              queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.launched(app, didLaunch: true) }
        })
        workspaceTokens.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                              queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.launched(app, didLaunch: false) }
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.didWakeNotification] {
            workspaceTokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onRecovery?(.session) }
            })
        }
        let dc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributedTokens.append(dc.addObserver(forName: Notification.Name(name), object: nil,
                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onRecovery?(.session) }
            })
        }
        centerTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        })
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        let ws = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(ws.removeObserver)
        distributedTokens.forEach(DistributedNotificationCenter.default().removeObserver)
        centerTokens.forEach(NotificationCenter.default.removeObserver)
        workspaceTokens = []
        distributedTokens = []
        centerTokens = []
        setHover(false)
        setWatchesLaunches(false)
        setExamPolling(false)
        trialPoll?.cancel()
        trialPoll = nil
        trialReported = false
    }

    // MARK: Workspace (§4.5, §4.11)

    private var watchesLaunches = false
    private var rereads: [IconsCancellable] = []

    /// `IconsNewIcons.watchesLaunches(engine:assertionActive:collapsed:)`. Turning it off drops pending re-reads.
    func setWatchesLaunches(_ on: Bool) {
        watchesLaunches = on
        if !on { cancelRereads() }
    }

    private func launched(_ app: NSRunningApplication?, didLaunch: Bool) {
        guard isStarted, let app else { return }
        let path = app.bundleURL?.standardizedFileURL.path
        if let event = IconsAgentWatch.event(launched: didLaunch, bundleID: app.bundleIdentifier, bundlePath: path) {
            EventLog.shared.record(.modules, didLaunch ? "Icons: MenuBarAgent launched" : "Icons: MenuBarAgent quit")
            onRecovery?(event)
            return
        }
        guard didLaunch, watchesLaunches,
              IconsLaunchWatch.counts(bundleID: app.bundleIdentifier, pid: app.processIdentifier, ownPID: ownPID,
                                      bundlePath: path) else { return }
        // Another launch restarts the series: the newest app gets its full +2/+10/+30 s.
        cancelRereads()
        rereads = IconsNewIcons.rereadDelays.map { delay in
            scheduler.after(delay) { [weak self] in
                guard let self, self.watchesLaunches else { return }
                self.onNewAppReread?()
            }
        }
    }

    private func cancelRereads() {
        rereads.forEach { $0.cancel() }
        rereads = []
    }

    // MARK: Screen (§4.2.3, X-18)

    private var trialPoll: IconsCancellable?
    private var trialReported = false

    private func screenParametersChanged() {
        guard isStarted else { return }
        refreshBands()
        reportTrial()
        onScreenParameters?()
        checkExam()
    }

    /// Tells the core about a pending Displays trial before it coalesces, then polls each second until the trial
    /// ends (Keep posts no screen change), so a deferred re-apply runs once.
    private func reportTrial() {
        let pending = displayTrialPending?() ?? false
        guard pending != trialReported else { return }
        trialReported = pending
        onDisplayTrialPending?(pending)
        trialPoll?.cancel()
        trialPoll = nil
        if pending { pollTrial() }
    }

    private func pollTrial() {
        trialPoll = scheduler.after(1) { [weak self] in
            guard let self, self.isStarted else { return }
            self.trialPoll = nil
            self.reportTrial()
            if self.trialReported, self.trialPoll == nil { self.pollTrial() }
        }
    }

    /// Bands for every screen, AppKit global space.
    private func refreshBands() {
        let thickness = Double(NSStatusBar.system.thickness)
        bands = NSScreen.screens.map { screen in
            IconsBand.band(LengthBackend.screen(screen), thickness: thickness,
                           visibleTopInset: Double(screen.frame.maxY - screen.visibleFrame.maxY))
        }.filter { !$0.isDegenerate }
    }

    // MARK: Hover (§4.6)

    private var globalMove: Any?
    private var localMove: Any?
    private var dwell = IconsHoverDwell()
    private var dwellCheck: IconsCancellable?

    /// `IconsHoverDwell.active(hover:collapsed:killSwitches:)`. The monitor exists only while this is true.
    func setHover(_ on: Bool) {
        if on, isStarted, globalMove == nil {
            if bands.isEmpty { refreshBands() }
            globalMove = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMoved() }
            }
            // Snaptic's own status items get their moves locally.
            localMove = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { self?.mouseMoved() }
                return event
            }
        } else if !on {
            if let globalMove { NSEvent.removeMonitor(globalMove) }
            if let localMove { NSEvent.removeMonitor(localMove) }
            globalMove = nil
            localMove = nil
            dwell.reset()
            dwellCheck?.cancel()
            dwellCheck = nil
        }
    }

    var hoverActive: Bool { globalMove != nil }

    /// Returns at once, with no allocation, while the pointer is outside every band and no dwell is running.
    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        let inBand = IconsBand.contains(bands, x: Double(p.x), y: Double(p.y))
        guard inBand || dwell.enteredAt != nil else { return }
        sampleDwell(inBand: inBand)
    }

    private func sampleDwell(inBand: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if dwell.sample(inBand: inBand, now: now) {
            dwellCheck?.cancel()
            dwellCheck = nil
            onHoverDwell?()
            return
        }
        guard inBand else {
            dwellCheck?.cancel()
            dwellCheck = nil
            return
        }
        // The pointer may stop moving: look again when the dwell is due.
        if dwellCheck == nil, let due = dwell.due {
            dwellCheck = scheduler.after(max(0, due - now)) { [weak self] in
                guard let self, self.hoverActive else { return }
                self.dwellCheck = nil
                let p = NSEvent.mouseLocation
                self.sampleDwell(inBand: IconsBand.contains(self.bands, x: Double(p.x), y: Double(p.y)))
            }
        }
    }

    // MARK: Exam guard (§4.11, R2-4)

    private var examPoll: IconsCancellable?
    private(set) var examReported = false

    /// Another process set an exam's presentation options. Asked before every Native activation.
    func examActive() -> Bool {
        let system = IconsPresentationFlag.flags(NSApp.currentSystemPresentationOptions.rawValue)
        let own = IconsPresentationFlag.flags(NSApp.presentationOptions.rawValue)
        return IconsExamGuard.active(system: system, own: own)
    }

    /// `IconsExamGuard.polls(engine:assertionActive:)`.
    func setExamPolling(_ on: Bool) {
        if on, isStarted, examPoll == nil {
            scheduleExamPoll()
        } else if !on {
            examPoll?.cancel()
            examPoll = nil
        }
    }

    private func scheduleExamPoll() {
        examPoll = scheduler.after(IconsExamGuard.pollInterval) { [weak self] in
            guard let self, self.isStarted, self.examPoll != nil else { return }
            self.checkExam()
            self.scheduleExamPoll()
        }
    }

    private func checkExam() {
        let active = examActive()
        guard active != examReported else { return }
        examReported = active
        EventLog.shared.record(.modules, active ? "Icons: exam session began" : "Icons: exam session ended")
        onExamChange?(active)
    }

    // MARK: Auto-collapse facts (§4.6, Y-11, X-13)

    /// What holds the auto-collapse timer, sampled now. The window list is bounds only (no Screen Recording). The
    /// VoiceOver cursor is read off main, only while VoiceOver runs; the rest is main. Answers on main.
    func rearmFacts(snapticWindowVisible: Bool, ownMenuOpen: Bool, lastHiddenListPress: Double?,
                    extraPIDs: Set<Int32>, completion: @escaping (IconsRearmFacts) -> Void) {
        var facts = IconsRearmFacts()
        facts.snapticWindowVisible = snapticWindowVisible
        facts.ownMenuOpen = ownMenuOpen
        facts.lastHiddenListPress = lastHiddenListPress
        let screens = NSScreen.screens
        let thickness = Double(NSStatusBar.system.thickness)
        let windows = Self.windowList(primaryHeight: LengthBackend.primaryHeight)
        let bands = screens.map { s in
            IconsBand.band(LengthBackend.screen(s), thickness: thickness,
                           visibleTopInset: Double(s.frame.maxY - s.visibleFrame.maxY))
        }.filter { !$0.isDegenerate }
        let p = NSEvent.mouseLocation
        facts.pointerInBand = IconsBand.contains(bands, x: Double(p.x), y: Double(p.y))
        if facts.pointerInBand, let screen = screens.first(where: { NSMouseInRect(p, $0.frame, false) }) {
            let f = screen.frame
            let systemFull = NSApp.currentSystemPresentationOptions.rawValue & IconsPresentationFlag.fullScreenBit != 0
            facts.fullScreen = IconsWindowGuard.fullScreen(
                windows, screen: IconsRect(x: f.minX, y: f.minY, width: f.width, height: f.height),
                frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, systemFullScreen: systemFull)
        }
        facts.menuOpen = IconsWindowGuard.menuOpen(windows, bands: bands, ownPID: ownPID)
        facts.popoverNearBand = IconsWindowGuard.popoverNearBand(windows, bands: bands, extraPIDs: extraPIDs,
                                                                ownPID: ownPID)
        guard NSWorkspace.shared.isVoiceOverEnabled, AXIsProcessTrusted() else {
            completion(facts)
            return
        }
        // At most 0.5 s: an app that doesn't answer leaves the cursor "not on an extra".
        let answer = VoiceOverAnswer(facts: facts, completion: completion)
        answer.fallback = scheduler.after(Self.voiceOverWait) { answer.finish(false) }
        voiceOverQueue.async {
            let onExtra = Self.voiceOverOnExtra()
            DispatchQueue.main.async { MainActor.assumeIsolated { answer.finish(onExtra) } }
        }
    }

    static let voiceOverWait = 0.5

    /// One `rearmFacts` answer, given once.
    @MainActor private final class VoiceOverAnswer {
        var facts: IconsRearmFacts
        let completion: (IconsRearmFacts) -> Void
        var fallback: IconsCancellable?
        private var done = false

        init(facts: IconsRearmFacts, completion: @escaping (IconsRearmFacts) -> Void) {
            self.facts = facts
            self.completion = completion
        }

        func finish(_ onExtra: Bool) {
            guard !done else { return }
            done = true
            fallback?.cancel()
            facts.voiceOverOnExtra = onExtra
            completion(facts)
        }
    }

    /// Snaptic's own windows that hold the timer: anything titled (Settings, onboarding, confirm and save panels,
    /// Sparkle, the custom session and PIP editors). The status items, the PIP picture itself, the OSD and toasts
    /// are untitled and don't count.
    static func snapticWindowVisible() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized && window.styleMask.contains(.titled)
        }
    }

    /// On-screen windows other than the desktop's, AppKit global space.
    private static func windowList(primaryHeight: Double?) -> [IconsWindowInfo] {
        guard let primaryHeight,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  let frame = IconsAXGeometry.appKitRect(x: Double(bounds.minX), y: Double(bounds.minY),
                                                         width: Double(bounds.width), height: Double(bounds.height),
                                                         primaryHeight: primaryHeight)
            else { return nil }
            return IconsWindowInfo(layer: layer, frame: frame, pid: pid,
                                   owner: info[kCGWindowOwnerName as String] as? String,
                                   alpha: (info[kCGWindowAlpha as String] as? Double) ?? 1)
        }
    }

    /// VoiceOver moves the system's focused element with its cursor on the menu bar. The cursor is on an extra when
    /// one of the focused element's four nearest ancestors is its app's extras bar (the extra may be an `AXGroup`, as
    /// MenuBarAgent's are, with the cursor on its child). Each call on an app's element is limited to 0.15 s; the
    /// system-wide element's timeout is never set (that would set the whole app's).
    nonisolated private static func voiceOverOnExtra() -> Bool {
        let system = AXUIElementCreateSystemWide()
        guard var element = element(system, kAXFocusedUIElementAttribute) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Float(IconsReadBudget.perCall))
        guard let bar = Self.element(app, kAXExtrasMenuBarAttribute) else { return false }
        for _ in 0..<4 {
            AXUIElementSetMessagingTimeout(element, Float(IconsReadBudget.perCall))
            guard let parent = Self.element(element, kAXParentAttribute) else { return false }
            if CFEqual(parent, bar) { return true }
            element = parent
        }
        return false
    }

    nonisolated private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
