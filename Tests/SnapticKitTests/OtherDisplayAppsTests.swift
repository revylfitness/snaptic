import XCTest
@testable import SnapticKit

final class OtherDisplayAppsTests: XCTestCase {
    func testDetectionByPrefix() {
        let running = ["com.apple.finder", "pro.betterdisplay.BetterDisplay", "me.guillaumeb.MonitorControl",
                       "fyi.lunar.Lunar.beta"]
        XCTAssertEqual(OtherDisplayApps.detect(bundleIDs: running).map(\.id), ["betterdisplay", "monitorcontrol", "lunar"])
        XCTAssertTrue(OtherDisplayApps.detect(bundleIDs: ["pro.betterdisplayx", "fyi.lunarx"]).isEmpty)
        XCTAssertTrue(OtherDisplayApps.detect(bundleIDs: []).isEmpty)
    }

    func testPausedFeaturesFollowPolicy() {
        let apps = OtherDisplayApps.detect(bundleIDs: ["me.guillaumeb.MonitorControl"])
        let paused = OtherDisplayApps.paused(running: apps, policy: .pauseOverlapping)
        XCTAssertEqual(paused[.brightnessDDC]?.name, "MonitorControl")
        XCTAssertNil(paused[.resolution])
        XCTAssertTrue(OtherDisplayApps.paused(running: apps, policy: .runBoth).isEmpty)
    }

    func testAlwaysOnFeaturesAreNeverPaused() {
        let paused = OtherDisplayApps.paused(running: OtherDisplayApps.known, policy: .pauseOverlapping)
        for feature in FeatureGraph.alwaysOn { XCTAssertNil(paused[feature]) }
    }

    func testFirstRunningAppNamesThePause() {
        let apps = OtherDisplayApps.detect(bundleIDs: ["fyi.lunar.Lunar", "pro.betterdisplay.BetterDisplay"])
        XCTAssertEqual(OtherDisplayApps.paused(running: apps, policy: .pauseOverlapping)[.ddcControls]?.id, "betterdisplay")
        XCTAssertEqual(OtherDisplayApps.pauseReason(apps[0]), "Paused while BetterDisplay runs")
        XCTAssertEqual(OtherDisplayApps.menuPauseReason(apps[0]), "Paused While BetterDisplay Runs")
    }

    func testKnownListIsWellFormed() {
        XCTAssertEqual(Set(OtherDisplayApps.known.map(\.id)).count, OtherDisplayApps.known.count)
        for app in OtherDisplayApps.known {
            XCTAssertFalse(app.bundlePrefixes.isEmpty)
            XCTAssertFalse(app.overlapping.isEmpty)
        }
    }
}
