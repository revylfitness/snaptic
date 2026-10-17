import XCTest
@testable import SnapticKit

final class ConfigModulesTests: XCTestCase {
    private func roundTrip(_ c: ModulesConfig) throws -> ModulesConfig {
        try JSONDecoder().decode(ModulesConfig.self, from: JSONEncoder().encode(c))
    }

    private func decode(_ json: String) throws -> ModulesConfig {
        try JSONDecoder().decode(ModulesConfig.self, from: Data(json.utf8))
    }

    func testFreshDefaultsEnableEveryModuleInTheSharedMenu() {
        let c = ModulesConfig()
        XCTAssertEqual(c.enabledModules, ModuleID.allCases)
        for id in ModuleID.allCases { XCTAssertEqual(c.placement(id), .shared) }
        XCTAssertFalse(c.showNewDisplaysCard)
        XCTAssertFalse(c.commandLine.enabled)
        XCTAssertTrue(c.scrollSlidersToAdjust)
    }

    func testUpgradeKeepsSwitcherAndOffersDisplays() {
        let c = ModulesConfig.upgradeDefaults()
        XCTAssertTrue(c.isEnabled(.windowSwitcher))
        XCTAssertFalse(c.isEnabled(.displays))
        XCTAssertTrue(c.showNewDisplaysCard)
    }

    func testTurningDisplaysOnDismissesTheCard() {
        var c = ModulesConfig.upgradeDefaults()
        c.setEnabled(true, for: .displays)
        XCTAssertFalse(c.showNewDisplaysCard)
        XCTAssertEqual(c.enabledModules, [.windowSwitcher, .displays])
    }

    func testRoundTrip() throws {
        var c = ModulesConfig.upgradeDefaults()
        c.setPlacement(.ownIcon, for: .displays)
        c.setSymbol("sun.max", for: .displays)
        c.setVisibility(.hidden, of: DisplayMenuItemID(rawValue: "c.brightness"), default: .visible)
        c.commandLine = CommandLineSettings(enabled: true, maySkipConfirmation: false)
        c.sharedSymbol = "display"
        XCTAssertEqual(try roundTrip(c), c)
    }

