import XCTest
@testable import SnapticKit

/// PLAN 0.3.1 A1–A5: the Snaptic menu's tabs (`MenuTabs`). The fuzzed invariants are in MenuLayoutTests.
final class MenuTabsTests: XCTestCase {
    private let all: [ModuleID] = [.windowSwitcher, .displays, .awake]

    private func plan(_ shared: [ModuleID], noModules: Bool = false) -> StatusItemPlan {
        StatusItemPlan(shared: shared, ownIcon: [], showShared: !shared.isEmpty || noModules,
                       noModulesEnabled: noModules, everythingHidden: false, awakeCompactInShared: shared.contains(.awake))
    }

    // MARK: Which tabs

    func testTabsOnlyWithTwoOrMoreModulesInPlanOrder() {
        XCTAssertEqual(MenuTabs.tabs(plan: plan([])), [])
        XCTAssertEqual(MenuTabs.tabs(plan: plan([], noModules: true)), [])
        for id in all { XCTAssertEqual(MenuTabs.tabs(plan: plan([id])), [], "one module keeps its 0.3 section") }
        XCTAssertEqual(MenuTabs.tabs(plan: plan([.windowSwitcher, .awake])), [.windowSwitcher, .awake])
        XCTAssertEqual(MenuTabs.tabs(plan: plan([.displays, .awake])), [.displays, .awake])
        XCTAssertEqual(MenuTabs.tabs(plan: plan(all)), all)
    }

    func testFreshInstallShowsThreeTabs() {
        let fresh = ModulesConfig().statusItemPlan(running: Set(all), awakeActive: false, displaysActive: false,
                                                   awakeShortcutBound: false, sharedShownAtRest: true)
        XCTAssertEqual(MenuTabs.tabs(plan: fresh), [.windowSwitcher, .displays, .awake])
    }

    // MARK: Selection (A5)

    func testSelectedDecodesLenientlyAndFallsBackToTheFirstTab() {
        let tabs: [ModuleID] = [.windowSwitcher, .displays, .awake]
        XCTAssertEqual(MenuTabs.selected(stored: "displays", tabs: tabs), .displays)
        XCTAssertEqual(MenuTabs.selected(stored: "awake", tabs: tabs), .awake)
        XCTAssertEqual(MenuTabs.selected(stored: " awake\n", tabs: tabs), .awake)
        for junk in [nil, "", "Displays", "pip", "displays.page", "0", "🙂"] as [String?] {
            XCTAssertEqual(MenuTabs.selected(stored: junk, tabs: tabs), .windowSwitcher, "\(String(describing: junk))")
        }
    }

    func testSelectedModuleThatIsNotATabNowShowsTheFirstTab() {
        XCTAssertEqual(MenuTabs.selected(stored: "awake", tabs: [.windowSwitcher, .displays]), .windowSwitcher)
        XCTAssertEqual(MenuTabs.selected(stored: "windowSwitcher", tabs: [.displays, .awake]), .displays)
        // The stored value is never rewritten by the fallback, so it comes back with its module.
        XCTAssertEqual(MenuTabs.selected(stored: "awake", tabs: [.windowSwitcher, .displays, .awake]), .awake)
    }

    func testNoTabsSelectsNothing() {
        XCTAssertNil(MenuTabs.selected(stored: "displays", tabs: []))
        XCTAssertNil(MenuTabs.selected(stored: nil, tabs: []))
    }

    func testDefaultsKeyIsThePlansKey() {
        XCTAssertEqual(MenuTabs.defaultsKey, "snapticMenuTab")
        for id in all { XCTAssertEqual(MenuTabs.selected(stored: id.rawValue, tabs: all), id, "round trip") }
    }

    // MARK: Label style (A1)

