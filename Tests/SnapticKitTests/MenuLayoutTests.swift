import XCTest
@testable import SnapticKit

/// PLAN 0.3 §5.2 / §6.6: presence × Awake active × Displays active × shortcut bound × shown at rest → plan.
final class MenuLayoutTests: XCTestCase {
    private let all = Set(ModuleID.allCases)

    private func config(switcher: MenuPresence = .inSnapticMenu, displays: MenuPresence = .inSnapticMenu,
                        awake: MenuPresence = .ownIconWhenActive, enabled: Set<ModuleID>? = nil) -> ModulesConfig {
        var c = ModulesConfig()
        let on = enabled ?? all
        c.modules[.windowSwitcher] = ModulePreferences(enabled: on.contains(.windowSwitcher), presence: switcher)
        c.modules[.displays] = ModulePreferences(enabled: on.contains(.displays), presence: displays)
        c.modules[.awake] = ModulePreferences(enabled: on.contains(.awake), presence: awake)
        return c
    }

    private func plan(_ c: ModulesConfig, running: Set<ModuleID>? = nil, active: Bool = false,
                      displaysActive: Bool = true, bound: Bool = false, atRest: Bool = true) -> StatusItemPlan {
        c.statusItemPlan(running: running ?? all, awakeActive: active, displaysActive: displaysActive,
                         awakeShortcutBound: bound, sharedShownAtRest: atRest)
    }

    // MARK: Defaults

    func testFreshDefaultsAtRestShowEverySectionInTheSnapticItem() {
        let p = plan(ModulesConfig())
        XCTAssertEqual(p.shared, [.windowSwitcher, .displays, .awake])
        XCTAssertTrue(p.awakeCompactInShared)
        XCTAssertTrue(p.showShared)
        XCTAssertEqual(p.ownIcon, [])
        XCTAssertEqual(p.custom, [])
        XCTAssertFalse(p.sharedActiveGlyph)
        XCTAssertFalse(p.sharedFooterInOwnMenus)
        XCTAssertFalse(p.noModulesEnabled)
        XCTAssertFalse(p.everythingHidden)
    }

    func testFreshDefaultsDuringASessionAddTheAwakeItemAndKeepTheCompactSection() {
        let p = plan(ModulesConfig(), active: true)
        XCTAssertEqual(p.shared, [.windowSwitcher, .displays, .awake])
        XCTAssertEqual(p.custom, [.awake])
        XCTAssertTrue(p.awakeCompactInShared)
        XCTAssertTrue(p.sharedActiveGlyph)
    }

    // MARK: Awake presence

    func testShowWhenActiveAloneKeepsTheSnapticItemForTheCompactSection() {
        let c = config(switcher: .ownIcon, displays: .ownIcon, awake: .ownIconWhenActive)
        let rest = plan(c)
        XCTAssertEqual(rest.shared, [.awake])
        XCTAssertEqual(rest.ownIcon, [.windowSwitcher, .displays])
        XCTAssertEqual(rest.custom, [])
        XCTAssertTrue(rest.showShared)

        // Shown at rest → it stays during the session, still with the compact section (parity M5).
        let kept = plan(c, active: true, atRest: true)
        XCTAssertEqual(kept.shared, [.awake])
        XCTAssertEqual(kept.custom, [.awake])
        XCTAssertTrue(kept.sharedActiveGlyph)
        XCTAssertFalse(kept.sharedFooterInOwnMenus)

        // Not shown at rest → only the Awake item, and the own menus carry the footer.
        let fresh = plan(c, active: true, atRest: false)
        XCTAssertEqual(fresh.shared, [])
        XCTAssertFalse(fresh.showShared)
        XCTAssertEqual(fresh.custom, [.awake])
        XCTAssertFalse(fresh.sharedActiveGlyph)
        XCTAssertTrue(fresh.sharedFooterInOwnMenus)
    }

    func testAlwaysShowIsAnOwnItemInEveryState() {
        let c = config(awake: .ownIcon)
        for active in [false, true] {
            for atRest in [false, true] {
                let p = plan(c, active: active, atRest: atRest)
                XCTAssertEqual(p.custom, [.awake])
                XCTAssertFalse(p.awakeCompactInShared)
                XCTAssertEqual(p.shared, [.windowSwitcher, .displays])
                XCTAssertEqual(p.sharedActiveGlyph, active)
            }
        }
    }

