import XCTest
@testable import SnapticKit

/// PLAN 0.3 §4.8 "0.2 menu", §5.2, N16: every frozen 0.2 menu id has a 0.3 place (or a removal reason), the
/// placement rules, and the pairing between M's menu specs and the Customize Displays Menu rows.
final class DisplaysMenuPlanTests: XCTestCase {
    private func id(_ raw: String) -> DisplayMenuItemID { DisplayMenuItemID(rawValue: raw) }

    /// "l.menu.c.ddc.volume" → "c.ddc.volume"; "l.menu.a.custom.*" → "a.custom.".
    private func menuID(_ legacy: LegacyControlID) -> String {
        let raw = String(legacy.rawValue.dropFirst("l.menu.".count))
        return raw.hasSuffix("*") ? String(raw.dropLast()) : raw
    }

    private var legacyMenuIDs: [LegacyControlID] {
        ControlLegacy.ids.filter { $0.rawValue.hasPrefix("l.menu.") && !$0.rawValue.hasPrefix("l.menu.fixed.") }
    }

    /// The 0.2 "Prevent Display Sleep" item moved to Awake (migration M1); its home is Awake's menu table.
    private let awakeHome = "d.sleepPrevention"

    private var menuSpecs: [ControlSpec] { DisplayMenuBlockControls.controls + DisplaysMenuBuilderControls.controls }

    // MARK: The table

    func testTheTableIsExactlyTheFrozen46() {
        XCTAssertEqual(DisplaysMenuPlan.items.count, 46)
        XCTAssertEqual(Set(DisplaysMenuPlan.items.map(\.id.rawValue)), Set(legacyMenuIDs.map(menuID)))
        XCTAssertEqual(Set(DisplaysMenuPlan.items.map(\.id)).count, 46, "duplicate ids")
    }

    /// Not in the Displays menu: the removal table plus d.sleepPrevention, whose home is Awake (migration M1).
    func testRemovedItemsAreTheRemovalTablePlusSleepPrevention() {
        var removed = Set(ControlRemovals.removed.keys.filter { $0.rawValue.hasPrefix("l.menu.") && !$0.rawValue.hasPrefix("l.menu.fixed.") }
            .map(menuID))
        removed.insert(awakeHome)
        let table = Set(DisplaysMenuPlan.items.filter { $0.location == .removed }.map(\.id.rawValue))
        XCTAssertEqual(table, removed)
    }

    func testEveryKeptItemIsCustomizableInAGroupWithATitle() {
        for info in DisplaysMenuPlan.items where info.location != .removed {
            XCTAssertNotEqual(info.customize, .none, info.id.rawValue)
            XCTAssertNotNil(info.customizeGroup, info.id.rawValue)
            XCTAssertFalse(info.title.isEmpty)
        }
        let rows = DisplayMenuCustomizeGroup.allCases.flatMap { DisplaysMenuPlan.customizeRows($0) }
        XCTAssertEqual(rows.count, 46 - 6 - 1, "every kept item except the custom-action family has a fixed row")
    }

    func testOnlyDisconnectAndTurnOffAreThreeWay() {
        let threeWay = DisplaysMenuPlan.items.filter { $0.customize == .threeWay }.map(\.id.rawValue)
        XCTAssertEqual(Set(threeWay), ["c.ddc.power", "d.disconnectItem"])
    }

    func testTopLevelItemsHaveSymbols() {
        for info in DisplaysMenuPlan.items {
            switch info.location {
            case .sectionItem, .pausedStatus: XCTAssertNotNil(info.symbol, info.id.rawValue)
            case .submenu(_, let promotable) where promotable: XCTAssertNotNil(info.symbol, info.id.rawValue)
            default: break
            }
        }
        for menu in DisplaysSectionMenu.allCases {
            XCTAssertFalse(menu.symbol.isEmpty)
            XCTAssertFalse(menu.title.isEmpty)
        }
    }

    func testCustomActionsMapToTheFamily() {
        XCTAssertTrue(DisplaysMenuPlan.isCustomAction(id("a.custom.ABC")))
        XCTAssertFalse(DisplaysMenuPlan.isCustomAction(id("a.custom.")))
        XCTAssertFalse(DisplaysMenuPlan.isCustomAction(id("c.brightness.slider")))
        XCTAssertEqual(DisplaysMenuPlan.info(for: id("a.custom.ABC"))?.location, .sectionMenu(.actions))
        XCTAssertNil(DisplaysMenuPlan.info(for: id("x.unknown")))
        XCTAssertEqual(DisplaysMenuPlan.rank(id("a.custom.1")), DisplaysMenuPlan.rank(id("a.custom.2")))
        XCTAssertEqual(DisplaysMenuPlan.rank(id("x.unknown")), Int.max)
    }

    // MARK: Placement

