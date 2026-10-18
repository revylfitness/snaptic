import XCTest
@testable import SnapticKit

final class SettingsShellRulesTests: XCTestCase {
    private let roots = Set(SettingsRootID.all)

    func testSevenRootsInSidebarOrder() {
        XCTAssertEqual(SettingsRootID.all,
                       ["general", "menuBar", "windowSwitcher", "displays", "awake", "permissions", "about"])
        XCTAssertEqual(roots.count, 7)
        XCTAssertEqual(SettingsRootID.groups.count, 3)
        for id in ModuleID.allCases { XCTAssertTrue(roots.contains(id.rawValue)) }
    }

    // MARK: resolve

    func testResolveRoots() {
        XCTAssertEqual(SettingsLocation.resolve("displays", roots: roots), SettingsLocation(root: "displays"))
        XCTAssertEqual(SettingsLocation.resolve("about", roots: roots), SettingsLocation(root: "about"))
    }

    func testResolveRoutes() {
        XCTAssertEqual(SettingsLocation.resolve("displays.color", roots: roots),
                       SettingsLocation(root: "displays", route: SettingsRoute("displays.color")))
        XCTAssertEqual(SettingsLocation.resolve("awake.history", roots: roots),
                       SettingsLocation(root: "awake", route: SettingsRoute("awake.history")))
        XCTAssertEqual(SettingsLocation.resolve("general.cli", roots: roots),
                       SettingsLocation(root: "general", route: SettingsRoute("general.cli")))
        XCTAssertEqual(SettingsLocation.resolve("switcher.features", roots: roots),
                       SettingsLocation(root: "windowSwitcher", route: SettingsRoute("switcher.features")))
        XCTAssertEqual(SettingsLocation.resolve("menubar.customize", roots: roots),
                       SettingsLocation(root: "menuBar", route: SettingsRoute("menubar.customize")))
    }

    func testResolveLegacyPagesWithTheirOwnRoot() {
        XCTAssertEqual(SettingsLocation.resolve("general.modules", roots: roots), SettingsLocation(root: "general"))
        XCTAssertEqual(SettingsLocation.resolve("general.menu", roots: roots), SettingsLocation(root: "menuBar"))
        XCTAssertEqual(SettingsLocation.resolve("general.permissions", roots: roots),
                       SettingsLocation(root: "permissions"))
        XCTAssertEqual(SettingsLocation.resolve("general.about", roots: roots), SettingsLocation(root: "about"))
    }

    func testResolveRejects() {
        XCTAssertNil(SettingsLocation.resolve("bogus.x", roots: roots))
        XCTAssertNil(SettingsLocation.resolve("bogus", roots: roots))
        XCTAssertNil(SettingsLocation.resolve("displays.", roots: roots))
        XCTAssertNil(SettingsLocation.resolve(".displays", roots: roots))
        XCTAssertNil(SettingsLocation.resolve("", roots: roots))
        XCTAssertNil(SettingsLocation.resolve("displays color", roots: roots))
        XCTAssertNil(SettingsLocation.resolve("displays.cölor", roots: roots))
        XCTAssertNil(SettingsLocation.resolve("displays." + String(repeating: "a", count: 60), roots: roots))
        XCTAssertNil(SettingsLocation.resolve("displays.color", roots: ["general"]))
        XCTAssertNil(SettingsLocation.resolve("general.about", roots: ["general"]))
    }

    // MARK: encoded

    func testEncodedRoundTrip() {
        let withRoute = SettingsLocation(root: "displays", route: SettingsRoute("displays.color"))
        XCTAssertEqual(withRoute.encoded, "displays displays.color")
        XCTAssertEqual(SettingsLocation(encoded: withRoute.encoded, roots: roots), withRoute)
        let rootOnly = SettingsLocation(root: "awake")
        XCTAssertEqual(rootOnly.encoded, "awake")
        XCTAssertEqual(SettingsLocation(encoded: "awake", roots: roots), rootOnly)
    }

    func testEncodedRejects() {
        XCTAssertNil(SettingsLocation(encoded: "", roots: roots))
        XCTAssertNil(SettingsLocation(encoded: "nope", roots: roots))
        XCTAssertNil(SettingsLocation(encoded: "displays a b", roots: roots))
        XCTAssertNil(SettingsLocation(encoded: "displays bad!", roots: roots))
        XCTAssertNil(SettingsLocation(encoded: "displays ", roots: roots))
        XCTAssertNil(SettingsLocation(encoded: " displays", roots: roots))
        XCTAssertNil(SettingsLocation(encoded: "displays", roots: ["general"]))
    }