    func testShowInSnapticMenuIsTheCompactSectionInEveryState() {
        let c = config(switcher: .ownIcon, displays: .hidden, awake: .inSnapticMenu)
        for active in [false, true] {
            for atRest in [false, true] {
                let p = plan(c, active: active, atRest: atRest)
                XCTAssertEqual(p.shared, [.awake])
                XCTAssertTrue(p.awakeCompactInShared)
                XCTAssertEqual(p.custom, [])
                XCTAssertEqual(p.sharedActiveGlyph, active)
                XCTAssertEqual(p.ownIcon, [.windowSwitcher])
            }
        }
    }

    func testDontShowWithABoundShortcut() {
        let c = config(awake: .hidden)
        let rest = plan(c, bound: true)
        XCTAssertEqual(rest.shared, [.windowSwitcher, .displays])
        XCTAssertEqual(rest.custom, [])
        // The Snaptic item exists: only its active glyph shows the session.
        let active = plan(c, active: true, bound: true)
        XCTAssertEqual(active.custom, [])
        XCTAssertTrue(active.sharedActiveGlyph)
        XCTAssertFalse(active.awakeCompactInShared)
        // No Snaptic item: the Awake item appears for the session (N11).
        let alone = config(switcher: .ownIcon, displays: .hidden, awake: .hidden)
        XCTAssertEqual(plan(alone, bound: true).custom, [])
        let session = plan(alone, active: true, bound: true)
        XCTAssertEqual(session.custom, [.awake])
        XCTAssertFalse(session.showShared)
        XCTAssertTrue(session.sharedFooterInOwnMenus)
    }

    func testDontShowWithoutAShortcutStillGetsAnItemWhileActive() {
        let c = config(awake: .hidden)
        XCTAssertEqual(plan(c, bound: false).custom, [])
        let active = plan(c, active: true, bound: false)
        XCTAssertEqual(active.custom, [.awake])
        XCTAssertTrue(active.sharedActiveGlyph)
    }

    func testDontShowFallbackAndSelectability() {
        XCTAssertEqual(config(awake: .hidden).awakePresenceFallback(awakeRunning: true, awakeShortcutBound: false),
                       .ownIconWhenActive)
        XCTAssertNil(config(awake: .hidden).awakePresenceFallback(awakeRunning: true, awakeShortcutBound: true))
        for presence in [MenuPresence.ownIcon, .ownIconWhenActive, .inSnapticMenu] {
            XCTAssertNil(config(awake: presence).awakePresenceFallback(awakeRunning: true, awakeShortcutBound: false))
        }
        // Applying the fallback gives a plan in which Awake is reachable at rest.
        var c = config(switcher: .hidden, displays: .hidden, awake: .hidden)
        XCTAssertTrue(plan(c).everythingHidden)
        if let fallback = c.awakePresenceFallback(awakeRunning: true, awakeShortcutBound: false) {
            c.setPresence(fallback, for: .awake)
        }
        let p = plan(c)
        XCTAssertFalse(p.everythingHidden)
        XCTAssertEqual(p.shared, [.awake])

        // Awake off: nothing to move (and no toast); the check runs again when it turns on.
        XCTAssertNil(config(awake: .hidden, enabled: [.displays])
            .awakePresenceFallback(awakeRunning: false, awakeShortcutBound: false))
        // ui N3: enabled but not running (a defaults setting turned it off): no fallback, so no toast either.
        XCTAssertNil(config(awake: .hidden).awakePresenceFallback(awakeRunning: false, awakeShortcutBound: false))

        XCTAssertFalse(MenuLayout.isSelectable(.hidden, for: .awake, awakeShortcutBound: false))
        XCTAssertTrue(MenuLayout.isSelectable(.hidden, for: .awake, awakeShortcutBound: true))
        XCTAssertTrue(MenuLayout.isSelectable(.hidden, for: .windowSwitcher, awakeShortcutBound: false))
        XCTAssertFalse(MenuLayout.isSelectable(.ownIconWhenActive, for: .windowSwitcher, awakeShortcutBound: true))
        XCTAssertTrue(MenuLayout.isSelectable(.ownIconWhenActive, for: .displays, awakeShortcutBound: false))
    }

