import XCTest
@testable import SnapticKit

// 0.4 A6 (§4.8): the hidden list's rows, titles, slot, press needs and match.

private let screen = IconsRect(x: 0, y: 0, width: 1728, height: 1117)
private let flat = IconsScreen(frame: screen)
/// A notched built-in display: x < 760 is behind the notch.
private let notched = IconsScreen(frame: screen, safeAreaTop: 32, auxiliaryTopRightMinX: 760)

private func rect(_ x: Double, width: Double = 24) -> IconsRect {
    IconsRect(x: x, y: 1093, width: width, height: 24)
}

private func extra(_ pid: Int32, _ index: Int, _ x: Double, bundle: String? = nil, title: String? = nil,
                   width: Double = 24) -> IconsExtra {
    IconsExtra(pid: pid, bundleID: bundle ?? "app.\(pid)", index: index, frame: rect(x, width: width), title: title)
}

private func placed(_ e: IconsExtra, _ section: IconsSection, line: Double = 1300) -> IconsPlacedExtra {
    IconsPlacedExtra(extra: e, section: section, distance: abs(e.frame.midX - line))
}

private func layout(_ extras: [IconsPlacedExtra], offScreen: [IconsExtra] = [],
                    sections: [String: IconsSection]? = nil) -> IconsLayout {
    var s: [String: IconsSection] = sections ?? [:]
    if sections == nil {
        for p in extras { s[p.extra.bundleID ?? ""] = p.section }
    }
    return IconsLayout(sections: s, systemBundles: [], carried: [], extras: extras, offScreen: offScreen,
                       scope: .unrestricted, readAt: 1)
}

private let names: [Int32: String] = [10: "Docker", 11: "iStat Menus", 12: "Dropbox", 13: "Clock"]

final class IconsHiddenListTests: XCTestCase {
    // MARK: Rows

    func testHiddenRowsAreNearestTheBoundaryFirstAndIncludeAlwaysHidden() {
        let l = layout([placed(extra(10, 0, 900), .alwaysHidden), placed(extra(11, 0, 1200), .hidden),
                        placed(extra(13, 0, 1400), .shown)])
        let list = IconsHiddenListRules.list(l, names: names, screens: [flat], rightToLeft: false)
        XCTAssertEqual(list.hidden.map(\.title), ["iStat Menus", "Docker"])
        XCTAssertEqual(list.hidden.map(\.section), [.hidden, .alwaysHidden])
        XCTAssertEqual(list.shown.map(\.title), ["Clock"])
        XCTAssertTrue(list.behindNotch.isEmpty)
        XCTAssertFalse(list.isEmpty)
    }

    func testSeveralExtrasUseTheAXTitleOrIconN() {
        let l = layout([placed(extra(11, 0, 1200, title: "CPU"), .hidden), placed(extra(11, 1, 1170), .hidden),
                        placed(extra(10, 0, 1100), .hidden)])
        let list = IconsHiddenListRules.list(l, names: names, screens: [flat], rightToLeft: false)
        XCTAssertEqual(list.hidden.map(\.title), ["iStat Menus — CPU", "iStat Menus — Icon 2", "Docker"])
    }

    func testTitleFallbacks() {
        let e = extra(10, 2, 0, title: "  Docker ")
        XCTAssertEqual(IconsHiddenListRules.title(e, appName: nil, several: false), "App")
        XCTAssertEqual(IconsHiddenListRules.title(e, appName: "", several: false), "App")
        // A title that only repeats the app's name says nothing.
        XCTAssertEqual(IconsHiddenListRules.title(e, appName: "Docker", several: true), "Docker — Icon 3")
    }

    func testZeroSizeExtrasAreDropped() {
        let l = layout([placed(extra(10, 0, 1200, width: 0), .hidden), placed(extra(11, 0, 1100), .hidden)])
        let list = IconsHiddenListRules.list(l, names: names, screens: [flat], rightToLeft: false)
        XCTAssertEqual(list.hidden.map(\.title), ["iStat Menus"])
    }

    func testShownIconsBehindANotchGetTheirOwnHeader() {
        let l = layout([placed(extra(12, 0, 700), .shown), placed(extra(13, 0, 1400), .shown)])
        let list = IconsHiddenListRules.list(l, names: names, screens: [notched], rightToLeft: false)
        XCTAssertEqual(list.behindNotch.map(\.title), ["Dropbox"])
        XCTAssertEqual(list.shown.map(\.title), ["Clock"])
        XCTAssertFalse(list.isEmpty)
        // Without a notch the same icon is simply shown.
        let plain = IconsHiddenListRules.list(l, names: names, screens: [flat], rightToLeft: false)
        XCTAssertTrue(plain.behindNotch.isEmpty)
        XCTAssertTrue(plain.isEmpty)
    }

    func testLengthPushedExtrasAreListedUnderTheirSectionInBarOrder() {
        // Collapsed on Length: a fresh read finds the hidden icons off the screen's left edge.
        let l = layout([placed(extra(13, 0, 1400), .shown)],
                       offScreen: [extra(10, 0, -9100), extra(11, 0, -9000), extra(13, 1, -8000)],
                       sections: ["app.10": .alwaysHidden, "app.11": .hidden, "app.13": .shown])
        let list = IconsHiddenListRules.list(l, names: names, screens: [flat], rightToLeft: false)
        XCTAssertEqual(list.hidden.map(\.title), ["iStat Menus", "Docker"])
        XCTAssertEqual(list.hidden.map(\.frameKnown), [false, false])
        XCTAssertEqual(list.hidden.map(\.section), [.hidden, .alwaysHidden])
        // Clock's off-screen sibling counts toward "several", but a shown app's pushed extra isn't listed.
        XCTAssertEqual(list.shown.map(\.title), ["Clock — Icon 1"])
    }

