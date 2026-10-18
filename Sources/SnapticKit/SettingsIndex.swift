import Foundation

// Settings search (H; PLAN 0.3 §4.1, §4.2, R5-13). Kit so the ranking, the folding table and anchor uniqueness are
// tested on Linux. Entries are derived from the control specs' `search` (no per-module index tables), so no entry
// text ever comes from the user's config.

/// "displays.color".
package struct SettingsRoute: Hashable, Sendable {
    package let id: String
    package init(_ id: String) { self.id = id }
}

package struct SettingsSearchEntry: Hashable, Sendable {
    /// `id == anchor ==` the row's `ControlID.rawValue`.
    package let id: String
    package let title: String
    package let keywords: [String]
    /// Sidebar item id.
    package let root: String
    /// Sub-page, nil = root page.
    package let route: SettingsRoute?
    package let anchor: String
    /// Advanced/other sheet id to open first.
    package let sheet: String?

    package init(id: String, title: String, keywords: [String] = [], root: String, route: SettingsRoute? = nil,
                 anchor: String, sheet: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.root = root
        self.route = route
        self.anchor = anchor
        self.sheet = sheet
    }
}

extension SettingsSearchEntry {
    /// id == anchor == spec.id.rawValue (R5-13).
    package init(_ spec: ControlSpec, search: SearchSpec) {
        self.init(id: spec.id.rawValue, title: search.title, keywords: search.keywords, root: search.root,
                  route: search.route, anchor: spec.id.rawValue, sheet: search.sheet)
    }
}

