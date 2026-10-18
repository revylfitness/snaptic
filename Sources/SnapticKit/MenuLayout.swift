import Foundation

// Status-item plan logic (owner: M; PLAN 0.3 §5.2). `MenuPresence` and `StatusItemPlan` are the lead's types
// (KitModules.swift, ConfigModules.swift); this file decides which items exist and what the Snaptic item shows.

/// Small pure helpers around the plan (M).
package enum MenuLayout {
    /// The Keep Awake action (G declares the `AwakeActionID` constants; the raw value is the contract).
    package static let keepAwakeAction = AwakeActionID(rawValue: "awake.toggle")

    /// Awake's "Don't Show" is only allowed while the Keep Awake shortcut is bound (parity M2).
    package static func awakeShortcutBound(_ shortcuts: LossyMap<AwakeActionID, HotkeyCombo>) -> Bool {
        shortcuts[keepAwakeAction] != nil
    }

    /// The Snaptic item's default glyph (stored as ""), and the one it uses instead while a module's own icon
    /// already shows the default (Window Switcher's glyph; ux m16: two identical icons side by side).
    package static let snapticSymbol = "rectangle.on.rectangle"
    package static let snapticAlternateSymbol = "square.grid.2x2"

    /// The Snaptic item's glyph: the stored choice; else the default, or the alternate while one of the own icons
    /// shown (`ownIconSymbols`) is the default glyph.
    package static func sharedSymbol(stored: String, ownIconSymbols: [String]) -> String {
        guard stored.isEmpty else { return stored }
        return ownIconSymbols.contains(snapticSymbol) ? snapticAlternateSymbol : snapticSymbol
    }

    /// What the Menu Bar page stores for a chosen Snaptic glyph: "" (follow the default) only for the default
    /// glyph while it doesn't collide; any other choice, or the default chosen while it collides, is kept as is.
    package static func storedSharedSymbol(chosen: String, ownIconSymbols: [String]) -> String {
        chosen == snapticSymbol && !ownIconSymbols.contains(snapticSymbol) ? "" : chosen
    }

    /// The toast the host shows when the Don't Show fallback (`awakePresenceFallback`) moves Awake back.
    package static var awakeFallbackNotice: String {
        L("Awake is back in the menu bar because its keyboard shortcut is no longer set.")
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
    /// - `awakeShortcutBound`: the Keep Awake shortcut is set (Awake's Don't Show is only safe with it).
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
        var shared: [ModuleID] = []
        var own: [ModuleID] = []
        for id in live where id != .awake {
            switch presence(id) {
            case .inSnapticMenu: shared.append(id)
            case .ownIcon: own.append(id)
            // Only Displays offers "when active"; anywhere else it is an unsanitized value and means an own icon.
            case .ownIconWhenActive: if id != .displays || displaysActive { own.append(id) }
            case .hidden: break
            }
        }

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
    /// nothing to change; also while Awake is off (it shows nothing anyway; the check runs again when it turns on).
    package func awakePresenceFallback(awakeShortcutBound: Bool) -> MenuPresence? {
        isEnabled(.awake) && presence(.awake) == .hidden && !awakeShortcutBound ? .ownIconWhenActive : nil
    }
}
