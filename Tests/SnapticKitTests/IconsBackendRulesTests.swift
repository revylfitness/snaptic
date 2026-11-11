import XCTest
@testable import SnapticKit

/// 0.4 A2: the rules `NativeBackend`, `AXInventory` and `IconsWatchdog` execute (§4.2.1, §4.2.2, §4.2.6, §4.11).
final class IconsBackendRulesTests: XCTestCase {
    func testShimCompletionCodes() {
        XCTAssertNoThrow(try IconsShimResult.completion(0).get())
        XCTAssertEqual(failure(IconsShimResult.completion(1)), .failed)
        XCTAssertEqual(failure(IconsShimResult.completion(2)), .poisoned)
        XCTAssertEqual(failure(IconsShimResult.completion(3)), .failed)
        XCTAssertEqual(failure(IconsShimResult.completion(99)), .failed)
        XCTAssertEqual(failure(IconsShimResult.completion(-1)), .failed)
    }

    func testRefusalIsNeverASuccess() {
        XCTAssertEqual(IconsShimResult.refusal(2), .poisoned)
        for code in [0, 1, 3, 7] { XCTAssertEqual(IconsShimResult.refusal(code), .failed) }
    }

    func testBudgets() {
        XCTAssertEqual(IconsReadBudget.perCall, 0.15)
        XCTAssertEqual(IconsReadBudget.maxExtras, 50)
        XCTAssertEqual(IconsReadBudget.appDeadline(appStart: 10, readDeadline: 11.2), 10.5)
        XCTAssertEqual(IconsReadBudget.appDeadline(appStart: 11, readDeadline: 11.2), 11.2)
    }

    func testOrderPutsLastReadsAppsFirst() {
        XCTAssertEqual(IconsReadBudget.order([9, 3, 7, 3, 1], preferred: [7, 1]), [1, 7, 3, 9])
        XCTAssertEqual(IconsReadBudget.order([], preferred: [1]), [])
        XCTAssertEqual(IconsReadBudget.order([5, 2], preferred: []), [2, 5])
    }

    func testWholeReadFailsOnlyWhenNobodyAnswered() {
        XCTAssertFalse(IconsReadBudget.failed([]))
        XCTAssertTrue(IconsReadBudget.failed([.timedOut, .denied]))
        XCTAssertFalse(IconsReadBudget.failed([.timedOut, .noExtras]))
        XCTAssertFalse(IconsReadBudget.failed([.denied, .ok]))
    }

    func testAXErrorMapping() {
        XCTAssertEqual(IconsAXError.result(IconsAXError.success), .ok)
        XCTAssertEqual(IconsAXError.result(IconsAXError.cannotComplete), .timedOut)
        for code in [IconsAXError.noValue, IconsAXError.attributeUnsupported, IconsAXError.invalidUIElement] {
            XCTAssertEqual(IconsAXError.result(code), .noExtras)
        }
        for code in [IconsAXError.apiDisabled, IconsAXError.notImplemented, IconsAXError.failure, -1] {
            XCTAssertEqual(IconsAXError.result(code), .denied)
        }
    }

    func testAXToAppKitFlipsYOnly() {
        // A 24 pt menu bar extra at the top of a 1117 pt primary screen.
        let r = IconsAXGeometry.appKitRect(x: -352, y: 0, width: 30, height: 24, primaryHeight: 1117)
        XCTAssertEqual(r, IconsRect(x: -352, y: 1093, width: 30, height: 24))
        // A screen above the primary has a negative AX y.
        XCTAssertEqual(IconsAXGeometry.appKitRect(x: 0, y: -1080, width: 10, height: 24, primaryHeight: 1117)?.y,
                       1117 + 1080 - 24)
        XCTAssertNil(IconsAXGeometry.appKitRect(x: .nan, y: 0, width: 1, height: 1, primaryHeight: 900))
        XCTAssertNil(IconsAXGeometry.appKitRect(x: 0, y: 0, width: 1, height: 1, primaryHeight: 0))
    }

    func testSystemIdentity() {
        typealias S = IconsSystemIdentity
        XCTAssertEqual(S.identifier(firstChild: "com.apple.menuextra.wifi", own: nil), "com.apple.menuextra.wifi")
        XCTAssertEqual(S.identifier(firstChild: "x", own: "com.apple.menuextra.clock"), "com.apple.menuextra.clock")
        XCTAssertNil(S.identifier(firstChild: "com.apple.menuextra.", own: "other"))
        XCTAssertNil(S.identifier(firstChild: nil, own: nil))
        XCTAssertTrue(S.isMenuBarAgent(bundleID: "com.apple.MenuBarAgent",
                                       bundlePath: "/System/Library/CoreServices/MenuBarAgent.app/"))
        XCTAssertFalse(S.isMenuBarAgent(bundleID: "com.apple.MenuBarAgent", bundlePath: "/Applications/Fake.app"))
        XCTAssertFalse(S.isMenuBarAgent(bundleID: "com.example", bundlePath: S.menuBarAgentPath))
        XCTAssertFalse(S.isMenuBarAgent(bundleID: "com.apple.MenuBarAgent", bundlePath: nil))
    }

    func testIdentityCheck() {
        typealias I = IconsIdentityCheck
        XCTAssertTrue(I.passes(translocated: false, resolvedPath: "/Applications/Snaptic.app/",
                               ownPath: "/Applications/Snaptic.app"))
        XCTAssertFalse(I.passes(translocated: true, resolvedPath: "/Applications/Snaptic.app",
                                ownPath: "/Applications/Snaptic.app"))
        XCTAssertFalse(I.passes(translocated: false, resolvedPath: "/Applications/Snaptic.app",
                                ownPath: "/Users/me/Downloads/Snaptic.app"))
        XCTAssertFalse(I.passes(translocated: false, resolvedPath: nil, ownPath: "/Applications/Snaptic.app"))
        XCTAssertFalse(I.passes(translocated: false, resolvedPath: "/", ownPath: "/"))
    }

    func testWatchdogReleasesOncePerHangWhileHeld() {
        typealias W = IconsWatchdogRule
        XCTAssertTrue(W.shouldRelease(mainAgeMillis: 3001, held: 1, firedThisHang: false))
        XCTAssertFalse(W.shouldRelease(mainAgeMillis: 3000, held: 1, firedThisHang: false))
        XCTAssertFalse(W.shouldRelease(mainAgeMillis: 9000, held: 0, firedThisHang: false))
        XCTAssertFalse(W.shouldRelease(mainAgeMillis: 9000, held: 2, firedThisHang: true))
        XCTAssertFalse(W.shouldRelease(mainAgeMillis: .nan, held: 1, firedThisHang: false))
        // 3 s plus one poll stays inside M12's 4 s.
        XCTAssertLessThan(W.hangMillis / 1000 + W.poll, 4)
    }

    func testDebugHang() {
        XCTAssertNil(IconsWatchdogRule.debugHang(0))
        XCTAssertNil(IconsWatchdogRule.debugHang(-2))
        XCTAssertNil(IconsWatchdogRule.debugHang(.infinity))
        XCTAssertEqual(IconsWatchdogRule.debugHang(6), 6)
        XCTAssertEqual(IconsWatchdogRule.debugHang(60), 10)
    }

    private func failure(_ r: Result<Void, IconsActivationError>) -> IconsActivationError? {
        if case .failure(let e) = r { return e }
        return nil
    }
}
