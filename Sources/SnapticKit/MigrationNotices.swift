import Foundation

// What the host says and decides around migration M1 (lead; 0.3 §4.6, R5-12, C7): the one-time toast at the first
// activation of a migrated rule, and the Recent Notice for a 0.2 shortcut that wasn't moved.

package enum MigrationNotices {
    /// The Settings location the M1 toast's button opens.
    package static let awakePage = "awake"

    /// "Keeping your Mac awake while “DELL U2720Q” is connected is now part of Awake."
    package static func movedText(displayNames: [String]) -> String {
        let names = displayNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let subject: String
        switch names.count {
        case 0: subject = L("a display")
        case 1: subject = "“" + names[0] + "”"
        case 2: subject = "“" + names[0] + "”" + L(" or ") + "“" + names[1] + "”"
        default: subject = "“" + names[0] + "”" + L(" or another display")
        }
        return L("Keeping your Mac awake while ") + subject + L(" is connected is now part of Awake.")
    }

    package static var showInSettingsTitle: String { L("Show in Settings") }

    /// R5-12: the 0.2 "toggle display sleep prevention" combo existed and wasn't moved to Pause Rules.
    package static var droppedShortcutText: String {
        L("Your display sleep shortcut was removed. Set Awake shortcuts in Settings › Awake › Keyboard Shortcuts.")
    }

    /// The host watches rule activations for the M1 toast while M1 ran, its toast hasn't been recorded, and one of
    /// the rules it made is still configured.
    package static func needsToastWatch(ledger: MigrationLedger, migratedRuleIDs: Set<StableID>,
                                        configuredRuleIDs: Set<StableID>) -> Bool {
        ledger.has(.fromDisplays) && !ledger.has(.fromDisplaysToast)
            && !migratedRuleIDs.isDisjoint(with: configuredRuleIDs)
    }

    /// The M1 toast is due: it hasn't been recorded and a migrated rule is active.
    package static func toastDue(ledger: MigrationLedger, migratedRuleIDs: Set<StableID>,
                                 activeRuleIDs: [StableID]) -> Bool {
        ledger.has(.fromDisplays) && !ledger.has(.fromDisplaysToast)
            && activeRuleIDs.contains { migratedRuleIDs.contains($0) }
    }
}

extension AwakeMigrationResult {
    /// The writer's view of M1 (R5-12, §4.6): rules replaced by id; module, `triggers` and the General card on when
    /// sleep prevention was effective; the 0.2 combo bound to Pause Rules when M1 moved it. The 0.2 entry in
    /// `keys.shortcuts` is never touched (a 0.2 downgrade still reads it). Returns whether the module was turned on.
    package func apply(to awake: inout AwakeConfig, modules: inout ModulesConfig) -> Bool {
        let ids = Set(triggers.map(\.id))
        awake.triggers.triggers = awake.triggers.triggers.filter { !ids.contains($0.id) } + triggers
        if let combo = pauseRulesShortcut, awake.shortcuts[.pauseAutomatic] == nil {
            awake.shortcuts[.pauseAutomatic] = combo
        }
        guard enableModule else { return false }
        awake.features[.triggers] = true
        modules.modules[.awake] = ModulePreferences(enabled: true, presence: .ownIconWhenActive)
        if !modules.newModuleCards.contains(.awakeMigrated) { modules.newModuleCards.append(.awakeMigrated) }
        return true
    }
}
