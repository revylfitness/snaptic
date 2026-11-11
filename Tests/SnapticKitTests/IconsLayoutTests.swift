import XCTest
@testable import SnapticKit

// 0.4 K2 (§4.2.5, §4.2.6, §4.8). The first six resolver tests port Hidden Bar's `MenuBarLayoutResolverTests` as
// behaviour: an LTR bar with `⋮` at 1000 and `|` at 1300 on a 1728 pt screen.

private let screen = IconsRect(x: 0, y: 0, width: 1728, height: 1117)
private let alwaysHiddenDivider = IconsRect(x: 1000, y: 0, width: 20, height: 24)
private let divider = IconsRect(x: 1300, y: 0, width: 20, height: 24)
private let toggle = IconsRect(x: 1340, y: 0, width: 24, height: 24)
private let skip = IconsSkipRules(ownPID: 1, ownBundlePath: "/Applications/Snaptic.app")

private func rect(_ x: Double, width: Double = 24) -> IconsRect {
    IconsRect(x: x, y: 0, width: width, height: 24)
}

/// One `.ok` app with an extra at each x.
private func app(_ bundle: String?, _ xs: Double..., path: String? = nil, pid: Int32? = nil,
                 result: IconsReadResult = .ok) -> IconsAppRead {
    // A pid per bundle, clear of Snaptic's own (1).
    var hash = 0
    for scalar in (bundle ?? "").unicodeScalars {
        hash = (hash * 31 + Int(scalar.value)) % 100_000
    }
    let p: Int32 = pid ?? Int32(100 + hash)
    let extras = xs.enumerated().map { IconsExtra(pid: p, bundleID: bundle, index: $0.offset, frame: rect($0.element)) }
    return IconsAppRead(pid: p, bundleID: bundle, bundlePath: path ?? bundle.map { "/Applications/\($0).app" },
                        result: result, extras: extras)
}

private func ltr(alwaysHidden: IconsRect? = alwaysHiddenDivider) -> IconsBoundaries {
    IconsBoundaries(hidden: divider, alwaysHidden: alwaysHidden)
}

private func resolve(_ apps: [IconsAppRead], _ boundaries: IconsBoundaries? = ltr(), screen s: IconsRect? = screen,
                     previous: [String: IconsSection]? = nil, scope: IconsReadScope = .unrestricted,
                     failed: Bool = false) -> IconsResolution {
    IconsLayoutResolver.resolve(IconsInventory(apps: apps, failed: failed, readAt: 42), boundaries: boundaries,
                                screen: s, skip: skip, previous: previous, scope: scope)
}

private func sections(_ resolution: IconsResolution, file: StaticString = #filePath,
                      line: UInt = #line) -> [String: IconsSection] {
    guard let layout = resolution.layout else {
        XCTFail("unusable: \(resolution)", file: file, line: line)
        return [:]
    }
    return layout.sections
}

final class IconsLayoutResolverTests: XCTestCase {
    // MARK: Hidden Bar's six

