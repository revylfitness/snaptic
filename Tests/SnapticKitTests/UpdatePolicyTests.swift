import XCTest
@testable import SnapticKit

// PLAN 0.3.1 E1, E4 (owner: T-update): the whole `UpdatePolicy.Event` matrix (hand-written), the update session and
// Relauncher's routes, the updater gate, the wait and status texts, the post-update notice and the Sparkle defaults keys.

final class UpdatePolicyTests: XCTestCase {
    private typealias Facts = UpdatePolicy.Facts

    /// Every combination of the three facts.
    private static let allFacts: [Facts] = [false, true].flatMap { lid in
        [false, true].flatMap { display in
            [false, true].map { safe in Facts(lidModeOn: lid, displayTrialPending: display, safeMode: safe) }
        }
    }

    // MARK: The matrix (E4), written out by hand (r1 C9)

    /// Expected decisions per event, in `allFacts` order: (lid, display, safe) = 000, 001, 010, 011, 100, 101, 110, 111.
    func testMatrix() {
        let A = UpdatePolicy.Decision.allow, R = UpdatePolicy.Decision.refuse
        let W = UpdatePolicy.Decision.wait(.lidClosed), D = UpdatePolicy.Decision.wait(.displayTrial)
        let table: [(UpdatePolicy.Event, [UpdatePolicy.Decision])] = [
            (.scheduledCheck,       [A, R, A, R, A, R, A, R]),
            (.userCheck,            [A, A, A, A, A, A, A, A]),
            (.relaunchAfterInstall, [A, A, D, D, W, W, W, W]),
            (.installNow,           [A, A, D, D, W, W, W, W]),
        ]
        XCTAssertEqual(Self.allFacts.count, 8)
        for (event, expected) in table {
            for (facts, decision) in zip(Self.allFacts, expected) {
                XCTAssertEqual(UpdatePolicy.decide(event, facts), decision, "\(event) with \(facts)")
            }
        }
        // Independent anchors: how many of the 32 cells go ahead, wait for the lid, or are refused.
        let all = table.flatMap { row in Self.allFacts.map { UpdatePolicy.decide(row.0, $0) } }
        XCTAssertEqual(all.filter { $0 == A }.count, 16)
        XCTAssertEqual(all.filter { $0 == W }.count, 8)
        XCTAssertEqual(all.filter { $0 == D }.count, 4)
        XCTAssertEqual(all.filter { $0 == R }.count, 4)
    }

    func testScheduledChecksStopInSafeModeButTheUserCanAlwaysCheck() {
        let safe = Facts(lidModeOn: false, displayTrialPending: false, safeMode: true)
        XCTAssertEqual(UpdatePolicy.decide(.scheduledCheck, safe), .refuse)
        XCTAssertEqual(UpdatePolicy.decide(.userCheck, safe), .allow)
        // A user-chosen update installs in Safe Mode, so a crash-looping release can be fixed.
        XCTAssertEqual(UpdatePolicy.decide(.installNow, safe), .allow)
    }

    func testNothingRelaunchesWhileLidClosedModeIsOn() {
        for facts in Self.allFacts where facts.lidModeOn {
            XCTAssertEqual(UpdatePolicy.decide(.relaunchAfterInstall, facts), .wait(.lidClosed))
            XCTAssertEqual(UpdatePolicy.decide(.installNow, facts), .wait(.lidClosed))
        }
    }

    // MARK: Lid-closed mode holds updates while it turns on or off too (r1 C7)

    func testLidModeHoldsUpdatesUnlessOffOrFailed() {
        let token = String(repeating: "a", count: 32)
        XCTAssertFalse(UpdatePolicy.holdsUpdates(.off))
        XCTAssertFalse(UpdatePolicy.holdsUpdates(.failed(.verify)))
        XCTAssertTrue(UpdatePolicy.holdsUpdates(.authorizing(token: token)))
        XCTAssertTrue(UpdatePolicy.holdsUpdates(.verifying(token: token, pid: 42)))
        XCTAssertTrue(UpdatePolicy.holdsUpdates(.on(token: token, pid: 42, until: 100)))
        XCTAssertTrue(UpdatePolicy.holdsUpdates(.stopping(token: token)))
    }

