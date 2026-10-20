import AppKit
import SnapticKit

/// `--selftest-launch <token-file>` (owner: T-update; PLAN 0.3.1 E3, HW-37 in CI), after SelfTest's token gate: builds
/// the host the way the app does (ModuleHost: stores, migrations, modules) and checks the updater gate, without
/// starting a module or a run loop, and without touching a TCC-guarded API (R5.5). It also runs `startUpdater()`: with
/// the gate closed it can't reach Sparkle; with it open (the signed app) it creates Sparkle's updater, whose first
/// update cycle is dispatched to the main queue, which never runs here, so nothing is checked or scheduled.
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
        // Sparkle, no network) and must leave no updater and no welcome card.
        let loaded = UpdaterController.isSparkleLoaded
        let gate = UpdaterController.gate
        report.append("selftest-launch: Sparkle " + (loaded ? "loaded" : "absent") + ", updater gate \(gate)")
        if gate != .ready {
            host.startUpdater()
            if host.updater != nil { problems.append("startUpdater() made an updater although the gate is \(gate)") }
            if host.showsV031Welcome { problems.append("the 0.3.1 card shows in a build that can't update itself") }
        } else {
            // The signed app, in launch order (r2 C2-1): a first launch begins onboarding inside bootstrap(), before
            // startUpdater() creates the updater. Unanswered, the updates page must join the run once it exists.
            UserDefaults.standard.removeObject(forKey: UpdateDefaultsKeys.automaticChecks)
            host.modulesStore.value.onboarding = .welcome
            host.onboarding.beginRun()
            if host.onboarding.includesUpdatesPage { problems.append("onboarding has the updates page before the updater exists") }
            host.startUpdater()
            if host.updater == nil { problems.append("startUpdater() made no updater although the gate is open") }
            if !host.onboarding.includesUpdatesPage {
                problems.append("onboarding has no updates page after startUpdater() (a new user is never asked)")
            }
            report.append("selftest-launch: onboarding begun before the updater, updates page "
                          + (host.onboarding.includesUpdatesPage ? "included" : "missing"))
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
