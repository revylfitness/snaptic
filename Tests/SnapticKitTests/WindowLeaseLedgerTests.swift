import XCTest
@testable import SnapticKit

// 0.5 K4 (§2.3, §2.5, D2-5): the `WindowServices` lease ledger — the union of needs, the first-acquire and
// last-release edges, the freshness linger and where it's hosted, and M32's AX observer count.

/// Regular apps running, for the observer count.
private let regularApps = 19

final class WindowLeaseLedgerTests: XCTestCase {
    // MARK: Needs

    func testTheUnionOfNeeds() {
        var ledger = WindowLeaseLedger()
        XCTAssertTrue(ledger.union.isEmpty)
        XCTAssertFalse(ledger.isLive)
        _ = ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails, .otherSpaces], now: 0)
        _ = ledger.acquire(.dockPreviews, needs: [.thumbnails, .freshness(42)], now: 0)
        XCTAssertEqual(ledger.union, [.recency, .thumbnails, .otherSpaces, .freshness(42)])
        XCTAssertEqual(ledger.needs(of: .dockPreviews), [.thumbnails, .freshness(42)])
        XCTAssertEqual(ledger.needs(of: .awake), [])
        XCTAssertTrue(ledger.holds(.windowSwitcher))
        XCTAssertFalse(ledger.holds(.awake))
        XCTAssertTrue(ledger.recencyLive)
        _ = ledger.release(.windowSwitcher, now: 1)
        XCTAssertEqual(ledger.union, [.thumbnails, .freshness(42)])
        XCTAssertFalse(ledger.recencyLive)
    }

    // MARK: Edges

    func testTheFirstAcquireAndTheLastRelease() {
        var ledger = WindowLeaseLedger()
        XCTAssertEqual(ledger.acquire(.dockPreviews, needs: [.thumbnails], now: 0), [.startServices])
        XCTAssertEqual(ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails], now: 1), [.startRecency],
                       "only the first lease starts the services")
        XCTAssertEqual(ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails, .otherSpaces], now: 2), [],
                       "acquiring again updates the lease")
        XCTAssertEqual(ledger.release(.dockPreviews, now: 3), [.purge(.dockPreviews)])
        XCTAssertEqual(ledger.release(.windowSwitcher, now: 4),
                       [.purge(.windowSwitcher), .stopRecency, .purgeAll, .stopServices])
        XCTAssertFalse(ledger.isLive)
        XCTAssertEqual(ledger, WindowLeaseLedger())
        XCTAssertEqual(ledger.acquire(.dockPreviews, needs: [], now: 5), [.startServices], "a fresh start after")
    }

    func testReleasingAClientWithoutALeaseDoesNothing() {
        var ledger = WindowLeaseLedger()
        XCTAssertEqual(ledger.release(.dockPreviews, now: 0), [])
        _ = ledger.acquire(.windowSwitcher, needs: [.recency], now: 0)
        XCTAssertEqual(ledger.release(.dockPreviews, now: 1), [])
        XCTAssertTrue(ledger.isLive)
    }

    func testDroppingThumbnailsPurgesTheClientThenEveryone() {
        var ledger = WindowLeaseLedger()
        _ = ledger.acquire(.windowSwitcher, needs: [.thumbnails], now: 0)
        _ = ledger.acquire(.dockPreviews, needs: [.thumbnails], now: 0)
        XCTAssertEqual(ledger.update(.dockPreviews, needs: [], now: 1), [.purge(.dockPreviews)],
                       "the switcher still holds thumbnails")
        XCTAssertEqual(ledger.update(.windowSwitcher, needs: [.recency], now: 2),
                       [.purge(.windowSwitcher), .purgeAll, .startRecency])
        XCTAssertEqual(ledger.update(.windowSwitcher, needs: [.recency], now: 3), [], "nothing to drop twice")
    }

    func testReleasingTheLastThumbnailsLeasePurgesAll() {
        var ledger = WindowLeaseLedger()
        _ = ledger.acquire(.windowSwitcher, needs: [.thumbnails], now: 0)
        _ = ledger.acquire(.dockPreviews, needs: [.otherSpaces], now: 0)
        XCTAssertEqual(ledger.release(.windowSwitcher, now: 1), [.purge(.windowSwitcher), .purgeAll])
        XCTAssertTrue(ledger.isLive)
    }

    // MARK: Freshness (§2.3)

    func testFreshnessStopsTwoSecondsAfterThePanelHides() {
        var ledger = WindowLeaseLedger()
        XCTAssertEqual(ledger.acquire(.dockPreviews, needs: [.thumbnails], now: 0), [.startServices])
        XCTAssertEqual(ledger.update(.dockPreviews, needs: [.thumbnails, .freshness(42)], now: 10),
                       [.startFreshness(pid: 42, host: .own)])
        XCTAssertEqual(ledger.freshnessPIDs, [42])
        XCTAssertNil(ledger.nextDeadline)
        XCTAssertEqual(ledger.update(.dockPreviews, needs: [.thumbnails], now: 20), [])
        XCTAssertEqual(ledger.nextDeadline, 22)
        XCTAssertEqual(ledger.tick(now: 21.99), [])
        XCTAssertEqual(ledger.freshnessPIDs, [42], "still registered during the linger")
        XCTAssertEqual(ledger.tick(now: 22), [.stopFreshness(pid: 42, host: .own)])
        XCTAssertEqual(ledger.freshnessPIDs, [])
        XCTAssertNil(ledger.nextDeadline)
        XCTAssertEqual(ledger.tick(now: 30), [])
    }

    func testShowingAgainWithinTheLingerKeepsTheNotifications() {
        var ledger = WindowLeaseLedger()
        _ = ledger.acquire(.dockPreviews, needs: [.freshness(42)], now: 0)
        _ = ledger.update(.dockPreviews, needs: [], now: 10)
        XCTAssertEqual(ledger.update(.dockPreviews, needs: [.freshness(42)], now: 11), [], "no re-registration")
        XCTAssertNil(ledger.nextDeadline)
        XCTAssertEqual(ledger.tick(now: 12), [])
        XCTAssertEqual(ledger.freshnessPIDs, [42])
    }

    func testMovingToAnotherAppStartsItsNotificationsAndLingersTheOld() {
        var ledger = WindowLeaseLedger()
        _ = ledger.acquire(.dockPreviews, needs: [.freshness(42)], now: 0)
        XCTAssertEqual(ledger.update(.dockPreviews, needs: [.freshness(43)], now: 5),
                       [.startFreshness(pid: 43, host: .own)])
        XCTAssertEqual(ledger.freshnessPIDs, [42, 43])
        XCTAssertEqual(ledger.nextDeadline, 7)
        _ = ledger.update(.dockPreviews, needs: [], now: 6)
        XCTAssertEqual(ledger.nextDeadline, 7, "the earliest stop")
        XCTAssertEqual(ledger.tick(now: 8), [.stopFreshness(pid: 42, host: .own), .stopFreshness(pid: 43, host: .own)],
                       "by pid")
    }

    func testTheLastReleaseStopsFreshnessAtOnce() {
        var ledger = WindowLeaseLedger()
        _ = ledger.acquire(.dockPreviews, needs: [.freshness(42), .freshness(7)], now: 0)
        XCTAssertEqual(ledger.release(.dockPreviews, now: 1),
                       [.purge(.dockPreviews), .stopFreshness(pid: 7, host: .own), .stopFreshness(pid: 42, host: .own),
                        .purgeAll, .stopServices])
        XCTAssertNil(ledger.nextDeadline)

        _ = ledger.acquire(.dockPreviews, needs: [.freshness(42)], now: 10)
        _ = ledger.update(.dockPreviews, needs: [], now: 11)
        XCTAssertEqual(ledger.release(.dockPreviews, now: 12),
                       [.purge(.dockPreviews), .stopFreshness(pid: 42, host: .own), .purgeAll, .stopServices],
                       "a lingering registration goes too")
        XCTAssertEqual(ledger.tick(now: 13), [])
    }

    func testFreshnessRidesOnFocusTrackerWhileRecencyIsLive() {
        var ledger = WindowLeaseLedger()
        XCTAssertEqual(ledger.acquire(.windowSwitcher, needs: [.recency], now: 0), [.startServices, .startRecency])
        XCTAssertEqual(ledger.acquire(.dockPreviews, needs: [.freshness(42)], now: 1),
                       [.startFreshness(pid: 42, host: .focusTracker)])
        XCTAssertEqual(ledger.ownFreshnessObservers, 0)
        XCTAssertEqual(ledger.release(.windowSwitcher, now: 2),
                       [.purge(.windowSwitcher), .stopFreshness(pid: 42, host: .focusTracker), .stopRecency,
                        .startFreshness(pid: 42, host: .own)])
        XCTAssertEqual(ledger.freshness[42], .own)
        XCTAssertEqual(ledger.ownFreshnessObservers, 1)
    }

    func testRecencyStartingMovesFreshnessOntoFocusTracker() {
        var ledger = WindowLeaseLedger()
        XCTAssertEqual(ledger.acquire(.dockPreviews, needs: [.freshness(42)], now: 0),
                       [.startServices, .startFreshness(pid: 42, host: .own)])
        XCTAssertEqual(ledger.acquire(.windowSwitcher, needs: [.recency], now: 1),
                       [.startRecency, .stopFreshness(pid: 42, host: .own), .startFreshness(pid: 42, host: .focusTracker)])
        XCTAssertEqual(ledger.freshness[42], .focusTracker)
        _ = ledger.update(.dockPreviews, needs: [], now: 2)
        XCTAssertEqual(ledger.tick(now: 4), [.stopFreshness(pid: 42, host: .focusTracker)])
    }

    // MARK: M32's AX observer count (D2-5)

    func testDockPreviewsAloneIsTheDockPlusThePreviewedApp() {
        var ledger = WindowLeaseLedger()
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), 0, "module off")
        _ = ledger.acquire(.dockPreviews, needs: [.thumbnails, .otherSpaces], now: 0)
        XCTAssertFalse(ledger.recencyLive, "Dock Previews holds no .recency")
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), 1, "at rest: the Dock")
        _ = ledger.update(.dockPreviews, needs: [.thumbnails, .otherSpaces, .freshness(42)], now: 10)
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), 2, "a preview is up")
        _ = ledger.update(.dockPreviews, needs: [.thumbnails, .otherSpaces], now: 20)
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), 2, "during the linger")
        _ = ledger.tick(now: 22)
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), 1, "after the linger")
    }

    func testWithTheSwitcherOnAPreviewAddsNoObserver() {
        var ledger = WindowLeaseLedger()
        _ = ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails], now: 0)
        let switcherOnly = ledger.axObservers(regularApps: regularApps)
        XCTAssertEqual(switcherOnly, regularApps)
        _ = ledger.acquire(.dockPreviews, needs: [.thumbnails, .otherSpaces], now: 1)
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), switcherOnly + 1)
        _ = ledger.update(.dockPreviews, needs: [.thumbnails, .otherSpaces, .freshness(42)], now: 2)
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), switcherOnly + 1, "hosted on FocusTracker")
        _ = ledger.release(.dockPreviews, now: 3)
        XCTAssertEqual(ledger.axObservers(regularApps: regularApps), switcherOnly, "module off")
    }
}
