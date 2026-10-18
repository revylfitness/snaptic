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

    func testPerDisplaySubmenuItemsAreThreeWayAndOnlyTwoOfferADistinctPlace() {
        for info in DisplaysMenuPlan.items {
            if case .submenu = info.location {
                XCTAssertEqual(info.customize, .threeWay, info.id.rawValue)
            } else if info.location != .removed {
                XCTAssertEqual(info.customize, .checkbox, info.id.rawValue)
            }
        }
        let distinct = DisplaysMenuPlan.items.filter(\.offersSubmenuChoice).map(\.id.rawValue)
        XCTAssertEqual(Set(distinct), ["c.ddc.power", "d.disconnectItem"])
    }

    /// Other teams' tables that also name a 0.2 menu id must agree with M's place for it (one home, no
    /// contradiction): the same customize kind (their location wording may be more detailed).
    func testOtherTablesAgreeWithMsPlacement() {
        let mine = menuSpecs
        let others = ControlRegistry.tables.filter {
            ![String(describing: DisplayMenuBlockControls.self), String(describing: DisplaysMenuBuilderControls.self),
              String(describing: CustomizeMenuSheetControls.self)].contains(String(describing: $0))
        }.flatMap { $0.controls }
        for spec in others {
            // Rows inside a section (customize .none: a layout, Save Current Layout…) aren't the item's home.
            guard let placement = spec.menu, placement.customize != .none, let legacy = placement.legacyMenuID
            else { continue }
            guard let home = mine.first(where: { $0.menu?.legacyMenuID == legacy })?.menu else { continue }
            XCTAssertEqual(placement.customize, home.customize, "\(spec.id.rawValue) vs M for \(legacy.rawValue)")
        }
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

    func testDefaults() {
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("c.brightness.slider"), declared: nil), .visible)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("c.ddc.contrast"), declared: nil), .hidden)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("c.ddc.contrast"), declared: .inSubmenu), .hidden)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("c.ddc.contrast"), declared: .visible), .visible)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("d.resolutionSlider"), declared: nil), .hidden)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("d.hdrToggle"), declared: nil), .hidden)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("d.setMain"), declared: nil), .inSubmenu)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("c.ddc.custom"), declared: nil), .visible)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("c.ddc.power"), declared: nil), .inSubmenu)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("d.disconnectItem"), declared: nil), .inSubmenu)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("d.disconnectAllButMain"), declared: nil), .visible)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("f.tools.panel"), declared: nil), .visible)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("z.unknown"), declared: nil), .visible)
        XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(id("z.unknown"), declared: .hidden), .hidden)
        // The §5.2 row budget's defaults: brightness and volume sliders show, contrast and resolution don't.
        var c = MenuConfig()
        for raw in ["c.ddc.contrast", "d.resolutionSlider", "c.ddc.custom"] {
            let fallback = DisplaysMenuPlan.defaultVisibility(id(raw), declared: .inSubmenu)
            XCTAssertNil(DisplaysMenuPlan.place(id(raw), visibility: c.visibility(of: id(raw), default: fallback),
                                                perDisplay: true, isCustomRow: true))
            c.setShown(true, for: id(raw), default: fallback)
            XCTAssertEqual(DisplaysMenuPlan.place(id(raw), visibility: c.visibility(of: id(raw), default: fallback),
                                                  perDisplay: true, isCustomRow: true), .slider)
        }
    }

    // MARK: Defaults equal the contributors' descriptors

    /// The repository root (this file is Tests/SnapticKitTests/…), when the app sources are next to the tests.
    private static var repositoryRoot: URL? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = root.appendingPathComponent("Sources/Snaptic")
        return FileManager.default.fileExists(atPath: app.path) ? root : nil
    }

    private static func swiftSources(under dir: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var texts: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) { texts.append(text) }
        }
        return texts
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    /// Every `DisplayMenuItemDescriptor(id: …, defaultVisibility: …)` in the app sources, with its id resolved
    /// through the `DisplayMenuItemID` constants it names (the app's and Kit's). A custom action (`menuID($0)`) is
    /// the family.
    private static func declaredDefaults(_ texts: [String]) -> (resolved: [(String, MenuItemVisibility)], unresolved: [String]) {
        var constants: [String: Set<String>] = ["menuID": [DisplaysMenuPlan.customActionPrefix]]
        var aliases: [String: String] = [:]
        for text in texts {
            for m in matches(#"static let (\w+)\s*=\s*(?:DisplayMenuItemID|Self)\(rawValue:\s*"([^"]*)"\)"#, in: text) {
                constants[m[0], default: []].insert(m[1])
            }
            for m in matches(#"static let (\w+)\s*=\s*DisplayMenuItemID\.(\w+)\b"#, in: text) { aliases[m[0]] = m[1] }
        }
        for (name, target) in aliases { if let raw = constants[target] { constants[name, default: []].formUnion(raw) } }
        var resolved: [(String, MenuItemVisibility)] = []
        var unresolved: [String] = []
        for text in texts {
            let pattern = #"DisplayMenuItemDescriptor\(\s*id:\s*([\w.]+)(?:\([^)]*\))?\s*,[\s\S]*?defaultVisibility:\s*\.(\w+)"#
            for m in matches(pattern, in: text) {
                let name = String(m[0].split(separator: ".").last ?? "")
                guard let raws = constants[name], raws.count == 1, let raw = raws.first,
                      let visibility = MenuItemVisibility(rawValue: m[1]) else {
                    unresolved.append("\(m[0]) \(m[1])")
                    continue
                }
                resolved.append((raw, visibility))
            }
        }
        return (resolved, unresolved)
    }

    /// The plan's default for each item equals its contributor's descriptor default (the descriptor wins at run
    /// time; the plan's is used when no contributor runs, so the two must not disagree), and every item the plan
    /// keeps has a contributor that declares it.
    func testPlanDefaultsEqualTheContributorsDescriptors() throws {
        guard let root = Self.repositoryRoot else { throw XCTSkip("App sources aren't next to the tests.") }
        let texts = Self.swiftSources(under: root.appendingPathComponent("Sources"))
        let (declared, unresolved) = Self.declaredDefaults(texts)
        XCTAssertEqual(unresolved, [], "descriptors whose id the test can't resolve")
        XCTAssertGreaterThanOrEqual(declared.count, 40)
        var seen: Set<String> = []
        for (raw, visibility) in declared {
            guard let info = DisplaysMenuPlan.info(for: id(raw)) else {
                XCTFail("\(raw) is declared by a contributor but not in the plan")
                continue
            }
            seen.insert(info.id.rawValue)
            guard info.location != .removed else { continue }
            XCTAssertEqual(info.menuDefault, visibility, "\(raw): plan vs descriptor")
            XCTAssertEqual(DisplaysMenuPlan.defaultVisibility(info.id, declared: nil),
                           DisplaysMenuPlan.defaultVisibility(info.id, declared: visibility), raw)
        }
        for info in DisplaysMenuPlan.items where info.location != .removed {
            XCTAssertTrue(seen.contains(info.id.rawValue), "\(info.id.rawValue) has no contributor descriptor")
        }
    }

    /// §4.8: Contrast and Resolution sliders are hidden by default; Brightness and Volume show (§5.2's row budget).
    func testSliderDefaultsFollowTheMenuTable() {
        XCTAssertEqual(DisplaysMenuPlan.info(for: id("c.ddc.contrast"))?.menuDefault, .hidden)
        XCTAssertEqual(DisplaysMenuPlan.info(for: id("d.resolutionSlider"))?.menuDefault, .hidden)
        XCTAssertEqual(DisplaysMenuPlan.info(for: id("c.brightness.slider"))?.menuDefault, .visible)
        XCTAssertEqual(DisplaysMenuPlan.info(for: id("c.ddc.volume"))?.menuDefault, .visible)
        for info in DisplaysMenuPlan.items where info.location == .slider {
            XCTAssertNotEqual(info.menuDefault, .inSubmenu, "\(info.id.rawValue): a slider is never in a submenu")
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

    /// M places every kept 0.2 menu id exactly once (DisplayMenuBlock or DisplaysMenuBuilder) and the Customize
    /// sheet has exactly one row for it, with the same kind and location.
    func testEveryKeptMenuIDHasExactlyOnePlacementAndOneSheetRow() {
        let removed = Set(ControlRemovals.removed.keys)
        let sheet = CustomizeMenuSheetControls.controls
        for legacy in legacyMenuIDs where !removed.contains(legacy) && menuID(legacy) != awakeHome {
            let placements = menuSpecs.compactMap(\.menu).filter { $0.legacyMenuID?.rawValue == menuID(legacy) }
            XCTAssertEqual(placements.count, 1, legacy.rawValue)
            guard let placement = placements.first else { continue }
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

    /// One home each (step 3, R5-13 totality for M's prefixes): every frozen `l.menu.*`, `l.menu.fixed.*` and
    /// `l.gen.menu.*` id is replaced by exactly one spec across all tables, or has a removal reason and no home.
    /// A 0.2 menu item's home is the spec of the item its builder makes; that spec names the item's 0.2 id (A's
    /// custom actions are a family, and Prevent Display Sleep moved to Awake's menu).
    func testEveryMenuLegacyIDHasExactlyOneHome() {
        var homes: [LegacyControlID: [ControlSpec]] = [:]
        for table in ControlRegistry.tables {
            for spec in table.controls {
                for legacy in spec.replaces { homes[legacy, default: []].append(spec) }
            }
        }
        let removed = Set(ControlRemovals.removed.keys)
        let prefixes = ["l.menu.", "l.gen.menu."]
        let ids = ControlLegacy.ids.filter { id in prefixes.contains { id.rawValue.hasPrefix($0) } }
        XCTAssertEqual(ids.count, 46 + 15 + 16)
        for legacy in ids {
            let found = homes[legacy] ?? []
            if removed.contains(legacy) {
                XCTAssertTrue(found.isEmpty, "\(legacy.rawValue) is removed but has \(found.map(\.id.rawValue))")
                continue
            }
            XCTAssertEqual(found.count, 1, "\(legacy.rawValue): \(found.map(\.id.rawValue))")
            guard let home = found.first, legacyMenuIDs.contains(legacy),
                  ![awakeHome, DisplaysMenuPlan.customActionPrefix].contains(menuID(legacy)) else { continue }
            XCTAssertEqual(home.menu?.legacyMenuID?.rawValue, menuID(legacy), legacy.rawValue)
            XCTAssertNotEqual(home.menu?.customize ?? MenuCustomize.none, MenuCustomize.none, legacy.rawValue)
        }
    }

    /// The Menu Bar page and the Customize sheet are found by search under the Menu Bar root.
    func testMenuBarSearchEntries() {
        let entries = SettingsIndex.entries(ControlRegistry.tables, root: "menuBar")
        let ids = Set(entries.map(\.id))
        for spec in MenuBarPageControls.controls + CustomizeMenuSheetControls.controls where spec.kind == .setting {
            XCTAssertTrue(ids.contains(spec.id.rawValue), spec.id.rawValue)
        }
        for raw in ["menubar.page.customize", "menubar.page.restoreDefaults", "menubar.customize.displays",
                    "menubar.customize.useDefaultOrder"] {
            XCTAssertTrue(ids.contains(raw), raw)
        }
        XCTAssertEqual(entries.first { $0.id == "menubar.page.customize" }?.sheet, nil)
        XCTAssertEqual(entries.first { $0.id == "menubar.customize.displays" }?.sheet, CustomizeMenuSheetControls.sheetID)
        XCTAssertTrue(entries.allSatisfy { $0.id.hasPrefix("menubar.") })
    }

    func testMenuGeneralSettingsHaveHomesOnTheMenuBarPageOrSheet() {
        let general = ControlLegacy.ids.filter { $0.rawValue.hasPrefix("l.gen.menu.") }
        let specs = MenuBarPageControls.controls + CustomizeMenuSheetControls.controls
        for legacy in general {
            XCTAssertTrue(specs.contains { $0.replaces.contains(legacy) }, legacy.rawValue)
        }
    }
}
