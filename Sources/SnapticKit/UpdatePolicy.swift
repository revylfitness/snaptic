import Foundation

// In-app updates, pure parts (owner: T-update; PLAN 0.3.1 E1, E4): when a check, an install or a relaunch must wait,
// the About page's status row, the post-update notice, and the Sparkle defaults keys (the only home of `SU*` key
// strings, lint L19). The app (UpdaterController) only gathers facts and calls these.

/// An update Sparkle found (gentle reminders): what the menu row and About's status row offer.
package struct UpdateOffer: Equatable, Sendable {
    /// "0.3.2"; nil when the feed's version isn't a plain version (`UpdatePolicy.isVersion`): the texts then read
    /// "a new version" in a form that still makes a sentence (r1 U5).
    package var version: String?
    /// Downloaded, and installs at quit: the menu row reads "Restart to Update Snaptic…".
    package var readyToRestart: Bool

    package init(version: String?, readyToRestart: Bool) {
        self.version = version.flatMap { UpdatePolicy.isVersion($0) ? $0 : nil }
        self.readyToRestart = readyToRestart
    }
}

/// What Snaptic knows of Sparkle's update session (E4; r1 C2, S9). UpdaterController feeds it Sparkle's callbacks and
/// only keeps the install-now block while `hasInstallBlock` says it is still alive.
package struct UpdateSession: Equatable, Sendable {
    /// What the menu row and About offer.
    package private(set) var offer: UpdateOffer?
    /// Sparkle's installer is prepared and installs when Snaptic quits ("Restart to Update Snaptic…").
    package private(set) var installWaits = false
    /// The install-now block from `willInstallUpdateOnQuit` can still run. Sparkle's automatic driver holds it only
    /// weakly, so it is dead once that driver's update cycle ended (or after it ran once).
    package private(set) var hasInstallBlock = false

    package enum Event: Equatable, Sendable {
        /// `standardUserDriverWillHandleShowingUpdate`: a gentle reminder; `installing` when Sparkle resumed an update
        /// whose installer already waits (`state.stage == .installing`).
        case found(version: String?, installing: Bool)
        /// `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` (Snaptic returned YES and kept the block).
        case installsOnQuit(version: String?)
        /// The user saw Sparkle's window, or its session ended (installed, skipped, dismissed or failed).
        case attentionOrFinished
        /// `updater(_:didFinishUpdateCycleFor:error:)`; `failed` as `UpdatePolicy.checkFailed` decides.
        case cycleFinished(failed: Bool)
        /// Snaptic ran the install-now block.
        case installStarted
        /// `updater(_:userDidMake:forUpdate:state:)`: the user's choice in Sparkle's window; `installing` when the
        /// window offered an install that already waits (`state.stage == .installing`).
        case userChose(UserChoice, installing: Bool)
    }

    /// Sparkle's `SPUUserUpdateChoice`.
    package enum UserChoice: Equatable, Sendable {
        case install, skip, dismiss
    }

    package init() {}

    package mutating func apply(_ event: Event) {
        switch event {
        case .found(let version, let installing):
            // A resumed install keeps its "Restart to Update" row; a ready offer is never downgraded (C2).
            if installing { installWaits = true }
            offer = UpdateOffer(version: version, readyToRestart: installWaits)
        case .installsOnQuit(let version):
            installWaits = true
            hasInstallBlock = true
            offer = UpdateOffer(version: version, readyToRestart: true)
        case .attentionOrFinished:
            // An install that still waits for quit keeps its row; anything else is Sparkle's window's business now.
            if !installWaits { offer = nil }
        case .cycleFinished(let failed):
            // The cycle that handed over the block is over, so its driver (and the block) is gone (S9). A failure
            // also ends the waiting install.
            hasInstallBlock = false
            if failed {
                installWaits = false
                offer = nil
            }
        case .installStarted:
            hasInstallBlock = false
        case .userChose(let choice, let installing):
            // Skip This Version on a waiting install cancels Sparkle's installer, and the cycle then ends without an
            // error (r2 C2-4). Install on Quit (dismiss) and Install and Relaunch leave it waiting.
            if choice == .skip && installing {
                installWaits = false
                hasInstallBlock = false
                offer = nil
            }
        }
    }
}

