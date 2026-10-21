import XCTest
@testable import SnapticKit

final class BundleCopyTextTests: XCTestCase {
    func testStringsUseCurlyApostrophesOnly() {
        for text in [BundleCopyText.lidWritable, AwakeLidText.translocated, AwakeLidText.footer, AwakeLidText.menuBarHelp] {
            XCTAssertFalse(text.contains("'"), text)
            XCTAssertTrue(text.hasSuffix("."), text)
        }
    }

    /// The Lid closed section's translocated row and footer are Kit's lid texts (one copy of each).
    func testTranslocatedTextNamesTheFix() {
        XCTAssertTrue(AwakeLidText.translocated.hasPrefix("Snaptic is running from a temporary location."))
        XCTAssertTrue(AwakeLidText.translocated.contains("Applications"))
    }

    func testFooterStatesTheLimits() {
        XCTAssertTrue(AwakeLidText.footer.contains("at least 10%"))
        XCTAssertTrue(AwakeLidText.footer.contains("after 24 hours"))
    }

    func testHelpURLsPointAtTheReadmeSections() {
        let readme = "https://github.com/revylfitness/snaptic/blob/main/README.md"
        XCTAssertEqual(BundleCopyText.lidHelpURL, readme + "#keeping-awake-with-the-lid-closed")
        XCTAssertEqual(BundleCopyText.passwordHelpURL, readme + "#your-password-and-what-runs-as-root")
        XCTAssertEqual(BundleCopyText.leftoverHelpURL, readme + "#if-sleep-stays-off")
    }
}
