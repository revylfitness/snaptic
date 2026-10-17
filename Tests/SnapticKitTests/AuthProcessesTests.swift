import XCTest
@testable import SnapticKit

final class AuthProcessesTests: XCTestCase {
    private let agent = "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle/Contents/MacOS/SecurityAgent"
    private let screen = [ScreenRect(x: 0, y: 0, width: 1920, height: 1080)]

    private func window(_ path: String, alpha: Double = 1, x: Double = 100, w: Double = 400) -> WindowSample {
        WindowSample(ownerPath: path, alpha: alpha, x: x, y: 100, width: w, height: 300)
    }

    func testFullPathMatchingOnly() {
        XCTAssertTrue(AuthProcesses.isAuthProcess(path: agent, sessionLocked: false))
        XCTAssertFalse(AuthProcesses.isAuthProcess(path: "/tmp/SecurityAgent", sessionLocked: false), "basename lookalike")
        XCTAssertFalse(AuthProcesses.isAuthProcess(path: agent + "x", sessionLocked: false))
        XCTAssertFalse(AuthProcesses.isAuthProcess(path: "/Applications/Evil.app/Contents/MacOS/coreautha", sessionLocked: false))
    }

    func testLoginWindowOnlyWhileLocked() {
        XCTAssertFalse(AuthProcesses.isAuthProcess(path: AuthProcesses.loginWindowPath, sessionLocked: false))
        XCTAssertTrue(AuthProcesses.isAuthProcess(path: AuthProcesses.loginWindowPath, sessionLocked: true))
    }

    func testInvisibleAndOffscreenWindowsIgnored() {
        XCTAssertTrue(AuthProcesses.isAuthWindow(window(agent), screens: screen, sessionLocked: false))
        XCTAssertFalse(AuthProcesses.isAuthWindow(window(agent, alpha: 0), screens: screen, sessionLocked: false))
        XCTAssertFalse(AuthProcesses.isAuthWindow(window(agent, alpha: .nan), screens: screen, sessionLocked: false))
        XCTAssertFalse(AuthProcesses.isAuthWindow(window(agent, x: 5000), screens: screen, sessionLocked: false))
        XCTAssertFalse(AuthProcesses.isAuthWindow(window(agent, w: 1), screens: screen, sessionLocked: false))
        XCTAssertTrue(AuthProcesses.authWindowPresent([window("/bin/other"), window(agent)], screens: screen, sessionLocked: false))
    }

    func testEpisodeCapsAt60Seconds() {
        var e = AuthEpisode()
        XCTAssertTrue(e.update(present: true, at: 0))
        XCTAssertTrue(e.isSuppressing)
        XCTAssertEqual(e.nextCheck(base: 0.5), AuthProcesses.recheckSeconds)
        XCTAssertFalse(e.update(present: true, at: 30))
        XCTAssertTrue(e.update(present: true, at: 61), "episode ends after 60 s")
        XCTAssertFalse(e.isSuppressing)
        XCTAssertFalse(e.update(present: true, at: 63), "a stuck window doesn't start a new episode")
        XCTAssertFalse(e.update(present: false, at: 65))
        XCTAssertTrue(e.update(present: true, at: 70), "it does after the window went away")
        XCTAssertTrue(e.update(present: false, at: 71))
        XCTAssertEqual(e.nextCheck(base: 0.5), 0.5)
    }
}
