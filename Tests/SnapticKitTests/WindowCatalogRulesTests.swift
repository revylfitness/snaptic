import XCTest
@testable import SnapticKit

// 0.5 K4 (§4.3, §4.8–§4.10, §4.23, §6.1): which windows are listed, privacy, order, badges, freshness and the capture
// path. The switcher's inclusion and filter cases moved here from `Switcher/WindowManager.swift` and
// `Switcher/SwitcherController.swift`.
//
// Resting on carried S0 rows: the S0-10 fixture (whether `SLSCopySpacesForWindows` really says "no Space" for those 24
// windows), Stage Manager (S0-11), the owner check without Screen Recording (S0-18), and the untitled other-Space and
// no-Screen-Recording legs (S0-23).

private let big = DockRect(x: 0, y: 0, width: 800, height: 600)

/// A window AX reports.
private func ax(_ id: UInt32, pid: Int32 = 10, hasTitle: Bool = true, minimized: Bool = false, hidden: Bool = false,
                onScreen: Bool = true, spaceKnown: Bool? = nil, fullscreen: Bool = false, layer: Int = 0,
                bounds: DockRect = big, kind: CatalogWindowKind = .standard) -> CatalogWindow {
    CatalogWindow(id: id, pid: pid, hasTitle: hasTitle, minimized: minimized, hidden: hidden, onScreen: onScreen,
                  spaceKnown: spaceKnown, fullscreen: fullscreen, layer: layer, bounds: bounds, kind: kind)
}

/// A window read only from `CGWindowList` (another Space, or something AX doesn't list).
private func listOnly(_ id: UInt32, pid: Int32 = 10, hasTitle: Bool = true, hidden: Bool = false,
                      onScreen: Bool = false, spaceKnown: Bool? = true, layer: Int = 0, bounds: DockRect = big,
                      alpha: Double = 1) -> CatalogWindow {
    CatalogWindow(id: id, pid: pid, hasTitle: hasTitle, hidden: hidden, onScreen: onScreen, spaceKnown: spaceKnown,
                  layer: layer, bounds: bounds, hasAXElement: false, kind: .unknown, alpha: alpha)
}

private func gate(_ client: ModuleID = .dockPreviews, screenRecording: Bool = true, thumbnailsLease: Bool = true,
                  ownerMatches: Bool = true, protectedApp: Bool = false, hiddenFromDock: Bool = false,
                  privatePath: Bool = true, hasLastSeen: Bool = true) -> CaptureGate {
    CaptureGate(client: client, screenRecording: screenRecording, thumbnailsLease: thumbnailsLease,
                ownerMatches: ownerMatches, protectedApp: protectedApp, hiddenFromDock: hiddenFromDock,
                privatePath: privatePath, hasLastSeen: hasLastSeen)
}

private func verdict(_ w: CatalogWindow, _ options: CatalogInclusion = .dock) -> CatalogVerdict {
    WindowCatalogRules.inclusion(w, appListed: true, options: options)
}

private func listed(_ w: CatalogWindow, _ options: CatalogInclusion = .dock) -> Bool { verdict(w, options).included }

private func leftOut(_ w: CatalogWindow, _ options: CatalogInclusion = .dock) -> CatalogLeftOut? {
    verdict(w, options).leftOut
}

private func kept(_ windows: [CatalogWindow], _ filter: CatalogFilter) -> [UInt32] {
    WindowCatalogRules.filter(windows, filter).map { windows[$0].id }
}

private let everything = CatalogFilter(otherSpaces: true, minimizedAndHidden: true, windowless: true)

final class WindowCatalogRulesTests: XCTestCase {
    // MARK: Inclusion (Y-3)