    func testLTRSectionsFollowTheDividers() {
        let r = resolve([app("com.always", 900), app("com.hidden", 1100), app("com.visible", 1400)])
        XCTAssertEqual(sections(r), ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .shown])
    }

    func testRTLSectionsAreMirrored() {
        // RTL: the arrow on the left, `|` just right of it, hidden further right.
        let b = IconsBoundaries(hidden: rect(300, width: 20), alwaysHidden: rect(600, width: 20), rightToLeft: true)
        let r = resolve([app("com.visible", 200), app("com.hidden", 450), app("com.always", 700)], b)
        XCTAssertEqual(sections(r), ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .shown])
    }

    func testWithoutTheAlwaysHiddenDividerEverythingBeyondIsHidden() {
        let r = resolve([app("com.far", 100), app("com.near", 1200)], ltr(alwaysHidden: nil))
        XCTAssertEqual(sections(r), ["com.far": .hidden, "com.near": .hidden])
    }

    func testTheMostVisibleExtraWinsForABundle() {
        let r = resolve([app("com.split", 1100, 1400), app("com.pair", 900, 1100)])
        XCTAssertEqual(sections(r)["com.split"], .shown)
        XCTAssertEqual(sections(r)["com.pair"], .hidden)
        // Order doesn't matter.
        let reversed = resolve([app("com.split", 1400, 1100), app("com.pair", 1100, 900)])
        XCTAssertEqual(sections(reversed), sections(r))
    }

    func testSkipsOwnSystemAndUnidentifiedApps() {
        let r = resolve([
            app("com.example.snaptic", 1100, path: "/Applications/Snaptic.app"),
            app("com.apple.MenuBarAgent", 1100, path: "/System/Library/CoreServices/MenuBarAgent.app"),
            app(nil, 1100, path: "/Applications/Nameless.app"),
            app("com.app", 1100),
        ])
        XCTAssertEqual(sections(r), ["com.app": .hidden])
    }

    func testBundlesAreFilteredAndSorted() {
        let layout = IconsLayout(sections: ["b": .shown, "a": .shown, "c": .hidden, "d": .alwaysHidden],
                                 systemBundles: [], carried: [], extras: [], offScreen: [], scope: .unrestricted,
                                 readAt: 0)
        XCTAssertEqual(layout.bundles(in: [.shown]), ["a", "b"])
        XCTAssertEqual(layout.bundles(in: [.shown, .hidden]), ["a", "b", "c"])
        XCTAssertEqual(layout.bundles(in: [.alwaysHidden]), ["d"])
    }

    // MARK: RTL, clipping, screens

    func testRTLMostVisibleWinsAndNoAlwaysHidden() {
        let b = IconsBoundaries(hidden: rect(300, width: 20), rightToLeft: true)
        let r = resolve([app("com.split", 700, 100), app("com.far", 900, 1200)], b)
        XCTAssertEqual(sections(r), ["com.split": .shown, "com.far": .hidden])
    }

    func testTheBoundaryIsTheDividersShownEdge() {
        // A Length-inflated `|` (minX far left) keeps its shown-side edge, so sections don't move.
        let inflated = IconsRect(x: 1320 - 3456, y: 0, width: 3456, height: 24)
        let r = resolve([app("com.hidden", 1100), app("com.visible", 1400)], IconsBoundaries(hidden: inflated))
        XCTAssertEqual(sections(r), ["com.hidden": .hidden, "com.visible": .shown])
    }

    func testExtrasOffTheArrowsScreenAreDropped() {
        // The app's other extra sits on the screen to the right; only the one on this screen counts.
        let r = resolve([app("com.two", 1100, 2000), app("com.right", 2100)])
        let layout = try? XCTUnwrap(r.layout)
        XCTAssertEqual(layout?.sections["com.two"], .hidden)
        // Every extra off this screen: it can't be placed, so it counts as shown.
        XCTAssertEqual(layout?.sections["com.right"], .shown)
        XCTAssertEqual(layout?.carried, ["com.right"])
        XCTAssertEqual(layout?.offScreen.map(\.frame.x).sorted(), [2000, 2100])
        XCTAssertEqual(layout?.extras.map(\.extra.bundleID), ["com.two"])
    }

    func testLengthCollapsedExtrasAreOffScreenAndKeepTheirSection() {
        // Collapsed on Length, the hidden icons sit at negative x. The read keeps the cached section and reports them.
        let r = resolve([app("com.hidden", -2400), app("com.visible", 1400)], previous: ["com.hidden": .hidden])
        XCTAssertEqual(sections(r), ["com.hidden": .hidden, "com.visible": .shown])
        XCTAssertEqual(r.layout?.offScreen.count, 1)
        XCTAssertEqual(r.layout?.carried, ["com.hidden"])
    }

    func testASecondaryScreenToTheLeftUsesItsOwnXRange() {
        // The arrow is on a screen left of the main one (negative x). Main-screen extras are dropped.
        let left = IconsRect(x: -1920, y: 0, width: 1920, height: 1080)
        let b = IconsBoundaries(hidden: rect(-400, width: 20))
        let r = resolve([app("com.hidden", -900), app("com.visible", -200), app("com.main", 500)], b, screen: left)
        XCTAssertEqual(sections(r), ["com.hidden": .hidden, "com.visible": .shown, "com.main": .shown])
        XCTAssertEqual(r.layout?.carried, ["com.main"])
    }

    func testTheScreenPickUsesYWhenScreensShareAnXRange() {
        let main = IconsScreen(frame: screen)
        let above = IconsScreen(frame: IconsRect(x: 0, y: -1080, width: 1920, height: 1080))
        let onAbove = IconsRect(x: 1340, y: -1080, width: 24, height: 24)
        XCTAssertEqual(IconsGeometry.screen(holding: onAbove, in: [main, above]), above)
        XCTAssertEqual(IconsGeometry.screen(holding: toggle, in: [above, main]), main)
        // Off every screen's height: the first whose x range holds it.
        XCTAssertEqual(IconsGeometry.screen(holding: IconsRect(x: 10, y: 5000, width: 4, height: 4),
                                            in: [main, above]), main)
        XCTAssertNil(IconsGeometry.screen(holding: rect(9000), in: [main, above]))
    }

    func testZeroSizeAndNonFiniteExtrasArePlacedNowhere() {
        var a = app("com.odd", 1100, 1400)
        a.extras[1].frame = IconsRect(x: 1400, y: 0, width: 0, height: 24)
        var b = app("com.nan", 1400)
        b.extras[0].frame = IconsRect(x: .nan, y: 0, width: 24, height: 24)
        let r = resolve([a, b])
        XCTAssertEqual(r.layout?.sections["com.odd"], .hidden)
        XCTAssertEqual(r.layout?.sections["com.nan"], .shown)
        XCTAssertEqual(r.layout?.carried, ["com.nan"])
        XCTAssertEqual(r.layout?.offScreen, [])
    }

    // MARK: Skips by path

    func testSkipsGoByPathNotId() {
        let r = resolve([
            // A spoofed id from /Applications is just an app.
            app("com.apple.controlcenter", 1100, path: "/Applications/Fake.app"),
            // `..` doesn't make a path a system path.
            app("com.evil", 1150, path: "/System/../Applications/Evil.app"),
            app("com.lookalike", 1160, path: "/SystemX/Lookalike.app"),
            app("com.apple.TextInputMenuAgent", 1400,
                path: "/System/Library/CoreServices/TextInputMenuAgent.app"),
            app("com.apple.MenuBarAgent", 1400, path: "/System/Library/CoreServices/MenuBarAgent.app"),
            // Own: by pid, or by Snaptic's own path whatever the id.
            app("com.someone.else", 1400, pid: 1),
            app("com.renamed", 1400, path: "/Applications/./Snaptic.app"),
        ])
        XCTAssertEqual(sections(r), ["com.apple.controlcenter": .hidden, "com.evil": .hidden,
                                     "com.lookalike": .hidden])
        // macOS owners other than MenuBarAgent are allowed by bundle on Native (R2-1).
        XCTAssertEqual(r.layout?.systemBundles, ["com.apple.TextInputMenuAgent"])
    }

    func testSkipReasons() {
        XCTAssertEqual(skip.skip(app("x", 1, pid: 1)), .own)
        XCTAssertEqual(skip.skip(app("x", 1, path: "/Applications/Snaptic.app/")), .own)
        XCTAssertEqual(skip.skip(app("x", 1, path: "/System/Applications/Clock.app")), .system)
        XCTAssertEqual(skip.skip(app(nil, 1)), .unidentified)
        XCTAssertEqual(skip.skip(app("", 1)), .unidentified)
        XCTAssertNil(skip.skip(app("com.app", 1)))
        XCTAssertNil(skip.skip(app("com.app", 1, path: "relative/System/App.app")))
        XCTAssertTrue(IconsSkipRules.isSystemPath("//System//Library/./CoreServices/X.app"))
        XCTAssertFalse(IconsSkipRules.isSystemPath("/System"))
    }

    // MARK: Per-app results

    func testAnAppThatWasntReadKeepsItsSectionOrCountsAsShown() {
        let r = resolve([
            app("com.ok", 1100),
            app("com.slow", result: .timedOut),
            app("com.refused", result: .denied),
            app("com.empty", result: .noExtras),
            app("com.new", result: .timedOut),
        ], previous: ["com.slow": .alwaysHidden, "com.refused": .hidden, "com.empty": .hidden, "com.ok": .shown])
        XCTAssertEqual(sections(r), ["com.ok": .hidden, "com.slow": .alwaysHidden, "com.refused": .hidden,
                                     "com.empty": .hidden, "com.new": .shown])
        XCTAssertEqual(r.layout?.carried, ["com.slow", "com.refused", "com.empty", "com.new"])
    }

    func testANonOKReadCarriesNoExtras() {
        let read = IconsAppRead(pid: 9, bundleID: "com.x", bundlePath: nil, result: .timedOut,
                                extras: [IconsExtra(pid: 9, bundleID: "com.x", index: 0, frame: rect(1100))])
        XCTAssertEqual(read.extras, [])
    }

    func testAnOKReadInOneProcessWinsOverAnotherThatTimedOut() {
        let r = resolve([app("com.multi", result: .timedOut), app("com.multi", 1100)],
                        previous: ["com.multi": .alwaysHidden])
        XCTAssertEqual(sections(r), ["com.multi": .hidden])
        XCTAssertEqual(r.layout?.carried, [])
    }

    // MARK: Restricted reads

    func testARestrictedReadTrustsOnlyAllowedBundles() {
        // `com.ah` is hidden by the assertion: its stale frame says shown, but it keeps its cached section.
        let r = resolve([app("com.shown", 1100), app("com.hid", 1400), app("com.ah", 1500), app("com.unknown", 1500)],
                        previous: ["com.shown": .shown, "com.hid": .hidden, "com.ah": .alwaysHidden],
                        scope: .restricted(allowed: ["com.shown", "com.hid"]))
        XCTAssertEqual(sections(r), ["com.shown": .hidden, "com.hid": .shown, "com.ah": .alwaysHidden])
        XCTAssertEqual(r.layout?.carried, ["com.ah"])
        XCTAssertEqual(r.layout?.scope, .restricted(allowed: ["com.shown", "com.hid"]))
    }

    // MARK: Reads that never collapse

    func testAFailedReadIsUnusable() {
        XCTAssertEqual(resolve([app("com.a", 1100)], failed: true), .unusable(.failed))
        XCTAssertEqual(IconsLayoutResolver.resolve(.failure(), boundaries: ltr(), screen: screen, skip: skip,
                                                   previous: nil), .unusable(.failed))
    }

    func testAnEmptyReadIsUnusable() {
        XCTAssertEqual(resolve([]), .unusable(.empty))
        XCTAssertEqual(resolve([app("com.a", result: .noExtras), app("com.b", result: .timedOut)]), .unusable(.empty))
    }

    func testLosingEveryThirdPartyIconWhileTheirAppsRunIsUnusable() {
        let system = app("com.apple.TextInputMenuAgent", 1400, path: "/System/Library/CoreServices/TIMA.app")
        let r = resolve([system, app("com.hid", result: .noExtras)], previous: ["com.hid": .hidden])
        XCTAssertEqual(r, .unusable(.lostThirdParty))
        // A timed-out app that was placed last time counts too.
        XCTAssertEqual(resolve([system, app("com.hid", result: .timedOut)], previous: ["com.hid": .hidden]),
                       .unusable(.lostThirdParty))
    }

    func testAnEmptyBarAfterTheAppsQuitIsTheTruth() {
        let system = app("com.apple.TextInputMenuAgent", 1400, path: "/System/Library/CoreServices/TIMA.app")
        XCTAssertEqual(sections(resolve([system], previous: ["com.gone": .hidden])), [:])
        // A first read with only macOS's icons is fine too.
        XCTAssertEqual(sections(resolve([system], previous: nil)), [:])
    }

    func testARestrictedReadOnlyCountsAllowedAppsAsLost() {
        let system = app("com.apple.TextInputMenuAgent", 1400, path: "/System/Library/CoreServices/TIMA.app")
        // The only running app from the last read is outside the allow-list: its absence proves nothing.
        let r = resolve([system, app("com.ah", result: .noExtras)], previous: ["com.ah": .alwaysHidden],
                        scope: .restricted(allowed: []))
        XCTAssertEqual(sections(r), ["com.ah": .alwaysHidden])
        let lost = resolve([system, app("com.hid", result: .noExtras)], previous: ["com.hid": .hidden],
                           scope: .restricted(allowed: ["com.hid"]))
        XCTAssertEqual(lost, .unusable(.lostThirdParty))
    }

    func testNoBoundaryOrNoScreenIsUnusable() {
        XCTAssertEqual(resolve([app("com.a", 1100)], nil), .unusable(.noBoundary))
        XCTAssertEqual(resolve([app("com.a", 1100)], screen: nil), .unusable(.noScreen))
        XCTAssertEqual(resolve([app("com.a", 1100)], screen: IconsRect(x: 0, y: 0, width: 0, height: 0)),
                       .unusable(.noScreen))
    }

    // MARK: Rows

    func testRowsAreNearestTheBoundaryFirst() throws {
        let layout = try XCTUnwrap(resolve([app("com.a", 1100, 1250), app("com.b", 1200), app("com.c", 1400, 1600),
                                            app("com.ah", 500, 900)]).layout)
        XCTAssertEqual(layout.rows(in: .hidden).map(\.extra.frame.x), [1250, 1200, 1100])
        XCTAssertEqual(layout.rows(in: .shown).map(\.extra.frame.x), [1400, 1600])
        XCTAssertEqual(layout.rows(in: .alwaysHidden).map(\.extra.frame.x), [900, 500])
        XCTAssertEqual(layout.cache, IconsLayoutCache(readAt: 42, sections: layout.sections))
    }

    func testRowTiesBreakByPidThenIndex() throws {
        let a = IconsAppRead(pid: 7, bundleID: "com.a", bundlePath: nil, result: .ok,
                             extras: [IconsExtra(pid: 7, bundleID: "com.a", index: 1, frame: rect(1100)),
                                      IconsExtra(pid: 7, bundleID: "com.a", index: 0, frame: rect(1100))])
        let b = IconsAppRead(pid: 5, bundleID: "com.b", bundlePath: nil, result: .ok,
                             extras: [IconsExtra(pid: 5, bundleID: "com.b", index: 3, frame: rect(1100))])
        let layout = try XCTUnwrap(resolve([a, b]).layout)
        XCTAssertEqual(layout.rows(in: .hidden).map { "\($0.extra.pid).\($0.extra.index)" }, ["5.3", "7.0", "7.1"])
    }
}

