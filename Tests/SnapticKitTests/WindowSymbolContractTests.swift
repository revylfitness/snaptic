import XCTest
@testable import SnapticKit

// 0.5 B1b (§4.12, §6.1): the window C-symbol contract — result classes, poisoning, probes driven through injected
// results, fallbacks, the OS gate, the layout's no answer, the pixel limit, the probe cache and the selftest lines.

private let build = "26B123"

final class WindowSymbolContractTests: XCTestCase {
    // MARK: Result classes (X2-1)

    func testAXResultClasses() {
        XCTAssertEqual(WindowResults.ax(error: 0, windowID: 42), .answer)
        for error in WindowResults.axNoAnswerErrors {
            XCTAssertEqual(WindowResults.ax(error: error, windowID: 0), .noAnswer, "\(error)")
        }
        // The app answers, so nothing it says is impossible.
        XCTAssertEqual(WindowResults.ax(error: -25200, windowID: 0), .noAnswer)
        XCTAssertEqual(WindowResults.ax(error: 0, windowID: 0), .noAnswer)
    }

    func testSpacesResultClasses() {
        XCTAssertEqual(WindowResults.copySpaces(.null), .noAnswer)
        XCTAssertEqual(WindowResults.copySpaces(.empty), .noAnswer)
        XCTAssertEqual(WindowResults.copySpaces(.elements([WindowImageSize(width: 0, height: 0)])), .answer)
        XCTAssertEqual(WindowResults.copySpaces(.notArray), .impossible)
        XCTAssertEqual(WindowResults.copySpaces(.wrongElement), .impossible)
    }

    func testMainConnectionResultClasses() {
        XCTAssertEqual(WindowResults.mainConnection(7), .answer)
        XCTAssertEqual(WindowResults.mainConnection(0), .impossible)
    }

    func testSetterResultClasses() {
        XCTAssertEqual(WindowResults.setSymbolicHotKey(error: 0, readBack: false, wanted: false), .answer)
        XCTAssertEqual(WindowResults.setSymbolicHotKey(error: 0, readBack: nil, wanted: false), .answer)
        XCTAssertEqual(WindowResults.setSymbolicHotKey(error: 1000, readBack: false, wanted: false), .impossible)
        XCTAssertEqual(WindowResults.setSymbolicHotKey(error: 0, readBack: true, wanted: false), .impossible)
    }

    func testRaiseErrorsAreNoAnswer() {
        XCTAssertEqual(WindowResults.raise(error: 0), .answer)
        XCTAssertEqual(WindowResults.raise(error: -600), .noAnswer)
        XCTAssertEqual(WindowResults.raise(error: 1000), .noAnswer)
    }

    func testCaptureResultClasses() {
        let limit = WindowResults.pixelLimit(windowWidth: 100, windowHeight: 50, maxScale: 2)
        let ok = WindowImageSize(width: 200, height: 100)
        XCTAssertEqual(WindowResults.capture(.elements([ok]), pixelLimit: limit), .answer)
        // NULL from a closed window or one on no display (PC-2), or an empty array, is no answer.
        XCTAssertEqual(WindowResults.capture(.null, pixelLimit: limit), .noAnswer)
        XCTAssertEqual(WindowResults.capture(.empty, pixelLimit: limit), .noAnswer)
        XCTAssertEqual(WindowResults.capture(.notArray, pixelLimit: limit), .impossible)
        XCTAssertEqual(WindowResults.capture(.wrongElement, pixelLimit: limit), .impossible)
        XCTAssertEqual(WindowResults.capture(.elements([WindowImageSize(width: 0, height: 100)]), pixelLimit: limit),
                       .impossible)
        // A partly off-screen window gives its visible part only, and passes (PC-2).
        XCTAssertEqual(WindowResults.capture(.elements([WindowImageSize(width: 100, height: 100)]), pixelLimit: limit),
                       .answer)
    }

