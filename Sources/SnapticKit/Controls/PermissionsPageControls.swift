import Foundation

/// Permissions (H; PLAN 0.3 §4.3): one row per permission with its state, who needs it and Open Privacy Settings…,
/// the Removable Volumes note while Drive Alive is on, and this copy of Snaptic (location, signer, relaunch).
package enum PermissionsPageControls: ControlTable {
    package static let surface = "permissions.page"
    package static let controls: [ControlSpec] = [
        ControlSpec("permissions.page.accessibility", .button,
                    replaces: ["l.gen.permissions.rows", "l.gen.permissions.openSettings", "l.sw.permissionRows",
                               "l.d.features.permissionRows"],
                    search: SearchSpec("Accessibility", keywords: ["permission", "privacy", "allow", "keys", "windows"],
                                       root: SettingsRootID.permissions)),
        ControlSpec("permissions.page.screenRecording", .button,
                    search: SearchSpec("Screen Recording", keywords: ["permission", "privacy", "thumbnails", "capture"],
                                       root: SettingsRootID.permissions)),
        ControlSpec("permissions.page.showInFinder", .button),
        ControlSpec("permissions.page.relaunch", .button, replaces: ["l.gen.permissions.relaunch"],
                    search: SearchSpec("Relaunch Snaptic", keywords: ["restart", "quit", "reopen"],
                                       root: SettingsRootID.permissions)),
    ]
}