final class IconsGuardsTests: XCTestCase {
    // MARK: arrangementValid

    func testLengthNeedsTheDividerBeyondTheArrow() {
        XCTAssertTrue(IconsGuards.arrangementValid(engine: .length, toggle: toggle, separator: divider,
                                                   rightToLeft: false))
        XCTAssertFalse(IconsGuards.arrangementValid(engine: .length, toggle: toggle, separator: rect(1400, width: 20),
                                                    rightToLeft: false))
        // Inflated, it still ends before the arrow.
        let inflated = IconsRect(x: 1320 - 3456, y: 0, width: 3456, height: 24)
        XCTAssertTrue(IconsGuards.arrangementValid(engine: .length, toggle: toggle, separator: inflated,
                                                   rightToLeft: false))
        // Dividers off: zero length still has a position.
        XCTAssertTrue(IconsGuards.arrangementValid(engine: .length, toggle: toggle, separator: rect(1320, width: 0),
                                                   rightToLeft: false))
    }

    func testLengthArrangementInRTL() {
        let rtlToggle = rect(270, width: 24)
        XCTAssertTrue(IconsGuards.arrangementValid(engine: .length, toggle: rtlToggle, separator: rect(300, width: 20),
                                                   rightToLeft: true))
        XCTAssertFalse(IconsGuards.arrangementValid(engine: .length, toggle: rtlToggle,
                                                    separator: rect(200, width: 20), rightToLeft: true))
    }

