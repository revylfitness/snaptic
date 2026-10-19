import AppKit
import SnapticKit

/// Restarts Snaptic (PLAN §3.2, R3C §5.5): opens a new instance with
/// `--relaunch-from <pid>`, then quits; the new instance waits for the instance lock.
/// 0.3.1 E4: while a downloaded update waits for quit, the relaunch goes through Sparkle instead (it installs, then
/// opens the new version), so a second instance never starts while Sparkle swaps the bundle. Safe Mode relaunches
/// never do.
@MainActor final class Relauncher {
    private var inFlight = false
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
        inFlight = true
        EventLog.shared.record(.modules, "Relaunching: \(reason)")
        if let updater, updater.hasPendingQuitInstall, updater.relaunchIntoUpdate(safeMode: safeMode) {
            // Sparkle quits Snaptic, installs, and opens the new version.
            willRelaunch?()
            return
        }
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
}
