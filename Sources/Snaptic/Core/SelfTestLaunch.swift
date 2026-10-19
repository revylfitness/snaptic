import AppKit
import SnapticKit

/// `--selftest-launch <token-file>` (owner: T-update; PLAN 0.3.1 E3, HW-37 in CI), after SelfTest's token gate: builds
/// the host the way the app does (ModuleHost: stores, migrations, modules) and checks the updater gate, without
/// starting a module, Sparkle's updater or a run loop, and without touching a TCC-guarded API (R5.5). With the gate
/// closed it also runs `startUpdater()`, which then can't reach Sparkle.
///
/// ModuleHost's init writes the user's settings (migrations, the first-run modules value), so this takes the instance
/// lock first (never beside a running Snaptic) and puts Snaptic's whole defaults domain back afterwards.
///
/// `SNAPTIC_SELFTEST_EXPECT_SPARKLE`: `absent` (CI's ad hoc app: no Sparkle) or `loaded` (the signed release: the gate
/// is open) makes the gate's answer a check; unset only reports it (the debug build may find Sparkle next to it, and its
/// gate then stays closed because it isn't an app bundle).
enum SelfTestLaunch {
    static let expectVariable = "SNAPTIC_SELFTEST_EXPECT_SPARKLE"

    /// The problems found (empty: passed), and the lines to print.
    @MainActor static func run() -> (problems: [String], report: [String]) {
        var problems: [String] = []
        var report: [String] = []
        let expectation = ProcessInfo.processInfo.environment[expectVariable]
        if let expectation, expectation != "absent", expectation != "loaded" {
            return (["\(expectVariable) must be absent or loaded"], [])
        }

        var lock = InstanceLock()
        switch lock.acquire() {
        case .acquired: break
        case .busy: return (["Snaptic is running; quit it first (this test writes its settings)"], [])
        case .failed(let reason): return (["instance lock: " + reason], [])
        }
        defer { lock.release() }

        let domainName = ConfigStore<ModulesConfig>.persistentDomainName
        let saved = UserDefaults.standard.persistentDomain(forName: domainName)
        defer {
            // Put back exactly what was there (or nothing).
            if let saved {
                UserDefaults.standard.setPersistentDomain(saved, forName: domainName)
            } else {
                UserDefaults.standard.removePersistentDomain(forName: domainName)
            }
        }

        _ = NSApplication.shared
        let relauncher = Relauncher()
        let host = ModuleHost(safeMode: .off, toasts: ToastPresenter(),
                              permissions: PermissionFlow(relauncher: relauncher, readsGrants: false),
                              spawner: HelperSpawner(), relauncher: relauncher)
        report.append("selftest-launch: ModuleHost built, \(host.modules.count) modules, "
                      + "\(host.runningModules.count) running")
        if host.modules.count != ModuleID.allCases.count { problems.append("ModuleHost has \(host.modules.count) modules") }
        if !host.runningModules.isEmpty { problems.append("a module started during the self-test") }
        if !host.ledgerStore.value.has(.v031Welcome) { problems.append("the 0.3.1 marker wasn't recorded") }

        // The gate `UpdaterController.make()` uses (r1 C6, C8). When it is closed, `startUpdater()` runs for real (no
        // Sparkle, no network) and must leave no updater and no welcome card. When it is open (the signed release),
        // the updater isn't started here: that would schedule checks.
        let loaded = UpdaterController.isSparkleLoaded
        let gate = UpdaterController.gate
        report.append("selftest-launch: Sparkle " + (loaded ? "loaded" : "absent") + ", updater gate \(gate)")
        if gate != .ready {
            host.startUpdater()
            if host.updater != nil { problems.append("startUpdater() made an updater although the gate is \(gate)") }
            if host.showsV031Welcome { problems.append("the 0.3.1 card shows in a build that can't update itself") }
        }
        switch expectation {
        case "absent"?:
            if gate != .noSparkle { problems.append("expected no Sparkle, but the updater gate is \(gate)") }
        case "loaded"?:
            // The signed app: Sparkle loaded, an .app bundle with a valid SUPublicEDKey.
            if gate != .ready { problems.append("expected the updater gate open, found \(gate)") }
        default:
            break
        }
        return (problems, report)
    }
}
