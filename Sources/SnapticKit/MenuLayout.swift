import Foundation

// Stub (owner: M). Written by the lead in step 0 (kind S): reproduces the 0.2 placement for Window Switcher and
// Displays, and gives Awake a provider item only while it should exist. M replaces it with the 0.3 plan logic
// (§5.2 rules, MenuLayoutTests) in step 1.

extension ModulesConfig {
    package func statusItemPlan(running: Set<ModuleID>, awakeActive: Bool, displaysActive: Bool,
                                awakeShortcutBound: Bool, sharedShownAtRest: Bool) -> StatusItemPlan {
        // 0.2 modules, exactly as 0.2 planned them (Awake contributes no section yet).
        let enabled = enabledModules.filter { $0 != .awake }
        var custom: [ModuleID] = []
        if isEnabled(.awake) && running.contains(.awake) {
            switch presence(.awake) {
            case .ownIcon: custom = [.awake]
            case .ownIconWhenActive: custom = awakeActive ? [.awake] : []
            case .inSnapticMenu, .hidden: custom = []
            }
        }
        guard !enabled.isEmpty else {
            return StatusItemPlan(shared: [], ownIcon: [], showShared: true, noModulesEnabled: true,
                                  everythingHidden: false, custom: custom)
        }
        let live = enabled.filter { running.contains($0) }
        let shared = live.filter { placement($0) == .shared }
        let own = live.filter { placement($0) == .ownIcon }
        let allHidden = enabled.allSatisfy { placement($0) == .hidden }
        return StatusItemPlan(shared: shared, ownIcon: own, showShared: !shared.isEmpty, noModulesEnabled: false,
                              everythingHidden: allHidden, custom: custom)
    }
}
