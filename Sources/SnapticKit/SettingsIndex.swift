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
