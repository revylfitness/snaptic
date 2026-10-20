import Foundation

// Status-item plan logic (owner: M; PLAN 0.3 §5.2). `MenuPresence` and `StatusItemPlan` are the lead's types
// (KitModules.swift, ConfigModules.swift); this file decides which items exist and what the Snaptic item shows.

/// Small pure helpers around the plan (M).
package enum MenuLayout {
    /// The Keep Awake action (G declares the `AwakeActionID` constants; the raw value is the contract).
    package static let keepAwakeAction = AwakeActionID(rawValue: "awake.toggle")

    /// Where the Keep Awake shortcut stands, for Awake's "Don't Show" (parity M2): only `registered` keeps a hidden
    /// Awake reachable. `registered` is G's runtime flag (`AwakeRuntimeState.keepAwakeRegistered`: the combo is
    /// registered right now); the other cases only choose the words (toast, Menu Bar footer).
    package enum AwakeShortcutStatus: Equatable, CaseIterable {
        /// Set and registered: Awake may be hidden.
        case registered
        /// No Keep Awake combo is stored.
        case notSet
        /// Set, but another app or macOS has the combo (AwakeAutomation's `failedShortcuts`).
        case failed
        /// Set, but nothing is registered: Awake's Keyboard Shortcuts feature is off (setting, defaults key).
        case turnedOff

        package var isBound: Bool { self == .registered }
    }

    /// `registered` wins (it is what macOS delivers); otherwise unset before failed before turned off.
    package static func awakeShortcutStatus(_ shortcuts: LossyMap<AwakeActionID, HotkeyCombo>,
                                            failed: Set<AwakeActionID>, registered: Bool) -> AwakeShortcutStatus {
        if registered { return .registered }
        if shortcuts[keepAwakeAction] == nil { return .notSet }
        return failed.contains(keepAwakeAction) ? .failed : .turnedOff
    }

    /// The Snaptic item's default glyph (stored as ""), and the ones it uses instead while a module's own icon
    /// already shows it (Window Switcher's glyph; ux m16: two identical icons side by side).
    package static let snapticSymbol = "rectangle.on.rectangle"
    package static let snapticAlternateSymbol = "square.grid.2x2"
    /// The Snaptic icon choices on the Menu Bar page, in order (the default first).
    package static let snapticSymbols = [snapticSymbol, snapticAlternateSymbol, "circle.grid.cross"]

    /// The Snaptic item's glyph: the stored choice ("" = the default) unless one of the own icons shown now
    /// (`ownIconSymbols`, from `ModulesConfig.ownIconIDs`) already uses it; then the first choice none of them uses.
    /// The Snaptic item and a module's item never show the same glyph (code N3).
    package static func sharedSymbol(stored: String, ownIconSymbols: [String]) -> String {
        let wanted = stored.isEmpty ? snapticSymbol : stored
        guard ownIconSymbols.contains(wanted) else { return wanted }
        return snapticSymbols.first { !ownIconSymbols.contains($0) } ?? wanted
    }

    /// What the Menu Bar page stores for a chosen Snaptic glyph: the default is always stored as "" (it then steps
    /// aside by itself whenever an own icon uses it), so a choice never pins a glyph that collides later.
    package static func storedSharedSymbol(chosen: String) -> String {
        chosen == snapticSymbol ? "" : chosen
    }

    /// The Snaptic icon tiles: the choices (plus a stored glyph that isn't one of them) except the glyphs an own
    /// icon shows now, so every tile can be the glyph the menu bar shows. `sharedSymbol` is always among them.
    package static func snapticSymbolChoices(stored: String, ownIconSymbols: [String]) -> [String] {
        var seen = Set<String>()
        let candidates = snapticSymbols + (stored.isEmpty ? [] : [stored])
        let free = candidates.filter { !ownIconSymbols.contains($0) && seen.insert($0).inserted }
        let shown = sharedSymbol(stored: stored, ownIconSymbols: ownIconSymbols)
        return free.contains(shown) ? free : [shown] + free
    }

    /// The toast the host shows when the Don't Show fallback (`awakePresenceFallback`) moves Awake back; nil for
    /// a registered shortcut (no fallback then).
    package static func awakeFallbackNotice(_ status: AwakeShortcutStatus) -> String? {
        switch status {
        case .registered: return nil
        case .notSet: return L("Awake is back in the menu bar because its keyboard shortcut is no longer set.")
        case .failed: return L("Awake is back in the menu bar because its keyboard shortcut is used by another app or by macOS.")
        case .turnedOff: return L("Awake is back in the menu bar because its keyboard shortcuts are turned off.")
        }
    }

    /// The Menu Bar page's footer while Awake can't be hidden; nil for a registered shortcut.
    package static func awakeHideHint(_ status: AwakeShortcutStatus) -> String? {
        switch status {
        case .registered: return nil
        case .notSet: return L("To hide Awake, first set a Keep Awake shortcut.")
        case .failed: return L("To hide Awake, choose a Keep Awake shortcut that no other app or macOS uses.")
        case .turnedOff: return L("Awake’s keyboard shortcuts are turned off, so Awake can’t be hidden.")
        }
    }

    /// Whether `presence` may be chosen for a module now: Awake's Don't Show needs a bound Keep Awake shortcut.
    package static func isSelectable(_ presence: MenuPresence, for id: ModuleID, awakeShortcutBound: Bool) -> Bool {
        guard MenuPresence.allowed(for: id).contains(presence) else { return false }
        return !(id == .awake && presence == .hidden && !awakeShortcutBound)
    }
}

