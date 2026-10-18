import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §4.6 + R5-12 (kind S): returns `.nothing`. G
// implements M1 in step 1; the lead wires the hook's result in step 2.

package struct AwakeMigrationResult: Equatable, Sendable {
    /// Empty when nothing to migrate.
    package var triggers: [AwakeTrigger]
    /// 0.2 sleep prevention was effective.
    package var enableModule: Bool
    /// ≤ 8, for the one-time toast; local UI only.
    package var migratedDisplayNames: [String]
    /// R5-12: bind to awake.pauseAutomatic.
    package var pauseRulesShortcut: HotkeyCombo?
    /// R5-12: a 0.2 combo existed and wasn't moved → Recent Notice.
    package var droppedShortcut: Bool

    package init(triggers: [AwakeTrigger], enableModule: Bool, migratedDisplayNames: [String],
                 pauseRulesShortcut: HotkeyCombo? = nil, droppedShortcut: Bool = false) {
        self.triggers = triggers
        self.enableModule = enableModule
        self.migratedDisplayNames = migratedDisplayNames
        self.pauseRulesShortcut = pauseRulesShortcut
        self.droppedShortcut = droppedShortcut
    }

    package static let nothing = AwakeMigrationResult(triggers: [], enableModule: false, migratedDisplayNames: [])
}

package enum AwakeMigration {
    /// M1 over the raw 0.2 Displays JSON. Stub: nothing to migrate.
    package static func fromDisplays(rawJSON: Data?, modulesEnabled: Set<ModuleID>,
                                     awakeShortcuts: LossyMap<AwakeActionID, HotkeyCombo>) -> AwakeMigrationResult {
        .nothing
    }
}
