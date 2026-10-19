import Foundation

/// General › Advanced… (H; PLAN 0.3 §4.3): commands can skip confirmation, exit codes, Safe Mode; footer Reset All
/// Settings….
package enum GeneralAdvancedSheetControls: ControlTable {
    package static let surface = "general.advanced"
    package static let sheet = "general.advanced"
    package static let controls: [ControlSpec] = [
        ControlSpec("general.advanced.skipConfirmation", .setting, when: [.state(.commandLineOn)],
                    replaces: ["l.gen.cli.maySkipConfirmation"], keys: ["commandLine.maySkipConfirmation"],
                    search: SearchSpec("Commands can skip confirmation", keywords: ["--yes", "confirm", "cli", "terminal"],
                                       root: SettingsRootID.general, sheet: sheet)),
        ControlSpec("general.advanced.exitCodes", .button, replaces: ["l.gen.cli.exitCodes"],
                    search: SearchSpec("Exit codes", keywords: ["cli", "scripts", "json"], root: SettingsRootID.general,
                                       sheet: sheet)),
        ControlSpec("general.advanced.safeMode", .button, replaces: ["l.gen.safeMode.restart", "l.gen.safeMode.leave"],
                    search: SearchSpec("Safe Mode", keywords: ["restart", "troubleshoot", "problem"],
                                       root: SettingsRootID.general, sheet: sheet)),
        ControlSpec("general.advanced.resetAll", .button, replaces: ["l.gen.backup.resetAll"],
                    search: SearchSpec("Reset All Settings", keywords: ["defaults", "erase", "start over"],
                                       root: SettingsRootID.general, sheet: sheet)),
    ]
}
