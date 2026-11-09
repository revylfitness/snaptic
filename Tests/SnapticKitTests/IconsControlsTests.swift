import XCTest
@testable import SnapticKit

/// 0.4 K5: Hidden Icons' control tables (§4.3, §4.8, §4.9) and their place in search.
final class IconsControlsTests: XCTestCase {
    private let tables: [any ControlTable.Type] = [
        IconsPageControls.self, IconsAdvancedSheetControls.self, IconsSectionsPageControls.self,
        IconsMenuRowsControls.self, IconsItemsControls.self,
    ]

    private func spec(_ id: String) -> ControlSpec? {
        tables.flatMap { $0.controls }.first { $0.id.rawValue == id }
    }

    func testEveryTableIsRegistered() {
        let registered = Set(ControlRegistry.tables.map { String(describing: $0) })
        for t in tables { XCTAssertTrue(registered.contains(String(describing: t)), String(describing: t)) }
    }

    func testSettingsSurfacesSearchIntoHiddenIcons() {
        let roots = Set(SettingsRootID.all)
        for t in [IconsPageControls.self, IconsAdvancedSheetControls.self, IconsSectionsPageControls.self]
            as [any ControlTable.Type] {
            XCTAssertTrue(SettingsIndexCoverage.isSettingsSurface(t.surface), t.surface)
            for spec in t.controls {
                guard let search = spec.search else { continue }
                XCTAssertEqual(search.root, SettingsRootID.hiddenIcons, spec.id.rawValue)
                for page in [search.route?.id, search.sheet].compactMap({ $0 }) {
                    XCTAssertEqual(SettingsLocation.resolve(page, roots: roots)?.root, SettingsRootID.hiddenIcons,
                                   page)
                }
            }
        }
        XCTAssertEqual(SettingsIndexCoverage.missing(tables), [])
        XCTAssertFalse(SettingsIndexCoverage.isSettingsSurface(IconsMenuRowsControls.surface))
        XCTAssertFalse(SettingsIndexCoverage.isSettingsSurface(IconsItemsControls.surface))
    }

    func testPageTitlesAndLocations() {
        XCTAssertEqual(SettingsIndex.pageTitle(IconsSectionsPageControls.surface), "Sections")
        XCTAssertEqual(SettingsIndex.pageTitle(IconsAdvancedSheetControls.sheet), "Advanced")
        let entry = SettingsSearchEntry(id: "x", title: "Refresh", root: SettingsRootID.hiddenIcons,
                                        route: SettingsRoute(IconsSectionsPageControls.surface), anchor: "x")
        XCTAssertEqual(SettingsIndex.location(of: entry, rootTitle: "Hidden Icons"), "Hidden Icons › Sections")
    }

    func testSearchFindsThePageFromOtherHidersNames() {
        let all = SettingsIndex.all(ControlRegistry.tables)
        for query in ["hidden bar", "bartender"] {
            let ids = SettingsSearch.rank(entries: all, query: query).map(\.id)
            XCTAssertTrue(ids.contains("icons.page.useHiddenIcons"), query)
        }
    }

    /// Everything but the master switch needs the module; engine-only rows name their engine (§4.9, §4.3).
    func testConditions() {
        for t in tables {
            for spec in t.controls where spec.id.rawValue != "icons.page.useHiddenIcons" {
                XCTAssertTrue(spec.when.contains(.module(.hiddenIcons)), spec.id.rawValue)
            }
        }
        XCTAssertEqual(spec("icons.page.useHiddenIcons")?.when, [])
        XCTAssertEqual(spec("icons.page.useHiddenIcons")?.keys, ["modules.*.enabled"])
        for id in ["icons.advanced.newApps", "icons.advanced.capture", "icons.sections.choice", "icons.sections.showAllAndRefresh",
                   "menu.icons.needsPermission"] {
            XCTAssertTrue(spec(id)?.when.contains(.iconsEngine(.native)) == true, id)
        }
        for id in ["menu.icons.allowAccessibility", "menu.iconItems.divider"] {
            XCTAssertTrue(spec(id)?.when.contains(.iconsEngine(.length)) == true, id)
        }
        XCTAssertTrue(spec("menu.icons.show")?.when.contains(.state(.iconsCollapsed)) == true)
        XCTAssertTrue(spec("menu.icons.hide")?.when.contains(.state(.iconsExpanded)) == true)
        XCTAssertTrue(spec("menu.icons.notchHeader")?.when.contains(.hardware(.notch)) == true)
        XCTAssertTrue(spec("icons.sections.choice")?.when.contains(.perItem("app")) == true)
    }

