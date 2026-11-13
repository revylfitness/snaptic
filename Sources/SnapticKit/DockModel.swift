import Foundation

// Dock Previews' shared Kit types (lead; PLAN 0.5 §2.1, H6). K1 adds the kill-switch features; the hover, click and
// key rules arrive in K3 as their own files.

/// Per-feature kill switches (H6): `Dock.disable.<rawValue>` = true in Snaptic's persistent domain turns the feature
/// off, read with `KillSwitches.read(domain, prefix: "Dock", as: DockFeature.self)` once per batch (no polling).
/// `Modules.disable.dockPreviews` turns off the whole module.
package enum DockFeature: String, Codable, CaseIterable, Sendable {
    /// The opt-in Dock click actions (§4.11); also read on each mouse-up the resolver would act on (D2-15).
    case clickActions
    /// Keyboard shortcuts in previews (§4.5).
    case keys
}