    func testValidIDs() {
        XCTAssertTrue(SettingsLocation.isValidID("displays.color"))
        XCTAssertTrue(SettingsLocation.isValidID("a-b_c.D9"))
        XCTAssertFalse(SettingsLocation.isValidID(""))
        XCTAssertFalse(SettingsLocation.isValidID("a/b"))
        XCTAssertFalse(SettingsLocation.isValidID(String(repeating: "a", count: 65)))
        XCTAssertTrue(SettingsLocation.isValidID(String(repeating: "a", count: 64)))
    }

    // MARK: Focus guard (R5-8)

    func testFreshGuardAllowsEverything() {
        let g = SettingsFocusGuard()
        XCTAssertTrue(g.mayStart(now: 100, eventIsKeyDown: true))
        XCTAssertTrue(g.mayStart(now: 100, eventIsKeyDown: false))
        XCTAssertFalse(g.externalOpenPending)
    }

    func testExternalOpenGuardsOneSecond() {
        var g = SettingsFocusGuard()
        g.externalOpen(now: 100)
        XCTAssertTrue(g.externalOpenPending)
        XCTAssertFalse(g.mayStart(now: 100, eventIsKeyDown: false))
        XCTAssertFalse(g.mayStart(now: 100.99, eventIsKeyDown: false))
        XCTAssertTrue(g.mayStart(now: 101, eventIsKeyDown: false))
        XCTAssertTrue(g.mayStart(now: 500, eventIsKeyDown: false))
        // A clock that reads earlier than the open fails safe.
        XCTAssertFalse(g.mayStart(now: 50, eventIsKeyDown: false))
    }

    func testKeyDownRefusedUntilMouseDown() {
        var g = SettingsFocusGuard()
        g.externalOpen(now: 100)
        XCTAssertFalse(g.mayStart(now: 200, eventIsKeyDown: true))
        g.mouseDown()
        XCTAssertFalse(g.externalOpenPending)
        XCTAssertTrue(g.mayStart(now: 200, eventIsKeyDown: true))
    }

    func testMouseDownDoesNotEndTheTimer() {
        var g = SettingsFocusGuard()
        g.externalOpen(now: 100)
        g.mouseDown()
        XCTAssertFalse(g.mayStart(now: 100.5, eventIsKeyDown: false))
        XCTAssertTrue(g.mayStart(now: 101.5, eventIsKeyDown: true))
    }

    func testInternalOpenClearsEverything() {
        var g = SettingsFocusGuard()
        g.externalOpen(now: 100)
        g.internalOpen()
        XCTAssertFalse(g.externalOpenPending)
        XCTAssertTrue(g.mayStart(now: 100.1, eventIsKeyDown: true))
        XCTAssertNil(g.externalOpenAt)
    }
}

final class SettingsHelpAnchorsTests: XCTestCase {
    func testEveryRootHasAnAnchor() {
        for root in SettingsRootID.all { XCTAssertNotNil(SettingsHelpAnchors.anchor(for: root), root) }
    }

    func testMostSpecificPrefixWins() {
        XCTAssertEqual(SettingsHelpAnchors.anchor(for: "displays.color"), "color")
        XCTAssertEqual(SettingsHelpAnchors.anchor(for: "displays.color.advanced"), "color")
        XCTAssertEqual(SettingsHelpAnchors.anchor(for: "displays.pip"), "displays")
        XCTAssertEqual(SettingsHelpAnchors.anchor(for: "windowSwitcher"), "window-switcher")
        XCTAssertEqual(SettingsHelpAnchors.anchor(for: "switcher.advanced"), "window-switcher")
        XCTAssertEqual(SettingsHelpAnchors.anchor(for: "awake.rules"), "awake")
        XCTAssertNil(SettingsHelpAnchors.anchor(for: "nowhere"))
        XCTAssertNil(SettingsHelpAnchors.anchor(for: ""))
    }

    func testURLs() {
        XCTAssertEqual(SettingsHelpAnchors.url(for: "menuBar"), SettingsHelpAnchors.readme + "#menu-bar")
        XCTAssertEqual(SettingsHelpAnchors.url(for: "nowhere"), SettingsHelpAnchors.readme)
        for anchor in SettingsHelpAnchors.anchors.values {
            XCTAssertTrue(anchor.unicodeScalars.allSatisfy { ($0 >= "a" && $0 <= "z") || $0 == "-" }, anchor)
        }
    }

    /// Each page that shows (?) has its own anchor (the README headings these name are listed for the docs).
    func testPagesWithHelpHaveSpecificAnchors() {
        for page in ["displays.brightness", "displays.hardware", "displays.color", "displays.keyboard", "displays.info"] {
            XCTAssertNotEqual(SettingsHelpAnchors.anchor(for: page), "displays", page)
        }
    }
}
