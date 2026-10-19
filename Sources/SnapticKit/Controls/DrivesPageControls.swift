import Foundation

/// Awake › Drives (J; PLAN 0.3 §4.3 Drives, §2.9): the "Keep drives awake" header switch, the volume list (each
/// row's switch performs the UI-confirmed first write), how often drives are written, and whether they stay awake
/// without a session. New in 0.3: no 0.2 control has its home here.
package enum DrivesPageControls: ControlTable {
    package static let surface = "awake.drives"
    package static let controls: [ControlSpec] = [
        ControlSpec("awake.drives.header", .setting, when: [.module(.awake)], keys: ["features.driveAlive"],
                    search: SearchSpec("Keep drives awake",
                                       keywords: ["drive alive", "external drive", "hard drive", "disk", "spin down",
                                                  "sleep", "usb drive", "keep alive"],
                                       root: SettingsRootID.awake, route: SettingsRoute(surface))),
        ControlSpec("awake.drives.volumes", .list, when: [.module(.awake), .awakeFeature(.driveAlive)],
                    keys: ["drives.volumes"],
                    search: SearchSpec("Drives to keep awake", keywords: ["external drive", "volume", "disk"],
                                       root: SettingsRootID.awake, route: SettingsRoute(surface))),
        ControlSpec("awake.drives.interval", .setting, when: [.module(.awake), .awakeFeature(.driveAlive)],
                    keys: ["drives.intervalSeconds"],
                    search: SearchSpec("Check drives every", keywords: ["drive", "interval", "seconds", "spin down"],
                                       root: SettingsRootID.awake, route: SettingsRoute(surface))),
        ControlSpec("awake.drives.evenWithoutSession", .setting, when: [.module(.awake), .awakeFeature(.driveAlive)],
                    keys: ["drives.evenWithoutSession"],
                    search: SearchSpec("Also when no session is running",
                                       keywords: ["drive", "always", "without session", "keep drives awake"],
                                       root: SettingsRootID.awake, route: SettingsRoute(surface))),
        ControlSpec("awake.drives.write", .button, when: [.module(.awake), .awakeFeature(.driveAlive), .perItem("volume")]),
    ]
}
