import XCTest
@testable import SnapticKit

/// The Hidden Icons page's rules (PLAN 0.4 §4.9, §4.17, A7): the status row's priority and notes, the Sections
/// lists, the row values, and the How to Arrange lines. Linux-safe.
final class IconsPageRulesTests: XCTestCase {
    private func facts(_ engine: IconsEngineKind? = .native, _ state: IconsEngineState = .expanded(.plain))
        -> IconsPageFacts {
        IconsPageFacts(engine: engine, state: state)
    }

    // MARK: Status: unavailable and paused

    func testUnavailableShowsReasonWithTryAgainOnlyForDisabledBuild() {
        let build = IconsPageRules.status(facts(.native, .unavailable(.disabledBuild)))
        XCTAssertTrue(build.warning)
        XCTAssertEqual(build.action, .tryAgain)
        XCTAssertEqual(build.text, IconsHiddenListRules.unavailableText(.disabledBuild))

        let kill = IconsPageRules.status(facts(.native, .unavailable(.killSwitch)))
        XCTAssertNil(kill.action)
        XCTAssertEqual(kill.text, L("Hidden Icons is turned off on this Mac, so your icons stay shown."))
    }

    func testStoppedReadsStarting() {
        let status = IconsPageRules.status(facts(nil, .unavailable(.stopped)))
        XCTAssertEqual(status, IconsStatus(L("Starting…")))
    }

    func testUnavailableHasNoNotes() {
        var f = facts(.native, .unavailable(.timeouts))
        f.ownItems = .someHidden
        f.failSafe = .activationFailed
        f.failSafeTime = "9:41"
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
    }

    func testPausedBeatsPermissionAndArrow() {
        var f = facts()
        f.pausedFor = KnownMenuBarHider(name: "Hidden Bar", bundleID: "com.dwarvesv.minimalbar", teamID: nil)
        f.access = .notGranted
        f.arrowVisible = false
        let status = IconsPageRules.status(f)
        XCTAssertEqual(status.text, L("Paused while Hidden Bar runs"))
        XCTAssertTrue(status.warning)
        XCTAssertNil(status.action)

        var exam = facts()
        exam.examPaused = true
        XCTAssertEqual(IconsPageRules.status(exam).text, L("Paused during an exam session"))
    }

    // MARK: Status: permission

    func testNativePermissionOffersPrivacyOrRelaunch() {
        var f = facts()
        f.access = .notGranted
        XCTAssertEqual(IconsPageRules.status(f).action, .openPrivacy)
        XCTAssertEqual(IconsPageRules.status(f).text, IconsPageRules.needsPermissionText)
        f.access = .revoked
        XCTAssertEqual(IconsPageRules.status(f).action, .openPrivacy)
        f.access = .notEffective
        XCTAssertEqual(IconsPageRules.status(f).action, .relaunch)
        XCTAssertEqual(IconsPageRules.status(f).text, IconsPageRules.notEffectiveText)
    }

    func testLengthIgnoresPermissionForTheStatus() {
        var f = facts(.length)
        f.access = .notGranted
        let status = IconsPageRules.status(f)
        XCTAssertFalse(status.warning)
        XCTAssertEqual(status.action, .hideIcons)
    }

    // MARK: Status: missing items and arrangement

    func testPermissionBeatsMissingArrow() {
        var f = facts()
        f.access = .notGranted
        f.arrowVisible = false
        XCTAssertEqual(IconsPageRules.status(f).action, .openPrivacy)
    }

    func testMissingItemsInOrder() {
        var f = facts(.length)
        f.alwaysHidden = true
        f.arrowVisible = false
        f.dividerVisible = false
        f.alwaysHiddenVisible = false
        f.arrangementValid = false
        XCTAssertEqual(IconsPageRules.status(f).action, .showArrow)
        f.arrowVisible = true
        XCTAssertEqual(IconsPageRules.status(f).action, .showDivider)
        XCTAssertEqual(IconsPageRules.status(f).text, L("The | divider isn’t in the menu bar, so icons stay shown."))
        f.dividerVisible = true
        XCTAssertEqual(IconsPageRules.status(f).action, .showAlwaysHiddenDivider)
        f.alwaysHiddenVisible = true
        let arrange = IconsPageRules.status(f)
        XCTAssertEqual(arrange.text, L("Drag the | divider to the left of the arrow (hold ⌘)."))
        XCTAssertEqual(arrange.action, .hideIcons)
        XCTAssertTrue(arrange.warning)
    }