    func testMissingFramesAreInvalidOnLengthButNotNative() {
        XCTAssertFalse(IconsGuards.arrangementValid(engine: .length, toggle: nil, separator: divider,
                                                    rightToLeft: false))
        XCTAssertFalse(IconsGuards.arrangementValid(engine: .length, toggle: toggle, separator: nil,
                                                    rightToLeft: false))
        XCTAssertFalse(IconsGuards.arrangementValid(engine: .length, toggle: toggle,
                                                    separator: IconsRect(x: .infinity, y: 0, width: 20, height: 24),
                                                    rightToLeft: false))
        XCTAssertTrue(IconsGuards.arrangementValid(engine: .native, toggle: nil, separator: nil, rightToLeft: false))
    }

    // MARK: alwaysHiddenPlaced

    func testAlwaysHiddenIsPlacedBeyondTheDividerOnLength() {
        func placed(_ ah: IconsRect?, _ sep: IconsRect? = divider, rtl: Bool = false) -> Bool {
            IconsGuards.alwaysHiddenPlaced(engine: .length, toggle: toggle, separator: sep, alwaysHidden: ah,
                                           screen: screen, rightToLeft: rtl)
        }
        XCTAssertTrue(placed(alwaysHiddenDivider))
        XCTAssertFalse(placed(rect(1310, width: 20)))     // between `|` and the arrow
        XCTAssertFalse(placed(nil))
        XCTAssertFalse(placed(alwaysHiddenDivider, nil))
        // Grown for a plain expand, its shown-side edge is still on screen and beyond `|`.
        XCTAssertTrue(placed(IconsRect(x: 1020 - 3456, y: 0, width: 3456, height: 24)))
        // Off-screen counts as not placed.
        XCTAssertFalse(placed(rect(-200, width: 20)))
        XCTAssertFalse(placed(rect(1800, width: 20)))
    }

