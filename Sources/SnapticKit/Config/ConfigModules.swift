import Foundation

/// One module's host-level settings (PLAN §3.3, §3.5).
package struct ModulePreferences: Codable, Equatable, Sendable {
    package var enabled: Bool
    package var placement: MenuPlacementChoice
    /// A curated SF Symbol for the module's own icon; empty = the module's default.
    package var symbol: String
    /// Own-icon placement only: hide the icon while no external display is connected.
    package var hideWithoutExternalDisplay: Bool

    package init(enabled: Bool, placement: MenuPlacementChoice = .shared, symbol: String = "",
                 hideWithoutExternalDisplay: Bool = false) {
        self.enabled = enabled
        self.placement = placement
        self.symbol = symbol
        self.hideWithoutExternalDisplay = hideWithoutExternalDisplay
    }

    private enum CodingKeys: String, CodingKey { case enabled, placement, symbol, hideWithoutExternalDisplay }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lossy(.enabled, true)
        placement = c.lossy(.placement, .shared)
        symbol = c.lossy(.symbol, "")
        hideWithoutExternalDisplay = c.lossy(.hideWithoutExternalDisplay, false)
    }
}

/// Command-line control (PLAN §11); the server arrives with step 2.
package struct CommandLineSettings: Codable, Equatable, Sendable {
    package var enabled: Bool
    /// Trials skip the confirmation panel when the CLI asks them to (default off).
    package var maySkipConfirmation: Bool

    package init(enabled: Bool = false, maySkipConfirmation: Bool = false) {
        self.enabled = enabled
        self.maySkipConfirmation = maySkipConfirmation
    }

    private enum CodingKeys: String, CodingKey { case enabled, maySkipConfirmation }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lossy(.enabled, false)
        maySkipConfirmation = c.lossy(.maySkipConfirmation, false)
    }
}

/// What to do while another display app (BetterDisplay, MonitorControl, Lunar) runs
/// (PLAN §3.8).
package enum OtherAppsPolicy: String, Codable, CaseIterable, Sendable {
    /// "Pause overlapping Snaptic features" (default).
    case pauseOverlapping
    /// "Run both anyway".
    case runBoth
}

/// First-run onboarding progress (PLAN §3.7). Saved after every step, so onboarding
/// resumes after a relaunch (permission grants on macOS 27 often need one).
package enum OnboardingStep: String, Codable, CaseIterable, Sendable {
    case welcome, modules, displays, permissions, done
}