    func testNativeIgnoresTheLengthDividerAndArrangement() {
        var f = facts()
        f.dividerVisible = false
        f.arrangementValid = false
        let status = IconsPageRules.status(f)
        XCTAssertFalse(status.warning)
        XCTAssertEqual(status.action, .hideIcons)
    }

    func testMissingAlwaysHiddenDividerCountsOnlyWhenOn() {
        var f = facts()
        f.alwaysHiddenVisible = false
        XCTAssertEqual(IconsPageRules.status(f).action, .hideIcons)
        f.alwaysHidden = true
        XCTAssertEqual(IconsPageRules.status(f).action, .showAlwaysHiddenDivider)
    }

    // MARK: Status: refusals and own items

    func testIdentityRefusal() {
        var f = facts()
        f.refusal = .identity
        let status = IconsPageRules.status(f)
        XCTAssertEqual(status.text, L("Move Snaptic to Applications to hide icons."))
        XCTAssertTrue(status.warning)
        XCTAssertNil(status.action)
    }

    func testOwnItemsBlockOrNote() {
        var f = facts(.length)
        f.ownItems = .arrowHidden
        XCTAssertEqual(IconsPageRules.status(f).text, IconsPageRules.ownItemsText(.arrowHidden))
        f.ownItems = .awakeHidden
        XCTAssertEqual(IconsPageRules.status(f).text, IconsPageRules.ownItemsText(.awakeHidden))
        f.ownItems = .someHidden
        let status = IconsPageRules.status(f)
        XCTAssertEqual(status.action, .hideIcons)
        XCTAssertEqual(status.notes, [IconsStatusNote(IconsPageRules.ownItemsText(.someHidden))])
    }

    // MARK: Status: engine states

    func testCollapsedCountsAndShowIcons() {
        var f = facts(.native, .collapsed)
        f.hiddenCount = 7
        XCTAssertEqual(IconsPageRules.status(f), IconsStatus(L("Hiding 7 icons"), action: .showIcons))
        f.hiddenCount = 1
        XCTAssertEqual(IconsPageRules.status(f).text, L("Hiding 1 icon"))
        f.hiddenCount = nil
        XCTAssertEqual(IconsPageRules.status(f).text, L("Icons are hidden"))
    }

    func testCalibrating() {
        XCTAssertEqual(IconsPageRules.status(facts(.native, .calibrating)), IconsStatus(L("Hiding icons…")))
    }

    func testExpandedFirstRunOrShowing() {
        var f = facts(.native, .expanded(.all))
        f.arranged = false
        XCTAssertEqual(IconsPageRules.status(f), IconsStatus(IconsPageRules.firstRunText, action: .arrangeNow))
        f.arranged = true
        XCTAssertEqual(IconsPageRules.status(f), IconsStatus(L("Showing all icons"), action: .hideIcons))
    }

    // MARK: Notes

    func testAlwaysHiddenMisplacedNotePerEngine() {
        var f = facts(.length)
        f.alwaysHidden = true
        f.alwaysHiddenPlaced = false
        XCTAssertEqual(IconsPageRules.status(f).notes,
                       [IconsStatusNote(L("Drag the ⋮ divider to the left of the | divider (hold ⌘)."))])
        f.engine = .native
        XCTAssertEqual(IconsPageRules.status(f).notes,
                       [IconsStatusNote(L("Drag the ⋮ divider to the left of the arrow (hold ⌘)."))])
        // A missing ⋮ is the main line, not a misplaced note.
        f.alwaysHiddenVisible = false
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
    }

    func testFailSafeNoteSkipsSessionAndAgentRestartAndNeedsATime() {
        var f = facts()
        f.failSafe = .activationFailed
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
        f.failSafeTime = "9:41"
        XCTAssertEqual(IconsPageRules.status(f).notes, [IconsStatusNote(IconsPageRules.failSafeText("9:41"))])
        XCTAssertEqual(IconsPageRules.failSafeText("9:41"),
                       L("Icons were shown at 9:41 because Snaptic couldn’t confirm they were hidden safely."))
        f.failSafe = .session
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
        f.failSafe = .agentRestart
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
    }

    func testStaleNoteIsNativeAlwaysHiddenAfterADay() {
        var f = facts()
        f.alwaysHidden = true
        f.cacheAge = IconsPageRules.staleAfter
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
        f.cacheAge = 2.5 * 86_400
        XCTAssertEqual(IconsPageRules.status(f).notes,
                       [IconsStatusNote(IconsPageRules.staleText(days: 2), warning: false)])
        f.alwaysHidden = false
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
        f.alwaysHidden = true
        f.engine = .length
        XCTAssertEqual(IconsPageRules.status(f).notes, [])
    }