    func testAlwaysHiddenOnNativeIsMeasuredFromTheArrow() {
        func placed(_ ah: IconsRect) -> Bool {
            IconsGuards.alwaysHiddenPlaced(engine: .native, toggle: toggle, separator: nil, alwaysHidden: ah,
                                           screen: screen, rightToLeft: false)
        }
        XCTAssertTrue(placed(rect(1310, width: 20)))
        XCTAssertFalse(placed(rect(1400, width: 20)))
    }

    func testAlwaysHiddenInRTL() {
        let rtlScreen = screen
        XCTAssertTrue(IconsGuards.alwaysHiddenPlaced(engine: .length, toggle: rect(270), separator: rect(300, width: 20),
                                                     alwaysHidden: rect(600, width: 20), screen: rtlScreen,
                                                     rightToLeft: true))
        XCTAssertFalse(IconsGuards.alwaysHiddenPlaced(engine: .length, toggle: rect(270),
                                                      separator: rect(300, width: 20),
                                                      alwaysHidden: rect(250, width: 20), screen: rtlScreen,
                                                      rightToLeft: true))
    }

    func testBoundariesDropAnUnplacedAlwaysHiddenDivider() throws {
        let length = try XCTUnwrap(IconsGuards.boundaries(engine: .length, toggle: toggle, separator: divider,
                                                          alwaysHidden: rect(1310, width: 20), screen: screen,
                                                          rightToLeft: false))
        XCTAssertEqual(length, IconsBoundaries(hidden: divider))
        // So what sits beyond `⋮` resolves as Hidden.
        let r = IconsLayoutResolver.resolve(IconsInventory(apps: [app("com.far", 100)]), boundaries: length,
                                            screen: screen, skip: skip, previous: nil)
        XCTAssertEqual(r.layout?.sections, ["com.far": .hidden])

        let native = try XCTUnwrap(IconsGuards.boundaries(engine: .native, toggle: toggle, separator: nil,
                                                          alwaysHidden: alwaysHiddenDivider, screen: screen,
                                                          rightToLeft: false))
        XCTAssertEqual(native, IconsBoundaries(hidden: toggle, alwaysHidden: alwaysHiddenDivider))
        XCTAssertNil(IconsGuards.boundaries(engine: .length, toggle: toggle, separator: nil, alwaysHidden: nil,
                                            screen: screen, rightToLeft: false))
        XCTAssertNil(IconsGuards.boundaries(engine: .native, toggle: nil, separator: divider, alwaysHidden: nil,
                                            screen: screen, rightToLeft: false))
    }

