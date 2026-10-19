import AppKit
import SnapticKit

/// Restarts Snaptic (PLAN §3.2, R3C §5.5): opens a new instance with
/// `--relaunch-from <pid>`, then quits; the new instance waits for the instance lock.
/// 0.3.1 E4: while a downloaded update waits for quit, the relaunch goes through Sparkle instead (it installs, then
/// opens the new version), so a second instance never starts while Sparkle swaps the bundle. When it can't (a Safe
/// Mode relaunch, which an update never replaces, or Sparkle's block is gone), nothing relaunches and a toast says to
/// quit first (`UpdatePolicy.relaunchRoute`).
@MainActor final class Relauncher {
    /// How long Sparkle gets to quit Snaptic after the hand-off before Relauncher takes the relaunch back (r1 S9:
    /// Sparkle's block is a no-op once its driver is gone).
    static let handOffTimeout: TimeInterval = 10

    private var inFlight = false
    private var handOffTimer: Timer?
    /// Runs right before this instance quits for a relaunch.
    var willRelaunch: (@MainActor () -> Void)?
    /// Set by ModuleHost once the updater runs (nil in builds without Sparkle).
    weak var updater: (any UpdaterControlling)?

    init() {}

    func relaunch(reason: String) {
        relaunch(reason: reason, safeMode: false)
    }

    func relaunch(reason: String, safeMode: Bool) {
        guard !inFlight else { return }
        switch updater?.prepareRelaunch(safeMode: safeMode) ?? .normal {
        case .normal:
            break
        case .quitFirst:
            // The updater showed why; nothing is in flight.
            EventLog.shared.record(.modules, "Relaunch held for the waiting update: \(reason)")
            return
        case .throughUpdate:
            // Sparkle quits Snaptic, installs, and opens the new version. If it hasn't quit Snaptic after a while,
            // its block did nothing: take the relaunch back, so neither this one nor any later one is lost.
            inFlight = true
            EventLog.shared.record(.modules, "Relaunching through the update: \(reason)")
            willRelaunch?()
            armHandOffFallback(reason: reason, safeMode: safeMode)
            return
        }
        inFlight = true
        EventLog.shared.record(.modules, "Relaunching: \(reason)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        var arguments = [KitArgs.relaunchFlag, String(getpid())]
        if safeMode { arguments.append(KitArgs.safeModeFlag) }
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if error == nil {
                        self.willRelaunch?()
                        NSApp.terminate(nil)
                        // Only reached when the quit didn't happen.
                        self.inFlight = false
                    } else {
                        self.inFlight = false
                        EventLog.shared.record(.modules, "Relaunch failed")
                        let alert = NSAlert()
                        alert.messageText = L("Snaptic couldn’t restart itself")
                        alert.informativeText = L("Quit Snaptic and open it again.")
                        NSApp.activate()
                        alert.runModal()
                    }
                }
            }
        }
    }

    private func armHandOffFallback(reason: String, safeMode: Bool) {
        handOffTimer?.invalidate()
        let timer = Timer(timeInterval: Self.handOffTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handOffTimer = nil
                self.inFlight = false
                EventLog.shared.record(.modules, "Sparkle didn’t take over the relaunch")
                // The block is spent, so this relaunches as usual or, while the installer still waits, says to quit.
                self.relaunch(reason: reason, safeMode: safeMode)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        handOffTimer = timer
    }
}