    func testEmptyAndGarbageFieldsFallBack() throws {
        XCTAssertEqual(try decode("{}"), ModulesConfig())
        let c = try decode(#"{"modules":7,"menuItems":"x","sharedSymbol":3,"scrollSlidersToAdjust":"yes","commandLine":[]}"#)
        XCTAssertEqual(c, ModulesConfig())
    }

    func testBadEntriesAreDroppedIndividually() throws {
        let json = #"""
        {"modules":{"windowSwitcher":{"enabled":false},"displays":{"enabled":"maybe","placement":"sideways"},
                    "futureModule":{"enabled":true}},
         "menuItems":{"c.brightness":"hidden","d.mode":"nonsense","x":"inSubmenu"}}
        """#
        let c = try decode(json).sanitized()
        XCTAssertFalse(c.isEnabled(.windowSwitcher))
        XCTAssertTrue(c.isEnabled(.displays))                 // bad field → default
        XCTAssertEqual(c.placement(.displays), .shared)
        XCTAssertEqual(c.visibility(of: DisplayMenuItemID(rawValue: "c.brightness"), default: .visible), .hidden)
        XCTAssertEqual(c.visibility(of: DisplayMenuItemID(rawValue: "d.mode"), default: .inSubmenu), .inSubmenu)
        XCTAssertEqual(c.visibility(of: DisplayMenuItemID(rawValue: "x"), default: .visible), .inSubmenu)
    }

    func testUnknownModulesSurviveARoundTrip() throws {
        let json = #"{"modules":{"futureModule":{"enabled":true,"placement":"ownIcon"}}}"#
        let once = try decode(json)
        let data = try JSONEncoder().encode(once)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("futureModule"))
    }

    func testSanitizeRejectsUncuratedSymbolsAndBadItemIDs() throws {
        var c = ModulesConfig()
        c.modules[.displays] = ModulePreferences(enabled: true, placement: .ownIcon, symbol: "../../etc")
        c.sharedSymbol = "not.a.curated.symbol"
        c.menuItems[DisplayMenuItemID(rawValue: "")] = .hidden
        c.menuItems[DisplayMenuItemID(rawValue: "has space")] = .hidden
        c.menuItems[DisplayMenuItemID(rawValue: String(repeating: "a", count: 65))] = .hidden
        c.menuItems[DisplayMenuItemID(rawValue: "ok.item-1_x")] = .hidden
        let s = c.sanitized()
        XCTAssertEqual(s.preferences(.displays).symbol, "")
        XCTAssertEqual(s.sharedSymbol, "")
        XCTAssertEqual(Array(s.menuItems.values.keys), [DisplayMenuItemID(rawValue: "ok.item-1_x")])
        XCTAssertEqual(s.sanitized(), s)
    }

    func testMenuItemsAreCapped() {
        var c = ModulesConfig()
        for i in 0..<400 { c.menuItems[DisplayMenuItemID(rawValue: "item.\(i)")] = .hidden }
        XCTAssertEqual(c.sanitized().menuItems.values.count, ModulesConfig.maxMenuItems)
    }

    func testChoosingTheDefaultVisibilityRemovesTheEntry() {
        var c = ModulesConfig()
        let id = DisplayMenuItemID(rawValue: "c.volume")
        c.setVisibility(.hidden, of: id, default: .inSubmenu)
        XCTAssertNotNil(c.menuItems[id])
        c.setVisibility(.inSubmenu, of: id, default: .inSubmenu)
        XCTAssertNil(c.menuItems[id])
        c.setVisibility(.hidden, of: DisplayMenuItemID(rawValue: "bad id"), default: .visible)
        XCTAssertTrue(c.menuItems.values.isEmpty)
    }

    func testResetMenuKeepsEnableFlags() {
        var c = ModulesConfig.upgradeDefaults()
        c.setPlacement(.hidden, for: .windowSwitcher)
        c.setVisibility(.hidden, of: DisplayMenuItemID(rawValue: "a"), default: .visible)
        c.resetMenu()
        XCTAssertEqual(c.placement(.windowSwitcher), .shared)
        XCTAssertTrue(c.menuItems.values.isEmpty)
        XCTAssertFalse(c.isEnabled(.displays))
    }

    // MARK: Status items

    func testPlanWithNoModulesShowsSharedItemWithNotice() {
        var c = ModulesConfig()
        for id in ModuleID.allCases { c.setEnabled(false, for: id) }
        let plan = c.statusItemPlan(running: [])
        XCTAssertTrue(plan.showShared)
        XCTAssertTrue(plan.noModulesEnabled)
        XCTAssertFalse(plan.everythingHidden)
    }

    func testPlanPlacements() {
        var c = ModulesConfig()
        c.setPlacement(.ownIcon, for: .displays)
        let plan = c.statusItemPlan(running: [.windowSwitcher, .displays])
        XCTAssertEqual(plan.shared, [.windowSwitcher])
        XCTAssertEqual(plan.ownIcon, [.displays])
        XCTAssertTrue(plan.showShared)

        c.setPlacement(.ownIcon, for: .windowSwitcher)
        let own = c.statusItemPlan(running: [.windowSwitcher, .displays])
        XCTAssertFalse(own.showShared)
        XCTAssertEqual(own.ownIcon, [.windowSwitcher, .displays])
    }

    func testEverythingHidden() {
        var c = ModulesConfig()
        for id in ModuleID.allCases { c.setPlacement(.hidden, for: id) }
        let plan = c.statusItemPlan(running: Set(ModuleID.allCases))
        XCTAssertTrue(plan.everythingHidden)
        XCTAssertFalse(plan.showShared)
        XCTAssertTrue(plan.ownIcon.isEmpty)
    }

    func testDisabledModulesDontAppearEvenIfStillRunning() {
        var c = ModulesConfig()
        c.setEnabled(false, for: .displays)
        let plan = c.statusItemPlan(running: [.windowSwitcher, .displays])
        XCTAssertEqual(plan.shared, [.windowSwitcher])
    }

    // MARK: Transitions

    func testTransitionsStopInReverseAndStartInOrder() {
        let order = ModuleID.allCases
        let t = ModuleTransitions.plan(order: order, running: Set(order), desired: [])
        XCTAssertEqual(t.stop, Array(order.reversed()))
        XCTAssertEqual(t.start, [])
        let s = ModuleTransitions.plan(order: order, running: [], desired: Set(order))
        XCTAssertEqual(s.start, order)
        let none = ModuleTransitions.plan(order: order, running: [.displays], desired: [.displays])
        XCTAssertTrue(none.stop.isEmpty && none.start.isEmpty)
    }

    func testFuzzedTransitionsReachTheDesiredSet() {
        var rng = SeededGenerator(seed: 0x40D)
        let order = ModuleID.allCases
        for _ in 0..<1_000 {
            let running = Set(order.filter { _ in rng.next() % 2 == 0 })
            let desired = Set(order.filter { _ in rng.next() % 2 == 0 })
            let t = ModuleTransitions.plan(order: order, running: running, desired: desired)
            let after = running.subtracting(t.stop).union(t.start)
            XCTAssertEqual(after, desired)
            XCTAssertTrue(Set(t.stop).isDisjoint(with: t.start))
        }
    }
}