    func testPixelLimitAtTheLargestScreenScale() throws {
        // 4 × (100 × 2) × (50 × 2) = 80,000 pixels.
        let limit = try XCTUnwrap(WindowResults.pixelLimit(windowWidth: 100, windowHeight: 50, maxScale: 2))
        XCTAssertEqual(limit, 80_000)
        XCTAssertEqual(WindowResults.capture(.elements([WindowImageSize(width: 400, height: 200)]), pixelLimit: limit),
                       .answer)
        XCTAssertEqual(WindowResults.capture(.elements([WindowImageSize(width: 401, height: 200)]), pixelLimit: limit),
                       .impossible)
        // At 1x the same image is over the limit.
        let oneX = WindowResults.pixelLimit(windowWidth: 100, windowHeight: 50, maxScale: 1)
        XCTAssertEqual(WindowResults.capture(.elements([WindowImageSize(width: 400, height: 200)]), pixelLimit: oneX),
                       .impossible)
        // No usable bounds: no limit, rather than a false impossible.
        XCTAssertNil(WindowResults.pixelLimit(windowWidth: 0, windowHeight: 50, maxScale: 2))
        XCTAssertNil(WindowResults.pixelLimit(windowWidth: .nan, windowHeight: 50, maxScale: 2))
    }

    func testUnknownLayoutIsNoAnswerAndKnownLayoutsAnswer() {
        XCTAssertEqual(WindowResults.layout(WindowResults.layoutANSI), .answer)
        XCTAssertEqual(WindowResults.layout(WindowResults.layoutISO), .answer)
        XCTAssertEqual(WindowResults.layout(WindowResults.layoutJIS), .answer)
        XCTAssertEqual(WindowResults.layout(0x3F3F_3F3F), .noAnswer)
        XCTAssertEqual(WindowResults.layout(0), .impossible)
        XCTAssertEqual(WindowResults.layout(0x4142_4344), .impossible)
    }

    // MARK: Poisoning (X2-1, P2-14)

    func testTenNoAnswersNeverPoison() {
        var health = WindowSymbolHealth(.copySpaces, probedBuild: build, currentBuild: build)
        for i in 0..<10 { XCTAssertFalse(health.record(.noAnswer, now: Double(i))) }
        XCTAssertFalse(health.poisoned)
        XCTAssertEqual(health.nextUse(now: 10), .call)
    }

    func testTwoImpossibleResultsInARowPoison() {
        var health = WindowSymbolHealth(.copySpaces, probedBuild: build, currentBuild: build)
        XCTAssertFalse(health.record(.impossible, now: 0))
        XCTAssertTrue(health.record(.impossible, now: 1))
        XCTAssertTrue(health.poisoned)
        XCTAssertEqual(health.nextUse(now: 2), .fallback)
    }

    func testNoAnswersDontBreakOrExtendTheRunButAnAnswerResetsIt() {
        var health = WindowSymbolHealth(.mainConnection, probedBuild: build, currentBuild: build)
        XCTAssertFalse(health.record(.impossible, now: 0))
        XCTAssertFalse(health.record(.noAnswer, now: 1))
        XCTAssertTrue(health.record(.impossible, now: 2), "a no answer between two impossible results doesn't reset")

        var reset = WindowSymbolHealth(.mainConnection, probedBuild: build, currentBuild: build)
        XCTAssertFalse(reset.record(.impossible, now: 0))
        XCTAssertFalse(reset.record(.answer, now: 1))
        XCTAssertFalse(reset.record(.impossible, now: 2))
        XCTAssertFalse(reset.poisoned)
    }

    func testAnOwnerMismatchNeverPoisons() {
        // The app claims a window another process owns: the id is dropped, and the symbol's result is an answer.
        var health = WindowSymbolHealth(.axGetWindow, probedBuild: build, currentBuild: build)
        for i in 0..<10 {
            let claimed: UInt32 = 900 + UInt32(i)
            XCTAssertNil(WindowCatalogRules.trustedWindowID(claimed: claimed, pid: 1, owners: [claimed: 2]))
            XCTAssertFalse(health.record(WindowResults.ax(error: 0, windowID: claimed), now: Double(i)))
        }
        XCTAssertFalse(health.poisoned)
    }

    func testFailedProbePoisonsThenReprobesAfterTenMinutesAndASecondPoisoningLasts() {
        var health = WindowSymbolHealth(.copySpaces, probedBuild: nil, currentBuild: build)
        XCTAssertEqual(health.nextUse(now: 0), .probe)
        XCTAssertEqual(health.nextUse(now: 0), .fallback, "a caller during the probe takes the fallback")
        XCTAssertEqual(health.probeFinished(.impossible, now: 1), .poisoned(lasting: false))
        XCTAssertTrue(health.poisoned)
        XCTAssertEqual(health.nextUse(now: 600), .fallback)
        XCTAssertEqual(health.nextUse(now: 601), .probe)
        XCTAssertEqual(health.probeFinished(.answer, now: 602), .passed(clearedPoison: true))
        XCTAssertFalse(health.poisoned)
        XCTAssertEqual(health.nextUse(now: 603), .call)

        XCTAssertFalse(health.record(.impossible, now: 700))
        XCTAssertTrue(health.record(.impossible, now: 701))
        XCTAssertTrue(health.lasting, "the second poisoning lasts until quit")
        XCTAssertEqual(health.nextUse(now: 1_000_000), .fallback)
    }

