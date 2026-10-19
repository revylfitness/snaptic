import Foundation

// In-app updates, pure parts (owner: T-update; PLAN 0.3.1 E1, E4): when an install or relaunch must wait, the About
// page's status row and the menu row texts, and the Sparkle defaults keys (the only home of `SU*` key strings, lint
// L19).
//
// Step 0 stub: Snaptic never defers (nothing installs yet), and the texts are empty until T-update lands.

/// An update Sparkle found (gentle reminders): what the menu row and About's status row offer.
package struct UpdateOffer: Equatable, Sendable {
    /// "0.3.2".
    package var version: String
    /// Downloaded, and installs at quit: the menu row reads "Restart to Update Snaptic…".
    package var readyToRestart: Bool

    package init(version: String, readyToRestart: Bool) {
        self.version = version
        self.readyToRestart = readyToRestart
    }
}

package enum UpdatePolicy {
    /// What can hold an install or relaunch back (E4).
    package struct Facts: Equatable, Sendable {
        package var lidModeOn: Bool
        package var displayTrialPending: Bool
        package var safeMode: Bool

        package init(lidModeOn: Bool, displayTrialPending: Bool, safeMode: Bool) {
            self.lidModeOn = lidModeOn
            self.displayTrialPending = displayTrialPending
            self.safeMode = safeMode
        }
    }

    /// nil = go ahead; otherwise the deferral line ("Version 0.3.2 will install when lid-closed mode ends."). Stub:
    /// nil.
    package static func waitText(_ facts: Facts, version: String) -> String? { nil }
}

/// About's status row (E1): "Last checked today at 9:12 AM", "Checking…", "Version 0.3.2 is available.", …,
/// hand-formatted (N12). Stub: empty.
package enum UpdateStatusText {}

/// Snaptic's Sparkle defaults keys: Reset clears them and backups exclude them (E4). Stub: none yet.
package enum UpdateDefaultsKeys {
    package static let all: [String] = []
}
