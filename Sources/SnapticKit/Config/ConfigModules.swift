import Foundation

/// One module's host-level settings (PLAN §3.3, §3.5; 0.3 §5.2, M2).
package struct ModulePreferences: Codable, Equatable, Sendable {
    package var enabled: Bool
    /// Where the module shows in the menu bar (0.3). `placement` and `hideWithoutExternalDisplay` are its 0.2 view.
    package var presence: MenuPresence
    /// A curated SF Symbol for the module's own icon; empty = the module's default.
    package var symbol: String

    /// 0.2 field, derived from `presence` and still written so 0.2 reads it (M2). Setting it maps to a presence,
    /// keeping "when active" when it stays an own icon.
    package var placement: MenuPlacementChoice {
        get { presence.legacyPlacement }
        set { presence = MenuPresence(legacy: newValue, hideWithoutExternalDisplay: hideWithoutExternalDisplay) }
    }

    /// 0.2 field: own icon only while an external display is connected = `.ownIconWhenActive` (M2).
    package var hideWithoutExternalDisplay: Bool {
        get { presence == .ownIconWhenActive }
        set {
            if newValue, presence == .ownIcon { presence = .ownIconWhenActive }
            if !newValue, presence == .ownIconWhenActive { presence = .ownIcon }
        }
    }

    /// The 0.2 form (legacy placement); the defaults and the 0.2 decode path still build preferences with it.
    package init(enabled: Bool, placement: MenuPlacementChoice = .shared, symbol: String = "",
                 hideWithoutExternalDisplay: Bool = false) {
        self.enabled = enabled
        self.presence = MenuPresence(legacy: placement, hideWithoutExternalDisplay: hideWithoutExternalDisplay)
        self.symbol = symbol
    }

    package init(enabled: Bool, presence: MenuPresence, symbol: String = "") {
        self.enabled = enabled
        self.presence = presence
        self.symbol = symbol
    }

    private enum CodingKeys: String, CodingKey { case enabled, presence, placement, symbol, hideWithoutExternalDisplay }

    /// M2 (generic part): without a readable `presence`, the 0.2 placement and hide flag decide. The per-module part
    /// (Awake's own icon → Show When Active) runs in `ModulesConfig.init(from:)`.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lossy(.enabled, true)
        let legacy = MenuPresence(legacy: c.lossy(.placement, .shared),
                                  hideWithoutExternalDisplay: c.lossy(.hideWithoutExternalDisplay, false))
        presence = c.lossy(.presence, legacy)
        symbol = c.lossy(.symbol, "")
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(presence, forKey: .presence)
        try c.encode(placement, forKey: .placement)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(hideWithoutExternalDisplay, forKey: .hideWithoutExternalDisplay)
    }

    /// Whether the stored object carries a `presence` key (decides M2's per-module part).
    fileprivate struct PresenceProbe: Codable, Equatable {
        let hasPresence: Bool
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            hasPresence = ((try? c?.decodeIfPresent(MenuPresence.self, forKey: .presence)) ?? nil) != nil
        }
        func encode(to encoder: Encoder) throws {}
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
    /// 0.2: the "New: Displays" card and "More display features…" item for upgraded users. Kept, decoded and
    /// encoded until 0.4; migration M3 turns it into `newModuleCards`.
    package var showNewDisplaysCard: Bool
    /// One-time General cards still to show (0.3; lossy, de-duplicated).
    package var newModuleCards: [NewModuleCard]
    package var commandLine: CommandLineSettings
    package var otherApps: OtherAppsPolicy
    /// Where onboarding stopped; `.done` once finished (or for upgraded users).
    package var onboarding: OnboardingStep
    /// Permissions chosen during onboarding that still have to be requested.
    package var onboardingPermissions: [Permission]

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
        newModuleCards = []
        commandLine = CommandLineSettings()
        otherApps = .pauseOverlapping
        onboarding = .welcome
        onboardingPermissions = []
    }

    private enum CodingKeys: String, CodingKey {
        case modules, sharedSymbol, showNewDisplaysCard, newModuleCards, commandLine, otherApps, onboarding,
             onboardingPermissions
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var decodedModules: LossyMap<ModuleID, ModulePreferences> = c.lossy(.modules, LossyMap())
        // M2, per module: Awake's own icon without a stored presence (a 0.3 → 0.2 → 0.3 round trip) is its default,
        // Show When Active. Pure mapping while `presence` is absent; nothing to record.
        let probes: LossyMap<ModuleID, ModulePreferences.PresenceProbe> = c.lossy(.modules, LossyMap())
        if var awake = decodedModules[.awake], probes[.awake]?.hasPresence != true, awake.presence == .ownIcon {
            awake.presence = .ownIconWhenActive
            decodedModules[.awake] = awake
        }
        modules = decodedModules
        sharedSymbol = c.lossy(.sharedSymbol, "")
        showNewDisplaysCard = c.lossy(.showNewDisplaysCard, false)
        newModuleCards = c.lossyArray(.newModuleCards, []).uniqued()
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
            if !MenuPresence.allowed(for: id).contains(p.presence) { p.presence = .ownIcon }
            c.modules[id] = p
        }
        c.newModuleCards = newModuleCards.uniqued()
        if !Self.isCuratedSymbol(c.sharedSymbol) { c.sharedSymbol = "" }
        var seen = Set<Permission>()
        c.onboardingPermissions = onboardingPermissions.filter { seen.insert($0).inserted }
        if c.onboarding == .done { c.onboardingPermissions = [] }
        return c
    }

    // MARK: Defaults

    /// A fresh install, per module: every module on; Window Switcher and Displays in the shared menu, Awake shown
    /// when active (0.3 C11).
    package static func defaultPreferences(_ id: ModuleID) -> ModulePreferences {
        switch id {
        case .windowSwitcher, .displays: return ModulePreferences(enabled: true, presence: .inSnapticMenu)
        case .awake: return ModulePreferences(enabled: true, presence: .ownIconWhenActive)
        }
    }

    /// What upgraders get for Awake before migration M1 runs (0.3 C7, §2.13): off, shown when active.
    package static let awakeUpgradePreferences = ModulePreferences(enabled: false, presence: .ownIconWhenActive)

    /// An existing 0.1 user without module settings (PLAN §3.4): the switcher stays on,
    /// Displays is off, and the "New: Displays" card is shown. Awake is inserted off with its "New: Awake" card (0.3 C7).
    package static func upgradeDefaults() -> ModulesConfig {
        var c = ModulesConfig()
        c.modules[.windowSwitcher] = ModulePreferences(enabled: true)
        c.modules[.displays] = ModulePreferences(enabled: false)
        c.modules[.awake] = awakeUpgradePreferences
        c.showNewDisplaysCard = true
        c.newModuleCards = [.displays, .awake]
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
        if id == .displays && enabled {
            showNewDisplaysCard = false
            newModuleCards.removeAll { $0 == .displays }
        }
    }

    package func presence(_ id: ModuleID) -> MenuPresence { preferences(id).presence }

    package mutating func setPresence(_ presence: MenuPresence, for id: ModuleID) {
        var p = preferences(id)
        p.presence = MenuPresence.allowed(for: id).contains(presence) ? presence : .ownIcon
        modules[id] = p
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
            p.presence = Self.defaultPreferences(id).presence
            p.symbol = ""
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
    /// Provider-built items that should exist now (Awake; 0.3 §5.2).
    package var custom: [ModuleID]
    /// The compact Awake section goes into the Snaptic item (§5.4).
    package var awakeCompactInShared: Bool
    /// N11: the Snaptic glyph shows its active variant (awake governing && showShared).
    package var sharedActiveGlyph: Bool
    /// The Snaptic item is absent: Recent Notices and Quit go into every own and custom menu.
    package var sharedFooterInOwnMenus: Bool

    package init(shared: [ModuleID], ownIcon: [ModuleID], showShared: Bool, noModulesEnabled: Bool,
                 everythingHidden: Bool, custom: [ModuleID] = [], awakeCompactInShared: Bool = false,
                 sharedActiveGlyph: Bool = false, sharedFooterInOwnMenus: Bool = false) {
        self.shared = shared
        self.ownIcon = ownIcon
        self.showShared = showShared
        self.noModulesEnabled = noModulesEnabled
        self.everythingHidden = everythingHidden
        self.custom = custom
        self.awakeCompactInShared = awakeCompactInShared
        self.sharedActiveGlyph = sharedActiveGlyph
        self.sharedFooterInOwnMenus = sharedFooterInOwnMenus
    }
}

