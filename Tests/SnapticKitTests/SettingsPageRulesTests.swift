import XCTest
@testable import SnapticKit

final class SettingsPageRulesTests: XCTestCase {
    // MARK: General cards

    func testNewModuleCardsShowWhileTheirModuleIsOff() {
        let all: [NewModuleCard] = [.displays, .awake]
        XCTAssertEqual(GeneralCardRules.visible(all, enabled: [], blocked: []), [.displays, .awake])
        XCTAssertEqual(GeneralCardRules.visible(all, enabled: [.displays], blocked: []), [.awake])
        XCTAssertEqual(GeneralCardRules.visible(all, enabled: [.displays, .awake], blocked: []), [])
    }

    func testMigrationNoticeShowsWhateverTheStateAndReplacesNewAwake() {
        let cards: [NewModuleCard] = [.awake, .awakeMigrated]
        XCTAssertEqual(GeneralCardRules.visible(cards, enabled: [.awake], blocked: []), [.awakeMigrated])
        XCTAssertEqual(GeneralCardRules.visible(cards, enabled: [], blocked: []), [.awakeMigrated])
    }

    func testBlockedModulesShowNoCards() {
        let cards: [NewModuleCard] = [.displays, .awake, .awakeMigrated]
        XCTAssertEqual(GeneralCardRules.visible(cards, enabled: [], blocked: [.awake]), [.displays])
        XCTAssertEqual(GeneralCardRules.visible(cards, enabled: [], blocked: [.awake, .displays]), [])
    }

    func testDuplicateCardsShowOnce() {
        XCTAssertEqual(GeneralCardRules.visible([.awake, .awake, .displays, .awake], enabled: [], blocked: []),
                       [.awake, .displays])
    }

    func testDismissingRemovesEveryCopyAndClearsTheDisplaysFlag() {
        var config = ModulesConfig()
        config.newModuleCards = [.displays, .awake, .displays]
        config.showNewDisplaysCard = true
        let afterDisplays = GeneralCardRules.dismissing(.displays, in: config)
        XCTAssertEqual(afterDisplays.newModuleCards, [.awake])
        XCTAssertFalse(afterDisplays.showNewDisplaysCard)
        let afterAwake = GeneralCardRules.dismissing(.awake, in: config)
        XCTAssertEqual(afterAwake.newModuleCards, [.displays, .displays])
        XCTAssertTrue(afterAwake.showNewDisplaysCard)
        XCTAssertEqual(GeneralCardRules.dismissing(.awakeMigrated, in: config), config)
    }

    func testCardModules() {
        XCTAssertEqual(GeneralCardRules.module(of: .displays), .displays)
        XCTAssertEqual(GeneralCardRules.module(of: .awake), .awake)
        XCTAssertEqual(GeneralCardRules.module(of: .awakeMigrated), .awake)
    }

    func testModuleChooserOnlyWithEveryChoosableModuleOff() {
        XCTAssertTrue(GeneralCardRules.showsModuleChooser(enabled: [], blocked: []))
        XCTAssertFalse(GeneralCardRules.showsModuleChooser(enabled: [.awake], blocked: []))
        // An enabled module that a defaults setting blocks doesn't run: the chooser still shows.
        XCTAssertTrue(GeneralCardRules.showsModuleChooser(enabled: [.awake], blocked: [.awake]))
        XCTAssertFalse(GeneralCardRules.showsModuleChooser(enabled: [], blocked: Set(ModuleID.allCases)))
    }

    func testRandomCardListsNeverShowDuplicatesOrBlockedModules() {
        var rng = SeededGenerator(seed: 0x5E77_1A65)
        for _ in 0..<500 {
            let count = Int(rng.next() % 7)
            let cards = (0..<count).map { _ in NewModuleCard.allCases[Int(rng.next() % UInt64(NewModuleCard.allCases.count))] }
            let enabled = Set(ModuleID.allCases.filter { _ in rng.next() & 1 == 0 })
            let blocked = Set(ModuleID.allCases.filter { _ in rng.next() & 1 == 0 })
            let shown = GeneralCardRules.visible(cards, enabled: enabled, blocked: blocked)
            XCTAssertEqual(shown.count, Set(shown).count)
            XCTAssertTrue(shown.allSatisfy { cards.contains($0) && !blocked.contains(GeneralCardRules.module(of: $0)) })
            XCTAssertFalse(shown.contains(.awake) && shown.contains(.awakeMigrated))
            for card in shown {
                var config = ModulesConfig()
                config.newModuleCards = cards
                XCTAssertFalse(GeneralCardRules.dismissing(card, in: config).newModuleCards.contains(card))
            }
        }
    }

    // MARK: Text

