import Foundation

// Settings › Hidden Icons (lead; PLAN 0.4 §4.0, §4.1, §4.2.2, §4.2.5, §4.9, §4.12, §4.17, A7). Pure: what the status
// row says and offers, its notes, the Sections value and list, the How to Arrange lines and the page's fixed strings.
// The app reads the module and the items, and builds SwiftUI rows from this.

/// The status row's button.
package enum IconsStatusAction: String, CaseIterable, Sendable {
    case showIcons
    case hideIcons
    case openPrivacy
    case relaunch
    case showArrow
    case showDivider
    case showAlwaysHiddenDivider
    case tryAgain
    case arrangeNow

    package var title: String {
        switch self {
        case .showIcons: L("Show Icons")
        case .hideIcons: L("Hide Icons")
        case .openPrivacy: L("Open Privacy Settings")
        case .relaunch: L("Relaunch Snaptic")
        case .showArrow: L("Show Arrow")
        case .showDivider, .showAlwaysHiddenDivider: L("Show Divider")
        case .tryAgain: L("Try Again")
        case .arrangeNow: L("How to Arrange…")
        }
    }
}

/// What decides the status row.
package struct IconsPageFacts: Equatable, Sendable {
    /// Nil while the engine is unavailable or the module is off.
    package var engine: IconsEngineKind?
    package var state: IconsEngineState
    package var access: IconsAccessState
    package var pausedFor: KnownMenuBarHider?
    package var examPaused: Bool
    /// The capture guard pauses hiding (`IconsCaptureGuard.pauses`).
    package var capturePaused: Bool
    package var arrowVisible: Bool
    package var dividerVisible: Bool
    package var alwaysHiddenVisible: Bool
    package var alwaysHidden: Bool
    /// `⋮` is on the far side of the Hidden boundary (`IconsGuards.alwaysHiddenPlaced`).
    package var alwaysHiddenPlaced: Bool
    /// `|` is on the hidden side of the arrow (`IconsGuards.arrangementValid`; always true on Native).
    package var arrangementValid: Bool
    package var arranged: Bool
    /// From the last read; nil when unknown (14–26 without Accessibility).
    package var hiddenCount: Int?
    package var refusal: IconsRefusal?
    package var ownItems: IconsOwnItemsRow?
    package var failSafe: IconsFailSafeReason?
    /// `failSafe`'s time, already formatted ("9:41").
    package var failSafeTime: String?
    /// Seconds since the cached layout was read; nil without one.
    package var cacheAge: Double?

    package init(engine: IconsEngineKind?, state: IconsEngineState, access: IconsAccessState = .granted,
                 pausedFor: KnownMenuBarHider? = nil, examPaused: Bool = false, capturePaused: Bool = false,
                 arrowVisible: Bool = true,
                 dividerVisible: Bool = true, alwaysHiddenVisible: Bool = true, alwaysHidden: Bool = false,
                 alwaysHiddenPlaced: Bool = true, arrangementValid: Bool = true, arranged: Bool = true,
                 hiddenCount: Int? = nil, refusal: IconsRefusal? = nil, ownItems: IconsOwnItemsRow? = nil,
                 failSafe: IconsFailSafeReason? = nil, failSafeTime: String? = nil, cacheAge: Double? = nil) {
        self.engine = engine
        self.state = state
        self.access = access
        self.pausedFor = pausedFor
        self.examPaused = examPaused
        self.capturePaused = capturePaused
        self.arrowVisible = arrowVisible
        self.dividerVisible = dividerVisible
        self.alwaysHiddenVisible = alwaysHiddenVisible
        self.alwaysHidden = alwaysHidden
        self.alwaysHiddenPlaced = alwaysHiddenPlaced
        self.arrangementValid = arrangementValid
        self.arranged = arranged
        self.hiddenCount = hiddenCount
        self.refusal = refusal
        self.ownItems = ownItems
        self.failSafe = failSafe
        self.failSafeTime = failSafeTime
        self.cacheAge = cacheAge
    }
}

/// A line under the status row.
package struct IconsStatusNote: Equatable, Sendable {
    package var text: String
    package var warning: Bool

    package init(_ text: String, warning: Bool = true) {
        self.text = text
        self.warning = warning
    }
}

