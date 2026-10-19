import XCTest
@testable import SnapticKit

// PLAN 0.3.1 E1, E4 (owner: T-update): the whole `UpdatePolicy.Event` matrix, the wait and status texts, the
// post-update notice and the Sparkle defaults keys.

final class UpdatePolicyTests: XCTestCase {
    private typealias Facts = UpdatePolicy.Facts

    /// Every combination of the three facts.
    private static let allFacts: [Facts] = [false, true].flatMap { lid in
        [false, true].flatMap { display in
            [false, true].map { safe in Facts(lidModeOn: lid, displayTrialPending: display, safeMode: safe) }
        }
    }

    private static let events: [UpdatePolicy.Event] = [
        .scheduledCheck, .userCheck, .relaunchAfterInstall, .installNow, .relaunch(safeMode: false),
        .relaunch(safeMode: true),
    ]

    // MARK: The matrix (E4)

    func testMatrix() {
        for facts in Self.allFacts {
            for event in Self.events {
                let expected: UpdatePolicy.Decision
                switch event {
                case .scheduledCheck:
                    expected = facts.safeMode ? .refuse : .allow
                case .userCheck:
                    expected = .allow
                case .relaunchAfterInstall, .installNow:
                    if facts.lidModeOn { expected = .wait(.lidClosed) }
                    else if facts.displayTrialPending { expected = .wait(.displayTrial) }
                    else { expected = .allow }
                case .relaunch(let safeMode):
                    expected = safeMode ? .refuse : .allow
                }
                XCTAssertEqual(UpdatePolicy.decide(event, facts), expected, "\(event) with \(facts)")
            }
        }
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

    func testRelauncherNeverTradesASafeModeRelaunchForAnUpdate() {
        for facts in Self.allFacts {
            XCTAssertEqual(UpdatePolicy.decide(.relaunch(safeMode: true), facts), .refuse)
            XCTAssertEqual(UpdatePolicy.decide(.relaunch(safeMode: false), facts), .allow)
        }
    }

    // MARK: Wait texts (E1)

    func testWaitPriorityAndTexts() {
        XCTAssertNil(UpdatePolicy.wait(Facts(lidModeOn: false, displayTrialPending: false, safeMode: false)))
        XCTAssertNil(UpdatePolicy.waitText(Facts(lidModeOn: false, displayTrialPending: false, safeMode: false),
                                           version: "0.3.2"))
        XCTAssertEqual(UpdatePolicy.wait(Facts(lidModeOn: true, displayTrialPending: true, safeMode: true)), .lidClosed)
        XCTAssertEqual(UpdatePolicy.wait(Facts(lidModeOn: false, displayTrialPending: true, safeMode: true)), .displayTrial)
        XCTAssertEqual(UpdatePolicy.wait(Facts(lidModeOn: false, displayTrialPending: false, safeMode: true)), .safeMode)
        XCTAssertEqual(UpdatePolicy.waitText(Facts(lidModeOn: true, displayTrialPending: false, safeMode: false),
                                             version: "0.3.2"),
                       "Version 0.3.2 will install when lid-closed mode ends.")
        XCTAssertEqual(UpdatePolicy.waitText(Facts(lidModeOn: false, displayTrialPending: true, safeMode: false),
                                             version: "0.3.2"),
                       "Version 0.3.2 will install when the display change is kept or undone.")
        XCTAssertEqual(UpdatePolicy.waitText(Facts(lidModeOn: false, displayTrialPending: false, safeMode: true),
                                             version: "0.3.2"),
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