    func testSlidersAreShowOrHideAndNeverInASubmenu() {
        for raw in ["c.brightness.slider", "c.ddc.volume", "c.ddc.contrast", "c.ddc.custom", "d.resolutionSlider"] {
            XCTAssertEqual(DisplaysMenuPlan.place(id(raw), visibility: .visible, perDisplay: true, isCustomRow: true), .slider)
            XCTAssertEqual(DisplaysMenuPlan.place(id(raw), visibility: .inSubmenu, perDisplay: true, isCustomRow: true), .slider)
            XCTAssertNil(DisplaysMenuPlan.place(id(raw), visibility: .hidden, perDisplay: true, isCustomRow: true))
            XCTAssertTrue(MenuConfig.isSlider(id(raw)))
        }
    }

    func testPromotableItemsGoUnderTheDeviceRowOnlyWhenShown() {
        for raw in ["c.ddc.power", "d.disconnectItem"] {
            XCTAssertEqual(DisplaysMenuPlan.place(id(raw), visibility: .visible, perDisplay: true, isCustomRow: false),
                           .underDevice)
            XCTAssertEqual(DisplaysMenuPlan.place(id(raw), visibility: .inSubmenu, perDisplay: true, isCustomRow: false),
                           .submenu(.power))
            XCTAssertNil(DisplaysMenuPlan.place(id(raw), visibility: .hidden, perDisplay: true, isCustomRow: false))
        }
        XCTAssertEqual(DisplaysMenuPlan.place(id("d.hdrToggle"), visibility: .visible, perDisplay: true, isCustomRow: false),
                       .submenu(.options))
        XCTAssertEqual(DisplaysMenuPlan.place(id("d.rotationMenu"), visibility: .inSubmenu, perDisplay: true,
                                              isCustomRow: false), .submenu(.rotation))
    }

    func testGlobalItems() {
        XCTAssertEqual(DisplaysMenuPlan.place(id("d.arrange"), visibility: .inSubmenu, perDisplay: false, isCustomRow: false),
                       .sectionItem)
        XCTAssertEqual(DisplaysMenuPlan.place(id("d.protection"), visibility: .visible, perDisplay: false, isCustomRow: false),
                       .sectionMenu(.layouts))
        XCTAssertEqual(DisplaysMenuPlan.place(id("a.custom.X"), visibility: .visible, perDisplay: false, isCustomRow: false),
                       .sectionMenu(.actions))
        XCTAssertEqual(DisplaysMenuPlan.place(id("c.sync.toggle"), visibility: .visible, perDisplay: false, isCustomRow: false),
                       .tools(toggle: true))
        XCTAssertEqual(DisplaysMenuPlan.place(id("f.tools.panel"), visibility: .inSubmenu, perDisplay: false,
                                              isCustomRow: false), .tools(toggle: false))
        XCTAssertNil(DisplaysMenuPlan.place(id("f.tools.panel"), visibility: .hidden, perDisplay: false, isCustomRow: false))
    }

    func testRestoreAllIsTopLevelWhilePendingWhateverTheChoice() {
        for v in MenuItemVisibility.allCases {
            XCTAssertEqual(DisplaysMenuPlan.place(id("b.restoreAll"), visibility: v, perDisplay: false, isCustomRow: false,
                                                  pendingConfirmation: true), .sectionItem)
        }
        XCTAssertEqual(DisplaysMenuPlan.place(id("b.restoreAll"), visibility: .visible, perDisplay: false,
                                              isCustomRow: false), .tools(toggle: false))
    }

    func testResumeShowsWhilePausedWhateverTheChoice() {
        for v in MenuItemVisibility.allCases {
            XCTAssertEqual(DisplaysMenuPlan.place(id("b.resumeAutomation"), visibility: v, perDisplay: false,
                                                  isCustomRow: false, automationPaused: true), .pausedStatus)
            XCTAssertNil(DisplaysMenuPlan.place(id("b.resumeAutomation"), visibility: v, perDisplay: false,
                                                isCustomRow: false, automationPaused: false))
        }
    }

    func testRemovedItemsNeverShow() {
        for info in DisplaysMenuPlan.items where info.location == .removed {
            for v in MenuItemVisibility.allCases {
                XCTAssertNil(DisplaysMenuPlan.place(info.id, visibility: v, perDisplay: info.isPerDisplay,
                                                    isCustomRow: false))
            }
        }
    }

