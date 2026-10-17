import Foundation
import SnapticKit

/// Persists launch-stability bookkeeping (Kit `KitLaunchStability`) in the persistent
/// domain under `SnapticLaunchHistoryV1`.
@MainActor enum LaunchStability {
    static let key = "SnapticLaunchHistoryV1"
    private static var survivalTimer: Timer?

    /// Startup step 5: true when the previous two launches were unstable. Also records this
    /// launch and marks it stable after 60 s.
    static func evaluate() -> Bool {
        let stored = ConfigStore<ModulesConfig>.persistentData(forKey: key)
        let result = KitLaunchStability.beginLaunch(KitLaunchStability.decode(stored), now: Date().timeIntervalSince1970)
        save(result.history)
        survivalTimer?.invalidate()
        let timer = Timer(timeInterval: KitLaunchStability.survivalSeconds, repeats: false) { _ in
            MainActor.assumeIsolated { LaunchStability.markSurvived() }
        }
        RunLoop.main.add(timer, forMode: .common)
        survivalTimer = timer
        if result.unstable { EventLog.shared.record(.safety, "Two unstable launches in a row: Safe Mode") }
        return result.unstable
    }

    static func markSurvived() {
        let stored = ConfigStore<ModulesConfig>.persistentData(forKey: key)
        save(KitLaunchStability.markSurvived(KitLaunchStability.decode(stored)))
    }

    /// Quit path (also before a relaunch).
    static func markCleanQuit() {
        survivalTimer?.invalidate()
        survivalTimer = nil
        let stored = ConfigStore<ModulesConfig>.persistentData(forKey: key)
        save(KitLaunchStability.markCleanQuit(KitLaunchStability.decode(stored)))
    }

    private static func save(_ history: LaunchHistory) {
        guard let data = KitLaunchStability.encode(history) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
