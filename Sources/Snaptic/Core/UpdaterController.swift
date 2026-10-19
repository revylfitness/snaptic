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
    /// Sparkle handed over an install-on-quit block (Relauncher calls it).
    var hasPendingQuitInstall: Bool { get }
    /// Check for Updates… (also in Safe Mode).
    func checkForUpdates()
    /// The menu row and About's Install and Relaunch…: Sparkle's window comes forward, or the pending install runs
    /// once UpdatePolicy allows it (otherwise a toast says why it waits).
    func installUpdate()
    /// 0.3.1 (T-update, additive): while a downloaded update waits for lid-closed mode or a display trial, the line
    /// the "Restart to Update Snaptic…" row shows instead (E4); nil when it can install now.
    var waitText: String? { get }
    /// 0.3.1 (T-update, additive): Relauncher is about to quit. True when a downloaded update takes over the
    /// relaunch (Sparkle installs it, then opens the new version); false to relaunch as usual. `safeMode`: the
    /// relaunch enters Safe Mode, which an update never replaces.
    func relaunchIntoUpdate(safeMode: Bool) -> Bool
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

    /// The updater gate (E4): dyld loaded Sparkle, so its symbols exist.
    static var isSparkleLoaded: Bool { Bundle(identifier: sparkleBundleIdentifier) != nil }

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

    @Published private(set) var availableUpdate: UpdateOffer? {
        didSet { if availableUpdate != oldValue { onChange() } }
    }
    @Published private(set) var checking = false
    /// The last update cycle ended in an error that isn't "no update" or the user's own choice.
    @Published private(set) var lastCheckFailed = false

    var hasPendingQuitInstall: Bool { pendingQuitInstall != nil }
    /// Read once: Sparkle's own decision follows the same test (SUInstallerLauncher).
    let needsAdministrator: Bool

    private var controller: SPUStandardUpdaterController?
    private let userDriverDelegate: UpdaterUserDriverDelegate
    private let facts: @MainActor () -> UpdatePolicy.Facts
    private let toast: @MainActor (String) -> Void
    private let onChange: @MainActor () -> Void
    private var pendingQuitInstall: (() -> Void)? {
        didSet { if (pendingQuitInstall == nil) != (oldValue == nil) { onChange() } }
    }
    /// Sparkle's relaunch, held while UpdatePolicy says wait.
    private var heldRelaunch: (() -> Void)?
    private var heldRelaunchTimer: Timer?
    /// Relauncher handed the quit to Sparkle: its relaunch is never held.
    private var relaunchRequested = false

    /// Nil when this build doesn't carry Sparkle (ad hoc, from source). GUI mode only (AppDelegate → ModuleHost).
    /// `facts`: lid-closed mode, display trials and Safe Mode now; `toast`: one line to show; `onChange`: on main,
    /// after every change to `availableUpdate` or `hasPendingQuitInstall` (ModuleHost forwards it as `updaterChanged`).
    static func make(facts: @escaping @MainActor () -> UpdatePolicy.Facts, toast: @escaping @MainActor (String) -> Void,
                     onChange: @escaping @MainActor () -> Void) -> UpdaterController? {
        guard isSparkleLoaded else { return nil }
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
        guard let block = pendingQuitInstall else {
            // Found, not downloaded: Sparkle's window comes forward (a user check, so it shows).
            checkForUpdates()
            return
        }
        switch UpdatePolicy.decide(.installNow, facts()) {
        case .allow:
            pendingQuitInstall = nil
            EventLog.shared.record(.modules, "Installing the downloaded update")
            block()
        case .wait(let wait):
            toast(UpdatePolicy.text(wait, version: availableUpdate?.version ?? ""))
        case .refuse:
            break
        }
    }

    var waitText: String? {
        guard let offer = availableUpdate, offer.readyToRestart,
              case .wait(let wait) = UpdatePolicy.decide(.installNow, facts()) else { return nil }
        return UpdatePolicy.text(wait, version: offer.version)
    }

    func relaunchIntoUpdate(safeMode: Bool) -> Bool {
        guard let block = pendingQuitInstall, UpdatePolicy.decide(.relaunch(safeMode: safeMode), facts()) == .allow
        else { return false }
        pendingQuitInstall = nil
        relaunchRequested = true
        EventLog.shared.record(.modules, "Relaunching into the downloaded update")
        block()
        return true
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

    private static func offerVersion(_ item: SUAppcastItem) -> String {
        // The feed is signed, but its text still reaches a menu title: only plain versions pass.
        UpdatePolicy.isVersion(item.displayVersionString) ? item.displayVersionString : L("a new version")
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
        guard let error = error as NSError? else {
            lastCheckFailed = false
            return
        }
        guard error.domain != Self.errorDomain else { return }
        lastCheckFailed = UpdatePolicy.checkFailed(sparkleDomain: error.domain == SUSparkleErrorDomain, code: error.code)
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
        pendingQuitInstall = immediateInstallHandler
        availableUpdate = UpdateOffer(version: Self.offerVersion(item), readyToRestart: true)
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
        watchHeldRelaunch()
        return true
    }

    @objc(updaterShouldRelaunchApplication:)
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { true }

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
        block()
    }

    // MARK: Gentle reminders (SPUStandardUserDriverDelegate, through UpdaterUserDriverDelegate)

    fileprivate func handle(_ event: UpdaterUserDriverDelegate.Event) {
        switch event {
        case .willShow(let version):
            // Scheduled updates never show Sparkle's window by themselves (not during onboarding or Safe Mode
            // either): the menu row and About offer them, and bring the window forward on request.
            availableUpdate = UpdateOffer(version: version, readyToRestart: false)
        case .attentionOrFinished:
            // The user saw Sparkle's window, or the session ended (installed, skipped, dismissed or failed). A
            // downloaded update that installs at quit keeps its row.
            if !(availableUpdate?.readyToRestart ?? false) || pendingQuitInstall == nil { availableUpdate = nil }
        }
    }
}

/// Sparkle's standard user driver calls this on the main thread; its protocol isn't main-actor annotated, so each
/// call hops to the main queue before it touches UpdaterController.
final class UpdaterUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    enum Event {
        case willShow(version: String)
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
        let version = UpdatePolicy.isVersion(update.displayVersionString) ? update.displayVersionString : L("a new version")
        send(.willShow(version: version))
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