// MARK: - 0.3.1 Part A: tabs in the Snaptic menu (owner: T-menu)

extension ModuleID {
    /// A1: the tab label when the full titles don't fit at equal widths. The full title stays the accessibility label.
    package var shortTitle: String {
        switch self {
        case .windowSwitcher: return L("Switcher")
        case .displays: return L("Displays")
        case .awake: return L("Awake")
        }
    }
}

/// The Snaptic menu's tabs (PLAN 0.3.1 A1–A5): which tabs show, which one is selected, how the labels fit, the ⌘n keys
/// and the spoken text. Pure decisions, tested in MenuTabsTests and the MenuLayoutTests fuzz; StatusMenu and
/// MenuTabBarView only draw them.
package enum MenuTabs {
    /// A5: the remembered tab, a plain `UserDefaults.standard` string holding a `ModuleID` raw value. It is navigation
    /// state, like `settingsLastRoute`: not in ModulesConfig, not in backups or the key cross-check, and no reset
    /// clears it.
    package static let defaultsKey = "snapticMenuTab"

    /// ⌘1…⌘9 address tabs by position; a tab past the ninth would have no key.
    package static let maxKeyIndex = 9

    /// A1: one tab per module in the Snaptic item, in `plan.shared` order, only with two or more. Empty means no tab
    /// bar (one module keeps its 0.3 header; none shows "No Modules Are On").
    package static func tabs(plan: StatusItemPlan) -> [ModuleID] {
        plan.shared.count >= 2 ? plan.shared : []
    }

    /// A1/A5: the tab to show. The stored value is decoded leniently (missing, unknown or stale values fall back to the
    /// first tab), and a module that isn't a tab now also falls back without the caller overwriting the stored
    /// choice, so the tab comes back when its module returns. nil only without tabs.
    package static func selected(stored: String?, tabs: [ModuleID]) -> ModuleID? {
        guard let first = tabs.first else { return nil }
        guard let raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines),
              let id = ModuleID(rawValue: raw), tabs.contains(id) else { return first }
        return id
    }

    /// A1: how the segment labels fit, tried in this order so HIG's equal segment widths hold in the common case.
    package enum LabelStyle: Equatable, CaseIterable, Sendable {
        /// `.fillEqually` with the full titles.
        case fullEqual
        /// `.fillEqually` with `ModuleID.shortTitle`.
        case shortEqual
        /// `.fit` with the short titles (the last resort; labels may truncate).
        case shortFit

        package var usesShortTitles: Bool { self != .fullEqual }
        package var fillsEqually: Bool { self != .shortFit }
    }

    /// A1: the first style whose labels fit. `fullWidths` and `shortWidths` are each segment's measured width with
    /// that label (text plus the segment's own padding, without the image); `imageWidth` (the attention image and its
    /// gap) is added to every segment whose `attention` is true. Equal widths fit when the widest segment, times the
    /// number of segments, fits in `available`. A width that isn't a finite, non-negative number never fits.
    /// (PLAN A4 also lists `fitWidths`: `.shortFit` is the unconditional last resort, so no width decides it.)
    package static func labelStyle(fullWidths: [Double], shortWidths: [Double], imageWidth: Double,
                                   attention: [Bool], available: Double) -> LabelStyle {
        func fitsEqually(_ widths: [Double]) -> Bool {
            guard !widths.isEmpty, available.isFinite, imageWidth.isFinite, imageWidth >= 0 else { return false }
            var widest = 0.0
            for (index, width) in widths.enumerated() {
                guard width.isFinite, width >= 0 else { return false }
                let marked = index < attention.count && attention[index]
                widest = max(widest, width + (marked ? imageWidth : 0))
            }
            return widest * Double(widths.count) <= available
        }
        if fitsEqually(fullWidths) { return .fullEqual }
        if fitsEqually(shortWidths) { return .shortEqual }
        return .shortFit
    }

    /// A3: the ⌘n position of a tab (1-based), nil when it isn't a tab or is past ⌘9.
    package static func keyIndex(for id: ModuleID, tabs: [ModuleID]) -> Int? {
        guard let index = tabs.firstIndex(of: id), index < maxKeyIndex else { return nil }
        return index + 1
    }

    /// A3: the tab ⌘n selects (by position), nil outside 1…min(tabs, 9).
    package static func tab(atKeyIndex n: Int, tabs: [ModuleID]) -> ModuleID? {
        guard n >= 1, n <= min(tabs.count, maxKeyIndex) else { return nil }
        return tabs[n - 1]
    }

    /// A1: the tabs that show the attention mark (`SnapticModule.menuAttention`).
    package static func attention(_ flags: [ModuleID: Bool], tabs: [ModuleID]) -> Set<ModuleID> {
        Set(tabs.filter { flags[$0] == true })
    }

    /// The digit-row virtual key codes (kVK_ANSI_1…9), for layouts whose digit row types symbols (AZERTY's "&").
    private static let digitRowKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// A3: the ⌘n a key-down asks for, by position. `commandOnly`: ⌘ is held and ⇧, ⌥ and ⌃ aren't. A typed digit
    /// wins; otherwise the physical digit-row key counts. nil when it isn't ⌘1…⌘n for `tabCount` tabs.
    package static func keyIndex(characters: String?, keyCode: UInt16, commandOnly: Bool, tabCount: Int) -> Int? {
        guard commandOnly, tabCount >= 2 else { return nil }
        let n: Int?
        if let characters, characters.count == 1, let digit = Int(characters) {
            n = digit
        } else {
            n = digitRowKeyCodes[keyCode]
        }
        guard let n, n >= 1, n <= min(tabCount, maxKeyIndex) else { return nil }
        return n
    }

    // MARK: Assistive input (A3)

    /// Where macOS keeps Accessibility › Keyboard › Full Keyboard Access (macOS 12+), which has no public API.
    /// `NSApp.isFullKeyboardAccessEnabled` reads Keyboard › Keyboard navigation (`AppleKeyboardUIMode`), a separate
    /// setting (r1 U2). HW-25 confirms the key.
    package static let fullKeyboardAccessDomain = "com.apple.Accessibility"
    package static let fullKeyboardAccessKey = "FullKeyboardAccessEnabled"

    /// A3: the Show … Tab items show while any assistive input is in use: VoiceOver, Switch Control, Keyboard
    /// navigation, or Full Keyboard Access. Either keyboard setting alone is enough (r1 U2).
    package static func showsTabItems(voiceOver: Bool, switchControl: Bool, keyboardNavigation: Bool,
                                      fullKeyboardAccess: Bool) -> Bool {
        voiceOver || switchControl || keyboardNavigation || fullKeyboardAccess
    }

    // MARK: Text (A1–A3)

    /// The tab bar's accessibility label.
    package static let barLabel = L("Menu tabs")

    /// The tab bar's accessibility help; the range follows the tab count.
    package static func barHelp(tabCount: Int) -> String {
        L("Press Command-1 to Command-\(min(max(tabCount, 1), maxKeyIndex)) to switch tabs.")
    }

    /// A segment's accessibility label: always the full title, then ", on" while Awake governs, then
    /// ", needs attention" with the attention mark.
    package static func segmentLabel(title: String, active: Bool, attention: Bool) -> String {
        title + (active ? L(", on") : "") + (attention ? L(", needs attention") : "")
    }

    /// A segment's tooltip: "Displays (⌘2)", or "Awake, on (⌘3)" while Awake governs.
    package static func segmentToolTip(title: String, keyIndex: Int?, active: Bool) -> String {
        let base = active ? title + L(", on") : title
        guard let keyIndex else { return base }
        return base + " (⌘\(keyIndex))"
    }

    /// A segment's VoiceOver help: only its key, spelled the way `barHelp` spells it ("Command-3"); nil past ⌘9. The
    /// label already speaks the title and ", on", so the help repeats neither and never reads the ⌘ glyph (r1 U3).
    package static func segmentHelp(keyIndex: Int?) -> String? {
        guard let keyIndex, keyIndex >= 1, keyIndex <= maxKeyIndex else { return nil }
        return L("Command-\(keyIndex)")
    }

    /// A3: the native twin of a tab, in the footer ("Show Displays Tab").
    package static func showTabTitle(_ title: String) -> String { L("Show \(title) Tab") }

    /// A2: the status row of a tab whose module has nothing to show (it stopped while the menu was open).
    package static let emptySection = L("Nothing to Show")
}

