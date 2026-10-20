import Foundation

/// General (H; PLAN 0.3 §4.3): the one-time cards, the module chooser shown while every module is off, Open at
/// login, Command-line control (+ Copy Install Command), and backup. Footer: Advanced… (?). 0.3.1 E1a: the welcome
/// card for upgraders (its rows are one-time card actions, listed in `SettingsIndexCoverage.unsearchable`).
package enum GeneralPageControls: ControlTable {
    package static let surface = "general.page"
    package static let controls: [ControlSpec] = [
        ControlSpec("general.page.card.primary", .button, when: [.perItem("card")],
                    replaces: ["l.gen.modules.newDisplaysCard.turnOn"]),
        ControlSpec("general.page.card.dismiss", .button, when: [.perItem("card")],
                    replaces: ["l.gen.modules.newDisplaysCard.notNow"]),
        ControlSpec("general.page.card.v031.openAccessibility", .button, when: [.state(.v031Welcome)]),
        ControlSpec("general.page.card.v031.openScreenRecording", .button, when: [.state(.v031Welcome)]),
        ControlSpec("general.page.card.v031.autoCheck", .button, when: [.state(.v031Welcome)]),
        ControlSpec("general.page.card.v031.notNow", .button, when: [.state(.v031Welcome)]),
        ControlSpec("general.page.card.v031.done", .button, when: [.state(.v031Welcome)]),
        ControlSpec("general.page.modules", .list, when: [.perItem("module")], keys: ["modules.*.enabled"],
                    search: SearchSpec("Choose what Snaptic does",
                                       keywords: ["modules", "window switcher", "displays", "awake", "turn on", "features"],
                                       root: SettingsRootID.general)),
        ControlSpec("general.page.leaveSafeMode", .statusAction, when: [.state(.safeMode)]),
        ControlSpec("general.page.openAtLogin", .setting, replaces: ["l.gen.startup.launchAtLogin"],
                    search: SearchSpec("Open at login", keywords: ["startup", "launch", "login items", "start"],
                                       root: SettingsRootID.general)),
        ControlSpec("general.page.commandLine", .setting, replaces: ["l.gen.cli.enabled"], keys: ["commandLine.enabled"],
                    search: SearchSpec("Command-line control", keywords: ["cli", "terminal", "snaptic command", "scripts"],
                                       root: SettingsRootID.general)),
        ControlSpec("general.page.copyInstall", .button, when: [.parentOn(ControlID("general.page.commandLine"))],
                    replaces: ["l.gen.cli.copyInstall"],
                    search: SearchSpec("Copy Install Command", keywords: ["install", "terminal", "path"],
                                       root: SettingsRootID.general)),
        ControlSpec("general.page.export", .button, replaces: ["l.gen.backup.export"],
                    search: SearchSpec("Export Settings", keywords: ["backup", "save", "file"], root: SettingsRootID.general)),
        ControlSpec("general.page.import", .button, replaces: ["l.gen.backup.import"],
                    search: SearchSpec("Import Settings", keywords: ["backup", "restore", "file"], root: SettingsRootID.general)),
        ControlSpec("general.page.advanced", .button,
                    search: SearchSpec("General Advanced Settings", keywords: ["more", "safe mode", "reset"],
                                       root: SettingsRootID.general)),
    ]
}