    /// The page's Restore Defaults… covers every exported setting and keeps `arranged`; the sheet's covers only its
    /// rows; Reset Arrow Position… is the one control on `arranged` (§4.9, §4.2.5).
    func testRestoreAndResetKeys() {
        XCTAssertEqual(Set(spec("icons.page.restore")?.keys ?? []), Set(IconsConfig.exportedKeys))
        XCTAssertFalse(spec("icons.page.restore")?.keys.contains("arranged") ?? true)
        let advancedRows = IconsAdvancedSheetControls.controls
            .filter { $0.kind == .setting }.flatMap(\.keys)
        XCTAssertEqual(Set(spec("icons.advanced.restore")?.keys ?? []), Set(advancedRows))
        let onArranged = tables.flatMap { $0.controls }.filter { $0.keys.contains("arranged") }.map(\.id.rawValue)
        XCTAssertEqual(onArranged, ["icons.advanced.resetArrow"])
    }

    func testEveryIconsSettingHasAControl() {
        let declared = Set(tables.flatMap { $0.controls }.flatMap(\.keys))
        let paths = ConfigFixtures.keyPaths(ConfigFixtures.fullIcons())
        let leaves = paths.filter { path in !paths.contains { $0.hasPrefix(path + ".") } }
        for path in leaves { XCTAssertTrue(ConfigFixtures.isCovered(path, by: declared), path) }
    }

    func testMenuRowsArentCustomizable() {
        for spec in IconsMenuRowsControls.controls + IconsItemsControls.controls {
            XCTAssertEqual(spec.menu?.customize, MenuCustomize.none, spec.id.rawValue)
            XCTAssertTrue(spec.replaces.isEmpty, spec.id.rawValue)
            XCTAssertNil(spec.search, spec.id.rawValue)
        }
    }

    // MARK: Canonical strings (§4.17, A7)

