import AppKit
import Combine
import Sparkle
import SnapticKit

// In-app updates (owner: T-update; PLAN 0.3.1 E4): wraps Sparkle's standard updater controller. The only file allowed to
// import Sparkle (lint L19). Sparkle is weak-linked: every Sparkle symbol is reached only after
// `Bundle(identifier: "org.sparkle-project.Sparkle") != nil` (`make`), so a build without the framework never touches
// it. Every decision (when to check, install, relaunch, what the status row says) is Kit's `UpdatePolicy`.

/// What the host, StatusMenu, the About page and Relauncher use (`ModuleHost.updater`).
@MainActor protocol UpdaterControlling: AnyObject {
    /// About's "Check for updates automatically" (Snaptic sets it from the user's consent, never Sparkle's prompt).
    var automaticallyChecksForUpdates: Bool { get set }
    /// About's "Download and install updates automatically" (never for root-owned copies).
    var automaticallyDownloadsUpdates: Bool { get set }
    /// The update Snaptic's own rows offer (gentle reminders), or nil.
    var availableUpdate: UpdateOffer? { get }
    /// Sparkle's installer waits to install a downloaded update when Snaptic quits.
    var hasPendingQuitInstall: Bool { get }
    /// Check for Updates… (also in Safe Mode).
    func checkForUpdates()
    /// The menu row and About's Install and Relaunch…: Sparkle's window comes forward, or the pending install runs
    /// once UpdatePolicy allows it (otherwise a toast says why it waits).
    func installUpdate()
    /// 0.3.1 (T-update, additive): while a downloaded update or Sparkle's relaunch waits for lid-closed mode or a
    /// display trial, the line the update row shows instead (E4; r3 U3-4); nil when it can go ahead now.
    var waitText: String? { get }
    /// 0.3.1: Relauncher is about to quit (E4; r1 C3, S9). `.throughUpdate`: the waiting update took over the relaunch
    /// (Sparkle installs it, then opens the new version); `.normal`: relaunch as usual; `.quitFirst`: an update waits
    /// to install at quit and can't take over (a Safe Mode relaunch, or its block is gone), so nothing relaunches and
    /// a toast says to quit first. `safeMode`: the relaunch enters Safe Mode, which an update never replaces.
    func prepareRelaunch(safeMode: Bool) -> UpdatePolicy.RelaunchRoute
}

@MainActor final class UpdaterController: NSObject, ObservableObject, UpdaterControlling, SPUUpdaterDelegate {
    /// Loaded by dyld only in builds that embed it (Developer ID releases).
    static let sparkleBundleIdentifier = "org.sparkle-project.Sparkle"
    /// The version Sparkle was about to install, for the post-update notice (E1). Snaptic's own key: Reset leaves it
    /// (the next launch reads and removes it), and backups never see it.
    static let installingVersionKey = "SnapticUpdateInstalling"
    /// How often a held relaunch looks again at what holds it.
    static let deferralRecheck: TimeInterval = 5
    private static let errorDomain = "app.snaptic.updates"

    /// dyld loaded Sparkle, so its symbols exist.
    static var isSparkleLoaded: Bool { Bundle(identifier: sparkleBundleIdentifier) != nil }

    /// The updater gate `make()` uses (E4; r1 C8): Sparkle is loaded, and this is an `.app` bundle with an update key.
    /// An unbundled debug run (`swift run`) can find Sparkle next to its binary, but Sparkle would only show its
    /// "Unable to Check For Updates" alert there.
    static var gate: UpdatePolicy.Gate {
        UpdatePolicy.gate(sparkleLoaded: isSparkleLoaded, bundleExtension: Bundle.main.bundleURL.pathExtension,
                          publicKey: Bundle.main.object(forInfoDictionaryKey: UpdatePolicy.publicKeyInfoKey) as? String)
    }

    /// Whether Sparkle must ask for an administrator password to replace this copy (root-owned; E1). Such copies
    /// never install by themselves.
    static var needsAdministrator: Bool {
        let path = Bundle.main.bundlePath
        let parent = (path as NSString).deletingLastPathComponent
        var info = stat()
        let owned = lstat(path, &info) == 0 && info.st_uid == getuid()
        return UpdatePolicy.needsAdministrator(bundleWritable: access(path, W_OK) == 0,
                                               parentWritable: access(parent, W_OK) == 0, ownedByUser: owned)
    }

