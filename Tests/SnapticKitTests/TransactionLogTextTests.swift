import XCTest
@testable import SnapticKit

final class TransactionLogTextTests: XCTestCase {
    func testSummaryUsesKindsAndCountsOnly() {
        let mode = ModeRef(ioModeID: 4, pixelWidth: 3024, pixelHeight: 1964, pointWidth: 1512, pointHeight: 982, refreshMilliHz: 60_000)
        XCTAssertEqual(TransactionLogText.summary([.mode(1, mode)]), "resolution on 1 display")
        XCTAssertEqual(TransactionLogText.summary([.origin(1, x: 0, y: 0), .main(2), .origin(2, x: 10, y: 0)]),
                       "arrangement x2, main display on 2 displays")
        XCTAssertEqual(TransactionLogText.summary([]), "no changes")
        XCTAssertEqual(TransactionLogText.summary([.enabled(3, false), .mirror(4, of: 3), .rotation(4, 90),
                                                   .underscan(4, 0.1), .hdr(4, true)]),
                       "connection, mirroring, rotation, underscan, HDR on 2 displays")
    }

    func testLineNeverCarriesALabel() {
        let line = TransactionLogText.line(changes: [.main(7)], risk: "trial", automatic: true, outcome: "kept")
        XCTAssertEqual(line, "Transaction (trial, automatic): main display on 1 display: kept")
        XCTAssertEqual(TransactionLogText.line(changes: [.hdr(1, false)], risk: "low", automatic: false, outcome: "applied"),
                       "Transaction (low): HDR on 1 display: applied")
    }
}