    func testUnknownIDsFollowTheirSlot() {
        XCTAssertEqual(DisplaysMenuPlan.place(id("z.new"), visibility: .visible, perDisplay: true, isCustomRow: false),
                       .submenu(.options))
        XCTAssertEqual(DisplaysMenuPlan.place(id("z.new"), visibility: .visible, perDisplay: true, isCustomRow: true), .slider)
        XCTAssertEqual(DisplaysMenuPlan.place(id("z.new"), visibility: .visible, perDisplay: false, isCustomRow: false),
                       .tools(toggle: false))
        XCTAssertNil(DisplaysMenuPlan.place(id("z.new"), visibility: .visible, perDisplay: false, isCustomRow: true))
        XCTAssertNil(DisplaysMenuPlan.place(id("z.new"), visibility: .hidden, perDisplay: true, isCustomRow: false))
    }

    /// Seeded fuzz over every id × choice × flag: a custom row (slider) never lands in a submenu, hidden items never
    /// show (except the two always-shown safety items), and a per-display item never leaves the display's places.
    func testFuzzInvariants() {
        var rng = SeededGenerator(seed: 0x5EED_03_02)
        let ids = DisplaysMenuPlan.items.map(\.id) + [id("a.custom.Q"), id("z.unknown"), id("")]
        for _ in 0..<5_000 {
            let i = ids[Int(rng.next() % UInt64(ids.count))]
            let v = MenuItemVisibility.allCases[Int(rng.next() % 3)]
            let perDisplay = rng.next() % 2 == 0
            let custom = rng.next() % 2 == 0
            let pending = rng.next() % 2 == 0
            let paused = rng.next() % 2 == 0
            let place = DisplaysMenuPlan.place(i, visibility: v, perDisplay: perDisplay, isCustomRow: custom,
                                               pendingConfirmation: pending, automationPaused: paused)
            if custom, let place {
                switch place {
                case .submenu, .sectionMenu, .tools: XCTFail("custom row \(i.rawValue) in a submenu")
                default: break
                }
            }
            let alwaysShown = (i.rawValue == "b.restoreAll" && pending) || (i.rawValue == "b.resumeAutomation" && paused)
            if v == .hidden && !alwaysShown { XCTAssertNil(place, i.rawValue) }
            if let info = DisplaysMenuPlan.info(for: i), info.isPerDisplay, let place {
                switch place {
                case .slider, .underDevice, .submenu: break
                default: XCTFail("per-display \(i.rawValue) placed at \(place)")
                }
            }
        }
    }

    func testCompactKeepsOneSliderByPriority() {
        XCTAssertNil(DisplaysMenuPlan.compactSlider([]))
        XCTAssertEqual(DisplaysMenuPlan.compactSlider([id("c.ddc.volume"), id("c.brightness.slider")]), 1)
        XCTAssertEqual(DisplaysMenuPlan.compactSlider([id("d.resolutionSlider"), id("c.ddc.contrast")]), 1)
        XCTAssertEqual(DisplaysMenuPlan.compactSlider([id("z.new"), id("z.other")]), 0)
    }

    func testDeviceSubtitleAndSingleDisplayOrder() {
        XCTAssertEqual(DisplaysMenuPlan.deviceSubtitle(badges: ["Main", "Mirroring"], style: .standard, showBadges: true),
                       "Main · Mirroring")
        XCTAssertNil(DisplaysMenuPlan.deviceSubtitle(badges: ["Main"], style: .compact, showBadges: true))
        XCTAssertNil(DisplaysMenuPlan.deviceSubtitle(badges: ["Main"], style: .standard, showBadges: false))
        XCTAssertNil(DisplaysMenuPlan.deviceSubtitle(badges: [], style: .standard, showBadges: true))
        XCTAssertTrue(DisplaysMenuPlan.slidersBeforeDevice(displayCount: 1, headerForSingleDisplay: false))
        XCTAssertFalse(DisplaysMenuPlan.slidersBeforeDevice(displayCount: 1, headerForSingleDisplay: true))
        XCTAssertFalse(DisplaysMenuPlan.slidersBeforeDevice(displayCount: 2, headerForSingleDisplay: false))
    }

    // MARK: Customize sheet

    func testFilterMatchesWordPrefixesIgnoringCaseAndDiacritics() {
        XCTAssertTrue(DisplaysMenuPlan.matches("Night Shift", query: ""))
        XCTAssertTrue(DisplaysMenuPlan.matches("Night Shift", query: "nig"))
        XCTAssertTrue(DisplaysMenuPlan.matches("Night Shift", query: "shift NI"))
        XCTAssertTrue(DisplaysMenuPlan.matches("Résolution", query: "reso"))
        XCTAssertFalse(DisplaysMenuPlan.matches("Night Shift", query: "ight"))
        XCTAssertFalse(DisplaysMenuPlan.matches("Night Shift", query: "night x"))
        XCTAssertTrue(DisplaysMenuPlan.matches("Match Text Size…", query: "  size  "))
    }