    /// Kit's view of Sparkle's session: the offer, a waiting install, and whether `installBlock` is still alive.
    private var session = UpdateSession() {
        willSet { objectWillChange.send() }
        didSet {
            if !session.hasInstallBlock { installBlock = nil }
            if session.offer != oldValue.offer || session.installWaits != oldValue.installWaits { onChange() }
        }
    }
    var availableUpdate: UpdateOffer? { session.offer }
    @Published private(set) var checking = false
    /// The last update cycle ended in an error that isn't "no update" or the user's own choice.
    @Published private(set) var lastCheckFailed = false

    var hasPendingQuitInstall: Bool { session.installWaits }
    /// Read once: Sparkle's own decision follows the same test (SUInstallerLauncher).
    let needsAdministrator: Bool
    /// Sparkle's updater started (r3 C3-4): `SPUStandardUpdaterController.startUpdater()` only logs a configuration
    /// error and shows its alert a second later, so `canCheckForUpdates` (set only on success) is what tells.
    private(set) var started = false

    private var controller: SPUStandardUpdaterController?
    private let userDriverDelegate: UpdaterUserDriverDelegate
    private let facts: @MainActor () -> UpdatePolicy.Facts
    private let toast: @MainActor (String) -> Void
    private let onChange: @MainActor () -> Void
    /// Sparkle's install-now block, kept only while `session.hasInstallBlock` (S9).
    private var installBlock: (() -> Void)?
    /// Sparkle's relaunch, held while UpdatePolicy says wait.
    private var heldRelaunch: (() -> Void)?
    private var heldRelaunchTimer: Timer?
    /// Relauncher handed the quit to Sparkle: its relaunch is never held.
    private var relaunchRequested = false

    /// Nil unless `gate` is `.ready` (ad hoc builds, builds from source, unbundled debug runs). GUI mode only
    /// (AppDelegate → ModuleHost).
    /// `facts`: lid-closed mode, display trials and Safe Mode now; `toast`: one line to show; `onChange`: on main,
    /// after every change to `availableUpdate` or `hasPendingQuitInstall` (ModuleHost forwards it as `updaterChanged`).
    static func make(facts: @escaping @MainActor () -> UpdatePolicy.Facts, toast: @escaping @MainActor (String) -> Void,
                     onChange: @escaping @MainActor () -> Void) -> UpdaterController? {
        guard gate == .ready else { return nil }
        let updater = UpdaterController(facts: facts, toast: toast, onChange: onChange)
        updater.start()
        return updater
    }

    private init(facts: @escaping @MainActor () -> UpdatePolicy.Facts, toast: @escaping @MainActor (String) -> Void,
                 onChange: @escaping @MainActor () -> Void) {
        self.facts = facts
        self.toast = toast
        self.onChange = onChange
        needsAdministrator = Self.needsAdministrator
        userDriverDelegate = UpdaterUserDriverDelegate()
        super.init()
        userDriverDelegate.handler = { [weak self] event in self?.handle(event) }
    }

