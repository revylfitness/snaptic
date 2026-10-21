import Foundation

// What Snaptic says about the copy of itself that runs (owner: T-lid-app; PLAN 0.3.1 B1, B6): the Permissions page's
// lid-closed sibling, kept in one place so every warning about this copy of Snaptic reads the same, and the README
// links of the Lid closed section (on the Awake page from 0.3.3). Its translocated row and footer are
// `AwakeLidText.translocated` and `footer`.

package enum BundleCopyText {
    /// B1: under "Keep awake with the lid closed" while it's on and this account can change Snaptic's bundle.
    package static let lidWritable = L("Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt.")
    /// README headings the lid-closed Learn More… links open (their anchors are GitHub's slugs, `SettingsHelpAnchors`):
    /// the feature, the password and what runs as root (B6), and recovering from sleep left off (B3.4).
    package static let lidHeading = "Keeping awake with the lid closed"
    package static let passwordHeading = "Your password and what runs as root"
    package static let leftoverHeading = "If sleep stays off"

    /// The README at `lidHeading` (the Lid closed footer's Learn More…).
    package static var lidHelpURL: String { readme(at: lidHeading) }
    /// The README at `passwordHeading` (the writable-bundle note's Learn More…).
    package static var passwordHelpURL: String { readme(at: passwordHeading) }
    /// The README at `leftoverHeading`.
    package static var leftoverHelpURL: String { readme(at: leftoverHeading) }

    private static func readme(at heading: String) -> String {
        SettingsHelpAnchors.readme + "#" + SettingsHelpAnchors.slug(heading)
    }
}
