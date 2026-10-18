import Foundation

/// Small host UI decisions, here so they can be tested (FIXES-R2 W5, W16, W18).
package enum HostUIRules {
    /// Pages to fall back to, in order, when the selected Settings page went away.
    package static let settingsFallbacks = ["displays.features", "general.modules"]

    /// The Settings page to show: the selection while it exists, otherwise the first
    /// fallback that exists, otherwise the first page (nil only without pages).
    package static func settingsSelection(_ selection: String?, available: [String],
                                          fallbacks: [String] = settingsFallbacks) -> String? {
        if let selection, available.contains(selection) { return selection }
        return fallbacks.first(where: { available.contains($0) }) ?? available.first
    }

    /// Whether a status item we asked to show really shows. From macOS 27 the system can
    /// hide items itself (Menu Bar settings) while `isVisible` stays true, so there its
    /// window must be on screen too; unknown counts as hidden (Settings opens instead).
    package static func statusItemShows(isVisible: Bool, osMajor: Int, windowOnScreen: Bool?) -> Bool {
        guard isVisible else { return false }
        guard osMajor >= 27 else { return true }
        return windowOnScreen ?? false
    }

    /// Accessibility missing although Snaptic ran here before: macOS most likely still
    /// lists an older copy (an update or a rebuild changes the signature), so the guide
    /// shows the remove-and-add-again steps at once instead of after 30 seconds.
    package static func showsReAddStepsAtOnce(_ permission: Permission, launchedBefore: Bool, granted: Bool) -> Bool {
        permission == .accessibility && launchedBefore && !granted
    }
}