extension ModulesConfig {
    /// The 0.3 status-item plan (§5.2, tested truth table in MenuLayoutTests).
    ///
    /// - `running`: modules that run now; enabled modules that don't run (turned off by a defaults key) show nothing.
    /// - `awakeActive`: an Awake session, rule or hold governs (`AwakeGoverning != .inactive`).
    /// - `displaysActive`: an external display is connected (Displays' Show When Active).
    /// - `awakeShortcutBound`: the Keep Awake shortcut is registered right now (`AwakeShortcutStatus.isBound`;
    ///   Awake's Don't Show is only safe with it).
    /// - `sharedShownAtRest`: the Snaptic item existed before this Awake session (a session never removes it).
    ///
    /// Rules: Window Switcher and Displays go into the Snaptic item (Show in Snaptic Menu), get their own item
    /// (Always Show; Displays' Show When Active only with `displaysActive`) or nothing (Don't Show). Awake:
    /// Always Show → its own item; Show When Active → the compact section in the Snaptic item at rest, its own item
    /// while active (plus the compact section when the Snaptic item was shown at rest); Show in Snaptic Menu → the
    /// compact section; Don't Show → nothing at rest, and while active the Snaptic item's active glyph if that item
    /// exists, otherwise its own item for the session (N11). Without a bound shortcut a hidden Awake also gets its own
    /// item while active, because nothing else could turn the session off from the menu bar.
    package func statusItemPlan(running: Set<ModuleID>, awakeActive: Bool, displaysActive: Bool,
                                awakeShortcutBound: Bool, sharedShownAtRest: Bool) -> StatusItemPlan {
        let enabled = enabledModules
        guard !enabled.isEmpty else {
            // "No Modules Are On" + Snaptic Settings…
            return StatusItemPlan(shared: [], ownIcon: [], showShared: true, noModulesEnabled: true,
                                  everythingHidden: false)
        }
        let live = enabled.filter { running.contains($0) }
        let governing = awakeActive && live.contains(.awake)
        var shared = live.filter { $0 != .awake && presence($0) == .inSnapticMenu }
        let own = ownIconIDs(running: running, displaysActive: displaysActive)

        var custom: [ModuleID] = []
        var compact = false
        if live.contains(.awake) {
            switch presence(.awake) {
            case .ownIcon:
                custom = [.awake]
            case .ownIconWhenActive:
                if governing {
                    custom = [.awake]
                    compact = sharedShownAtRest
                } else {
                    compact = true
                }
            case .inSnapticMenu:
                compact = true
            case .hidden:
                if governing && (shared.isEmpty || !awakeShortcutBound) { custom = [.awake] }
            }
        }
        if compact { shared.append(.awake) }
        shared = ModuleID.allCases.filter { shared.contains($0) }   // start order

        let showShared = !shared.isEmpty
        let everythingHidden = enabled.allSatisfy { presence($0) == .hidden } && custom.isEmpty
        return StatusItemPlan(shared: shared, ownIcon: own, showShared: showShared, noModulesEnabled: false,
                              everythingHidden: everythingHidden, custom: custom, awakeCompactInShared: compact,
                              sharedActiveGlyph: governing && showShared,
                              sharedFooterInOwnMenus: !showShared && !(own.isEmpty && custom.isEmpty))
    }