    // MARK: Own items (Length)

    func testOwnItemsPlacement() {
        let items = [IconsOwnItem(id: "Snaptic.main", frame: rect(1400)),
                     IconsOwnItem(id: "Snaptic.awake", frame: rect(1200), isAwake: true),
                     IconsOwnItem(id: "Snaptic.displays", frame: rect(900)),
                     IconsOwnItem(id: "Snaptic.new", frame: nil)]
        let p = IconsGuards.ownItemsPlacement(toggle: toggle, separator: divider, items: items, rightToLeft: false)
        XCTAssertEqual(p, IconsOwnItemsPlacement(known: true, toggleBeyond: false,
                                                 beyond: ["Snaptic.awake", "Snaptic.displays"], awakeBeyond: true,
                                                 unplaced: ["Snaptic.new"]))
    }

    func testOwnItemsWithTheArrowBeyondTheDivider() {
        let p = IconsGuards.ownItemsPlacement(toggle: rect(1200), separator: divider,
                                              items: [IconsOwnItem(id: "Snaptic.main", frame: rect(1400))],
                                              rightToLeft: false)
        XCTAssertTrue(p.toggleBeyond)
        XCTAssertFalse(p.awakeBeyond)
        XCTAssertEqual(p.beyond, [])
    }

    func testOwnItemsInRTL() {
        let p = IconsGuards.ownItemsPlacement(toggle: rect(270), separator: rect(300, width: 20),
                                              items: [IconsOwnItem(id: "a", frame: rect(200), isAwake: true),
                                                      IconsOwnItem(id: "b", frame: rect(500))],
                                              rightToLeft: true)
        XCTAssertEqual(p.beyond, ["b"])
        XCTAssertFalse(p.awakeBeyond)
    }

