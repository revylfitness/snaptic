import XCTest
@testable import SnapticKit

final class ConfigMenuTests: XCTestCase {
    private func key(_ i: Int) -> DisplayKey { DisplayKey(rawValue: String(format: "%032x", i))! }
    private let brightness = DisplayMenuItemID(rawValue: "c.brightness")
    private let volume = DisplayMenuItemID(rawValue: "c.volume")
    private let input = DisplayMenuItemID(rawValue: "c.input")

    func testDefaults() {
        let c = MenuConfig()
        XCTAssertEqual(c.orderedSections, [.displays, .tools])
        XCTAssertTrue(c.mainFirst)
        XCTAssertFalse(c.compact)
        XCTAssertTrue(c.showBadges)
        XCTAssertNil(c.showPanelShortcut)
        XCTAssertEqual(c.sanitized(), c)
    }

    func testRoundTrip() throws {
        var c = MenuConfig()
        c.setVisibility(.hidden, for: brightness, default: .visible)
        c.setHidden(true, for: key(1))
        c.setCollapsed(true, for: key(2))
        c.move(key(3), by: -1, in: [key(1), key(3)])
        c.compact = true
        c.showPanelShortcut = HotkeyCombo(keyCode: 2, carbonModifiers: 0x0100 | 0x0800)
        c.sectionOrder = [.tools, .displays]
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(MenuConfig.self, from: data), c)
    }

    func testLossyDecodeKeepsGoodFields() throws {
        let good = key(7).rawValue
        let json = #"""
        {"items":{"c.brightness":"hidden","c.volume":"sideways"},
         "sectionOrder":["tools","future","tools"],
         "hiddenDisplays":["nothex","\#(good)"],
         "compact":"yes","mainFirst":false,
         "showPanelShortcut":{"keyCode":"x"}}
        """#
        let c = try JSONDecoder().decode(MenuConfig.self, from: Data(json.utf8))
        XCTAssertEqual(c.items[brightness], .hidden)
        XCTAssertNil(c.items[volume])
        XCTAssertEqual(c.hiddenDisplays, [key(7)])
        XCTAssertFalse(c.compact)
        XCTAssertFalse(c.mainFirst)
        XCTAssertNil(c.showPanelShortcut)
        XCTAssertEqual(c.orderedSections, [.tools, .displays])
        XCTAssertEqual(c.sanitized().sectionOrder, [.tools, .displays])
    }

    func testGarbageDecodesToDefaults() throws {
        for json in ["{}", #"{"items":5,"sectionOrder":"x","displayOrder":{}}"#] {
            let c = try JSONDecoder().decode(MenuConfig.self, from: Data(json.utf8))
            XCTAssertEqual(c.sanitized(), MenuConfig())
        }
    }

    func testVisibilityOverrideAndDefault() {
        var c = MenuConfig()
        XCTAssertEqual(c.visibility(of: brightness, default: .visible), .visible)
        c.setVisibility(.inSubmenu, for: brightness, default: .visible)
        XCTAssertEqual(c.visibility(of: brightness, default: .visible), .inSubmenu)
        XCTAssertTrue(c.hasOverride(brightness))
        // Choosing the default again removes the override.
        c.setVisibility(.visible, for: brightness, default: .visible)
        XCTAssertFalse(c.hasOverride(brightness))
        // Invalid ids are never stored.
        c.setVisibility(.hidden, for: DisplayMenuItemID(rawValue: "bad id!"), default: .visible)
        XCTAssertTrue(c.items.values.isEmpty)
    }

    func testPartitionKeepsOrderAndDropsHidden() {
        var c = MenuConfig()
        c.setVisibility(.hidden, for: volume, default: .visible)
        c.setVisibility(.visible, for: input, default: .inSubmenu)
        let entries: [(id: DisplayMenuItemID, item: String)] = [
            (brightness, "b"), (volume, "v"), (input, "i"), (DisplayMenuItemID(rawValue: "d.mode"), "m"),
        ]
        let defaults: [String: MenuItemVisibility] = ["c.brightness": .visible, "c.volume": .visible,
                                                       "c.input": .inSubmenu, "d.mode": .inSubmenu]
        let result = c.partition(entries) { defaults[$0.rawValue] ?? .visible }
        XCTAssertEqual(result.visible, ["b", "i"])
        XCTAssertEqual(result.more, ["m"])
    }

    func testResetLayout() {
        var c = MenuConfig()
        c.setVisibility(.hidden, for: brightness, default: .visible)
        c.setHidden(true, for: key(1))
        c.sectionOrder = [.tools, .displays]
        c.compact = true
        c.resetLayout()
        XCTAssertTrue(c.items.values.isEmpty)
        XCTAssertTrue(c.hiddenDisplays.isEmpty)
        XCTAssertEqual(c.orderedSections, [.displays, .tools])
        XCTAssertTrue(c.compact, "appearance options are not part of the layout")
    }

    func testOrderedDisplaysMainFirstThenUserOrder() {
        var c = MenuConfig()
        let registry = [key(1), key(2), key(3), key(4)]
        XCTAssertEqual(c.orderedDisplays(registry, main: key(3)), [key(3), key(1), key(2), key(4)])
        c.displayOrder = [key(4), key(2)]
        XCTAssertEqual(c.orderedDisplays(registry, main: key(3)), [key(3), key(4), key(2), key(1)])
        c.mainFirst = false
        XCTAssertEqual(c.orderedDisplays(registry, main: key(3)), [key(4), key(2), key(1), key(3)])
        c.setHidden(true, for: key(2))
        XCTAssertEqual(c.orderedDisplays(registry, main: nil), [key(4), key(1), key(3)])
        XCTAssertEqual(c.orderedDisplays(registry, main: nil, includeHidden: true), [key(4), key(2), key(1), key(3)])
        // Duplicates in the input are dropped.
        XCTAssertEqual(c.orderedDisplays([key(1), key(1)], main: nil), [key(1)])
    }

    func testMoveKeepsOfflineDisplaysAndClamps() {
        var c = MenuConfig()
        c.mainFirst = false
        c.displayOrder = [key(9), key(1)]
        let shown = [key(1), key(2), key(3)]
        c.move(key(3), by: -5, in: shown)
        XCTAssertEqual(c.displayOrder, [key(3), key(1), key(2), key(9)])
        XCTAssertEqual(c.orderedDisplays(shown, main: nil), [key(3), key(1), key(2)])
        c.move(key(3), by: 1, in: c.orderedDisplays(shown, main: nil))
        XCTAssertEqual(c.orderedDisplays(shown, main: nil), [key(1), key(3), key(2)])
        c.move(key(7), by: 1, in: shown) // not shown: no change
        XCTAssertEqual(c.orderedDisplays(shown, main: nil), [key(1), key(3), key(2)])
    }

    func testForgetRemovesEveryChoice() {
        var c = MenuConfig()
        c.setHidden(true, for: key(1))
        c.setCollapsed(true, for: key(1))
        c.displayOrder = [key(1), key(2)]
        c.forget(key(1))
        XCTAssertFalse(c.isHidden(key(1)))
        XCTAssertFalse(c.isCollapsed(key(1)))
        XCTAssertEqual(c.displayOrder, [key(2)])
    }

    func testMoveSection() {
        var c = MenuConfig()
        c.moveSection(.tools, by: -1)
        XCTAssertEqual(c.orderedSections, [.tools, .displays])
        c.moveSection(.tools, by: 10)
        XCTAssertEqual(c.orderedSections, [.displays, .tools])
    }

    func testSanitizedBoundsListsAndIDs() {
        var c = MenuConfig()
        c.hiddenDisplays = (0..<100).map(key) + [key(0)]
        c.displayOrder = [key(1), key(1), key(2)]
        c.items[DisplayMenuItemID(rawValue: "")] = .hidden
        c.items[DisplayMenuItemID(rawValue: String(repeating: "x", count: 65))] = .hidden
        c.items[DisplayMenuItemID(rawValue: "ok.id-1_2")] = .hidden
        let s = c.sanitized()
        XCTAssertEqual(s.hiddenDisplays.count, MenuConfig.maxDisplays)
        XCTAssertEqual(s.displayOrder, [key(1), key(2)])
        XCTAssertEqual(Array(s.items.values.keys), [DisplayMenuItemID(rawValue: "ok.id-1_2")])
        XCTAssertEqual(s.sanitized(), s, "sanitized is idempotent")
    }

    func testShortcutSanitizing() {
        let cmdK = HotkeyCombo(keyCode: 40, carbonModifiers: 0x0100)
        XCTAssertEqual(MenuConfig.sanitizedCombo(cmdK), cmdK)
        XCTAssertNil(MenuConfig.sanitizedCombo(HotkeyCombo(keyCode: 40, carbonModifiers: 0)), "needs ⌘ or ⌃")
        XCTAssertNil(MenuConfig.sanitizedCombo(HotkeyCombo(keyCode: 40, carbonModifiers: 0x0800)), "⌥ alone")
        XCTAssertNil(MenuConfig.sanitizedCombo(HotkeyCombo(keyCode: 56, carbonModifiers: 0x0100)), "modifier key")
        XCTAssertNil(MenuConfig.sanitizedCombo(HotkeyCombo(keyCode: 200, carbonModifiers: 0x0100)))
        XCTAssertEqual(MenuConfig.sanitizedCombo(HotkeyCombo(keyCode: 122, carbonModifiers: 0)),
                       HotkeyCombo(keyCode: 122, carbonModifiers: 0), "F1 alone is fine")
        XCTAssertEqual(MenuConfig.sanitizedCombo(HotkeyCombo(keyCode: 40, carbonModifiers: 0x0100 | 0x4000_0000)), cmdK,
                       "stray bits are dropped")

        var c = MenuConfig()
        c.showPanelShortcut = cmdK
        c.identifyShortcut = cmdK
        let s = c.sanitized()
        XCTAssertEqual(s.showPanelShortcut, cmdK)
        XCTAssertNil(s.identifyShortcut, "one shortcut can't do two things")
    }

    // MARK: 0.3

    func testStyleIsTheCompactFlag() throws {
        var c = MenuConfig()
        XCTAssertEqual(c.style, .standard)
        c.style = .compact
        XCTAssertTrue(c.compact)
        XCTAssertEqual(c.style, .compact)
        let decoded = try JSONDecoder().decode(MenuConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded.style, .compact)
        c.style = .standard
        XCTAssertFalse(c.compact)
        XCTAssertEqual(MenuStyle.allCases, [.standard, .compact])
    }

    func testRestoringDefaultsPerScope() {
        let cmdK = HotkeyCombo(keyCode: 40, carbonModifiers: 0x0100)
        var c = MenuConfig()
        c.setVisibility(.hidden, for: brightness, default: .visible)
        c.setHidden(true, for: key(1))
        c.setCollapsed(true, for: key(2))
        c.displayOrder = [key(3), key(1)]
        c.sectionOrder = [.tools, .displays]
        c.mainFirst = false
        c.showBadges = false
        c.headerForSingleDisplay = false
        c.compact = true
        c.scrollAdjustsSliders = false
        c.showPanelShortcut = cmdK
        c.identifyShortcut = HotkeyCombo(keyCode: 34, carbonModifiers: 0x0100)

        let sheet = c.restoringDefaults(scope: .displaysMenu)
        XCTAssertTrue(sheet.items.values.isEmpty)
        XCTAssertEqual(sheet.hiddenDisplays, [])
        XCTAssertEqual(sheet.collapsedDisplays, [])
        XCTAssertEqual(sheet.displayOrder, [])
        XCTAssertEqual(sheet.orderedSections, [.displays, .tools])
        XCTAssertTrue(sheet.mainFirst && sheet.showBadges && sheet.headerForSingleDisplay)
        XCTAssertTrue(sheet.compact, "Style is the Menu Bar page's")
        XCTAssertFalse(sheet.scrollAdjustsSliders)
        XCTAssertEqual(sheet.showPanelShortcut, cmdK, "0.2 shortcut fields are never reset here")
        XCTAssertEqual(sheet.identifyShortcut, c.identifyShortcut)

        let page = c.restoringDefaults(scope: .menuBar)
        var expected = MenuConfig()
        expected.showPanelShortcut = c.showPanelShortcut
        expected.identifyShortcut = c.identifyShortcut
        XCTAssertEqual(page, expected)
        XCTAssertEqual(MenuConfig().restoringDefaults(scope: .menuBar), MenuConfig())
    }

    func testSlidersAreShowOrHideOnly() {
        let slider = DisplayMenuItemID(rawValue: "c.brightness.slider")
        let mute = DisplayMenuItemID(rawValue: "c.ddc.mute")
        XCTAssertTrue(MenuConfig.isSlider(slider))
        XCTAssertFalse(MenuConfig.isSlider(mute))
        XCTAssertEqual(MenuConfig.sliderItemIDs.count, 5)
        XCTAssertEqual(MenuConfig.choices(for: slider), [.visible, .hidden])
        XCTAssertEqual(MenuConfig.choices(for: mute), [.visible, .inSubmenu, .hidden])

        var c = MenuConfig()
        XCTAssertTrue(c.isSliderShown(slider, default: .visible))
        XCTAssertFalse(c.isSliderShown(slider, default: .hidden))
        // A 0.2 "In submenu" choice keeps the slider, now at the top level.
        c.items[slider] = .inSubmenu
        XCTAssertTrue(c.isSliderShown(slider, default: .visible))

        c.setSliderShown(false, for: slider, default: .visible)
        XCTAssertEqual(c.items[slider], .hidden)
        XCTAssertFalse(c.isSliderShown(slider, default: .visible))
        c.setSliderShown(true, for: slider, default: .visible)
        XCTAssertNil(c.items[slider], "equal to the default: no override")

        let contrast = DisplayMenuItemID(rawValue: "c.ddc.contrast")
        c.setSliderShown(true, for: contrast, default: .hidden)
        XCTAssertEqual(c.items[contrast], .visible)
        c.setSliderShown(false, for: contrast, default: .hidden)
        XCTAssertNil(c.items[contrast])

        // A slider whose descriptor default is "In submenu" shows by default and hides on request.
        let custom = DisplayMenuItemID(rawValue: "c.ddc.custom")
        XCTAssertTrue(c.isSliderShown(custom, default: .inSubmenu))
        c.setSliderShown(false, for: custom, default: .inSubmenu)
        XCTAssertFalse(c.isSliderShown(custom, default: .inSubmenu))
        c.setSliderShown(true, for: custom, default: .inSubmenu)
        XCTAssertNil(c.items[custom])
        XCTAssertTrue(c.isSliderShown(custom, default: .inSubmenu))
    }

    func testSectionOrderIsAlwaysAFullPermutation() {
        var c = MenuConfig()
        c.sectionOrder = []
        XCTAssertEqual(c.orderedSections, [.displays, .tools])
        c.sectionOrder = [.tools, .tools]
        XCTAssertEqual(c.orderedSections, [.tools, .displays])
        c.moveSection(.displays, by: -5)
        XCTAssertEqual(c.orderedSections, [.displays, .tools])
        c.moveSection(.displays, by: 9)
        XCTAssertEqual(c.orderedSections, [.tools, .displays])
    }

    func testFuzzedSanitizeIsStableAndBounded() throws {
        var rng = SeededGenerator(seed: 0xF00D)
        let visibilities = MenuItemVisibility.allCases
        for _ in 0..<2_000 {
            var c = MenuConfig()
            for _ in 0..<Int(rng.next() % 12) {
                let id = DisplayMenuItemID(rawValue: String(format: "id%llu", rng.next() % 50) + (rng.next() % 9 == 0 ? " " : ""))
                c.items[id] = visibilities[Int(rng.next() % 3)]
            }
            c.hiddenDisplays = (0..<Int(rng.next() % 80)).map { _ in key(Int(rng.next() % 90)) }
            c.displayOrder = (0..<Int(rng.next() % 80)).map { _ in key(Int(rng.next() % 90)) }
            c.sectionOrder = (0..<Int(rng.next() % 4)).map { _ in DisplaysMenuSection.allCases[Int(rng.next() % 2)] }
            c.showPanelShortcut = HotkeyCombo(keyCode: UInt32(rng.next() % 140), carbonModifiers: UInt32(truncatingIfNeeded: rng.next()))
            let s = c.sanitized()
            XCTAssertEqual(s.sanitized(), s)
            XCTAssertLessThanOrEqual(s.hiddenDisplays.count, MenuConfig.maxDisplays)
            XCTAssertEqual(Set(s.displayOrder).count, s.displayOrder.count)
            XCTAssertEqual(Set(s.sectionOrder), Set(DisplaysMenuSection.allCases))
            XCTAssertTrue(s.items.values.keys.allSatisfy(MenuConfig.isValidItemID))
            let decoded = try JSONDecoder().decode(MenuConfig.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(decoded, s)
        }
    }
}