    func testPushedExtrasInRTLAreNearestFirstFromTheOtherSide() {
        let l = layout([], offScreen: [extra(10, 0, 9100), extra(11, 0, 9000)],
                       sections: ["app.10": .hidden, "app.11": .hidden])
        let list = IconsHiddenListRules.list(l, names: names, screens: [flat], rightToLeft: true)
        XCTAssertEqual(list.hidden.map(\.title), ["iStat Menus", "Docker"])
    }

    func testNoLayoutIsAnEmptyList() {
        XCTAssertEqual(IconsHiddenListRules.list(nil, names: names, screens: [flat], rightToLeft: false),
                       IconsHiddenList())
    }

    // MARK: Slot

    private func content(_ f: IconsListFacts) -> IconsListContent {
        IconsHiddenListRules.content(f) { IconsHiddenList() }
    }

    func testSlotPrefersReasonsThenPermissionThenRows() {
        let hider = KnownMenuBarHiders.all[0]
        XCTAssertEqual(content(IconsListFacts(engine: .length, state: .collapsed, access: .notGranted,
                                              pausedFor: hider)),
                       .reason("Paused while Hidden Bar runs"))
        XCTAssertEqual(content(IconsListFacts(engine: .native, state: .collapsed, access: .granted, examPaused: true)),
                       .reason("Paused during an exam session"))
        XCTAssertEqual(content(IconsListFacts(engine: nil, state: .unavailable(.identity), access: .granted)),
                       .reason("Move Snaptic to Applications to hide icons."))
        XCTAssertEqual(content(IconsListFacts(engine: .length, state: .collapsed, access: .notGranted)),
                       .allowAccessibility)
        XCTAssertEqual(content(IconsListFacts(engine: .native, state: .collapsed, access: .revoked)),
                       .needsPermission)
        XCTAssertEqual(content(IconsListFacts(engine: .length, state: .collapsed, access: .granted,
                                              inventoryOff: true)), .none)
        XCTAssertEqual(content(IconsListFacts(engine: .native, state: .collapsed, access: .granted)),
                       .rows(IconsHiddenList()))
        XCTAssertEqual(content(IconsListFacts(engine: nil, state: .unavailable(.stopped), access: .granted)), .none)
    }

    func testEveryUnavailableReasonButStoppedHasText() {
        for reason in IconsUnavailableReason.allCases {
            XCTAssertEqual(IconsHiddenListRules.unavailableText(reason) == nil, reason == .stopped, "\(reason)")
        }
    }

    // MARK: Press

    func testExpandNeededBySection() {
        typealias R = IconsHiddenListRules
        XCTAssertNil(R.expand(for: .shown, state: .collapsed))
        XCTAssertEqual(R.expand(for: .hidden, state: .collapsed), .plain)
        XCTAssertEqual(R.expand(for: .hidden, state: .calibrating), .plain)
        XCTAssertNil(R.expand(for: .hidden, state: .expanded(.plain)))
        XCTAssertEqual(R.expand(for: .alwaysHidden, state: .expanded(.plain)), .all)
        XCTAssertEqual(R.expand(for: .alwaysHidden, state: .collapsed), .all)
        XCTAssertNil(R.expand(for: .alwaysHidden, state: .expanded(.all)))
    }

    func testReadyMeansInTheArrowsScreen() {
        XCTAssertTrue(IconsHiddenListRules.ready(rect(1200), screen: screen))
        XCTAssertFalse(IconsHiddenListRules.ready(rect(-9000), screen: screen))
        XCTAssertFalse(IconsHiddenListRules.ready(rect(1200, width: 0), screen: screen))
        XCTAssertFalse(IconsHiddenListRules.ready(nil, screen: screen))
    }

    func testMatchWithinFourPoints() {
        let row = IconsListRow(extra: extra(10, 0, 1200), section: .hidden, title: "Docker", frameKnown: true)
        XCTAssertTrue(IconsHiddenListRules.matches(row, actual: rect(1204)))
        XCTAssertFalse(IconsHiddenListRules.matches(row, actual: rect(1205)))
        XCTAssertFalse(IconsHiddenListRules.matches(row, actual: rect(1200, width: 30)))
        // A frame read off the screen matches by size only.
        var pushed = row
        pushed.frameKnown = false
        XCTAssertTrue(IconsHiddenListRules.matches(pushed, actual: rect(400)))
        XCTAssertFalse(IconsHiddenListRules.matches(pushed, actual: rect(400, width: 40)))
    }

    func testRefreshIsThrottled() {
        XCTAssertTrue(IconsHiddenListRules.wantsRefresh(lastAsk: nil, now: 10))
        XCTAssertFalse(IconsHiddenListRules.wantsRefresh(lastAsk: 10, now: 14))
        XCTAssertTrue(IconsHiddenListRules.wantsRefresh(lastAsk: 10, now: 15))
        // The uptime clock never runs back, but a reset store could hand back a later stamp.
        XCTAssertTrue(IconsHiddenListRules.wantsRefresh(lastAsk: 10, now: 5))
    }

    func testHeaders() {
        XCTAssertEqual(IconsHiddenListRules.hiddenHeader(3), "Hidden (3)")
        XCTAssertEqual(IconsHiddenListRules.notchHeader(1), "Behind the Notch (1)")
    }
}
