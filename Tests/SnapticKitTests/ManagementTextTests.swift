import XCTest
@testable import SnapticKit

/// ux N1 (round 2): the display-management controllers' own strings (Keyboard Shortcuts titles, "Keep this change?"
/// labels, toasts, Display Information sections, new virtual display names) use the 0.3 words, not 0.2's.
final class ManagementTextTests: XCTestCase {
    private var userTexts: [String] {
        ManagementText.all
            + RecipeKind.allCases.flatMap { [$0.title, $0.summary] }
            + VirtualHostFailure.allCases.map(\.message)
            + [VirtualHostSpawnFailure.helpersStarting, .helpersUnavailable(""), .appChanged, .checkFailed,
               .launchFailed].map(\.message)
            + [Recipes.spec(for: .headless).name, VirtualScreenSpec(id: StableID(), name: " ", aspectWidth: 16,
                                                                    aspectHeight: 9, sizeInches: 27, hiDPI: true,
                                                                    modes: []).sanitized().name]
    }

    func testNoRetiredWords() {
        for text in userTexts {
            for word in ManagementText.retiredWords {
                XCTAssertFalse(text.contains(word), "“\(text)” contains “\(word)”")
            }
        }
    }

    /// The controllers' own strings name things in curly quotes and never call a display a screen.
    func testManagementStringsUseDisplayAndCurlyQuotes() {
        for text in ManagementText.all {
            XCTAssertFalse(text.lowercased().contains("screen"), text)
            XCTAssertFalse(text.contains("'"), text)
        }
    }

    func testTheReviewScenarioReadsInSharperTextWords() {
        XCTAssertEqual(ManagementText.turnOnSharperText, "Turn on sharper text")
        XCTAssertEqual(ManagementText.sharperTextDisplayName("DELL U2720Q"), "DELL U2720Q (Sharper Text)")
        XCTAssertEqual(ManagementText.sharperTextSection, DisplaysUIText.title(.smartHiDPI))
        XCTAssertEqual(ManagementText.virtualDisplaysSection, "Virtual displays")
        XCTAssertEqual(ManagementText.savedLayoutsSection, "Saved layouts")
    }

    /// An action's title is the menu item's title for the same action (one name per action).
    func testActionTitlesMatchTheMenu() {
        XCTAssertEqual(ManagementText.matchTextSize, "Match Text Size…")
        XCTAssertEqual(ManagementText.useAsMainDisplay, "Use as Main Display")
        XCTAssertEqual(ManagementText.toggleSharperText, "Toggle Sharper Text")
        XCTAssertEqual(ManagementText.toggleHighDynamicRange, "Toggle High Dynamic Range")
        XCTAssertEqual(ManagementText.toggleVirtualDisplay(2), "Toggle Virtual Display 2")
    }

    /// New names only: a stored virtual display keeps the name it has.
    func testStoredNamesAreKept() throws {
        let stored = #"{"id":"\#(StableID().rawValue)","name":"Office (Smart HiDPI)","aspectWidth":16,"aspectHeight":9}"#
        let spec = try JSONDecoder().decode(VirtualScreenSpec.self, from: Data(stored.utf8))
        XCTAssertEqual(spec.name, "Office (Smart HiDPI)")
        XCTAssertEqual(spec.sanitized().name, "Office (Smart HiDPI)")
        let unnamed = #"{"id":"\#(StableID().rawValue)","aspectWidth":16,"aspectHeight":9}"#
        XCTAssertEqual(try JSONDecoder().decode(VirtualScreenSpec.self, from: Data(unnamed.utf8)).name,
                       ManagementText.newVirtualDisplayName)
    }
}
