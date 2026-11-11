import XCTest
@testable import SnapticKit

/// 0.4 A3: the rules `IconsMonitors` executes (§4.6, §4.10, §4.11). Frames use the A3 probe's layout: a 2560 × 1440
/// primary screen with a 30 pt bar and a 1728 × 1117 notched screen to its left.
final class IconsMonitorRulesTests: XCTestCase {
    private let primary = IconsRect(x: 0, y: 0, width: 2560, height: 1440)
    private let side = IconsRect(x: -1728, y: 323, width: 1728, height: 1117)
    private let own: Int32 = 1

    private var bands: [IconsRect] {
        [IconsBand.band(primary, thickness: 22, visibleTopInset: 30),
         IconsBand.band(side, thickness: 22, safeAreaTop: 32, visibleTopInset: 33)]
    }

    // MARK: Band

    func testBandUsesTheTallestOfThicknessNotchAndRealBar() {
        XCTAssertEqual(IconsBand.band(primary, thickness: 22), IconsRect(x: 0, y: 1418, width: 2560, height: 22))
        XCTAssertEqual(IconsBand.band(primary, thickness: 22, visibleTopInset: 30).minY, 1410)
        XCTAssertEqual(IconsBand.band(side, thickness: 22, safeAreaTop: 32).height, 32)
        let screen = IconsScreen(frame: side, safeAreaTop: 32)
        XCTAssertEqual(IconsBand.band(screen, thickness: 22, visibleTopInset: 33).height, 33)
        // Non-finite parts are ignored; the band never exceeds the screen.
        XCTAssertEqual(IconsBand.band(primary, thickness: .nan, visibleTopInset: 30).height, 30)
        XCTAssertEqual(IconsBand.band(IconsRect(x: 0, y: 0, width: 10, height: 5), thickness: 22).height, 5)
    }

    func testPointerInBand() {
        XCTAssertTrue(IconsBand.contains(bands, x: 100, y: 1440))      // the top edge
        XCTAssertTrue(IconsBand.contains(bands, x: 100, y: 1410))
        XCTAssertFalse(IconsBand.contains(bands, x: 100, y: 1409.5))
        XCTAssertTrue(IconsBand.contains(bands, x: -10, y: 1420))      // the side screen's band
        XCTAssertFalse(IconsBand.contains(bands, x: 2560, y: 1420))     // past the right edge
        XCTAssertFalse(IconsBand.contains([], x: 0, y: 1440))
    }

    // MARK: Window guards

    private func window(_ layer: Int, _ x: Double, _ cgY: Double, _ w: Double, _ h: Double, pid: Int32 = 50,
                        owner: String? = "App", alpha: Double = 1) -> IconsWindowInfo {
        // CG bounds (top-left, y down) to AppKit, as the app converts them.
        IconsWindowInfo(layer: layer, frame: IconsRect(x: x, y: 1440 - cgY - h, width: w, height: h), pid: pid,
                        owner: owner, alpha: alpha)
    }

    func testMenuOpen() {
        // The probe's open menu: layer 101 hanging from y 27 under a 30 pt bar.
        XCTAssertTrue(IconsWindowGuard.menuOpen([window(101, 1421, 27, 470, 405)], bands: bands, ownPID: own))
        // Control Center's panel at 25 counts; another app's 25 doesn't.
        XCTAssertTrue(IconsWindowGuard.menuOpen([window(25, 2000, 30, 300, 400, owner: "ControlCenter")],
                                                bands: bands, ownPID: own))
        XCTAssertFalse(IconsWindowGuard.menuOpen([window(25, 2000, 30, 300, 400)], bands: bands, ownPID: own))
        // A context menu in the middle of the screen, Snaptic's own menu, a transparent one: no.
        XCTAssertFalse(IconsWindowGuard.menuOpen([window(101, 500, 600, 200, 300)], bands: bands, ownPID: own))
        XCTAssertFalse(IconsWindowGuard.menuOpen([window(101, 1421, 27, 470, 405, pid: own)], bands: bands,
                                                 ownPID: own))
        XCTAssertFalse(IconsWindowGuard.menuOpen([window(101, 1421, 27, 470, 405, alpha: 0)], bands: bands,
                                                 ownPID: own))
        // A status item's own window, inside the band: no.
        XCTAssertFalse(IconsWindowGuard.menuOpen([window(25, 1000, 0, 30, 30, owner: "ControlCenter")],
                                                 bands: bands, ownPID: own))
    }

    func testPopoverNearBand() {
        let extraApp: Set<Int32> = [77]
        XCTAssertTrue(IconsWindowGuard.popoverNearBand([window(26, 900, 60, 300, 300)], bands: bands,
                                                       extraPIDs: [], ownPID: own))      // 30 pt below the bar
        XCTAssertFalse(IconsWindowGuard.popoverNearBand([window(26, 900, 80, 300, 300)], bands: bands,
                                                        extraPIDs: [], ownPID: own))     // 50 pt below
        XCTAssertTrue(IconsWindowGuard.popoverNearBand([window(3, 900, 40, 300, 300, pid: 77)], bands: bands,
                                                       extraPIDs: extraApp, ownPID: own))
        XCTAssertFalse(IconsWindowGuard.popoverNearBand([window(3, 900, 40, 300, 300, pid: 78)], bands: bands,
                                                        extraPIDs: extraApp, ownPID: own))
        // The probe's overlays: transparent full-screen windows at 25–27, notch apps far above 101, 1 pt markers.
        let overlays = [window(26, 0, 0, 2560, 1440, alpha: 0), window(2_147_483_628, 968, 0, 624, 320),
                        window(1000, 0, 1439, 1, 1, alpha: 0.01), window(24, 0, 0, 2560, 30, owner: "Window Server")]
        XCTAssertFalse(IconsWindowGuard.popoverNearBand(overlays, bands: bands, extraPIDs: [], ownPID: own))
        // Wholly inside the band: a status item, not a popover.
        XCTAssertFalse(IconsWindowGuard.popoverNearBand([window(25, 1000, 0, 30, 30)], bands: bands, extraPIDs: [],
                                                        ownPID: own))
    }