    func testStaleTextSingular() {
        XCTAssertEqual(IconsPageRules.staleText(days: 1),
                       L("Icon positions were last read 1 day ago. Option-click the arrow to refresh them."))
        XCTAssertEqual(IconsPageRules.staleText(days: 3),
                       L("Icon positions were last read 3 days ago. Option-click the arrow to refresh them."))
    }

    func testNotesStackInOrder() {
        var f = facts()
        f.ownItems = .someHidden
        f.alwaysHidden = true
        f.alwaysHiddenPlaced = false
        f.failSafe = .activateTimeout
        f.failSafeTime = "9:41"
        f.cacheAge = 3 * 86_400
        XCTAssertEqual(IconsPageRules.status(f).notes.map(\.text), [
            IconsPageRules.ownItemsText(.someHidden),
            IconsPageRules.alwaysHiddenMisplacedText(.native),
            IconsPageRules.failSafeText("9:41"),
            IconsPageRules.staleText(days: 3),
        ])
    }

    // MARK: Rows

    func testShowsDividers() {
        XCTAssertTrue(IconsPageRules.showsDividers(engine: .length, alwaysHidden: false))
        XCTAssertTrue(IconsPageRules.showsDividers(engine: .length, alwaysHidden: true))
        XCTAssertFalse(IconsPageRules.showsDividers(engine: .native, alwaysHidden: false))
        XCTAssertTrue(IconsPageRules.showsDividers(engine: .native, alwaysHidden: true))
    }

    func testDividersHelpPerEngine() {
        XCTAssertTrue(IconsPageRules.dividersHelp(.length).contains("|"))
        XCTAssertFalse(IconsPageRules.dividersHelp(.native).contains("|"))
    }

    func testSectionsValue() {
        XCTAssertNil(IconsPageRules.sectionsValue(hidden: nil, choices: 0))
        XCTAssertEqual(IconsPageRules.sectionsValue(hidden: 7, choices: 0), "7 hidden")
        XCTAssertEqual(IconsPageRules.sectionsValue(hidden: 0, choices: 0), "0 hidden")
        XCTAssertEqual(IconsPageRules.sectionsValue(hidden: 7, choices: 1), "7 hidden · 1 choice")
        XCTAssertEqual(IconsPageRules.sectionsValue(hidden: 7, choices: 2), "7 hidden · 2 choices")
        XCTAssertEqual(IconsPageRules.sectionsValue(hidden: nil, choices: 3), "3 choices")
    }

    func testAutoCollapseTitle() {
        XCTAssertEqual(IconsPageRules.autoCollapseTitle(10), "Hide icons automatically after 10 seconds")
    }

    // MARK: Sections

    func testSectionsPlaceChoicesOnNative() {
        let list = IconsPageRules.sections(
            ["a": .shown, "b": .shown, "c": .hidden, "d": .alwaysHidden, "e": .alwaysHidden, "sys": .hidden],
            system: ["sys"],
            choices: ["b": .alwaysHide, "c": .alwaysShow, "d": .alwaysShow, "e": .alwaysHide, "sys": .alwaysShow],
            newShown: ["a"], engine: .native,
            names: ["a": "Alpha", "b": "Bravo", "c": "Charlie", "d": "Delta", "e": "Echo", "sys": "Input"])
        XCTAssertEqual(list.shown.map(\.bundleID), ["a", "c", "d"])
        XCTAssertEqual(list.hidden.map(\.bundleID), ["b", "sys"])
        // Always Hide doesn't pull an app out of Always Hidden (G-7).
        XCTAssertEqual(list.alwaysHidden.map(\.bundleID), ["e"])
        let sys = list.hidden.first { $0.bundleID == "sys" }
        XCTAssertEqual(sys?.canChoose, false)
        XCTAssertNil(sys?.choice)
        XCTAssertEqual(list.shown.first?.isNew, true)
        XCTAssertEqual(list.shown.first { $0.bundleID == "c" }?.choice, .alwaysShow)
    }

    func testSectionsIgnoreChoicesOnLength() {
        let list = IconsPageRules.sections(["a": .hidden, "b": .shown], system: [],
                                           choices: ["a": .alwaysShow, "b": .alwaysHide], newShown: [],
                                           engine: .length, names: [:])
        XCTAssertEqual(list.hidden.map(\.bundleID), ["a"])
        XCTAssertEqual(list.shown.map(\.bundleID), ["b"])
        XCTAssertTrue((list.hidden + list.shown).allSatisfy { !$0.canChoose && $0.choice == nil })
    }

