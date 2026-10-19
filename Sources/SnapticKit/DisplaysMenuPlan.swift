import Foundation

// Where every Displays menu item goes in 0.3 (owner: M; PLAN 0.3 §4.8 "0.2 menu", §5.2). The contributors build
// the items (one `DisplayMenuItemID` each, possibly several items per id); `DisplaysMenuBuilder` and
// `DisplayMenuBlock` place them with this table, and the Customize Displays Menu sheet lists its rows. Pure data
// and rules, so the placement of all 46 frozen 0.2 menu ids is tested on Linux.

/// The groups of a display's submenu, in menu order; a separator goes between non-empty groups (§5.2).
package enum DisplaySubmenuGroup: Int, CaseIterable, Comparable, Sendable {
    /// Modes (≤ 8), "More Resolutions…", Undo/Redo.
    case resolution
    /// Use as Main Display, Mirror “X”.
    case arrangement
    /// The opt-in checkmark toggles (High Dynamic Range … Show in Picture in Picture).
    case options
    /// "Rotation" header + Standard / 90° / 180° / 270°.
    case rotation
    /// "Color Profile" header + profiles + More Color Profiles….
    case colorProfile
    /// "Preset" header + Apple display presets.
    case preset
    /// "Input" header + inputs (DDC).
    case input
    /// Mute, Turn Off Display, Disconnect.
    case power

    package static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The submenus of the Displays section (§5.2), in menu order.
package enum DisplaysSectionMenu: Int, CaseIterable, Comparable, Sendable {
    case layouts, virtualDisplays, pictureInPicture, actions

    package static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    package var title: String {
        switch self {
        case .layouts: return L("Saved Layouts")
        case .virtualDisplays: return L("Virtual Displays")
        case .pictureInPicture: return L("Picture in Picture")
        case .actions: return L("Actions")
        }
    }

    /// The 16 pt template symbol every top-level Displays item has (§5.1: all items of a section or none).
    package var symbol: String {
        switch self {
        case .layouts: return "square.stack.3d.up"
        case .virtualDisplays: return "display.2"
        case .pictureInPicture: return "pip"
        case .actions: return "bolt"
        }
    }
}

/// An item's 0.3 home (§4.8 "0.2 menu").
package enum DisplayMenuLocation: Equatable, Sendable {
    /// Top-level `MenuSliderRow` under the device row; never in a submenu.
    case slider
    /// In the display's submenu; `promotable` items move to the top level under the device row when set to Show.
    case submenu(DisplaySubmenuGroup, promotable: Bool)
    /// A top-level item of the Displays section ("Arrange Displays…").
    case sectionItem
    /// Inside one of the Displays section's submenus.
    case sectionMenu(DisplaysSectionMenu)
    /// In Display Tools ›; `toggle` items follow a separator (✓ Sync Brightness, ✓ Night Shift).
    case tools(toggle: Bool)
    /// Under the "Display automation is paused" status row, always while paused.
    case pausedStatus
    /// Not in the 0.3 Displays menu (`ControlRemovals` gives the reason; Awake's rules replace d.sleepPrevention).
    case removed
}

/// The disclosure groups of the Customize Displays Menu sheet that list items (§4.3; the "Displays" group lists
/// displays, not items).
package enum DisplayMenuCustomizeGroup: String, CaseIterable, Sendable {
    case perDisplay, section, tools

    package var title: String {
        switch self {
        case .perDisplay: return L("Per Display")
        case .section: return L("Displays Section")
        case .tools: return L("Display Tools")
        }
    }
}

/// One registered 0.2 menu id and its 0.3 home.
package struct DisplayMenuItemInfo: Equatable, Sendable, Identifiable {
    /// The id, or the family prefix "a.custom." for custom actions.
    package let id: DisplayMenuItemID
    /// The Customize sheet's human title (sentence-free noun phrase, Title Case like the menu item).
    package let title: String
    package let location: DisplayMenuLocation
    /// The feature the item needs; nil = always available while Displays runs.
    package let feature: DisplayFeature?
    /// Header put in front of the item's rows when it is flattened into the display submenu.
    package let header: String?
    /// Top-level symbol when the item is placed at the top level of the Displays section.
    package let symbol: String?
    /// The item's default visibility, equal to its contributor's `DisplayMenuItemDescriptor.defaultVisibility`
    /// (checked against the sources by DisplaysMenuPlanTests): the 0.2 default (§4.8: "Default" is kept) except
    /// where 0.3 places the item differently — Contrast and Resolution sliders are hidden (§4.8 "default Hide"; 0.3
    /// has no slider submenu), custom hardware controls show (0.2 showed them under More ▸), Turn Display On or Off
    /// stays in the display submenu (§5.2; migration M10 promotes it for 0.2 header-switch users), and Disconnect
    /// All But Main is listed in Display Tools (§5.2). Used when no contributor runs (the Customize sheet with
    /// Displays off); a running contributor's descriptor wins.
    package let menuDefault: MenuItemVisibility

    init(_ id: String, _ title: String, _ location: DisplayMenuLocation, feature: DisplayFeature? = nil,
         header: String? = nil, symbol: String? = nil, default menuDefault: MenuItemVisibility? = nil) {
        self.id = DisplayMenuItemID(rawValue: id)
        self.title = title
        self.location = location
        self.feature = feature
        self.header = header
        self.symbol = symbol
        if let menuDefault {
            self.menuDefault = menuDefault
        } else if case .submenu = location {
            self.menuDefault = .inSubmenu
        } else {
            self.menuDefault = .visible
        }
    }

    package var isPerDisplay: Bool {
        switch location {
        case .slider, .submenu: return true
        default: return false
        }
    }

    /// The Customize sheet's control for this item (§4.3; lead r4): per-display items in the display submenu are
    /// three-way (Show / In Display Submenu / Hide), sliders and everything else are checkboxes.
    package var customize: MenuCustomize {
        switch location {
        case .submenu: return .threeWay
        case .slider, .sectionItem, .sectionMenu, .tools, .pausedStatus: return .checkbox
        case .removed: return .none
        }
    }

    /// Whether Show and In Display Submenu put the item in different places (Disconnect, Turn Display On or Off:
    /// Show moves them under the device row). Where they don't, the sheet shows one checkbox instead of a pop-up
    /// with two choices that do the same thing; a stored 0.2 "In submenu" still reads as shown.
    package var offersSubmenuChoice: Bool {
        if case .submenu(_, let promotable) = location { return promotable }
        return false
    }

    package var customizeGroup: DisplayMenuCustomizeGroup? {
        switch location {
        case .slider, .submenu: return .perDisplay
        case .sectionItem, .sectionMenu, .pausedStatus: return .section
        case .tools: return .tools
        case .removed: return nil
        }
    }

    /// Always shown in its place (Resume Display Automation while paused): the sheet shows its checkbox on and
    /// disabled.
    package var isLocked: Bool { location == .pausedStatus }
}

/// Where one item ends up for the current choice.
package enum DisplayMenuPlace: Equatable, Sendable {
    case slider
    /// Top level, right under the device row (Show for Disconnect / Turn Off Display; migration M10).
    case underDevice
    case submenu(DisplaySubmenuGroup)
    case sectionItem
    case sectionMenu(DisplaysSectionMenu)
    case tools(toggle: Bool)
    case pausedStatus
}

package enum DisplaysMenuPlan {
    /// The custom-action family: one id per action, "a.custom.<action id>".
    package static let customActionPrefix = "a.custom."

    /// Every frozen 0.2 menu id (§4.8.1 `l.menu.*`, 46 entries; `a.custom.` stands for the family), in the order the
    /// Customize sheet lists them within their groups and the menu places them within their groups.
    package static let items: [DisplayMenuItemInfo] = [
        // Per display: sliders (top level, Show / Hide).
        DisplayMenuItemInfo("c.brightness.slider", L("Brightness"), .slider, feature: .brightness),
        DisplayMenuItemInfo("c.ddc.volume", L("Volume"), .slider, feature: .ddcControls),
        DisplayMenuItemInfo("c.ddc.contrast", L("Contrast"), .slider, feature: .ddcControls, default: .hidden),
        DisplayMenuItemInfo("c.ddc.custom", L("Custom Hardware Controls"), .slider, feature: .ddcCustom),
        DisplayMenuItemInfo("d.resolutionSlider", L("Resolution Slider"), .slider, feature: .resolution,
                            default: .hidden),
        // Per display: the display submenu, in §5.2 order.
        DisplayMenuItemInfo("d.resolutionMenu", L("Resolutions"), .submenu(.resolution, promotable: false),
                            feature: .resolution),
        DisplayMenuItemInfo("d.setMain", L("Use as Main Display"), .submenu(.arrangement, promotable: false),
                            feature: .mainDisplay),
        DisplayMenuItemInfo("d.mirrorMenu", L("Mirroring"), .submenu(.arrangement, promotable: false),
                            feature: .mirroring),
        DisplayMenuItemInfo("d.hdrToggle", L("High Dynamic Range"), .submenu(.options, promotable: false),
                            feature: .hdrToggle, default: .hidden),
        DisplayMenuItemInfo("c.xdr.toggle", L("Extra Brightness"), .submenu(.options, promotable: false),
                            feature: .xdr),
        DisplayMenuItemInfo("d.smartHiDPI", L("Sharper Text"), .submenu(.options, promotable: false),
                            feature: .smartHiDPI, default: .hidden),
        DisplayMenuItemInfo("c.color.submenu", L("Adjust Colors"), .submenu(.options, promotable: false),
                            feature: .color),
        DisplayMenuItemInfo("c.color.autoBrightness", L("Automatically Adjust Brightness"),
                            .submenu(.options, promotable: false), feature: .autoBrightness),
        DisplayMenuItemInfo("c.menuBarStrip.toggle", L("Black Menu Bar Background"),
                            .submenu(.options, promotable: false), feature: .menuBarOverlays),
        DisplayMenuItemInfo("d.underscanMenu", L("Underscan"), .submenu(.options, promotable: false),
                            feature: .underscan, default: .hidden),
        DisplayMenuItemInfo("e.pip.display", L("Show in Picture in Picture"), .submenu(.options, promotable: false),
                            feature: .pip),
        DisplayMenuItemInfo("d.rotationMenu", L("Rotation"), .submenu(.rotation, promotable: false),
                            feature: .rotation, header: L("Rotation"), default: .hidden),
        DisplayMenuItemInfo("c.color.profiles", L("Color Profile"), .submenu(.colorProfile, promotable: false),
                            feature: .colorProfiles, header: L("Color Profile")),
        DisplayMenuItemInfo("c.color.applePresets", L("Display Preset"), .submenu(.preset, promotable: false),
                            feature: .applePresets, header: L("Preset")),
        DisplayMenuItemInfo("c.ddc.input", L("Input"), .submenu(.input, promotable: false), feature: .ddcInput,
                            header: L("Input")),
        DisplayMenuItemInfo("c.ddc.mute", L("Mute"), .submenu(.power, promotable: false), feature: .ddcControls),
        DisplayMenuItemInfo("c.ddc.power", L("Turn Display On or Off"), .submenu(.power, promotable: true),
                            feature: .ddcPower, symbol: "power"),
        DisplayMenuItemInfo("d.disconnectItem", L("Disconnect"), .submenu(.power, promotable: true),
                            feature: .disconnect, symbol: "eject"),
        // Displays section.
        DisplayMenuItemInfo("b.resumeAutomation", L("Resume Display Automation"), .pausedStatus,
                            symbol: "play.circle"),
        DisplayMenuItemInfo("d.arrange", L("Arrange Displays…"), .sectionItem, feature: .arrangement,
                            symbol: "rectangle.3.group"),
        DisplayMenuItemInfo("d.layoutsMenu", L("Saved Layouts"), .sectionMenu(.layouts), feature: .layouts),
        DisplayMenuItemInfo("d.layoutMatch", L("Apply Matching Layout"), .sectionMenu(.layouts), feature: .layouts),
        DisplayMenuItemInfo("d.protection", L("Protect Arrangement"), .sectionMenu(.layouts), feature: .protection),
        DisplayMenuItemInfo("d.virtualMenu", L("Virtual Displays"), .sectionMenu(.virtualDisplays),
                            feature: .virtualScreens),
        DisplayMenuItemInfo("e.pip.tools", L("Picture in Picture"), .sectionMenu(.pictureInPicture), feature: .pip),
        DisplayMenuItemInfo(customActionPrefix, L("Actions"), .sectionMenu(.actions), feature: .customActions),
        // Display Tools.
        DisplayMenuItemInfo("f.tools.identify", L("Identify Displays"), .tools(toggle: false)),
        DisplayMenuItemInfo("f.tools.redetect", L("Redetect Displays"), .tools(toggle: false)),
        DisplayMenuItemInfo("f.tools.panel", L("Show Displays Panel"), .tools(toggle: false)),
        DisplayMenuItemInfo("d.matchUI", L("Match Text Size…"), .tools(toggle: false), feature: .scaleMatch),
        DisplayMenuItemInfo("d.connectAll", L("Connect All Displays"), .tools(toggle: false), feature: .disconnect),
        DisplayMenuItemInfo("d.disconnectAllButMain", L("Disconnect All But Main"), .tools(toggle: false),
                            feature: .disconnect),
        DisplayMenuItemInfo("b.restoreAll", L("Restore All Displays"), .tools(toggle: false),
                            symbol: "arrow.uturn.backward"),
        DisplayMenuItemInfo("c.sync.toggle", L("Sync Brightness"), .tools(toggle: true), feature: .sync),
        DisplayMenuItemInfo("c.tools.nightShift", L("Night Shift"), .tools(toggle: true), feature: .nightShift),
        // Not in the 0.3 menu (ControlRemovals).
        DisplayMenuItemInfo("c.brightness.method", L("Brightness Method"), .removed),
        DisplayMenuItemInfo("d.powerSwitch", L("Connect Switch"), .removed),
        DisplayMenuItemInfo("d.connectAll.quick", L("Connect All Displays"), .removed),
        DisplayMenuItemInfo("d.sleepPrevention", L("Prevent Display Sleep"), .removed),
        DisplayMenuItemInfo("b.restoreAll.quick", L("Restore All Displays"), .removed),
        DisplayMenuItemInfo("f.quick.redetect", L("Redetect Displays"), .removed),
    ]

    private static let byID: [DisplayMenuItemID: DisplayMenuItemInfo] = {
        var map: [DisplayMenuItemID: DisplayMenuItemInfo] = [:]
        for info in items where map[info.id] == nil { map[info.id] = info }
        return map
    }()

    private static let order: [DisplayMenuItemID: Int] = {
        var map: [DisplayMenuItemID: Int] = [:]
        for (i, info) in items.enumerated() where map[info.id] == nil { map[info.id] = i }
        return map
    }()

    package static func isCustomAction(_ id: DisplayMenuItemID) -> Bool {
        id.rawValue.hasPrefix(customActionPrefix) && id.rawValue.count > customActionPrefix.count
    }

    /// The table entry for an id (a custom action maps to the family entry); nil for an id 0.2 didn't have.
    package static func info(for id: DisplayMenuItemID) -> DisplayMenuItemInfo? {
        if isCustomAction(id) { return byID[DisplayMenuItemID(rawValue: customActionPrefix)] }
        return byID[id]
    }

    /// Sort key within a place: table order; ids 0.2 didn't have go last, in arrival order (stable sort).
    package static func rank(_ id: DisplayMenuItemID) -> Int {
        if isCustomAction(id) { return order[DisplayMenuItemID(rawValue: customActionPrefix)] ?? Int.max }
        return order[id] ?? Int.max
    }

    // MARK: Placement

    /// The default an item's choice is stored against: the running contributor's descriptor (`declared`), else the
    /// table's default, else Show. A slider declared "In submenu" is hidden by default: 0.3 sliders are never in a
    /// submenu (an explicit 0.2 "In submenu" choice still shows it, `MenuConfig.isSliderShown`).
    package static func defaultVisibility(_ id: DisplayMenuItemID, declared: MenuItemVisibility?) -> MenuItemVisibility {
        let entry = Self.info(for: id)
        let value = declared ?? entry?.menuDefault ?? .visible
        if entry?.location == .slider && value == .inSubmenu { return .hidden }
        return value
    }

    /// Where an item goes for the user's choice (§5.2: "Show" places it at its location, "In Display Submenu" keeps
    /// a per-display item in the submenu, "Hide" removes it; sliders are Show or Hide only, and a 0.2 "In submenu"
    /// slider shows at the top level). nil = not in the menu.
    ///
    /// - `perDisplay`: the contributor returned it from `menuItems(for:)` (else from `globalItems`); it decides
    ///   the place of an id 0.2 didn't have.
    /// - `isCustomRow`: the item is an AppKit view row (a slider). A view row is never put in a submenu: it goes to
    ///   the top level under the device row, or (a global one) nowhere.
    /// - `pendingConfirmation`: a display change awaits confirmation; Restore All Displays is then top-level.
    /// - `automationPaused`: Resume Display Automation shows under its status row only while paused.
    package static func place(_ id: DisplayMenuItemID, visibility: MenuItemVisibility, perDisplay: Bool,
                              isCustomRow: Bool, pendingConfirmation: Bool = false,
                              automationPaused: Bool = true) -> DisplayMenuPlace? {
        let location: DisplayMenuLocation
        if let known = Self.info(for: id) {
            location = known.location
        } else {
            location = perDisplay ? (isCustomRow ? .slider : .submenu(.options, promotable: false)) : .tools(toggle: false)
        }
        if id.rawValue == "b.restoreAll" && pendingConfirmation { return .sectionItem }
        let placed: DisplayMenuPlace?
        switch location {
        case .removed:
            placed = nil
        case .pausedStatus:
            placed = automationPaused ? .pausedStatus : nil
        case .slider:
            placed = visibility == .hidden ? nil : .slider
        case .submenu(let group, let promotable):
            switch visibility {
            case .hidden: placed = nil
            case .visible: placed = promotable ? .underDevice : .submenu(group)
            case .inSubmenu: placed = .submenu(group)
            }
        case .sectionItem:
            placed = visibility == .hidden ? nil : .sectionItem
        case .sectionMenu(let menu):
            placed = visibility == .hidden ? nil : .sectionMenu(menu)
        case .tools(let toggle):
            placed = visibility == .hidden ? nil : .tools(toggle: toggle)
        }
        guard isCustomRow, let placed else { return placed }
        switch placed {
        case .slider, .underDevice, .sectionItem, .pausedStatus: return perDisplay ? .slider : placed
        case .submenu: return .slider
        case .sectionMenu, .tools: return perDisplay ? .slider : nil
        }
    }

    /// The Compact style keeps one slider per display (§5.2): brightness, else volume, contrast, a custom control,
    /// resolution, else the first one. Returns the index into `ids` (nil when empty).
    package static func compactSlider(_ ids: [DisplayMenuItemID]) -> Int? {
        let priority = ["c.brightness.slider", "c.ddc.volume", "c.ddc.contrast", "c.ddc.custom", "d.resolutionSlider"]
        for raw in priority {
            if let i = ids.firstIndex(of: DisplayMenuItemID(rawValue: raw)) { return i }
        }
        return ids.isEmpty ? nil : 0
    }

    /// The subtitle of a device row: the badges in order, or nil (Compact style, badges off, or none).
    package static func deviceSubtitle(badges: [String], style: MenuStyle, showBadges: Bool) -> String? {
        guard style == .standard, showBadges, !badges.isEmpty else { return nil }
        return badges.joined(separator: " · ")
    }

    /// With "Header row with one display" off and a single display, its sliders come first and the device row
    /// (which holds the submenu) follows them.
    package static func slidersBeforeDevice(displayCount: Int, headerForSingleDisplay: Bool) -> Bool {
        displayCount == 1 && !headerForSingleDisplay
    }

    // MARK: Customize Displays Menu

    /// The rows of one disclosure group, in table order (custom actions are listed one per action by the sheet).
    package static func customizeRows(_ group: DisplayMenuCustomizeGroup) -> [DisplayMenuItemInfo] {
        items.filter { $0.customizeGroup == group && $0.id.rawValue != customActionPrefix }
    }

    /// Rows matching the sheet's filter: every word of the query is a prefix of a word of the title (case and
    /// diacritics ignored); an empty query matches everything.
    package static func matches(_ title: String, query: String) -> Bool {
        let words = Self.words(query)
        guard !words.isEmpty else { return true }
        let titleWords = Self.words(title)
        return words.allSatisfy { w in titleWords.contains { $0.hasPrefix(w) } }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// Splits rows into those whose feature can be used and those that need a feature that is off (shown as one
    /// dimmed "n items need features that are off" row).
    package static func partition(_ rows: [DisplayMenuItemInfo], featureOn: (DisplayFeature) -> Bool)
        -> (available: [DisplayMenuItemInfo], needFeatures: [DisplayMenuItemInfo]) {
        var available: [DisplayMenuItemInfo] = []
        var off: [DisplayMenuItemInfo] = []
        for row in rows {
            if let feature = row.feature, !featureOn(feature) { off.append(row) } else { available.append(row) }
        }
        return (available, off)
    }

    /// "1 item needs a feature that is off" / "6 items need features that are off".
    package static func needFeaturesTitle(_ count: Int) -> String {
        count == 1 ? L("1 item needs a feature that is off") : L("\(count) items need features that are off")
    }
}

extension MenuConfig {
    /// The Customize sheet's checkbox: shown unless hidden (a 0.2 "In submenu" choice counts as shown).
    package func isShown(_ id: DisplayMenuItemID, default fallback: MenuItemVisibility) -> Bool {
        visibility(of: id, default: fallback) != .hidden
    }

    /// Writes a checkbox: on stores Show (or nothing, when the default already shows it), off stores Hide.
    package mutating func setShown(_ shown: Bool, for id: DisplayMenuItemID, default fallback: MenuItemVisibility) {
        setSliderShown(shown, for: id, default: fallback)
    }
}