package enum UpdatePolicy {
    /// The constant feed (E3). The updater's delegate returns it, so a `SUFeedURL` written into Snaptic's defaults
    /// can't redirect checks (E2, feed pinning).
    package static let feedURL = "https://github.com/revylfitness/snaptic/releases/latest/download/appcast.xml"
    /// Check for Updates… in builds without Sparkle, and the source of every release.
    package static let releasesURL = "https://github.com/revylfitness/snaptic/releases"
    /// The Info.plist key holding the update key (E4); a bundle without it can't start Sparkle's updater.
    package static let publicKeyInfoKey = "SUPublicEDKey"

    /// What can hold an install or relaunch back (E4).
    package struct Facts: Equatable, Sendable {
        /// Lid-closed mode is on, or turning on or off (`holdsUpdates`; r1 C7).
        package var lidModeOn: Bool
        /// A display change waits for Keep or Undo, or the display queue is still applying one.
        package var displayTrialPending: Bool
        package var safeMode: Bool

        package init(lidModeOn: Bool, displayTrialPending: Bool, safeMode: Bool) {
            self.lidModeOn = lidModeOn
            self.displayTrialPending = displayTrialPending
            self.safeMode = safeMode
        }
    }

    /// Why something waits, most important first.
    package enum Wait: Equatable, Sendable {
        case lidClosed, displayTrial, safeMode
    }

    /// Everything the updater asks Snaptic (E4's matrix; `UpdatePolicyTests` covers every event and fact).
    package enum Event: Equatable, Sendable {
        /// Sparkle's once-a-day check (`updater(_:mayPerform:)` with a background check).
        case scheduledCheck
        /// Check for Updates…, the menu row and About's buttons (a user check; also in Safe Mode, so a crash-looping
        /// release can still be fixed).
        case userCheck
        /// Sparkle is about to relaunch into a newly installed version (`shouldPostponeRelaunchForUpdate`).
        case relaunchAfterInstall
        /// "Restart to Update Snaptic…" or About's Install and Relaunch… runs the stored install-on-quit block.
        case installNow
    }

    package enum Decision: Equatable, Sendable {
        case allow
        case wait(Wait)
        /// The event doesn't happen at all (a scheduled check in Safe Mode).
        case refuse
    }

    package static func decide(_ event: Event, _ facts: Facts) -> Decision {
        switch event {
        case .scheduledCheck:
            return facts.safeMode ? .refuse : .allow
        case .userCheck:
            return .allow
        case .relaunchAfterInstall, .installNow:
            // Relaunching closes the lid-closed session (the Mac would sleep at once with the lid shut) and reverts a
            // display trial, so both wait. Safe Mode doesn't: the user chose this update by hand.
            if facts.lidModeOn { return .wait(.lidClosed) }
            if facts.displayTrialPending { return .wait(.displayTrial) }
            return .allow
        }
    }

    /// Whether lid-closed mode holds updates back (r1 C7): on, and also while the password is asked for, the
    /// watchdog is verified, or the mode stops. Only `off` and a failure (on its way to `off`) let updates go ahead.
    package static func holdsUpdates(_ mode: AwakeLidMode) -> Bool {
        switch mode {
        case .off, .failed: return false
        case .authorizing, .verifying, .on, .stopping: return true
        }
    }

    /// How Relauncher quits (E4; r1 C3, S9).
    package enum RelaunchRoute: Equatable, Sendable {
        /// Open a new instance, then quit (nothing waits to install).
        case normal
        /// Run Sparkle's install-now block: it installs the waiting update, then opens the new version.
        case throughUpdate
        /// An update waits to install at quit and can't take over this relaunch (a Safe Mode relaunch, which an
        /// update must never replace, or the block is gone). A new instance opened now would start from the bundle
        /// Sparkle replaces when this one quits, so nothing relaunches; `quitFirstText` says what to do.
        case quitFirst
    }

    package static func relaunchRoute(safeMode: Bool, session: UpdateSession) -> RelaunchRoute {
        guard session.installWaits else { return .normal }
        return !safeMode && session.hasInstallBlock ? .throughUpdate : .quitFirst
    }

    package static func quitFirstText(safeMode: Bool) -> String {
        safeMode ? L("Quit Snaptic to finish installing the update first, then hold Shift while you open it to start in Safe Mode.")
            : L("Quit Snaptic to finish installing the update, then open it again.")
    }

    /// Why Sparkle's updater does or doesn't start in this process (E4; r1 C8).
    package enum Gate: Equatable, Sendable {
        case ready
        /// dyld didn't load Sparkle (ad hoc builds and builds from source carry none).
        case noSparkle
        /// Not running from an `.app` bundle (`swift run`, `.build/debug/Snaptic`): Sparkle would only show its
        /// "Unable to Check For Updates" alert.
        case notAppBundle
        /// The bundle has no valid `SUPublicEDKey` (a 32-byte Ed25519 key, base64), so no update could verify.
        case noPublicKey
    }

    package static func gate(sparkleLoaded: Bool, bundleExtension: String, publicKey: String?) -> Gate {
        guard sparkleLoaded else { return .noSparkle }
        guard bundleExtension == "app" else { return .notAppBundle }
        guard let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return .noPublicKey }
        return .ready
    }

    /// The menu row (E1): "Update Available: Snaptic 0.3.2…", or "Restart to Update Snaptic…" once it installs at quit.
    package static func menuTitle(_ offer: UpdateOffer) -> String {
        if offer.readyToRestart { return L("Restart to Update Snaptic…") }
        guard let version = offer.version else { return L("Update Available: Snaptic…") }
        return L("Update Available: Snaptic ") + version + "…"
    }

    /// The deferral line (also the toast when Install and Relaunch… is clicked while it waits; E1, E4).
    package static func text(_ wait: Wait, version: String?) -> String {
        switch wait {
        case .lidClosed:
            guard let version else { return L("The update will install when lid-closed mode ends.") }
            return L("Version ") + version + L(" will install when lid-closed mode ends.")
        case .displayTrial:
            guard let version else { return L("The update will install when the display change is kept or undone.") }
            return L("Version ") + version + L(" will install when the display change is kept or undone.")
        case .safeMode: return L("Updates are paused in Safe Mode. Choose Check for Updates… to update anyway.")
        }
    }

    /// "0.3.2": three dot-separated numbers of at most 4 digits each. Versions come from the feed and from defaults,
    /// so they are checked before they reach a URL or a sentence.
    package static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.count <= 4 && part.utf8.allSatisfy { (0x30...0x39).contains($0) }
        }
    }

    /// What's New after an update (E1): the release page of a valid version, else nil.
    package static func releaseNotesURL(version: String) -> String? {
        isVersion(version) ? releasesURL + "/tag/v" + version : nil
    }

    /// Sparkle's update-cycle error, as About's status row reads it: false for "no update" and for the user's own
    /// cancel or "later" (Sparkle's error codes 1001, 4007, 4008 in its own domain); true for anything else (the feed
    /// or the download failed, or the update didn't verify).
    package static func checkFailed(sparkleDomain: Bool, code: Int) -> Bool {
        guard sparkleDomain else { return true }
        return ![1001, 4007, 4008].contains(code)
    }

    /// Whether Sparkle has to ask for an administrator password to replace this copy (E1: "root-owned"), mirroring
    /// Sparkle's own test: the bundle and its folder must be writable and the bundle owned by this account. Such
    /// copies never install by themselves; the automatic-install row explains why instead.
    package static func needsAdministrator(bundleWritable: Bool, parentWritable: Bool, ownedByUser: Bool) -> Bool {
        !(bundleWritable && parentWritable && ownedByUser)
    }

    /// The post-update notice (E1): shown once, on the first launch of the version Sparkle recorded before it
    /// installed. `recorded` is nil when Sparkle installed nothing (a manual install shows nothing).
    package static func updatedNotice(recorded: String?, running: String) -> String? {
        guard let recorded, recorded == running, isVersion(running) else { return nil }
        return L("Snaptic was updated to ") + running + "."
    }
}