    func testAPoisonedReprobeWithNoAnswerStaysPoisonedAndRetriesInAMinute() {
        var health = WindowSymbolHealth(.mainConnection, probedBuild: nil, currentBuild: build)
        XCTAssertEqual(health.nextUse(now: 0), .probe)
        _ = health.probeFinished(.impossible, now: 0)
        XCTAssertEqual(health.nextUse(now: 600), .probe)
        XCTAssertEqual(health.probeFinished(.noAnswer, now: 600), .noAnswer)
        XCTAssertTrue(health.poisoned)
        XCTAssertEqual(health.nextUse(now: 659), .fallback)
        XCTAssertEqual(health.nextUse(now: 660), .probe)
    }

    func testAProbeWithNoAnswerIsNotAFailureAndRetriesAtMostOnceAMinute() {
        var health = WindowSymbolHealth(.layoutType, probedBuild: nil, currentBuild: build)
        XCTAssertEqual(health.nextUse(now: 0), .probe)
        XCTAssertEqual(health.probeFinished(WindowResults.layout(WindowResults.layoutUnknown), now: 0), .noAnswer)
        XCTAssertFalse(health.poisoned)
        XCTAssertEqual(health.poisonings, 0)
        XCTAssertEqual(health.nextUse(now: 30), .fallback)
        XCTAssertEqual(health.nextUse(now: 60), .probe)
    }

    func testForcedPoisonLastsForTheProcess() {
        var health = WindowSymbolHealth(.setSymbolicHotKeyEnabled, probedBuild: nil, currentBuild: build)
        XCTAssertEqual(health.nextUse(now: 0), .call, "presence only")
        health.poisonForProcess()
        XCTAssertTrue(health.lasting)
        XCTAssertEqual(health.nextUse(now: 10_000), .fallback)
        XCTAssertEqual(health.probeFinished(.answer, now: 10_001), .poisoned(lasting: true))
    }

    // MARK: Probe failure branches through injected results (D2-13)

    func testEveryProbesFailureBranch() {
        let failures: [(WindowSymbolID, WindowResultClass)] = [
            (.mainConnection, WindowResults.mainConnectionProbe(sls: 0, cgs: nil)),
            (.mainConnection, WindowResults.mainConnectionProbe(sls: 5, cgs: 6)),
            (.copySpaces, WindowResults.copySpaces(.wrongElement)),
            (.axGetWindow, WindowResults.axProbe([(0, 11), (0, 12)], expected: 99)),
            (.layoutType, WindowResults.layout(0x1234_5678)),
            (.hwCapture, WindowResults.captureProbe(
                WindowCaptureProbeResult(shape: .elements([WindowImageSize(width: 64, height: 64)]),
                                         sample: CapturePattern.expectedSample.map { 255 - $0 }),
                pixelLimit: WindowResults.pixelLimit(windowWidth: 64, windowHeight: 64, maxScale: 2))),
            (.hwCapture, WindowResults.captureProbe(WindowCaptureProbeResult(shape: .notArray, sample: nil),
                                                    pixelLimit: nil)),
        ]
        for (id, result) in failures {
            XCTAssertEqual(result, .impossible, "\(id)")
            var health = WindowSymbolHealth(id, probedBuild: nil, currentBuild: build)
            XCTAssertEqual(health.nextUse(now: 0), .probe, "\(id)")
            XCTAssertEqual(health.probeFinished(result, now: 0), .poisoned(lasting: false), "\(id)")
            XCTAssertTrue(health.poisoned, "\(id)")
        }
    }