    // MARK: The update session (r1 C2, S9)

    func testAResumedInstallKeepsRestartToUpdate() {
        // Downloaded silently, installs at quit; later Sparkle resumes it as a gentle reminder in the installing stage.
        var session = UpdateSession()
        session.apply(.installsOnQuit(version: "0.3.2"))
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: true))
        session.apply(.found(version: "0.3.2", installing: true))
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: true))
        // Even a reminder that doesn't say "installing" never downgrades a waiting install.
        session.apply(.found(version: "0.3.2", installing: false))
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: true))
        session.apply(.attentionOrFinished)
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: true))
        XCTAssertTrue(session.installWaits)
    }

    func testAnInstallingReminderWithoutABlockIsReadyToo() {
        var session = UpdateSession()
        session.apply(.found(version: "0.3.2", installing: true))
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: true))
        XCTAssertTrue(session.installWaits)
        XCTAssertFalse(session.hasInstallBlock)
    }

    func testAnOfferThatDoesntWaitGoesWithSparklesWindow() {
        var session = UpdateSession()
        session.apply(.found(version: "0.3.2", installing: false))
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: false))
        session.apply(.attentionOrFinished)
        XCTAssertNil(session.offer)
        XCTAssertFalse(session.installWaits)
    }

    func testTheInstallBlockDiesWithItsCycle() {
        var session = UpdateSession()
        session.apply(.installsOnQuit(version: "0.3.2"))
        XCTAssertTrue(session.hasInstallBlock)
        session.apply(.cycleFinished(failed: false))
        XCTAssertFalse(session.hasInstallBlock)
        // The installer may still wait: the row stays, and Relauncher no longer hands over to a dead block.
        XCTAssertTrue(session.installWaits)
        XCTAssertEqual(session.offer, UpdateOffer(version: "0.3.2", readyToRestart: true))

        var failed = UpdateSession()
        failed.apply(.installsOnQuit(version: "0.3.2"))
        failed.apply(.cycleFinished(failed: true))
        XCTAssertFalse(failed.hasInstallBlock)
        XCTAssertFalse(failed.installWaits)
        XCTAssertNil(failed.offer)

        var used = UpdateSession()
        used.apply(.installsOnQuit(version: "0.3.2"))
        used.apply(.installStarted)
        XCTAssertFalse(used.hasInstallBlock)
        XCTAssertTrue(used.installWaits)
    }

    // MARK: Relauncher (r1 C3, S9)

    func testRelaunchRoutes() {
        let idle = UpdateSession()
        var live = UpdateSession()
        live.apply(.installsOnQuit(version: "0.3.2"))
        var dead = live
        dead.apply(.cycleFinished(failed: false))
        var resumed = UpdateSession()
        resumed.apply(.found(version: "0.3.2", installing: true))

        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: false, session: idle), .normal)
        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: true, session: idle), .normal)
        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: false, session: live), .throughUpdate)
        // A Safe Mode relaunch never installs the waiting update, and never starts beside Sparkle's installer.
        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: true, session: live), .quitFirst)
        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: false, session: dead), .quitFirst)
        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: true, session: dead), .quitFirst)
        XCTAssertEqual(UpdatePolicy.relaunchRoute(safeMode: false, session: resumed), .quitFirst)
        XCTAssertEqual(UpdatePolicy.quitFirstText(safeMode: false),
                       "Quit Snaptic to finish installing the update, then open it again.")
        XCTAssertEqual(UpdatePolicy.quitFirstText(safeMode: true),
                       "Quit Snaptic to finish installing the update first, then hold ⇧ while you open it to start in Safe Mode.")
    }

    // MARK: The updater gate (r1 C8)

    func testTheUpdaterStartsOnlyInAnAppBundleWithAKey() {
        let key = "P/QyXVQX6nBYXfuNXlR8trb8+r8A5zyYAQEVyYucW4k="
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: true, bundleExtension: "app", publicKey: key), .ready)
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: false, bundleExtension: "app", publicKey: key), .noSparkle)
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: true, bundleExtension: "", publicKey: key), .notAppBundle)
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: true, bundleExtension: "debug", publicKey: nil), .notAppBundle)
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: true, bundleExtension: "app", publicKey: nil), .noPublicKey)
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: true, bundleExtension: "app", publicKey: ""), .noPublicKey)
        XCTAssertEqual(UpdatePolicy.gate(sparkleLoaded: true, bundleExtension: "app", publicKey: "AAAA"), .noPublicKey)
        XCTAssertEqual(UpdatePolicy.publicKeyInfoKey, "SUPublicEDKey")
    }

    // MARK: Texts (E1), with and without a plain version (r1 U5)

    func testMenuTitles() {
        XCTAssertEqual(UpdatePolicy.menuTitle(UpdateOffer(version: "0.3.2", readyToRestart: false)),
                       "Update Available: Snaptic 0.3.2…")
        XCTAssertEqual(UpdatePolicy.menuTitle(UpdateOffer(version: nil, readyToRestart: false)), "Update Available: Snaptic…")
        XCTAssertEqual(UpdatePolicy.menuTitle(UpdateOffer(version: "0.3.2-b1", readyToRestart: false)),
                       "Update Available: Snaptic…")
        XCTAssertEqual(UpdatePolicy.menuTitle(UpdateOffer(version: "0.3.2", readyToRestart: true)), "Restart to Update Snaptic…")
        XCTAssertEqual(UpdatePolicy.menuTitle(UpdateOffer(version: nil, readyToRestart: true)), "Restart to Update Snaptic…")
        // Only plain versions are kept.
        XCTAssertNil(UpdateOffer(version: "0.4", readyToRestart: false).version)
        XCTAssertEqual(UpdateOffer(version: "0.3.2", readyToRestart: false).version, "0.3.2")
    }

    func testWaitTexts() {
        XCTAssertEqual(UpdatePolicy.text(.lidClosed, version: "0.3.2"), "Version 0.3.2 will install when lid-closed mode ends.")
        XCTAssertEqual(UpdatePolicy.text(.lidClosed, version: nil), "The update will install when lid-closed mode ends.")
        XCTAssertEqual(UpdatePolicy.text(.displayTrial, version: "0.3.2"),
                       "Version 0.3.2 will install when the display change is kept or undone.")
        XCTAssertEqual(UpdatePolicy.text(.displayTrial, version: nil),
                       "The update will install when the display change is kept or undone.")
        XCTAssertEqual(UpdatePolicy.text(.safeMode, version: "0.3.2"),
                       "Updates are paused in Safe Mode. Choose Check for Updates… to update anyway.")
    }

    // MARK: Versions, URLs, errors, ownership

    func testVersionsAreThreeShortNumbers() {
        for good in ["0.3.2", "1.0.0", "10.20.30", "0.0.0", "9999.0.1"] { XCTAssertTrue(UpdatePolicy.isVersion(good), good) }
        for bad in ["", "0.3", "0.3.2.1", "v0.3.2", "0.3.x", "0..2", "0.3.2 ", " 0.3.2", "00000.1.2", "0.3.-2",
                    "٣.٣.٣", "0.3.2\n", "0.3.2/../x", "1e3.0.0"] {
            XCTAssertFalse(UpdatePolicy.isVersion(bad), bad)
        }
    }

    func testReleaseNotesURLOnlyForAValidVersion() {
        XCTAssertEqual(UpdatePolicy.releaseNotesURL(version: "0.3.2"),
                       "https://github.com/revylfitness/snaptic/releases/tag/v0.3.2")
        XCTAssertNil(UpdatePolicy.releaseNotesURL(version: "0.3.2?x=1"))
        XCTAssertNil(UpdatePolicy.releaseNotesURL(version: "../../evil"))
        XCTAssertEqual(UpdatePolicy.feedURL, "https://github.com/revylfitness/snaptic/releases/latest/download/appcast.xml")
        XCTAssertTrue(UpdatePolicy.feedURL.hasPrefix("https://"))
    }

    func testCheckFailures() {
        XCTAssertFalse(UpdatePolicy.checkFailed(sparkleDomain: true, code: 1001))   // no update
        XCTAssertFalse(UpdatePolicy.checkFailed(sparkleDomain: true, code: 4007))   // canceled
        XCTAssertFalse(UpdatePolicy.checkFailed(sparkleDomain: true, code: 4008))   // authorize later
        for code in [1000, 1002, 2001, 3001, 3002, 4005] {
            XCTAssertTrue(UpdatePolicy.checkFailed(sparkleDomain: true, code: code), "\(code)")
        }
        XCTAssertTrue(UpdatePolicy.checkFailed(sparkleDomain: false, code: 1001))   // e.g. NSURLErrorDomain
        XCTAssertTrue(UpdatePolicy.checkFailed(sparkleDomain: false, code: -1009))
    }

    func testOnlyAWritableCopyOwnedByTheUserInstallsWithoutAPassword() {
        for bundle in [false, true] {
            for parent in [false, true] {
                for owned in [false, true] {
                    XCTAssertEqual(UpdatePolicy.needsAdministrator(bundleWritable: bundle, parentWritable: parent,
                                                                   ownedByUser: owned),
                                   !(bundle && parent && owned))
                }
            }
        }
    }

    func testUpdatedNoticeOnlyForTheVersionSparkleInstalled() {
        XCTAssertEqual(UpdatePolicy.updatedNotice(recorded: "0.3.2", running: "0.3.2"), "Snaptic was updated to 0.3.2.")
        XCTAssertNil(UpdatePolicy.updatedNotice(recorded: nil, running: "0.3.2"))          // manual install
        XCTAssertNil(UpdatePolicy.updatedNotice(recorded: "0.3.2", running: "0.3.1"))      // the install failed
        XCTAssertNil(UpdatePolicy.updatedNotice(recorded: "x", running: "x"))
    }

    // MARK: About's status row (E1)

    private let last = UpdateStatusText.LastCheck(daysAgo: 0, month: 10, day: 12, hour: 9, minute: 12)

    func testStatusPriority() {
        typealias S = UpdateStatusText
        let offer = UpdateOffer(version: "0.3.2", readyToRestart: false)
        let ready = UpdateOffer(version: "0.3.2", readyToRestart: true)
        let lid = Facts(lidModeOn: true, displayTrialPending: false, safeMode: false)
        let safe = Facts(lidModeOn: false, displayTrialPending: false, safeMode: true)
        XCTAssertEqual(S.state(S.Facts(fromSource: true, checking: true, offer: offer)), .fromSource)
        XCTAssertEqual(S.state(S.Facts(checking: true, failed: true, offer: offer)), .checking)
        XCTAssertEqual(S.state(S.Facts(failed: true, offer: offer)), .available("0.3.2"))
        XCTAssertEqual(S.state(S.Facts(offer: ready)), .ready("0.3.2"))
        XCTAssertEqual(S.state(S.Facts(offer: ready, policy: lid)), .waiting(.lidClosed, "0.3.2"))
        XCTAssertEqual(S.state(S.Facts(offer: ready, policy: safe)), .ready("0.3.2"))
        XCTAssertEqual(S.state(S.Facts(failed: true, automaticChecks: true, lastCheck: last, policy: safe)), .failed)
        XCTAssertEqual(S.state(S.Facts(automaticChecks: true, lastCheck: last, policy: safe)), .safeMode)
        XCTAssertEqual(S.state(S.Facts(automaticChecks: false, consentDecided: true, lastCheck: last, policy: safe)),
                       .lastChecked(last))
        XCTAssertEqual(S.state(S.Facts(automaticChecks: true, lastCheck: last)), .lastChecked(last))
        XCTAssertEqual(S.state(S.Facts(automaticChecks: false, consentDecided: true)), .checksOff)
        XCTAssertEqual(S.state(S.Facts(automaticChecks: false, consentDecided: false)), .notChecked)
        XCTAssertEqual(S.state(S.Facts(automaticChecks: true, consentDecided: true)), .notChecked)
    }

    func testStatusTexts() {
        typealias S = UpdateStatusText
        XCTAssertEqual(S.text(.fromSource, uses24Hour: false),
                       "This copy was built from source, so it can’t update itself. Download Snaptic from GitHub Releases to get updates.")
        XCTAssertEqual(S.text(.checking, uses24Hour: false), "Checking…")
        XCTAssertEqual(S.text(.failed, uses24Hour: false),
                       "Snaptic couldn’t check for updates. Check your connection and try again.")
        XCTAssertEqual(S.text(.notChecked, uses24Hour: false), "Not checked yet")
        XCTAssertEqual(S.text(.checksOff, uses24Hour: false), "Automatic checks are off.")
        XCTAssertEqual(S.text(.safeMode, uses24Hour: false),
                       "Updates are paused in Safe Mode. Choose Check for Updates… to update anyway.")
        XCTAssertEqual(S.text(.available("0.3.2"), uses24Hour: false), "Version 0.3.2 is available.")
        XCTAssertEqual(S.text(.ready("0.3.2"), uses24Hour: false), "Version 0.3.2 is ready to install.")
        XCTAssertEqual(S.text(.available(nil), uses24Hour: false), "A new version is available.")
        XCTAssertEqual(S.text(.ready(nil), uses24Hour: false), "A new version is ready to install.")
        XCTAssertEqual(S.text(.waiting(.lidClosed, nil), uses24Hour: false),
                       "The update will install when lid-closed mode ends.")
        XCTAssertEqual(S.text(.waiting(.displayTrial, "0.3.2"), uses24Hour: false),
                       "Version 0.3.2 will install when the display change is kept or undone.")
        XCTAssertEqual(S.text(.lastChecked(last), uses24Hour: false), "Last checked today at 9:12 AM")
        XCTAssertEqual(S.text(.lastChecked(last), uses24Hour: true), "Last checked today at 09:12")
        XCTAssertTrue(S.offersInstall(.available("0.3.2")))
        XCTAssertTrue(S.offersInstall(.ready("0.3.2")))
        XCTAssertFalse(S.offersInstall(.waiting(.lidClosed, "0.3.2")))
        XCTAssertFalse(S.offersInstall(.checking))
    }

    func testLastCheckedIsHandFormatted() {
        typealias Check = UpdateStatusText.LastCheck
        XCTAssertEqual(UpdateStatusText.when(Check(daysAgo: 1, month: 10, day: 11, hour: 21, minute: 5), uses24Hour: false),
                       "yesterday at 9:05 PM")
        XCTAssertEqual(UpdateStatusText.when(Check(daysAgo: 7, month: 10, day: 12, hour: 9, minute: 12), uses24Hour: false),
                       "on Oct 12")
        XCTAssertEqual(UpdateStatusText.when(Check(daysAgo: 400, month: 1, day: 3, hour: 0, minute: 0), uses24Hour: true),
                       "on Jan 3")
        XCTAssertEqual(UpdateStatusText.when(Check(daysAgo: 2, month: 12, day: 31, hour: 0, minute: 0), uses24Hour: true),
                       "on Dec 31")
        // A clock set back reads as today; odd components never trap.
        XCTAssertEqual(UpdateStatusText.when(Check(daysAgo: -3, month: 10, day: 12, hour: 0, minute: 0), uses24Hour: false),
                       "today at 12:00 AM")
        for month in [Int.min, -13, -1, 0, 13, 25, Int.max] {
            XCTAssertTrue(UpdateStatusText.when(Check(daysAgo: 9, month: month, day: Int.max, hour: Int.min, minute: Int.max),
                                                uses24Hour: false).hasPrefix("on "))
        }
    }

    // MARK: Defaults keys (E4)

    func testDefaultsKeysAreSparklesOwn() {
        let keys = UpdateDefaultsKeys.all
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("SU") })
        for key in [UpdateDefaultsKeys.automaticChecks, UpdateDefaultsKeys.automaticallyUpdate,
                    UpdateDefaultsKeys.lastCheckTime, UpdateDefaultsKeys.feedURL] {
            XCTAssertTrue(keys.contains(key), key)
        }
        XCTAssertEqual(UpdateDefaultsKeys.automaticChecks, "SUEnableAutomaticChecks")
        XCTAssertEqual(UpdateDefaultsKeys.automaticallyUpdate, "SUAutomaticallyUpdate")
        // None of Snaptic's own keys: Reset clears these, and they never reach a backup.
        XCTAssertFalse(keys.contains { $0.hasPrefix("Snaptic") })
    }
}
