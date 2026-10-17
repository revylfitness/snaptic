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

/// Host settings under `SnapticModulesV1`: which modules run, where their menus go, the
/// per-item menu choices of the Menu page, and the other General settings (R5.1).
package struct ModulesConfig: ConfigModel {
    package var modules: LossyMap<ModuleID, ModulePreferences>
    /// Menu customization (General → Menu): Visible / In submenu / Hidden per item.
    package var menuItems: LossyMap<DisplayMenuItemID, MenuItemVisibility>
    /// Icon of the shared status item; empty = Snaptic's icon.
    package var sharedSymbol: String
    /// "Scroll on a slider to adjust" for menu sliders.
    package var scrollSlidersToAdjust: Bool
    /// The "New: Displays" card and "More display features…" item for upgraded users.
    package var showNewDisplaysCard: Bool
    package var commandLine: CommandLineSettings

    package static let maxMenuItems = 256
    package static let maxSymbolLength = 64

    /// SF Symbols offered for status icons (General → Menu).
    package static let curatedSymbols = [
        "rectangle.on.rectangle", "rectangle.stack", "macwindow.on.rectangle", "square.grid.2x2",
        "display", "display.2", "sun.max", "sun.min", "slider.horizontal.3", "dial.low",
        "rectangle.split.3x1", "circle.grid.cross", "bolt", "sparkles",
    ]

    package init() {
        modules = LossyMap()
        menuItems = LossyMap()
        sharedSymbol = ""
        scrollSlidersToAdjust = true
        showNewDisplaysCard = false
        commandLine = CommandLineSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case modules, menuItems, sharedSymbol, scrollSlidersToAdjust, showNewDisplaysCard, commandLine
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modules = c.lossy(.modules, LossyMap())
        menuItems = c.lossy(.menuItems, LossyMap())
        sharedSymbol = c.lossy(.sharedSymbol, "")
        scrollSlidersToAdjust = c.lossy(.scrollSlidersToAdjust, true)
        showNewDisplaysCard = c.lossy(.showNewDisplaysCard, false)
        commandLine = c.lossy(.commandLine, CommandLineSettings())
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
        var items: [DisplayMenuItemID: MenuItemVisibility] = [:]
        for key in c.menuItems.values.keys.sorted(by: { $0.rawValue < $1.rawValue })
        where Self.isValidMenuItemID(key) && items.count < Self.maxMenuItems {
            items[key] = c.menuItems.values[key]
        }
        c.menuItems = LossyMap(items)
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
        return c
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

    /// The user's choice for a menu item, or the contributor's default.
    package func visibility(of item: DisplayMenuItemID, default fallback: MenuItemVisibility) -> MenuItemVisibility {
        menuItems[item] ?? fallback
    }

    /// Stores a choice; choosing the default removes the entry so defaults can change later.
    package mutating func setVisibility(_ visibility: MenuItemVisibility, of item: DisplayMenuItemID,
                                        default fallback: MenuItemVisibility) {
        guard Self.isValidMenuItemID(item) else { return }
        menuItems[item] = visibility == fallback ? nil : visibility
    }

    package mutating func resetMenu() {
        menuItems = LossyMap()
        sharedSymbol = ""
        scrollSlidersToAdjust = true
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

    /// 1–64 characters from [A-Za-z0-9._-], like "c.brightness" or "d.resolution.slider".
    package static func isValidMenuItemID(_ id: DisplayMenuItemID) -> Bool {
        let utf8 = id.rawValue.utf8
        guard !utf8.isEmpty, utf8.count <= 64 else { return false }
        return utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || byte == 0x2E || byte == 0x5F || byte == 0x2D
        }
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

/// Start/stop decisions for the host (PLAN §3.3): stops run in reverse start order.
package enum ModuleTransitions {
    package static func plan(order: [ModuleID], running: Set<ModuleID>, desired: Set<ModuleID>)
        -> (stop: [ModuleID], start: [ModuleID]) {
        let stop = order.reversed().filter { running.contains($0) && !desired.contains($0) }
        let start = order.filter { desired.contains($0) && !running.contains($0) }
        return (Array(stop), start)
    }
}