    func testSerialCommaLists() {
        XCTAssertEqual(SettingsText.list([]), "")
        XCTAssertEqual(SettingsText.list(["Awake"]), "Awake")
        XCTAssertEqual(SettingsText.list(["Window Switcher", "Displays"]), "Window Switcher and Displays")
        XCTAssertEqual(SettingsText.list(["Window Switcher", "Displays", "Awake"]), "Window Switcher, Displays, and Awake")
        XCTAssertEqual(SettingsText.list(["", "Displays", ""]), "Displays")
    }

    func testNeededBy() {
        XCTAssertEqual(SettingsText.neededBy(["Displays"]), "Needed by Displays.")
        XCTAssertEqual(SettingsText.neededBy([]), "Not needed by the features that are on.")
    }

    func testVersionLine() {
        XCTAssertEqual(SettingsText.version(short: "0.3.0", build: "45"), "Version 0.3.0 (45)")
        XCTAssertEqual(SettingsText.version(short: "0.3.0", build: "0.3.0"), "Version 0.3.0")
        XCTAssertEqual(SettingsText.version(short: "0.3.0", build: nil), "Version 0.3.0")
        XCTAssertEqual(SettingsText.version(short: nil, build: " "), "Version ?")
    }

    func testExitCodesListEveryCode() {
        let text = SettingsText.exitCodes
        for code in [ControlExit.ok, ControlExit.usage, ControlExit.notFound, ControlExit.refused, ControlExit.unavailable] {
            XCTAssertTrue(text.contains(String(code) + " "), String(code))
        }
        XCTAssertTrue(text.contains("6 "))
        XCTAssertTrue(text.contains("--json"))
    }

    // MARK: Host report

    func testHostReportSections() {
        let sections = HostReport.sections(version: "Version 0.3.0", system: "15.4", safeMode: true,
                                           modules: [HostReport.Module(title: "Awake", state: "Running")],
                                           granted: [.accessibility], commandLine: "Off")
        XCTAssertEqual(sections.map(\.title), ["Snaptic", "Modules", "Permissions"])
        XCTAssertEqual(sections[0].rows.first { $0.label == "Safe Mode" }?.value, "On")
        XCTAssertEqual(sections[1].rows, [DiagnosticsRow("Awake", "Running")])
        XCTAssertEqual(sections[2].rows, [DiagnosticsRow("Accessibility", "Allowed"),
                                          DiagnosticsRow("Screen Recording", "Not allowed")])
        let report = DiagnosticsText.report(header: "Snaptic", sections: sections, events: [])
        XCTAssertTrue(report.contains("- Accessibility: Allowed"))
    }

    // MARK: Window Switcher choices

    func testSpacesGating() {
        for raw in SwitcherPageRules.spaces {
            XCTAssertTrue(SwitcherPageRules.spaceChoiceEnabled(raw, otherSpacesOn: true))
            XCTAssertEqual(SwitcherPageRules.effectiveSpace(raw, otherSpacesOn: true), raw)
            XCTAssertEqual(SwitcherPageRules.effectiveSpace(raw, otherSpacesOn: false), "current")
        }
        XCTAssertFalse(SwitcherPageRules.spaceChoiceEnabled("all", otherSpacesOn: false))
        XCTAssertFalse(SwitcherPageRules.spaceChoiceEnabled("others", otherSpacesOn: false))
        XCTAssertTrue(SwitcherPageRules.spaceChoiceEnabled("current", otherSpacesOn: false))
    }

    func testStyleGating() {
        XCTAssertEqual(SwitcherPageRules.effectiveStyle("thumbnails", thumbnailsOn: false), "icons")
        XCTAssertEqual(SwitcherPageRules.effectiveStyle("titles", thumbnailsOn: false), "titles")
        XCTAssertEqual(SwitcherPageRules.effectiveStyle("thumbnails", thumbnailsOn: true), "thumbnails")
        XCTAssertFalse(SwitcherPageRules.styleChoiceEnabled("thumbnails", thumbnailsOn: false))
        XCTAssertTrue(SwitcherPageRules.styleChoiceEnabled("icons", thumbnailsOn: false))
        XCTAssertTrue(SwitcherPageRules.showsThumbnailOptions(style: "thumbnails", thumbnailsOn: true))
        XCTAssertFalse(SwitcherPageRules.showsThumbnailOptions(style: "thumbnails", thumbnailsOn: false))
        XCTAssertFalse(SwitcherPageRules.showsThumbnailOptions(style: "icons", thumbnailsOn: true))
    }

    func testDisabledChoicesKeepTheStoredValue() {
        XCTAssertEqual(SwitcherPageRules.write("all", current: "others", enabled: false), "others")
        XCTAssertEqual(SwitcherPageRules.write("all", current: "others", enabled: true), "all")
    }
}