/// The status row: one line, a style, at most one button, and notes.
package struct IconsStatus: Equatable, Sendable {
    package var text: String
    package var warning: Bool
    package var action: IconsStatusAction?
    package var notes: [IconsStatusNote]

    package init(_ text: String, warning: Bool = false, action: IconsStatusAction? = nil,
                 notes: [IconsStatusNote] = []) {
        self.text = text
        self.warning = warning
        self.action = action
        self.notes = notes
    }
}

/// One app on the Sections page.
package struct IconsSectionsRow: Equatable, Sendable {
    package var bundleID: String
    package var name: String
    /// Where it lists: the choice's section when it has one (Native), else where it is.
    package var section: IconsSection
    package var choice: IconsAppChoice?
    /// Native and not a macOS owner.
    package var canChoose: Bool
    /// A new app's icon kept shown (§4.5): the secondary line **New**.
    package var isNew: Bool

    package init(bundleID: String, name: String, section: IconsSection, choice: IconsAppChoice?, canChoose: Bool,
                 isNew: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.section = section
        self.choice = choice
        self.canChoose = canChoose
        self.isNew = isNew
    }
}

/// The Sections page's three lists.
package struct IconsSectionsList: Equatable, Sendable {
    package var shown: [IconsSectionsRow]
    package var hidden: [IconsSectionsRow]
    package var alwaysHidden: [IconsSectionsRow]

    package init(shown: [IconsSectionsRow] = [], hidden: [IconsSectionsRow] = [],
                 alwaysHidden: [IconsSectionsRow] = []) {
        self.shown = shown
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }

    package func rows(_ section: IconsSection) -> [IconsSectionsRow] {
        switch section {
        case .shown: shown
        case .hidden: hidden
        case .alwaysHidden: alwaysHidden
        }
    }
}

