import XCTest
@testable import SnapticKit

final class BrightnessFirstReadTests: XCTestCase {
    private func wait(initialized: Bool = false, hardware: Bool = false, softwareOverride: Bool = false,
                      candidate: Bool = true, unknown: Bool = true, waited: Double = 0) -> Bool {
        BrightnessFirstRead.shouldWait(initialized: initialized, hardwareChosen: hardware, softwareOverride: softwareOverride,
                                       ddcCandidate: candidate, ddcUnknown: unknown, waited: waited)
    }

    func testWaitsForAPendingDDCProbe() {
        XCTAssertTrue(wait())
        XCTAssertTrue(wait(waited: 9.9))
    }

    func testStopsWaitingWhenAnythingIsKnown() {
        XCTAssertFalse(wait(initialized: true), "already managed: never re-wait")
        XCTAssertFalse(wait(hardware: true), "Apple or DDC answered")
        XCTAssertFalse(wait(softwareOverride: true), "the user chose gamma or overlay")
        XCTAssertFalse(wait(candidate: false), "not wired, or DDC brightness is off")
        XCTAssertFalse(wait(unknown: false), "the probe answered or failed")
    }

    func testTimeoutAndBadClocks() {
        XCTAssertFalse(wait(waited: BrightnessFirstRead.maxWaitSeconds))
        XCTAssertFalse(wait(waited: 3600))
        XCTAssertFalse(wait(waited: -1))
        XCTAssertFalse(wait(waited: .nan))
        XCTAssertFalse(wait(waited: .infinity))
    }
}
