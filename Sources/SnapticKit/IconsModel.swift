import Foundation

// Hidden Icons' shared vocabulary (lead; PLAN 0.4 §2). K1 holds what the stores and the kill switches need; K2 adds
// the inventory, layout and engine types.

/// The three sections of the menu bar, from the arrow's point of view (§4.1). Raw values are persisted (the layout
/// cache and `knownBundles` in `SnapticIconsAppsV1`).
package enum IconsSection: String, Codable, CaseIterable, Sendable {
    /// Right of the arrow: always shown.
    case shown
    /// Between the divider and the arrow: hidden while collapsed.
    case hidden
    /// Left of the divider: hidden even while expanded, when Always Hidden is on.
    case alwaysHidden
}

/// Per-feature kill switches (H3): `Icons.disable.<rawValue>` = true in Snaptic's persistent domain turns the feature
/// off (`KillSwitches.read(prefix: "Icons")`). `Modules.disable.hiddenIcons` turns off the whole module.
package enum IconsFeature: String, Codable, CaseIterable, Sendable {
    /// The macOS 27 engine (`MBAssessmentModeAssertion`); also observed live and re-read before each collapse.
    case native
    /// The macOS 14–26 engine (separator lengths); also observed live.
    case length
    /// Accessibility reads of other apps' menu bar extras (Sections, the hidden list, new-icon detection).
    case inventory
    /// Show icons on hover.
    case hover
    /// Opening a hidden icon's menu from the hidden list (AXPress).
    case axpress

    package static let prefix = "Icons"
}