/// About's status row (E1): "Last checked today at 9:12 AM", "Checking…", "Version 0.3.2 is available.", …,
/// hand-formatted (N12). The app passes the calendar facts; nothing here reads a clock or a locale.
package enum UpdateStatusText {
    /// A past check in the user's calendar: how many days ago (0 = today), and its local month, day, hour and minute.
    package struct LastCheck: Equatable, Sendable {
        package var daysAgo: Int
        package var month: Int
        package var day: Int
        package var hour: Int
        package var minute: Int

        package init(daysAgo: Int, month: Int, day: Int, hour: Int, minute: Int) {
            self.daysAgo = daysAgo
            self.month = month
            self.day = day
            self.hour = hour
            self.minute = minute
        }
    }

    package struct Facts: Equatable, Sendable {
        /// Sparkle isn't in this build (built from source, ad hoc).
        package var fromSource: Bool
        package var checking: Bool
        /// The last check (or download) failed.
        package var failed: Bool
        package var offer: UpdateOffer?
        package var automaticChecks: Bool
        /// The user answered (onboarding, the 0.3.1 card, or a toggle): "Automatic checks are off." instead of
        /// "Not checked yet".
        package var consentDecided: Bool
        package var lastCheck: LastCheck?
        package var policy: UpdatePolicy.Facts

        package init(fromSource: Bool = false, checking: Bool = false, failed: Bool = false, offer: UpdateOffer? = nil,
                     automaticChecks: Bool = false, consentDecided: Bool = false, lastCheck: LastCheck? = nil,
                     policy: UpdatePolicy.Facts = UpdatePolicy.Facts(lidModeOn: false, displayTrialPending: false,
                                                                     safeMode: false)) {
            self.fromSource = fromSource
            self.checking = checking
            self.failed = failed
            self.offer = offer
            self.automaticChecks = automaticChecks
            self.consentDecided = consentDecided
            self.lastCheck = lastCheck
            self.policy = policy
        }
    }

    package enum State: Equatable, Sendable {
        case fromSource, checking, failed, notChecked, checksOff, safeMode
        case lastChecked(LastCheck)
        /// The offered version, nil when the feed's isn't a plain version (U5).
        case available(String?), ready(String?)
        /// A downloaded update waits for lid-closed mode or a display trial.
        case waiting(UpdatePolicy.Wait, String?)
    }

    /// One line, most specific first: source builds, a running check, an offer (or why it waits), a failure, Safe
    /// Mode's pause, the last check, then consent.
    package static func state(_ facts: Facts) -> State {
        if facts.fromSource { return .fromSource }
        if facts.checking { return .checking }
        if let offer = facts.offer {
            // Only a downloaded update installs once the wait ends; one that isn't downloaded still offers Sparkle's
            // window, which a user check may always open (r2 C2-3).
            guard offer.readyToRestart else { return .available(offer.version) }
            if case .wait(let wait) = UpdatePolicy.decide(.installNow, facts.policy) { return .waiting(wait, offer.version) }
            return .ready(offer.version)
        }
        if facts.failed { return .failed }
        if facts.policy.safeMode && facts.automaticChecks { return .safeMode }
        if let last = facts.lastCheck { return .lastChecked(last) }
        return facts.consentDecided && !facts.automaticChecks ? .checksOff : .notChecked
    }

    /// The row's text. Install and Relaunch… shows beside `.available` and `.ready` (`offersInstall`).
    package static func text(_ state: State, uses24Hour: Bool) -> String {
        switch state {
        case .fromSource:
            return L("This copy was built from source, so it can’t update itself. Download Snaptic from GitHub Releases to get updates.")
        case .checking: return L("Checking…")
        case .failed: return L("Snaptic couldn’t check for updates. Check your connection and try again.")
        case .notChecked: return L("Not checked yet")
        case .checksOff: return L("Automatic checks are off.")
        case .safeMode: return UpdatePolicy.text(.safeMode, version: nil)
        case .lastChecked(let last): return L("Last checked ") + when(last, uses24Hour: uses24Hour)
        case .available(let version):
            guard let version else { return L("A new version is available.") }
            return L("Version ") + version + L(" is available.")
        case .ready(let version):
            guard let version else { return L("A new version is ready to install.") }
            return L("Version ") + version + L(" is ready to install.")
        case .waiting(let wait, let version): return UpdatePolicy.text(wait, version: version)
        }
    }

    package static func offersInstall(_ state: State) -> Bool {
        switch state {
        case .available, .ready: return true
        default: return false
        }
    }

    /// "today at 9:12 AM", "yesterday at 9:12 AM", "on Oct 12" (a future date, from a changed clock, reads as today).
    package static func when(_ last: LastCheck, uses24Hour: Bool) -> String {
        let time = AwakeCountdown.clock(hour: last.hour, minute: last.minute, uses24Hour: uses24Hour)
        if last.daysAgo <= 0 { return L("today at ") + time }
        if last.daysAgo == 1 { return L("yesterday at ") + time }
        return L("on ") + monthName(last.month) + " " + String(min(max(last.day, 1), 31))
    }

    private static let months = [L("Jan"), L("Feb"), L("Mar"), L("Apr"), L("May"), L("Jun"), L("Jul"), L("Aug"),
                                 L("Sep"), L("Oct"), L("Nov"), L("Dec")]

    /// Out-of-range months wrap instead of trapping.
    private static func monthName(_ month: Int) -> String {
        months[((month % 12) + 11) % 12]
    }
}

/// Snaptic's Sparkle defaults keys (E4): General › Reset clears them; backups never contain them (Backup exports only
/// Snaptic's own stores). Sparkle 2.10.0 writes exactly these into Snaptic's domain (SUConstants.m, SUAppcastDriver.m).
package enum UpdateDefaultsKeys {
    /// The user's answer to "check automatically" (set from Snaptic's own consent UI; absent = not asked yet).
    package static let automaticChecks = "SUEnableAutomaticChecks"
    package static let automaticallyUpdate = "SUAutomaticallyUpdate"
    package static let lastCheckTime = "SULastCheckTime"
    /// A feed URL some other tool wrote; the updater clears it at launch and never reads it (E2, feed pinning).
    package static let feedURL = "SUFeedURL"

    package static let all: [String] = [
        automaticChecks, automaticallyUpdate, lastCheckTime, feedURL,
        "SUHasLaunchedBefore", "SUSkippedVersion", "SUSkippedMajorVersion", "SUSkippedMajorSubreleaseVersion",
        "SUScheduledCheckInterval", "SUSendProfileInfo", "SULastProfileSubmissionDate", "SUUpdateGroupIdentifier",
        "SUInitialFailedFeedSigningValidationDate",
    ]
}