    private func start() {
        // Sparkle holds both delegates weakly; this object owns the user-driver delegate.
        let standard = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self,
                                                    userDriverDelegate: userDriverDelegate)
        controller = standard
        let updater = standard.updater
        // E2 feed pinning: a SUFeedURL written into Snaptic's defaults never redirects a check.
        _ = updater.clearFeedURLFromUserDefaults()
        updater.sendsSystemProfile = false
        // Root-owned copies only install after an explicit Install and Relaunch (E1).
        if needsAdministrator && updater.automaticallyDownloadsUpdates { updater.automaticallyDownloadsUpdates = false }
        standard.startUpdater()
        started = updater.canCheckForUpdates
        guard started else {
            EventLog.shared.record(.modules, "Updater failed to start")
            return
        }
        EventLog.shared.record(.modules, "Updater started" + (needsAdministrator ? " (installs need a password)" : ""))
    }

    // MARK: Settings (About, onboarding, the 0.3.1 card)

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != newValue else { return }
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            let value = newValue && !needsAdministrator
            guard let updater = controller?.updater, updater.automaticallyDownloadsUpdates != value else { return }
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = value
        }
    }

    /// The user answered "check automatically" (Snaptic's onboarding step, the 0.3.1 card or About's toggle).
    var consentDecided: Bool { UserDefaults.standard.object(forKey: UpdateDefaultsKeys.automaticChecks) != nil }

    /// Check Automatically / Not Now: checks and automatic install together (never install for root-owned copies).
    func setConsent(_ allowed: Bool) {
        objectWillChange.send()
        automaticallyChecksForUpdates = allowed
        automaticallyDownloadsUpdates = allowed
        // Not Now answers the question even when the value didn't change (Sparkle only writes on a change).
        if !consentDecided { UserDefaults.standard.set(allowed, forKey: UpdateDefaultsKeys.automaticChecks) }
        EventLog.shared.record(.modules, allowed ? "Automatic update checks on" : "Automatic update checks off")
    }

    // MARK: Actions

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    func installUpdate() {
        guard let block = installBlock else {
            // Found, not downloaded, or an install Sparkle resumed itself: Sparkle's window comes forward (a user
            // check, so it shows; it resumes a waiting installer).
            checkForUpdates()
            return
        }
        switch UpdatePolicy.decide(.installNow, facts()) {
        case .allow:
            session.apply(.installStarted)
            EventLog.shared.record(.modules, "Installing the downloaded update")
            block()
        case .wait(let wait):
            toast(UpdatePolicy.text(wait, version: availableUpdate?.version.flatMap { $0.isEmpty ? nil : $0 }))
        case .refuse:
            break
        }
    }

    var waitText: String? { UpdatePolicy.waitText(availableUpdate, facts()) }

    func prepareRelaunch(safeMode: Bool) -> UpdatePolicy.RelaunchRoute {
        var route = UpdatePolicy.relaunchRoute(safeMode: safeMode, session: session)
        if route == .throughUpdate && installBlock == nil { route = .quitFirst }
        relaunchRequested = route == .throughUpdate
        switch route {
        case .normal:
            break
        case .throughUpdate:
            guard let block = installBlock else { break }
            session.apply(.installStarted)
            EventLog.shared.record(.modules, "Relaunching into the downloaded update")
            block()
        case .quitFirst:
            EventLog.shared.record(.modules, "Relaunch refused: an update waits to install when Snaptic quits")
            toast(UpdatePolicy.quitFirstText(safeMode: safeMode))
        }
        return route
    }

    // MARK: About's status row (E1)

    func statusText(now: Date = Date()) -> String {
        let state = UpdateStatusText.state(UpdateStatusText.Facts(
            checking: checking, failed: lastCheckFailed, offer: availableUpdate,
            automaticChecks: automaticallyChecksForUpdates, consentDecided: consentDecided,
            lastCheck: lastCheck(now: now), policy: facts()))
        return UpdateStatusText.text(state, uses24Hour: AwakeFormat.text.uses24Hour)
    }

    /// Install and Relaunch… shows beside the status row.
    var offersInstall: Bool {
        UpdateStatusText.offersInstall(UpdateStatusText.state(UpdateStatusText.Facts(
            checking: checking, failed: lastCheckFailed, offer: availableUpdate, policy: facts())))
    }

    private func lastCheck(now: Date) -> UpdateStatusText.LastCheck? {
        guard let date = controller?.updater.lastUpdateCheckDate else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return UpdateStatusText.LastCheck(daysAgo: days, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 0,
                                          minute: c.minute ?? 0)
    }

    // MARK: SPUUpdaterDelegate (explicit selectors, so a renamed Swift spelling can't silently drop a hook)

    @objc(feedURLStringForUpdater:)
    func feedURLString(for updater: SPUUpdater) -> String? { UpdatePolicy.feedURL }

    /// Snaptic asks in its own UI (onboarding, the 0.3.1 card); Sparkle's prompt never appears.
    @objc(updaterShouldPromptForPermissionToCheckForUpdates:)
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    /// Scheduled checks stop in Safe Mode; checks the user starts always run (E4).
    @objc(updater:mayPerformUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let event: UpdatePolicy.Event = updateCheck == .updatesInBackground ? .scheduledCheck : .userCheck
        guard UpdatePolicy.decide(event, facts()) == .allow else {
            throw NSError(domain: Self.errorDomain, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("Updates are paused in Safe Mode.")])
        }
        checking = true
    }

    @objc(updater:didFinishUpdateCycleForUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        checking = false
        guard let failure = error else {
            lastCheckFailed = false
            session.apply(.cycleFinished(failed: false))
            return
        }
        let error = failure as NSError
        guard error.domain != Self.errorDomain else {
            // Snaptic's own Safe Mode refusal: no cycle ran.
            session.apply(.cycleFinished(failed: false))
            return
        }
        lastCheckFailed = UpdatePolicy.checkFailed(sparkleDomain: error.domain == SUSparkleErrorDomain, code: error.code)
        // The cycle is over, so the block its driver handed over is dead (S9).
        session.apply(.cycleFinished(failed: lastCheckFailed))
        if lastCheckFailed { EventLog.shared.record(.modules, "Update check failed (\(error.domain) \(error.code))") }
    }

    /// Sparkle starts installing (the user's Install and Relaunch, or at quit): the next launch says it updated.
    @objc(updater:willInstallUpdate:)
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        recordInstalling(item)
    }

    /// E4: Snaptic owns the prompt ("Restart to Update Snaptic…"); Sparkle still installs when Snaptic quits.
    @objc(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        recordInstalling(item)
        installBlock = immediateInstallHandler
        // The feed is signed, but its text still reaches a menu title: UpdateOffer keeps only plain versions.
        session.apply(.installsOnQuit(version: item.displayVersionString))
        return true
    }

    /// A relaunch into the new version waits for lid-closed mode and display trials (E4). Snaptic checks again every
    /// few seconds and lets it go once nothing holds it.
    @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !relaunchRequested, case .wait(let wait) = UpdatePolicy.decide(.relaunchAfterInstall, facts()) else {
            return false
        }
        EventLog.shared.record(.modules, "Update relaunch held: \(wait)")
        heldRelaunch = installHandler
        // Sparkle's window may close or end its session meanwhile: the menu and About keep the update, with the line
        // saying Snaptic restarts by itself once the wait ends (r3 U3-4).
        session.apply(.relaunchHeld(version: item.displayVersionString))
        toast(UpdatePolicy.relaunchText(wait, version: availableUpdate?.version))
        watchHeldRelaunch()
        return true
    }

    @objc(updaterShouldRelaunchApplication:)
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { true }

    /// The user's choice in Sparkle's window. Skip This Version on a waiting install cancels Sparkle's installer
    /// without an error, so only this tells the session that nothing waits any more (r2 C2-4).
    @objc(updater:userDidMakeChoice:forUpdate:state:)
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem,
                 state: SPUUserUpdateState) {
        let made: UpdateSession.UserChoice
        switch choice {
        case .skip: made = .skip
        case .install: made = .install
        case .dismiss: made = .dismiss
        @unknown default: return
        }
        session.apply(.userChose(made, installing: state.stage == .installing))
    }

    private func recordInstalling(_ item: SUAppcastItem) {
        guard UpdatePolicy.isVersion(item.displayVersionString) else { return }
        UserDefaults.standard.set(item.displayVersionString, forKey: Self.installingVersionKey)
    }

    private func watchHeldRelaunch() {
        heldRelaunchTimer?.invalidate()
        let timer = Timer(timeInterval: Self.deferralRecheck, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckHeldRelaunch() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        heldRelaunchTimer = timer
    }

    private func recheckHeldRelaunch() {
        guard let block = heldRelaunch else {
            heldRelaunchTimer?.invalidate()
            heldRelaunchTimer = nil
            return
        }
        guard UpdatePolicy.decide(.relaunchAfterInstall, facts()) == .allow else { return }
        heldRelaunch = nil
        heldRelaunchTimer?.invalidate()
        heldRelaunchTimer = nil
        EventLog.shared.record(.modules, "Update relaunch released")
        session.apply(.relaunchReleased)
        block()
    }

    // MARK: Gentle reminders (SPUStandardUserDriverDelegate, through UpdaterUserDriverDelegate)

    fileprivate func handle(_ event: UpdaterUserDriverDelegate.Event) {
        switch event {
        case .willShow(let version, let installing):
            // Scheduled updates never show Sparkle's window by themselves (not during onboarding or Safe Mode
            // either): the menu row and About offer them, and bring the window forward on request. A resumed install
            // keeps "Restart to Update Snaptic…" (C2).
            session.apply(.found(version: version, installing: installing))
        case .attentionOrFinished:
            // The user saw Sparkle's window, or the session ended (installed, skipped, dismissed or failed). An
            // install that waits for quit keeps its row.
            session.apply(.attentionOrFinished)
        }
    }
}

/// Sparkle's standard user driver calls this on the main thread; its protocol isn't main-actor annotated, so each
/// call hops to the main queue before it touches UpdaterController.
final class UpdaterUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    enum Event {
        case willShow(version: String, installing: Bool)
        case attentionOrFinished
    }

    /// Set once by UpdaterController's init, before Sparkle can call anything.
    var handler: (@MainActor (Event) -> Void)?

    @objc var supportsGentleScheduledUpdateReminders: Bool { true }

    @objc(standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:)
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    @objc(standardUserDriverWillHandleShowingUpdate:forUpdate:state:)
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        send(.willShow(version: update.displayVersionString, installing: state.stage == .installing))
    }

    @objc(standardUserDriverDidReceiveUserAttentionForUpdate:)
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        send(.attentionOrFinished)
    }

    @objc(standardUserDriverWillFinishUpdateSession)
    func standardUserDriverWillFinishUpdateSession() {
        send(.attentionOrFinished)
    }

    private func send(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handler?(event) }
        }
    }
}
