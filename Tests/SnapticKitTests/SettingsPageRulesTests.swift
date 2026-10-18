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

    func testAwakeSectionOnlyWhenGiven() {
        let without = HostReport.sections(version: "v", system: "s", safeMode: false, modules: [], granted: [],
                                          commandLine: "Off")
        XCTAssertFalse(without.contains { $0.title == "Awake" })
        let with = HostReport.sections(version: "v", system: "s", safeMode: false, modules: [], granted: [],
                                       commandLine: "Off", awake: ["Assertion: display", "", "  plain line  "])
        XCTAssertEqual(with.last?.title, "Awake")
        XCTAssertEqual(with.last?.rows, [DiagnosticsRow("Assertion", "display"), DiagnosticsRow("Note", "plain line")])
        XCTAssertEqual(HostReport.sections(version: "v", system: "s", safeMode: false, modules: [], granted: [],
                                           commandLine: "Off", awake: []).last?.rows, [])
    }

    func testReportRowParsing() {
        XCTAssertNil(HostReport.row("   "))
        XCTAssertEqual(HostReport.row(": x"), DiagnosticsRow("Note", ": x"))
        XCTAssertEqual(HostReport.row("Rules: 2: on"), DiagnosticsRow("Rules", "2: on"))
    }

    // MARK: Window Switcher choices

    func testSpacesChoicesTurnTheFeatureOn() {
        for raw in SwitcherPageRules.spaces {
            XCTAssertEqual(SwitcherPageRules.effectiveSpace(raw, otherSpacesOn: true), raw)
            XCTAssertEqual(SwitcherPageRules.effectiveSpace(raw, otherSpacesOn: false), "current")
        }
        XCTAssertTrue(SwitcherPageRules.spaceChoiceTurnsOnOtherSpaces("all"))
        XCTAssertTrue(SwitcherPageRules.spaceChoiceTurnsOnOtherSpaces("others"))
        XCTAssertFalse(SwitcherPageRules.spaceChoiceTurnsOnOtherSpaces("current"))
        XCTAssertFalse(SwitcherPageRules.spaceChoiceTurnsOnOtherSpaces("bogus"))
    }

    func testWindowlessChoiceTurnsTheFeatureOn() {
        XCTAssertTrue(SwitcherPageRules.windowlessChoiceTurnsOnFeature(true))
        XCTAssertFalse(SwitcherPageRules.windowlessChoiceTurnsOnFeature(false))
        XCTAssertTrue(SwitcherPageRules.effectiveWindowless(true, featureOn: true))
        XCTAssertFalse(SwitcherPageRules.effectiveWindowless(true, featureOn: false))
        XCTAssertFalse(SwitcherPageRules.effectiveWindowless(false, featureOn: true))
    }

    /// Round 2 ui F2 / parity Q1: the 0.2 user with other Spaces off and both shortcuts stored as All Spaces sets ⌥⇥ to
    /// All Spaces; ⌥` keeps Current Space.
    func testSpacesChoiceKeepsOtherShortcutsAsShown() {
        let r = SwitcherPageRules.spacesChoice(["all", "all"], changed: 0, to: "all", otherSpacesOn: false)
        XCTAssertTrue(r.turnsOn)
        XCTAssertEqual(r.spaces, ["all", "current"])
        let on = SwitcherPageRules.spacesChoice(["all", "others"], changed: 1, to: "current", otherSpacesOn: true)
        XCTAssertFalse(on.turnsOn)
        XCTAssertEqual(on.spaces, ["all", "current"])
        let stayOff = SwitcherPageRules.spacesChoice(["others", "all"], changed: 1, to: "current", otherSpacesOn: false)
        XCTAssertFalse(stayOff.turnsOn)
        XCTAssertEqual(stayOff.spaces, ["others", "current"], "nothing turns on, so stored values stay")
        XCTAssertEqual(SwitcherPageRules.spacesChoice(["all"], changed: 3, to: "all", otherSpacesOn: false).spaces, ["all"])
    }

    func testWindowlessChoiceKeepsOtherShortcutsAsShown() {
        let r = SwitcherPageRules.windowlessChoice([false, true, true], changed: 0, to: true, featureOn: false)
        XCTAssertTrue(r.turnsOn)
        XCTAssertEqual(r.values, [true, false, false])
        let on = SwitcherPageRules.windowlessChoice([false, true], changed: 0, to: true, featureOn: true)
        XCTAssertFalse(on.turnsOn)
        XCTAssertEqual(on.values, [true, true])
        let off = SwitcherPageRules.windowlessChoice([true, true], changed: 1, to: false, featureOn: false)
        XCTAssertFalse(off.turnsOn)
        XCTAssertEqual(off.values, [true, false])
    }

    /// Any choice: every other shortcut reads exactly as before, and the chosen one reads as chosen whenever the
    /// feature is on afterwards.
    func testSeededSwitcherChoicesChangeOnlyTheChosenShortcut() {
        var g = SeededGenerator(seed: 0x5_A1C3)
        let raws = SwitcherPageRules.spaces + ["bogus"]
        for _ in 0..<2000 {
            let n = 1 + Int(g.next() % 5)
            let stored = (0..<n).map { _ in raws[Int(g.next() % UInt64(raws.count))] }
            let featureOn = g.next() % 2 == 0
            let changed = Int(g.next() % UInt64(n))
            let raw = SwitcherPageRules.spaces[Int(g.next() % 3)]
            let r = SwitcherPageRules.spacesChoice(stored, changed: changed, to: raw, otherSpacesOn: featureOn)
            let after = featureOn || r.turnsOn
            for i in 0..<n where i != changed {
                XCTAssertEqual(SwitcherPageRules.effectiveSpace(r.spaces[i], otherSpacesOn: after),
                               SwitcherPageRules.effectiveSpace(stored[i], otherSpacesOn: featureOn))
            }
            XCTAssertEqual(r.spaces[changed], raw)
            if raw != "current" { XCTAssertTrue(after) }

            let flags = (0..<n).map { _ in g.next() % 2 == 0 }
            let on = g.next() % 2 == 0
            let w = SwitcherPageRules.windowlessChoice(flags, changed: changed, to: on, featureOn: featureOn)
            let wAfter = featureOn || w.turnsOn
            for i in 0..<n where i != changed {
                XCTAssertEqual(SwitcherPageRules.effectiveWindowless(w.values[i], featureOn: wAfter),
                               SwitcherPageRules.effectiveWindowless(flags[i], featureOn: featureOn))
            }
            XCTAssertEqual(SwitcherPageRules.effectiveWindowless(w.values[changed], featureOn: wAfter), on)
        }
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
}

final class DefaultsLockTests: XCTestCase {
    func testWordingAndCommand() {
        XCTAssertEqual(DefaultsLock.text, "Turned off for this Mac by an administrator or a Terminal command.")
        XCTAssertFalse(DefaultsLock.text.lowercased().contains("defaults setting"))
        XCTAssertEqual(DefaultsLock.command(domain: "app.snaptic.Snaptic", key: "Modules.disable.awake"),
                       "defaults delete app.snaptic.Snaptic Modules.disable.awake")
        XCTAssertEqual(DefaultsLock.command(domain: "my app", key: "it's"), "defaults delete 'my app' 'it'\\''s'")
        XCTAssertEqual(DefaultsLock.command(domain: "", key: "k"), "defaults delete '' k")
        let details = DefaultsLock.details(domain: "app.snaptic.Snaptic", key: "Modules.disable.displays")
        XCTAssertTrue(details.contains("defaults delete app.snaptic.Snaptic Modules.disable.displays"))
        XCTAssertTrue(DefaultsLock.state(key: "Modules.disable.awake").contains("Modules.disable.awake"))
    }
}
