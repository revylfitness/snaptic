import XCTest
@testable import SnapticKit

// 0.5 A2b (§4.9, §4.17; X-5, X2-8, X3-9): the private path's content check and its recheck, both probe branches, the
// scale-down, and the Window Switcher page's stopped rows.

private let flat = [UInt8](repeating: 0, count: 256)
private let busy: [UInt8] = (0..<256).map { UInt8(($0 * 37) % 256) }

final class CaptureContentCheckTests: XCTestCase {
    // MARK: The luma test

    func testStandardDeviation() {
        XCTAssertNil(CaptureContentCheck.standardDeviation([]))
        XCTAssertEqual(CaptureContentCheck.standardDeviation(flat), 0)
        // Half 0, half 2: mean 1, every deviation 1.
        let halves = [UInt8](repeating: 0, count: 128) + [UInt8](repeating: 2, count: 128)
        XCTAssertEqual(CaptureContentCheck.standardDeviation(halves) ?? -1, 1, accuracy: 1e-9)
        // Half 0, half 255: 127.5.
        let stripes = [UInt8](repeating: 0, count: 128) + [UInt8](repeating: 255, count: 128)
        XCTAssertEqual(CaptureContentCheck.standardDeviation(stripes) ?? -1, 127.5, accuracy: 1e-9)
    }

    func testSuspectThreshold() {
        XCTAssertTrue(CaptureContentCheck.isSuspect(nil), "an unreadable image is suspect")
        XCTAssertTrue(CaptureContentCheck.isSuspect([]))
        XCTAssertTrue(CaptureContentCheck.isSuspect(flat), "all black, or alpha 0 drawn flat, is suspect")
        XCTAssertTrue(CaptureContentCheck.isSuspect([UInt8](repeating: 255, count: 256)), "all white")
        // 0/2 halves: deviation 1, under 2.
        XCTAssertTrue(CaptureContentCheck.isSuspect([UInt8](repeating: 0, count: 128) + [UInt8](repeating: 2, count: 128)))
        // 0/4 halves: deviation exactly 2, which isn't under 2.
        XCTAssertFalse(CaptureContentCheck.isSuspect([UInt8](repeating: 0, count: 128) + [UInt8](repeating: 4, count: 128)))
        XCTAssertFalse(CaptureContentCheck.isSuspect(busy))
        // A dark terminal with a little text is one colour almost everywhere, yet not suspect (X-5).
        var terminal = [UInt8](repeating: 30, count: 256)
        for i in stride(from: 0, to: 256, by: 9) { terminal[i] = 200 }
        XCTAssertFalse(CaptureContentCheck.isSuspect(terminal))
    }

    // MARK: The counter