/// Host settings under `SnapticModulesV1`: which modules run, where their menus go, and
/// the other General settings (R5.1). Per-item Displays menu choices live in
/// `DisplaysConfig.menu` (MenuConfig), the single source of truth.
package struct ModulesConfig: ConfigModel {
    package var modules: LossyMap<ModuleID, ModulePreferences>
    /// Icon of the shared status item; empty = Snaptic's icon.
    package var sharedSymbol: String
    /// The "New: Displays" card and "More display features…" item for upgraded users.
    package var showNewDisplaysCard: Bool
    package var commandLine: CommandLineSettings
    package var otherApps: OtherAppsPolicy
    /// Where onboarding stopped; `.done` once finished (or for upgraded users).
    package var onboarding: OnboardingStep
    /// Permissions chosen during onboarding that still have to be requested.
    package var onboardingPermissions: [Permission]

    package static let maxSymbolLength = 64

    /// SF Symbols offered for status icons (General → Menu).
    package static let curatedSymbols = [
        "rectangle.on.rectangle", "rectangle.stack", "macwindow.on.rectangle", "square.grid.2x2",
        "display", "display.2", "sun.max", "sun.min", "slider.horizontal.3", "dial.low",
        "rectangle.split.3x1", "circle.grid.cross", "bolt", "sparkles",
    ]

    package init() {
        modules = LossyMap()
        sharedSymbol = ""
        showNewDisplaysCard = false
        commandLine = CommandLineSettings()
        otherApps = .pauseOverlapping
        onboarding = .welcome
        onboardingPermissions = []
    }

    private enum CodingKeys: String, CodingKey {
        case modules, sharedSymbol, showNewDisplaysCard, commandLine, otherApps, onboarding, onboardingPermissions
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modules = c.lossy(.modules, LossyMap())
        sharedSymbol = c.lossy(.sharedSymbol, "")
        showNewDisplaysCard = c.lossy(.showNewDisplaysCard, false)
        commandLine = c.lossy(.commandLine, CommandLineSettings())
        otherApps = c.lossy(.otherApps, .pauseOverlapping)
        // A missing or unreadable step means an older Snaptic: nothing to resume.
        onboarding = c.lossy(.onboarding, .done)
        let names: [String] = c.lossy(.onboardingPermissions, [])
        onboardingPermissions = names.compactMap { Permission(rawValue: $0) }
    }

    package func sanitized() -> ModulesConfig {
        var c = self
        c.modules.dropUnknown(keepingAtMost: 16)
        for (id, prefs) in c.modules.values {
            var p = prefs
            if !Self.isCuratedSymbol(p.symbol) { p.symbol = "" }
            c.modules[id] = p
        }
        if !Self.isCuratedSymbol(c.sharedSymbol) { c.sharedSymbol = "" }
        var seen = Set<Permission>()
        c.onboardingPermissions = onboardingPermissions.filter { seen.insert($0).inserted }
        if c.onboarding == .done { c.onboardingPermissions = [] }
        return c
    }

    // MARK: Defaults

    /// A fresh install: every module on, all in the shared menu.
    package static func defaultPreferences(_ id: ModuleID) -> ModulePreferences {
        ModulePreferences(enabled: true)
    }

    /// An existing 0.1 user without module settings (PLAN §3.4): the switcher stays on,
    /// Displays is off, and the "New: Displays" card is shown.
    package static func upgradeDefaults() -> ModulesConfig {
        var c = ModulesConfig()
        c.modules[.windowSwitcher] = ModulePreferences(enabled: true)
        c.modules[.displays] = ModulePreferences(enabled: false)
        c.showNewDisplaysCard = true
        c.onboarding = .done
        return c
    }

    /// What a launch without stored module settings starts from (PLAN §3.4): a new user
    /// gets the fresh defaults (onboarding at Welcome), an earlier 0.1 user the upgrade
    /// defaults. A fresh value equals `init()`, so the store must write it with
    /// `save(force: true)`: otherwise a user who quits at Welcome is an "upgrader" next time.
    package static func firstRun(launchedBefore: Bool) -> ModulesConfig {
        launchedBefore ? upgradeDefaults() : ModulesConfig()
    }

    // MARK: Queries

    package func preferences(_ id: ModuleID) -> ModulePreferences {
        modules[id] ?? Self.defaultPreferences(id)
    }

    package func isEnabled(_ id: ModuleID) -> Bool { preferences(id).enabled }

    package func placement(_ id: ModuleID) -> MenuPlacementChoice { preferences(id).placement }

    /// Enabled modules in start order (`ModuleID.allCases`).
    package var enabledModules: [ModuleID] { ModuleID.allCases.filter { isEnabled($0) } }

    package mutating func setEnabled(_ enabled: Bool, for id: ModuleID) {
        var p = preferences(id)
        p.enabled = enabled
        modules[id] = p
        if id == .displays && enabled { showNewDisplaysCard = false }
    }

    package mutating func setPlacement(_ placement: MenuPlacementChoice, for id: ModuleID) {
        var p = preferences(id)
        p.placement = placement
        modules[id] = p
    }

    package mutating func setSymbol(_ symbol: String, for id: ModuleID) {
        var p = preferences(id)
        p.symbol = Self.isCuratedSymbol(symbol) ? symbol : ""
        modules[id] = p
    }

    /// Placements and icons back to defaults (the Displays item choices reset separately,
    /// in MenuConfig).
    package mutating func resetMenu() {
        sharedSymbol = ""
        for id in ModuleID.allCases {
            var p = preferences(id)
            p.placement = .shared
            p.symbol = ""
            p.hideWithoutExternalDisplay = false
            modules[id] = p
        }
    }

    // MARK: Validation

    package static func isCuratedSymbol(_ symbol: String) -> Bool {
        symbol.isEmpty || curatedSymbols.contains(symbol)
    }

    // MARK: Onboarding

    package var needsOnboarding: Bool { onboarding != .done }

    /// The steps shown, in order: the Displays step only while Displays is on.
    package func onboardingSteps() -> [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .displays || isEnabled(.displays) }
    }

    /// The step after `step` (`.done` after the last one).
    package func step(after step: OnboardingStep) -> OnboardingStep {
        let steps = onboardingSteps()
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return .done }
        return steps[i + 1]
    }

    /// A saved step that no longer applies (Displays turned off meanwhile) moves on.
    package var resumeStep: OnboardingStep {
        onboardingSteps().contains(onboarding) ? onboarding : step(after: .modules)
    }
}

