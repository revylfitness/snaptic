import XCTest
@testable import SnapticKit

final class BundleCopyTextTests: XCTestCase {
    func testStringsUseCurlyApostrophesOnly() {
        for text in [BundleCopyText.lidWritable, BundleCopyText.lidTranslocated, BundleCopyText.lidFooter] {
            XCTAssertFalse(text.contains("'"), text)
            XCTAssertTrue(text.hasSuffix("."), text)
        }
    }

    func testTranslocatedTextNamesTheFix() {
        XCTAssertTrue(BundleCopyText.lidTranslocated.hasPrefix("Snaptic is running from a temporary location."))
        XCTAssertTrue(BundleCopyText.lidTranslocated.contains("Applications"))
    }

    func testFooterStatesTheLimits() {
        XCTAssertTrue(BundleCopyText.lidFooter.contains("at least 10%"))
        XCTAssertTrue(BundleCopyText.lidFooter.contains("after 24 hours"))
    }

    func testHelpURLsPointAtTheReadmeSections() {
        let readme = "https://github.com/revylfitness/snaptic/blob/main/README.md"
        XCTAssertEqual(BundleCopyText.lidHelpURL, readme + "#keeping-awake-with-the-lid-closed")
        XCTAssertEqual(BundleCopyText.passwordHelpURL, readme + "#your-password-and-what-runs-as-root")
        XCTAssertEqual(BundleCopyText.leftoverHelpURL, readme + "#if-sleep-stays-off")
    }
}
