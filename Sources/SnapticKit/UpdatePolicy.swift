import Foundation

// In-app updates, pure parts (owner: T-update; PLAN 0.3.1 E1, E4): when a check, an install or a relaunch must wait,
// the About page's status row, the post-update notice, and the Sparkle defaults keys (the only home of `SU*` key
// strings, lint L19). The app (UpdaterController) only gathers facts and calls these.

/// An update Sparkle found (gentle reminders): what the menu row and About's status row offer.
package struct UpdateOffer: Equatable, Sendable {
    /// "0.3.2".
    package var version: String
    /// Downloaded, and installs at quit: the menu row reads "Restart to Update Snaptic…".
    package var readyToRestart: Bool

    package init(version: String, readyToRestart: Bool) {
        self.version = version
        self.readyToRestart = readyToRestart
    }
}

package enum UpdatePolicy {
    /// The constant feed (E3). The updater's delegate returns it, so a `SUFeedURL` written into Snaptic's defaults
    /// can't redirect checks (E2, feed pinning).
    package static let feedURL = "https://github.com/revylfitness/snaptic/releases/latest/download/appcast.xml"
    /// Check for Updates… in builds without Sparkle, and the source of every release.
    package static let releasesURL = "https://github.com/revylfitness/snaptic/releases"

    /// What can hold an install or relaunch back (E4).
    package struct Facts: Equatable, Sendable {
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
        /// Relauncher quits this copy and a downloaded update waits for quit: install it on the way. `safeMode`:
        /// the relaunch enters or leaves Safe Mode, which must never be traded for an update.
        case relaunch(safeMode: Bool)
    }

    package enum Decision: Equatable, Sendable {
        case allow
        case wait(Wait)
        /// The event doesn't happen at all (a scheduled check in Safe Mode; Relauncher's own relaunch instead).
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
        case .relaunch(let safeMode):
            // Quitting ends lid-closed mode and display trials anyway (E4), so only a Safe Mode relaunch opts out.
            return safeMode ? .refuse : .allow
        }
    }

    /// The deferral line of About's status row (E1, E4), most important first: nil = nothing waits. Safe Mode only
    /// pauses automatic checks, so its line shows whatever is offered.
    package static func wait(_ facts: Facts) -> Wait? {
        if facts.lidModeOn { return .lidClosed }
        if facts.displayTrialPending { return .displayTrial }
        if facts.safeMode { return .safeMode }
        return nil
    }

    /// nil = go ahead; otherwise the deferral line ("Version 0.3.2 will install when lid-closed mode ends.").
    package static func waitText(_ facts: Facts, version: String) -> String? {
        wait(facts).map { text($0, version: version) }
    }

    /// The deferral line for `wait` (also the toast when Install and Relaunch… is clicked while it waits).
    package static func text(_ wait: Wait, version: String) -> String {
        switch wait {
        case .lidClosed: return L("Version ") + version + L(" will install when lid-closed mode ends.")
        case .displayTrial: return L("Version ") + version + L(" will install when the display change is kept or undone.")
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
        case available(String), ready(String)
        /// An offer waits for lid-closed mode or a display trial.
        case waiting(UpdatePolicy.Wait, String)
    }

    /// One line, most specific first: source builds, a running check, an offer (or why it waits), a failure, Safe
    /// Mode's pause, the last check, then consent.
    package static func state(_ facts: Facts) -> State {
        if facts.fromSource { return .fromSource }
        if facts.checking { return .checking }
        if let offer = facts.offer {
            if case .wait(let wait) = UpdatePolicy.decide(.installNow, facts.policy) { return .waiting(wait, offer.version) }
            return offer.readyToRestart ? .ready(offer.version) : .available(offer.version)
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
        case .safeMode: return UpdatePolicy.text(.safeMode, version: "")
        case .lastChecked(let last): return L("Last checked ") + when(last, uses24Hour: uses24Hour)
        case .available(let version): return L("Version ") + version + L(" is available.")
        case .ready(let version): return L("Version ") + version + L(" is ready to install.")
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
