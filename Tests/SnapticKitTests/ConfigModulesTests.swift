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
        XCTAssertEqual(c.otherApps, .pauseOverlapping)
        XCTAssertTrue(c.needsOnboarding)
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
        c.otherApps = .runBoth
        c.onboarding = .permissions
        c.onboardingPermissions = [.accessibility]
        c.commandLine = CommandLineSettings(enabled: true, maySkipConfirmation: false)
        c.sharedSymbol = "display"
        XCTAssertEqual(try roundTrip(c), c)
    }

    func testEmptyAndGarbageFieldsFallBack() throws {
        var empty = ModulesConfig()
        empty.onboarding = .done   // an older Snaptic wrote this: nothing to resume
        XCTAssertEqual(try decode("{}"), empty)
        let c = try decode(#"{"modules":7,"sharedSymbol":3,"commandLine":[],"otherApps":"x","onboarding":"nowhere"}"#)
        var expected = ModulesConfig()
        expected.onboarding = .done
        XCTAssertEqual(c, expected)
    }

    func testBadEntriesAreDroppedIndividually() throws {
        let json = #"""
        {"modules":{"windowSwitcher":{"enabled":false},"displays":{"enabled":"maybe","placement":"sideways"},
                    "futureModule":{"enabled":true}}}
        """#
        let c = try decode(json).sanitized()
        XCTAssertFalse(c.isEnabled(.windowSwitcher))
        XCTAssertTrue(c.isEnabled(.displays))                 // bad field → default
        XCTAssertEqual(c.placement(.displays), .shared)
    }

    func testUnknownModulesSurviveARoundTrip() throws {
        let json = #"{"modules":{"futureModule":{"enabled":true,"placement":"ownIcon"}}}"#
        let once = try decode(json)
        let data = try JSONEncoder().encode(once)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("futureModule"))
    }

    func testResetMenuKeepsEnableFlags() {
        var c = ModulesConfig.upgradeDefaults()
        c.setPlacement(.hidden, for: .windowSwitcher)
        c.sharedSymbol = "display"
        c.resetMenu()
        XCTAssertEqual(c.placement(.windowSwitcher), .shared)
        XCTAssertEqual(c.sharedSymbol, "")
        XCTAssertFalse(c.isEnabled(.displays))
    }

    func testSanitizeRejectsUncuratedSymbols() {
        var c = ModulesConfig()
        c.modules[.displays] = ModulePreferences(enabled: true, placement: .ownIcon, symbol: "../../etc")
        c.sharedSymbol = "not.a.curated.symbol"
        let s = c.sanitized()
        XCTAssertEqual(s.preferences(.displays).symbol, "")
        XCTAssertEqual(s.sharedSymbol, "")
        XCTAssertEqual(s.sanitized(), s)
    }

    // MARK: Onboarding

    func testUpgradedUsersSkipOnboarding() {
        XCTAssertFalse(ModulesConfig.upgradeDefaults().needsOnboarding)
    }

    func testOnboardingStepsFollowDisplaysToggle() {
        var c = ModulesConfig()
        XCTAssertEqual(c.onboardingSteps(), [.welcome, .modules, .displays, .permissions, .done])
        XCTAssertEqual(c.step(after: .modules), .displays)
        c.setEnabled(false, for: .displays)
        XCTAssertEqual(c.onboardingSteps(), [.welcome, .modules, .permissions, .done])
        XCTAssertEqual(c.step(after: .modules), .permissions)
        XCTAssertEqual(c.step(after: .permissions), .done)
        XCTAssertEqual(c.step(after: .done), .done)
    }

    func testResumeSkipsAStepThatNoLongerApplies() {
        var c = ModulesConfig()
        c.onboarding = .displays
        XCTAssertEqual(c.resumeStep, .displays)
        c.setEnabled(false, for: .displays)
        XCTAssertEqual(c.resumeStep, .permissions)
    }

    func testOnboardingPermissionsAreDedupedAndClearedWhenDone() throws {
        var c = ModulesConfig()
        c.onboarding = .permissions
        c.onboardingPermissions = [.screenRecording, .screenRecording, .accessibility]
        XCTAssertEqual(c.sanitized().onboardingPermissions, [.screenRecording, .accessibility])
        c.onboarding = .done
        XCTAssertEqual(c.sanitized().onboardingPermissions, [])
        let json = #"{"onboarding":"permissions","onboardingPermissions":["accessibility","teleport",3]}"#
        let decoded = try decode(json)
        XCTAssertEqual(decoded.onboarding, .permissions)
        XCTAssertEqual(decoded.onboardingPermissions, [])   // one bad element fails the list
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

    // MARK: First run (FIXES-R2 W1)

    func testFirstRunOfANewUserEqualsDefaultsSoTheWriteMustBeForced() throws {
        let fresh = ModulesConfig.firstRun(launchedBefore: false)
        // Equal to init(): no didSet change, nothing pending. Only a forced save writes it.
        XCTAssertEqual(fresh, ModulesConfig())
        XCTAssertFalse(ConfigSavePolicy.shouldWrite(hasPendingChange: false, force: false, everWritten: false))
        XCTAssertTrue(ConfigSavePolicy.shouldWrite(hasPendingChange: false, force: true, everWritten: false))
        // What is written keeps onboarding at Welcome on the next launch (a missing value
        // would decode as .done, the upgrader path).
        let stored = try roundTrip(fresh)
        XCTAssertTrue(stored.needsOnboarding)
        XCTAssertEqual(stored.resumeStep, .welcome)
        XCTAssertFalse(stored.showNewDisplaysCard)
        XCTAssertEqual(stored.enabledModules, ModuleID.allCases)
    }

    func testFirstRunOfAnEarlierUserIsTheUpgrade() {
        let c = ModulesConfig.firstRun(launchedBefore: true)
        XCTAssertEqual(c, ModulesConfig.upgradeDefaults())
        XCTAssertFalse(c.needsOnboarding)
        XCTAssertTrue(c.showNewDisplaysCard)
        XCTAssertFalse(c.isEnabled(.displays))
    }

    func testSavePolicy() {
        // A pending change is always written; force only matters before the first write.
        for force in [false, true] {
            for ever in [false, true] {
                XCTAssertTrue(ConfigSavePolicy.shouldWrite(hasPendingChange: true, force: force, everWritten: ever))
            }
        }
        XCTAssertFalse(ConfigSavePolicy.shouldWrite(hasPendingChange: false, force: true, everWritten: true))
        XCTAssertFalse(ConfigSavePolicy.shouldWrite(hasPendingChange: false, force: false, everWritten: true))
    }

    // MARK: Icons that need an external display (W16)

    func testIconsNeedExternalDisplay() {
        var c = ModulesConfig()
        XCTAssertFalse(c.iconsNeedExternalDisplay)       // shared item always shows
        c.setPlacement(.hidden, for: .windowSwitcher)
        c.setPlacement(.ownIcon, for: .displays)
        XCTAssertFalse(c.iconsNeedExternalDisplay)       // own icon without the hide option
        var p = c.preferences(.displays)
        p.hideWithoutExternalDisplay = true
        c.modules[.displays] = p
        XCTAssertTrue(c.iconsNeedExternalDisplay)
        c.setPlacement(.ownIcon, for: .windowSwitcher)
        XCTAssertFalse(c.iconsNeedExternalDisplay)       // the switcher's icon still shows
        c.setPlacement(.hidden, for: .windowSwitcher)
        c.setEnabled(false, for: .windowSwitcher)
        XCTAssertTrue(c.iconsNeedExternalDisplay)
        c.setEnabled(false, for: .displays)
        XCTAssertFalse(c.iconsNeedExternalDisplay)       // nothing enabled: the shared item shows
        c.setEnabled(true, for: .displays)
        c.setPlacement(.hidden, for: .displays)
        XCTAssertFalse(c.iconsNeedExternalDisplay)       // everything hidden has its own notice
    }
}
