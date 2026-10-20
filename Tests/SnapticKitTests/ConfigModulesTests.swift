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
        // 0.3: per-id defaults; Awake is shown when active (C11), so placement(.awake) is no longer .shared.
        for id in [ModuleID.windowSwitcher, .displays] { XCTAssertEqual(c.placement(id), .shared) }
        XCTAssertEqual(c.presence(.awake), .ownIconWhenActive)
        XCTAssertEqual(c.placement(.awake), .ownIcon)
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
        XCTAssertEqual(c.newModuleCards, [.displays, .awake])
        // 0.3 C7: upgraders get Awake off, shown when active.
        XCTAssertFalse(c.isEnabled(.awake))
        XCTAssertEqual(c.presence(.awake), .ownIconWhenActive)
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

    /// r1 U6: the updates page is in the run's pages whenever the run includes it, answered or not, so Done keeps
    /// its number.
    func testOnboardingPagesPutUpdatesBeforeDone() {
        var c = ModulesConfig()
        XCTAssertEqual(c.onboardingPages(includesUpdates: true),
                       [.step(.welcome), .step(.modules), .step(.displays), .step(.permissions), .updates, .step(.done)])
        XCTAssertEqual(c.onboardingPages(includesUpdates: false),
                       [.step(.welcome), .step(.modules), .step(.displays), .step(.permissions), .step(.done)])
        c.setEnabled(false, for: .displays)
        XCTAssertEqual(c.onboardingPages(includesUpdates: true),
                       [.step(.welcome), .step(.modules), .step(.permissions), .updates, .step(.done)])
    }

    /// r2 C2-1: on a first launch the window opens before the updater exists; the page joins when the updater starts
    /// and stays after the answer.
    func testTheUpdatesPageJoinsWhenTheUpdaterStartsAfterTheWindowOpened() {
        XCTAssertTrue(OnboardingUpdatesPage.asks(updaterExists: true, consentDecided: false))
        XCTAssertFalse(OnboardingUpdatesPage.asks(updaterExists: true, consentDecided: true))
        XCTAssertFalse(OnboardingUpdatesPage.asks(updaterExists: false, consentDecided: false))

        var page = OnboardingUpdatesPage()
        page.windowOpened(asks: false)      // bootstrap(): no updater yet
        XCTAssertFalse(page.included)
        page.refresh(asks: true)            // startUpdater(): the question is open
        XCTAssertTrue(page.included)
        page.refresh(asks: false)           // answered: the page keeps its place (U6)
        XCTAssertTrue(page.included)
        page.windowOpened(asks: false)      // a later run, after the answer
        XCTAssertFalse(page.included)

        var adHoc = OnboardingUpdatesPage()  // a build that can't update itself
        adHoc.windowOpened(asks: false)
        adHoc.refresh(asks: false)
        XCTAssertFalse(adHoc.included)

        var resumed = OnboardingUpdatesPage() // reopened later in the run, still unanswered
        resumed.windowOpened(asks: true)
        XCTAssertTrue(resumed.included)
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

    /// Review6 ux nit 7: the Menu Bar page's Snaptic icon tiles are live only while a Snaptic item exists.
    func testHasSnapticItem() {
        let all = Set(ModuleID.allCases)
        var c = ModulesConfig()
        XCTAssertTrue(c.hasSnapticItem(running: all), "defaults: every module in the Snaptic menu")
        for id in [ModuleID.windowSwitcher, .displays] { c.setPresence(.ownIcon, for: id) }
        c.setPresence(.ownIcon, for: .awake)
        XCTAssertFalse(c.hasSnapticItem(running: all), "every module Always Show: no Snaptic item")
        c.setPresence(.ownIconWhenActive, for: .awake)
        XCTAssertTrue(c.hasSnapticItem(running: all), "Awake's compact rows live in the Snaptic item at rest")
        c.setPresence(.hidden, for: .awake)
        XCTAssertFalse(c.hasSnapticItem(running: all))
        c.setPresence(.inSnapticMenu, for: .windowSwitcher)
        XCTAssertTrue(c.hasSnapticItem(running: all))
        XCTAssertFalse(c.hasSnapticItem(running: [.displays, .awake]), "a stopped module shows nothing")
        for id in ModuleID.allCases { c.setEnabled(false, for: id) }
        XCTAssertTrue(c.hasSnapticItem(running: []), "No Modules Are On is the Snaptic item")
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

    // MARK: 0.3 presence (M2)

    func testPerIDDefaults() {
        XCTAssertEqual(ModulesConfig.defaultPreferences(.windowSwitcher), ModulePreferences(enabled: true, presence: .inSnapticMenu))
        XCTAssertEqual(ModulesConfig.defaultPreferences(.displays), ModulePreferences(enabled: true, presence: .inSnapticMenu))
        XCTAssertEqual(ModulesConfig.defaultPreferences(.awake), ModulePreferences(enabled: true, presence: .ownIconWhenActive))
    }

    func testM2MapsStoredPlacementsWhilePresenceIsAbsent() throws {
        let json = #"""
        {"modules":{"windowSwitcher":{"enabled":true,"placement":"shared"},
                    "displays":{"enabled":true,"placement":"ownIcon","hideWithoutExternalDisplay":true},
                    "awake":{"enabled":true,"placement":"ownIcon"}}}
        """#
        let c = try decode(json)
        XCTAssertEqual(c.presence(.windowSwitcher), .inSnapticMenu)
        XCTAssertEqual(c.presence(.displays), .ownIconWhenActive)
        XCTAssertEqual(c.presence(.awake), .ownIconWhenActive)   // Awake's own icon → its default
        let hidden = try decode(#"{"modules":{"displays":{"placement":"hidden"},"awake":{"placement":"hidden"}}}"#)
        XCTAssertEqual(hidden.presence(.displays), .hidden)
        XCTAssertEqual(hidden.presence(.awake), .hidden)
        let own = try decode(#"{"modules":{"displays":{"placement":"ownIcon"}}}"#)
        XCTAssertEqual(own.presence(.displays), .ownIcon)
    }

    func testStoredPresenceWinsAndAnUnknownOneFallsBack() throws {
        let json = #"{"modules":{"awake":{"presence":"ownIcon","placement":"hidden"},"displays":{"presence":"teleport","placement":"hidden"}}}"#
        let c = try decode(json)
        XCTAssertEqual(c.presence(.awake), .ownIcon)
        XCTAssertEqual(c.presence(.displays), .hidden)
    }

    func testPresenceIsWrittenBackAsTheZeroTwoFields() throws {
        var c = ModulesConfig()
        c.setPresence(.ownIconWhenActive, for: .displays)
        c.setPresence(.hidden, for: .windowSwitcher)
        let text = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        struct Legacy: Decodable {
            struct Prefs: Decodable { var placement: MenuPlacementChoice; var hideWithoutExternalDisplay: Bool }
            var modules: [String: Prefs]
        }
        let legacy = try JSONDecoder().decode(Legacy.self, from: Data(text.utf8))
        XCTAssertEqual(legacy.modules["displays"]?.placement, .ownIcon)
        XCTAssertEqual(legacy.modules["displays"]?.hideWithoutExternalDisplay, true)
        XCTAssertEqual(legacy.modules["windowSwitcher"]?.placement, .hidden)
        XCTAssertEqual(try roundTrip(c), c)
    }

    func testZeroTwoRoundTripKeepsPresence() throws {
        // 0.3 → 0.2 (re-saves without `presence`) → 0.3.
        var c = ModulesConfig()
        c.setPresence(.ownIconWhenActive, for: .displays)
        c.setPresence(.inSnapticMenu, for: .awake)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stripped = String(decoding: try encoder.encode(c), as: UTF8.self)
            .replacingOccurrences(of: #""presence":"ownIconWhenActive","#, with: "")
            .replacingOccurrences(of: #""presence":"inSnapticMenu","#, with: "")
        XCTAssertFalse(stripped.contains("presence"))
        let back = try decode(stripped)
        XCTAssertEqual(back.presence(.displays), .ownIconWhenActive)
        XCTAssertEqual(back.presence(.awake), .inSnapticMenu)
    }

    func testZeroTwoSettersKeepPresenceInStep() {
        var c = ModulesConfig()
        c.setPlacement(.ownIcon, for: .displays)
        var p = c.preferences(.displays)
        p.hideWithoutExternalDisplay = true
        c.modules[.displays] = p
        XCTAssertEqual(c.presence(.displays), .ownIconWhenActive)
        c.setPlacement(.ownIcon, for: .displays)
        XCTAssertEqual(c.presence(.displays), .ownIconWhenActive)
        c.setPlacement(.shared, for: .displays)
        XCTAssertEqual(c.presence(.displays), .inSnapticMenu)
        c.resetMenu()
        XCTAssertEqual(c.presence(.awake), .ownIconWhenActive)
        XCTAssertEqual(c.presence(.displays), .inSnapticMenu)
    }

    func testSanitizeOnlyAllowsWhenActiveForDisplaysAndAwake() {
        var c = ModulesConfig()
        c.modules[.windowSwitcher] = ModulePreferences(enabled: true, presence: .ownIconWhenActive)
        XCTAssertEqual(c.sanitized().presence(.windowSwitcher), .ownIcon)
        c.setPresence(.ownIconWhenActive, for: .windowSwitcher)
        XCTAssertEqual(c.presence(.windowSwitcher), .ownIcon)
    }

    // MARK: 0.3 new-module cards (M3)

    func testNewModuleCardsDecodeLossilyAndDeduplicated() throws {
        let c = try decode(#"{"newModuleCards":["awake.migrated","teleport","displays","awake.migrated",4]}"#)
        XCTAssertEqual(c.newModuleCards, [.awakeMigrated, .displays])
        XCTAssertEqual(c.sanitized().newModuleCards, [.awakeMigrated, .displays])
        XCTAssertEqual(try roundTrip(c).newModuleCards, [.awakeMigrated, .displays])
    }

    func testM3RunsOnceAndRecordsItsMarker() {
        var c = ModulesConfig()
        c.showNewDisplaysCard = true
        var ledger = MigrationLedger()
        let once = c.migrated(ledger: &ledger)
        XCTAssertEqual(once.newModuleCards, [.displays])
        XCTAssertTrue(ledger.has(.newModuleCards))
        // The user dismisses the card; a second run must not bring it back.
        var dismissed = once
        dismissed.newModuleCards = []
        XCTAssertEqual(dismissed.migrated(ledger: &ledger), dismissed)
    }

    func testM3WithoutTheCardAddsNothing() {
        var ledger = MigrationLedger()
        XCTAssertEqual(ModulesConfig().migrated(ledger: &ledger).newModuleCards, [])
        XCTAssertTrue(ledger.has(.newModuleCards))
    }

    // MARK: Awake upgrader insertion (§2.13, marker awakeUpgrade.v1)

    /// One launch as ModuleHost runs it: the stored value (or the first-run value), M3, the Awake insertion, then
    /// M1's marker (recorded on every launch whatever M1 found); what it returns is what gets saved, so it goes
    /// through JSON like the store.
    private func launch(_ stored: ModulesConfig?, launchedBefore: Bool = true,
                        ledger: inout MigrationLedger) throws -> ModulesConfig {
        var c = stored ?? ModulesConfig.firstRun(launchedBefore: launchedBefore)
        c = c.migrated(ledger: &ledger)
        c = c.insertingAwakeForUpgrader(modulesExisted: stored != nil, ledger: &ledger)
        ledger.record(.fromDisplays)
        return try roundTrip(c)
    }

    /// A tester who installed a 0.3 build from before `awakeUpgrade.v1` existed (review5 ui N1): its launches
    /// recorded M3 and M1 but not this marker. The next build must not take it for a 0.2 upgrader.
    func testPreMarkerZeroThreeInstallIsNotAnUpgrader() throws {
        var ledger = MigrationLedger()
        ledger.record(.newModuleCards)
        ledger.record(.fromDisplays)
        var stored = ModulesConfig.firstRun(launchedBefore: false)
        stored.onboarding = .done
        XCTAssertNil(stored.modules[.awake])
        let c = try launch(stored, ledger: &ledger)
        XCTAssertNil(c.modules[.awake])
        XCTAssertTrue(c.isEnabled(.awake))
        XCTAssertFalse(c.newModuleCards.contains(.awake))
        XCTAssertTrue(ledger.has(.awakeUpgrade))
        // A 0.2 store has no ledger at all, so the same stored value from 0.2 is still an upgrade.
        var fresh = MigrationLedger()
        XCTAssertFalse(try launch(stored, ledger: &fresh).isEnabled(.awake))
    }

    func testFreshInstallKeepsAwakeOnAcrossLaunches() throws {
        var ledger = MigrationLedger()
        var c = try launch(nil, launchedBefore: false, ledger: &ledger)
        XCTAssertTrue(ledger.has(.awakeUpgrade))
        XCTAssertNil(c.modules[.awake])
        // Onboarding finished without touching the Awake switch: still no Awake entry stored.
        c.onboarding = .done
        for _ in 0..<3 {
            c = try launch(c, ledger: &ledger)
            XCTAssertTrue(c.isEnabled(.awake))
            XCTAssertEqual(c.presence(.awake), .ownIconWhenActive)
            XCTAssertFalse(c.newModuleCards.contains(.awake))
        }
    }

    func testResetKeepsThePerIDDefaults() throws {
        var ledger = MigrationLedger()
        var c = try launch(nil, launchedBefore: false, ledger: &ledger)
        c.setEnabled(false, for: .awake)
        c = try launch(c, ledger: &ledger)
        // General › Reset writes ModulesConfig() and relaunches; the ledger is kept.
        c = try launch(ModulesConfig(), ledger: &ledger)
        for id in ModuleID.allCases { XCTAssertEqual(c.preferences(id), ModulesConfig.defaultPreferences(id)) }
        XCTAssertTrue(c.isEnabled(.awake))
        XCTAssertEqual(c.newModuleCards, [])
    }

    func testZeroTwoUpgraderGetsAwakeOffAndItsCardOnce() throws {
        // A 0.2 store: module entries without Awake, no ledger (0.2 never writes it).
        var zeroTwo = ModulesConfig()
        zeroTwo.modules[.windowSwitcher] = ModulePreferences(enabled: true)
        zeroTwo.modules[.displays] = ModulePreferences(enabled: true)
        zeroTwo.onboarding = .done
        var ledger = MigrationLedger()
        var c = try launch(zeroTwo, ledger: &ledger)
        XCTAssertEqual(c.modules[.awake], ModulesConfig.awakeUpgradePreferences)
        XCTAssertFalse(c.isEnabled(.awake))
        XCTAssertEqual(c.newModuleCards, [.awake])
        XCTAssertTrue(ledger.has(.awakeUpgrade))
        // The user dismisses the card, then turns Awake on: later launches change neither.
        c.newModuleCards = []
        c = try launch(c, ledger: &ledger)
        XCTAssertEqual(c.newModuleCards, [])
        c.setEnabled(true, for: .awake)
        c = try launch(c, ledger: &ledger)
        XCTAssertTrue(c.isEnabled(.awake))
        XCTAssertEqual(c.newModuleCards, [])
        // Even a stored value that lost its Awake entry later is not an upgrade any more.
        c.modules[.awake] = nil
        XCTAssertTrue(try launch(c, ledger: &ledger).isEnabled(.awake))
    }

    func testZeroOneUpgraderGetsTheEntryFromTheUpgradeDefaultsOnly() throws {
        var ledger = MigrationLedger()
        let c = try launch(nil, launchedBefore: true, ledger: &ledger)
        XCTAssertFalse(c.isEnabled(.awake))
        XCTAssertEqual(c.newModuleCards, [.displays, .awake])
        XCTAssertTrue(ledger.has(.awakeUpgrade))
        XCTAssertEqual(try launch(c, ledger: &ledger), c)
    }

    func testAwakeInsertionKeepsAStoredAwakeEntry() {
        var c = ModulesConfig()
        c.modules[.awake] = ModulePreferences(enabled: true, presence: .ownIcon)
        var ledger = MigrationLedger()
        XCTAssertEqual(c.insertingAwakeForUpgrader(modulesExisted: true, ledger: &ledger), c)
        XCTAssertTrue(ledger.has(.awakeUpgrade))
    }

    func testTurningDisplaysOnRemovesItsCard() {
        var c = ModulesConfig.upgradeDefaults()
        c.newModuleCards = [.displays, .awakeMigrated]
        c.setEnabled(true, for: .displays)
        XCTAssertEqual(c.newModuleCards, [.awakeMigrated])
    }

    // MARK: 0.3 status items

    func testStatusItemPlanDefaultsKeepTheZeroTwoCallSitesCompiling() {
        let plan = StatusItemPlan(shared: [], ownIcon: [], showShared: true, noModulesEnabled: true, everythingHidden: false)
        XCTAssertEqual(plan.custom, [])
        XCTAssertFalse(plan.awakeCompactInShared)
        XCTAssertFalse(plan.sharedActiveGlyph)
        XCTAssertFalse(plan.sharedFooterInOwnMenus)
    }
}