    /// The fallback's toast and the Menu Bar footer name where Awake went and why, one text per reason; a
    /// registered shortcut has neither (parity #2, code M1).
    func testFallbackWordsPerShortcutStatus() {
        var texts = Set<String>()
        for status in MenuLayout.AwakeShortcutStatus.allCases {
            let notice = MenuLayout.awakeFallbackNotice(status)
            let hint = MenuLayout.awakeHideHint(status)
            if status == .registered {
                XCTAssertNil(notice)
                XCTAssertNil(hint)
                XCTAssertTrue(status.isBound)
                continue
            }
            XCTAssertFalse(status.isBound)
            guard let notice, let hint else { return XCTFail("\(status) needs words") }
            XCTAssertTrue(notice.contains("menu bar"))
            XCTAssertTrue(notice.contains("shortcut"))
            XCTAssertTrue(hint.contains("hide") || hint.contains("hidden"))
            XCTAssertTrue(texts.insert(notice).inserted)
            XCTAssertTrue(texts.insert(hint).inserted)
        }
    }

    /// ux m16 / code N3: the Snaptic item never shows the glyph of an own icon shown now; the default is never
    /// stored explicitly, so no choice pins a glyph that collides later.
    func testSnapticGlyphStepsAsideForAnOwnIconWithTheSameGlyph() {
        let switcher = MenuLayout.snapticSymbol
        XCTAssertEqual(MenuLayout.sharedSymbol(stored: "", ownIconSymbols: []), switcher)
        XCTAssertEqual(MenuLayout.sharedSymbol(stored: "", ownIconSymbols: ["display.2"]), switcher)
        XCTAssertEqual(MenuLayout.sharedSymbol(stored: "", ownIconSymbols: [switcher]), MenuLayout.snapticAlternateSymbol)
        XCTAssertEqual(MenuLayout.sharedSymbol(stored: "circle.grid.cross", ownIconSymbols: [switcher]), "circle.grid.cross")
        // An explicit default stored by an earlier build steps aside too.
        XCTAssertEqual(MenuLayout.sharedSymbol(stored: switcher, ownIconSymbols: [switcher]), MenuLayout.snapticAlternateSymbol)
        XCTAssertEqual(MenuLayout.sharedSymbol(stored: MenuLayout.snapticAlternateSymbol,
                                               ownIconSymbols: [MenuLayout.snapticAlternateSymbol]), switcher)
        XCTAssertNotEqual(MenuLayout.snapticAlternateSymbol, switcher)
        XCTAssertEqual(MenuLayout.snapticSymbols.first, switcher)

        // Choosing: the default is always stored as "" (it steps aside by itself); anything else as is.
        XCTAssertEqual(MenuLayout.storedSharedSymbol(chosen: switcher), "")
        XCTAssertEqual(MenuLayout.storedSharedSymbol(chosen: "square.grid.2x2"), "square.grid.2x2")

        // The code N3 scenario: the page chose while nothing collided; a Window Switcher or Displays icon with the
        // same glyph appears later; the two items still differ.
        let stored = MenuLayout.storedSharedSymbol(chosen: switcher)
        XCTAssertNotEqual(MenuLayout.sharedSymbol(stored: stored, ownIconSymbols: [switcher]), switcher)

        // Tiles: never a glyph an own icon shows, always the one the Snaptic item shows; round trip: tapping a
        // tile makes the item show that tile.
        let pool = MenuLayout.snapticSymbols + ["display", "rectangle.stack"]
        var rng = SeededGenerator(seed: 0x61_7970_68)
        for _ in 0..<2_000 {
            let own = pool.filter { _ in rng.next() % 3 == 0 }
            let storedNow = rng.next() % 3 == 0 ? "" : pool[Int(rng.next() % UInt64(pool.count))]
            let shown = MenuLayout.sharedSymbol(stored: storedNow, ownIconSymbols: own)
            let tiles = MenuLayout.snapticSymbolChoices(stored: storedNow, ownIconSymbols: own)
            XCTAssertTrue(tiles.contains(shown))
            XCTAssertEqual(tiles.count, Set(tiles).count)
            if MenuLayout.snapticSymbols.contains(where: { !own.contains($0) }) {
                XCTAssertFalse(own.contains(shown), "\(storedNow) \(own)")
                XCTAssertTrue(tiles.allSatisfy { !own.contains($0) })
            }
            for chosen in tiles {
                let value = MenuLayout.storedSharedSymbol(chosen: chosen)
                XCTAssertNotEqual(value, switcher, "the default is never stored explicitly")
                XCTAssertEqual(MenuLayout.sharedSymbol(stored: value, ownIconSymbols: own), chosen)
            }
        }
    }

