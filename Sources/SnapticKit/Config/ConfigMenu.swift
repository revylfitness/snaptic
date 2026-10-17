import Foundation

// Displays menu presentation (owner: F). The Menu customization page (A) edits these
// fields; DisplaysMenuBuilder, DisplayMenuBlock and the floating Displays panel read them.

/// The top-level sections of the Displays menu, in the user's order.
package enum DisplaysMenuSection: String, Codable, CaseIterable, Sendable {
    /// One block per display.
    case displays
    /// The Tools section (`MenuSlot.tools` items).
    case tools
}

package struct MenuConfig: ConfigModel {
    /// Longest accepted DisplayMenuItemID raw value (ids are short, e.g. "c.brightness").
    package static let maxItemIDLength = 64
    /// Same bound as remembered displays (DisplaysConfig.maxRememberedDisplays).
    package static let maxDisplays = 64

    /// The user's choice per menu item, keyed by DisplayMenuItemID raw value. Items with
    /// no entry use their descriptor's `defaultVisibility`; an entry equal to the default
    /// is removed, so changing a contributor's default reaches users who never touched it.
    package var items: LossyMap<DisplayMenuItemID, MenuItemVisibility>
    /// Order of the Displays menu sections. Always a permutation of every section.
    package var sectionOrder: [DisplaysMenuSection]
    /// Displays whose block is not shown in the menu or the floating panel.
    package var hiddenDisplays: [DisplayKey]
    /// The user's display order; displays not listed follow in registry order.
    package var displayOrder: [DisplayKey]
    /// Displays whose block is folded into its header row (a submenu).
    package var collapsedDisplays: [DisplayKey]
    /// The main display's block comes first, before `displayOrder`.
    package var mainFirst: Bool
    /// Compact blocks: the "More" items hang off the header row instead of their own row,
    /// and badges are left out.
    package var compact: Bool
    /// Status badges (Main, Virtual, Mirroring…) in block headers.
    package var showBadges: Bool
    /// Show the header row even when only one display is connected.
    package var headerForSingleDisplay: Bool
    /// Scrolling over a menu slider adjusts it (read by MenuSliderItem).
    package var scrollAdjustsSliders: Bool
    /// Global shortcut that opens the floating Displays panel at the pointer (macOS 27:
    /// the status item may sit in the overflow, where it can't be opened).
    package var showPanelShortcut: HotkeyCombo?
    /// Global shortcut that shows the Identify labels on every display.
    package var identifyShortcut: HotkeyCombo?

    package init() {
        items = LossyMap()
        sectionOrder = DisplaysMenuSection.allCases
        hiddenDisplays = []
        displayOrder = []
        collapsedDisplays = []
        mainFirst = true
        compact = false
        showBadges = true
        headerForSingleDisplay = true
        scrollAdjustsSliders = true
        showPanelShortcut = nil
        identifyShortcut = nil
    }

    private enum CodingKeys: String, CodingKey {
        case items, sectionOrder, hiddenDisplays, displayOrder, collapsedDisplays, mainFirst, compact, showBadges,
             headerForSingleDisplay, scrollAdjustsSliders, showPanelShortcut, identifyShortcut
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuConfig()
        items = c.lossy(.items, d.items)
        sectionOrder = Self.decodeSections(c)
        hiddenDisplays = Self.decodeKeys(c, .hiddenDisplays)
        displayOrder = Self.decodeKeys(c, .displayOrder)
        collapsedDisplays = Self.decodeKeys(c, .collapsedDisplays)
        mainFirst = c.lossy(.mainFirst, d.mainFirst)
        compact = c.lossy(.compact, d.compact)
        showBadges = c.lossy(.showBadges, d.showBadges)
        headerForSingleDisplay = c.lossy(.headerForSingleDisplay, d.headerForSingleDisplay)
        scrollAdjustsSliders = c.lossy(.scrollAdjustsSliders, d.scrollAdjustsSliders)
        showPanelShortcut = Self.decodeCombo(c, .showPanelShortcut)
        identifyShortcut = Self.decodeCombo(c, .identifyShortcut)
    }

    /// Entry by entry: unknown section names and bad display keys are skipped, not fatal.
    private static func decodeSections(_ c: KeyedDecodingContainer<CodingKeys>) -> [DisplaysMenuSection] {
        let raw: [String] = c.lossy(.sectionOrder, DisplaysMenuSection.allCases.map(\.rawValue))
        return raw.compactMap { DisplaysMenuSection(rawValue: $0) }
    }

    private static func decodeKeys(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [DisplayKey] {
        let raw: [String] = c.lossy(key, [])
        return raw.compactMap { DisplayKey(rawValue: $0) }
    }

    private static func decodeCombo(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> HotkeyCombo? {
        if let combo = try? c.decodeIfPresent(HotkeyCombo.self, forKey: key) { return combo }
        return nil
    }

    package func sanitized() -> MenuConfig {
        var c = self
        var kept: [DisplayMenuItemID: MenuItemVisibility] = [:]
        for (id, visibility) in items.values where Self.isValidItemID(id) { kept[id] = visibility }
        var map = LossyMap<DisplayMenuItemID, MenuItemVisibility>(kept)
        map.dropUnknown(keepingAtMost: 0)
        c.items = map
        c.sectionOrder = Self.normalizedSections(sectionOrder)
        c.hiddenDisplays = Self.unique(hiddenDisplays)
        c.displayOrder = Self.unique(displayOrder)
        c.collapsedDisplays = Self.unique(collapsedDisplays)
        c.showPanelShortcut = showPanelShortcut.flatMap(Self.sanitizedCombo)
        c.identifyShortcut = identifyShortcut.flatMap(Self.sanitizedCombo)
        if c.showPanelShortcut != nil, c.showPanelShortcut == c.identifyShortcut { c.identifyShortcut = nil }
        return c
    }

    // MARK: Item visibility

    /// Ids are short, printable and dot-separated ("c.brightness"); anything else was not
    /// written by Snaptic and is dropped.
    package static func isValidItemID(_ id: DisplayMenuItemID) -> Bool {
        let s = id.rawValue
        guard !s.isEmpty, s.utf8.count <= maxItemIDLength else { return false }
        return s.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
            default: return false
            }
        }
    }

    package func visibility(of id: DisplayMenuItemID, default fallback: MenuItemVisibility) -> MenuItemVisibility {
        items[id] ?? fallback
    }

    package func hasOverride(_ id: DisplayMenuItemID) -> Bool { items[id] != nil }

    /// Stores a choice; a choice equal to the default removes the override.
    package mutating func setVisibility(_ visibility: MenuItemVisibility, for id: DisplayMenuItemID,
                                        default fallback: MenuItemVisibility) {
        guard Self.isValidItemID(id) else { return }
        items[id] = visibility == fallback ? nil : visibility
    }

    /// "Reset Menu Layout": every item back to its default, sections and order too.
    package mutating func resetLayout() {
        let d = MenuConfig()
        items = d.items
        sectionOrder = d.sectionOrder
        displayOrder = d.displayOrder
        hiddenDisplays = d.hiddenDisplays
        collapsedDisplays = d.collapsedDisplays
    }

    /// Splits items into first-level and "More" (submenu) lists, dropping hidden ones.
    /// Input order is kept within each list.
    package func partition<T>(_ entries: [(id: DisplayMenuItemID, item: T)],
                              defaults: (DisplayMenuItemID) -> MenuItemVisibility) -> (visible: [T], more: [T]) {
        var visible: [T] = []
        var more: [T] = []
        for entry in entries {
            switch visibility(of: entry.id, default: defaults(entry.id)) {
            case .visible: visible.append(entry.item)
            case .inSubmenu: more.append(entry.item)
            case .hidden: break
            }
        }
        return (visible, more)
    }

    // MARK: Sections

    /// `sectionOrder` as a full permutation (missing sections appended, duplicates dropped).
    package var orderedSections: [DisplaysMenuSection] { Self.normalizedSections(sectionOrder) }

    package mutating func moveSection(_ section: DisplaysMenuSection, by offset: Int) {
        var order = orderedSections
        guard let i = order.firstIndex(of: section) else { return }
        let j = min(max(i + offset, 0), order.count - 1)
        order.remove(at: i)
        order.insert(section, at: j)
        sectionOrder = order
    }

    private static func normalizedSections(_ sections: [DisplaysMenuSection]) -> [DisplaysMenuSection] {
        var seen: Set<DisplaysMenuSection> = []
        var result = sections.filter { seen.insert($0).inserted }
        result += DisplaysMenuSection.allCases.filter { !seen.contains($0) }
        return result
    }

    // MARK: Displays

    package func isHidden(_ key: DisplayKey) -> Bool { hiddenDisplays.contains(key) }

    package mutating func setHidden(_ hidden: Bool, for key: DisplayKey) {
        hiddenDisplays.removeAll { $0 == key }
        if hidden { hiddenDisplays.append(key) }
        hiddenDisplays = Self.unique(hiddenDisplays)
    }

    package func isCollapsed(_ key: DisplayKey) -> Bool { collapsedDisplays.contains(key) }

    package mutating func setCollapsed(_ collapsed: Bool, for key: DisplayKey) {
        collapsedDisplays.removeAll { $0 == key }
        if collapsed { collapsedDisplays.append(key) }
        collapsedDisplays = Self.unique(collapsedDisplays)
    }

    /// Displays in menu order: main first (if `mainFirst`), then the user's order, then
    /// the rest in the given (registry) order. Duplicates are dropped; hidden displays are
    /// dropped unless `includeHidden`.
    package func orderedDisplays(_ keys: [DisplayKey], main: DisplayKey?, includeHidden: Bool = false) -> [DisplayKey] {
        var seen: Set<DisplayKey> = []
        let unique = keys.filter { seen.insert($0).inserted }
        var rank: [DisplayKey: Int] = [:]
        for (i, key) in displayOrder.enumerated() where rank[key] == nil { rank[key] = i }
        let hidden = Set(hiddenDisplays)
        let ordered = unique.enumerated().sorted { a, b in
            let mainA = mainFirst && a.element == main ? 0 : 1
            let mainB = mainFirst && b.element == main ? 0 : 1
            if mainA != mainB { return mainA < mainB }
            let rankA = rank[a.element] ?? Int.max
            let rankB = rank[b.element] ?? Int.max
            if rankA != rankB { return rankA < rankB }
            return a.offset < b.offset
        }.map(\.element)
        return includeHidden ? ordered : ordered.filter { !hidden.contains($0) }
    }

    /// Moves `key` by `offset` places within `current` (the order as shown) and stores the
    /// result. Remembered displays that aren't in `current` keep their place after it.
    package mutating func move(_ key: DisplayKey, by offset: Int, in current: [DisplayKey]) {
        var order = current
        guard let i = order.firstIndex(of: key), offset != 0 else { return }
        let j = min(max(i + offset, 0), order.count - 1)
        order.remove(at: i)
        order.insert(key, at: j)
        let shown = Set(order)
        displayOrder = Self.unique(order + displayOrder.filter { !shown.contains($0) })
    }

    /// Drops every per-display choice for a forgotten display.
    package mutating func forget(_ key: DisplayKey) {
        hiddenDisplays.removeAll { $0 == key }
        displayOrder.removeAll { $0 == key }
        collapsedDisplays.removeAll { $0 == key }
    }

    /// Order-preserving dedupe, capped at `maxDisplays`.
    private static func unique(_ keys: [DisplayKey]) -> [DisplayKey] {
        var seen: Set<DisplayKey> = []
        return Array(keys.filter { seen.insert($0).inserted }.prefix(maxDisplays))
    }

    // MARK: Shortcuts

    /// Carbon modifier bits: ⌘ 0x100, ⇧ 0x200, ⌥ 0x800, ⌃ 0x1000.
    package static let carbonModifierMask: UInt32 = 0x0100 | 0x0200 | 0x0800 | 0x1000
    private static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// A shortcut the menu could have recorded: a real key (not a modifier), with ⌘ or ⌃
    /// unless it is an F-key. Anything else (hand-edited settings) is dropped.
    package static func sanitizedCombo(_ combo: HotkeyCombo) -> HotkeyCombo? {
        guard combo.keyCode < 128, !(54...63).contains(combo.keyCode) else { return nil }
        let mods = combo.carbonModifiers & carbonModifierMask
        if !functionKeyCodes.contains(combo.keyCode), mods & (0x0100 | 0x1000) == 0 { return nil }
        return HotkeyCombo(keyCode: combo.keyCode, carbonModifiers: mods)
    }
}
