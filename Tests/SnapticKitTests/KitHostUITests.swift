import XCTest
@testable import SnapticKit

final class KitHostUITests: XCTestCase {
    // MARK: Settings selection (W18)

    func testSelectionStaysWhileItsPageExists() {
        let pages = ["general.modules", "general.menu", "displays.features", "displays.brightness"]
        XCTAssertEqual(HostUIRules.settingsSelection("displays.brightness", available: pages), "displays.brightness")
        XCTAssertEqual(HostUIRules.settingsSelection("general.menu", available: pages), "general.menu")
    }

    func testVanishedPageFallsBackToDisplayFeaturesThenModules() {
        let withDisplays = ["general.modules", "general.menu", "displays.features"]
        XCTAssertEqual(HostUIRules.settingsSelection("displays.pip", available: withDisplays), "displays.features")
        XCTAssertEqual(HostUIRules.settingsSelection(nil, available: withDisplays), "displays.features")
        let generalOnly = ["general.modules", "general.menu"]
        XCTAssertEqual(HostUIRules.settingsSelection("displays.features", available: generalOnly), "general.modules")
        XCTAssertEqual(HostUIRules.settingsSelection("x", available: ["general.menu"]), "general.menu")
        XCTAssertNil(HostUIRules.settingsSelection("x", available: []))
    }

    func testFallbackIsAlwaysAnAvailablePage() {
        var rng = SeededGenerator(seed: 0x5E77)
        let all = ["general.modules", "general.menu", "displays.features", "displays.pip", "switcher.main"]
        for _ in 0..<500 {
            let available = all.filter { _ in rng.next() % 2 == 0 }
            let selection: String? = rng.next() % 4 == 0 ? nil : all[Int(rng.next() % UInt64(all.count))]
            let result = HostUIRules.settingsSelection(selection, available: available)
            if available.isEmpty { XCTAssertNil(result) } else { XCTAssertTrue(available.contains(result ?? "")) }
            if let selection, available.contains(selection) { XCTAssertEqual(result, selection) }
        }
    }

    // MARK: Status item visibility (W16)

    func testStatusItemShows() {
        XCTAssertFalse(HostUIRules.statusItemShows(isVisible: false, osMajor: 14, windowOnScreen: true))
        XCTAssertTrue(HostUIRules.statusItemShows(isVisible: true, osMajor: 14, windowOnScreen: nil))
        XCTAssertTrue(HostUIRules.statusItemShows(isVisible: true, osMajor: 26, windowOnScreen: false))
        // macOS 27 can hide items itself: isVisible alone isn't trusted.
        XCTAssertTrue(HostUIRules.statusItemShows(isVisible: true, osMajor: 27, windowOnScreen: true))
        XCTAssertFalse(HostUIRules.statusItemShows(isVisible: true, osMajor: 27, windowOnScreen: false))
        XCTAssertFalse(HostUIRules.statusItemShows(isVisible: true, osMajor: 27, windowOnScreen: nil))
        XCTAssertFalse(HostUIRules.statusItemShows(isVisible: false, osMajor: 28, windowOnScreen: true))
    }

    // MARK: Re-add guidance (W5)

    func testReAddStepsShowAtOnceOnlyForAMissingAccessibilityGrantAfterAnEarlierLaunch() {
        XCTAssertTrue(HostUIRules.showsReAddStepsAtOnce(.accessibility, launchedBefore: true, granted: false))
        XCTAssertFalse(HostUIRules.showsReAddStepsAtOnce(.accessibility, launchedBefore: false, granted: false))
        XCTAssertFalse(HostUIRules.showsReAddStepsAtOnce(.accessibility, launchedBefore: true, granted: true))
        XCTAssertFalse(HostUIRules.showsReAddStepsAtOnce(.screenRecording, launchedBefore: true, granted: false))
    }
}