    func testMinimizedHiddenWindowlessAndFullScreenAreListedEitherWay() {
        for on in [false, true] {
            for options in [CatalogInclusion.dock, .switcher] {
                XCTAssertTrue(listed(ax(1, minimized: on, onScreen: !on), options), "minimized \(on)")
                XCTAssertTrue(listed(ax(1, hidden: on, onScreen: !on), options), "hidden \(on)")
                XCTAssertTrue(listed(ax(1, fullscreen: on), options), "full screen \(on)")
            }
        }
        let none = verdict(.windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false))
        XCTAssertTrue(none.included)
        XCTAssertFalse(none.appHasWindow, "a no-windows entry proves nothing")
    }

    func testTheSettingsTurnMinimizedHiddenAndWindowlessOnAndOff() {
        let windows: [CatalogWindow] = [ax(1), ax(2, minimized: true, onScreen: false),
                                        ax(3, hidden: true, onScreen: false),
                                        ax(4, fullscreen: true),
                                        .windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false)]
        var config = DockConfig()
        XCTAssertEqual(kept(windows, .dock(config, pid: 10)), [1, 2, 3, 4, CatalogWindow.firstSyntheticID])
        config.includeMinimizedAndHidden = false
        XCTAssertEqual(kept(windows, .dock(config, pid: 10)), [1, 4, CatalogWindow.firstSyntheticID])
        config.windowlessApps = false
        XCTAssertEqual(kept(windows, .dock(config, pid: 10)), [1, 4])
        config.includeMinimizedAndHidden = true
        XCTAssertEqual(kept(windows, .dock(config, pid: 10)), [1, 2, 3, 4])
    }

    func testDockFilterFromConfig() {
        var config = DockConfig()
        XCTAssertEqual(CatalogFilter.dock(config, pid: 7),
                       CatalogFilter(otherSpaces: true, spaces: .all, minimizedAndHidden: true, windowless: true,
                                     scope: .app(7)))
        config.otherSpaces = false
        config.includeMinimizedAndHidden = false
        config.windowlessApps = false
        XCTAssertEqual(CatalogFilter.dock(config, pid: 7),
                       CatalogFilter(otherSpaces: false, minimizedAndHidden: false, windowless: false, scope: .app(7)))
    }

    func testFloatingPanelsSystemDialogsAndPopUpsAreLeftOut() {
        XCTAssertEqual(CatalogWindowKind(subrole: "AXStandardWindow"), .standard)
        XCTAssertEqual(CatalogWindowKind(subrole: "AXDialog"), .dialog)
        XCTAssertEqual(CatalogWindowKind(subrole: "AXSystemDialog"), .systemDialog)
        XCTAssertEqual(CatalogWindowKind(subrole: "AXFloatingWindow"), .floating)
        XCTAssertEqual(CatalogWindowKind(subrole: "AXSystemFloatingWindow"), .floating)
        XCTAssertEqual(CatalogWindowKind(subrole: "AXNotification"), .other)
        XCTAssertEqual(CatalogWindowKind(subrole: nil), .unknown)
        for kind in [CatalogWindowKind.floating, .systemDialog, .other, .unknown] {
            XCTAssertEqual(leftOut(ax(1, kind: kind)), .kind, kind.rawValue)
            XCTAssertEqual(leftOut(ax(1, kind: kind), .switcher), .kind, kind.rawValue)
        }
        XCTAssertNil(leftOut(ax(1, kind: .standard)))
    }

    func testTheDockListsTitledDialogsOnly() {
        XCTAssertNil(leftOut(ax(1, hasTitle: true, kind: .dialog)))
        XCTAssertEqual(leftOut(ax(1, hasTitle: false, kind: .dialog)), .untitledDialog)
        XCTAssertNil(WindowCatalogRules.kindLeftOut(.dialog, hasTitle: nil, options: .dock), "title not read yet")
    }

    func testAnythingUnder100PointsIsLeftOutOfTheDock() {
        XCTAssertNil(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 100, height: 100))))
        XCTAssertEqual(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 99.5, height: 600))), .tooSmall)
        XCTAssertEqual(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 600, height: 99))), .tooSmall)
        XCTAssertEqual(leftOut(listOnly(1, bounds: DockRect(x: 0, y: 0, width: 99, height: 600))), .tooSmall)
        XCTAssertNil(leftOut(listOnly(1, bounds: DockRect(x: 0, y: 0, width: 100, height: 100))))
    }

    func testTheDesktopWindowAndGoneAppsAndIDsAreLeftOut() {
        // Finder's desktop window sits below the normal layer (`kCGDesktopWindowLevel`).
        XCTAssertEqual(leftOut(ax(1, layer: -2_147_483_623)), .desktop)
        XCTAssertEqual(leftOut(listOnly(1, layer: -2_147_483_623)), .desktop)
        XCTAssertEqual(WindowCatalogRules.inclusion(ax(1), appListed: false, options: .dock).leftOut, .appGone)
        XCTAssertEqual(leftOut(listOnly(CatalogWindow.firstSyntheticID)), .idGone)
        XCTAssertNil(leftOut(ax(CatalogWindow.firstSyntheticID)), "an AX window without a trusted id can still raise")
    }

    // MARK: Other Spaces (§2.6) and the Spaces filter (P-19, S0-10)

    func testOtherSpaceWindowsWithAndWithoutATitle() {
        let titled = listOnly(1, hasTitle: true), untitled = listOnly(2, hasTitle: false)
        XCTAssertTrue(titled.onOtherSpace)
        XCTAssertTrue(untitled.onOtherSpace)
        XCTAssertTrue(listed(titled))
        XCTAssertTrue(listed(titled, .switcher))
        XCTAssertTrue(listed(untitled), "the Dock lists it as \"Window on another Space\"")
        XCTAssertEqual(WindowCatalogRules.dockCardText(untitled, privacy: .none), .windowOnAnotherSpace)
        XCTAssertEqual(WindowCatalogRules.dockCardText(titled, privacy: .none), .title)
        XCTAssertEqual(verdict(untitled, .switcher), CatalogVerdict(leftOut: .untitled, appHasWindow: true),
                       "the switcher drops it, but its app gets no \"No windows\" entry")
    }

    func testSpacesUnknownDropsCGWindowListOnlyWindows() {
        for options in [CatalogInclusion.dock, .switcher] {
            XCTAssertEqual(verdict(listOnly(1, spaceKnown: nil), options),
                           CatalogVerdict(leftOut: .spacesUnknown, appHasWindow: true))
            XCTAssertEqual(verdict(listOnly(1, hasTitle: false, spaceKnown: nil), options).leftOut, .spacesUnknown)
            XCTAssertTrue(listed(ax(2, onScreen: false, spaceKnown: nil), options), "AX windows don't need the check")
        }
    }

    func testTheOtherSpaceRule() {
        XCTAssertTrue(ax(1, onScreen: false).onOtherSpace)
        XCTAssertFalse(ax(1, onScreen: true).onOtherSpace)
        XCTAssertFalse(ax(1, minimized: true, onScreen: false).onOtherSpace)
        XCTAssertFalse(ax(1, hidden: true, onScreen: false).onOtherSpace)
        XCTAssertTrue(listOnly(1, hidden: true).onOtherSpace, "a hidden app's other-Space window stays elsewhere")
        XCTAssertFalse(CatalogWindow.windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false).onOtherSpace)
        XCTAssertFalse(CatalogWindow(id: 1, pid: 10, onScreen: false, inStageStrip: true).onOtherSpace)
    }

    func testOtherSpaceIsKeptAsReadAfterARestoreInPlace() {
        var w = ax(1, minimized: true, onScreen: false)
        XCTAssertFalse(w.onOtherSpace)
        w.minimized = false
        XCTAssertFalse(w.onOtherSpace, "restoring a minimized window doesn't move it to another Space")
    }

    func testTheOtherSpacesSetting() {
        let windows = [ax(1), listOnly(2), ax(3, onScreen: false)]
        XCTAssertEqual(kept(windows, everything), [1, 2, 3])
        XCTAssertEqual(kept(windows, CatalogFilter(otherSpaces: false, minimizedAndHidden: true, windowless: true)), [1])
    }

    func testS0_10ListOnlyWindowsNeedTheSpacesFilter() {
        // S0-10: 24 layer-0 windows not on screen, not in AX, not minimized or hidden, from six apps, with no other
        // Space in existence; 20 untitled, one with alpha 0 (which one isn't recorded, so every position is tried).
        // Carried: that `SLSCopySpacesForWindows` really says "no Space" for them.
        func fixture(spaceKnown: Bool?, transparent: Int) -> [CatalogWindow] {
            (0..<24).map { i in
                listOnly(UInt32(100 + i), pid: Int32(500 + i % 6), hasTitle: i < 4, spaceKnown: spaceKnown,
                         alpha: i == transparent ? 0 : 1)
            }
        }
        func count(_ windows: [CatalogWindow], _ options: CatalogInclusion) -> Int {
            windows.filter { listed($0, options) }.count
        }
        for transparent in 0..<24 {
            XCTAssertTrue(fixture(spaceKnown: true, transparent: transparent).allSatisfy(\.onOtherSpace),
                          "the other-Space rule alone would list them all")
            for spaceKnown in [false, nil] as [Bool?] {
                let windows = fixture(spaceKnown: spaceKnown, transparent: transparent)
                XCTAssertEqual(count(windows, .dock), 0, "spaceKnown \(String(describing: spaceKnown))")
                XCTAssertEqual(count(windows, .switcher), 0, "spaceKnown \(String(describing: spaceKnown))")
            }
            let onSomeSpace = fixture(spaceKnown: true, transparent: transparent)
            XCTAssertEqual(count(onSomeSpace, .dock), 23)
            XCTAssertEqual(count(onSomeSpace, .switcher), transparent < 4 ? 3 : 4)
            for w in fixture(spaceKnown: nil, transparent: transparent) {
                XCTAssertEqual(WindowCatalogRules.needsSpaceCheck(w, appListed: true, options: .dock), w.alpha > 0)
            }
        }
    }

    // MARK: Native tabs

    func testNativeTabsAreFilteredButCountTheirApp() {
        XCTAssertEqual(verdict(ax(1, onScreen: false, spaceKnown: false)),
                       CatalogVerdict(leftOut: .nativeTab, appHasWindow: true))
        XCTAssertEqual(verdict(ax(1, onScreen: false, spaceKnown: false), .switcher).leftOut, .nativeTab)
        XCTAssertTrue(listed(ax(1, onScreen: false, spaceKnown: true)))
        XCTAssertTrue(listed(ax(1, minimized: true, onScreen: false, spaceKnown: false)))
        XCTAssertTrue(listed(ax(1, hidden: true, onScreen: false, spaceKnown: false)))
        XCTAssertEqual(verdict(listOnly(1, spaceKnown: false)), CatalogVerdict(leftOut: .nativeTab, appHasWindow: false))
    }

    func testTheSpacesCheckRunsOnlyWhereItDecides() {
        func needs(_ w: CatalogWindow, _ options: CatalogInclusion = .switcher) -> Bool {
            WindowCatalogRules.needsSpaceCheck(w, appListed: true, options: options)
        }
        XCTAssertFalse(needs(ax(1)))
        XCTAssertTrue(needs(ax(1, onScreen: false)))
        XCTAssertFalse(needs(ax(1, minimized: true, onScreen: false)))
        XCTAssertFalse(needs(ax(1, hidden: true, onScreen: false)))
        XCTAssertFalse(needs(ax(1, onScreen: false, kind: .floating)))
        XCTAssertTrue(needs(listOnly(1)))
        XCTAssertTrue(needs(listOnly(1, hasTitle: false)))
        XCTAssertTrue(needs(listOnly(1, hasTitle: false), .dock))
        XCTAssertFalse(needs(listOnly(1, onScreen: true)))
        XCTAssertFalse(needs(listOnly(1, layer: 3)))
        XCTAssertFalse(needs(listOnly(1, alpha: 0)))
        XCTAssertFalse(needs(listOnly(1, bounds: DockRect(x: 0, y: 0, width: 50, height: 50))))
        XCTAssertFalse(needs(.windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false)))
        XCTAssertFalse(WindowCatalogRules.needsSpaceCheck(listOnly(1), appListed: false, options: .switcher))
    }

    // MARK: Stage Manager (§4.8, Y-8; S0-11 carried)

    func testAStageStripWindowIsOnThisSpaceAndGetsItsOwnCapture() {
        let strip = CatalogWindow(id: 1, pid: 10, onScreen: false, spaceKnown: false, inStageStrip: true)
        XCTAssertFalse(strip.onOtherSpace)
        XCTAssertTrue(listed(strip), "not a native tab")
        XCTAssertTrue(listed(strip, .switcher))
        XCTAssertNil(WindowCatalogRules.dockBadge(strip, displayName: nil, displayCount: 1))
        XCTAssertEqual(WindowCatalogRules.capturePath(strip, gate: gate()), .privateCapture)
        XCTAssertEqual(WindowCatalogRules.capturePath(strip, gate: gate(privatePath: false)), .lastSeen)
        XCTAssertEqual(WindowCatalogRules.capturePath(strip, gate: gate(privatePath: false, hasLastSeen: false)), .icon)
        let shown = CatalogWindow(id: 2, pid: 10, onScreen: true, inStageStrip: true)
        XCTAssertEqual(WindowCatalogRules.capturePath(shown, gate: gate()), .screenCaptureKit)
    }

    // MARK: Privacy (§4.10)

    func testAProtectedApp() {
        let defaults = PIPPrivacy.defaultProtectedPrefixes
        func privacy(_ bundleID: String?, protect: Bool = true, windowless: Bool = false) -> CatalogPrivacy {
            WindowCatalogRules.privacy(bundleID: bundleID, hasTitle: true, hasPrivateMarker: false,
                                       windowless: windowless, protect: protect, protectedApps: defaults)
        }
        XCTAssertEqual(privacy("com.1password.1password"), .protectedApp)
        XCTAssertEqual(privacy("com.1password"), .protectedApp)
        XCTAssertEqual(privacy("com.1passwordx.app"), .none, "a prefix matches whole parts only")
        XCTAssertEqual(privacy("com.1password.1password", protect: false), .none)
        XCTAssertEqual(privacy("com.1password.1password", windowless: true), .none)
        XCTAssertEqual(privacy(nil), .none)
        XCTAssertTrue(WindowCatalogRules.isProtected(bundleID: "org.keepassxc.keepassxc", protect: true,
                                                     protectedApps: defaults))
        XCTAssertEqual(WindowCatalogRules.dockCardText(ax(1), privacy: .protectedApp), .appName)
        XCTAssertEqual(WindowCatalogRules.captureRefusal(ax(1), gate: gate(protectedApp: true)), .protectedApp)
        XCTAssertEqual(WindowCatalogRules.capturePath(ax(1), gate: gate(protectedApp: true)), .icon)
    }

    func testAPrivateMarker() {
        let marked = TextSanitizer.hasPrivateMarker("Example Domain — Private Browsing")
        XCTAssertTrue(marked)
        XCTAssertEqual(WindowCatalogRules.privacy(bundleID: "org.mozilla.firefox", hasTitle: true,
                                                  hasPrivateMarker: marked, windowless: false, protect: true,
                                                  protectedApps: []), .privateMarker)
        XCTAssertEqual(WindowCatalogRules.privacy(bundleID: "com.example.editor", hasTitle: true,
                                                  hasPrivateMarker: marked, windowless: false, protect: true,
                                                  protectedApps: []), .privateMarker, "any app's title")
        XCTAssertEqual(WindowCatalogRules.dockCardText(ax(1), privacy: .privateMarker), .privateWindow)
        var w = ax(1)
        w.isPrivate = true
        XCTAssertEqual(WindowCatalogRules.captureRefusal(w, gate: gate()), .privateWindow)
        XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: gate()), .icon, "never the last-seen thumbnail")
    }

    func testABrowserWithAnEmptyTitle() {
        func privacy(_ bundleID: String, hasTitle: Bool) -> CatalogPrivacy {
            WindowCatalogRules.privacy(bundleID: bundleID, hasTitle: hasTitle, hasPrivateMarker: false,
                                       windowless: false, protect: true, protectedApps: [])
        }
        XCTAssertEqual(privacy("com.google.Chrome", hasTitle: false), .untitledBrowser)
        XCTAssertEqual(privacy("com.google.Chrome.canary", hasTitle: false), .untitledBrowser)
        XCTAssertEqual(privacy("com.google.Chrome", hasTitle: true), .none)
        XCTAssertEqual(privacy("com.example.editor", hasTitle: false), .none)
        XCTAssertEqual(WindowCatalogRules.dockCardText(ax(1, hasTitle: false), privacy: .untitledBrowser),
                       .privateWindow)
    }

    func testThePrivacyRuleAgreesWithPIPs() {
        let cases: [(title: String, bundleID: String)] = [
            ("Example — Private Browsing", "org.mozilla.firefox"), ("", "com.apple.Safari"), ("Docs", "com.apple.Safari"),
            ("", "com.example.editor"), ("Notes", "com.example.editor"), ("New Incognito Tab", "com.example.editor"),
        ]
        for c in cases {
            let rule = WindowCatalogRules.privacy(bundleID: c.bundleID, hasTitle: !c.title.isEmpty,
                                                  hasPrivateMarker: TextSanitizer.hasPrivateMarker(c.title),
                                                  windowless: false, protect: true, protectedApps: [])
            XCTAssertEqual(rule.isPrivate, PIPPrivacy.isPrivateWindow(title: c.title, bundleID: c.bundleID), c.bundleID)
        }
    }

    // MARK: Apps hidden from Dock previews (D2-24, G3-3)

    func testAnAppHiddenFromDockPreviewsYieldsNoPanelAndTheSwitcherStillListsAndCapturesIt() {
        let hidden = ["com.example.secret"]
        XCTAssertFalse(WindowCatalogRules.yieldsPanel(bundleID: "com.example.secret", hiddenBundleIDs: hidden))
        XCTAssertTrue(WindowCatalogRules.yieldsPanel(bundleID: "com.example.secret.helper", hiddenBundleIDs: hidden),
                      "exact ids only")
        XCTAssertTrue(WindowCatalogRules.yieldsPanel(bundleID: "com.example.other", hiddenBundleIDs: hidden))
        XCTAssertTrue(WindowCatalogRules.yieldsPanel(bundleID: nil, hiddenBundleIDs: hidden))
        XCTAssertTrue(WindowCatalogRules.yieldsPanel(bundleID: "", hiddenBundleIDs: [""]))

        // The switcher's list doesn't read the hidden list.
        XCTAssertTrue(WindowCatalogRules.listsApp(regular: true, isOwnProcess: false, bundleID: "com.example.secret",
                                                  excluded: []))
        XCTAssertTrue(listed(ax(1), .switcher))
        let w = ax(1)
        XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: gate(.windowSwitcher, hiddenFromDock: true)),
                       .screenCaptureKit)
        XCTAssertEqual(WindowCatalogRules.captureRefusal(w, gate: gate(.dockPreviews, hiddenFromDock: true)),
                       .hiddenFromDock)
        XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: gate(.dockPreviews, hiddenFromDock: true)), .icon)
    }

    // MARK: Order (§2.3, §4.18)

    /// A, B, C (minimized), D, F, then a "no windows" entry, in AX order.
    private let ordered: [CatalogWindow] = [
        ax(1), ax(2), ax(3, minimized: true, onScreen: false), ax(4), ax(6),
        .windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false),
    ]

    func testTheRecencyMergeWithRecency() {
        XCTAssertEqual(WindowCatalogRules.recencyOrder(ordered, recency: [4, 2, 4, 99], zOrder: [1: 0]),
                       [3, 1, 0, 2, 4, 5])
        XCTAssertEqual(WindowCatalogRules.dockOrder(ordered, titles: Array(repeating: "", count: 6),
                                                    sort: .recentlyUsed, recency: [4, 2], zOrder: [1: 0]),
                       [3, 1, 0, 2, 4, 5])
    }

    func testTheRecencyMergeWithoutRecency() {
        // No `.recency` lease: stacking order, then minimized windows, then the rest, all in AX order.
        XCTAssertEqual(WindowCatalogRules.recencyOrder(ordered, recency: nil, zOrder: [4: 0, 1: 1]),
                       [3, 0, 2, 1, 4, 5])
        XCTAssertEqual(WindowCatalogRules.recencyOrder(ordered, recency: nil, zOrder: [:]), [2, 0, 1, 3, 4, 5])
    }

    func testTheTitleSortIgnoresCaseAndDiacriticsAndTiesKeepRecency() {
        let windows = [ax(1), ax(2), ax(3), ax(4)]
        let titles = ["zeta", "école", "Ecole", "Alpha"]
        XCTAssertEqual(WindowCatalogRules.dockOrder(windows, titles: titles, sort: .title, recency: [3, 2], zOrder: [:]),
                       [3, 2, 1, 0])
        XCTAssertEqual(WindowCatalogRules.dockOrder(windows, titles: titles, sort: .title, recency: nil, zOrder: [:]),
                       [3, 1, 2, 0])
    }

    func testMinimizedAndHiddenLast() {
        let windows = [ax(1, minimized: true, onScreen: false), ax(2), ax(3, hidden: true, onScreen: false), ax(4)]
        XCTAssertEqual(WindowCatalogRules.minimizedAndHiddenLast(windows, order: [0, 1, 2, 3]), [1, 3, 0, 2])
        // Recency puts 3 (hidden) and 1 (minimized) first; they still go last, in that order.
        XCTAssertEqual(WindowCatalogRules.dockOrder(windows, titles: ["", "", "", ""], sort: .minimizedAndHiddenLast,
                                                    recency: [3, 1], zOrder: [:]),
                       [1, 3, 2, 0])
    }

    // MARK: Badges (§4.3, §4.23)

    func testTheDockBadgeOrder() {
        func badge(_ w: CatalogWindow, _ name: String? = "Studio Display", _ displays: Int = 2) -> CatalogBadge? {
            WindowCatalogRules.dockBadge(w, displayName: name, displayCount: displays)
        }
        var all = ax(1, minimized: true, onScreen: false, fullscreen: true)
        all.onOtherSpace = true
        XCTAssertEqual(badge(all), .minimized)
        all.minimized = false
        XCTAssertEqual(badge(all), .fullScreen)
        all.fullscreen = false
        XCTAssertEqual(badge(all), .otherSpace)
        XCTAssertEqual(badge(ax(1)), .display("Studio Display"))
        XCTAssertNil(badge(ax(1), "Studio Display", 1), "the display name shows only with more than one display")
        XCTAssertNil(badge(ax(1), "", 2))
        XCTAssertNil(badge(ax(1), nil, 2))
    }

    func testHiddenIsNeverACardBadge() {
        let hidden = ax(1, hidden: true, onScreen: false)
        XCTAssertNil(WindowCatalogRules.dockBadge(hidden, displayName: "Built-in", displayCount: 1))
        XCTAssertEqual(WindowCatalogRules.dockBadge(hidden, displayName: "Built-in", displayCount: 2), .display("Built-in"))
        XCTAssertNil(WindowCatalogRules.dockBadge(.windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: true),
                                                  displayName: "Built-in", displayCount: 2))
    }

    func testTheSwitcherKeepsItsBadgeOrder() {
        XCTAssertEqual(WindowCatalogRules.switcherBadge(.windowless(id: CatalogWindow.firstSyntheticID, pid: 10,
                                                                    hidden: true), groupedCount: 1), .noWindows)
        var w = ax(1, minimized: true, hidden: true, onScreen: false, fullscreen: true)
        w.onOtherSpace = true
        XCTAssertEqual(WindowCatalogRules.switcherBadge(w, groupedCount: 3), .windows(3))
        XCTAssertEqual(WindowCatalogRules.switcherBadge(w, groupedCount: 1), .minimized)
        w.minimized = false
        XCTAssertEqual(WindowCatalogRules.switcherBadge(w, groupedCount: 1), .hidden)
        w.hidden = false
        XCTAssertEqual(WindowCatalogRules.switcherBadge(w, groupedCount: 1), .otherSpace)
        w.onOtherSpace = false
        XCTAssertEqual(WindowCatalogRules.switcherBadge(w, groupedCount: 1), .fullScreen)
        XCTAssertNil(WindowCatalogRules.switcherBadge(ax(1), groupedCount: 1))
    }

    // MARK: Freshness (§4.9)

    func testFreshnessAt29Point9And30Seconds() {
        XCTAssertTrue(WindowCatalogRules.isFresh(capturedAt: 100, now: 129.9))
        XCTAssertFalse(WindowCatalogRules.isFresh(capturedAt: 100, now: 130))
        XCTAssertTrue(WindowCatalogRules.isFresh(capturedAt: 100, now: 100))
        XCTAssertFalse(WindowCatalogRules.isFresh(capturedAt: 100, now: 99), "a capture from the future isn't fresh")
    }

    // MARK: Capture path (§4.9)

    func testTheCapturePathChoice() {
        let onScreen = ax(1), minimized = ax(2, minimized: true, onScreen: false), elsewhere = listOnly(3)
        XCTAssertEqual(WindowCatalogRules.capturePath(onScreen, gate: gate()), .screenCaptureKit)
        XCTAssertEqual(WindowCatalogRules.capturePath(onScreen, gate: gate(privatePath: false, hasLastSeen: false)),
                       .screenCaptureKit)
        for w in [minimized, elsewhere, ax(4, onScreen: false)] {
            XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: gate()), .privateCapture)
            XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: gate(privatePath: false)), .lastSeen)
            XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: gate(privatePath: false, hasLastSeen: false)), .icon)
        }
        let hidden = ax(5, hidden: true, onScreen: false)
        XCTAssertEqual(WindowCatalogRules.capturePath(hidden, gate: gate()), .lastSeen, "never the private path")
        XCTAssertEqual(WindowCatalogRules.capturePath(hidden, gate: gate(hasLastSeen: false)), .icon)
    }

    func testCaptureRefusalsInOrder() {
        func refusal(_ w: CatalogWindow, _ g: CaptureGate) -> CaptureRefusal? {
            WindowCatalogRules.captureRefusal(w, gate: g)
        }
        XCTAssertNil(refusal(ax(1), gate()))
        XCTAssertEqual(refusal(.windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false), gate()),
                       .windowless)
        XCTAssertEqual(refusal(ax(CatalogWindow.firstSyntheticID), gate()), .noWindowID)
        XCTAssertEqual(refusal(ax(1), gate(screenRecording: false, thumbnailsLease: false)), .noThumbnailsLease)
        XCTAssertEqual(refusal(ax(1), gate(protectedApp: true, hiddenFromDock: true)), .protectedApp)
        XCTAssertEqual(refusal(ax(1), gate(ownerMatches: false, hiddenFromDock: true)), .hiddenFromDock)
        // S0-18 (carried): the owner check, and no Screen Recording.
        XCTAssertEqual(refusal(ax(1), gate(screenRecording: false, ownerMatches: false)), .ownerMismatch)
        XCTAssertEqual(refusal(ax(1), gate(screenRecording: false)), .noScreenRecording)
        XCTAssertEqual(WindowCatalogRules.capturePath(ax(1), gate: gate(ownerMatches: false)), .icon)
        XCTAssertEqual(WindowCatalogRules.capturePath(listOnly(2), gate: gate(screenRecording: false)), .lastSeen,
                       "no Screen Recording keeps the last-seen thumbnail")
        XCTAssertEqual(WindowCatalogRules.capturePath(ax(1), gate: gate(screenRecording: false, hasLastSeen: false)),
                       .icon)
    }

    // MARK: Actions (§4.4)

    func testNoAXElementMeansRaiseOnly() {
        XCTAssertEqual(WindowCatalogRules.cardActions(listOnly(1)), [.raise])
        XCTAssertEqual(WindowCatalogRules.cardActions(ax(1)), [.raise, .close, .minimize, .fullScreen])
        XCTAssertEqual(WindowCatalogRules.cardActions(.windowless(id: CatalogWindow.firstSyntheticID, pid: 10,
                                                                  hidden: false)), [.raise])
    }

    // MARK: The switcher's cases, moved from the app (§4.23)

    func testTheSwitcherKeepsItsAXThresholdAndUntitledDialogs() {
        XCTAssertEqual(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 39, height: 500)), .switcher), .tooSmall)
        XCTAssertEqual(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 500, height: 39)), .switcher), .tooSmall)
        XCTAssertNil(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 40, height: 40)), .switcher))
        XCTAssertEqual(leftOut(ax(1, bounds: DockRect(x: 0, y: 0, width: 40, height: 40))), .tooSmall, "the Dock uses 100")
        XCTAssertNil(leftOut(ax(1, hasTitle: false, kind: .dialog), .switcher))
        XCTAssertNil(WindowCatalogRules.sizeLeftOut(width: 40, height: 40, minimum: CatalogInclusion.switcher.minAXSide))
    }

    func testTheSwitchersCGWindowListOnlyRules() {
        XCTAssertEqual(verdict(listOnly(1, layer: 3), .switcher), CatalogVerdict(leftOut: .notNormalLayer, appHasWindow: false))
        XCTAssertEqual(verdict(listOnly(1, onScreen: true), .switcher), CatalogVerdict(leftOut: .onScreen, appHasWindow: false))
        XCTAssertEqual(verdict(listOnly(1, bounds: DockRect(x: 0, y: 0, width: 99, height: 600)), .switcher).leftOut, .tooSmall)
        XCTAssertNil(leftOut(listOnly(1, bounds: DockRect(x: 0, y: 0, width: 100, height: 100)), .switcher))
        XCTAssertEqual(verdict(listOnly(1, alpha: 0), .switcher), CatalogVerdict(leftOut: .transparent, appHasWindow: false))
        XCTAssertEqual(verdict(listOnly(1, hasTitle: false), .switcher), CatalogVerdict(leftOut: .untitled, appHasWindow: true))
        XCTAssertEqual(verdict(listOnly(1), .switcher), CatalogVerdict(leftOut: nil, appHasWindow: true))
    }

    func testATrustedWindowIDIsOneTheWindowServerAgreesOn() {
        let owners: [UInt32: Int32] = [7: 10, 8: 11]
        XCTAssertEqual(WindowCatalogRules.trustedWindowID(claimed: 7, pid: 10, owners: owners), 7)
        XCTAssertNil(WindowCatalogRules.trustedWindowID(claimed: 8, pid: 10, owners: owners), "another app's window")
        XCTAssertNil(WindowCatalogRules.trustedWindowID(claimed: 9, pid: 10, owners: owners))
        XCTAssertNil(WindowCatalogRules.trustedWindowID(claimed: nil, pid: 10, owners: owners))
    }

    func testWithoutTheAXWindowIDAWindowIsMatchedByTitleAndFrame() {
        let frame = DockRect(x: 100, y: 50, width: 800, height: 600)
        func candidate(_ id: UInt32, _ title: String? = "Notes", x: Double = 100, width: Double = 800,
                       layer: Int = 0) -> WindowFrameCandidate {
            WindowFrameCandidate(id: id, title: title, frame: DockRect(x: x, y: 50, width: width, height: 600),
                                 layer: layer)
        }
        func match(_ candidates: [WindowFrameCandidate], title: String = "Notes",
                   taken: Set<UInt32> = []) -> UInt32? {
            WindowCatalogRules.matchByTitleAndFrame(title: title, frame: frame, candidates: candidates, taken: taken)
        }
        XCTAssertEqual(match([candidate(7), candidate(8, x: 140)]), 7)
        XCTAssertEqual(match([candidate(7, x: 100.6, width: 799.5)]), 7, "within a point")
        XCTAssertNil(match([candidate(7, x: 102)]), "more than a point off")
        XCTAssertNil(match([candidate(7, "Other")]), "a title the window server reports must match")
        XCTAssertEqual(match([candidate(7, nil)]), 7, "no title without Screen Recording: the frame decides")
        XCTAssertEqual(match([candidate(7, "")]), 7)
        XCTAssertEqual(match([candidate(7)], title: ""), 7, "an AX title not read in time: the frame decides")
        XCTAssertEqual(match([candidate(7, "Other"), candidate(8)]), 8, "the title tells two same-frame windows apart")
        XCTAssertNil(match([candidate(7, nil), candidate(8, nil)]), "two possible windows: none, never a guess")
        XCTAssertNil(match([candidate(7)], taken: [7]), "another AX window already has it")
        XCTAssertEqual(match([candidate(7), candidate(8)], taken: [7]), 8)
        XCTAssertNil(match([candidate(7, layer: 3)]), "only layer 0")
        XCTAssertNil(match([candidate(CatalogWindow.firstSyntheticID)]), "never a synthetic id")
        XCTAssertNil(match([]))
    }

    func testWhichAppsTheSwitcherLists() {
        func lists(regular: Bool = true, own: Bool = false, _ bundleID: String?, _ excluded: [String] = []) -> Bool {
            WindowCatalogRules.listsApp(regular: regular, isOwnProcess: own, bundleID: bundleID, excluded: excluded)
        }
        XCTAssertTrue(lists("com.example.app"))
        XCTAssertFalse(lists(regular: false, "com.example.app"))
        XCTAssertFalse(lists(own: true, "com.example.app"))
        XCTAssertFalse(lists("com.example.app", ["com.example"]))
        XCTAssertFalse(lists("com.example.app", ["com.example.app"]))
        XCTAssertTrue(lists("com.examples.app", ["com.example"]))
        XCTAssertTrue(lists(nil, ["com.example"]))
        XCTAssertTrue(lists("", [""]), "an empty id matches nothing")
    }

    func testTheActiveAppScope() {
        let windows: [CatalogWindow] = [ax(1, pid: 10), ax(2, pid: 11),
                                        .windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false)]
        func scoped(_ pid: Int32?) -> [UInt32] {
            kept(windows, CatalogFilter(otherSpaces: true, minimizedAndHidden: true, windowless: true, scope: .app(pid)))
        }
        XCTAssertEqual(scoped(10), [1, CatalogWindow.firstSyntheticID])
        XCTAssertEqual(scoped(11), [2])
        XCTAssertEqual(scoped(nil), [], "no front app keeps nothing")
    }

    func testTheCurrentScreenScopeUsesEachWindowsCentre() {
        let screen = DockRect(x: 0, y: 0, width: 1000, height: 800)
        let windows: [CatalogWindow] = [
            ax(1, bounds: DockRect(x: -100, y: 0, width: 400, height: 300)),  // centre (100, 150)
            ax(2, bounds: DockRect(x: 900, y: 0, width: 400, height: 300)),   // centre (1100, 150)
            ax(3, bounds: DockRect(x: 800, y: 0, width: 400, height: 300)),   // centre (1000, 150): the far edge is outside
            .windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false),
        ]
        func scoped(_ frame: DockRect?) -> [UInt32] {
            kept(windows, CatalogFilter(otherSpaces: true, minimizedAndHidden: true, windowless: true,
                                        scope: .screen(frame)))
        }
        XCTAssertEqual(scoped(screen), [1, CatalogWindow.firstSyntheticID])
        XCTAssertEqual(scoped(nil), [1, 2, 3, CatalogWindow.firstSyntheticID])
        XCTAssertTrue(screen.contains(x: 0, y: 0))
        XCTAssertFalse(screen.contains(x: 1000, y: 0))
        XCTAssertFalse(DockRect.zero.contains(x: 0, y: 0))
    }

    func testTheSpacesChoice() {
        let windows: [CatalogWindow] = [ax(1), listOnly(2), ax(3, minimized: true, onScreen: false),
                                        .windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false)]
        func spaces(_ s: CatalogSpaces) -> [UInt32] {
            kept(windows, CatalogFilter(otherSpaces: true, spaces: s, minimizedAndHidden: true, windowless: true))
        }
        XCTAssertEqual(spaces(.all), [1, 2, 3, CatalogWindow.firstSyntheticID])
        XCTAssertEqual(spaces(.current), [1, 3, CatalogWindow.firstSyntheticID])
        XCTAssertEqual(spaces(.others), [2, CatalogWindow.firstSyntheticID])
    }

    func testLeavingOutMinimizedAndHiddenDropsAHiddenAppsNoWindowsEntry() {
        let windows: [CatalogWindow] = [.windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: true),
                                        .windowless(id: CatalogWindow.firstSyntheticID + 1, pid: 11, hidden: false)]
        XCTAssertEqual(kept(windows, CatalogFilter(otherSpaces: true, minimizedAndHidden: false, windowless: true)),
                       [CatalogWindow.firstSyntheticID + 1])
    }

    func testOneWindowPerApp() {
        let windows: [CatalogWindow] = [ax(1, pid: 10), ax(2, pid: 11), ax(3, pid: 10),
                                        .windowless(id: CatalogWindow.firstSyntheticID, pid: 12, hidden: false), ax(4, pid: 10)]
        let grouped = WindowCatalogRules.groupedByApp(windows)
        XCTAssertEqual(grouped.map(\.index), [0, 1, 3])
        XCTAssertEqual(grouped.map(\.count), [3, 1, 1])
        XCTAssertTrue(WindowCatalogRules.groupedByApp([]).isEmpty)
    }

    func testTheSwitcherOrder() {
        let windows: [CatalogWindow] = [ax(1), ax(2), ax(3), ax(4), ax(5),
                                        .windowless(id: CatalogWindow.firstSyntheticID, pid: 10, hidden: false), ax(6), ax(7)]
        let names: [(app: String, title: String)] = [
            ("Mail", "Inbox"), ("Notes", "b"), ("Notes", "a"), ("Mail", "Draft"), ("Safari", "x"), ("Aaa", ""),
            ("Notes", "a"), ("Mail", "Inbox"),
        ]
        // Focused 4; recently used 2, then 1; stacking 5 then 3; 6 and 7 never seen, so by app name: Mail before Notes.
        let order = WindowCatalogRules.switcherOrder(windows, names: names, focusedID: 4, mru: [4, 2, 1, 2],
                                                     zOrder: [5: 0, 3: 1])
        XCTAssertEqual(order.map { windows[$0].id }, [4, 2, 1, 5, 3, 7, 6, CatalogWindow.firstSyntheticID])
        let unfocused = WindowCatalogRules.switcherOrder([ax(1), ax(2), ax(3)],
                                                         names: [("B", "x"), ("A", "y"), ("A", "x")],
                                                         focusedID: nil, mru: [], zOrder: [:])
        XCTAssertEqual(unfocused, [2, 1, 0])
        XCTAssertEqual(WindowCatalogRules.switcherOrder([ax(1), ax(2)], names: [("A", "x"), ("A", "x")],
                                                        focusedID: nil, mru: [], zOrder: [:]), [0, 1],
                       "then by position, so the order is stable")
    }

    func testTheSwitchersCapturePermissionMatchesItsOldRule() {
        // 0.4's `isCapturable`: a real id, not minimized, hidden, elsewhere, windowless or private.
        for bits in 0..<64 {
            func bit(_ n: Int) -> Bool { bits & (1 << n) != 0 }
            var w = ax(bit(0) ? 1 : CatalogWindow.firstSyntheticID)
            w.minimized = bit(1)
            w.hidden = bit(2)
            w.onOtherSpace = bit(3)
            w.windowless = bit(4)
            w.isPrivate = bit(5)
            let old = w.hasRealID && !w.minimized && !w.hidden && !w.onOtherSpace && !w.windowless && !w.isPrivate
            XCTAssertEqual(WindowCatalogRules.capturePath(w, gate: .switcherList) == .screenCaptureKit, old, "\(bits)")
        }
    }

    func testANoWindowsEntry() {
        let w = CatalogWindow.windowless(id: CatalogWindow.firstSyntheticID + 3, pid: 10, hidden: true)
        XCTAssertTrue(w.windowless)
        XCTAssertTrue(w.hidden)
        XCTAssertFalse(w.hasTitle)
        XCTAssertFalse(w.hasAXElement)
        XCTAssertFalse(w.hasRealID)
        XCTAssertFalse(w.onOtherSpace)
        XCTAssertEqual(w.bounds, .zero)
        XCTAssertTrue(ax(CatalogWindow.firstSyntheticID - 1).hasRealID)
    }
}