    func testOwnItemsWithoutFramesAreUnknown() {
        XCTAssertEqual(IconsGuards.ownItemsPlacement(toggle: nil, separator: divider, items: [], rightToLeft: false),
                       .unknown)
        XCTAssertEqual(IconsGuards.ownItemsPlacement(toggle: toggle, separator: nil, items: [], rightToLeft: false),
                       .unknown)
    }
}

final class IconsNotchTests: XCTestCase {
    private let notched = IconsScreen(frame: screen, safeAreaTop: 38, auxiliaryTopRightMinX: 952)
    private let external = IconsScreen(frame: IconsRect(x: 1728, y: 0, width: 2560, height: 1440))

    private func row(_ x: Double, width: Double = 24) -> IconsPlacedExtra {
        IconsPlacedExtra(extra: IconsExtra(pid: 3, bundleID: "com.a", index: Int(x), frame: rect(x, width: width)),
                         section: .shown, distance: 0)
    }

    // MARK: Geometry

    func testNoNotchHasNoBoundary() {
        XCTAssertNil(IconsNotch.boundary(of: IconsScreen(frame: screen)))
        XCTAssertNil(IconsNotch.boundary(of: IconsScreen(frame: screen, safeAreaTop: 0, auxiliaryTopRightMinX: 952)))
        XCTAssertNil(IconsNotch.boundary(of: IconsScreen(frame: screen, safeAreaTop: .nan)))
    }

    func testANotchUsesTheTopRightArea() {
        XCTAssertEqual(IconsNotch.boundary(of: notched), 952)
    }