    func testDistance() {
        let a = IconsRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(IconsWindowGuard.distance(a, IconsRect(x: 5, y: 5, width: 10, height: 10)), 0)
        XCTAssertEqual(IconsWindowGuard.distance(a, IconsRect(x: 0, y: 30, width: 10, height: 10)), 20)
        XCTAssertEqual(IconsWindowGuard.distance(a, IconsRect(x: 13, y: 14, width: 1, height: 1)), 5)
    }

    func testFullScreenNeedsBothSignals() {
        let cover = window(0, 0, 0, 2560, 1440, pid: 9)
        XCTAssertTrue(IconsWindowGuard.fullScreen([cover], screen: primary, frontPID: 9, systemFullScreen: true))
        XCTAssertFalse(IconsWindowGuard.fullScreen([cover], screen: primary, frontPID: 9, systemFullScreen: false))
        XCTAssertFalse(IconsWindowGuard.fullScreen([cover], screen: primary, frontPID: 8, systemFullScreen: true))
        XCTAssertFalse(IconsWindowGuard.fullScreen([cover], screen: side, frontPID: 9, systemFullScreen: true))
        XCTAssertFalse(IconsWindowGuard.fullScreen([window(0, 0, 30, 2560, 1322, pid: 9)], screen: primary,
                                                   frontPID: 9, systemFullScreen: true))
    }

    // MARK: Presentation options

    func testPresentationFlags() {
        XCTAssertEqual(IconsPresentationFlag.flags(0), [])
        XCTAssertEqual(IconsPresentationFlag.flags(1 << 5), [.disableProcessSwitching])
        XCTAssertEqual(IconsPresentationFlag.flags((1 << 6) | (1 << 7) | (1 << 10) | 1),
                       [.disableForceQuit, .disableSessionTermination])
        XCTAssertEqual(IconsPresentationFlag.fullScreenBit, 1024)
        XCTAssertTrue(IconsExamGuard.active(system: IconsPresentationFlag.flags(1 << 5)))
        XCTAssertFalse(IconsExamGuard.active(system: IconsPresentationFlag.flags(1 << 5),
                                             own: IconsPresentationFlag.flags(1 << 5)))
    }

    // MARK: MenuBarAgent, launches, hiders

    func testAgentWatch() {
        let path = "/System/Library/CoreServices/MenuBarAgent.app"
        XCTAssertEqual(IconsAgentWatch.event(launched: false, bundleID: "com.apple.MenuBarAgent", bundlePath: path),
                       .agentTerminated)
        XCTAssertEqual(IconsAgentWatch.event(launched: true, bundleID: "com.apple.MenuBarAgent",
                                             bundlePath: path + "/"), .agentLaunched)
        XCTAssertNil(IconsAgentWatch.event(launched: true, bundleID: "com.apple.MenuBarAgent",
                                           bundlePath: "/Applications/MenuBarAgent.app"))
        XCTAssertNil(IconsAgentWatch.event(launched: true, bundleID: "com.example", bundlePath: path))
    }

    func testLaunchWatch() {
        XCTAssertTrue(IconsLaunchWatch.counts(bundleID: "com.example.app", pid: 5, ownPID: own, bundlePath: nil))
        XCTAssertFalse(IconsLaunchWatch.counts(bundleID: "com.example.app", pid: own, ownPID: own, bundlePath: nil))
        XCTAssertFalse(IconsLaunchWatch.counts(bundleID: nil, pid: 5, ownPID: own, bundlePath: nil))
        XCTAssertFalse(IconsLaunchWatch.counts(bundleID: "com.apple.MenuBarAgent", pid: 5, ownPID: own,
                                               bundlePath: "/System/Library/CoreServices/MenuBarAgent.app"))
    }

    func testHiderCandidates() {
        XCTAssertTrue(KnownMenuBarHiders.candidate(bundleID: "com.dwarvesv.minimalbar"))
        XCTAssertTrue(KnownMenuBarHiders.candidate(bundleID: "com.surteesstudios.Bartender"))
        XCTAssertTrue(KnownMenuBarHiders.candidate(bundleID: "com.stonerl.Thaw.beta"))
        XCTAssertFalse(KnownMenuBarHiders.candidate(bundleID: "com.stonerl.Thawed"))
        XCTAssertFalse(KnownMenuBarHiders.candidate(bundleID: "com.dwarvesv.minimalbar.helper"))
        XCTAssertFalse(KnownMenuBarHiders.candidate(bundleID: nil))
        XCTAssertFalse(KnownMenuBarHiders.candidate(bundleID: ""))
        // A candidate is paused for only with the right team (where one is known).
        let wrongTeam = [IconsRunningApp(bundleID: "com.dwarvesv.minimalbar", teamID: "XXXXXXXXXX")]
        XCTAssertNil(IconsHiderPause.pausedFor(policy: .pause, running: wrongTeam))
        let real = [IconsRunningApp(bundleID: "com.dwarvesv.minimalbar", teamID: "W777S7V8TN")]
        XCTAssertEqual(IconsHiderPause.pausedFor(policy: .pause, running: real)?.name, "Hidden Bar")
    }
}
