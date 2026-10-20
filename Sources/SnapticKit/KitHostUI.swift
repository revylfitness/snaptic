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

    /// A permission missing although Snaptic ran here before: macOS most likely still
    /// lists an older copy (an update or a rebuild changes the signature), so the guide
    /// shows the remove-and-add-again steps at once instead of after 30 seconds. 0.3.1 E2: Screen Recording too,
    /// because the switch to Developer ID signing resets both grants once.
    package static func showsReAddStepsAtOnce(_ permission: Permission, launchedBefore: Bool, granted: Bool) -> Bool {
        launchedBefore && !granted
    }

    /// 0.3.1 E1a: the welcome card's re-grant rows, in `Permission` order: what the running modules need and macOS no
    /// longer grants (the launched-before heuristic; Snaptic never recorded what was granted before).
    package static func regrantRows(needed: Set<Permission>, granted: Set<Permission>) -> [Permission] {
        Permission.allCases.filter { needed.contains($0) && !granted.contains($0) }
    }

    /// 0.3.1 E1a: the welcome card hides itself once the update choice is made (or this build can't update itself)
    /// and nothing is left to grant again.
    package static func welcomeFinished(updateChoiceMade: Bool, regrantRows: [Permission]) -> Bool {
        updateChoiceMade && regrantRows.isEmpty
    }
}