    func testNonSuspectIsAcceptedAndResets() {
        var check = CaptureContentCheck()
        XCTAssertEqual(check.record(window: 1, suspect: false), .accept)
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspect)
        XCTAssertEqual(check.record(window: 2, suspect: true), .suspect)
        XCTAssertEqual(check.run, 2)
        XCTAssertEqual(check.record(window: 3, suspect: false), .accept)
        XCTAssertEqual(check.run, 0)
        XCTAssertEqual(check.runWindows, [])
        // The run starts again from nothing.
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspect)
        XCTAssertEqual(check.record(window: 2, suspect: true), .suspect)
        XCTAssertEqual(check.record(window: 3, suspect: true), .suspectRecheck)
    }

    func testThreeSuspectsFromOneWindowDontRecheck() {
        var check = CaptureContentCheck()
        for _ in 0..<5 { XCTAssertEqual(check.record(window: 7, suspect: true), .suspect) }
        XCTAssertEqual(check.run, 5)
        XCTAssertNil(check.rechecking)
        // A second window joins the run: three or more suspects from two windows.
        XCTAssertEqual(check.record(window: 8, suspect: true), .suspectRecheck)
        XCTAssertEqual(check.rechecking, [7, 8])
    }

    func testOnlyOneRecheckAtATime() {
        var check = CaptureContentCheck()
        _ = check.record(window: 1, suspect: true)
        _ = check.record(window: 2, suspect: true)
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspectRecheck)
        XCTAssertEqual(check.record(window: 3, suspect: true), .suspect, "a recheck is under way")
        XCTAssertEqual(check.rechecking, [1, 2], "the windows that started it")
    }

    /// The pattern branch (S0-4): those windows are plain from then on, and the counter resets.
    func testPatternPassAcceptsThoseWindows() {
        var check = CaptureContentCheck()
        _ = check.record(window: 1, suspect: true)
        _ = check.record(window: 2, suspect: true)
        XCTAssertEqual(check.record(window: 2, suspect: true), .suspectRecheck)
        check.recheckFinished(.patternPass)
        XCTAssertEqual(check.plain, [1, 2])
        XCTAssertEqual(check.run, 0)
        XCTAssertNil(check.rechecking)
        XCTAssertEqual(check.record(window: 1, suspect: true), .accept)
        XCTAssertEqual(check.record(window: 2, suspect: true), .accept)
        // A plain window's suspect leaves the counter as it is; another window's still counts.
        XCTAssertEqual(check.record(window: 3, suspect: true), .suspect)
        XCTAssertEqual(check.record(window: 1, suspect: true), .accept)
        XCTAssertEqual(check.run, 1)
    }

    /// The shape-only branch (X3-9): nothing is accepted, and the counter resets.
    func testShapeOnlyPassAcceptsNothing() {
        var check = CaptureContentCheck()
        _ = check.record(window: 1, suspect: true)
        _ = check.record(window: 2, suspect: true)
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspectRecheck)
        check.recheckFinished(.shapeOnlyPass)
        XCTAssertEqual(check.plain, [])
        XCTAssertEqual(check.run, 0)
        XCTAssertNil(check.rechecking)
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspect)
        XCTAssertEqual(check.record(window: 2, suspect: true), .suspect)
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspectRecheck, "a later run rechecks again")
    }

    func testNoAnswerAndFailureAcceptNothing() {
        var check = CaptureContentCheck()
        _ = check.record(window: 1, suspect: true)
        _ = check.record(window: 2, suspect: true)
        _ = check.record(window: 1, suspect: true)
        check.recheckFinished(.patternPass)
        XCTAssertEqual(check.plain, [1, 2])

        _ = check.record(window: 3, suspect: true)
        _ = check.record(window: 4, suspect: true)
        XCTAssertEqual(check.record(window: 3, suspect: true), .suspectRecheck)
        check.recheckFinished(.noAnswer)
        XCTAssertEqual(check.plain, [1, 2], "no answer isn't a failure")
        XCTAssertEqual(check.record(window: 3, suspect: true), .suspect)

        _ = check.record(window: 4, suspect: true)
        XCTAssertEqual(check.record(window: 3, suspect: true), .suspectRecheck)
        check.recheckFinished(.failed)
        XCTAssertEqual(check.plain, [], "a poisoned path proves itself again")
        XCTAssertEqual(check.run, 0)
        XCTAssertEqual(check.record(window: 1, suspect: true), .suspect)
    }

    func testRecheckFinishedWithoutARecheckChangesNothing() {
        var check = CaptureContentCheck()
        _ = check.record(window: 1, suspect: true)
        check.recheckFinished(.patternPass)
        XCTAssertEqual(check.run, 1)
        XCTAssertEqual(check.plain, [])
    }

    func testGoneWindowsLosePlain() {
        var check = CaptureContentCheck()
        _ = check.record(window: 1, suspect: true)
        _ = check.record(window: 2, suspect: true)
        _ = check.record(window: 1, suspect: true)
        check.recheckFinished(.patternPass)
        check.keepPlain([2, 9])
        XCTAssertEqual(check.plain, [2])
    }

    // MARK: Scaling

    func testScaledSize() {
        XCTAssertNil(PrivateCaptureScaling.scaledSize(width: 0, height: 10, maxPixels: 640))
        XCTAssertNil(PrivateCaptureScaling.scaledSize(width: 10, height: 0, maxPixels: 640))
        // Never scaled up.
        XCTAssertTrue(PrivateCaptureScaling.scaledSize(width: 300, height: 200, maxPixels: 640)! == (300, 200))
        XCTAssertTrue(PrivateCaptureScaling.scaledSize(width: 640, height: 400, maxPixels: 640)! == (640, 400))
        // The longer side fits.
        XCTAssertTrue(PrivateCaptureScaling.scaledSize(width: 1280, height: 800, maxPixels: 640)! == (640, 400))
        XCTAssertTrue(PrivateCaptureScaling.scaledSize(width: 800, height: 1600, maxPixels: 640)! == (320, 640))
        XCTAssertTrue(PrivateCaptureScaling.scaledSize(width: 3456, height: 2234, maxPixels: 2400)! == (2400, 1551))
        // A sliver keeps at least one pixel.
        XCTAssertTrue(PrivateCaptureScaling.scaledSize(width: 5000, height: 2, maxPixels: 640)! == (640, 1))
        XCTAssertEqual(PrivateCaptureScaling.scaleFactor(width: 1280, height: 800, maxPixels: 640), 0.5)
        XCTAssertEqual(PrivateCaptureScaling.scaleFactor(width: 1280, height: 800, maxPixels: .infinity), 1)
        XCTAssertEqual(PrivateCaptureScaling.scaleFactor(width: 1280, height: 800, maxPixels: 0), 1)
    }

    // MARK: Diagnostics (M1, M33)

    func testHWCaptureDiagnostic() {
        typealias D = PrivateCaptureDiagnostics
        // Safe Mode wins over everything, the crash guard included.
        XCTAssertEqual(D.hwCapture(safeMode: true, state: .available, phase: .needsProbe), "safeMode")
        XCTAssertEqual(D.hwCapture(safeMode: true, state: .disabled, phase: .passed), "safeMode")
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .unavailable, phase: .needsProbe), "unavailable")
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .disabled, phase: .passed), "disabled")
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .poisoned, phase: .retry(at: 600)), "poisoned")
        // Thumbnails off, or no capture yet: the probe hasn't run (M1).
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .available, phase: .needsProbe), "notProbed")
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .available, phase: .probing), "probing")
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .available, phase: .passed), "passed")
        XCTAssertEqual(D.hwCapture(safeMode: false, state: .available, phase: .retry(at: 60)), "noAnswer")
    }

    func testDiagnosticsLinesBecomeRows() {
        let lines = PrivateCaptureDiagnostics.lines(hwCapture: "safeMode", privateCaptures: 0, killSwitches: [])
        XCTAssertEqual(lines, ["hwCapture: safeMode", "Private captures: 0", "Kill switches: none"])
        let rows = lines.compactMap(HostReport.row)
        XCTAssertEqual(rows.map(\.label), ["hwCapture", "Private captures", "Kill switches"])
        XCTAssertEqual(rows.map(\.value), ["safeMode", "0", "none"])
        let set = PrivateCaptureDiagnostics.lines(hwCapture: "passed", privateCaptures: 3,
                                                  killSwitches: [.raise, .hwCapture])
        XCTAssertEqual(set.last, "Kill switches: hwCapture, raise", "table order")
    }

    // MARK: Stopped rows (§4.17)

    func testSwitcherPageRowsFollowTheTableOrder() {
        let rows = WindowStopRows.switcherPage(crashGuard: [.layoutType, .hwCapture], poisoned: [.spaces, .raise])
        XCTAssertEqual(rows.map(\.feature), [.hwCapture, .layoutType, .raise, .spaces])
        XCTAssertEqual(rows.map(\.action), [.tryAgain, .tryAgain, nil, nil])
        XCTAssertEqual(rows[0].text, "Thumbnails of minimized windows and windows on other Spaces stopped after a problem in macOS. Snaptic tries again after a macOS update.")
        XCTAssertEqual(rows[2].text, "Bringing windows forward from other Spaces stopped because macOS answered in a way Snaptic didn’t expect. Quit and reopen Snaptic to try again.")
        XCTAssertTrue(WindowStopRows.switcherPage(crashGuard: [], poisoned: []).isEmpty)
    }

    func testEveryFeatureShowsOnTheSwitcherPage() {
        let all = Set(WindowFeature.allCases)
        XCTAssertEqual(WindowStopRows.switcherPage(crashGuard: all, poisoned: []).map(\.feature),
                       WindowFeature.allCases)
        // A crash-guard stop shows once, with its Try Again.
        let both = WindowStopRows.switcherPage(crashGuard: [.symbolicHotKeys], poisoned: [.symbolicHotKeys])
        XCTAssertEqual(both.count, 1)
        XCTAssertEqual(both.first?.action, .tryAgain)
    }

    /// The Dock page lists only the “Both pages” features, in table order; a crash-guard stop isn't also poisoned.
    func testDockPageShowsOnlyTheSharedFeatures() {
        let all = Set(WindowFeature.allCases)
        let rows = WindowStopRows.dockPage(crashGuard: all, poisoned: all)
        XCTAssertEqual(rows.crashGuard, [.hwCapture, .axWindowID, .raise, .spaces])
        XCTAssertEqual(rows.poisoned, [])
        let mixed = WindowStopRows.dockPage(crashGuard: [.spaces, .layoutType], poisoned: [.raise, .hwCapture, .spaces,
                                                                                            .symbolicHotKeys])
        XCTAssertEqual(mixed.crashGuard, [.spaces])
        XCTAssertEqual(mixed.poisoned, [.hwCapture, .raise])
        let none = WindowStopRows.dockPage(crashGuard: [.symbolicHotKeys], poisoned: [.layoutType])
        XCTAssertTrue(none.crashGuard.isEmpty && none.poisoned.isEmpty)
    }

    func testGiveBackRow() {
        XCTAssertNil(WindowStopRows.giveBack(pending: false, comesBackAtLogout: false))
        let stays = WindowStopRows.giveBack(pending: true, comesBackAtLogout: false)
        XCTAssertEqual(stays?.text, "⌘⇥ doesn’t switch apps, because Snaptic couldn’t turn it back on after a problem in macOS.")
        XCTAssertEqual(stays?.help, "This also affects ⌘⇧⇥ and ⌘ with the key above Tab.")
        XCTAssertEqual(stays?.action, .tryAgainGiveBack)
        XCTAssertNil(stays?.feature)
        XCTAssertEqual(WindowStopRows.giveBack(pending: true, comesBackAtLogout: true)?.text,
                       "⌘⇥ may not switch apps until you log out, because Snaptic couldn’t turn it back on after a problem in macOS.")
    }
}