/// Which status items exist and what each one shows (PLAN §3.5).
package struct StatusItemPlan: Equatable, Sendable {
    /// Running modules whose sections go into the shared item, in start order.
    package var shared: [ModuleID]
    /// Running modules with their own icon, in start order.
    package var ownIcon: [ModuleID]
    /// The shared item exists (also when no module is enabled).
    package var showShared: Bool
    /// No module is enabled: the shared menu says so and offers Settings.
    package var noModulesEnabled: Bool
    /// Modules are enabled but every one is hidden: no status item at all, so a relaunch
    /// (or the CLI) opens Settings.
    package var everythingHidden: Bool

    package init(shared: [ModuleID], ownIcon: [ModuleID], showShared: Bool, noModulesEnabled: Bool,
                 everythingHidden: Bool) {
        self.shared = shared
        self.ownIcon = ownIcon
        self.showShared = showShared
        self.noModulesEnabled = noModulesEnabled
        self.everythingHidden = everythingHidden
    }
}

extension ModulesConfig {
    package func statusItemPlan(running: Set<ModuleID>) -> StatusItemPlan {
        let enabled = enabledModules
        guard !enabled.isEmpty else {
            return StatusItemPlan(shared: [], ownIcon: [], showShared: true, noModulesEnabled: true, everythingHidden: false)
        }
        let live = enabled.filter { running.contains($0) }
        let shared = live.filter { placement($0) == .shared }
        let own = live.filter { placement($0) == .ownIcon }
        let allHidden = enabled.allSatisfy { placement($0) == .hidden }
        return StatusItemPlan(shared: shared, ownIcon: own, showShared: !shared.isEmpty, noModulesEnabled: false,
                              everythingHidden: allHidden)
    }
}

extension ModulesConfig {
    /// Every icon that could show is the Displays icon set to "Hide the icon when no
    /// external display is connected": without an external display nothing shows in the
    /// menu bar (General → Menu warns). "Everything hidden" has its own notice.
    package var iconsNeedExternalDisplay: Bool {
        let shown = enabledModules.filter { placement($0) != .hidden }
        guard !shown.isEmpty else { return false }
        return shown.allSatisfy { id in
            id == .displays && placement(id) == .ownIcon && preferences(id).hideWithoutExternalDisplay
        }
    }
}

/// Start/stop decisions for the host (PLAN §3.3): stops run in reverse start order.
package enum ModuleTransitions {
    package static func plan(order: [ModuleID], running: Set<ModuleID>, desired: Set<ModuleID>)
        -> (stop: [ModuleID], start: [ModuleID]) {
        let stop = order.reversed().filter { running.contains($0) && !desired.contains($0) }
        let start = order.filter { desired.contains($0) && !running.contains($0) }
        return (Array(stop), start)
    }
}
