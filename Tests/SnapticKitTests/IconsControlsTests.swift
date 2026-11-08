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
        for id in ["icons.advanced.newApps", "icons.sections.choice", "icons.sections.showAllAndRefresh",
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
}
