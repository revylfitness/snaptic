import Foundation

/// The Color Profile group of a display submenu (PLAN 0.3 §4.8 `c.color.profiles`): the current profile, the one it
/// replaced and up to three recently used ones, each once, then "More Color Profiles…" (which opens Settings). The
/// whole installed list lives in Settings, so the menu stays short.
package enum ProfileMenuOrder {
    /// At most this many profile rows.
    package static let rowLimit = 5
    /// At most this many remembered recent profiles per display.
    package static let recentLimit = 3

    /// Rows in order: `current`, `previous`, then `recent` (most recent first), skipping repeats and anything
    /// `isAvailable` rejects (an uninstalled profile), at most `rowLimit`.
    package static func rows<T: Hashable>(current: T, previous: T?, recent: [T],
                                          isAvailable: (T) -> Bool = { _ in true }) -> [T] {
        var seen = Set<T>()
        var rows: [T] = []
        for candidate in [current] + (previous.map { [$0] } ?? []) + recent.prefix(recentLimit) {
            guard rows.count < rowLimit, isAvailable(candidate) || candidate == current,
                  seen.insert(candidate).inserted else { continue }
            rows.append(candidate)
        }
        return rows
    }

    /// The recent list after `used` was chosen: it moves to the front, repeats go, at most `recentLimit`.
    package static func remembering<T: Hashable>(_ used: T, in recent: [T]) -> [T] {
        Array(([used] + recent.filter { $0 != used }).prefix(recentLimit))
    }
}