    func testANotchWithoutATopRightAreaFallsBackFromTheScreensLeftEdge() {
        XCTAssertEqual(IconsNotch.boundary(of: IconsScreen(frame: screen, safeAreaTop: 38)), 972)
        let moved = IconsScreen(frame: IconsRect(x: -1728, y: 0, width: 1728, height: 1117), safeAreaTop: 38)
        XCTAssertEqual(IconsNotch.boundary(of: moved), -756)
        let narrow = IconsScreen(frame: IconsRect(x: 0, y: 0, width: 800, height: 600), safeAreaTop: 38)
        XCTAssertEqual(IconsNotch.boundary(of: narrow), 800)
    }

    func testATopRightAreaOutsideTheScreenFallsBack() {
        XCTAssertEqual(IconsNotch.boundary(of: IconsScreen(frame: screen, safeAreaTop: 38,
                                                           auxiliaryTopRightMinX: 5000)), 972)
        XCTAssertEqual(IconsNotch.boundary(of: IconsScreen(frame: screen, safeAreaTop: 38,
                                                           auxiliaryTopRightMinX: .infinity)), 972)
    }

    // MARK: Classifier

    func testExtrasStartingLeftOfTheBoundaryAreBehindTheNotch() {
        let split = IconsNotch.split([row(1000), row(940), row(952), row(600)], screens: [notched])
        XCTAssertEqual(split.clear.map(\.extra.frame.x), [1000, 952])
        XCTAssertEqual(split.behindNotch.map(\.extra.frame.x), [940, 600])
    }

    func testZeroSizeExtrasAreDropped() {
        let split = IconsNotch.split([row(600, width: 0), row(1000, width: 0)], screens: [notched])
        XCTAssertEqual(split.clear, [])
        XCTAssertEqual(split.behindNotch, [])
    }

    func testEachExtraUsesItsOwnScreen() {
        // An external display has no notch, even where its x is past the built-in's boundary.
        let split = IconsNotch.split([row(1800), row(900)], screens: [external, notched])
        XCTAssertEqual(split.clear.map(\.extra.frame.x), [1800])
        XCTAssertEqual(split.behindNotch.map(\.extra.frame.x), [900])
    }

    func testAnExtraOnNoKnownScreenIsInTheClear() {
        let split = IconsNotch.split([row(900)], screens: [external])
        XCTAssertEqual(split.clear.map(\.extra.frame.x), [900])
        XCTAssertEqual(IconsNotch.split([row(900)], screens: []).behindNotch, [])
    }
}

final class IconsModelTests: XCTestCase {
    func testAutosaveNames() {
        XCTAssertEqual(IconsItemRole.allCases.map(\.autosaveName),
                       ["Snaptic.icons.toggle", "Snaptic.icons.separator", "Snaptic.icons.alwaysHidden"])
    }

    func testVisibilityRankOrdersTheSections() {
        XCTAssertEqual(IconsSection.allCases.map(\.visibilityRank), [0, 1, 2])
    }

    func testRectEdgesAndDegenerateFrames() {
        let r = IconsRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual([r.minX, r.midX, r.maxX, r.minY, r.midY, r.maxY], [10, 25, 40, 20, 40, 60])
        XCTAssertTrue(r.contains(x: 10, y: 20))
        XCTAssertFalse(r.contains(x: 40, y: 20))
        XCTAssertFalse(r.isDegenerate)
        XCTAssertTrue(IconsRect(x: 0, y: 0, width: 0, height: 4).isDegenerate)
        XCTAssertTrue(IconsRect(x: 0, y: 0, width: 4, height: -1).isDegenerate)
        XCTAssertTrue(IconsRect(x: .nan, y: 0, width: 4, height: 4).isDegenerate)
    }

    func testRectCodableRoundTrip() throws {
        let r = IconsRect(x: -1.5, y: 2, width: 24, height: 22)
        XCTAssertEqual(try JSONDecoder().decode(IconsRect.self, from: JSONEncoder().encode(r)), r)
    }
}
