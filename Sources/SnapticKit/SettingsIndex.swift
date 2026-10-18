import Foundation

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S). Kit so search ranking
// and anchor uniqueness are tested on Linux. Entries are derived from the control specs' `search` (R5-13).

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
    /// Every searchable spec of `tables` under `root`. Stub: none.
    package static func entries(_ tables: [any ControlTable.Type], root: String) -> [SettingsSearchEntry] { [] }
}

package enum SettingsSearch {
    /// Prefix-of-word match on title > keywords > synonyms, hand-written folding. Stub: nothing found.
    package static func rank(entries: [SettingsSearchEntry], query: String) -> [SettingsSearchEntry] { [] }
}
