import Foundation

/// About (H; PLAN 0.3 §4.3): version, Check for Updates…, Acknowledgements…, and Display Information… (while
/// Displays runs) or Diagnostics Report…. 0.3.1 E1, E7: the Updates section (automatic checks and install, the status
/// row's Install and Relaunch…), shown while Sparkle is loaded.
package enum AboutPageControls: ControlTable {
    package static let surface = "about.page"
    package static let controls: [ControlSpec] = [
        ControlSpec("about.page.checkUpdates", .button, replaces: ["l.gen.about.checkUpdates"],
                    search: SearchSpec("Check for Updates", keywords: ["version", "update", "release", "download"],
                                       root: SettingsRootID.about)),
        ControlSpec("about.page.autoCheck", .setting, when: [.state(.updaterAvailable)],
                    search: SearchSpec("Check for updates automatically", keywords: ["updates", "sparkle", "update"],
                                       root: SettingsRootID.about)),
        ControlSpec("about.page.autoInstall", .setting,
                    when: [.state(.updaterAvailable), .parentOn(ControlID("about.page.autoCheck")),
                           .state(.bundleWritable)],
                    search: SearchSpec("Download and install updates automatically", root: SettingsRootID.about)),
        ControlSpec("about.page.installUpdate", .statusAction, when: [.state(.updateAvailable)]),
        ControlSpec("about.page.acknowledgements", .button, replaces: ["l.gen.about.licenses"],
                    search: SearchSpec("Acknowledgements", keywords: ["license", "mit", "credits", "open source"],
                                       root: SettingsRootID.about)),
        ControlSpec("about.page.displayInformation", .button, when: [.module(.displays)]),
        ControlSpec("about.page.diagnostics", .button,
                    search: SearchSpec("Diagnostics Report", keywords: ["report", "problem", "support", "log"],
                                       root: SettingsRootID.about)),
    ]
}