    /// The repository root (this file is Tests/SnapticKitTests/…), when the app sources are next to the tests.
    private static var repositoryRoot: URL? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = root.appendingPathComponent("Sources/Snaptic")
        return FileManager.default.fileExists(atPath: app.path) ? root : nil
    }

    /// §4.17's (and §4.16's) strings as the sources spell them: counts, times and names are the interpolations that fill them
    /// ("Hiding 7 icons" is `Hiding \(n) icons`, "9:41" is `\(time)`).
    private static let canonical: [String] = [
        #"Hidden Icons"#,
        #"Use Hidden Icons"#,
        #"Hide the menu bar icons you don’t need behind an arrow."#,
        #"Keep your menu bar tidy: click the arrow to hide the icons to its left, and click again to show them."#,
        #"Hidden Icons uses it to see where your menu bar icons are, so it can hide the right ones."#,
        #"Hidden Icons uses it to list your hidden icons. Hiding works without it."#,
        #"Hiding \(n) icons"#,
        #"Hiding 1 icon"#,
        #"Icons are hidden"#,
        #"Showing all icons"#,
        #"Arrange your icons, then click the arrow to hide them."#,
        #"How to Arrange…"#,
        #"Hidden Icons isn’t available on this version of macOS. Your icons stay shown."#,
        #"Hidden Icons is turned off on this Mac, so your icons stay shown."#,
        #"Move Snaptic to Applications to hide icons."#,
        #"Hidden Icons stopped using the macOS 27 method after a problem, so your icons stay shown."#,
        #"Try Again"#,
        #"Paused while \(hider.name) runs"#,
        #"Paused during an exam session"#,
        #"Icons were shown at \(time) because Snaptic couldn’t confirm they were hidden safely."#,
        #"Snaptic couldn’t hide icons, so they’re shown. Details are in Hidden Icons settings."#,
        #"Open Settings"#,
        #"Show Icons"#,
        #"Hide Icons"#,
        #"Hide icons automatically after \(seconds) seconds"#,
        #"Hide icons when Snaptic opens"#,
        #"Reopening Snaptic to show Settings doesn’t hide them."#,
        #"Always Hidden section"#,
        #"Icons left of the ⋮ divider stay hidden until you Option-click the arrow."#,
        #"Section dividers"#,
        #"Shows the | and ⋮ dividers while icons are shown."#,
        #"Shows the ⋮ divider while icons are shown. On this version of macOS the arrow marks the edge of "#
            + #"the hidden icons."#,
        #"Show or hide icons"#,
        #"Show or Hide Hidden Icons"#,
        #"Sections"#,
        #"\(hidden) hidden"#,
        #"\(choices) choices"#,
        #"Show Hidden Icons"#,
        #"Hide Icons Again"#,
        #"Show All Hidden Icons"#,
        #"Hide Icons Automatically"#,
        #"Hidden Icons Settings…"#,
        #"No Hidden Icons"#,
        #"Allow Accessibility to List Icons…"#,
        #"Needs Permission"#,
        #"Arrow and Snaptic Menu"#,
        #"Arrow Only"#,
        #"The arrow is always in the menu bar. Arrow and Snaptic Menu also lists hidden icons in the "#
            + #"Snaptic menu, so you can open one without showing them all."#,
        #"Off"#,
        #"Choose where each module appears in the menu bar."#,
        #"The Snaptic icon appears when a module is set to Show in Snaptic Menu, or Hidden Icons to Arrow "#
            + #"and Snaptic Menu. With two or more, the Snaptic menu shows a tab for each; while it’s open, "#
            + #"press ⌘1, ⌘2, and so on to switch tabs."#,
        #"Where each module appears, their icons, and the Displays menu go back to their defaults. Your "#
            + #"other Snaptic settings stay as they are."#,
        #"macOS can also hide icons, including the Hidden Icons arrow, in System Settings › Menu Bar. "#
            + #"Opening Snaptic again always shows Settings."#,
        #"How to Arrange Your Icons"#,
        #"Hold ⌘ and drag icons in the menu bar:"#,
        #"To the right of the arrow ‹: always shown."#,
        #"Between | and ‹: hidden when you click the arrow."#,
        #"Left of ⋮: hidden until you Option-click the arrow."#,
        #"New apps’ icons appear at the far left, so they start hidden."#,
        #"To the left of the arrow ‹: hidden when you click it."#,
        #"You can also choose Always Show or Always Hide for an app in Settings › Hidden Icons › Sections."#,
        #"Done"#,
        #"The arrow isn’t in the menu bar, so icons stay shown."#,
        #"The | divider isn’t in the menu bar, so icons stay shown."#,
        #"Hidden Icons needs Device Control and Data Access to see where your icons are."#,
        #"macOS may need Snaptic to reopen before the permission takes effect."#,
        #"Relaunch Snaptic"#,
        #"Open Privacy Settings"#,
        #"Show Arrow"#,
        // §4.16: the New card and onboarding (A8).
        #"New: Hidden Icons"#,
        #"Hide the menu bar icons you don’t need behind an arrow, and open them from the Snaptic menu."#,
        #"Turn On Hidden Icons"#,
        #"A window switcher, display controls, Keep Awake, and hidden menu bar icons, in your menu bar. "#
            + #"Turn on only what you want; everything else stays off."#,
        #"Arrange Your Icons"#,
        #"Nothing hides until you click the arrow for the first time."#,
        #"Click the arrow ‹ to hide icons once they’re arranged."#,
    ]

    /// Every §4.17 string is a whole literal somewhere in the app or Kit sources, so a reworded string fails here
    /// until the plan and the code agree again.
    func testEveryCanonicalStringIsInTheSources() throws {
        guard let root = Self.repositoryRoot else { throw XCTSkip("App sources aren't next to the tests.") }
        let sources = root.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return XCTFail("can't list \(sources.path)")
        }
        var text = ""
        for case let url as URL in walker where url.pathExtension == "swift" {
            text += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        for string in Self.canonical {
            XCTAssertTrue(text.contains("\"" + string + "\""), "§4.17 string not in the sources: \(string)")
        }
    }
}