package enum IconsPageRules {
    /// §4.2.2: a cached layout older than this, with Always Hidden on, says how old it is (Native).
    package static let staleAfter: Double = 86_400

    // MARK: Status row

    /// The engine state, the first thing that keeps icons from hiding, or the state's button; then the notes.
    package static func status(_ f: IconsPageFacts) -> IconsStatus {
        var status = main(f)
        status.notes = notes(f, main: status)
        return status
    }

    private static func main(_ f: IconsPageFacts) -> IconsStatus {
        if case .unavailable(let why) = f.state {
            guard let text = IconsHiddenListRules.unavailableText(why) else { return IconsStatus(L("Starting…")) }
            return IconsStatus(text, warning: true, action: why == .disabledBuild ? .tryAgain : nil)
        }
        let paused = IconsListFacts(engine: f.engine, state: f.state, access: f.access, pausedFor: f.pausedFor,
                                    examPaused: f.examPaused, capturePaused: f.capturePaused)
        if let reason = IconsHiddenListRules.reason(paused) { return IconsStatus(reason, warning: true) }
        if f.engine == .native, f.access.needsPermission {
            return f.access.offersRelaunch
                ? IconsStatus(notEffectiveText, warning: true, action: .relaunch)
                : IconsStatus(needsPermissionText, warning: true, action: .openPrivacy)
        }
        if !f.arrowVisible {
            return IconsStatus(L("The arrow isn’t in the menu bar, so icons stay shown."), warning: true,
                               action: .showArrow)
        }
        if f.engine == .length, !f.dividerVisible {
            return IconsStatus(L("The | divider isn’t in the menu bar, so icons stay shown."), warning: true,
                               action: .showDivider)
        }
        if f.alwaysHidden, !f.alwaysHiddenVisible {
            return IconsStatus(L("The ⋮ divider isn’t in the menu bar, so Always Hidden icons hide with the others."),
                               warning: true, action: .showAlwaysHiddenDivider)
        }
        if f.engine == .length, !f.arrangementValid {
            return IconsStatus(L("Drag the | divider to the left of the arrow (hold ⌘)."), warning: true,
                               action: .hideIcons)
        }
        if f.refusal == .identity, let text = IconsHiddenListRules.unavailableText(.identity) {
            return IconsStatus(text, warning: true)
        }
        if let row = f.ownItems, row != .someHidden { return IconsStatus(ownItemsText(row), warning: true) }
        switch f.state {
        case .collapsed:
            return IconsStatus(IconsItemsLook.arrowValue(collapsed: true, hiddenCount: f.hiddenCount),
                               action: .showIcons)
        case .calibrating:
            return IconsStatus(L("Hiding icons…"))
        case .expanded, .unavailable:
            if !f.arranged { return IconsStatus(firstRunText, action: .arrangeNow) }
            return IconsStatus(IconsItemsLook.arrowValue(collapsed: false, hiddenCount: f.hiddenCount),
                               action: .hideIcons)
        }
    }

    private static func notes(_ f: IconsPageFacts, main: IconsStatus) -> [IconsStatusNote] {
        guard !isUnavailable(f.state) else { return [] }
        var out: [IconsStatusNote] = []
        if f.ownItems == .someHidden { out.append(IconsStatusNote(ownItemsText(.someHidden))) }
        if f.alwaysHidden, f.alwaysHiddenVisible, !f.alwaysHiddenPlaced, let engine = f.engine {
            out.append(IconsStatusNote(alwaysHiddenMisplacedText(engine)))
        }
        if let reason = f.failSafe, ![.session, .agentRestart, .capture].contains(reason), let time = f.failSafeTime {
            out.append(IconsStatusNote(failSafeText(time)))
        }
        if f.engine == .native, f.alwaysHidden, let age = f.cacheAge, age > staleAfter {
            out.append(IconsStatusNote(staleText(days: Int(age / 86_400)), warning: false))
        }
        return out.filter { $0.text != main.text }
    }

    private static func isUnavailable(_ state: IconsEngineState) -> Bool {
        if case .unavailable = state { return true }
        return false
    }

    // MARK: Strings (§4.17)

    package static let summary =
        L("Keep your menu bar tidy: click the arrow to hide the icons to its left, and click again to show them.")
    package static let firstRunText = L("Arrange your icons, then click the arrow to hide them.")
    package static let needsPermissionText =
        L("Hidden Icons needs Device Control and Data Access to see where your icons are.")
    package static let notEffectiveText = L("macOS may need Snaptic to reopen before the permission takes effect.")

    package static func failSafeText(_ time: String) -> String {
        L("Icons were shown at \(time) because Snaptic couldn’t confirm they were hidden safely.")
    }

    /// §4.2.2.
    package static func staleText(days: Int) -> String {
        days == 1
            ? L("Icon positions were last read 1 day ago. Option-click the arrow to refresh them.")
            : L("Icon positions were last read \(days) days ago. Option-click the arrow to refresh them.")
    }

    /// §4.2.5.
    package static func ownItemsText(_ row: IconsOwnItemsRow) -> String {
        switch row {
        case .arrowHidden: L("The arrow is in the hidden area. ⌘-drag it to the right of the | divider.")
        case .awakeHidden:
            L("Awake’s icon is in the hidden area, so icons stay shown while your Mac is kept awake. ⌘-drag it to the right of the arrow.")
        case .someHidden: L("Some Snaptic icons are in the hidden area. ⌘-drag them to the right of the arrow.")
        }
    }

    /// §4.2.5: `⋮` is on the shown side of the Hidden boundary.
    package static func alwaysHiddenMisplacedText(_ engine: IconsEngineKind) -> String {
        switch engine {
        case .length: L("Drag the ⋮ divider to the left of the | divider (hold ⌘).")
        case .native: L("Drag the ⋮ divider to the left of the arrow (hold ⌘).")
        }
    }

    // MARK: Rows

    package static let autoCollapseLabel = L("Hide icons automatically")
    package static func autoCollapseTitle(_ seconds: Int) -> String {
        L("Hide icons automatically after \(seconds) seconds")
    }
    package static let launchTitle = L("Hide icons when Snaptic opens")
    package static let launchHelp = L("Reopening Snaptic to show Settings doesn’t hide them.")
    package static let alwaysHiddenTitle = L("Always Hidden section")
    package static let alwaysHiddenHelp = L("Icons left of the ⋮ divider stay hidden until you Option-click the arrow.")
    package static let dividersTitle = L("Section dividers")
    package static let shortcutTitle = L("Show or hide icons")
    package static let shortcutName = L("Show or Hide Hidden Icons")

    /// Section dividers is hidden on 27 while Always Hidden is off (`|` is zero-length there).
    package static func showsDividers(engine: IconsEngineKind, alwaysHidden: Bool) -> Bool {
        engine == .length || alwaysHidden
    }

    package static func dividersHelp(_ engine: IconsEngineKind) -> String {
        switch engine {
        case .length: L("Shows the | and ⋮ dividers while icons are shown.")
        case .native:
            L("Shows the ⋮ divider while icons are shown. On this version of macOS the arrow marks the edge of the hidden icons.")
        }
    }

    /// The Sections › value: "7 hidden", "7 hidden · 2 choices"; nil with nothing to say.
    package static func sectionsValue(hidden: Int?, choices: Int) -> String? {
        var parts: [String] = []
        if let hidden { parts.append(L("\(hidden) hidden")) }
        if choices > 0 { parts.append(choices == 1 ? L("1 choice") : L("\(choices) choices")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Sections

    /// One row per bundle under the section it lists in. Choices count on Native only: Always Show lists under
    /// Shown, Always Hide under Hidden unless the app is in Always Hidden (only a ⌘-drag puts it there, G-7). macOS
    /// owners take no choice. Sorted by name, then bundle id.
    ///
    /// - Parameter names: the app's name per bundle; a missing one shows the bundle id.
    package static func sections(_ sections: [String: IconsSection], system: Set<String>,
                                 choices: [String: IconsAppChoice], newShown: Set<String>, engine: IconsEngineKind,
                                 names: [String: String]) -> IconsSectionsList {
        var list = IconsSectionsList()
        for (bundle, placed) in sections {
            let canChoose = engine == .native && !system.contains(bundle)
            let choice = canChoose ? choices[bundle] : nil
            var section = placed
            switch choice {
            case .alwaysShow: section = .shown
            case .alwaysHide: if placed == .shown { section = .hidden }
            case nil: break
            }
            let name = names[bundle].flatMap { $0.isEmpty ? nil : $0 } ?? bundle
            let row = IconsSectionsRow(bundleID: bundle, name: name, section: section, choice: choice,
                                       canChoose: canChoose, isNew: newShown.contains(bundle))
            switch section {
            case .shown: list.shown.append(row)
            case .hidden: list.hidden.append(row)
            case .alwaysHidden: list.alwaysHidden.append(row)
            }
        }
        let order: (IconsSectionsRow, IconsSectionsRow) -> Bool = { a, b in
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            return c == .orderedSame ? a.bundleID < b.bundleID : c == .orderedAscending
        }
        list.shown.sort(by: order)
        list.hidden.sort(by: order)
        list.alwaysHidden.sort(by: order)
        return list
    }

    /// The section headers.
    package static func sectionTitle(_ section: IconsSection) -> String {
        switch section {
        case .shown: L("Shown")
        case .hidden: L("Hidden")
        case .alwaysHidden: L("Always Hidden")
        }
    }

    /// The pop-up's options: nil is Where It Is.
    package static let choiceOptions: [(IconsAppChoice?, String)] = [
        (nil, L("Where It Is")), (.alwaysShow, L("Always Show")), (.alwaysHide, L("Always Hide")),
    ]

    package static let sectionsNoPermissionLength =
        L("Allow Accessibility to see which icons are in each section. Hiding works without it.")
    package static let sectionsCachedFooter = L("As of the last time your icons were shown.")
    package static let sectionsLengthFooter = L("⌘-drag icons in the menu bar to move them between sections.")
    package static let sectionsChoiceHelp =
        L("Always Show and Always Hide apply to all of an app’s icons and win over where you drag them.")
    package static let sectionsSystemFooter = L("Icons that macOS hides in System Settings › Menu Bar aren’t listed.")

    /// Native while the read is limited (restricted or collapsed) offers Show All Icons and Refresh.
    package static func refreshTitle(engine: IconsEngineKind?, limited: Bool) -> String {
        engine == .native && limited ? L("Show All Icons and Refresh") : L("Refresh")
    }

    // MARK: How to Arrange (§4.17)

    package static let arrangeTitle = L("How to Arrange Your Icons")
    package static let arrangeIntro = L("Hold ⌘ and drag icons in the menu bar:")

    /// The bullets, then the closing line.
    package static func arrangeLines(engine: IconsEngineKind, alwaysHidden: Bool) -> (bullets: [String],
                                                                                         closing: String) {
        var bullets = [L("To the right of the arrow ‹: always shown.")]
        switch engine {
        case .length: bullets.append(L("Between | and ‹: hidden when you click the arrow."))
        case .native: bullets.append(L("To the left of the arrow ‹: hidden when you click it."))
        }
        if alwaysHidden { bullets.append(L("Left of ⋮: hidden until you Option-click the arrow.")) }
        let closing = engine == .length
            ? L("New apps’ icons appear at the far left, so they start hidden.")
            : L("You can also choose Always Show or Always Hide for an app in Settings › Hidden Icons › Sections.")
        return (bullets, closing)
    }

    // MARK: First collapse on 27 (§4.0)

    package static let firstCollapseTitle = L("Hide all other apps’ icons?")
    package static let firstCollapseMessage =
        L("No icons are to the right of the arrow yet, so every other app’s icon will be hidden. ⌘-drag the icons you want to keep to the right of the arrow first.")

    /// Asks once, on Native, before the first collapse a person asks for, when the read found other apps' icons and
    /// none of them would stay shown.
    package static func asksBeforeFirstCollapse(engine: IconsEngineKind?, arranged: Bool, asked: Bool,
                                                layout: IconsLayout?, ownBundleID: String,
                                                choices: [String: IconsAppChoice] = [:],
                                                newShown: Set<String> = []) -> Bool {
        guard engine == .native, !arranged, !asked, let layout else { return false }
        let others = layout.sections.filter { !layout.systemBundles.contains($0.key) && $0.key != ownBundleID }
        guard !others.isEmpty else { return false }
        return !others.contains { bundle, section in
            let choice = choices[bundle]
            if choice == .alwaysShow || newShown.contains(bundle) { return true }
            return section == .shown && choice != .alwaysHide
        }
    }

    // MARK: Advanced (§4.5, §4.7, §4.9, §4.10, §4.2.5)

    package static let hoverHelp = L("Shows hidden icons when the pointer rests on the menu bar.")
    package static let newAppsHelp =
        L("Show keeps a new app’s icon visible until you next show all icons or choose where it goes.")
    /// R3-90.
    package static let captureHelp =
        L("Shows your icons while an app uses the camera or microphone, so its dot stays visible, then hides them again.")
    /// R3-90, under the Advanced toggle while it's off.
    package static let captureOffFootnote =
        L("While icons are hidden, macOS 27 hides the camera and microphone dots with them.")
    package static let otherHidersFootnote = L("On macOS 27, an icon stays shown unless both apps hide it.")
    package static let fullBarHelp =
        L("Snaptic becomes the active app while icons are shown, so the current app loses focus.")
    package static let fullBarFootnote =
        L("Snaptic also appears in the Dock and the app switcher until the icons are hidden.")
    package static let resetArrowTitle = L("Put the arrow back next to the Snaptic icon?")
    package static let resetArrowMessage =
        L("The arrow and dividers move back next to the Snaptic icon, and your icons are shown. You’ll arrange your icons again.")

    package static let restoreTitle = L("Restore Hidden Icons settings to their defaults?")
    package static let restoreMessage =
        L("Automatic hiding, Always Hidden, dividers, the shortcut, hover, new apps’ icons, the camera and microphone dots, the full menu bar, and every app’s Always Show or Always Hide choice go back to their defaults. Where your icons are in the menu bar stays as it is.")

    /// General › Reset All Settings… adds this while Hidden Icons is on or arranged (A7).
    package static let resetAllNote =
        L("Hidden Icons’ arrow and dividers go back next to the Snaptic icon, so you’ll arrange your icons again.")

    // MARK: Permissions page (§4.17)

    package static func permissionsNeededFor(native: Bool) -> String {
        native
            ? L("Hidden Icons uses it to see where your menu bar icons are, so it can hide the right ones.")
            : L("Hidden Icons uses it to list your hidden icons. Hiding works without it.")
    }
}
