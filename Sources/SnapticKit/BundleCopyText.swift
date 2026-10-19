import Foundation

// What Snaptic says about the copy of itself that runs (owner: T-lid-app; PLAN 0.3.1 B1, B6): the Permissions page's
// lid-closed siblings, kept in one place so every warning about this copy of Snaptic reads the same.

package enum BundleCopyText {
    /// B1: under "Keep awake with the lid closed" while it's on and this account can change Snaptic's bundle.
    package static let lidWritable = L("Your account can change this copy of Snaptic, so another app could change it and misuse the password prompt.")
    /// B1: shown instead of the toggle in a translocated copy (the Permissions page's warning has the same start).
    package static let lidTranslocated = L("Snaptic is running from a temporary location. Move it to Applications to use lid-closed mode.")
    /// B1: the Lid closed section's footer; its Learn More… link follows it.
    package static let lidFooter = L("While lid-closed mode is on, your Mac can’t sleep for low battery or heat. Awake turns it off at the Awake page’s battery level (at least 10%), when your Mac gets hot, or after 24 hours. Use it on a hard surface, not in a bag.")
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
