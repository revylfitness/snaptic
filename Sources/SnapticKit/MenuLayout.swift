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
