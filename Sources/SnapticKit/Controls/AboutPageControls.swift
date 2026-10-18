import Foundation

/// About (H; PLAN 0.3 §4.3): version, Check for Updates…, Acknowledgements…, and Display Information… (while
/// Displays runs) or Diagnostics Report….
package enum AboutPageControls: ControlTable {
    package static let surface = "about.page"
    package static let controls: [ControlSpec] = [
        ControlSpec("about.page.checkUpdates", .button, replaces: ["l.gen.about.checkUpdates"],
                    search: SearchSpec("Check for Updates", keywords: ["version", "update", "release", "download"],
                                       root: SettingsRootID.about)),
        ControlSpec("about.page.acknowledgements", .button, replaces: ["l.gen.about.licenses"],
                    search: SearchSpec("Acknowledgements", keywords: ["license", "mit", "credits", "open source"],
                                       root: SettingsRootID.about)),
        ControlSpec("about.page.displayInformation", .button, when: [.module(.displays)]),
        ControlSpec("about.page.diagnostics", .button,
                    search: SearchSpec("Diagnostics Report", keywords: ["report", "problem", "support", "log"],
                                       root: SettingsRootID.about)),
    ]
}