    func testProbePassesAndNoAnswers() {
        XCTAssertEqual(WindowResults.mainConnectionProbe(sls: 5, cgs: 5), .answer)
        XCTAssertEqual(WindowResults.mainConnectionProbe(sls: 5, cgs: nil), .answer)
        XCTAssertEqual(WindowResults.mainConnectionProbe(sls: nil, cgs: nil), .noAnswer)
        XCTAssertEqual(WindowResults.axProbe([(0, 11), (0, 99)], expected: 99), .answer)
        XCTAssertEqual(WindowResults.axProbe([(-25204, 0), (-25211, 0)], expected: 99), .noAnswer)
        XCTAssertEqual(WindowResults.axProbe([], expected: 99), .noAnswer)
        let limit = WindowResults.pixelLimit(windowWidth: 64, windowHeight: 64, maxScale: 2)
        let image = WindowArrayShape.elements([WindowImageSize(width: 128, height: 128)])
        XCTAssertEqual(WindowResults.captureProbe(WindowCaptureProbeResult(shape: image,
                                                                           sample: CapturePattern.expectedSample),
                                                  pixelLimit: limit), .answer)
        XCTAssertEqual(WindowResults.captureProbe(WindowCaptureProbeResult(shape: image, sample: nil),
                                                  pixelLimit: limit), .noAnswer)
        XCTAssertEqual(WindowResults.captureProbe(WindowCaptureProbeResult(shape: .null, sample: nil),
                                                  pixelLimit: limit), .noAnswer)
    }

    func testCapturePatternIsStripesAndSurvivesAVerticalFlip() throws {
        let expected = CapturePattern.expectedSample
        XCTAssertEqual(expected.count, 256)
        XCTAssertEqual(Array(expected[0..<8]), [0, 0, 0, 0, 255, 255, 255, 255])
        let rows = stride(from: 0, to: 256, by: 16).map { Array(expected[$0..<$0 + 16]) }
        XCTAssertEqual(Array(rows.reversed().joined()), expected, "a vertical flip reads the same")
        XCTAssertEqual(CapturePattern.difference(sample: expected), 0)
        XCTAssertEqual(try XCTUnwrap(CapturePattern.difference(sample: expected.map { 255 - $0 })), 1)
        // A half-grey column at two stripe edges (about 6%) still passes; a blank image doesn't.
        var blurred = expected
        for i in stride(from: 3, to: 256, by: 8) { blurred[i] = 128 }
        XCTAssertTrue(CapturePattern.passes(sample: blurred))
        XCTAssertFalse(CapturePattern.passes(sample: [UInt8](repeating: 0, count: 256)))
        XCTAssertFalse(CapturePattern.passes(sample: [0, 255]))
    }

    // MARK: Probe cache (X3-3)

    func testAProbePassIsCachedPerOSBuild() {
        XCTAssertEqual(WindowSymbolHealth(.copySpaces, probedBuild: build, currentBuild: build).phase, .passed)
        XCTAssertEqual(WindowSymbolHealth(.copySpaces, probedBuild: "25A1", currentBuild: build).phase, .needsProbe)
        XCTAssertEqual(WindowSymbolHealth(.copySpaces, probedBuild: nil, currentBuild: build).phase, .needsProbe)
        XCTAssertEqual(WindowSymbolHealth(.copySpaces, probedBuild: "", currentBuild: "").phase, .needsProbe)
        XCTAssertEqual(WindowSymbolHealth(.hwCapture, probedBuild: build, currentBuild: build).phase, .passed)
        // Presence-only symbols never probe.
        for id in [WindowSymbolID.getProcessForPID, .setFrontProcess, .postEventRecord, .isSymbolicHotKeyEnabled,
                   .setSymbolicHotKeyEnabled, .kbdType] {
            XCTAssertEqual(WindowSymbolHealth(id, probedBuild: nil, currentBuild: build).phase, .passed, "\(id)")
        }
    }

    // MARK: Secure input (X2-2)

    func testUnknownSecureInputGivesCommandTabBackWithoutCancelling() {
        let unknown = SecureInputVerdict.decide(.unknown, tapEnabled: true, trusted: true)
        XCTAssertTrue(unknown.suspendTake)
        XCTAssertFalse(unknown.cancel, "the switcher stays open")
        let on = SecureInputVerdict.decide(.on, tapEnabled: true, trusted: true)
        XCTAssertEqual(on, SecureInputVerdict(suspendTake: true, cancel: true))
        let off = SecureInputVerdict.decide(.off, tapEnabled: true, trusted: true)
        XCTAssertEqual(off, SecureInputVerdict(suspendTake: false, cancel: false))
        XCTAssertEqual(SecureInputVerdict.decide(.unknown, tapEnabled: false, trusted: true),
                       SecureInputVerdict(suspendTake: true, cancel: true))
        XCTAssertEqual(SecureInputVerdict.decide(.off, tapEnabled: true, trusted: false),
                       SecureInputVerdict(suspendTake: true, cancel: true))
    }

    // MARK: Fallbacks

