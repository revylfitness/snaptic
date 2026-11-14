import AppKit
import SnapticKit

/// What can pause Dock Previews while it runs (PLAN 0.5 §4.15, §4.16, §4.21; A6b): a known Dock preview tool, VoiceOver
/// and a `dock pause`. Kit `DockPauseRules` decides; this only watches, and `onChange` runs after any of them changes.
/// - Known tools are read from `NSWorkspace.runningApplications` at `start()` and on each app launch and quit, by the
///   exact bundle ids in `KnownDockTools`; never polled (§4.15).
/// - VoiceOver is `NSWorkspace.isVoiceOverEnabled`, observed with KVO.
/// - A command pause lives in memory only, so a relaunch resumes (§4.21). One one-shot timer runs to its end; it
///   counts in `DockLive.timers`.
/// - Nothing here is logged: the module logs pause changes as enums (§4.22).
@MainActor final class DockPauseSources {
    /// Bundle ids of the running `KnownDockTools` apps, in `runningApplications` order.
    private(set) var runningToolIDs: [String] = []
    private(set) var voiceOverOn = false
    /// The held `dock pause`, nil while none is.
    private(set) var commandPause: DockCommandPause?
    var onChange: (@MainActor () -> Void)?

    private var tokens: [NSObjectProtocol] = []
    private var voiceOverObservation: NSKeyValueObservation?
    private var endTimer: Timer?

    var isStarted: Bool { !tokens.isEmpty }

    /// Reads all three now, then on each change. Idempotent; `onChange` doesn't run for the first read.
    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let quit = note.name == NSWorkspace.didTerminateApplicationNotification
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { self?.scanTools(quitPID: quit ? pid : nil) }
            })
        }
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: []) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.readVoiceOver() } }
        }
        runningToolIDs = Self.toolIDs(quitPID: nil)
        voiceOverOn = NSWorkspace.shared.isVoiceOverEnabled
    }

    /// Removes every observer and the timer, and drops a held command pause (it's in memory only).
    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = []
        voiceOverObservation?.invalidate()
        voiceOverObservation = nil
        cancelEndTimer()
        commandPause = nil
        runningToolIDs = []
        voiceOverOn = false
    }

    // MARK: Command pause (§4.21)

    /// Holds a command pause for `seconds`, never shortening one already held (G2-12). Returns the end, Unix seconds.
    @discardableResult
    func pause(seconds: Int) -> Double {
        let now = Date().timeIntervalSince1970
        let end = DockCommandGrammar.pauseEnd(current: commandPause?.untilUnix, now: now, seconds: seconds)
        guard end != commandPause?.untilUnix else { return end }
        commandPause = DockCommandPause(untilUnix: end, clock: Self.clock(end))
        armEndTimer()
        onChange?()
        return end
    }

    /// Clears a held command pause. False when none was held.
    @discardableResult
    func resume() -> Bool {
        guard commandPause != nil else { return false }
        commandPause = nil
        cancelEndTimer()
        onChange?()
        return true
    }

    private func armEndTimer() {
        cancelEndTimer()
        guard let end = commandPause?.untilUnix else { return }
        let timer = Timer(fire: Date(timeIntervalSince1970: end), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endTimerFired() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
        DockPreviewsModule.liveCount(.timers, up: true)
    }

    private func cancelEndTimer() {
        guard let endTimer else { return }
        endTimer.invalidate()
        self.endTimer = nil
        DockPreviewsModule.liveCount(.timers, up: false)
    }

    /// The end came. The wall clock decides, so a timer that fired early is armed again.
    private func endTimerFired() {
        cancelEndTimer()
        guard let end = commandPause?.untilUnix else { return }
        if Date().timeIntervalSince1970 >= end {
            commandPause = nil
            onChange?()
        } else {
            armEndTimer()
        }
    }

    /// "3:45 PM": the end as the page and the menu show it.
    private static func clock(_ unix: Double) -> String {
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: unix), dateStyle: .none, timeStyle: .short)
    }

    // MARK: Known tools and VoiceOver

    private func scanTools(quitPID: pid_t?) {
        guard isStarted else { return }
        let ids = Self.toolIDs(quitPID: quitPID)
        guard ids != runningToolIDs else { return }
        runningToolIDs = ids
        onChange?()
    }

    private func readVoiceOver() {
        guard isStarted else { return }
        let on = NSWorkspace.shared.isVoiceOverEnabled
        guard on != voiceOverOn else { return }
        voiceOverOn = on
        onChange?()
    }

    /// The running apps' bundle ids that `KnownDockTools` lists. An app that just quit can still be listed, so its
    /// pid is left out.
    private static func toolIDs(quitPID: pid_t?) -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, app.processIdentifier != quitPID,
                  let id = app.bundleIdentifier, KnownDockTools.match(bundleID: id) != nil else { return nil }
            return id
        }
    }
}