extension ModulesConfig {
    /// The 0.2 entry point (r3 consistency m7; its tests pin the 0.2 placement): the MenuLayout plan with Awake idle,
    /// Displays active and the Snaptic item shown at rest.
    package func statusItemPlan(running: Set<ModuleID>) -> StatusItemPlan {
        statusItemPlan(running: running, awakeActive: false, displaysActive: true, awakeShortcutBound: false,
                       sharedShownAtRest: true)
    }

    /// Whether the menu bar has a Snaptic item at rest (a module set to Show in Snaptic Menu, Awake's compact rows,
    /// or "No Modules Are On"). Without one, the Menu Bar page's Snaptic icon tiles have nothing to change
    /// (review6 ux nit 7).
    package func hasSnapticItem(running: Set<ModuleID>) -> Bool {
        let plan = statusItemPlan(running: running, awakeActive: false, displaysActive: false, awakeShortcutBound: true,
                                  sharedShownAtRest: false)
        return plan.showShared || plan.noModulesEnabled
    }
}

extension ModulesConfig {
    /// Every icon that could show is the Displays icon set to "Hide the icon when no
    /// external display is connected": without an external display nothing shows in the
    /// menu bar (General → Menu warns). "Everything hidden" has its own notice.
    /// Awake shown only when active doesn't count: it isn't there at rest either.
    package var iconsNeedExternalDisplay: Bool {
        let shown = enabledModules.filter { id in
            presence(id) != .hidden && !(id == .awake && presence(id) == .ownIconWhenActive)
        }
        guard !shown.isEmpty else { return false }
        return shown.allSatisfy { id in id == .displays && presence(id) == .ownIconWhenActive }
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

extension ModulesConfig {
    /// M3 (R5-2): `showNewDisplaysCard == true` → `newModuleCards` gains `.displays`. Runs iff `newModuleCards.v1`
    /// is absent, then records it. Pure; ModuleHost runs it.
    package func migrated(ledger: inout MigrationLedger) -> ModulesConfig {
        guard !ledger.has(.newModuleCards) else { return self }
        var c = self
        if c.showNewDisplaysCard && !c.newModuleCards.contains(.displays) { c.newModuleCards.append(.displays) }
        ledger.record(.newModuleCards)
        return c
    }

    /// §2.13 (R5-2 step 4): a 0.1/0.2 upgrader gets Awake **off** with its "New: Awake" card, once. Runs iff
    /// `awakeUpgrade.v1` is absent, then records it whatever it decided. It inserts only when module settings
    /// existed before this launch (`modulesExisted`; a 0.2 store never holds an Awake entry) and hold no Awake
    /// entry. A fresh install records the marker on its first launch (`modulesExisted == false`), so its later
    /// launches, and General › Reset (which keeps the ledger), keep the per-id default (Awake on). A 0.1 user
    /// without module settings gets the same entry from `upgradeDefaults()`. Pure; ModuleHost runs it, before M1.
    ///
    /// A ledger that already holds `fromDisplays.v1` (M1's marker, recorded on every 0.3 launch, after this step) means
    /// a 0.3 build ran before: a 0.3 install, not a 0.1/0.2 upgrade. That covers testers of 0.3 builds from before
    /// this marker existed (review5 ui N1), whose fresh install would otherwise read as an upgrade once.
    package func insertingAwakeForUpgrader(modulesExisted: Bool, ledger: inout MigrationLedger) -> ModulesConfig {
        guard !ledger.has(.awakeUpgrade) else { return self }
        let zeroThreeRanBefore = ledger.has(.fromDisplays)
        ledger.record(.awakeUpgrade)
        guard modulesExisted, !zeroThreeRanBefore, modules[.awake] == nil else { return self }
        var c = self
        c.modules[.awake] = Self.awakeUpgradePreferences
        // C7: upgraders see "New: Awake" on General (hidden by H's card rules once M1 migrated or Awake is on).
        if !c.newModuleCards.contains(.awake) { c.newModuleCards.append(.awake) }
        return c
    }
}