    func testFallbackForEveryFeature() {
        let expected: [WindowFeature: WindowFallback] = [
            .hwCapture: .lastSeenThenIcon, .axWindowID: .matchByTitleAndFrame, .raise: .axRaiseThenActivate,
            .spaces: .dropOtherSpaces, .symbolicHotKeys: .systemKeepsCommandTab, .layoutType: .ansiLayout,
        ]
        XCTAssertEqual(expected.count, WindowFeature.allCases.count)
        for feature in WindowFeature.allCases {
            XCTAssertEqual(WindowSymbolContract.fallback(for: feature), expected[feature], "\(feature)")
        }
    }

    func testFeaturesNamesAndKillSwitchKeys() {
        XCTAssertEqual(WindowFeature.allCases.map(\.killSwitchKey), [
            "Windows.disable.hwCapture", "Windows.disable.axWindowID", "Windows.disable.raise",
            "Windows.disable.spaces", "Windows.disable.symbolicHotKeys", "Windows.disable.layoutType",
        ])
        XCTAssertEqual(WindowFeature.hwCapture.displayName, "Thumbnails of minimized windows and windows on other Spaces")
        XCTAssertEqual(WindowFeature.symbolicHotKeys.displayName, "Using ⌘⇥ for the Window Switcher")
        XCTAssertEqual(WindowFeature.allCases.filter(\.switcherPageOnly), [.symbolicHotKeys, .layoutType])
        let domain: [String: Any] = ["Windows.disable.raise": true, "Windows.disable.spaces": false]
        XCTAssertEqual(KillSwitches.read(domain, prefix: "Windows", as: WindowFeature.self), [.raise])
        for feature in WindowFeature.allCases {
            XCTAssertFalse(WindowSymbolID.symbols(for: feature).isEmpty, "\(feature)")
        }
    }

    // MARK: OS gate and image (X3-1, X2-7)

    func testOSGateOnVerifiedAndUnverifiedMajors() {
        for id in WindowSymbolID.allCases {
            XCTAssertTrue(WindowOSGate.allows(id, major: 15), "\(id)")
            XCTAssertTrue(WindowOSGate.allows(id, major: 27), "\(id)")
            XCTAssertFalse(WindowOSGate.allows(id, major: 13), "\(id)")
        }
        for major in [14, 26, 28] {
            XCTAssertFalse(WindowOSGate.allows(.hwCapture, major: major), "the capture waits for a verified major")
            for id in WindowSymbolID.allCases where id != .hwCapture {
                XCTAssertTrue(WindowOSGate.allows(id, major: major), "0.4's \(id) runs on \(major)")
            }
        }
    }

    func testStateFromLookupGateImageAndGuards() {
        let sky = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        let moved = "/System/Library/PrivateFrameworks/WindowServerKit.framework/Versions/A/WindowServerKit"
        let found = WindowSymbolLookup(present: true, imagePath: sky, variant: .sls)
        XCTAssertEqual(WindowSymbolContract.state(.copySpaces, lookup: found, major: 27, disabled: false, poisoned: false),
                       .available)
        XCTAssertEqual(WindowSymbolContract.state(.copySpaces, lookup: .absent, major: 27, disabled: false,
                                                  poisoned: false), .unavailable)
        let movedLookup = WindowSymbolLookup(present: true, imagePath: moved)
        XCTAssertEqual(WindowSymbolContract.state(.copySpaces, lookup: movedLookup, major: 27, disabled: false,
                                                  poisoned: false), .unavailable)
        XCTAssertTrue(WindowSymbolContract.imageMoved(.copySpaces, lookup: movedLookup))
        XCTAssertEqual(WindowSymbolContract.state(.copySpaces, lookup: movedLookup, major: 26, disabled: false,
                                                  poisoned: false), .available, "only reported on an unverified major")
        XCTAssertEqual(WindowSymbolContract.state(.hwCapture, lookup: found, major: 26, disabled: false, poisoned: false),
                       .unavailable)
        XCTAssertEqual(WindowSymbolContract.state(.hwCapture, lookup: found, major: 27, disabled: true, poisoned: false),
                       .disabled)
        XCTAssertEqual(WindowSymbolContract.state(.hwCapture, lookup: .absent, major: 26, disabled: true, poisoned: true),
                       .poisoned)
        let hiServices = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/"
            + "HIServices.framework/Versions/A/HIServices"
        XCTAssertTrue(WindowSymbolImage.hiServices.matches(path: hiServices))
        XCTAssertFalse(WindowSymbolImage.hiServices.matches(path: "/tmp/HIServices"))
        XCTAssertFalse(WindowSymbolImage.skyLight.matches(path: nil))
        let states: [WindowSymbolID: WindowSymbolState] = [.mainConnection: .available, .copySpaces: .available,
                                                            .getProcessForPID: .available, .setFrontProcess: .poisoned]
        XCTAssertTrue(WindowSymbolContract.featureWorks(.spaces, states: states))
        XCTAssertFalse(WindowSymbolContract.featureWorks(.raise, states: states))
    }