    func testSectionsSortByNameThenBundleAndFallBackToTheBundleID() {
        let list = IconsPageRules.sections(["z": .shown, "y": .shown, "x": .shown, "w": .shown], system: [],
                                           choices: [:], newShown: [], engine: .native,
                                           names: ["z": "apple", "y": "Apple", "x": "Banana", "w": ""])
        XCTAssertEqual(list.shown.map(\.bundleID), ["y", "z", "x", "w"])
        XCTAssertEqual(list.shown.last?.name, "w")
        XCTAssertEqual(list.rows(.shown), list.shown)
    }

    func testRefreshTitle() {
        XCTAssertEqual(IconsPageRules.refreshTitle(engine: .native, limited: true), "Show All Icons and Refresh")
        XCTAssertEqual(IconsPageRules.refreshTitle(engine: .native, limited: false), "Refresh")
        XCTAssertEqual(IconsPageRules.refreshTitle(engine: .length, limited: true), "Refresh")
        XCTAssertEqual(IconsPageRules.refreshTitle(engine: nil, limited: true), "Refresh")
    }

    func testChoiceOptionsOrder() {
        XCTAssertEqual(IconsPageRules.choiceOptions.map(\.0), [nil, .alwaysShow, .alwaysHide])
        XCTAssertEqual(IconsPageRules.choiceOptions.map(\.1), ["Where It Is", "Always Show", "Always Hide"])
    }

    // MARK: How to Arrange

    func testArrangeLinesPerEngine() {
        let length = IconsPageRules.arrangeLines(engine: .length, alwaysHidden: false)
        XCTAssertEqual(length.bullets, ["To the right of the arrow ‹: always shown.",
                                        "Between | and ‹: hidden when you click the arrow."])
        XCTAssertEqual(length.closing, "New apps’ icons appear at the far left, so they start hidden.")
        let native = IconsPageRules.arrangeLines(engine: .native, alwaysHidden: true)
        XCTAssertEqual(native.bullets, ["To the right of the arrow ‹: always shown.",
                                        "To the left of the arrow ‹: hidden when you click it.",
                                        "Left of ⋮: hidden until you Option-click the arrow."])
        XCTAssertTrue(native.closing.contains("Settings › Hidden Icons › Sections"))
    }

    // MARK: First collapse on 27

    private func layout(_ sections: [String: IconsSection], system: Set<String> = []) -> IconsLayout {
        IconsLayout(sections: sections, systemBundles: system, carried: [], extras: [], offScreen: [],
                    scope: .unrestricted, readAt: 1)
    }

    func testAsksBeforeFirstCollapseWhenNothingStaysShown() {
        let own = "com.snaptic.app"
        let allHidden = layout(["a": .hidden, "b": .alwaysHidden, own: .shown, "sys": .shown], system: ["sys"])
        XCTAssertTrue(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                             layout: allHidden, ownBundleID: own))
        // One app stays shown, by place, choice, or as a new app.
        let oneShown = layout(["a": .hidden, "b": .shown])
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                              layout: oneShown, ownBundleID: own))
        XCTAssertTrue(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                             layout: oneShown, ownBundleID: own,
                                                             choices: ["b": .alwaysHide]))
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                              layout: allHidden, ownBundleID: own,
                                                              choices: ["a": .alwaysShow]))
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                              layout: allHidden, ownBundleID: own, newShown: ["b"]))
    }

    func testDoesNotAskOffNativeArrangedAskedOrEmpty() {
        let own = "com.snaptic.app"
        let hidden = layout(["a": .hidden])
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .length, arranged: false, asked: false,
                                                              layout: hidden, ownBundleID: own))
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: true, asked: false,
                                                              layout: hidden, ownBundleID: own))
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: true,
                                                              layout: hidden, ownBundleID: own))
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                              layout: nil, ownBundleID: own))
        XCTAssertFalse(IconsPageRules.asksBeforeFirstCollapse(engine: .native, arranged: false, asked: false,
                                                              layout: layout([own: .hidden, "sys": .hidden],
                                                                             system: ["sys"]),
                                                              ownBundleID: own))
    }

    // MARK: Permissions page

    func testPermissionsNeededForPerEngine() {
        XCTAssertTrue(IconsPageRules.permissionsNeededFor(native: true).contains("hide the right ones"))
        XCTAssertTrue(IconsPageRules.permissionsNeededFor(native: false).contains("Hiding works without it."))
    }
}