    /// The modules (not Awake, which builds its own item) shown with an icon of their own now: running, Always Show,
    /// or Show When Active while it is active (only Displays offers it; anywhere else it is an unsanitized value
    /// and means an own icon). The plan's `ownIcon`, and what the Menu Bar page's Snaptic icon steps aside for.
    package func ownIconIDs(running: Set<ModuleID>, displaysActive: Bool) -> [ModuleID] {
        enabledModules.filter { id in
            guard id != .awake, running.contains(id) else { return false }
            switch presence(id) {
            case .ownIcon: return true
            case .ownIconWhenActive: return id != .displays || displaysActive
            case .inSnapticMenu, .hidden: return false
            }
        }
    }

    /// The plan with the Snaptic item's "shown at rest" memory resolved the way StatusMenu does it: the item counts
    /// as shown at rest when it exists now or when the same configuration without a session would show it.
    package func statusItemPlan(running: Set<ModuleID>, awakeActive: Bool, displaysActive: Bool,
                                awakeShortcutBound: Bool, sharedExistsNow: Bool) -> StatusItemPlan {
        let atRest = statusItemPlan(running: running, awakeActive: false, displaysActive: displaysActive,
                                    awakeShortcutBound: awakeShortcutBound, sharedShownAtRest: true)
        guard awakeActive else { return atRest }
        return statusItemPlan(running: running, awakeActive: true, displaysActive: displaysActive,
                              awakeShortcutBound: awakeShortcutBound,
                              sharedShownAtRest: sharedExistsNow || atRest.showShared)
    }

    /// The "Don't Show" fallback (§5.2, parity minor 11): Awake set to Don't Show while the Keep Awake shortcut is
    /// unbound goes back to Show When Active (the host then says so in `MenuLayout.awakeFallbackNotice`). nil =
    /// nothing to change; also while Awake doesn't run (`awakeRunning` false: off, or turned off by a defaults
    /// setting; it shows nothing anyway, its shortcut isn't registered, and the check runs again when it starts).
    package func awakePresenceFallback(awakeRunning: Bool, awakeShortcutBound: Bool) -> MenuPresence? {
        awakeRunning && isEnabled(.awake) && presence(.awake) == .hidden && !awakeShortcutBound
            ? .ownIconWhenActive : nil
    }
}