    // MARK: Selftest lines (P-8, P2-7)

    func testLaunchLines() {
        let reports = [
            WindowSymbolReport(name: "CGSHWCaptureWindowList", state: .available),
            WindowSymbolReport(name: "MainConnectionID", state: .available, variant: .sls),
            WindowSymbolReport(name: "CopySpacesForWindows", state: .unavailable, variant: .cgs),
        ]
        XCTAssertEqual(WindowSymbolContract.launchLines(reports, secureInput: .off), [
            "selftest-launch: windows CGSHWCaptureWindowList available",
            "selftest-launch: windows MainConnectionID available SLS",
            "selftest-launch: windows CopySpacesForWindows unavailable CGS",
            "selftest-launch: windows secureInput available",
        ])
        XCTAssertEqual(WindowSymbolContract.launchLines([], secureInput: .unknown),
                       ["selftest-launch: windows secureInput unknown"])
        XCTAssertEqual(WindowSymbolContract.launchLines([], secureInput: .on),
                       ["selftest-launch: windows secureInput available"])
    }

    func testSelfTestVerdict() {
        let ok = [WindowSymbolReport(name: "A", state: .available), WindowSymbolReport(name: "B", state: .available)]
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(ok, secureInput: .off, expect: nil), [])
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(ok, secureInput: .off, expect: "available"), [])
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(ok, secureInput: .unknown, expect: "available").count, 1)
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(ok, secureInput: .unknown, expect: nil), [])
        let mixed = [WindowSymbolReport(name: "A", state: .available), WindowSymbolReport(name: "B", state: .disabled)]
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(mixed, secureInput: .off, expect: "available"),
                       ["expected window symbol B available, found disabled"])
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(mixed, secureInput: .off, expect: nil), [])
        let poisoned = [WindowSymbolReport(name: "A", state: .poisoned)]
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(poisoned, secureInput: .off, expect: nil),
                       ["window symbol A is poisoned"])
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(ok, secureInput: .off, expect: "poisoned").count, 1)
        XCTAssertEqual(WindowSymbolContract.selfTestProblems(ok, secureInput: .off, expect: "yes").count, 1)
    }

    func testPoisonPathVerdict() {
        let all = WindowSymbolID.allCases.map { WindowSymbolReport(name: $0.rawValue, state: .poisoned) }
        XCTAssertEqual(WindowSymbolContract.poisonProblems(all), [])
        XCTAssertEqual(WindowSymbolContract.poisonLine([]), "selftest-launch: windows poison path ok")
        var one = all
        one[3].state = .available
        XCTAssertEqual(WindowSymbolContract.poisonProblems(one).count, 1)
        XCTAssertEqual(WindowSymbolContract.poisonLine(["x"]), "selftest-launch: windows poison path failed")
        XCTAssertEqual(WindowSymbolContract.poisonProblems([]).count, 1)
    }

    func testSymbolTable() {
        XCTAssertEqual(WindowSymbolID.allCases.filter(\.newIn05), [.hwCapture])
        XCTAssertEqual(WindowSymbolID.allCases.filter { !$0.readOnly },
                       [.hwCapture, .getProcessForPID, .setFrontProcess, .postEventRecord, .setSymbolicHotKeyEnabled])
        XCTAssertEqual(WindowSymbolID.symbols(for: .raise), [.getProcessForPID, .setFrontProcess, .postEventRecord])
        XCTAssertEqual(WindowSymbolID.allCases.filter(\.hasAlias),
                       [.mainConnection, .copySpaces, .isSymbolicHotKeyEnabled, .setSymbolicHotKeyEnabled])
        XCTAssertEqual(WindowSymbolID.axGetWindow.image, .hiServices)
        XCTAssertEqual(WindowSymbolID.kbdType.image, .hiToolbox)
        XCTAssertEqual(WindowSymbolID.hwCapture.image, .skyLight)
    }
}
