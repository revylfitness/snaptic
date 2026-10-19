import XCTest
@testable import SnapticKit

/// ux N1 (round 2): the display-management controllers' own strings (Keyboard Shortcuts titles, "Keep this change?"
/// labels, toasts, Display Information sections, new virtual display names) use the 0.3 words, not 0.2's.
final class ManagementTextTests: XCTestCase {
    private var userTexts: [String] {
        var texts: [String] = ManagementText.all
        texts += DisplaysToggleText.withMenuItems.map { $0.title }
        texts += RecipeKind.allCases.flatMap { [$0.title, $0.summary] }
        texts += VirtualHostFailure.allCases.map(\.message)
        let spawn: [VirtualHostSpawnFailure] = [.helpersStarting, .helpersUnavailable(""), .appChanged, .checkFailed,
                                                .launchFailed]
        texts += spawn.map(\.message)
        texts.append(Recipes.spec(for: .headless).name)
        texts.append(VirtualScreenSpec(id: StableID(), name: " ", aspectWidth: 16, aspectHeight: 9, sizeInches: 27,
                                       hiDPI: true, modes: []).sanitized().name)
        return texts
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
        XCTAssertEqual(ManagementText.sharperTextOnOff, "Sharper Text On or Off")
        XCTAssertEqual(ManagementText.highDynamicRangeOnOff, "High Dynamic Range On or Off")
        XCTAssertEqual(ManagementText.virtualDisplayOnOff(2), "Virtual Display 2 On or Off")
        XCTAssertEqual(ManagementText.mirroringOnOff, "Mirroring On or Off")
        XCTAssertEqual(ManagementText.builtInDisplayOnOff, "Built-in Display On or Off")
        // One verb pattern for switches across the Keyboard Shortcuts sheet (no "Toggle …").
        for title in ManagementText.all + [ManagementText.hiDPIOnOff] { XCTAssertFalse(title.hasPrefix("Toggle"), title) }
    }

    /// Review6 ux R3-2: every Displays switch's shortcut is "<menu item> On or Off", with the menu item's own words,
    /// so filtering Keyboard Shortcuts for the name seen in the menu finds it.
    func testOtherSwitchesAreMenuItemOnOrOff() throws {
        for (title, menuItem) in DisplaysToggleText.withMenuItems {
            XCTAssertTrue(title.hasSuffix(" On or Off"), title)
            XCTAssertFalse(title.hasPrefix("Toggle"), title)
            XCTAssertFalse(title.contains("'"), title)
            guard let menuItem else { continue }
            let info = try XCTUnwrap(DisplaysMenuPlan.info(for: DisplayMenuItemID(rawValue: menuItem)), menuItem)
            XCTAssertEqual(title, DisplaysToggleText.onOrOff(info.title), menuItem)
        }
        XCTAssertEqual(DisplaysToggleText.showInPictureInPicture, "Show in Picture in Picture On or Off")
        XCTAssertEqual(DisplaysToggleText.protectArrangement, "Protect Arrangement On or Off")
        XCTAssertEqual(DisplaysToggleText.mute, "Mute On or Off")
        XCTAssertEqual(DisplaysToggleText.invertColors, "Invert Colors On or Off")
        // Every title is distinct, and none collides with D's.
        let titles = DisplaysToggleText.withMenuItems.map { $0.title }
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(Set(titles).isDisjoint(with: ManagementText.all))
    }

    /// Quick Changes ▾ knows the notch state, so it names the change like "Turn On HiDPI" next to it.
    func testNotchAreaQuickChangeNamesTheChange() {
        XCTAssertEqual(ManagementText.notchAreaChange(turnsOn: true), "Turn On Notch Area")
        XCTAssertEqual(ManagementText.notchAreaChange(turnsOn: false), "Turn Off Notch Area")
        XCTAssertEqual(ManagementText.notchAreaOnOff, "Notch Area On or Off", "the shortcut keeps the switch title")
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