    func testLabelStyleTruthTable() {
        // available 272 (300 − 2 × 14): three segments fit equally up to 90.67 each.
        let a = 272.0
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [90, 60, 50], shortWidths: [60, 60, 50], imageWidth: 14,
                                           attention: [false, false, false], available: a), .fullEqual)
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [110, 60, 50], shortWidths: [60, 60, 50], imageWidth: 14,
                                           attention: [false, false, false], available: a), .shortEqual)
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [110, 95, 50], shortWidths: [91, 60, 50], imageWidth: 14,
                                           attention: [false, false, false], available: a), .shortFit)
        // Exactly fitting counts as fitting.
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [68, 68], shortWidths: [50, 50], imageWidth: 14,
                                           attention: [false, false], available: 136), .fullEqual)
    }

    func testLabelStyleCountsTheAttentionImage() {
        let a = 272.0
        // 80 fits alone; 80 + 14 on any segment makes every equal segment 94 wide: 282 > 272.
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [80, 60, 50], shortWidths: [60, 60, 50], imageWidth: 14,
                                           attention: [false, false, false], available: a), .fullEqual)
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [80, 60, 50], shortWidths: [60, 60, 50], imageWidth: 14,
                                           attention: [false, false, true], available: a), .fullEqual)
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [80, 60, 50], shortWidths: [60, 60, 50], imageWidth: 14,
                                           attention: [true, false, false], available: a), .shortEqual)
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [80, 60, 50], shortWidths: [80, 60, 50], imageWidth: 14,
                                           attention: [true, false, false], available: a), .shortFit)
        // A short attention list means "no mark" for the missing segments.
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [80, 60, 85], shortWidths: [60, 60, 50], imageWidth: 14,
                                           attention: [false], available: a), .fullEqual)
    }

    func testLabelStyleNeverTrustsBadWidths() {
        for bad in [Double.nan, .infinity, -1] {
            XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [bad, 10], shortWidths: [10, 10], imageWidth: 0,
                                               attention: [], available: 300), .shortEqual)
            XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [10, 10], shortWidths: [10, 10], imageWidth: bad,
                                               attention: [], available: 300), .shortFit)
            XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [10, 10], shortWidths: [10, 10], imageWidth: 0,
                                               attention: [], available: bad), .shortFit)
        }
        XCTAssertEqual(MenuTabs.labelStyle(fullWidths: [], shortWidths: [], imageWidth: 0, attention: [],
                                           available: 300), .shortFit)
    }

    func testLabelStyleFlags() {
        XCTAssertEqual(MenuTabs.LabelStyle.allCases.map(\.usesShortTitles), [false, true, true])
        XCTAssertEqual(MenuTabs.LabelStyle.allCases.map(\.fillsEqually), [true, true, false])
    }

    func testShortTitles() {
        XCTAssertEqual(all.map(\.shortTitle), ["Switcher", "Displays", "Awake"])
    }

    // MARK: Keys (A3)

    func testKeyIndicesArePositional() {
        let tabs: [ModuleID] = [.displays, .awake]
        XCTAssertEqual(MenuTabs.keyIndex(for: .displays, tabs: tabs), 1)
        XCTAssertEqual(MenuTabs.keyIndex(for: .awake, tabs: tabs), 2)
        XCTAssertNil(MenuTabs.keyIndex(for: .windowSwitcher, tabs: tabs))
        XCTAssertEqual(MenuTabs.tab(atKeyIndex: 1, tabs: tabs), .displays)
        XCTAssertEqual(MenuTabs.tab(atKeyIndex: 2, tabs: tabs), .awake)
        for n in [-1, 0, 3, 9, 10, Int.max, Int.min] { XCTAssertNil(MenuTabs.tab(atKeyIndex: n, tabs: tabs), "\(n)") }
        XCTAssertNil(MenuTabs.tab(atKeyIndex: 1, tabs: []))
    }

    func testKeyEventsMapToTabsByPosition() {
        func key(_ c: String?, _ code: UInt16 = 0, command: Bool = true, tabs: Int = 3) -> Int? {
            MenuTabs.keyIndex(characters: c, keyCode: code, commandOnly: command, tabCount: tabs)
        }
        XCTAssertEqual(key("1", 18), 1)
        XCTAssertEqual(key("2", 19), 2)
        XCTAssertEqual(key("3", 20), 3)
        XCTAssertNil(key("4", 21), "only as many as there are tabs")
        XCTAssertNil(key("3", 20, tabs: 2))
        XCTAssertEqual(key("2", 19, tabs: 2), 2)
        XCTAssertNil(key("1", 18, tabs: 1), "no tabs, no keys")
        XCTAssertNil(key("1", 18, tabs: 0))
        XCTAssertNil(key("1", 18, command: false), "⇧, ⌥, ⌃ or no ⌘")
        XCTAssertNil(key("0", 29))
        XCTAssertNil(key(",", 43), "⌘, stays Settings")
        XCTAssertNil(key("q", 12), "⌘Q stays Quit")
        // AZERTY's digit row types symbols: the physical key counts.
        XCTAssertEqual(key("&", 18), 1)
        XCTAssertEqual(key("é", 19), 2)
        XCTAssertEqual(key("\"", 20), 3)
        // A typed digit wins over the key's position (keypad, other layouts).
        XCTAssertEqual(key("2", 84), 2)
        XCTAssertEqual(key("1", 19), 1)
        XCTAssertNil(key(nil, 0))
        XCTAssertEqual(key("12", 18), 1, "not one digit: the key's position decides")
        XCTAssertNil(key("12", 0))
    }

    func testEveryDigitRowKeyCodeIsDistinctAndInRange() {
        var seen = Set<Int>()
        for code in UInt16(0)...UInt16(127) {
            guard let n = MenuTabs.keyIndex(characters: nil, keyCode: code, commandOnly: true, tabCount: 9) else { continue }
            XCTAssertTrue((1...9).contains(n))
            XCTAssertTrue(seen.insert(n).inserted, "key code \(code)")
        }
        XCTAssertEqual(seen, Set(1...9))
    }

    // MARK: Attention (A1)

    func testAttentionOnlyForTabsThatAskForIt() {
        let tabs: [ModuleID] = [.windowSwitcher, .displays, .awake]
        XCTAssertEqual(MenuTabs.attention([:], tabs: tabs), [])
        XCTAssertEqual(MenuTabs.attention([.displays: true, .windowSwitcher: false], tabs: tabs), [.displays])
        XCTAssertEqual(MenuTabs.attention([.displays: true, .windowSwitcher: true], tabs: tabs), [.windowSwitcher, .displays])
        XCTAssertEqual(MenuTabs.attention([.displays: true], tabs: [.windowSwitcher, .awake]), [], "not a tab")
        XCTAssertEqual(MenuTabs.attention([.displays: true], tabs: []), [])
    }

    // MARK: Text

    func testSpokenAndTooltipText() {
        XCTAssertEqual(MenuTabs.barLabel, "Menu tabs")
        XCTAssertEqual(MenuTabs.barHelp(tabCount: 3), "Press Command-1 to Command-3 to switch tabs.")
        XCTAssertEqual(MenuTabs.barHelp(tabCount: 2), "Press Command-1 to Command-2 to switch tabs.")
        XCTAssertEqual(MenuTabs.segmentLabel(title: "Displays", active: false, attention: false), "Displays")
        XCTAssertEqual(MenuTabs.segmentLabel(title: "Displays", active: false, attention: true),
                       "Displays, needs attention")
        XCTAssertEqual(MenuTabs.segmentLabel(title: "Awake", active: true, attention: false), "Awake, on")
        XCTAssertEqual(MenuTabs.segmentToolTip(title: "Window Switcher", keyIndex: 1, active: false),
                       "Window Switcher (⌘1)")
        XCTAssertEqual(MenuTabs.segmentToolTip(title: "Awake", keyIndex: 3, active: true), "Awake, on (⌘3)")
        XCTAssertEqual(MenuTabs.segmentToolTip(title: "Awake", keyIndex: nil, active: false), "Awake")
        XCTAssertEqual(MenuTabs.showTabTitle("Window Switcher"), "Show Window Switcher Tab")
        XCTAssertEqual(MenuTabs.showTabTitle("Displays"), "Show Displays Tab")
        XCTAssertEqual(MenuTabs.showTabTitle("Awake"), "Show Awake Tab")
        XCTAssertEqual(MenuTabs.emptySection, "Nothing to Show")
    }

    /// r1 U3: the segment's help is only its key, spelled out; the label already says the title and ", on".
    func testSegmentHelpIsTheKeySpelledOut() {
        XCTAssertEqual(MenuTabs.segmentHelp(keyIndex: 1), "Command-1")
        XCTAssertEqual(MenuTabs.segmentHelp(keyIndex: 3), "Command-3")
        XCTAssertEqual(MenuTabs.segmentHelp(keyIndex: 9), "Command-9")
        XCTAssertNil(MenuTabs.segmentHelp(keyIndex: nil))
        XCTAssertNil(MenuTabs.segmentHelp(keyIndex: 0))
        XCTAssertNil(MenuTabs.segmentHelp(keyIndex: 10), "past ⌘9 there is no key")
        for n in 1...9 {
            let help = MenuTabs.segmentHelp(keyIndex: n) ?? ""
            XCTAssertFalse(help.contains("⌘"), "VoiceOver would read the glyph")
            XCTAssertFalse(help.contains(", on"))
        }
    }

    // MARK: Assistive input

    /// r1 U2: Accessibility › Full Keyboard Access alone shows the Show … Tab items, as does each other input.
    func testShowTabItemsForEveryAssistiveInput() {
        XCTAssertFalse(MenuTabs.showsTabItems(voiceOver: false, switchControl: false, keyboardNavigation: false,
                                             fullKeyboardAccess: false))
        XCTAssertTrue(MenuTabs.showsTabItems(voiceOver: false, switchControl: false, keyboardNavigation: false,
                                            fullKeyboardAccess: true), "the accessibility feature, keyboard navigation off")
        XCTAssertTrue(MenuTabs.showsTabItems(voiceOver: false, switchControl: false, keyboardNavigation: true,
                                            fullKeyboardAccess: false))
        XCTAssertTrue(MenuTabs.showsTabItems(voiceOver: true, switchControl: false, keyboardNavigation: false,
                                            fullKeyboardAccess: false))
        XCTAssertTrue(MenuTabs.showsTabItems(voiceOver: false, switchControl: true, keyboardNavigation: false,
                                            fullKeyboardAccess: false))
    }

    func testFullKeyboardAccessPreference() {
        XCTAssertEqual(MenuTabs.fullKeyboardAccessDomain, "com.apple.Accessibility")
        XCTAssertEqual(MenuTabs.fullKeyboardAccessKey, "FullKeyboardAccessEnabled")
    }
}