    func testPartitionByFeature() {
        let rows = DisplaysMenuPlan.customizeRows(.tools)
        let split = DisplaysMenuPlan.partition(rows) { $0 != .disconnect }
        XCTAssertEqual(split.needFeatures.map(\.id.rawValue), ["d.connectAll", "d.disconnectAllButMain"])
        XCTAssertEqual(split.available.count + split.needFeatures.count, rows.count)
        XCTAssertTrue(split.available.contains { $0.id.rawValue == "f.tools.identify" }, "no feature = always available")
        XCTAssertEqual(DisplaysMenuPlan.needFeaturesTitle(1), "1 item needs a feature that is off")
        XCTAssertEqual(DisplaysMenuPlan.needFeaturesTitle(6), "6 items need features that are off")
    }

    func testCheckboxRoundTripsForEveryDefault() {
        let i = id("f.tools.panel")
        for fallback in MenuItemVisibility.allCases {
            var c = MenuConfig()
            XCTAssertEqual(c.isShown(i, default: fallback), fallback != .hidden)
            c.setShown(false, for: i, default: fallback)
            XCTAssertFalse(c.isShown(i, default: fallback))
            c.setShown(true, for: i, default: fallback)
            XCTAssertTrue(c.isShown(i, default: fallback))
            if fallback != .hidden { XCTAssertFalse(c.hasOverride(i), "showing a shown default stores nothing") }
        }
    }

    // MARK: Control tables (N16 pairing)

    func testEveryKeptMenuIDHasExactlyOneMenuSpecAndOneSheetRow() {
        let removed = Set(ControlRemovals.removed.keys)
        let sheet = CustomizeMenuSheetControls.controls
        for legacy in legacyMenuIDs where !removed.contains(legacy) && menuID(legacy) != awakeHome {
            let homes = menuSpecs.filter { $0.replaces.contains(legacy) }
            XCTAssertEqual(homes.count, 1, legacy.rawValue)
            guard let home = homes.first, let placement = home.menu else { XCTFail(legacy.rawValue); continue }
            XCTAssertEqual(placement.legacyMenuID?.rawValue, menuID(legacy), legacy.rawValue)
            let info = DisplaysMenuPlan.info(for: DisplayMenuItemID(rawValue: menuID(legacy)))
            XCTAssertEqual(placement.customize, info?.customize, legacy.rawValue)
            let rows = sheet.filter { $0.menu?.legacyMenuID == placement.legacyMenuID }
            XCTAssertEqual(rows.count, 1, "Customize row for \(legacy.rawValue)")
            XCTAssertEqual(rows.first?.menu?.customize, placement.customize, legacy.rawValue)
            XCTAssertEqual(rows.first?.menu?.location, placement.location, legacy.rawValue)
        }
    }

    func testRemovedMenuIDsHaveNoHome() {
        let removed = Set(ControlRemovals.removed.keys)
        for spec in menuSpecs + CustomizeMenuSheetControls.controls {
            XCTAssertTrue(spec.replaces.allSatisfy { !removed.contains($0) }, spec.id.rawValue)
        }
    }

    func testEverySheetItemRowIsASearchableSettingInTheSheet() {
        for spec in CustomizeMenuSheetControls.controls where spec.menu != nil {
            XCTAssertEqual(spec.kind, .setting, spec.id.rawValue)
            XCTAssertEqual(spec.search?.sheet, CustomizeMenuSheetControls.sheetID, spec.id.rawValue)
            XCTAssertEqual(spec.search?.root, "menuBar", spec.id.rawValue)
        }
        for spec in MenuBarPageControls.controls where spec.kind == .setting {
            XCTAssertEqual(spec.search?.root, "menuBar", spec.id.rawValue)
            XCTAssertNil(spec.search?.sheet, spec.id.rawValue)
        }
    }

    func testFixedMenuRowsHaveHomes() {
        let fixed = ControlLegacy.ids.filter { $0.rawValue.hasPrefix("l.menu.fixed.") }
        let removed = Set(ControlRemovals.removed.keys)
        let mine = menuSpecs + StatusMenuControls.controls
        let switcher: Set<String> = ["l.menu.fixed.switcher.enableThumbnails", "l.menu.fixed.switcher.pressHint",
                                     "l.menu.fixed.switcher.gather"]   // team A's Switcher section
        for legacy in fixed where !removed.contains(legacy) && !switcher.contains(legacy.rawValue) {
            XCTAssertTrue(mine.contains { $0.replaces.contains(legacy) }, legacy.rawValue)
        }
    }

    func testMenuGeneralSettingsHaveHomesOnTheMenuBarPageOrSheet() {
        let general = ControlLegacy.ids.filter { $0.rawValue.hasPrefix("l.gen.menu.") }
        let specs = MenuBarPageControls.controls + CustomizeMenuSheetControls.controls
        for legacy in general {
            XCTAssertTrue(specs.contains { $0.replaces.contains(legacy) }, legacy.rawValue)
        }
    }
}