package enum SettingsIndex {
    /// Every searchable spec of `tables` whose search entry belongs to `root`, in table order. A repeated id keeps
    /// its first entry (the registry test rejects duplicates; search never traps on one).
    package static func entries(_ tables: [any ControlTable.Type], root: String) -> [SettingsSearchEntry] {
        var seen = Set<String>()
        var result: [SettingsSearchEntry] = []
        for table in tables {
            for spec in table.controls {
                guard let search = spec.search, search.root == root else { continue }
                guard seen.insert(spec.id.rawValue).inserted else { continue }
                result.append(SettingsSearchEntry(spec, search: search))
            }
        }
        return result
    }

    /// The whole Settings index: every root's entries in sidebar order (`roots`), each id once. Entries whose root
    /// has no sidebar item are left out (nothing could reveal them).
    package static func all(_ tables: [any ControlTable.Type], roots: [String] = SettingsRootID.all) -> [SettingsSearchEntry] {
        var seen = Set<String>()
        var result: [SettingsSearchEntry] = []
        for root in roots {
            for entry in entries(tables, root: root) where seen.insert(entry.id).inserted {
                result.append(entry)
            }
        }
        return result
    }

    /// The spec with `id`, first match.
    package static func spec(_ id: String, in tables: [any ControlTable.Type]) -> ControlSpec? {
        for table in tables {
            if let spec = table.controls.first(where: { $0.id.rawValue == id }) { return spec }
        }
        return nil
    }

    /// The page header switch of a module root ("Use Window Switcher"): its searchable setting that edits
    /// `modules.*.enabled` on the root page itself. A reveal into a module that is off highlights it.
    package static func masterSwitch(root: String, in tables: [any ControlTable.Type]) -> String? {
        for table in tables {
            for spec in table.controls where spec.kind == .setting && spec.keys.contains("modules.*.enabled") {
                guard let search = spec.search, search.root == root, search.route == nil, search.sheet == nil else {
                    continue
                }
                return spec.id.rawValue
            }
        }
        return nil
    }

    /// Where a reveal goes when its row isn't shown (a subordinate row whose parent is off): the `parentOn` chain,
    /// nearest first, at most 8 deep, never repeating.
    package static func revealFallbacks(for id: String, in tables: [any ControlTable.Type]) -> [String] {
        var result: [String] = []
        var current = id
        while result.count < 8, let spec = spec(current, in: tables) {
            var next: String?
            for case .parentOn(let parent) in spec.when {
                next = parent.rawValue
                break
            }
            guard let parent = next, parent != id, !result.contains(parent) else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    /// Names of sub-pages and sheets for the result rows ("Thumbnail size — Window Switcher › Advanced"). Route ids
    /// are the owners' table surfaces (F's `DisplaysSubpage`).
    package static let pageTitles: [String: String] = [
        "displays.brightness": L("Brightness and Dimming"),
        "displays.color": L("Color"),
        "displays.hardware": L("Hardware Controls"),
        "displays.keyboard": L("Keyboard"),
        "displays.layouts": L("Saved Layouts"),
        "displays.virtual": L("Virtual Displays"),
        "displays.pip": L("Picture in Picture"),
        "displays.automations": L("Automations"),
        "displays.info": L("Display Information"),
        "awake.drives": L("Drives"),
        "awake.history": L("History"),
        "switcher.shortcuts": L("More Shortcuts"),
        "displays.details": L("Display Details"),
        "displays.arrange": L("Arrange Displays"),
        "menubar.customize": L("Customize Displays Menu"),
        "awake.sessions": L("Sessions"),
    ]

    /// A route's or sheet's title: the table, then "….advanced" → Advanced, "….shortcuts" → Keyboard Shortcuts.
    package static func pageTitle(_ id: String) -> String? {
        if let title = pageTitles[id] { return title }
        if id.hasSuffix(".advanced") { return L("Advanced") }
        if id.hasSuffix(".shortcuts") { return L("Keyboard Shortcuts") }
        return nil
    }

    /// "Window Switcher › Advanced", "Displays › Color › Advanced": the root's title, then the route's and the
    /// sheet's when they have one.
    package static func location(of entry: SettingsSearchEntry, rootTitle: String,
                                 routeTitle: String? = nil) -> String {
        var parts = [rootTitle]
        if let route = entry.route, let title = routeTitle ?? pageTitle(route.id) { parts.append(title) }
        if let sheet = entry.sheet, let title = pageTitle(sheet) { parts.append(title) }
        return parts.joined(separator: " › ")
    }
}

/// "Every visible control is findable" (PLAN 0.3 step-3 exit), as data: which control specs must carry a search
/// entry, and the few that deliberately don't. `SettingsIndexTests` checks the whole registry against it.
package enum SettingsIndexCoverage {
    /// Surfaces that aren't Settings pages: the menus, the floating panel, onboarding and the Custom session panel.
    package static let otherSurfaces: [String] = ["menu", "onboarding", "displays.panel", "awake.custom"]

    /// Editors of one list item (a rule, a preset, a hook, …): search can't know which item to open, so their rows
    /// are reached through the list on the page.
    package static let itemEditorSurfaces: Set<String> = [
        "awake.rule", "awake.sessions", "displays.virtual.editor", "displays.pip.editor", "displays.automations.hook",
        "displays.automations.action",
    ]

    /// Visible controls without a search entry, each with its reason.
    package static let unsearchable: [String: String] = [
        "about.page.displayInformation": "Opens Displays › Display Information, which has its own entry.",
        "displays.advanced.confirm.useDefaultShortcut": "Part of the Restore All Displays shortcut row, which has an entry.",
        "menubar.customize.needFeatures": "Groups dimmed items that each have their own entry.",
    ]

    /// Controls whose owners add a search entry in step 3 (lead: empty this list at the step-3 exit).
    package static let awaitingSearch: Set<String> = [
        "menubar.page.customize", "menubar.page.restoreDefaults", "menubar.customize.displays",
        "menubar.customize.useDefaultOrder",
    ]

    package static func isSettingsSurface(_ surface: String) -> Bool {
        !otherSurfaces.contains { surface == $0 || surface.hasPrefix($0 + ".") } && !itemEditorSurfaces.contains(surface)
    }

    /// A control on a Settings surface needs an entry when it is a setting, shortcut or navigation row, or a button
    /// or list that isn't one list item's row action. Status-row actions (shown only while a state holds) and
    /// controls repeated per list item (other than per display: those show for the selected display) don't.
    package static func requiresSearch(_ spec: ControlSpec, surface: String) -> Bool {
        guard isSettingsSurface(surface) else { return false }
        var perItem: String?
        for case .perItem(let item) in spec.when { perItem = item }
        if let perItem, perItem != "display" { return false }
        switch spec.kind {
        case .setting, .shortcut, .navigation:
            return true
        case .button, .list:
            return perItem == nil
        case .statusAction, .menuItem, .menuSlider, .menuSubmenu, .menuSwitchHeader:
            return false
        }
    }

    /// "Table: id" for every control that needs a search entry and has none (nor an exclusion).
    package static func missing(_ tables: [any ControlTable.Type]) -> [String] {
        var result: [String] = []
        for table in tables {
            for spec in table.controls where spec.search == nil && requiresSearch(spec, surface: table.surface) {
                let id = spec.id.rawValue
                if unsearchable[id] == nil && !awaitingSearch.contains(id) {
                    result.append(String(describing: table) + ": " + id)
                }
            }
        }
        return result
    }
}

package enum SettingsSearch {
    /// Longest query looked at, in characters, and most words.
    package static let maxQueryLength = 64
    package static let maxQueryWords = 8

    /// Equivalent terms (§4.1). A query that matches one phrase of a group also finds entries that match another
    /// phrase of it, in their title, keywords or page (so "caffeinate" lists Awake's settings).
    package static let synonyms: [[String]] = [
        ["ddc", "monitor", "hardware"],
        ["awake", "keep awake", "caffeinate", "insomnia", "amphetamine", "sleep", "prevent sleep", "lid", "clamshell",
         "jiggle", "screen saver"],
        ["window switcher", "alt-tab", "alttab", "⌥⇥"],
        ["pip", "picture in picture"],
        ["osd", "brightness indicator"],
        ["hidpi", "sharper text"],
        ["xdr", "extra brightness"],
        ["shortcut", "keyboard shortcut", "hotkey", "key combination"],
        ["open at login", "launch at login", "start at login", "login items", "startup"],
        ["reset", "restore defaults"],
        ["volume", "sound", "audio"],
        ["hdr", "high dynamic range"],
        ["cli", "command line", "terminal"],
    ]

    /// Ranked matches (prefix of a word, case- and diacritic-insensitive): title words first, then title and
    /// keywords, then synonyms in title and keywords, then synonyms naming the page. Inside a tier: titles that
    /// start with the first query word, then shorter titles, then input order. Empty query: nothing.
    package static func rank(entries: [SettingsSearchEntry], query: String) -> [SettingsSearchEntry] {
        let q = Array(words(String(query.prefix(maxQueryLength))).prefix(maxQueryWords))
        guard !q.isEmpty else { return [] }
        let alternatives = synonymPhrases(for: q)

        var scored: [(tier: Int, startsWith: Bool, length: Int, index: Int, entry: SettingsSearchEntry)] = []
        var seen = Set<String>()
        for (index, entry) in entries.enumerated() where !seen.contains(entry.id) {
            let title = words(entry.title)
            let keywords = entry.keywords.flatMap { words($0) }
            let tier: Int
            if allPrefix(q, of: title) {
                tier = 0
            } else if allPrefix(q, of: title + keywords) {
                tier = 1
            } else if alternatives.contains(where: { allPrefix($0, of: title + keywords) }) {
                tier = 2
            } else if alternatives.contains(where: { allPrefix($0, of: rootWords(entry.root)) }) {
                tier = 3
            } else {
                continue
            }
            seen.insert(entry.id)
            let startsWith = title.first.map { $0.hasPrefix(q[0]) } ?? false
            scored.append((tier, startsWith, title.count, index, entry))
        }
        scored.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.startsWith != $1.startsWith { return $0.startsWith }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.index < $1.index
        }
        return scored.map(\.entry)
    }

    // MARK: Folding and words

    /// Lowercase, without diacritics (hand-written table for ASCII, Latin-1 and Latin Extended-A; combining marks
    /// dropped; other scripts lowercased as they are).
    package static func fold(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for u in text.unicodeScalars {
            let v = u.value
            if v >= 0x41 && v <= 0x5A {
                out.append(Unicode.Scalar(v + 32) ?? u)
            } else if v < 0x80 {
                out.append(u)
            } else if v >= 0x300 && v <= 0x36F {
                continue
            } else if v >= 0xC0 && v <= 0xFF {
                let i = Int(v - 0xC0)
                out.append(contentsOf: (i < latin1.count ? latin1[i] : "").unicodeScalars)
            } else if v >= 0x100 && v <= 0x17F {
                let i = Int(v - 0x100)
                out.append(contentsOf: (i < latinExtendedA.count ? latinExtendedA[i] : "").unicodeScalars)
            } else {
                out.append(contentsOf: String(u).lowercased().unicodeScalars)
            }
        }
        return String(out)
    }

    /// Folded words: letters, digits and symbols such as ⌥ and ⇥; whitespace, punctuation and math symbols
    /// separate words.
    package static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for u in fold(text).unicodeScalars {
            if isWordScalar(u) {
                current.append(u)
            } else if !current.isEmpty {
                result.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }

    /// "windowSwitcher" → ["window", "switcher"].
    package static func rootWords(_ id: String) -> [String] {
        var spaced = ""
        for ch in id {
            if ch.isUppercase && !spaced.isEmpty { spaced.append(" ") }
            spaced.append(ch)
        }
        return words(spaced)
    }

    private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        if v < 0x80 {
            return (v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x7A) || (v >= 0x41 && v <= 0x5A)
        }
        if u.properties.isWhitespace { return false }
        switch u.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .mathSymbol, .spaceSeparator, .lineSeparator, .paragraphSeparator,
             .control, .format:
            return false
        default:
            return true
        }
    }

    /// Every query word is the prefix of some word.
    private static func allPrefix(_ query: [String], of words: [String]) -> Bool {
        !query.isEmpty && query.allSatisfy { q in words.contains { $0.hasPrefix(q) } }
    }

    /// The phrases (as words) of every synonym group one of whose phrases the query matches: the query's words are
    /// prefixes of the phrase's leading words, in order. Queries shorter than 3 characters only match a phrase
    /// exactly.
    private static func synonymPhrases(for q: [String]) -> [[String]] {
        let length = q.reduce(0) { $0 + $1.count }
        var result: [[String]] = []
        for group in synonyms {
            let phrases = group.map { words($0) }.filter { !$0.isEmpty }
            let hit = phrases.contains { phrase in
                guard q.count <= phrase.count else { return false }
                if length < 3 { return phrase == q }
                return zip(q, phrase).allSatisfy { $1.hasPrefix($0) }
            }
            if hit { result.append(contentsOf: phrases) }
        }
        return result
    }

    // MARK: Tables

    /// U+00C0…U+00FF.
    private static let latin1: [String] = expand([
        (6, "a"), (1, "ae"), (1, "c"), (4, "e"), (4, "i"), (1, "d"), (1, "n"), (5, "o"), (1, " "), (1, "o"),
        (4, "u"), (1, "y"), (1, "th"), (1, "ss"),
        (6, "a"), (1, "ae"), (1, "c"), (4, "e"), (4, "i"), (1, "d"), (1, "n"), (5, "o"), (1, " "), (1, "o"),
        (4, "u"), (1, "y"), (1, "th"), (1, "y"),
    ])

    /// U+0100…U+017F.
    private static let latinExtendedA: [String] = expand([
        (6, "a"), (8, "c"), (4, "d"), (10, "e"), (8, "g"), (4, "h"), (10, "i"), (2, "ij"), (2, "j"), (3, "k"),
        (10, "l"), (9, "n"), (6, "o"), (2, "oe"), (6, "r"), (8, "s"), (6, "t"), (12, "u"), (2, "w"), (3, "y"),
        (6, "z"), (1, "s"),
    ])

    private static func expand(_ runs: [(Int, String)]) -> [String] {
        runs.flatMap { Array(repeating: $0.1, count: $0.0) }
    }

    /// Table sizes (tests).
    package static var foldTableSizes: (latin1: Int, latinExtendedA: Int) { (latin1.count, latinExtendedA.count) }
}