    func testKeepAwakeShortcutStatus() {
        typealias S = MenuLayout.AwakeShortcutStatus
        var shortcuts = LossyMap<AwakeActionID, HotkeyCombo>()
        let keep = MenuLayout.keepAwakeAction
        XCTAssertEqual(keep.rawValue, "awake.toggle")
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [], registered: false), S.notSet)
        shortcuts[AwakeActionID(rawValue: "awake.preset1")] = HotkeyCombo(keyCode: 0, carbonModifiers: 0x0100)
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [], registered: false), S.notSet)
        shortcuts[keep] = HotkeyCombo(keyCode: 1, carbonModifiers: 0x0100)
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [], registered: true), S.registered)
        // Set but not registered: another app or macOS has it, or Awake's shortcuts are off (kill switch, backup;
        // ui F3 / code M1 / parity Q2: a stored combo alone no longer counts as bound).
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [keep], registered: false), S.failed)
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [], registered: false), S.turnedOff)
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [AwakeActionID(rawValue: "awake.preset1")],
                                                      registered: false), S.turnedOff)
        // The registered flag is the truth macOS delivers; it wins over a stale failure.
        XCTAssertEqual(MenuLayout.awakeShortcutStatus(shortcuts, failed: [keep], registered: true), S.registered)
        // Only `registered` keeps a hidden Awake.
        for status in S.allCases {
            XCTAssertEqual(MenuLayout.isSelectable(.hidden, for: .awake, awakeShortcutBound: status.isBound),
                           status == .registered)
            XCTAssertEqual(config(awake: .hidden).awakePresenceFallback(awakeRunning: true,
                                                                       awakeShortcutBound: status.isBound) == nil,
                           status == .registered)
        }
    }

    /// The Menu Bar page decides the Snaptic glyph from the same own icons as the live plan (code N3).
    func testOwnIconIDsMatchThePlan() {
        let c = config(switcher: .ownIcon, displays: .ownIconWhenActive)
        XCTAssertEqual(c.ownIconIDs(running: all, displaysActive: false), [.windowSwitcher])
        XCTAssertEqual(c.ownIconIDs(running: all, displaysActive: true), [.windowSwitcher, .displays])
        // Turned off by a defaults setting (enabled, not running): no icon, so nothing to step aside for.
        XCTAssertEqual(c.ownIconIDs(running: [.displays, .awake], displaysActive: true), [.displays])
        XCTAssertEqual(config(switcher: .ownIcon, enabled: [.displays]).ownIconIDs(running: all, displaysActive: true), [])
        XCTAssertEqual(config(awake: .ownIcon).ownIconIDs(running: all, displaysActive: true), [])
    }

    // MARK: Displays and the Switcher

    func testDisplaysShowWhenActiveFollowsTheExternalDisplay() {
        let c = config(displays: .ownIconWhenActive)
        XCTAssertEqual(plan(c, displaysActive: false).ownIcon, [])
        XCTAssertEqual(plan(c, displaysActive: true).ownIcon, [.displays])
        XCTAssertEqual(plan(c, displaysActive: false).shared, [.windowSwitcher, .awake])
        // An unsanitized "when active" Switcher is an own icon.
        let odd = config(switcher: .ownIconWhenActive)
        XCTAssertEqual(plan(odd, displaysActive: false).ownIcon, [.windowSwitcher])
    }

    func testOwnIconsKeepStartOrderAndNeverHoldAwake() {
        let c = config(switcher: .ownIcon, displays: .ownIcon, awake: .ownIcon)
        let p = plan(c, active: true)
        XCTAssertEqual(p.ownIcon, [.windowSwitcher, .displays])
        XCTAssertEqual(p.custom, [.awake])
        XCTAssertFalse(p.showShared)
        XCTAssertTrue(p.sharedFooterInOwnMenus)
    }

    // MARK: Snaptic item existence

    func testNoModuleEnabledShowsTheSnapticItem() {
        let p = plan(config(enabled: []), running: [], active: true)
        XCTAssertTrue(p.noModulesEnabled)
        XCTAssertTrue(p.showShared)
        XCTAssertEqual(p.shared, [])
        XCTAssertEqual(p.custom, [])
        XCTAssertFalse(p.everythingHidden)
        XCTAssertFalse(p.sharedActiveGlyph)
        XCTAssertFalse(p.sharedFooterInOwnMenus)
    }

    func testEverythingDontShowMeansNoItem() {
        let c = config(switcher: .hidden, displays: .hidden, awake: .hidden)
        let p = plan(c, bound: true)
        XCTAssertTrue(p.everythingHidden)
        XCTAssertFalse(p.showShared)
        XCTAssertEqual(p.ownIcon, [])
        XCTAssertEqual(p.custom, [])
        XCTAssertFalse(p.sharedFooterInOwnMenus)
        // A session still shows itself, so "no item at all" is false meanwhile.
        let active = plan(c, active: true, bound: true)
        XCTAssertFalse(active.everythingHidden)
        XCTAssertEqual(active.custom, [.awake])
        XCTAssertTrue(active.sharedFooterInOwnMenus)
    }

    func testEnabledModulesThatDontRunShowNothing() {
        let p = plan(ModulesConfig(), running: [.windowSwitcher], active: true)
        XCTAssertEqual(p.shared, [.windowSwitcher])
        XCTAssertEqual(p.custom, [])
        XCTAssertFalse(p.awakeCompactInShared)
        XCTAssertFalse(p.sharedActiveGlyph, "Awake doesn't run, so it can't govern")
    }

    func testDisabledAwakeIgnoresActivity() {
        let c = config(enabled: [.windowSwitcher, .displays])
        let p = plan(c, active: true)
        XCTAssertEqual(p.shared, [.windowSwitcher, .displays])
        XCTAssertEqual(p.custom, [])
        XCTAssertFalse(p.sharedActiveGlyph)
    }

    func testOnlyAwakeEnabled() {
        let c = config(enabled: [.awake])
        XCTAssertEqual(plan(c).shared, [.awake])
        let p = plan(c, active: true, atRest: true)
        XCTAssertEqual(p.shared, [.awake])
        XCTAssertEqual(p.custom, [.awake])
        XCTAssertFalse(p.noModulesEnabled)
    }

    // MARK: Shown-at-rest resolution

    func testSharedExistsNowResolvesTheMemory() {
        // A session restored at launch with the default setup: the Snaptic item would exist at rest, so the compact
        // section stays in it from the first plan on.
        let c = ModulesConfig()
        let launch = c.statusItemPlan(running: all, awakeActive: true, displaysActive: true, awakeShortcutBound: false,
                                      sharedExistsNow: false)
        XCTAssertTrue(launch.awakeCompactInShared)
        XCTAssertEqual(launch.custom, [.awake])

        // The item exists although the configuration alone wouldn't need it during a session.
        let mine = config(switcher: .ownIcon, displays: .ownIcon, awake: .ownIconWhenActive)
        let kept = mine.statusItemPlan(running: all, awakeActive: true, displaysActive: true, awakeShortcutBound: false,
                                       sharedExistsNow: true)
        XCTAssertTrue(kept.showShared)
        // At rest the memory doesn't matter.
        let rest = mine.statusItemPlan(running: all, awakeActive: false, displaysActive: true, awakeShortcutBound: false,
                                       sharedExistsNow: false)
        XCTAssertEqual(rest, plan(mine))
    }

    func testZeroTwoEntryPointIsTheIdlePlan() {
        let c = config(switcher: .ownIcon, displays: .ownIconWhenActive, awake: .inSnapticMenu)
        XCTAssertEqual(c.statusItemPlan(running: all), plan(c, displaysActive: true, bound: false, atRest: true))
    }

    // MARK: MenuPresence (lead's type, tested here per §6.6)

    func testAllowedPresencesAndLegacyPlacement() {
        XCTAssertEqual(MenuPresence.allowed(for: .windowSwitcher), [.ownIcon, .inSnapticMenu, .hidden])
        XCTAssertEqual(MenuPresence.allowed(for: .displays), MenuPresence.allCases)
        XCTAssertEqual(MenuPresence.allowed(for: .awake), MenuPresence.allCases)
        XCTAssertEqual(MenuPresence.ownIcon.legacyPlacement, .ownIcon)
        XCTAssertEqual(MenuPresence.ownIconWhenActive.legacyPlacement, .ownIcon)
        XCTAssertEqual(MenuPresence.inSnapticMenu.legacyPlacement, .shared)
        XCTAssertEqual(MenuPresence.hidden.legacyPlacement, .hidden)
        XCTAssertEqual(MenuPresence(legacy: .ownIcon, hideWithoutExternalDisplay: true), .ownIconWhenActive)
        XCTAssertEqual(MenuPresence(legacy: .ownIcon, hideWithoutExternalDisplay: false), .ownIcon)
        XCTAssertEqual(MenuPresence(legacy: .shared, hideWithoutExternalDisplay: true), .inSnapticMenu)
        XCTAssertEqual(MenuPresence(legacy: .hidden, hideWithoutExternalDisplay: true), .hidden)
        // Round trip through the 0.2 view for every presence a 0.2 build can express.
        for presence in MenuPresence.allCases {
            let hide = presence == .ownIconWhenActive
            XCTAssertEqual(MenuPresence(legacy: presence.legacyPlacement, hideWithoutExternalDisplay: hide), presence)
        }
    }

    // MARK: Invariants (seeded fuzz)

    func testFuzzedPlansKeepTheInvariants() {
        var rng = SeededGenerator(seed: 0x5EC7_10)
        let presences = MenuPresence.allCases
        for _ in 0..<5_000 {
            var c = ModulesConfig()
            for id in ModuleID.allCases where rng.next() % 6 != 0 {
                c.modules[id] = ModulePreferences(enabled: rng.next() % 4 != 0,
                                                  presence: presences[Int(rng.next() % UInt64(presences.count))])
            }
            let running = Set(ModuleID.allCases.filter { _ in rng.next() % 5 != 0 })
            let active = rng.next() % 2 == 0
            let displaysActive = rng.next() % 2 == 0
            let bound = rng.next() % 2 == 0
            let atRest = rng.next() % 2 == 0
            let p = c.statusItemPlan(running: running, awakeActive: active, displaysActive: displaysActive,
                                     awakeShortcutBound: bound, sharedShownAtRest: atRest)
            let again = c.statusItemPlan(running: running, awakeActive: active, displaysActive: displaysActive,
                                         awakeShortcutBound: bound, sharedShownAtRest: atRest)
            XCTAssertEqual(p, again)
            XCTAssertEqual(p.ownIcon, c.ownIconIDs(running: running, displaysActive: displaysActive))

            let live = Set(c.enabledModules).intersection(running)
            let governing = active && live.contains(.awake)
            let order = ModuleID.allCases
            XCTAssertEqual(p.shared, order.filter { p.shared.contains($0) }, "start order, no duplicates")
            XCTAssertEqual(p.ownIcon, order.filter { p.ownIcon.contains($0) })
            XCTAssertTrue(Set(p.shared).isSubset(of: live))
            XCTAssertTrue(Set(p.ownIcon).isSubset(of: live))
            XCTAssertTrue(Set(p.shared).isDisjoint(with: p.ownIcon))
            XCTAssertFalse(p.ownIcon.contains(.awake))
            XCTAssertTrue(p.custom.allSatisfy { $0 == .awake } && Set(p.custom).isSubset(of: live))
            XCTAssertEqual(p.awakeCompactInShared, p.shared.contains(.awake))
            XCTAssertEqual(p.noModulesEnabled, c.enabledModules.isEmpty)
            XCTAssertEqual(p.showShared, !p.shared.isEmpty || p.noModulesEnabled)
            XCTAssertEqual(p.sharedActiveGlyph, governing && p.showShared)
            XCTAssertEqual(p.sharedFooterInOwnMenus, !p.showShared && !(p.ownIcon.isEmpty && p.custom.isEmpty))
            if p.everythingHidden {
                XCTAssertFalse(p.showShared)
                XCTAssertTrue(p.ownIcon.isEmpty && p.custom.isEmpty)
            }
            // N11: a session is never invisible.
            if governing { XCTAssertTrue(p.custom.contains(.awake) || p.sharedActiveGlyph) }
            // Idle Awake never has an item unless it is always shown.
            if !governing && live.contains(.awake) && c.presence(.awake) != .ownIcon { XCTAssertEqual(p.custom, []) }

            // A session never removes an item that was shown at rest, and never moves the other modules.
            let rest = c.statusItemPlan(running: running, awakeActive: false, displaysActive: displaysActive,
                                        awakeShortcutBound: bound, sharedShownAtRest: true)
            let session = c.statusItemPlan(running: running, awakeActive: active, displaysActive: displaysActive,
                                           awakeShortcutBound: bound, sharedExistsNow: rest.showShared)
            if rest.showShared { XCTAssertTrue(session.showShared) }
            XCTAssertEqual(session.ownIcon, rest.ownIcon)
            XCTAssertEqual(session.shared.filter { $0 != .awake }, rest.shared.filter { $0 != .awake })
            if rest.awakeCompactInShared { XCTAssertTrue(session.awakeCompactInShared) }
        }
    }
}
