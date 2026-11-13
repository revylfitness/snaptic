import AppKit
import SnapticKit

/// `--selftest-launch <token-file>` (owner: T-update; PLAN 0.3.1 E3, HW-37 in CI), after SelfTest's token gate: builds
/// the host the way the app does (ModuleHost: stores, migrations, modules) and checks the updater gate, without
/// starting a module or a run loop, and without touching a TCC-guarded API (R5.5). It also runs `startUpdater()`: with
/// the gate closed it can't reach Sparkle; with it open (the signed app) it creates Sparkle's updater, whose first
/// update cycle is dispatched to the main queue, which never runs here, so nothing is checked or scheduled. A DEBUG
/// build also starts Dock Previews once with a Safe Mode context, after the `dock live` line; that start creates
/// nothing (0.5 A6a, G3-5).
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

        // The app's own startup checks: the release binary must find the account's home folder (0.3.1 shipped one
        // that didn't) and agree with the Displays journal's lookup.
        if let refusal = SnapticEntry.accountRefusal(environment: ProcessInfo.processInfo.environment) {
            problems.append("startup checks refuse: " + refusal)
        }
        let accountHome = AccountPaths.home
        let foundationHome = FileManager.default.homeDirectoryForCurrentUser.path
        if accountHome == nil || accountHome != foundationHome {
            problems.append("home lookups disagree: \(accountHome ?? "nil") vs \(foundationHome)")
        }
        report.append("selftest-launch: account home " + (accountHome ?? "nil"))

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
        // 0.4 A1: building the modules creates no Hidden Icons item; only start() does.
        report.append("selftest-launch: icons items \(IconsItems.liveCount)")
        if IconsItems.liveCount != 0 { problems.append("IconsModule created \(IconsItems.liveCount) status items before start()") }
        // 0.5 §4.22 (A1a, A6a): building the modules takes no WindowServices lease and creates no Dock observer, tap,
        // panel or timer; only start() does.
        let leases = WindowServices.shared.liveLeases
        report.append(DockPreviewsModule.live.launchLine(leases: leases))
        problems += DockPreviewsModule.live.launchProblems(leases: leases)

        // 0.4 H8: the Native shim's encodings, without activating an assertion or touching Accessibility.
        let shim = PrivateMenuBarAPI.verify()
        report.append(IconsShimContract.launchLine(shim.state))
        problems += IconsShimContract.selfTestProblems(
            state: shim.state, present: shim.present, mismatches: shim.mismatches,
            expect: ProcessInfo.processInfo.environment[IconsShimContract.expectVariable])
        #if DEBUG
        // The poison path. The shim stays poisoned for the rest of this process; nothing after this uses it.
        let forced = PrivateMenuBarAPI.forcePoisonForSelfTest()
        problems += IconsShimContract.poisonProblems(poisoned: forced.poisoned, available: forced.available)
        report.append("selftest-launch: icons shim poison path " + (forced.poisoned && !forced.available ? "ok" : "failed"))
        // 0.5 A6a (G3-5, P3-2): Dock Previews in Safe Mode is paused and creates nothing. The verbs are A9's.
        if let probe = host.debugDockSafeModeProbe() {
            let (line, found) = dockSafeModeCheck(probe)
            report.append(line)
            problems += found
        } else {
            problems.append("the Dock Previews Safe Mode probe didn't run")
        }
        #endif

        // 0.5 B1b (PLAN §4.12): one line per window symbol from the lookups, the gate, the image check, the crash
        // guard and the kill switches, then secure input. No private call and no Accessibility request runs here.
        problems += PrivateWindowAPI.tableProblems()
        let windowReports = PrivateWindowAPI.launchReports()
        let secureInput = PrivateWindowAPI.secureInputState
        report += WindowSymbolContract.launchLines(windowReports, secureInput: secureInput)
        problems += WindowSymbolContract.selfTestProblems(
            windowReports, secureInput: secureInput,
            expect: ProcessInfo.processInfo.environment[WindowSymbolContract.expectVariable])
        #if DEBUG
        // The poison path. Every window symbol stays poisoned for the rest of this process; nothing after this uses one.
        let poisonedReports = PrivateWindowAPI.forcePoisonForSelfTest()
        let poisonProblems = WindowSymbolContract.poisonProblems(poisonedReports)
        problems += poisonProblems
        report.append(WindowSymbolContract.poisonLine(poisonProblems))
        #endif

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
            // r3 C3-4: Sparkle refuses a misconfigured bundle only in a log line and a delayed alert.
            if let updater = host.updaterController, !updater.started {
                problems.append("Sparkle's updater didn't start (canCheckForUpdates is false; see the log)")
            }
            report.append("selftest-launch: Sparkle's updater " + (host.updaterController?.started == true ? "started" : "not started"))
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

    #if DEBUG
    /// `selftest-launch: dock safe mode state=paused observer=no leases=0 captures=0`, and what's wrong with it.
    @MainActor private static func dockSafeModeCheck(
        _ probe: (state: ModuleState, diagnostics: [String], liveLeases: Int)
    ) -> (line: String, problems: [String]) {
        let rows = probe.diagnostics.compactMap(HostReport.row)
        func value(_ label: String) -> String { rows.first { $0.label == label }?.value ?? "missing" }
        let observer = value("Observer attached")
        let leases = value("Leases")
        let captures = value("Captures")
        let state: String
        switch probe.state {
        case .stopped: state = "stopped"
        case .running: state = "running"
        case .degraded(let reason): state = reason == L("Paused in Safe Mode") ? "paused" : "degraded"
        }
        var problems: [String] = []
        if probe.state != .degraded(L("Paused in Safe Mode")) {
            problems.append("Dock Previews in Safe Mode is \(state), not paused")
        }
        if observer != "no" { problems.append("Dock Previews in Safe Mode reports its observer as \(observer)") }
        if leases != "0" || probe.liveLeases != 0 {
            problems.append("Dock Previews in Safe Mode holds a lease (\(leases), \(probe.liveLeases) live)")
        }
        if captures != "0" { problems.append("Dock Previews in Safe Mode reports \(captures) captures") }
        if !DockPreviewsModule.live.isBalanced { problems.append("Dock Previews in Safe Mode created something") }
        let line = "selftest-launch: dock safe mode state=\(state) observer=\(observer) leases=\(leases) "
            + "captures=\(captures)"
        return (line, problems)
    }
    #endif
}
